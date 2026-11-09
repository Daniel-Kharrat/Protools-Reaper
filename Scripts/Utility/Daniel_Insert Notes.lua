local cursor = reaper.GetCursorPosition()

--Insert empty item
reaper.Main_OnCommand(40142, 0)

reaper.SetEditCurPos(cursor, false, false)

--Item: Show notes for items
reaper.Main_OnCommand(40850, 0)
