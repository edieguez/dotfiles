-- Manages window focus intelligently using Hammerspoon's window filter.
--
-- General Functionality:
-- 1. Monitors window events (window destroyed or minimized) to ensure a focused window or application is always active.
-- 2. Implements prioritization rules for selecting the next window or application to focus on.
--
-- Rules for focusing:
-- 1. Prioritize focusing on the first non-fullscreen window in the current application stack.
-- 2. If no non-fullscreen windows are available, focus a fullscreen window (if one exists).
-- 3. If all windows are minimized or no windows are left, focus Finder.
-- 4. Minimized windows are not considered for focusing.

-- Initialize a window filter for all applications
-- Ignore dialog windows and set sort order to focus on the last used window
local wf = hs.window.filter.new(nil)
    :setOverrideFilter({
        visible = true,
        allowRoles = { "AXStandardWindow", "AXDialog" },
    })
    :setSortOrder(hs.window.filter.sortByFocusedLast)

local function focusNextWindow()
    local windows = wf:getWindows()

    local normalWindows = {}
    local fullscreenWindows = {}

    for _, win in ipairs(windows) do
        if win:isFullScreen() then
            table.insert(fullscreenWindows, win)
        elseif not win:isMinimized() and not win:application():isHidden() then
            table.insert(normalWindows, win)
        end
    end

    if #normalWindows > 0 then
        normalWindows[1]:focus()
    elseif #fullscreenWindows > 0 then
        fullscreenWindows[1]:focus()
    else
        -- If no windows are left, focus Finder
        hs.application.find("Finder"):activate()
    end
end

wf:subscribe(hs.window.filter.windowDestroyed, function(win)
    if win and win:role() == "AXDialog" then
        local parentApp = win:application()
        if parentApp then
            parentApp:activate() -- Improved dialog handling
        end
        return
    end

    focusNextWindow()
end)
wf:subscribe(hs.window.filter.windowMinimized, focusNextWindow)

-- -- Keyboard shortcuts
hs.hotkey.bind({"ctrl", "cmd"}, "T", function()
    hs.application.launchOrFocus("iTerm")
end)

hs.hotkey.bind({"ctrl", "cmd"}, "E", function()
    hs.application.launchOrFocus("Finder")
end)

hs.hotkey.bind({"ctrl", "cmd"}, "B", function()
    hs.application.launchOrFocus("Brave Browser")
end)
