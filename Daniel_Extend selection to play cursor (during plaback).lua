reaper.PreventUIRefresh(1)

local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
local track = reaper.GetSelectedTrack(0,0)

local old_cursor = reaper.GetCursorPosition()

--View: Move edit cursor to play cursor
reaper.Main_OnCommand(40434,0)
local new_cursor = reaper.GetCursorPosition()

local num_selected_tracks = reaper.CountSelectedTracks(0)

for i = 0, num_selected_tracks - 1 do

  -- Get the track at index i
  local track = reaper.GetSelectedTrack(0, i)

  if start_time == end_time then
    reaper.GetSet_LoopTimeRange(true, true, old_cursor, new_cursor, false )
    local razor_str = old_cursor .. " " .. new_cursor .. ' ""'
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

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
