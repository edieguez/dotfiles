-- Manages window focus intelligently using Hammerspoon's window filter.

hs.application.enableSpotlightForNameSearches(true)
local spaces = require("hs.spaces")
local axSystemWide = require("hs.axuielement").systemWideElement()

-- 1. Create a global window filter that tracks all standard, visible windows
-- Sorted by most-recently-focused first.
local wf = hs.window.filter.new(true)
    :setOverrideFilter({
        visible = true,
        allowRoles = { "AXStandardWindow", "AXDialog" },
    })
    :setSortOrder(hs.window.filter.sortByFocusedLast)

local function windowIsAlive(id)
    if id == nil or id == 0 then return false end
    if hs.window(id) ~= nil then return true end

    -- Fallback for full-screen / multi-space windows
    local winSpaces = spaces.windowSpaces(id)
    return winSpaces ~= nil and #winSpaces > 0
end

local function isRealFocus(win)
    if not win then return false end
    local ok, id = pcall(function() return win:id() end)
    return ok and windowIsAlive(id)
end

-- Detects in-place text editing (e.g. Finder's inline rename field) so the
-- polling safety net below doesn't yank focus away mid-edit.
local function isEditingTextField()
    local ok, focusedElement = pcall(function()
        return axSystemWide:attributeValue("AXFocusedUIElement")
    end)
    if not ok or not focusedElement then return false end
    local role = focusedElement.AXRole
    return role == "AXTextField" or role == "AXTextArea"
end

-- Focuses the next valid window, explicitly skipping any closing/closing window ID
local function focusNextWindow(excludeId)
    local windows = wf:getWindows()

    for _, w in ipairs(windows) do
        local wid = w:id()
        if wid ~= excludeId and windowIsAlive(wid) then
            local app = w:application()
            if app then app:activate() end
            w:focus()
            return
        end
    end

    -- Fallback if no valid windows remain on screen
    local finder = hs.application.find("Finder")
    if finder then finder:activate() end
end

-- Prevent GC from swallowing single-shot timers
local pendingFocusTimer

wf:subscribe(hs.window.filter.windowDestroyed, function(win)
    local closedId = win and win:id() or nil

    -- Small delay to allow macOS window server to finish unmapping the surface
    pendingFocusTimer = hs.timer.doAfter(0.05, function()
        focusNextWindow(closedId)
    end)
end)

wf:subscribe(hs.window.filter.windowMinimized, function(win)
    local minId = win and win:id() or nil
    focusNextWindow(minId)
end)

-- System UI surfaces to ignore during periodic checks
local IGNORED_FRONTMOST_APPS = {
    Spotlight = true,
    loginwindow = true,
    ScreenSaverEngine = true,
    NotificationCenter = true,
    ControlCenter = true,
    SystemUIServer = true,
    Dock = true,
}

-- Safety Net: Polling fallback for non-compliant apps (Ghostty, Finder, etc.)
local deadStreak = 0
local lastRealApp = nil

FOCUS_POLL_TIMER = hs.timer.doEvery(0.1, function()
    local frontApp = hs.application.frontmostApplication()
    if frontApp and IGNORED_FRONTMOST_APPS[frontApp:name()] then
        deadStreak = 0
        return
    end

    local fw = hs.window.focusedWindow()
    if isRealFocus(fw) then
        deadStreak = 0
        lastRealApp = fw:application()
        return
    end

    if isEditingTextField() then
        deadStreak = 0
        return
    end

    if not (frontApp and lastRealApp and frontApp:bundleID() == lastRealApp:bundleID()) then
        deadStreak = 0
        return
    end

    deadStreak = deadStreak + 1
    if deadStreak >= 2 then
        local currentWin = hs.window.focusedWindow()
        focusNextWindow(currentWin and currentWin:id() or nil)
        deadStreak = 0
    end
end)

-- Shortcuts Config
local config = {}
local ok, result = pcall(dofile, hs.configdir .. "/config.lua")
if ok and type(result) == "table" then
    config = result
end

config.terminal = config.terminal or "Terminal"
config.fileManager = config.fileManager or "Finder"
config.browser = config.browser or "Safari"

hs.hotkey.bind({"ctrl", "cmd"}, "T", function() hs.application.launchOrFocus(config.terminal) end)
hs.hotkey.bind({"ctrl", "cmd"}, "E", function() hs.application.launchOrFocus(config.fileManager) end)
hs.hotkey.bind({"ctrl", "cmd"}, "B", function() hs.application.launchOrFocus(config.browser) end)
