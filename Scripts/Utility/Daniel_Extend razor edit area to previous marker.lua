reaper.PreventUIRefresh(1)

local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

--move edit cursor to start of time selection
if start_time ~= end_time then
  reaper.SetEditCurPos(start_time, false, false)
end

local old_cursor = reaper.GetCursorPosition()

--Markers: Go to previous marker/project start
reaper.Main_OnCommand(40172,0)
local new_cursor = reaper.GetCursorPosition()

--Create selection
local num_selected_tracks = reaper.CountSelectedTracks(0)

if start_time == end_time then
  reaper.GetSet_LoopTimeRange(true, true, new_cursor, old_cursor, false )

  for i = 0, num_selected_tracks - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local razor_str = new_cursor .. " " .. old_cursor .. ' ""'
    reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )
  end

else
  reaper.GetSet_LoopTimeRange(true, true, new_cursor, end_time, false )
  
  for i = 0, num_selected_tracks - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local razor_str = new_cursor .. " " .. end_time .. ' ""'
    reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )
  end
end

--Script: Daniel_Select all items within time selection on selected tracks.lua
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS94dc0dfafd24dbff81a1b0fd6d5b7bb388026d1c"), 0)


reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
