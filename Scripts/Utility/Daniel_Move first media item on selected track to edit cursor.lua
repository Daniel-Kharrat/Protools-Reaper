--Get first selected track
track = reaper.GetSelectedTrack(0, 0)

-- Get first media item on selected track
item = reaper.GetTrackMediaItem(track, 0)

-- Move item to edit cursor
reaper.SetMediaItemInfo_Value(item, "D_POSITION", reaper.GetCursorPosition())

--Select the media item
reaper.SetMediaItemSelected(item, true)

-- Update the arrange view
reaper.UpdateArrange()
