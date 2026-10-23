-- Daniel_Horizontal zoom presets manager
-- Version: 1.0
-- Author: Daniel Kharrat
-- Description: Window with five buttons for the horizontal zoom presets
--   (Daniel_Horizontal zoom preset 1 to 5). A zoom is stored as pixels per second,
--   so a saved preset looks the same on any screen size. The presets are kept in
--   reaper-extstate.ini (section "Daniel_Horizontal zoom presets").
--   Left click: load the preset.
--   Hold the button for half a second: save the current arrange zoom into it
--   (overwrites what is there; the button lights up when it is saved).
--   Right click: reset the preset to its default.
--   A number is coloured while its preset holds a custom zoom.
--   Resize by dragging the left or right edge, the bottom edge or the bottom corners
--   (the window keeps its proportions; the top edge is locked). Right-click the
--   title bar to dock or undock it (when docked, right-click an empty area).
--   Running the script again closes the window. The toolbar toggle script
--   "Daniel_Horizontal zoom presets manager (toolbar toggle)" lights up while it is open.
-- Requires: ReaImGui, SWS (js_ReaScriptAPI optional: returns focus to REAPER after clicks)

if not reaper.ImGui_CreateContext then
  reaper.MB("This script needs the ReaImGui extension (install it with ReaPack).", "Horizontal zoom presets manager", 0)
  return
end

---------------------------------------------------------------------------
-- Toolbar toggle. The button follows the window. The flag in reaper.ini is 1 while the
-- window is open and 0 once the user closed it; quitting REAPER leaves it at 1.
---------------------------------------------------------------------------
local EXT = "Daniel_Horizontal zoom presets manager" -- temporary ExtState (not saved)
local INI_SECTION, INI_KEY = "toolbar button states", "Horizontal_Zoom_Presets_Manager"

local _, _, section_id, cmd_id = reaper.get_action_context()
-- Action ID of "Daniel_Horizontal zoom presets manager (toolbar toggle).lua" (from the Action List)
local toggle_cmd = reaper.NamedCommandLookup("_RS55232491fef7e93e7a593d1fffc9b0fe138f4aed")

local function set_toggle(state)
  reaper.SetToggleCommandState(section_id, cmd_id, state)
  reaper.RefreshToolbar2(section_id, cmd_id)
  if toggle_cmd ~= 0 then
    reaper.SetToggleCommandState(0, toggle_cmd, state)
    reaper.RefreshToolbar2(0, toggle_cmd)
  end
end

local function write_flag(v)
  if reaper.BR_Win32_WritePrivateProfileString then
    reaper.BR_Win32_WritePrivateProfileString(INI_SECTION, INI_KEY, tostring(v), reaper.get_ini_file())
  end
end

-- Running the script again stops the running window without asking
reaper.set_action_options(1 | 2)

-- Started again right after being stopped = "turn off" (toolbar button, shortcut, action list)
local stopped_at = tonumber(reaper.GetExtState(EXT, "stopped_at"))
if stopped_at and reaper.time_precise() - stopped_at < 1 then
  reaper.DeleteExtState(EXT, "stopped_at", false)
  set_toggle(0)
  write_flag(0)
  return
end

local closed_by_x = false
set_toggle(1)
write_flag(1)

reaper.atexit(function()
  set_toggle(0)
  if closed_by_x then
    write_flag(0)
  else
    reaper.SetExtState(EXT, "stopped_at", tostring(reaper.time_precise()), false)
  end
end)

local SECTION = "Daniel_Horizontal zoom presets" -- ExtState section shared with the preset scripts
local DEFAULTS = { 500, 160, 93, 46, 31 } -- same as the defaults inside the preset scripts
local LONG_PRESS = 0.5 -- seconds a button is held to save

---------------------------------------------------------------------------
-- Saved presets (reaper-extstate.ini)
---------------------------------------------------------------------------
local saved = {}

local function load_saved()
  saved = {}
  for i = 1, 5 do
    local v = tonumber(reaper.GetExtState(SECTION, "preset_" .. i))
    if v and v > 0 then saved[i] = v end
  end
end

local function store(i)
  if saved[i] then
    reaper.SetExtState(SECTION, "preset_" .. i, string.format("%.4f", saved[i]), true)
  else
    reaper.DeleteExtState(SECTION, "preset_" .. i, true)
  end
end

local function apply_zoom(pps)
  local view_start, view_end = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  local view_center = (view_start + view_end) / 2
  local view_width_px = (view_end - view_start) * reaper.GetHZoomLevel()
  local target_range = view_width_px / pps
  reaper.GetSet_ArrangeView2(0, true, 0, 0, view_center - target_range / 2, view_center + target_range / 2)
  if reaper.GetPlayState() & 1 == 0 then
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_HSCROLL50"), 0)
  end
end

load_saved()

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local ctx = reaper.ImGui_CreateContext("Horizontal zoom presets manager")

-- The window only moves by its title bar, so dragging an edge never moves it
if reaper.ImGui_ConfigVar_WindowsMoveFromTitleBarOnly then
  reaper.ImGui_SetConfigVar(ctx, reaper.ImGui_ConfigVar_WindowsMoveFromTitleBarOnly(), 1)
end

local os_name = reaper.GetOS()
local FAMILY = "DejaVu Sans"
if os_name:find("OSX") or os_name:find("macOS") then FAMILY = "Helvetica Neue"
elseif os_name:find("Win") then FAMILY = "Segoe UI" end

local _, _, imgui_ver = reaper.ImGui_GetVersion()
local vmaj, vmin = tostring(imgui_ver):match("^(%d+)%.(%d+)")
local NEW_FONT_API = (tonumber(vmaj) or 0) > 0 or (tonumber(vmin) or 0) >= 10

local function make_font(size, bold)
  local flags = bold and reaper.ImGui_FontFlags_Bold() or reaper.ImGui_FontFlags_None()
  local f
  if NEW_FONT_API then
    f = reaper.ImGui_CreateFont(FAMILY, flags)
  else
    f = reaper.ImGui_CreateFont(FAMILY, size, flags)
  end
  pcall(reaper.ImGui_Attach, ctx, f)
  return { f = f, size = size }
end

-- A few font sizes so the text can follow the window size
local F_BIG, F_NORM = {}, {}
for _, s in ipairs({ 12, 16, 20, 26, 34, 44, 56 }) do F_BIG[#F_BIG + 1] = make_font(s, true) end
for _, s in ipairs({ 12, 14, 17 }) do F_NORM[#F_NORM + 1] = make_font(s, false) end

local function pick_font(list, limit)
  local best = list[1]
  for _, ft in ipairs(list) do
    if ft.size <= limit then best = ft end
  end
  return best
end

local function push_font(ft)
  if NEW_FONT_API then reaper.ImGui_PushFont(ctx, ft.f, ft.size) else reaper.ImGui_PushFont(ctx, ft.f) end
end
local function pop_font() reaper.ImGui_PopFont(ctx) end

-- Colours (0xRRGGBBAA)
local C_BG        = 0x333333FF -- window background
local C_TITLE     = 0x2C2C2CFF
local C_BORDER    = 0x1F1F1FFF
local C_TEXT      = 0xE6E6E6FF
local C_HOVER     = 0x404040FF -- right-click menu row
local C_NUM       = 0xD2D2D2FF -- number on a default preset
local C_NUM_ON    = 0x74AAF3FF -- number on a custom preset
local C_NUM_SHADE = 0x00000070

-- Button look, measured from the reference image (an 18 px button):
-- a 1 px outline, a 1 px darker inner edge, then three flat bands (light, medium, dark).
-- "pressed" is the look while a long press saves: only the outline and inner edge change.
local KEY = {
  fill    = { 0x737373FF, 0x595959FF, 0x404040FF },
  normal  = { outline = 0x2C2C2CFF, edge = { 0x4F4F4FFF, 0x414141FF, 0x343434FF } },
  pressed = { outline = 0x2A2A2AFF, edge = { 0x585858FF, 0x474747FF, 0x373737FF } },
}

-- Proportions: button = 1 unit, gap = GAP units; one row of five buttons
local PAD = 8
local GAP = 0.22
local W_U, H_U = 5 + 4 * GAP, 1
local INIT_W, MIN_W = 230, 130
local GRIP = 6 -- width of the draggable edge zones, in px

local dock_request = nil
local hovered_slot = nil -- the button under the mouse this frame
local press = nil        -- the left press in progress: { i, t0, done }
local lit_until = {}     -- per button: keep the pressed look until this time
local DL

-- Height of the window (title bar + padding) that is not content
local function chrome_h() return reaper.ImGui_GetFrameHeight(ctx) + 2 * PAD end
-- Window height that matches a given window width, and the other way round
local function h_for(w) return (w - 2 * PAD) * H_U / W_U + chrome_h() end
local function w_for(h) return (h - chrome_h()) * W_U / H_U + 2 * PAD end

local function measure(ft, s)
  push_font(ft)
  local w, h = reaper.ImGui_CalcTextSize(ctx, s)
  pop_font()
  return w, h
end

local function put(ft, x, y, col, s)
  push_font(ft)
  reaper.ImGui_DrawList_AddText(DL, x, y, col, s)
  pop_font()
end

local function return_focus()
  if reaper.JS_Window_SetFocus then reaper.JS_Window_SetFocus(reaper.GetMainHwnd()) end
end

-- One button. The outline and the inner edge are drawn as rounded rectangles, then the
-- three bands are cut out of them with clip strips, so the corners stay round.
local function draw_key(x, y, w, h, pressed)
  local pal = pressed and KEY.pressed or KEY.normal
  local o = math.max(2, math.floor(h / 14 + 0.5)) -- outline thickness
  local rad = math.max(3, h * 0.16) -- corner radius
  local fy, fh = y + o, h - 2 * o
  local b1 = math.floor(fy + fh * 5 / 14 + 0.5) -- light band: 5 of 14 rows
  local b2 = math.floor(fy + fh * 9 / 14 + 0.5) -- medium band: 4 rows, dark band: 5 rows
  local strips = { { y - 2, b1 }, { b1, b2 }, { b2, y + h + 2 } }

  reaper.ImGui_DrawList_AddRectFilled(DL, x, y, x + w, y + h, pal.outline, rad)
  for i = 1, 3 do
    reaper.ImGui_DrawList_PushClipRect(DL, x - 2, strips[i][1], x + w + 2, strips[i][2], true)
    reaper.ImGui_DrawList_AddRectFilled(DL, x + o, y + o, x + w - o, y + h - o, KEY.fill[i], math.max(0, rad - o))
    reaper.ImGui_DrawList_PopClipRect(DL)
  end
end

local function draw()
  DL = reaper.ImGui_GetWindowDrawList(ctx)
  local x0, y0 = reaper.ImGui_GetCursorScreenPos(ctx)
  local aw, ah = reaper.ImGui_GetContentRegionAvail(ctx)

  -- Whole-pixel sizes keep the button edges crisp
  local u = math.max(8, math.min(aw / W_U, ah / H_U))
  local s = math.max(8, math.floor(u))
  local gap = math.max(2, math.floor(GAP * s + 0.5))
  local gx = math.floor(x0 + math.max(0, (aw - (5 * s + 4 * gap)) / 2) + 0.5)
  local gy = math.floor(y0 + math.max(0, (ah - s) / 2) + 0.5)
  local f_num = pick_font(F_BIG, s * 0.5)
  local now = reaper.time_precise()

  hovered_slot = nil
  for i = 1, 5 do
    local x = gx + (i - 1) * (s + gap)
    reaper.ImGui_SetCursorScreenPos(ctx, x, gy)
    reaper.ImGui_InvisibleButton(ctx, "slot" .. i, s, s)
    local hov = reaper.ImGui_IsItemHovered(ctx)
    if hov then hovered_slot = i end

    -- Left button: a short click loads, holding saves
    if reaper.ImGui_IsItemActivated(ctx) then press = { i = i, t0 = now, done = false } end
    if press and press.i == i then
      if reaper.ImGui_IsItemActive(ctx) then
        if not press.done and now - press.t0 >= LONG_PRESS then
          press.done = true
          saved[i] = reaper.GetHZoomLevel()
          store(i)
          lit_until[i] = now + 0.3
        end
      else
        if not press.done and hov then apply_zoom(saved[i] or DEFAULTS[i]) end
        press = nil
      end
    end

    -- Right button: reset to the default
    if hov and reaper.ImGui_IsMouseReleased(ctx, 1) then
      saved[i] = nil
      store(i)
      return_focus()
    end

    local lit = (press and press.i == i and press.done) or (lit_until[i] and now < lit_until[i])
    draw_key(x, gy, s, s, lit)

    -- The number, with a small shadow below it
    local num = tostring(i)
    local nw, nh = measure(f_num, num)
    local tx = math.floor(x + (s - nw) / 2 + 0.5)
    local ty = math.floor(gy + (s - nh) / 2 + 0.5)
    put(f_num, tx, ty + 1, C_NUM_SHADE, num)
    put(f_num, tx, ty, saved[i] and C_NUM_ON or C_NUM, num)
  end
end

---------------------------------------------------------------------------
-- Resizing
-- The window is resized by this script (not by ImGui): the left and right edges,
-- the bottom edge and the two bottom corners can be dragged, the top edge does
-- nothing. The new size is worked out from the mouse during a frame and applied at
-- the start of the NEXT frame, so the window never changes size in the middle of a
-- frame. The top-left corner stays put, except when dragging from the left, where
-- the right edge stays put. Width and height are always linked.
---------------------------------------------------------------------------
local rs = nil      -- the drag in progress
local pending = nil -- window size/position to apply at the start of the next frame

-- Mouse position for resizing, read from the operating system instead of from ImGui.
-- ImGui works its mouse position out from the window's position, and that position
-- changes on every frame while the left edge is dragged, which made that drag jerky.
local function mouse_pos()
  return reaper.ImGui_GetMousePos(ctx)
end

-- While dragging, only the OS mouse position is used (it never depends on where the window
-- is), so moving the window for a left-edge drag cannot feed back into the measurement.
-- kx / ky convert OS pixels to window units (ky also carries the sign: macOS counts y upwards).
local function native_scale(nx, ny)
  if not reaper.ImGui_PointConvertNative then return 1, 1 end
  local ax, ay = reaper.ImGui_PointConvertNative(ctx, nx, ny, false)
  local bx, by = reaper.ImGui_PointConvertNative(ctx, nx + 100, ny + 100, false)
  return (bx - ax) / 100, (by - ay) / 100
end

local function handle_resize()
  if reaper.ImGui_IsWindowDocked(ctx) then
    rs = nil
    return
  end
  local wx, wy = reaper.ImGui_GetWindowPos(ctx)
  local ww, wh = reaper.ImGui_GetWindowSize(ctx)
  local mx, my = mouse_pos()

  if rs then
    if reaper.ImGui_IsMouseDown(ctx, 0) then
      reaper.ImGui_SetMouseCursor(ctx, rs.cursor)
      -- the width each dragged side asks for; a corner uses the average of both
      local nx, ny = reaper.GetMousePosition()
      local dx, dy = (nx - rs.nx) * rs.kx, (ny - rs.ny) * rs.ky
      local w_x, w_y
      if rs.l then
        w_x = rs.w0 - dx
      elseif rs.r then
        w_x = rs.w0 + dx
      end
      if rs.b then w_y = w_for(rs.h0 + dy) end
      local w = (w_x and w_y) and (w_x + w_y) / 2 or w_x or w_y
      -- whole pixels only: fractional sizes make the window edge flicker between two pixels
      w = math.floor(math.max(w, MIN_W) + 0.5)
      local right = math.floor(rs.right + 0.5)
      pending = { w = w, h = math.floor(h_for(w) + 0.5), x = rs.l and (right - w) or math.floor(rs.x + 0.5), y = math.floor(rs.y + 0.5) }
    else
      rs = nil
      return_focus()
    end
    return
  end

  -- Not dragging: keep the window in shape (for example after undocking)
  local w = math.max(ww, MIN_W)
  if math.abs(wh - h_for(w)) > 2 or ww < MIN_W - 2 then pending = { w = w, h = h_for(w) } end

  -- Edge zones (never the top edge, and never the title bar)
  if reaper.ImGui_IsPopupOpen(ctx, "window_menu") or not reaper.ImGui_IsWindowHovered(ctx) then return end
  local below_title = my > wy + reaper.ImGui_GetFrameHeight(ctx)
  local l = below_title and mx < wx + GRIP
  local r = below_title and mx > wx + ww - GRIP
  local b = my > wy + wh - GRIP
  if not (l or r or b) then return end

  local cursor
  if b and (l or r) then
    cursor = l and reaper.ImGui_MouseCursor_ResizeNESW() or reaper.ImGui_MouseCursor_ResizeNWSE()
  elseif b then
    cursor = reaper.ImGui_MouseCursor_ResizeNS()
  else
    cursor = reaper.ImGui_MouseCursor_ResizeEW()
  end
  reaper.ImGui_SetMouseCursor(ctx, cursor)

  if reaper.ImGui_IsMouseClicked(ctx, 0) then
    local nx, ny = reaper.GetMousePosition()
    local kx, ky = native_scale(nx, ny)
    rs = { l = l, r = r, b = b, cursor = cursor, x = wx, y = wy, right = wx + ww,
      w0 = ww, h0 = wh, nx = nx, ny = ny, kx = kx, ky = ky }
  end
end

---------------------------------------------------------------------------
-- Right-click menu: dock / undock
-- (title bar when floating, any empty area when docked; a right click on a button resets it)
---------------------------------------------------------------------------
local MENU_W, MENU_H = 132, 28

local function window_menu()
  local docked = reaper.ImGui_IsWindowDocked(ctx)
  if reaper.ImGui_IsMouseReleased(ctx, 1) and reaper.ImGui_IsWindowHovered(ctx) and not hovered_slot then
    local on_title = false
    if not docked then
      local wx, wy = reaper.ImGui_GetWindowPos(ctx)
      local ww = reaper.ImGui_GetWindowSize(ctx)
      local mx, my = reaper.ImGui_GetMousePos(ctx)
      on_title = mx >= wx and mx <= wx + ww and my >= wy and my <= wy + reaper.ImGui_GetFrameHeight(ctx)
    end
    if docked or on_title then reaper.ImGui_OpenPopup(ctx, "window_menu") end
  end

  -- Dark rounded card with one row (rounded hover highlight)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 6, 6)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupRounding(), 10)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupBorderSize(), 1)
  local open = reaper.ImGui_BeginPopup(ctx, "window_menu")
  reaper.ImGui_PopStyleVar(ctx, 3)
  if not open then return end

  local pdl = reaper.ImGui_GetWindowDrawList(ctx)
  local label = docked and "Undock" or "Dock"
  local f = pick_font(F_NORM, 14)
  local _, th = measure(f, label)
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
  local clicked = reaper.ImGui_InvisibleButton(ctx, "dock_toggle", MENU_W, MENU_H)
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_DrawList_AddRectFilled(pdl, x, y, x + MENU_W, y + MENU_H, C_HOVER, 7)
  end
  push_font(f)
  reaper.ImGui_DrawList_AddText(pdl, x + 12, y + (MENU_H - th) / 2, C_TEXT, label)
  pop_font()

  if clicked then
    dock_request = docked and 0 or -1 -- 0 = floating, -1 = first docker
    reaper.ImGui_CloseCurrentPopup(ctx)
    return_focus()
  end
  reaper.ImGui_EndPopup(ctx)
end

local function loop()
  if dock_request then
    reaper.ImGui_SetNextWindowDockID(ctx, dock_request, reaper.ImGui_Cond_Always())
    dock_request = nil
  end
  if pending then
    reaper.ImGui_SetNextWindowSize(ctx, pending.w, pending.h, reaper.ImGui_Cond_Always())
    if pending.x then reaper.ImGui_SetNextWindowPos(ctx, pending.x, pending.y, reaper.ImGui_Cond_Always()) end
    pending = nil
  else
    reaper.ImGui_SetNextWindowSize(ctx, INIT_W, h_for(INIT_W), reaper.ImGui_Cond_FirstUseEver())
  end

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), C_BG)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(), C_TITLE)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(), C_TITLE)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgCollapsed(), C_TITLE)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), C_TEXT)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), C_TITLE)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), C_BORDER)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), PAD, PAD)

  local flags = reaper.ImGui_WindowFlags_NoCollapse() | reaper.ImGui_WindowFlags_NoScrollbar()
    | reaper.ImGui_WindowFlags_NoScrollWithMouse() | reaper.ImGui_WindowFlags_NoResize()
  local visible, open = reaper.ImGui_Begin(ctx, "Horizontal zoom presets manager", true, flags)
  if visible then
    draw()
    handle_resize()
    window_menu()
    -- Give keyboard focus back to REAPER after every click so shortcuts keep working
    if reaper.ImGui_IsMouseReleased(ctx, 0) and reaper.ImGui_IsWindowHovered(ctx) then return_focus() end
    reaper.ImGui_End(ctx)
  end

  reaper.ImGui_PopStyleVar(ctx, 1)
  reaper.ImGui_PopStyleColor(ctx, 7)

  if open then
    reaper.defer(loop)
  else
    closed_by_x = true
  end
end

reaper.defer(loop)
