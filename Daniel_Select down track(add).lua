local start_time, end_time = math.huge, -1
for tr = 0, reaper.CountSelectedTracks( 0 )-1 do
  local track = reaper.GetSelectedTrack(0, tr)
  local _, areas = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
  if areas ~= "" then
    for area_start, area_end in string.gmatch(areas, '(%S+) (%S+) %S+') do
      area_start, area_end = tonumber(area_start), tonumber(area_end)
      if area_start < start_time then start_time = area_start end
      if area_end > end_time then end_time = area_end end
    end
  end
end

--go to next track leaving other track selected
reaper.Main_OnCommand(40287,0)

local selected_track_count = reaper.CountSelectedTracks(0)

local last_selected_track = reaper.GetSelectedTrack(0, selected_track_count - 1)

--create razor edit area
local razor_str = start_time .. " " .. end_time .. ' ""'
reaper.GetSetMediaTrackInfo_String( last_selected_track, "P_RAZOREDITS", razor_str, true )
--Razor edit: Select media items within razor edit area
reaper.Main_OnCommand(42957,0)
