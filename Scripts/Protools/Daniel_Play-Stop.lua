--Get time selection
start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

--Get the state of "insertion follows playback" action
local command_id1 = reaper.NamedCommandLookup("_RS3954f4d6fde790290a4c7e86538380193bf6db74")
local state1 = reaper.GetToggleCommandState(command_id1)

--Get the state of 'link timeline and edit selection' 
local command_id2 = reaper.NamedCommandLookup("_RSdd4ba6262e05c57604ab621179a4552cf2bad49b")
local state2 = reaper.GetToggleCommandState(command_id2)

--Check if there is a time selection and "insertion follows playback" is active 
if start_time ~= end_time and state1 ~= 1 and state2 == 1 then
  reaper.SetEditCurPos(start_time, false, false)
end

--Transport: Play/stop
reaper.Main_OnCommand(40044,0)
