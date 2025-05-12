local track = reaper.GetTrackFromPoint(reaper.GetMousePosition())
reaper.SetTrackSelected(track, true)

local num_selected_tracks = reaper.CountSelectedTracks(0)

-- Get the most recently selected track
local last_selected_track = reaper.GetSelectedTrack(0, num_selected_tracks - 1)
local last_track_index = reaper.GetMediaTrackInfo_Value(last_selected_track, "IP_TRACKNUMBER") - 1

-- Get the first track that was originally selected
local first_selected_track = reaper.GetSelectedTrack(0, 0)
local first_track_index = reaper.GetMediaTrackInfo_Value(first_selected_track, "IP_TRACKNUMBER") - 1

-- Determine the range between the first and the newly clicked track
local start_track_index = math.min(first_track_index, last_track_index)
local end_track_index = math.max(first_track_index, last_track_index)

-- Select all tracks in this range
for i = start_track_index, end_track_index do
    local track = reaper.GetTrack(0, i)
    reaper.SetTrackSelected(track, true)
end

reaper.UpdateArrange()

