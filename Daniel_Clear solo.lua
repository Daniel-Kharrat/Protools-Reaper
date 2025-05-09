--Track: Unsolo all tracks
reaper.Main_OnCommand(40340,0)

--Unsolo master track
master_track = reaper.GetMasterTrack(0)
reaper.SetMediaTrackInfo_Value(master_track, "I_SOLO", 0)

