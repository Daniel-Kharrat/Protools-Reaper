local cursor = reaper.GetCursorPosition()

-- Freeze drawing so the edit cursor jump is not visible
reaper.PreventUIRefresh(1)

-- Remember the visible part of the timeline
local view_start, view_end = reaper.GetSet_ArrangeView2(0, false, 0, 0)

--Insert empty item
reaper.Main_OnCommand(40142, 0)

-- Give the new item a fixed dark gray color (good contrast with white text), not the track color
local NOTE_COLOR = reaper.ColorToNative(80, 80, 80) | 0x1000000
local item = reaper.GetSelectedMediaItem(0, 0)
if item then
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", NOTE_COLOR)
  reaper.UpdateItemInProject(item)
end

reaper.SetEditCurPos(cursor, false, false)

-- Put the timeline view back where it was (no page jump)
reaper.GetSet_ArrangeView2(0, true, 0, 0, view_start, view_end)

reaper.PreventUIRefresh(-1)

--Item: Show notes for items
reaper.Main_OnCommand(40850, 0)
