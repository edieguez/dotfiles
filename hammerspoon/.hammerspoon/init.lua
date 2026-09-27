-- init.lua — Windows-style window focus for macOS (Hammerspoon)
--
-- Behaviour (mirrors Windows):
--   * One global focus history (MRU z-order) across ALL apps, not per app.
--   * When the ACTIVE window closes, minimizes or its app hides/quits, focus goes
--     to the most recently used remaining window, whatever app owns it.
--   * Closing a dialog prefers a window of the same app (its likely owner).
--   * Only eligible windows: standard windows/dialogs that are visible, not
--     minimized, not hidden, and on a currently visible Space (any monitor).
--   * Minimized windows drop to the bottom of the history.
--   * Nothing eligible left -> the "desktop" (Finder active, no window).
--   * Closing a BACKGROUND window never moves focus.
--   * If focus already went to a different app on purpose (e.g. a link opened
--     the browser), it is left alone.

hs.application.enableSpotlightForNameSearches(true)
local spaces = require("hs.spaces")
hs.window.animationDuration = 0
-- Don't let one unresponsive app stall Hammerspoon's accessibility calls.
if type(hs.window.timeout) == "function" then hs.window.timeout(0.5) end
if hs.window.filter.setLogLevel then hs.window.filter.setLogLevel("error") end

-- Global anchor: keeps timers, watchers and the event tap from being GC'd.
FocusManager = {}
local FM = FocusManager

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local ALLOWED_SUBROLES = { AXStandardWindow = true, AXDialog = true }

-- While one of these is frontmost, never move focus.
local IGNORED_APPS = {
    Spotlight = true, loginwindow = true, ScreenSaverEngine = true,
    NotificationCenter = true, ControlCenter = true, SystemUIServer = true,
    Dock = true, Raycast = true, Alfred = true,
}

local PROMOTE_DELAY   = 0.15 -- a focus change must hold this long to enter history
local REFOCUS_DELAY   = 0.10 -- let the window server finish tearing the window down
local VERIFY_DELAY    = 0.20 -- re-check that our focus stuck (some apps fight back)
local KEY_CHECK_DELAY = 0.35 -- fallback check after Cmd-W / Cmd-M
local POLL_INTERVAL   = 0.5  -- last-resort check for apps that emit no events
local QUIT_WINDOW     = 5    -- seconds a Cmd-Q stays "fresh"
-- Closing a fullscreen window tears down its Space; the desktop behind it
-- only becomes visible after the animation, so wait and retry before
-- concluding that nothing is left.
local FULLSCREEN_DELAY = 0.5  -- first attempt after a fullscreen window closes
local SETTLE_STEP      = 0.25 -- then retry this often...
local SETTLE_RETRIES   = 6    -- ...this many times before falling back to Finder
local MRU_LIMIT       = 200

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local now       = hs.timer.secondsSinceEpoch
local mru       = {}  -- committed focus history: window ids, most recent first
local meta      = {}  -- id -> { pid, subrole }, recorded when we see a window focused
local gone      = {}  -- destroyed ids (CGWindowIDs are not reused within a session)
local handledAt = {}  -- id -> time its disappearance was handled
local pendingId = nil -- focused, but not yet committed to history
local lastReal  = nil -- { id, pid } last eligible window seen focused
local lastClose = nil -- { ctx, at } most recent refocus context
local quitCtx   = nil -- { pid, at, snapshot, closedId } set by Cmd-Q

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function safe(f, ...)
    local ok, r = pcall(f, ...)
    if ok then return r end
    return nil
end

local function indexOf(t, v)
    for i, x in ipairs(t) do if x == v then return i end end
    return nil
end

local function mruRemove(id)
    local i = indexOf(mru, id)
    if i then table.remove(mru, i) end
end

local function mruPromote(id)
    mruRemove(id)
    table.insert(mru, 1, id)
    if #mru > MRU_LIMIT then table.remove(mru) end
end

local function mruDemote(id)
    mruRemove(id)
    table.insert(mru, id)
end

local function copy(t) return table.move(t, 1, #t, 1, {}) end

-- Returns id, pid, subrole (or nil) without ever throwing.
local function describe(win)
    if not win then return nil end
    local id = safe(win.id, win)
    if not id or id == 0 then return nil end
    local app = safe(win.application, win)
    local pid = app and safe(app.pid, app)
    return id, pid, safe(win.subrole, win)
end

local function isIgnoredApp(app)
    local name = app and safe(app.name, app)
    return name ~= nil and IGNORED_APPS[name] == true
end

-- Looks a window up inside its own app only (cheap, and reliable for apps
-- whose destroy notifications never arrive).
local function findWindow(pid, id)
    if not pid or not id then return nil end
    local app = hs.application.applicationForPID(pid)
    if not app then return nil end
    for _, w in ipairs(safe(app.allWindows, app) or {}) do
        if safe(w.id, w) == id then return w end
    end
    return nil
end

local function cancelPending()
    if FM.promoteTimer then FM.promoteTimer:stop() end
    FM.promoteTimer = nil
    pendingId = nil
end

-- Captures everything needed to pick the next window, at the moment the
-- active window goes away (before macOS's own same-app refocus pollutes it).
local function makeCtx(id, force)
    local m = meta[id] or {}
    local ctx = {
        closedId = id, closedPid = m.pid, closedSubrole = m.subrole,
        closedFullscreen = m.fullscreen == true,
        snapshot = copy(mru), force = force,
    }
    if quitCtx and m.pid == quitCtx.pid and now() - quitCtx.at < QUIT_WINDOW then
        ctx.force, ctx.excludePid = true, m.pid -- app is quitting: skip its windows
    end
    return ctx
end

---------------------------------------------------------------------------
-- Choosing and focusing the next window
---------------------------------------------------------------------------
local function candidateOk(w, ctx)
    local id, pid, subrole = describe(w)
    if not id or id == ctx.closedId or gone[id] then return false end
    if ctx.excludePid and pid == ctx.excludePid then return false end
    if not ALLOWED_SUBROLES[subrole] then return false end
    if isIgnoredApp(safe(w.application, w)) then return false end
    return true, pid
end

-- Returns the Space id if this window is fullscreen on its own Space.
local function fullscreenSpaceOf(id)
    for _, sp in ipairs(safe(spaces.windowSpaces, id) or {}) do
        if safe(spaces.spaceType, sp) == "fullscreen" then return sp end
    end
    return nil
end

-- A fullscreen window on another Space still counts as a candidate, like a
-- fullscreen window would on Windows (which has no separate Spaces for it).
local function offscreenFullscreen(id)
    local m = meta[id]
    if not m or not m.fullscreen or not m.win or gone[id] then return nil end
    if fullscreenSpaceOf(id) then return m.win end
    return nil
end

-- True while we're still looking at the closed window's (now empty)
-- fullscreen Space, i.e. macOS hasn't finished animating away from it.
local function onEmptyFullscreenSpace()
    local sp = safe(spaces.focusedSpace)
    if not sp or safe(spaces.spaceType, sp) ~= "fullscreen" then return false end
    for _, wid in ipairs(safe(spaces.windowsForSpace, sp) or {}) do
        if meta[wid] and not gone[wid] then return false end
    end
    return true
end

local function pickTarget(ctx)
    -- On-screen windows only: visible, not minimized, not hidden, on the
    -- Spaces currently shown on each monitor. Front-to-back order.
    local onScreen = safe(hs.window.orderedWindows) or {}
    local byId = {}
    for _, w in ipairs(onScreen) do
        local id = safe(w.id, w)
        if id then byId[id] = w end
    end

    -- Focus history first, then real z-order for windows never focused.
    local ordered, seen = {}, {}
    local function add(w)
        local id = safe(w.id, w)
        if id and not seen[id] then seen[id] = true; ordered[#ordered + 1] = w end
    end
    for _, id in ipairs(ctx.snapshot) do
        local w = byId[id] or offscreenFullscreen(id)
        if w then add(w) end
    end
    for _, w in ipairs(onScreen) do add(w) end

    -- Closing a dialog returns to a window of the same app when possible.
    local closingDialog = ctx.closedSubrole ~= nil and ctx.closedSubrole ~= "AXStandardWindow"
    local fallback
    for _, w in ipairs(ordered) do
        local ok, pid = candidateOk(w, ctx)
        if ok then
            if not closingDialog or pid == ctx.closedPid then return w end
            fallback = fallback or w
        end
    end
    return fallback
end

local function focusWindow(w)
    local id = safe(w.id, w)
    -- Focusing a window on another fullscreen Space normally switches to it;
    -- give that animation time before checking.
    local fsSpace = fullscreenSpaceOf(id)
    local switching = fsSpace ~= nil and fsSpace ~= safe(spaces.focusedSpace)
    safe(w.focus, w)
    if FM.verifyTimer then FM.verifyTimer:stop() end
    FM.verifyTimer = hs.timer.doAfter(switching and 0.8 or VERIFY_DELAY, function()
        FM.verifyTimer = nil
        local fw = hs.window.focusedWindow()
        if fw and safe(fw.id, fw) == id then return end
        if switching then
            -- The app didn't take us there: switch Spaces explicitly, then focus.
            safe(spaces.gotoSpace, fsSpace)
            FM.verifyTimer = hs.timer.doAfter(0.8, function()
                FM.verifyTimer = nil
                safe(w.focus, w)
            end)
        else
            safe(w.focus, w) -- one retry
        end
    end)
end

local function refocus(ctx)
    if isIgnoredApp(hs.application.frontmostApplication()) then return end

    local fid, fpid = describe(hs.window.focusedWindow())
    if not ctx.force and fid and fid ~= ctx.closedId and not gone[fid]
        and fpid and fpid ~= ctx.closedPid then
        return -- focus already moved to another app deliberately; respect it
    end

    -- Still on the closed window's empty fullscreen Space: the desktop behind
    -- it isn't visible yet, so its windows would be missed. Wait it out.
    if ctx.closedFullscreen and (ctx.attempts or 0) < SETTLE_RETRIES
        and onEmptyFullscreenSpace() then
        ctx.attempts = (ctx.attempts or 0) + 1
        FM.refocusTimer = hs.timer.doAfter(SETTLE_STEP, function()
            FM.refocusTimer = nil
            refocus(ctx)
        end)
        return
    end

    local target = pickTarget(ctx)
    if target then
        if safe(target.id, target) ~= fid then focusWindow(target) end
    else
        -- Nothing eligible on the visible desktops: go to the desktop.
        local finder = hs.application.get("com.apple.finder")
        if finder then finder:activate() end
    end
end

local function scheduleRefocus(ctx)
    lastClose = { ctx = ctx, at = now() }
    if FM.refocusTimer then FM.refocusTimer:stop() end
    local delay = ctx.closedFullscreen and FULLSCREEN_DELAY or REFOCUS_DELAY
    FM.refocusTimer = hs.timer.doAfter(delay, function()
        FM.refocusTimer = nil
        refocus(ctx)
    end)
end

---------------------------------------------------------------------------
-- Window events
---------------------------------------------------------------------------
local function onFocused(win)
    local id, pid, subrole = describe(win)
    if not id or not ALLOWED_SUBROLES[subrole] then return end
    meta[id] = { pid = pid, subrole = subrole, win = win,
                 fullscreen = safe(win.isFullScreen, win) == true }
    lastReal = { id = id, pid = pid }

    -- Commit only if focus holds. This keeps macOS's instant "focus the same
    -- app's next window" reaction out of the history when a window closes.
    cancelPending()
    pendingId = id
    FM.promoteTimer = hs.timer.doAfter(PROMOTE_DELAY, function()
        FM.promoteTimer, pendingId = nil, nil
        local fw = hs.window.focusedWindow()
        if fw and safe(fw.id, fw) == id then mruPromote(id) end
    end)
end

local function onGone(win, kind)
    local id = win and safe(win.id, win)
    if not id then return end
    local wasActive = (mru[1] == id) or (pendingId == id)

    if kind == "destroyed" then
        if handledAt[id] then return end
        gone[id] = true
        local ctx = wasActive and makeCtx(id, false)
        mruRemove(id)
        meta[id] = nil
        if not wasActive then return end -- background window: focus stays put
        handledAt[id] = now()
        cancelPending()
        scheduleRefocus(ctx)
    else -- "minimized" or "hidden"
        local ctx = wasActive and makeCtx(id, kind == "hidden")
        mruDemote(id) -- bottom of the z-order, like Windows
        if not wasActive then return end
        handledAt[id] = now()
        cancelPending()
        scheduleRefocus(ctx)
    end
end

local WF = hs.window.filter
FM.wf = WF.new(true):setOverrideFilter({ allowRoles = { "AXStandardWindow", "AXDialog" } })
FM.wf:subscribe(WF.windowFocused,   onFocused)
FM.wf:subscribe(WF.windowDestroyed, function(w) onGone(w, "destroyed") end)
FM.wf:subscribe(WF.windowMinimized, function(w) onGone(w, "minimized") end)
FM.wf:subscribe(WF.windowHidden,    function(w) onGone(w, "hidden") end)

-- Track fullscreen state so a close can wait out the Space animation.
local function setFullscreen(win, value)
    local id, pid, subrole = describe(win)
    if not id then return end
    meta[id] = meta[id] or { pid = pid, subrole = subrole }
    meta[id].fullscreen = value
    meta[id].win = win
end
FM.wf:subscribe(WF.windowFullscreened,   function(w) setFullscreen(w, true) end)
FM.wf:subscribe(WF.windowUnfullscreened, function(w) setFullscreen(w, false) end)

---------------------------------------------------------------------------
-- Fallback 1: Cmd-W / Cmd-M / Cmd-Q, for apps with unreliable window events
---------------------------------------------------------------------------
local function onCommandKey(key)
    local front = hs.application.frontmostApplication()
    local fpid = front and safe(front.pid, front)

    if key == "q" then
        if fpid then
            quitCtx = { pid = fpid, at = now(), snapshot = copy(mru),
                        closedId = lastReal and lastReal.id }
        end
        return
    end

    -- Uses state we already track instead of AX calls, so the tap stays fast.
    if not lastReal or lastReal.pid ~= fpid then return end
    local id, pid = lastReal.id, lastReal.pid
    local ctx = makeCtx(id, false)

    if FM.keyTimer then FM.keyTimer:stop() end
    FM.keyTimer = hs.timer.doAfter(KEY_CHECK_DELAY, function()
        FM.keyTimer = nil
        if key == "w" then
            if handledAt[id] or gone[id] then return end -- events already handled it
            if findWindow(pid, id) then return end      -- only a tab closed, or a save prompt
            gone[id], handledAt[id] = true, now()
            mruRemove(id)
        else -- "m"
            if handledAt[id] and now() - handledAt[id] < 2 then return end
            local w = findWindow(pid, id)
            if not w or not safe(w.isMinimized, w) then return end
            handledAt[id] = now()
            mruDemote(id)
        end
        refocus(ctx)
    end)
end

local keymap = hs.keycodes.map
FM.keyTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
    local f = e:getFlags()
    if f.cmd and not f.ctrl then
        local key = keymap[e:getKeyCode()]
        if key == "w" or key == "m" or key == "q" then onCommandKey(key) end
    end
    return false -- never swallow the key
end)
FM.keyTap:start()

-- macOS silently disables event taps sometimes; turn it back on.
FM.tapWatchdog = hs.timer.doEvery(5, function()
    if not FM.keyTap:isEnabled() then FM.keyTap:start() end
end)

---------------------------------------------------------------------------
-- Fallback 2: app quit (Cmd-Q, Dock, or apps that quit on last window close)
---------------------------------------------------------------------------
FM.appWatcher = hs.application.watcher.new(function(_, event, app)
    if event ~= hs.application.watcher.terminated then return end
    local pid = app and safe(app.pid, app)
    if not pid then return end

    for id, m in pairs(meta) do
        if m.pid == pid then gone[id] = true; mruRemove(id); meta[id] = nil end
    end

    local t, ctx = now(), nil
    if quitCtx and quitCtx.pid == pid and t - quitCtx.at < QUIT_WINDOW then
        ctx = { closedId = quitCtx.closedId, closedPid = pid,
                snapshot = quitCtx.snapshot, force = true, excludePid = pid }
        quitCtx = nil
    elseif lastClose and lastClose.ctx.closedPid == pid and t - lastClose.at < 3 then
        ctx = lastClose.ctx
        ctx.force, ctx.excludePid = true, pid
    end
    if ctx then scheduleRefocus(ctx) end
end)
FM.appWatcher:start()

---------------------------------------------------------------------------
-- Fallback 3: slow poll for windows closed by mouse in apps with no events.
-- Acts only when the frontmost app is the one that last had a real window,
-- it has no focused window now, AND that window no longer exists — so
-- clicking the desktop (Finder) or renaming a file never triggers it.
---------------------------------------------------------------------------
local strikes = 0
FM.poll = hs.timer.doEvery(POLL_INTERVAL, function()
    local front = hs.application.frontmostApplication()
    if not front or isIgnoredApp(front) or not lastReal
        or hs.window.focusedWindow() ~= nil
        or safe(front.pid, front) ~= lastReal.pid
        or handledAt[lastReal.id]
        or findWindow(lastReal.pid, lastReal.id) then
        strikes = 0
        return
    end
    strikes = strikes + 1
    if strikes < 2 then return end
    strikes = 0

    local id = lastReal.id
    local ctx = makeCtx(id, false)
    gone[id], handledAt[id] = true, now()
    mruRemove(id)
    refocus(ctx)
end)

---------------------------------------------------------------------------
-- Seed history from the current z-order so it works right after reload.
---------------------------------------------------------------------------
for _, w in ipairs(safe(hs.window.orderedWindows) or {}) do
    local id, pid, subrole = describe(w)
    if id and ALLOWED_SUBROLES[subrole] then
        meta[id] = { pid = pid, subrole = subrole, win = w,
                     fullscreen = safe(w.isFullScreen, w) == true }
        mru[#mru + 1] = id
    end
end
do
    local fw = hs.window.focusedWindow()
    local id, pid, subrole = describe(fw)
    if id and ALLOWED_SUBROLES[subrole] then
        meta[id] = { pid = pid, subrole = subrole, win = fw,
                     fullscreen = safe(fw.isFullScreen, fw) == true }
        mruPromote(id)
        lastReal = { id = id, pid = pid }
    end
end

---------------------------------------------------------------------------
-- Shortcuts
---------------------------------------------------------------------------
local config = {}
local ok, result = pcall(dofile, hs.configdir .. "/config.lua")
if ok and type(result) == "table" then config = result end

config.terminal    = config.terminal    or "Terminal"
config.fileManager = config.fileManager or "Finder"
config.browser     = config.browser     or "Safari"

hs.hotkey.bind({ "ctrl", "cmd" }, "T", function() hs.application.launchOrFocus(config.terminal) end)
hs.hotkey.bind({ "ctrl", "cmd" }, "E", function() hs.application.launchOrFocus(config.fileManager) end)
hs.hotkey.bind({ "ctrl", "cmd" }, "B", function() hs.application.launchOrFocus(config.browser) end)
