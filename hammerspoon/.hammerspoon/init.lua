-- Manages window focus intelligently using Hammerspoon's window filter.
--
-- Features:
-- 1. Ensures a window is always focused: when a window is destroyed or minimized, focuses the next available window.
-- 2. If no windows are available, activates Finder as a fallback.
-- 3. Binds hotkeys for launching Terminal, Finder, and Browser (customizable).

hs.application.enableSpotlightForNameSearches(true)

-- Initialize a window filter for all applications
local wf = hs.window.filter.new(nil)
    :setOverrideFilter({
        visible = true,
        allowRoles = { "AXStandardWindow", "AXDialog" },
    })
    :setSortOrder(hs.window.filter.sortByFocusedLast)

local function focusNextWindow()
    local windows = wf:getWindows()

    if #windows > 0 then
        windows[1]:focus()
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

    local destroyedApp = win and win:application()
    hs.timer.doAfter(0.05, function()
        if destroyedApp then
            for _, w in ipairs(wf:getWindows()) do
                if w:application():bundleID() == destroyedApp:bundleID() then
                    return
                end
            end
        end
        focusNextWindow()
    end)
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
hs.hotkey.bind({"ctrl", "cmd"}, "T", function()
    hs.application.launchOrFocus(config.terminal)
end)

hs.hotkey.bind({"ctrl", "cmd"}, "E", function()
    hs.application.launchOrFocus(config.fileManager)
end)

hs.hotkey.bind({"ctrl", "cmd"}, "B", function()
    hs.application.launchOrFocus(config.browser)
end)
