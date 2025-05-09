reaper.PreventUIRefresh(1)

--Get cursor position
local cursor_pos = reaper.GetCursorPosition()

--Get arrange view position
local view_start, view_end = reaper.GetSet_ArrangeView2(0, false, 0, 0)

--Item: Paste items/tracks
reaper.Main_OnCommand(42398,0)

--Restore cursor position
reaper.SetEditCurPos(cursor_pos, false, false)

--Restore arrange view position
reaper.GetSet_ArrangeView2(0, true, 0, 0, view_start, view_end)

--SWS: Set time selection to selected items (skip if time selection exists)
reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAFETIMESEL"), 0)


-- Update the arrange view
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
