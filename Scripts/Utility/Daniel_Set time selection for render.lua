------------------------------------------------------------
-- Create Time Selection: Project Start → End of Outro
------------------------------------------------------------

local OUTRO_TRACK_NAME = "Outro"

------------------------------------------------------------
-- Find Outro track
------------------------------------------------------------

local outro_track = nil

for i = 0, reaper.CountTracks(0) - 1 do

    local track = reaper.GetTrack(0, i)
    local _, track_name = reaper.GetSetMediaTrackInfo_String(
        track,
        "P_NAME",
        "",
        false
    )

    if track_name == OUTRO_TRACK_NAME then
        outro_track = track
        break
    end
end

------------------------------------------------------------
-- Check that Outro track exists
------------------------------------------------------------

if not outro_track then
    reaper.ShowMessageBox(
        'Could not find a track named "' .. OUTRO_TRACK_NAME .. '".',
        "Create Time Selection",
        0
    )
    return
end

------------------------------------------------------------
-- Find the rightmost item on Outro
------------------------------------------------------------

local last_item_end = nil

for i = 0, reaper.CountTrackMediaItems(outro_track) - 1 do

    local item = reaper.GetTrackMediaItem(outro_track, i)

    local position = reaper.GetMediaItemInfo_Value(
        item,
        "D_POSITION"
    )

    local length = reaper.GetMediaItemInfo_Value(
        item,
        "D_LENGTH"
    )

    local item_end = position + length

    if not last_item_end or item_end > last_item_end then
        last_item_end = item_end
    end
end

------------------------------------------------------------
-- Check that Outro contains an item
------------------------------------------------------------

if not last_item_end then
    reaper.ShowMessageBox(
        'The track "' .. OUTRO_TRACK_NAME .. '" contains no items.',
        "Create Time Selection",
        0
    )
    return
end

------------------------------------------------------------
-- Set time selection: 0 → end of Outro
------------------------------------------------------------

reaper.GetSet_LoopTimeRange(
    true,
    false,
    0,
    last_item_end,
    false
)

--View: Zoom out project
reaper.Main_OnCommand(40295,0)

--Peaks: Reset peaks display zoom for project
reaper.Main_OnCommand(42449,0)

--Move edit cursor to the beginning
reaper.SetEditCurPos(0, false, false)

reaper.UpdateArrange()
