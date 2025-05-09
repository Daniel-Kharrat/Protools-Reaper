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
--go to previous track
reaper.Main_OnCommand(40286,0)
--clear all razor edits
reaper.Main_OnCommand(42406,0)
--create razor edit area
local track = reaper.GetSelectedTrack(0,0)
local razor_str = start_time .. " " .. end_time .. ' ""'
reaper.GetSetMediaTrackInfo_String( track, "P_RAZOREDITS", razor_str, true )
--select media item
--reaper.Main_OnCommand(42957,0)
