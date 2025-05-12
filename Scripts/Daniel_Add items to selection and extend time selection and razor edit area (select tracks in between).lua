reaper.PreventUIRefresh(1)

-- Save current arrange view scroll position
local view_start, view_end = reaper.BR_GetArrangeView(0)

local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

local old_cursor = reaper.GetCursorPosition()

--View: Move edit cursor to mouse cursor
reaper.Main_OnCommand(40513,0)

--Item: Select item under mouse cursor
reaper.Main_OnCommand(40528,0)

local new_cursor = reaper.GetCursorPosition()

-- Get the currently clicked track (the track under the mouse cursor)
local track = reaper.GetTrackFromPoint(reaper.GetMousePosition())
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS2ff6cea039db08b318797cc281eed6ffde8cb4e5"), 0)

if track then
    local is_selected = reaper.IsTrackSelected(track)

    if not is_selected then
        reaper.SetTrackSelected(track, true)
    end
end


local num_selected_tracks = reaper.CountSelectedTracks(0)

for i = 0, num_selected_tracks - 1 do
    -- Get the track at index i
    local track = reaper.GetSelectedTrack(0, i)
  
  if start_time == end_time and new_cursor > old_cursor then
    --move cursor to right edge
    reaper.Main_OnCommand(40319, 0)
    local sel_end = reaper.GetCursorPosition()
    reaper.GetSet_LoopTimeRange(true, true, old_cursor, sel_end, false )
    local razor_str = old_cursor .. " " .. sel_end .. ' ""'
    reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )
  end

  if start_time == end_time and new_cursor < old_cursor then
    -- move cursor to left edge
    reaper.Main_OnCommand(40318, 0) 
    local sel_start = reaper.GetCursorPosition()
    reaper.GetSet_LoopTimeRange(true, true, sel_start, old_cursor, false )
    local razor_str = sel_start .. " " .. old_cursor .. ' ""'
    reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )
  end    
  
  -- Calculate distances
  local dist_to_start = math.abs(new_cursor - start_time)
  local dist_to_end = math.abs(new_cursor - end_time)

  if dist_to_start > dist_to_end then
    if new_cursor < end_time then
      reaper.GetSet_LoopTimeRange(true, true, start_time, end_time, false )
      local razor_str = start_time .. " " .. end_time .. ' ""'
      reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )
    else
    --move cursor to right edge
    reaper.Main_OnCommand(40319, 0)
    local sel_end = reaper.GetCursorPosition()
    reaper.GetSet_LoopTimeRange(true, true, start_time, sel_end, false )
    local razor_str = start_time .. " " .. sel_end .. ' ""'
    reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )
    end
  end

  if dist_to_start < dist_to_end then
    if new_cursor > start_time then
      reaper.GetSet_LoopTimeRange(true, true, start_time, end_time, false )
      local razor_str = start_time .. " " .. end_time .. ' ""'
      reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )
    else
    -- move cursor to left edge
    reaper.Main_OnCommand(40318, 0) 
    local sel_start = reaper.GetCursorPosition()
    reaper.GetSet_LoopTimeRange(true, true, sel_start, end_time, false )
    local razor_str = sel_start .. " " .. end_time .. ' ""'
    reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )
    end
  end
  
end

--get time selection again
start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

--Move edit cursor to start of time selection
reaper.SetEditCurPos(start_time, false, false)
      
-- Script: Daniel_Select all items within time selection on selected tracks.lua
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS7f0f28a9e4ffff9e42de5f30f5c2a32b6453b72c"), 0)

-- Restore the arrange view scroll position
reaper.BR_SetArrangeView(0, view_start, view_end)

-- Update the arrange view
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
