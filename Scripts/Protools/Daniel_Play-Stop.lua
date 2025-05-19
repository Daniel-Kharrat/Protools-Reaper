--Get time selection
start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

--Get the state of "insertion follows playback" action
local command_id = reaper.NamedCommandLookup("_RS3954f4d6fde790290a4c7e86538380193bf6db74")
local active = reaper.GetToggleCommandState(command_id)

--Check if there is a time selection and "insertion follows playback" is active 
if start_time ~= end_time and active == 0 then
  reaper.SetEditCurPos(start_time, false, false)
end

--Transport: Play/stop
reaper.Main_OnCommand(40044,0)
