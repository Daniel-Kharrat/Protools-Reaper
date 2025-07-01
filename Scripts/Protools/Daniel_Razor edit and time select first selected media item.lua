--Get time selection
start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

--Get first selected track
track = reaper.GetSelectedTrack(0, 0)

-- Get first media item on selected track
item = reaper.GetSelectedMediaItem(0, 0)

local start_item = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
local end_item = start_item + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

--Check if there is a time selection 
if start_time == end_time then
  reaper.GetSet_LoopTimeRange(true, true, start_item, end_item, false)
  local razor_str = start_item .. " " .. end_item .. ' ""'
  reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )
  reaper.SetEditCurPos(start_item, false, false)
end
