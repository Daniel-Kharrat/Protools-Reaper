reaper.set_action_options(2)

if reaper.GetPlayState() & 1 == 1 then
  reaper.PreventUIRefresh(1)
  
  local old_cursor =reaper.GetCursorPosition()

  --View: Move edit cursor to play cursor
  reaper.Main_OnCommand(40434,0)
  
  --set playback speed to 50%
  reaper.CSurf_OnPlayRateChange(2)
  
  --Transport: Play
  reaper.Main_OnCommand(1007,0)
  
  reaper.SetEditCurPos(old_cursor, false, false)
  
  reaper.PreventUIRefresh(-1)
else
  --set playback speed to 50% 
  reaper.CSurf_OnPlayRateChange(2)
  --Transport: Play
  reaper.Main_OnCommand(1007,0)
end


function reset()
  local is_playing = reaper.GetPlayState() & 1 == 1

  if is_playing then
    --do nothing
  else
  reaper.CSurf_OnPlayRateChange(1.0)
  return
  end
  
  reaper.defer(reset)
end

reset()
