local time_start, time_end = reaper.GetSet_LoopTimeRange( false, false, 0, 0, false )

if time_start ~= time_end then
  time_end = reaper.GetProjectLength()
  reaper.GetSet_LoopTimeRange( true, false, time_start, time_end, false )
else
  time_start = reaper.GetCursorPosition()
  time_end = reaper.GetProjectLength()
  reaper.GetSet_LoopTimeRange( true, false, time_start, time_end, false )
end


--Set selected tracks razor edit area to time selection
local time_start, time_end = reaper.GetSet_LoopTimeRange( false, false, 0, 0, false )
if time_start == time_end then return false end

local count_sel_tracks = reaper.CountSelectedTracks( 0 )
local count_tracks = reaper.CountTracks( 0 )

reaper.PreventUIRefresh( 1 )

reaper.Undo_BeginBlock()

for i = 0, count_tracks - 1 do
  local track = reaper.GetTrack( 0, i )
  if count_sel_tracks == 0 or reaper.IsTrackSelected( track ) then
    local razor_str = time_start .. " " .. time_end .. ' ""'
    local retval, stringNeedBig = reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )
  end
end

--Razor edit: Select media items within razor edit area
reaper.Main_OnCommand(42957,0)

reaper.Undo_BeginBlock( "Set selected tracks razor edit area to time selection", -1 )
reaper.UpdateArrange()
reaper.PreventUIRefresh(1)
