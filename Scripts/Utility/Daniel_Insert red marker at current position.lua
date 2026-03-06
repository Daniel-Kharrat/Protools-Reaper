reaper.Undo_BeginBlock()

local playstate = reaper.GetPlayState()
local cursor_pos

if playstate & 1 == 0 then
   cursor_pos = reaper.GetCursorPosition()
else
   cursor_pos = reaper.GetPlayPosition()
end

local r, g, b = 240, 40, 40
local color = reaper.ColorToNative(r, g, b) | 0x1000000

reaper.AddProjectMarker2(0, false, cursor_pos, 0, "", -1, color)

reaper.Undo_EndBlock("Insert red marker", -1)
