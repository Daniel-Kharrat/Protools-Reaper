-- Get first selected media item
item = reaper.GetSelectedMediaItem(0,0)

-- Move item to start of project
reaper.SetMediaItemInfo_Value(item, "D_POSITION", 0)

-- Update the arrange view
reaper.UpdateArrange()

