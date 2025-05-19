function toggle_record_monitoring()

  local track_count = reaper.CountSelectedTracks(0)

  for i = 0, track_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local monitor_state = reaper.GetMediaTrackInfo_Value(track, "I_RECMON")
    
    if monitor_state == 0 then
      reaper.SetMediaTrackInfo_Value(track, "I_RECMON", 1)
    else
      reaper.SetMediaTrackInfo_Value(track, "I_RECMON", 0)
    end
  end
  -- Update the arrangement to reflect changes
  reaper.TrackList_AdjustWindows(false)
end

reaper.Undo_BeginBlock()
toggle_record_monitoring()
reaper.Undo_EndBlock("Toggle record monitoring", -1)

