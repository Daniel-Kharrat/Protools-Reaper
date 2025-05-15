reaper.PreventUIRefresh(1)

--Get cursor position
local cursor_pos = reaper.GetCursorPosition()

--Get time selection
local start_time, end_time = reaper.GetSet_LoopTimeRange(false,false,0,0,false)

--Get arrange view position
local view_start, view_end = reaper.GetSet_ArrangeView2(0, false, 0, 0)

if start_time ~= end_time then
  
  --Move edit cursor to start of time selection
  reaper.SetEditCurPos(start_time, false, false)

  --Item: Paste items/tracks
  reaper.Main_OnCommand(42398,0)

else
  
  --Item: Paste items/tracks
  reaper.Main_OnCommand(42398,0)

end

--Restore cursor position
reaper.SetEditCurPos(cursor_pos, false, false)

--Restore arrange view position
reaper.GetSet_ArrangeView2(0, true, 0, 0, view_start, view_end)

--Time selection: Set time selection to items
reaper.Main_OnCommand(40290,0)

-- Update the arrange view
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
