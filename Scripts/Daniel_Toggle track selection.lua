-- Get the currently clicked track (the track under the mouse cursor)
local track = reaper.GetTrackFromPoint(reaper.GetMousePosition())

if track then
    local is_selected = reaper.IsTrackSelected(track)

    if not is_selected then
        reaper.SetTrackSelected(track, true)
    else
        reaper.SetTrackSelected(track, false)
    end

    reaper.UpdateArrange()
end

