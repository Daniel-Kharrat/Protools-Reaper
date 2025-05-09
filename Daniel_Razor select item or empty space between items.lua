track = reaper.GetSelectedTrack(0,0)
-- Unselect all items
reaper.Main_OnCommand(40289,0)

----------------------------------------------
--Check if there are items before the cursor--
----------------------------------------------

-- Get the position of the edit cursor
local cursor_position = reaper.GetCursorPosition()

-- Initialize a variable to track if a media item is found
local item_found_before_cursor = false

-- Loop through all media items on the selected track
local item_count = reaper.CountTrackMediaItems(track)
  for i = 0, item_count - 1 do
     local item = reaper.GetTrackMediaItem(track, i)
     local item_position = reaper.GetMediaItemInfo_Value(item, "D_POSITION") -- Get the item's start position

     -- Check if the item starts before the edit cursor
     if item_position < cursor_position then
          item_found_before_cursor = true
          break  -- Exit the loop if we find at least one item
     end
end
-----------------------------------------------
-----------------------------------------------

--if there are media items before the cursor then move the cursor to item edge
if item_found_before_cursor == true then
  -- move cursor to left edge
  local sws_command_id = reaper.NamedCommandLookup("_RS90087e94b35313c1f1462a2dcaf4e5d7496b33b7")
  reaper.Main_OnCommand(sws_command_id, 0) 
  else -- move the cursor to start of project
  reaper.Main_OnCommand(40042, 0)
end

--set selection start
local start_time = reaper.GetCursorPosition()

----------------------------------------------
--Check if there are items before the cursor--
----------------------------------------------

-- Get the position of the edit cursor
local cursor_position = reaper.GetCursorPosition()

-- Initialize a variable to track if a media item is found
local item_found_after_cursor = false

-- Loop through all media items on the selected track
local item_count = reaper.CountTrackMediaItems(track)
  for i = 0, item_count - 1 do
     local item = reaper.GetTrackMediaItem(track, i)
     local item_position = reaper.GetMediaItemInfo_Value(item, "D_POSITION") -- Get the item's start position

     -- Check if the item starts before the edit cursor
     if item_position > cursor_position then
          item_found_after_cursor = true
          break  -- Exit the loop if we find at least one item
     end
end
-----------------------------------------------
-----------------------------------------------

--if there are media items after the cursor then move the cursor to item edge
if item_found_after_cursor == true then
  --move cursor to right edge
  local sws_command_id = reaper.NamedCommandLookup("_RSb8146d3e43543df6ec61dadfccdfc1c99ce97ac9")
  reaper.Main_OnCommand(sws_command_id, 0)
  else -- move the cursor to end of project
  reaper.Main_OnCommand(40043, 0)
end

--set selection end point
local end_time = reaper.GetCursorPosition()

--create razor edit area
local razor_str = start_time .. " " .. end_time .. ' ""'
reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )

--move edit cursor to start of razor edit area
reaper.SetEditCurPos(start_time, 0, 0)
