function are_tracks_soloed()
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local is_soloed = reaper.GetMediaTrackInfo_Value(track, "I_SOLO")
        if is_soloed == 1 or is_soloed == 2 then  -- 1 = Solo, 2 = Solo in place
            return true
        end
    end
    return false
end

function is_master_soloed()
    local masterMuteSoloFlags = reaper.GetMasterMuteSoloFlags()
    local isSoloed = masterMuteSoloFlags & 2
    if isSoloed == 2 then
      return true
    else
      return false
    end
end

function update_toolbar_button()

    local command_id = reaper.NamedCommandLookup("_RSab27b93a5d47c6be970a3409a47941aae1a8083b")

    if are_tracks_soloed() or is_master_soloed() then
        reaper.SetToggleCommandState(0, command_id, 1)
    else
        reaper.SetToggleCommandState(0, command_id, 0)
    end

    reaper.RefreshToolbar2(0, command_id)

    reaper.defer(update_toolbar_button)
end

update_toolbar_button()

