reaper.PreventUIRefresh(1)

local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

--move edit cursor to end of time selection
if start_time ~= end_time then
  reaper.SetEditCurPos(end_time, false, false)
end

local old_cursor = reaper.GetCursorPosition()

--Markers: Go to next marker/project end
reaper.Main_OnCommand(40173,0)
local new_cursor = reaper.GetCursorPosition()

--Create selection
local num_selected_tracks = reaper.CountSelectedTracks(0)

if start_time == end_time then
  reaper.GetSet_LoopTimeRange(true, true, old_cursor, new_cursor, false )

  for i = 0, num_selected_tracks - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local razor_str = old_cursor .. " " .. new_cursor .. ' ""'
    reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )
  end

else
  reaper.GetSet_LoopTimeRange(true, true, start_time, new_cursor, false )
  
  for i = 0, num_selected_tracks - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local razor_str = start_time .. " " .. new_cursor .. ' ""'
    reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )
  end
end

--Script: Daniel_Select all items within time selection on selected tracks.lua
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS94dc0dfafd24dbff81a1b0fd6d5b7bb388026d1c"), 0)


reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
