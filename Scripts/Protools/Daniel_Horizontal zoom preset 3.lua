local pixels_per_second = 93

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
