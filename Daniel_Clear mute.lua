--Track: Unmute all tracks
reaper.Main_OnCommand(40339,0)

--Unmute master track
master_track = reaper.GetMasterTrack(0)
reaper.SetMediaTrackInfo_Value(master_track, "B_MUTE", 0)

