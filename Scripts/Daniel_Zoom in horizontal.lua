-- Get cursor position
local old_cursor = reaper.GetCursorPosition()

-- Get horizontal scroll position
local view_start, view_end = reaper.GetSet_ArrangeView2(0, false, 0, 0)

-- Find view center
local view_length = view_end - view_start
local view_center = view_start + view_length/2


-- Check if edit cursor is in the view
if old_cursor < view_end and old_cursor > view_start then
  -- View: Zoom out horizontal
  reaper.Main_OnCommand(1012, 0)
  
else

  reaper.PreventUIRefresh(1)

  -- Move edit cursor to view center
  reaper.SetEditCurPos(view_center, false, false)

  -- View: Zoom out horizontal
  reaper.Main_OnCommand(1012, 0)

  -- Restore cursor position
  reaper.SetEditCurPos(old_cursor, false, false)

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  
end
