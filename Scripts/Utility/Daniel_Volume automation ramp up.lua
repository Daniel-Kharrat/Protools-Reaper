reaper.Undo_BeginBlock()

local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

--move edit cursor to end of time selection
if start_time ~= end_time then
  reaper.SetEditCurPos((start_time + end_time)/2, false, false)
end

--SWS/BR: Insert 2 envelope points at time selection
reaper.Main_OnCommand(reaper.NamedCommandLookup("_BR_INSERT_2_ENV_POINT_TIME_SEL"), 0)

--SWS/BR: Move edit cursor to next envelope point and select it
reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_BRMOVEEDITSELNEXTENV"), 0)

--SWS/BR: Increase selected envelope points by 10 db (volume envelope only)
reaper.Main_OnCommand(reaper.NamedCommandLookup("_BR_INC_VOL_ENV_PT_10db"), 0)

--SWS/BR: Increase selected envelope points by 5 db (volume envelope only)
reaper.Main_OnCommand(reaper.NamedCommandLookup("_BR_INC_VOL_ENV_PT_5db"), 0)

--SWS/BR: Increase selected envelope points by 1 db (volume envelope only)
reaper.Main_OnCommand(reaper.NamedCommandLookup("_BR_INC_VOL_ENV_PT_1db"), 0)

--SWS/BR: Increase selected envelope points by 1 db (volume envelope only)
reaper.Main_OnCommand(reaper.NamedCommandLookup("_BR_INC_VOL_ENV_PT_1db"), 0)

reaper.Undo_EndBlock("",-1)
