local home = os.getenv("HOME")
local playlist_file = home .. "/.config/mpv/last_playlist.m3u8"
local finished_all = false

-- Helpers

local function is_url(s)
	return s:match("^%a[%a%d+%-%.]*://") ~= nil
end

local function resolve_path(filename, cwd)
	if not is_url(filename) and not filename:match("^/") then
		return cwd .. "/" .. filename
	end
	return filename
end

local function read_saved_playlist()
	local items = {}
	local f = io.open(playlist_file, "r")
	if not f then
		return items
	end
	for line in f:lines() do
		line = line:match("^%s*(.-)%s*$") -- trim whitespace
		if line ~= "" and not line:match("^#") then
			table.insert(items, line)
		end
	end
	f:close()
	return items
end

local function save_playlist_items(items)
	if #items == 0 then
		os.remove(playlist_file)
		return
	end
	local f = io.open(playlist_file, "w")
	if f then
		f:write("#EXTM3U\n")
		for _, item in ipairs(items) do
			f:write(item .. "\n")
		end
		f:close()
	end
end

-- Returns playlist items from a given 0-indexed position onwards
local function get_remaining_items(from_pos)
	local playlist = mp.get_property_native("playlist") or {}
	local cwd = mp.get_property("working-directory")
	local items = {}
	for i = from_pos + 1, #playlist do -- +1: Lua is 1-indexed, from_pos is 0-indexed
		table.insert(items, resolve_path(playlist[i].filename, cwd))
	end
	return items
end

-- Startup: merge saved playlist with command-line args

mp.add_timeout(0, function()
	local cwd = mp.get_property("working-directory")

	-- Capture items passed via command-line (already in MPV's playlist)
	local cmdline_items = {}
	for _, item in ipairs(mp.get_property_native("playlist") or {}) do
		table.insert(cmdline_items, resolve_path(item.filename, cwd))
	end

	local saved_items = read_saved_playlist()

	if #saved_items == 0 and #cmdline_items == 0 then
		return -- nothing to do
	end

	if #saved_items == 0 then
		-- No saved playlist: play normally, but save for future tracking
		save_playlist_items(cmdline_items)
		return
	end

	-- Load saved playlist first (this replaces MPV's current playlist)
	mp.commandv("loadlist", playlist_file)

	-- Append any new command-line items to the end
	for _, filename in ipairs(cmdline_items) do
		mp.commandv("loadfile", filename, "append")
	end

	-- Persist the combined list to disk
	if #cmdline_items > 0 then
		local all_items = {}
		for _, item in ipairs(saved_items) do
			table.insert(all_items, item)
		end
		for _, item in ipairs(cmdline_items) do
			table.insert(all_items, item)
		end
		save_playlist_items(all_items)
	end

	mp.osd_message("Resuming saved playlist (" .. (#saved_items + #cmdline_items) .. " items)", 3)
end)

-- When a file finishes naturally: remove it from the saved playlist

mp.register_event("end-file", function(event)
	if event.reason ~= "eof" then
		return
	end

	local pos = mp.get_property_number("playlist-pos", 0)
	local count = mp.get_property_number("playlist-count", 0)

	if pos >= count - 1 then
		-- Last item finished: clear the saved playlist entirely
		save_playlist_items({})
		finished_all = true
	else
		-- Save everything after the just-finished item
		save_playlist_items(get_remaining_items(pos + 1))
	end
end)

-- On quit mid-playlist: save from current item onwards (inclusive)

mp.register_event("shutdown", function()
	if finished_all then
		return
	end
	local pos = mp.get_property_number("playlist-pos", 0)
	save_playlist_items(get_remaining_items(pos))
end)
