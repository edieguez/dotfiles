-- Initialize a window filter for the current application
local wf = hs.window.filter.new(nil)
    :setDefaultFilter()
    :setSortOrder(hs.window.filter.sortByFocusedLast)

-- Function to focus the last used application or next available window
local function focusNextOrLastUsedApp()
    -- Introduce a delay to handle potential new window creation
    hs.timer.doAfter(0.15, function()
        local windows = wf:getWindows()
        if #windows > 0 then
            local currentApp = hs.application.frontmostApplication()
            local minimizedWindows = hs.fnutils.filter(windows, function(win)
                return win:isMinimized()
            end)

            -- Check if only one window exists and it's minimized
            if #windows == 1 and #minimizedWindows == 1 then
                -- Focus the last used application
                local lastApp = hs.application.frontmostApplication()

                if lastApp then
                    lastApp:activate()
                end
            else
                -- Focus the next window in the list
                windows[1]:focus()
            end
        else
            -- If no windows are left, activate the last used application
            local nextApp = hs.application.frontmostApplication()

            if nextApp then
                nextApp:activate()
            end
        end
    end)
end

-- Subscribe to window destroyed events
wf:subscribe(hs.window.filter.windowDestroyed, focusNextOrLastUsedApp)

-- Subscribe to application deactivated events to handle minimized windows
wf:subscribe(hs.window.filter.windowMinimized, focusNextOrLastUsedApp)


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

hs.hotkey.bind({"ctrl", "cmd"}, "F4", function()
    hs.execute("/Users/emmanuel/.zsh/zsh-config/bin/bt-toggle.sh")
end)
