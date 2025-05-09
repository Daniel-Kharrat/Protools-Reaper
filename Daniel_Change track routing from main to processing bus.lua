function main()
  reaper.Undo_BeginBlock()

  local proj = 0
  local voBus = nil

  -- Find VO BUS track
  local trackCount = reaper.CountTracks(proj)
  for i = 0, trackCount - 1 do
    local track = reaper.GetTrack(proj, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if name == "VO BUS" then
      voBus = track
      break
    end
  end

  if not voBus then
    reaper.ShowMessageBox("Track named 'VO BUS' not found.", "Error", 0)
    return
  end

  -- Process each selected track
  local numSel = reaper.CountSelectedTracks(proj)
  for i = 0, numSel - 1 do
    local track = reaper.GetSelectedTrack(proj, i)
    local sendIndex = -1

    -- Check if this track has a send to VO BUS
    local numSends = reaper.GetTrackNumSends(track, 0)
    for s = 0, numSends - 1 do
      local destTrack = reaper.BR_GetMediaTrackSendInfo_Track(track, 0, s, 1)
      if destTrack == voBus then
        sendIndex = s
        break
      end
    end

    if sendIndex >= 0 then
      -- Send exists: remove it and restore main send
      reaper.RemoveTrackSend(track, 0, sendIndex)
      reaper.SetMediaTrackInfo_Value(track, "B_MAINSEND", 1)
    else
      -- No send: disable main send and create one to VO BUS
      reaper.SetMediaTrackInfo_Value(track, "B_MAINSEND", 0)
      local newSend = reaper.CreateTrackSend(track, voBus)
      reaper.SetTrackSendInfo_Value(track, 0, newSend, "I_SENDMODE", 0) -- post-fader
      reaper.SetTrackSendInfo_Value(track, 0, newSend, "D_VOL", 1.0)    -- 0 dB
    end
  end

  reaper.Undo_EndBlock("Toggle selected tracks main send vs VO BUS send", -1)
end

-- Load SWS extension check
if not reaper.BR_GetMediaTrackSendInfo_Track then
  reaper.ShowMessageBox("This script requires the SWS extension.", "Missing Dependency", 0)
else
  main()
end

