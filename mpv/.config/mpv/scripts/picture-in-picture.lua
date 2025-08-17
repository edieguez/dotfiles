-- Put MPV in picture-in-picture mode
local states = {
    windowed = "windowed",
    picture_in_picture = "picture-in-picture",
    fullscreen = "fullscreen"
}
local current_state = states.windowed
local previous_state = nil
local previous_geometry = nil
local messages = {
    windowed = "Windowed mode activated",
    picture_in_picture = "Picture-in-Picture mode activated",
    fullscreen = "Fullscreen mode activated"
}
local options = {
    resolution = "854x480",
    position = "bottom-right"
}

mp.options = require "mp.options"
mp.options.read_options(options, "picture-in-picture")

function toggle_pip()
    if current_state == states.windowed or current_state == states.fullscreen then
        mp.osd_message("Picture-in-Picture mode activated", 2)

        -- Store the current geometry, including position
        if current_state == states.windowed then
            save_geometry()
        end

        mp.set_property("ontop", "yes")
        mp.set_property("autofit", options.resolution)
        mp.set_property("fullscreen", "no")

        -- Move the window to the specified corner
        set_position()

        transition_state(states.picture_in_picture)
    else
        restore_geometry()

        mp.osd_message(messages.windowed, 2)
        transition_state(states.windowed)
    end
end

function set_position()
    local x, y = 0, 0

    if options.position == "top-left" then
        x, y = 0, 0
    elseif options.position == "top-right" then
        x, y = 100, 0
    elseif options.position == "bottom-left" then
        x, y = 0, 100
    elseif options.position == "bottom-right" then
        x, y = 100, 100
    elseif options.position == "left-center" then
        x, y = 0, 50
    elseif options.position == "right-center" then
        x, y = 100, 50
    elseif options.position == "top-center" then
        x, y = 50, 0
    elseif options.position == "bottom-center" then
        x, y = 50, 100
    elseif options.position == "center" then
        x, y = 50, 50
    else
        -- If the position is not recognized, default to bottom-right
        mp.osd_message("Invalid position option. Defaulting to bottom-right.", 2)
        x, y = 100, 100
    end

    mp.set_property("geometry", string.format("%d%%:%d%%", x, y))
end

function save_geometry()
    previous_geometry = {
        ontop = mp.get_property("ontop"),
        autofit = mp.get_property("autofit"),
        geometry = mp.get_property("geometry"),
        fullscreen = mp.get_property("fullscreen")
    }
end

function restore_geometry()
    if previous_geometry then
        mp.set_property("ontop", previous_geometry.ontop)
        mp.set_property("autofit", previous_geometry.autofit)
        mp.set_property("geometry", "50%:50%")
        mp.set_property("fullscreen", previous_geometry.fullscreen)
    end
end

function transition_state(target_state)
    previous_state = current_state
    current_state = target_state
end

-- Transition states when entering/exiting fullscreen
mp.observe_property("fullscreen", "bool", function(name, value)
    if value then
        mp.osd_message(messages.fullscreen, 2)
        mp.set_property("ontop", "no")
        transition_state(states.fullscreen)
    elseif previous_state == states.windowed then
        mp.osd_message(messages.windowed, 2)
        transition_state(states.windowed)
    elseif previous_state == states.picture_in_picture then
        mp.osd_message(messages.picture_in_picture, 2)
        mp.set_property("ontop", "yes")
        transition_state(states.picture_in_picture)
    end

    if previous_geometry == nil then
        save_geometry()
    end
end)

-- Activate PIP when pressing i
mp.add_key_binding("i", "toggle_pip", toggle_pip)