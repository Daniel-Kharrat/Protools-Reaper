reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local start_time, end_time = reaper.GetSet_LoopTimeRange(false,false,0,0,false)

-- Save selected items in a list
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
-- Move edit cursor right
reaper.Main_OnCommand(40375,0)
-- Unselect all items
reaper.Main_OnCommand(40289,0)
-- Recover selection
for i=0, count-1 do
  reaper.SetMediaItemSelected(selected_items[i],true)
end

local new_cursor = reaper.GetCursorPosition()
local track = reaper.GetSelectedTrack(0,0)
local razor_str

if new_cursor < end_time then
  -- move cursor to end of selection
  reaper.Main_OnCommand(40631,0)
  -- move cursor one transient right
  reaper.Main_OnCommand(40375,0)

  reaper.GetSet_LoopTimeRange(true, true, start_time, reaper.GetCursorPosition(), false )
  razor_str = start_time .. " " .. reaper.GetCursorPosition() .. ' ""'
else
  if start_time == end_time then
  start_time = old_cursor
  end
  reaper.GetSet_LoopTimeRange(true, true, start_time, new_cursor, false )
  razor_str = start_time .. " " .. new_cursor .. ' ""'
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
