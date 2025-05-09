local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

if start_time ~= end_time then

    local num_selected_tracks = reaper.CountSelectedTracks(0)

    -- Loop through all selected tracks
    for t = 0, num_selected_tracks - 1 do
        local track = reaper.GetSelectedTrack(0, t)

        local num_items = reaper.CountTrackMediaItems(track)

        -- Loop through all items on the track
        for i = 0, num_items - 1 do
            local item = reaper.GetTrackMediaItem(track, i)
            local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_end = item_pos + item_len

            -- Check if the item is within the time selection range
            if (item_pos < end_time) and (item_end > start_time) then
                reaper.SetMediaItemSelected(item, true)  -- Select the item
            end
        end
    end
    reaper.UpdateArrange()
end

