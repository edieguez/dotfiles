-- Manages window focus intelligently using Hammerspoon's window filter.
-- 
-- General Functionality:
-- 1. Monitors window events (window destroyed or minimized) to ensure a focused window or application is always active.
-- 2. Implements prioritization rules for selecting the next window or application to focus on.
--
-- Rules for focusing:
-- 1. Prioritize focusing on the first non-fullscreen window in the current application stack.
-- 2. If no non-fullscreen windows are available, focus a fullscreen window (if one exists).
-- 3. If all windows are minimized or no windows are left:
--    - First, focus the Finder application (if available).
--    - As a final fallback, activate the last-used application.

-- Initialize a window filter for all applications
local wf = hs.window.filter.new(nil)
    :setDefaultFilter()
    :setSortOrder(hs.window.filter.sortByFocusedLast)

-- Focus the first available window or fallback to Finder or last used app
local function focusNextWindow()
    hs.timer.doAfter(0.15, function()
        local windows = wf:getWindows()

        -- Focus the first non-fullscreen or fullscreen window
        for _, win in ipairs(windows) do
            if not win:isFullScreen() or #windows == 1 then
                win:focus()
                return
            end
        end

        -- If no windows, fallback to Finder
        local finder = hs.application.find("Finder")

        if finder then
            finder:activate()
            return
        end

        -- Final fallback: last used app
        local lastApp = hs.application.frontmostApplication()
        if lastApp then lastApp:activate() end
    end)
end

-- Subscribe to relevant events
wf:subscribe(hs.window.filter.windowDestroyed, focusNextWindow)
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
