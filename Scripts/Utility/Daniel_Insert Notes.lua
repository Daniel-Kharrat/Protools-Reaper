local cursor = reaper.GetCursorPosition()

-- Freeze drawing so the edit cursor jump is not visible
reaper.PreventUIRefresh(1)

--Insert empty item
reaper.Main_OnCommand(40142, 0)

reaper.SetEditCurPos(cursor, false, false)

reaper.PreventUIRefresh(-1)

--Item: Show notes for items
reaper.Main_OnCommand(40850, 0)
