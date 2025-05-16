-- Get cursor position
local old_cursor = reaper.GetCursorPosition()

-- Get horizontal scroll position
local view_start, view_end = reaper.GetSet_ArrangeView2(0, false, 0, 0)

-- Find view center
local view_center = view_start + (view_end - view_start)/2


reaper.PreventUIRefresh(1)

-- Move edit cursor to view center
reaper.SetEditCurPos(view_center, false, false)

-- View: Zoom out horizontal
reaper.Main_OnCommand(1011, 0)
reaper.Main_OnCommand(1011, 0)

-- Restore cursor position
reaper.SetEditCurPos(old_cursor, false, false)

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
