reaper.Undo_BeginBlock()

local item = reaper.GetSelectedMediaItem(0,0)
if not item then return end

local _, chunk = reaper.GetItemStateChunk(item, "", false)
local t = {}

for line in chunk:gmatch("[^\r\n]+") do
    -- Remove any existing AUDIO or VIDEO_DISABLED lines
    if line ~= "AUDIO 0" and line ~= "AUDIO 1" and line ~= "VIDEO_DISABLED" then
        table.insert(t, line)
    end
end

-- Insert flags for video-only
-- Video enabled (default), audio disabled
for i=1,#t do
    if t[i] == "<SOURCE VIDEO" then
        table.insert(t, i+1, "AUDIO 0")
        table.insert(t, i+2, "VIDEO")  -- explicitly video enabled
        break
    end
end

-- Apply changes
reaper.SetItemStateChunk(item, table.concat(t,"\n"), false)

-- Force REAPER to refresh item
reaper.UpdateItemInProject(item)
reaper.Main_OnCommand(40047,0) -- rebuild peaks
reaper.UpdateArrange()

reaper.Undo_EndBlock("Set item to video-only exclusive", -1)
