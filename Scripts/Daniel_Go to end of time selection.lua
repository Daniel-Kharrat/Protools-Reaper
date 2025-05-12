local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

--move edit cursor to end of time selection
if start_time ~= end_time then
  reaper.SetEditCurPos(end_time, false, false)
end

--SWS: Horizontal scroll to put edit cursor at 50%
reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_HSCROLL50"),0)
