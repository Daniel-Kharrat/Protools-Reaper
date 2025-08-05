local time_start, time_end = reaper.GetSet_LoopTimeRange( false, false, 0, 0, false )

--Get the state of 'link timeline and edit selection' 
local command_id = reaper.NamedCommandLookup("_RSdd4ba6262e05c57604ab621179a4552cf2bad49b")
local state = reaper.GetToggleCommandState(command_id)

if time_start ~= time_end and state == 1 then
  --move cursor to start of time selection
  reaper.SetEditCurPos(time_start, false, false)
end

--Edit: Cut items/tracks/envelope points (depending on focus) within time selection, if any (smart cut)
reaper.Main_OnCommand(41384,0)

--Time selection: Remove (unselect) time selection and loop points
reaper.Main_OnCommand(40020,0)
