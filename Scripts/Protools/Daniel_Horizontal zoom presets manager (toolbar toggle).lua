-- Daniel_Horizontal zoom presets manager (toolbar toggle)
-- Version: 1.0
-- Author: Daniel Kharrat
-- Description: Toolbar toggle for "Daniel_Horizontal zoom presets manager". Opens the window, or
--   closes it if it is already open. The button lights up while the window is open; the manager
--   keeps both in sync.

-- Action ID of "Daniel_Horizontal zoom presets manager.lua" (from the Action List)
local main_cmd = reaper.NamedCommandLookup("_RSd3f0c65f03b9ea9fd7b289fae07e4e84cdda964e")
if main_cmd == 0 then return end

-- Running the manager while it is open closes it (it is set up to do that)
reaper.Main_OnCommand(main_cmd, 0)
