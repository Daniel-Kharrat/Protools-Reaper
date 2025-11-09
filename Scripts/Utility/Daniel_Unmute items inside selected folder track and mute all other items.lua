reaper.Undo_BeginBlock()

local sel_track = reaper.GetSelectedTrack(0, 0)
if not sel_track then
    reaper.ShowMessageBox("No track selected. Select the folder track (or any track inside the folder) and run again.","Error",0)
    return
end

local track_count = reaper.CountTracks(0)

-- 1) Mute every item in the project
for t = 0, track_count-1 do
    local tr = reaper.GetTrack(0, t)
    local it_cnt = reaper.CountTrackMediaItems(tr)
    for i = 0, it_cnt-1 do
        local it = reaper.GetTrackMediaItem(tr, i)
        reaper.SetMediaItemInfo_Value(it, "B_MUTE", 1)
    end
end

-- 2) Find the folder start for the selected track (if a child was selected)
local sel_idx = math.floor(reaper.GetMediaTrackInfo_Value(sel_track, "IP_TRACKNUMBER") - 1 + 0.5)
local folder_idx = sel_idx
local sel_depth = reaper.GetTrackDepth(sel_track)

-- If the selected track isn't a folder start, walk backwards to find the containing folder start
if reaper.GetMediaTrackInfo_Value(sel_track, "I_FOLDERDEPTH") ~= 1 then
    for i = sel_idx-1, 0, -1 do
        local t = reaper.GetTrack(0, i)
        if not t then break end
        if reaper.GetTrackDepth(t) < sel_depth then
            folder_idx = i
            break
        end
    end
end

local folder_track = reaper.GetTrack(0, folder_idx)
if not folder_track then
    reaper.ShowMessageBox("Could not find folder track.","Error",0)
    return
end

local folder_depth = reaper.GetTrackDepth(folder_track)

-- 3) Unmute items on the folder track itself
local it_cnt = reaper.CountTrackMediaItems(folder_track)
for i = 0, it_cnt-1 do
    local it = reaper.GetTrackMediaItem(folder_track, i)
    reaper.SetMediaItemInfo_Value(it, "B_MUTE", 0)
end

-- 4) Unmute items on all child tracks (stop when depth <= folder_depth)
local i = folder_idx + 1
while i < track_count do
    local tr = reaper.GetTrack(0, i)
    if not tr then break end
    local d = reaper.GetTrackDepth(tr)
    if d <= folder_depth then break end
    local itc = reaper.CountTrackMediaItems(tr)
    for j = 0, itc-1 do
        local it = reaper.GetTrackMediaItem(tr, j)
        reaper.SetMediaItemInfo_Value(it, "B_MUTE", 0)
    end
    i = i + 1
end

reaper.UpdateArrange()
reaper.Undo_EndBlock("Solo folder items (mute others)", -1)

