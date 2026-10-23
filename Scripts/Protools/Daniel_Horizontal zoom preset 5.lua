-- Daniel_Horizontal zoom preset 5
-- Version: 1.2
-- Author: Daniel Kharrat
-- Description: Zooms the arrange view to a fixed pixels-per-second value, so the zoom
--   looks the same on any screen size. Uses the zoom saved from
--   "Daniel_Horizontal zoom presets manager" if there is one, otherwise the default below.
-- Changelog:
--   1.2 - The saved zoom is read from reaper-extstate.ini instead of a file in the Data folder
--   1.1 - Uses the zoom saved from the Daniel_Horizontal zoom presets window

local slot = 5
local default_pixels_per_second = 31

-- Saved zoom for this slot (falls back to the default)
local pixels_per_second = default_pixels_per_second
do
  local v = tonumber(reaper.GetExtState("Daniel_Horizontal zoom presets", "preset_" .. slot))
  if v and v > 0 then pixels_per_second = v end
end

-- Get arrange view start and end
local view_start, view_end = reaper.GetSet_ArrangeView2(0, false, 0, 0)
local view_center = (view_start + view_end) / 2

-- Arrange view width in pixels, derived from current zoom
local view_width_px = (view_end - view_start) * reaper.GetHZoomLevel()

-- Time range that gives the wanted pixels per second at this width
local target_range = view_width_px / pixels_per_second

-- Calculate new start and end
local new_start = view_center - (target_range / 2)
local new_end = view_center + (target_range / 2)

-- Set arrange new start and end
reaper.GetSet_ArrangeView2(0, true, 0, 0, new_start, new_end)

if reaper.GetPlayState() & 1 == 0 then
  --SWS: Horizontal scroll to put edit cursor at 50%
  reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_HSCROLL50"),0)
end
