--Get first selected track
track = reaper.GetSelectedTrack(0, 0)

--Item: Unselect (clear selection of) all items
reaper.Main_OnCommand(40289,0)

-- Get first media item on selected track
item = reaper.GetTrackMediaItem(track, 0)

--Select the media item
reaper.SetMediaItemSelected(item, true)

--Edit: Copy items
reaper.Main_OnCommand(40698,0)

--Script: Daniel_Paste items-tracks.lua
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RSa405821fb80d64b8aa5261a7f041fdaf96be4268"), 0)


-- Update the arrange view
reaper.UpdateArrange()
