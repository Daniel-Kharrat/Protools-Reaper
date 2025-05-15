function are_tracks_armed()
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local is_armed = reaper.GetMediaTrackInfo_Value(track, "I_RECARM")
        if is_armed == 1 then
            return true
        end
    end
    return false
end

function update_toolbar_button()function are_tracks_armed()
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local is_armed = reaper.GetMediaTrackInfo_Value(track, "I_RECARM")
        if is_armed == 1 then
            return true
        end
    end
    return false
end

function update_toolbar_button()

    local command_id = reaper.NamedCommandLookup("_RS02a24eb9425299db445e21d1ed1a08a2f6818766")
    
    if are_tracks_armed() then
        reaper.SetToggleCommandState(0, command_id, 1)
    else
        reaper.SetToggleCommandState(0, command_id, 0)
    end

    reaper.RefreshToolbar2(0, command_id)

    reaper.defer(update_toolbar_button)
end


update_toolbar_button()



    local command_id = reaper.NamedCommandLookup("_RS00bef326aea423845b8f957d0b0e62b841fadb7e")
    
    if are_tracks_armed() then
        reaper.SetToggleCommandState(0, command_id, 1)
    else
        reaper.SetToggleCommandState(0, command_id, 0)
    end

    reaper.RefreshToolbar2(0, command_id)

    reaper.defer(update_toolbar_button)
end


update_toolbar_button()

