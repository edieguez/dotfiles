-- Manages window focus intelligently using Hammerspoon's window filter.
--
-- Features:
-- 1. Ensures a window is always focused: when a window is destroyed or minimized, focuses the next available window.
-- 2. If no windows are available, activates Finder as a fallback.
-- 3. Binds hotkeys for launching Terminal, Finder, and Browser (customizable).

hs.application.enableSpotlightForNameSearches(true)

-- Initialize a window filter for all applications
wf = hs.window.filter.new(nil)
    :setOverrideFilter({
        visible = true,
        allowRoles = { "AXStandardWindow", "AXDialog" },
    })
    :setSortOrder(hs.window.filter.sortByFocusedLast)

local function focusNextWindow()
    local windows = wf:getWindows()
    local frontApp = hs.application.frontmostApplication() -- Get current frontmost app

    if #windows > 0 then
        local nextWindow = windows[1]
        local nextApp = nextWindow:application()
        if nextApp and frontApp and nextApp:bundleID() ~= frontApp:bundleID() then
            nextWindow:focus()
        elseif not nextApp then
            nextWindow:focus()
        end
    else
        hs.application.find("Finder"):activate()
    end
end

wf:subscribe(hs.window.filter.windowDestroyed, function(win)
    if win and win:role() == "AXDialog" then
        local parentApp = win:application()
        if parentApp then
            parentApp:activate()
        end
        return
    end

    focusNextWindow()
end)
wf:subscribe(hs.window.filter.windowMinimized, focusNextWindow)

-- Load shortcut configuration with error handling
local config = {}
local ok, result = pcall(dofile, hs.configdir .. "/config.lua")
if ok and type(result) == "table" then
    config = result
end

config.terminal = config.terminal or "Terminal"
config.fileManager = config.fileManager or "Finder"
config.browser = config.browser or "Safari"

-- Keyboard shortcuts
if config.terminal then
    hs.hotkey.bind({"ctrl", "cmd"}, "T", function()
        hs.application.launchOrFocus(config.terminal)
    end)
end

if config.fileManager then
    hs.hotkey.bind({"ctrl", "cmd"}, "E", function()
        hs.application.launchOrFocus(config.fileManager)
    end)
end

if config.browser then
    hs.hotkey.bind({"ctrl", "cmd"}, "B", function()
        hs.application.launchOrFocus(config.browser)
    end)
end
