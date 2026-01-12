--Markers: Insert marker at current position
reaper.Main_OnCommand(40157, 0)

local max_idx = -1
local enum_index_of_max = nil
local max_pos, max_rgnend, max_name

--Count markers and regions
local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)
local total = num_markers + num_regions

--Find marker with highest ID
for i=0, total-1 do
  local retval, isrgn, pos, rgnend, name, idx = reaper.EnumProjectMarkers3(proj, i)

  if retval and not isrgn then
    if idx > max_idx then
      max_idx = idx
      enum_index_of_max = i
      max_pos = pos
      max_rgnend = rgnend
      max_name = name
    end
  end
end

--Change marker color
if enum_index_of_max then
  local r, g, b = 240, 40, 40
  local color = reaper.ColorToNative(r, g, b) | 0x1000000

  reaper.SetProjectMarkerByIndex2(0, enum_index_of_max, false, max_pos, max_rgnend, max_idx, max_name, color, 0)
end
