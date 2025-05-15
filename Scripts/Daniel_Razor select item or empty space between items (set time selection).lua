reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- Save current arrange view scroll position
local view_start, view_end = reaper.BR_GetArrangeView(0)

--Time selection: Remove (unselect) time selection and loop points
reaper.Main_OnCommand(40020,0)

--Track: Select track under mouse
reaper.Main_OnCommand(41110,0)

--get selected track
local track = reaper.GetSelectedTrack(0,0)

--Select all items on selected track
reaper.Main_OnCommand(40421,0)

----------------------------------------------
--Check if there are items before the cursor--
----------------------------------------------
local cursor_position = reaper.GetCursorPosition()

local item_found_before_cursor = false

-- Loop through all media items on the selected track
local item_count = reaper.CountTrackMediaItems(track)
  for i = 0, item_count - 1 do
     local item = reaper.GetTrackMediaItem(track, i)
     local item_position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
     if item_position < cursor_position then
     break
     else
     reaper.SetEditCurPos(0, false, false)
     end
end

----------------------------------------------
----------------------------------------------

-- move cursor to left edge
reaper.Main_OnCommand(40318, 0) 

--set selection start
local start_time = reaper.GetCursorPosition()
  
--move cursor to right edge
reaper.Main_OnCommand(40319, 0)

--set selection end point
local end_time = reaper.GetCursorPosition()

-- Unselect all items
reaper.Main_OnCommand(40289,0)



--create razor edit area
local razor_str = start_time .. " " .. end_time .. ' ""'
reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )

--Set time selection
reaper.GetSet_LoopTimeRange(true, true, start_time, end_time, false)

--Move edit cursor to start of time selection
reaper.SetEditCurPos(start_time, false, false)

--Restore the arrange view scroll position
reaper.BR_SetArrangeView(0, view_start, view_end)

--Item: Select items
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS94dc0dfafd24dbff81a1b0fd6d5b7bb388026d1c"), 0)

reaper.Undo_EndBlock("Move cursor right to nearest item edge in selected tracks and set time selection",0)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
