local time_start, time_end = reaper.GetSet_LoopTimeRange( false, false, 0, 0, false )
time_start = 0

if time_start ~= time_end then
  reaper.GetSet_LoopTimeRange( true, false, time_start, time_end, false )
else
  time_end = reaper.GetCursorPosition()
  reaper.GetSet_LoopTimeRange( true, false, time_start, time_end, false )
end


--Set selected tracks razor edit area to time selection

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

--Move edit cursor to start of project
reaper.SetEditCurPos(0, false, false)

reaper.Undo_BeginBlock( "Set selected tracks razor edit area to time selection", -1 )
reaper.UpdateArrange()
reaper.PreventUIRefresh(1)
