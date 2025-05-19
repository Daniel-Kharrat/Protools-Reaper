reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local start_time, end_time = reaper.GetSet_LoopTimeRange(false,false,0,0,false)
 
 --  Save selected items in a list
  local count = reaper.CountSelectedMediaItems(0)
  local selected_items = {}
  for i=0, count-1 do
    selected_items[i] = reaper.GetSelectedMediaItem(0,i)
  end
  
 local old_cursor = reaper.GetCursorPosition()
  
  -- Unselect all items
  reaper.Main_OnCommand(40289,0)
  -- Select all items on selected track
  reaper.Main_OnCommand(40421,0)
  -- Move edit cursor left
  reaper.Main_OnCommand(40376,0)
  -- Unselect all items
  reaper.Main_OnCommand(40289,0)
  -- Recover selection
  for i=0, count-1 do
  reaper.SetMediaItemSelected(selected_items[i],true)
  end
  
  local new_cursor = reaper.GetCursorPosition()
  local track = reaper.GetSelectedTrack(0,0)
  local razor_str
  
if new_cursor < start_time then
  reaper.GetSet_LoopTimeRange(true, true, new_cursor, end_time, false )
  razor_str = new_cursor .. " " .. end_time .. ' ""'
  else
  -- move cursor to start of selection
  reaper.Main_OnCommand(40630,0)
  -- move cursor one transient left
  reaper.Main_OnCommand(40376,0)
  --get the cursor position
  new_cursor = reaper.GetCursorPosition()
  reaper.GetSet_LoopTimeRange(true, true, new_cursor, old_cursor, false )
  razor_str = new_cursor .. " " .. old_cursor .. ' ""'
end
---------------------------
--create razor edit areas--
---------------------------
local track_count = reaper.CountSelectedTracks(0)

for i = 0, track_count - 1 do
  local track = reaper.GetSelectedTrack(0, i)
  reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )
end
  
reaper.Undo_EndBlock("Move cursor right to nearest item edge in selected tracks and set time selection",0)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
