local cursor = reaper.GetCursorPosition()

-- Freeze drawing so the edit cursor jump is not visible
reaper.PreventUIRefresh(1)

-- Remember the visible part of the timeline
local view_start, view_end = reaper.GetSet_ArrangeView2(0, false, 0, 0)

--Insert empty item
reaper.Main_OnCommand(40142, 0)

reaper.SetEditCurPos(cursor, false, false)

-- Put the timeline view back where it was (no page jump)
reaper.GetSet_ArrangeView2(0, true, 0, 0, view_start, view_end)

reaper.PreventUIRefresh(-1)

--Item: Show notes for items
reaper.Main_OnCommand(40850, 0)
