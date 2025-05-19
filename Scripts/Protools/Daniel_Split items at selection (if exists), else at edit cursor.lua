--Get selection
local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

--SWS: Split items at time selection/razor edit areas (if exists), else at edit cursor (also during playback)
reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SMARTSPLIT2"), 0)

if start_time == end_time then
  --SWS: Unselect all items on selected track(s)
  reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_UNSELONTRACKS"), 0)
end
