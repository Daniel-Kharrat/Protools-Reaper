reaper.PreventUIRefresh(1)

local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

local old_cursor = reaper.GetCursorPosition()

--View: Move edit cursor to mouse cursor
reaper.Main_OnCommand(40513,0)
local new_cursor = reaper.GetCursorPosition()


-- Get the currently clicked track (the track under the mouse cursor)
local track = reaper.GetTrackFromPoint(reaper.GetMousePosition())
--reaper.Main_OnCommand(reaper.NamedCommandLookup("_RSf6098a40ebbc367e990daedac677a4b0b05bd1dc"), 0)  --don't select tracks in between

if track then
    local is_selected = reaper.IsTrackSelected(track)
    if not is_selected then
        reaper.SetTrackSelected(track, true)
    end
end

local num_selected_tracks = reaper.CountSelectedTracks(0)

for i = 0, num_selected_tracks - 1 do

  local track = reaper.GetSelectedTrack(0, i)
    
  if start_time == end_time and new_cursor > old_cursor then
    reaper.GetSet_LoopTimeRange(true, true, old_cursor, new_cursor, false )
    local razor_str = old_cursor .. " " .. new_cursor .. ' ""'
    reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )
  end

  if start_time == end_time and new_cursor < old_cursor then
    reaper.GetSet_LoopTimeRange(true, true, new_cursor, old_cursor, false )
    local razor_str = new_cursor .. " " .. old_cursor .. ' ""'
    reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )
  end

  -- Calculate distances
  local dist_to_start = math.abs(new_cursor - start_time)
  local dist_to_end = math.abs(new_cursor - end_time)

  if dist_to_start > dist_to_end then
    reaper.GetSet_LoopTimeRange(true, true, start_time, new_cursor, false )
    local razor_str = start_time .. " " .. new_cursor .. ' ""'
    reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )
  end

  if dist_to_start < dist_to_end then
    reaper.GetSet_LoopTimeRange(true, true, new_cursor, end_time, false )
    local razor_str = new_cursor .. " " .. end_time .. ' ""'
    reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )
  end
  
end

reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS94dc0dfafd24dbff81a1b0fd6d5b7bb388026d1c"), 0)


reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
