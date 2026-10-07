-- @description Daniel_Floating Mixer
-- @version 1.0
-- @author Daniel
-- @about
--   # Floating Mixer
--   A floating mixer window that looks and works like REAPER's own mixer, drawn with the current
--   theme's images, colors and fonts (Default 7 theme family), and always in sync with the real mixer.
--
--   - Follow the selected tracks, or pick any tracks (and the master) to show side by side
--   - Snapshots: up to 64 numbered slots per project that remember which tracks are shown
--   - Several mixer windows at once (the + button); each project remembers its windows
--   - Each window can float or dock (right-click the title bar); position, size and tracks are remembered
--   - Faders, pan, meters, FX and send lists, routing, record arm / input, mute / solo, etc.,
--     with REAPER's own right-click menus where REAPER offers them
--   - Fader background colored by automation mode, folder tracks indented like the mixer, and
--     folders collapse / expand in sync with REAPER's mixer
--   - Running the action again closes the windows (works as a toolbar toggle)
--
--   Requirements: REAPER 7, ReaImGui 0.9.3 or newer (ReaPack).
--   Recommended: SWS (opens the SWS Snapshots window for mix snapshots) and js_ReaScriptAPI
--   (keeps your keyboard shortcuts working while you use the window).
--   Made for the Default 7 theme and themes based on it; other themes may not lay out correctly.

local r = reaper
if not r.ImGui_GetBuiltinPath then
  r.MB('This script requires the ReaImGui extension (install it via ReaPack).', 'Floating Mixer', 0)
  return
end
package.path = r.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9.3'

local SCRIPT_NAME = 'Floating Mixer'
-- One script can show several mixer windows (the + button). CUR_WIN is the number of the
-- window being drawn; window 1 uses the original setting names, so its saved position / dock / tracks carry over.
local CUR_WIN = 1
local function inst_key(k) return CUR_WIN == 1 and k or (k .. '_' .. CUR_WIN) end   -- per-window setting names
local ctx = ImGui.CreateContext('Daniel Floating Mixer')
local FONT_BASE = 18
local font_ui   = ImGui.CreateFont('sans-serif', 13)
local font_reg  = ImGui.CreateFont('sans-serif', FONT_BASE)
local font_bold = ImGui.CreateFont('sans-serif', FONT_BASE, ImGui.FontFlags_Bold)
ImGui.Attach(ctx, font_ui); ImGui.Attach(ctx, font_reg); ImGui.Attach(ctx, font_bold)
local font_list, LIST_PX = font_reg, 24   -- FX/send list font; replaced by the theme's lb_font once loaded
local state_list_fix     -- width correction for the name label if the theme's font isn't available
local font_label         -- track name label font (created before the first frame)
local font_rename        -- slightly smaller font for the inline rename field
ImGui.SetConfigVar(ctx, ImGui.ConfigVar_WindowsMoveFromTitleBarOnly, 1)
ImGui.SetConfigVar(ctx, ImGui.ConfigVar_DockingWithShift, 1)   -- no dock previews while dragging (Shift+drag still docks)

local _, _, sec_id, cmd_id = r.get_action_context()

-- Toolbar sync: the toolbar button runs the separate "(toolbar toggle)" script. This script keeps that
-- button (and its own toggle state) matching whether the mixer is really open, however it was started or closed.
do
local TOGGLE_KEY = 'Floating_Mixer'                    -- the key in reaper.ini that the startup action reads
-- the toolbar button's script: Daniel_Floating Mixer (toolbar toggle).lua
local TOGGLE_BUTTON = '_RS973b18e586205dfc84710f0cc614eb97f048d2ec'
local function toggle_button_id()
  local id = r.NamedCommandLookup(TOGGLE_BUTTON)
  if id and id ~= 0 then return id end
end
local function set_visual_state(on)
  local v = on and 1 or 0
  r.SetToggleCommandState(sec_id, cmd_id, v); r.RefreshToolbar2(sec_id, cmd_id)
  local tid = toggle_button_id()
  if tid then r.SetToggleCommandState(0, tid, v); r.RefreshToolbar2(0, tid) end
end
local REAPER_INI = r.GetResourcePath() .. "/reaper.ini"
-- Sets KEY=value in reaper.ini, in the [toolbar button states] section. If the line isn't
-- there yet, it's added to that section (and the section is added at the end if it's missing).
local function SetIniValue(key, value)
  local file = io.open(REAPER_INI, "rb")
  if not file then return false end
  local contents = file:read("*all")
  file:close()
  value = tostring(value)

  local new_contents, count = contents:gsub(
    "(\n" .. key .. "=)[^\r\n]*",
    function(prefix) return prefix .. value end
  )
  if count == 0 then
    local nl = contents:find("\r\n", 1, true) and "\r\n" or "\n"
    local header = "[toolbar button states]"
    local s = (contents:sub(1, #header) == header) and 1 or contents:find("\n" .. header, 1, true)
    if s then
      local eol = contents:find("\n", s + (s == 1 and 0 or 1), true)
      if not eol then contents = contents .. nl; eol = #contents end   -- header was the last line
      new_contents = contents:sub(1, eol) .. key .. "=" .. value .. nl .. contents:sub(eol + 1)
    else
      if contents ~= "" and not contents:match("\n$") then contents = contents .. nl end
      new_contents = contents .. header .. nl .. key .. "=" .. value .. nl
    end
  end
  if new_contents == contents then return true end

  file = io.open(REAPER_INI, "wb")
  if not file then return false end
  file:write(new_contents)
  file:close()
  return true
end
local function write_ini_flag(on) SetIniValue(TOGGLE_KEY, on and 1 or 0) end
-- Running the action while the mixer is open turns it off. REAPER stops the running script and, with
-- set_action_options(1 + 2), starts it again right away; the stopped one left the time it stopped, so
-- this new start knows it's a "turn off": it writes 0 and doesn't open. (REAPER quitting stops the
-- script without starting it again, so the flag stays 1 and the mixer comes back at the next startup.)
local stopped_at = tonumber(r.GetExtState('Daniel_FloatingMixer', 'stopped_at'))
r.DeleteExtState('Daniel_FloatingMixer', 'stopped_at', false)
if stopped_at and r.time_precise() - stopped_at < 1 then
  set_visual_state(false)
  write_ini_flag(false)
  return
end
set_visual_state(true)
write_ini_flag(true)
DFM_closed_by_user = false   -- (global) set when the last window is closed with its X (see loop)
r.atexit(function()
  set_visual_state(false)
  if DFM_closed_by_user then
    write_ini_flag(false)                        -- closed with X: stays closed
  else                                           -- stopped by running it again (or REAPER quitting)
    r.SetExtState('Daniel_FloatingMixer', 'stopped_at', tostring(r.time_precise()), false)
  end
end)
end
-- launching the script again while it runs closes it (a toggle), without REAPER's dialog:
-- 1 = stop the running one, 2 = then start this one (which sees it was a "turn off", above)
if r.set_action_options then r.set_action_options(1 | 2) end

--------------------------------------------------------------------------------
-- Look settings (measured from the Default 7 MCP at 100%)
--------------------------------------------------------------------------------
local DESIGN_W   = 172   -- set per strip from the theme's mixer width

local COL = {
  bg = 0x262626FF, groove = 0x000000FF, btn = 0x575757FF, btn_dark = 0x3A3D3DFF,
  btn_light = 0x686C6CFF, env = 0x787B7BFF, border = 0x141414FF,
  text_vol = 0xA8A8A8FF, text_peak = 0x7A7A7AFF, text_btn = 0xC8C8C8FF, text_label = 0x949494FF,
  meter_unlit = 0x402820FF, meter_green = 0x23A101FF, meter_yel = 0xD8C000FF, meter_red = 0xFF4000FF,
  mark_unlit = 0xFF4000FF, mark_lit = 0x0E3A00FF,
  route_active = 0xCC7A29FF, pan_ptr = 0x8E67FFFF, knob_ring = 0x2A2A2AFF,
  mute_on = 0xD93627FF, solo_on = 0xE8C83AFF, rec_on = 0xD93627FF, phase_on = 0xCC7A29FF,
  fxbyp_on = 0xCC7A29FF, infx = 0xC9C1C1FF, infx_on = 0x9ED49EFF,
}
local AUTO = { [0] = { 'Trim/Read', 'TRIM', 0x949494FF }, { 'Read', 'READ', 0x5CC878FF },
  { 'Touch', 'TOUCH', 0xE8C83AFF }, { 'Write', 'WRITE', 0xE04A4AFF },
  { 'Latch', 'LATCH', 0xB57BE8FF }, { 'Latch Preview', 'PREVIEW', 0x6C9CE8FF } }
local RECMODE = { [0] = { 'in', 'Input (audio or MIDI)' }, { 'out', 'Output (stereo)' },
  { 'none', 'Disable (input monitoring only)' }, { 'out lc', 'Output (stereo, latency compensated)' },
  { 'midi', 'Output (MIDI)' }, { 'mono', 'Output (mono)' }, { 'mono lc', 'Output (mono, latency compensated)' },
  { 'odub', 'MIDI overdub' }, { 'repl', 'MIDI replace' }, { 'touch', 'MIDI touch-replace' },
  { 'multi', 'Output (multichannel)' }, { 'multi lc', 'Output (multichannel, latency compensated)' } }

--------------------------------------------------------------------------------
-- Math / value conversion (WDL math + REAPER's own fader curve)
--------------------------------------------------------------------------------
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function val2db(v)
  if not v or v < 0.0000000298023223876953125 then return -150.0 end
  local d = math.log(v) * 8.6858896380650365530225783783321
  return d < -150 and -150.0 or d
end
local function db2val(d) return math.exp(d * 0.11512925464970228420089957273422) end
local function pos_of(db) if db <= -149.9 then return 0 end return clamp(r.DB2SLIDER(db) / 1000, 0, 1) end
local function vol_of_pos(p) if p <= 0 then return 0 end return db2val(r.SLIDER2DB(p * 1000)) end
local function max_db() return r.SLIDER2DB(1000) end

local function fmt_vol(d) if d <= -149.9 then return '-inf dB' end
  local s = string.format('%.2f', d); if s == '-0.00' then s = '0.00' end; return s .. 'dB' end
local function fmt_peak(d) if d <= -149.9 then return '-inf' end
  local s = string.format('%.1f', d); if s == '-0.0' then s = '0.0' end; return s end
local function fmt_pan(p, suffix_c)
  local pct = math.floor(math.abs(p) * 100 + 0.5)
  if pct == 0 then return suffix_c or 'center' end
  return pct .. '%' .. (p < 0 and 'L' or 'R')
end

--------------------------------------------------------------------------------
-- Writers (UI path = touch automation, groups and selection ganging like the MCP)
--------------------------------------------------------------------------------
local IGN = 0  -- 1|2 to ignore groups / selection ganging
local function set_vol(tr, v, done)   r.SetTrackUIVolume(tr, clamp(v, 0, db2val(max_db())), false, done and true or false, IGN) end
local function set_pan(tr, v, done)   r.SetTrackUIPan(tr, clamp(v, -1, 1), false, done and true or false, IGN) end
local function set_width(tr, v, done) r.SetTrackUIWidth(tr, clamp(v, -1, 1), false, done and true or false, IGN) end
local function undo_wrap(desc, fn) r.Undo_BeginBlock(); fn(); r.Undo_EndBlock(desc, 1) end

--------------------------------------------------------------------------------
-- Colors / tint (Default 7 tints panels with the track color)
--------------------------------------------------------------------------------
local TR, TG, TB = 1, 1, 1
local track_rgba
local function rgba(R, G, B, A)
  return (math.floor(clamp(R, 0, 255) + 0.5) << 24) | (math.floor(clamp(G, 0, 255) + 0.5) << 16)
       | (math.floor(clamp(B, 0, 255) + 0.5) << 8) | (A or 255)
end
local function shade(c, d)
  return rgba(((c >> 24) & 255) + d, ((c >> 16) & 255) + d, ((c >> 8) & 255) + d, c & 255)
end
local function set_tint(tr)
  local c = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_CUSTOMCOLOR'))
  if c & 0x1000000 == 0 then TR, TG, TB, track_rgba = 1, 1, 1, nil; return end
  local R, G, B = r.ColorFromNative(c & 0xFFFFFF)
  local m = math.max(R, G, B, 1)
  TR, TG, TB = R / m, G / m, B / m
  track_rgba = rgba(R, G, B)
end
-- gray level L tinted toward the track color by 'sat'
local function T(L, sat, A)
  return rgba(L * (1 - sat * (1 - TR)), L * (1 - sat * (1 - TG)), L * (1 - sat * (1 - TB)), A)
end

--------------------------------------------------------------------------------
-- Drawing helpers (design coordinates -> screen)
--------------------------------------------------------------------------------
local G = {}
local function X(v) return G.ox + v * G.s end
local function Y(v) return G.oy + v * G.s end

-- track name label only: the theme's face; if that face isn't on this system the substitute is
-- narrowed to its width (REAPER's label measured 67 px vs 80 px for the substitute)
local function label_fix(fnt)
  if state_list_fix then return state_list_fix end
  local sample = 'fsfdfg dsddssdds'
  ImGui.PushFont(ctx, fnt);      local a = ImGui.CalcTextSize(ctx, sample); ImGui.PopFont(ctx)
  ImGui.PushFont(ctx, font_reg); local b = ImGui.CalcTextSize(ctx, sample); ImGui.PopFont(ctx)
  state_list_fix = (a / b > 0.95) and 0.87 or 1
  return state_list_fix
end

local function list_name_font(kind)
  local f = font_label or font_list
  local sub = label_fix(f) ~= 1           -- true when the theme's face isn't available
  if not sub then return f, 1 end
  return f, (kind == 'fx') and 0.95 or 0.95   -- matched to REAPER's FX and send names
end

local function text_size(fnt, size, str)
  ImGui.PushFont(ctx, fnt); local w, h = ImGui.CalcTextSize(ctx, str); ImGui.PopFont(ctx)
  local k = size * G.s / (G.font_base or FONT_BASE)   -- the size the fonts were made at (see sync_fonts)
  return w * k, h * k
end
local function fit(fnt, size, str, maxw)
  if text_size(fnt, size, str) <= maxw then return str end
  while #str > 1 and text_size(fnt, size, str .. '..') > maxw do str = str:sub(1, -2) end
  return str .. '..'
end
-- x,y screen; y is vertical center; align 'l','c','r'
local function text(fnt, size, x, y, col, str, align)
  local w, h = text_size(fnt, size, str)
  if align == 'c' then x = x - w / 2 elseif align == 'r' then x = x - w end
  ImGui.DrawList_AddTextEx(G.dl, fnt, size * G.s, x, y - h / 2, col, str)
end
local function clip_text(fnt, size, x, y, col, str, xmax)
  ImGui.DrawList_PushClipRect(G.dl, x, y - size * G.s, xmax, y + size * G.s, true)
  text(fnt, size, x, y, col, str)
  ImGui.DrawList_PopClipRect(G.dl)
end
-- A horizontal hairline exactly one physical pixel tall, snapped to the pixel grid (x1, x2, y in screen
-- coordinates). A half-point line (1 design unit) is one real pixel on a 2x screen, but on a 1x screen it's
-- half a pixel and comes and goes as its position shifts; this draws the same 1 px line on every screen.
-- (kept on G: the main chunk is close to Lua's 200-local limit)
G.hline = function(x1, x2, y, col)
  local dpi = 1
  if ImGui.GetWindowDpiScale then dpi = math.max(1, ImGui.GetWindowDpiScale(ctx) or 1) end
  local px = 1 / dpi
  local sy = math.floor(y * dpi + 0.5) / dpi
  ImGui.DrawList_AddRectFilled(G.dl, x1, sy, x2, sy + px, col)
end

local function rect(x1, y1, x2, y2, col, rnd, flags)
  ImGui.DrawList_AddRectFilled(G.dl, x1, y1, x2, y2, col, rnd or 0, flags or 0)
end

local drag = {}
local function mods() return ImGui.GetKeyMods(ctx) end
local function is_fine() return (mods() & ImGui.Mod_Shift) ~= 0 end
local function is_alt()  return (mods() & ImGui.Mod_Alt) ~= 0 end
local function is_ctrl() return (mods() & ImGui.Mod_Ctrl) ~= 0 end

local function hit(id, x1, y1, x2, y2, tip)
  ImGui.SetCursorScreenPos(ctx, x1, y1)
  local clicked = ImGui.InvisibleButton(ctx, id, math.max(1, x2 - x1), math.max(1, y2 - y1))
  local hov = ImGui.IsItemHovered(ctx)
  if tip and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayNormal) and not ImGui.IsItemActive(ctx) then
    ImGui.SetTooltip(ctx, tip)
  end
  return { click = clicked, hov = hov, act = ImGui.IsItemActive(ctx),
    activated = ImGui.IsItemActivated(ctx), deactivated = ImGui.IsItemDeactivated(ctx),
    rclick = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right),
    dbl = hov and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) }
end

-- generic drag: per_dx / per_dy = value change per screen pixel
-- REAPER Preferences > Editing Behavior > Mouse: "Ignore mousewheel on (all / track panel) faders".
-- Stored in mousewheelmode; bits 1 and 2 are those options (yours: 1026 -> ignoring). Re-read every few seconds.
local wheel_cache, wheel_t = nil, 0
local function wheel_on_faders()
  local now = r.time_precise()
  if wheel_cache == nil or now - wheel_t > 3 then
    wheel_t = now
    local v = 0
    if r.get_config_var_string then
      local ok, sv = r.get_config_var_string('mousewheelmode')
      v = (ok and tonumber(sv)) or 0
    end
    wheel_cache = (math.floor(v) & 3) == 0
  end
  return wheel_cache
end

local function drag_value(id, h, v, lo, hi, reset, per_dx, per_dy, wheel_step)
  id = (G.sid or '') .. id
  local nv, done
  if h.activated then drag[id] = v; if is_alt() then drag[id] = reset; nv = reset end end
  if h.dbl then drag[id] = reset; nv = reset end
  if h.act and drag[id] then
    local dx, dy = ImGui.GetMouseDelta(ctx)
    local d = (dx * per_dx - dy * per_dy) * (is_fine() and 0.1 or 1)
    if d ~= 0 then drag[id] = clamp(drag[id] + d, lo, hi); nv = drag[id] end
  end
  if h.deactivated and drag[id] then nv = drag[id]; done = true; drag[id] = nil end
  if h.hov and not h.act and wheel_on_faders() then
    local w = ImGui.GetMouseWheel(ctx)
    if w ~= 0 then nv = clamp(v + w * wheel_step * (is_fine() and 0.2 or 1), lo, hi); done = true end
  end
  return nv, done
end

local function btn_bg(x1, y1, x2, y2, h, base)
  local rnd = 3 * G.s
  if h then
    if h.act then base = shade(base, -16) elseif h.hov then base = shade(base, 14) end
  end
  rect(x1 - 1, y1 - 1, x2 + 1, y2 + 1, COL.border, rnd)
  rect(x1, y1, x2, y2, base, rnd)
  rect(x1, y1, x2, (y1 + y2) / 2, shade(base, 12), rnd, ImGui.DrawFlags_RoundCornersTop)
  ImGui.DrawList_AddLine(G.dl, x1 + rnd, y1 + 1, x2 - rnd, y1 + 1, shade(base, 30))
end


--------------------------------------------------------------------------------
-- Theme images: loaded straight from the active REAPER theme
--------------------------------------------------------------------------------
local LIST_TINT = 0       -- FX/send slot images are drawn untinted, like the mixer
local Theme = { file = nil, dir = nil, ini = nil, imgs = {}, next_check = 0, layouts = {}, colors = {}, lay = {} }
-- design units = pixels of the theme's 200% images
local VARIANTS = { { scale = 200, sub = '200/', k = 1 }, { scale = 150, sub = '150/', k = 200 / 150 },
                   { scale = 100, sub = '', k = 2 } }

local function file_exists(p) local f = io.open(p, 'rb'); if f then f:close(); return true end end
-- fingerprint of a zip: its size + the zip's own table of contents (central directory), which holds
-- the CRC32 checksum, size and date of every file inside. Any change to any file inside changes it.
-- Only the end of the zip is read, so it stays fast even for big themes.
local function zip_stamp(p)
  local f = io.open(p, 'rb'); if not f then return '' end
  local n = f:seek('end')
  local tail_len = math.min(n, 65557)                       -- end record + max comment length
  f:seek('set', n - tail_len)
  local tail = f:read(tail_len) or ''
  local pos, e = nil, 1
  while true do local s = tail:find('PK\5\6', e, true); if not s then break end; pos, e = s, s + 1 end
  local cd = ''
  if pos and pos + 21 <= #tail then
    local cd_size, cd_off = string.unpack('<I4I4', tail, pos + 12)
    if cd_off + cd_size <= n then f:seek('set', cd_off); cd = f:read(cd_size) or '' end
  end
  f:close()
  local h1, h2 = 5381, 0                                   -- two simple 32-bit hashes over the directory
  for i = 1, #cd do
    local b = cd:byte(i)
    h1 = (h1 * 33 + b) & 0xFFFFFFFF
    h2 = (h2 + b * i) & 0xFFFFFFFF
  end
  return string.format('%d-%d-%08x%08x', n, #cd, h1, h2)
end
local function read_all(p) local f = io.open(p, 'rb'); if not f then return end
  local d = f:read('a'); f:close(); return d end
local function write_all(p, d) local f = io.open(p, 'wb'); if f then f:write(d); f:close() end end

local function find_theme_dir(dir, depth)
  r.EnumerateFiles(dir, -1)
  if file_exists(dir .. '/rtconfig.txt') or file_exists(dir .. '/mcp_volthumb.png') then return dir end
  if depth <= 0 then return end
  local i = 0
  while true do
    local sub = r.EnumerateSubdirectories(dir, i)
    if not sub then break end
    local f = find_theme_dir(dir .. '/' .. sub, depth - 1)
    if f then return f end
    i = i + 1
  end
end

local function extract_zip(zip, dest)
  r.RecursiveCreateDirectory(dest, 0)
  local cmd
  if r.GetOS():match('Win') then
    cmd = 'tar -xf "' .. zip .. '" -C "' .. dest .. '"'
  elseif r.GetOS():match('OSX') or r.GetOS():match('mac') then
    cmd = '/usr/bin/unzip -o -qq "' .. zip .. '" -d "' .. dest .. '"'
  else
    cmd = 'unzip -o -qq "' .. zip .. '" -d "' .. dest .. '"'
  end
  r.ExecProcess(cmd, 120000)
end

local function find_ini(dir)
  if not dir then return end
  r.EnumerateFiles(dir, -1)
  local i = 0
  while true do
    local f = r.EnumerateFiles(dir, i)
    if not f then return end
    if f:lower():match('%.reapertheme$') then return dir .. '/' .. f end
    i = i + 1
  end
end

-- returns image folder, .ReaperTheme file
local function resolve_theme_dir(tf)
  if not tf or tf == '' then return end
  local low = tf:lower()
  local base = tf:gsub('%.[Rr][Ee][Aa][Pp][Ee][Rr][Tt][Hh][Ee][Mm][Ee][Zz][Ii][Pp]$', '')
  base = base:gsub('%.[Rr][Ee][Aa][Pp][Ee][Rr][Tt][Hh][Ee][Mm][Ee]$', '')
  local ini = low:match('%.reapertheme$') and tf or nil
  local d = find_theme_dir(base, 2)                     -- unpacked theme folder
  if d then return d, ini end
  local zip = (low:match('%.reaperthemezip$') and tf) or (file_exists(base .. '.ReaperThemeZip') and base .. '.ReaperThemeZip')
  if not zip then return nil, ini end
  local name = base:match('([^/\\]+)$') or 'theme'
  local dest = r.GetResourcePath() .. '/Data/Daniel_FloatingMixer/theme_cache/' .. name
  local stamp = zip_stamp(zip)
  if read_all(dest .. '/.stamp') ~= stamp or not find_theme_dir(dest, 3) then
    extract_zip(zip, dest)
    write_all(dest .. '/.stamp', stamp)
  end
  return find_theme_dir(dest, 3), ini or find_ini(dest)
end

-- Layout "name" "image folder" lines from rtconfig (e.g. 'A_Red Fader (mixer only)' -> 'red 100')
local function layout_key(name)
  local k = name:gsub(' 200%%', ''):gsub(' 150%%', ''):gsub('^200%%_', ''):gsub('^150%%_', '')
  return k
end
local function parse_layouts(dir)
  local L = {}
  local d = dir and read_all(dir .. '/rtconfig.txt') or ''
  for line in d:gmatch('[^\r\n]+') do
    local _, name, rest = line:match('^%s*[Ll]ayout%s+(["\'])(.-)%1(.*)$')
    if name then
      local _, folder = rest:match('^%s*(["\'])(.-)%1')
      if folder and folder ~= '' then
        local scale = name:find('200%%') and 200 or (name:find('150%%') and 150 or 100)
        local key = layout_key(name)
        L[key] = L[key] or {}
        L[key][scale] = folder
      end
    end
  end
  return L
end

-- colors from the .ReaperTheme file (Windows COLORREF = 0x00BBGGRR)
local function parse_colors(ini)
  local c = {}
  local d = ini and read_all(ini)
  if d then for k, v in d:gmatch('([%w_]+)=(%-?%d+)') do c[k] = tonumber(v) end end
  return c
end
local function theme_col(key, fallback)
  if r.GetThemeColor then
    local c = r.GetThemeColor(key, 0)
    if c and c >= 0 then
      local R, G, B = r.ColorFromNative(c)
      return rgba(R, G, B)
    end
  end
  local v = Theme.colors[key]
  if not v or v < 0 then return fallback end
  v = math.floor(v)
  return rgba(v & 255, (v >> 8) & 255, (v >> 16) & 255)
end

-- Reads the pink/yellow control pixels REAPER themes use (via REAPER's gfx image API)
local function analyze(path)
  local slot = 1000
  if gfx.loadimg(slot, path) < 0 then return end
  local w, h = gfx.getimgdim(slot)
  if not w or w < 1 then return end
  local old = gfx.dest
  gfx.dest = slot
  local function mk(x, y)
    gfx.x, gfx.y = x, y
    local R, G, B = gfx.getpixel()
    if R > 0.9 and G < 0.1 and B > 0.9 then return 'P' end
    if R > 0.9 and G > 0.9 and B < 0.1 then return 'Y' end
  end
  local a = { w = w, h = h, x0 = 0, y0 = 0, x1 = w, y1 = h, L = 0, T = 0, R = 0, B = 0 }
  if mk(0, 0) then
    -- 1px control border on all sides; pink runs give margins / fixed (non-stretch) sizes
    a.x0, a.y0, a.x1, a.y1 = 1, 1, w - 1, h - 1
    local function run(x, y, dx, dy, max)
      local n = 0
      while n < max and mk(x + dx * n, y + dy * n) == 'P' do n = n + 1 end
      return n
    end
    a.L = run(1, 0, 1, 0, w - 2);     a.T = run(0, 1, 0, 1, h - 2)
    a.R = run(w - 2, h - 1, -1, 0, w - 2); a.B = run(w - 1, h - 2, 0, -1, h - 2)
  elseif mk(w - 1, 0) then
    a.x1 = w - 1   -- fader-thumb style: control column on the right only
  end
  gfx.dest = old
  return a
end

local function load_path(p, k)
  local c = Theme.imgs[p]
  if c ~= nil then return c or nil end
  local res = false
  if file_exists(p) then
    local a = analyze(p)
    local ok, im = pcall(ImGui.CreateImage, p)
    if a and ok and im then
      ImGui.Attach(ctx, im)
      a.img, a.k = im, k
      a.tiny = a.w <= 12 and a.h <= 22        -- tiny blank "nothing here" images
      res = a
    end
  end
  Theme.imgs[p] = res
  return res or nil
end

-- same lookup order as REAPER: the track layout's image folder first, then the theme folder
local function load(name)
  if not Theme.dir then return end
  for _, v in ipairs(VARIANTS) do
    local lf = Theme.lay[v.scale]
    if lf then
      local a = load_path(Theme.dir .. '/' .. lf .. '/' .. name .. '.png', v.k)
      if a then return a end
    end
    local a = load_path(Theme.dir .. '/' .. v.sub .. name .. '.png', v.k)
    if a then return a end
  end
end

-- a single image (knobs, arrows, list slots...)
local function img(...)
  for i = 1, select('#', ...) do
    local a = load((select(i, ...)))
    if a and not a.tiny then return a end
  end
end

-- a button: REAPER draws the base image, then the _ol overlay on top of it
local function bimg(...)
  for i = 1, select('#', ...) do
    local n = select(i, ...)
    local b, o = load(n), load(n .. '_ol')
    if b and b.tiny then b = nil end
    if o and o.tiny then o = nil end
    if b or o then return { base = b, ol = o } end
  end
end

local function set_track_layout(tr)
  local _, lay = r.GetSetMediaTrackInfo_String(tr, 'P_MCP_LAYOUT', '', false)
  local def = 'A'
  if r.ThemeLayout_GetLayout then
    local ok, d = r.ThemeLayout_GetLayout('mcp', -1)   -- theme's default mixer layout
    if ok and d and d ~= '' then def = d end
  end
  if tr ~= r.GetMasterTrack(0) then
    -- tracks use the theme's default layout (A), whatever the mixer uses (B / C would break the strip),
    -- except its colored-fader versions (e.g. 'A_Blue Fader (mixer only)', set by SWS auto layout):
    -- those keep layout A's shape, only their images (fader cap) differ
    local dl = (def:gsub('^%d+%%_', '')):match('^%a') or 'A'
    local own = lay:gsub('^%d+%%_', '')
    if not own:match('^' .. dl .. '_') then lay = '' end
  end
  if lay == '' then lay = def end
  Theme.lay = (lay ~= '' and Theme.layouts[layout_key(lay)]) or {}
end

-- theme parameters as set in REAPER (Theme adjuster): same values the theme's rtconfig uses
local function read_params()
  local P, i = {}, 0
  while true do
    local name, _, val = r.ThemeLayout_GetParameter(i)
    if not name or name == '' then break end
    P[name] = val
    i = i + 1
  end
  Theme.P = P
end

local function theme_check()
  local now = r.time_precise()
  if now < Theme.next_check then return end
  Theme.next_check = now + 1.5
  read_params()
  local tf = r.GetLastColorThemeFile()
  if tf == Theme.file then return end
  for _, a in pairs(Theme.imgs) do if a and a.img then pcall(ImGui.Detach, ctx, a.img) end end
  Theme.imgs, Theme.file = {}, tf
  Theme.dir, Theme.ini = resolve_theme_dir(tf)
  Theme.layouts = parse_layouts(Theme.dir)
  Theme.colors = parse_colors(Theme.ini)
  -- list font: the theme's lb_font (a Windows LOGFONT stored as hex). Height is at 100%, x2 for design units.
  local hex = Theme.ini and (read_all(Theme.ini) or ''):match('\nlb_font=(%x+)')
  if hex and #hex >= 92 then
    local b = {}
    for i = 1, #hex, 2 do b[#b + 1] = tonumber(hex:sub(i, i + 1), 16) end
    local hgt = b[1] | (b[2] << 8) | (b[3] << 16) | (b[4] << 24)
    if hgt >= 0x80000000 then hgt = hgt - 0x100000000 end
    local face = {}
    for i = 29, math.min(#b, 60) do
      if b[i] == 0 then break end
      face[#face + 1] = string.char(b[i])
    end
    face = table.concat(face)
    if hgt ~= 0 then LIST_PX = math.abs(hgt) * 2 end
    -- theme font table: 1 = lb_font, 2 = lb_font2, 3.. = user_fontN (the rtconfig adds +10 at 200% scale)
    Theme.font_px = {}
    local d = read_all(Theme.ini) or ''
    local function px_of(key)
      local hx = d:match('\n' .. key .. '=(%x+)')
      if not hx or #hx < 8 then return end
      local v = tonumber(hx:sub(1, 2), 16) | (tonumber(hx:sub(3, 4), 16) << 8) | (tonumber(hx:sub(5, 6), 16) << 16) | (tonumber(hx:sub(7, 8), 16) << 24)
      if v >= 0x80000000 then v = v - 0x100000000 end
      return math.abs(v)
    end
    Theme.font_px[1] = px_of('lb_font'); Theme.font_px[2] = px_of('lb_font2')
    for i = 3, 20 do Theme.font_px[i] = px_of('user_font' .. i) end
    if face ~= '' and face ~= Theme.face then
      Theme.face = face
      local ok, f = pcall(ImGui.CreateFont, face, G.font_base or FONT_BASE)
      if ok and f and pcall(ImGui.Attach, ctx, f) then font_list = f end
    end
  end
end


--------------------------------------------------------------------------------
-- Theme rules (ported from the Default 7 rtconfig, using your theme parameters)
--------------------------------------------------------------------------------
local function tp(name, def) local v = Theme.P and Theme.P[name]; if v == nil then return def end; return v end
local function lp(name, def) return tp('Layout' .. (G.layout or 'A') .. '-' .. name, def) end
local function tbm() return tp('textBrightness', 100) / 100 end
-- size (design units = 200% pixels) of the theme's font index, as the rtconfig picks it at 200%: index + 10
local function fpx(idx, fallback)
  local f = Theme.font_px and Theme.font_px[idx + 10]
  return f and f > 0 and f or fallback
end
local function gray(v, a) v = clamp(v * tbm(), 0, 255); return rgba(v, v, v, a) end
local function brightness(R, G_, B) return 0.299 * R + 0.587 * G_ + 0.114 * B end

-- mcpMainSecCol: theme background mixed with the track color (Custom Color Strength) + selection overlay
local function main_sec_rgb(tr, nosel)   -- nosel: the color without the selection brightening
  local ratio = track_rgba and tp('customColorDepthParam', 30) / 100 or 0
  local sel = (not nosel and r.IsTrackSelected(tr)) and tp('selectStrength', 25) / 100 or 0
  local tR, tG, tB = 0, 0, 0
  if track_rgba then tR, tG, tB = (track_rgba >> 24) & 255, (track_rgba >> 16) & 255, (track_rgba >> 8) & 255 end
  local function mix(t, b) return (1 - sel) * (ratio * t + (1 - ratio) * b) + sel * 255 end
  return mix(tR, tp('mcpBgColR', 129)), mix(tG, tp('mcpBgColG', 137)), mix(tB, tp('mcpBgColB', 137))
end

--------------------------------------------------------------------------------
-- Track helpers
--------------------------------------------------------------------------------
local tracks_menu, route_target, keep_reaper_focus
local state = { vol_buf = '', name_buf = '', focus = false }

local function track_from_guid(guid)
  local m = r.GetMasterTrack(0)
  if r.GetTrackGUID(m) == guid then return m end
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i); if r.GetTrackGUID(t) == guid then return t end
  end
end
-- helper tracks of other scripts never show up here (not in the list, not when selected)
do
  local HIDDEN_TRACKS = { ['always recording (auto)'] = true }
  state.hidden_track = function(tr)
    if not tr or tr == r.GetMasterTrack(0) then return false end
    local _, nm = r.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', false)
    return HIDDEN_TRACKS[nm:lower()] == true
  end
end
-- mode 'follow' = the selected tracks (one or several); 'list' = tracks you picked (saved in the project)
local function load_choice()
  local _, mode = r.GetProjExtState(0, 'Daniel_FloatingMixer', inst_key('mode'))
  local _, list = r.GetProjExtState(0, 'Daniel_FloatingMixer', inst_key('tracks'))
  if CUR_WIN > 1 and (mode or '') == '' then   -- a new window starts with window 1's choice; after that it's its own
    _, mode = r.GetProjExtState(0, 'Daniel_FloatingMixer', 'mode')
    _, list = r.GetProjExtState(0, 'Daniel_FloatingMixer', 'tracks')
  end
  state.mode = (mode == 'list') and 'list' or 'follow'
  state.list = {}
  for g in (list or ''):gmatch('[^,]+') do state.list[#state.list + 1] = g end
end
local function save_choice()
  r.SetProjExtState(0, 'Daniel_FloatingMixer', inst_key('mode'), state.mode)
  r.SetProjExtState(0, 'Daniel_FloatingMixer', inst_key('tracks'), table.concat(state.list, ','))
end
local function in_list(g) for k, v in ipairs(state.list) do if v == g then return k end end end
local function toggle_in_list(g)
  local k = in_list(g)
  if k then table.remove(state.list, k) else state.list[#state.list + 1] = g end
  state.mode = 'list'; save_choice()
end

--------------------------------------------------------------------------------
-- Folder collapse in the mixer. It's REAPER's own state, shared with the real mixer: the track's
-- "BUSCOMP" line, 2nd value (1 = children hidden in the mixer). There is no API value for it, so it is
-- read from the track's state (undo-style, which is light) and checked again every half second.
--------------------------------------------------------------------------------
local mcp_comp = {}
local function is_folder(tr) return tr ~= r.GetMasterTrack(0) and r.GetMediaTrackInfo_Value(tr, 'I_FOLDERDEPTH') == 1 end
local function mcp_collapsed(tr)
  if not is_folder(tr) then return false end
  local g, now = r.GetTrackGUID(tr), r.time_precise()
  local c = mcp_comp[g]
  if not c or now - c.t > 0.5 then
    local ok, ch = r.GetTrackStateChunk(tr, '', true)
    local v = ok and tonumber(ch:match('\n%s*BUSCOMP%s+%-?%d+%s+(%-?%d+)')) or 0
    c = { v = v, t = now }; mcp_comp[g] = c
  end
  return c.v ~= 0
end
local function set_mcp_collapsed(tr, on)
  local ok, ch = r.GetTrackStateChunk(tr, '', true)
  if not ok then return end
  local v = on and '1' or '0'
  local new, n = ch:gsub('(\n%s*BUSCOMP%s+%-?%d+%s+)%-?%d+', '%1' .. v, 1)
  if n == 0 then new, n = ch:gsub('(\n%s*ISBUS[^\n]*)', '%1\nBUSCOMP 0 ' .. v .. ' 0 0 0', 1) end
  if n == 0 then return end
  r.PreventUIRefresh(1)
  r.SetTrackStateChunk(tr, new, true)          -- undo-style: keeps the track's plugins as they are
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)             -- the real mixer shows / hides the children too
  mcp_comp[r.GetTrackGUID(tr)] = { v = on and 1 or 0, t = r.time_precise() }
end
-- hidden here because a folder it's in is collapsed, and that folder is shown in this window
local function hidden_by_collapse(tr, shown)
  local p = r.GetParentTrack(tr)
  while p do
    if shown[p] and mcp_collapsed(p) then return true end
    p = r.GetParentTrack(p)
  end
  return false
end

local function strip_tracks()
  local proj = r.EnumProjects(-1)
  if proj ~= state.proj then state.proj = proj; load_choice() end
  -- 'list': the tracks you picked; 'follow': every selected track (master included), live
  local out, shown = {}, {}
  if state.mode == 'list' then
    for _, g in ipairs(state.list) do
      local t = track_from_guid(g); if t and not state.hidden_track(t) then out[#out + 1] = t; shown[t] = true end
    end
  else
    for i = 0, r.CountSelectedTracks2(0, true) - 1 do
      local t = r.GetSelectedTrack2(0, i, true)
      if t and not state.hidden_track(t) then out[#out + 1] = t; shown[t] = true end
    end
  end
  -- in track order (master first), and children of a collapsed folder that's shown stay hidden
  local function pos(t) return (t == r.GetMasterTrack(0)) and 0 or r.GetMediaTrackInfo_Value(t, 'IP_TRACKNUMBER') end
  table.sort(out, function(a, b) return pos(a) < pos(b) end)
  local vis = {}
  for _, t in ipairs(out) do
    if t == r.GetMasterTrack(0) or not hidden_by_collapse(t, shown) then vis[#vis + 1] = t end
  end
  return vis
end
local function track_name(tr)
  if tr == r.GetMasterTrack(0) then return 'MASTER', 'MASTER' end
  local n = math.floor(r.GetMediaTrackInfo_Value(tr, 'IP_TRACKNUMBER'))
  local _, name = r.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', false)
  return tostring(n), (name ~= '' and name or ('Track ' .. n))
end
local function recinput_name(v)
  if v < 0 then return 'none' end
  if v >= 4096 then
    local dev, ch = (v >> 5) & 63, v & 31
    local dn = (dev == 63) and 'All' or (select(2, r.GetMIDIInputName(dev, '')) or ('MIDI ' .. (dev + 1)))
    return 'MIDI: ' .. dn .. ': ' .. (ch == 0 and 'All' or tostring(ch))
  end
  local idx = v & 1023
  local function nm(i) local n = r.GetInputChannelName(i); return (n and n ~= '') and n or ('Input ' .. (i + 1)) end
  if v & 2048 ~= 0 then return nm(idx) .. ' (multi)' end
  if v & 1024 ~= 0 then return nm(idx) .. '/' .. nm(idx + 1) end
  return nm(idx)
end
local function clean_fx_name(n)
  n = n:gsub('^[%w]+:%s*', ''):gsub('%s*%b()$', '')
  return n
end

--------------------------------------------------------------------------------
-- Sections
--------------------------------------------------------------------------------
-- image drawing -----------------------------------------------------------------
-- draw one frame of an image; (x, y) = design position of the element's core
-- (overlay margins from the pink pixels are applied unless raw = true)
local function draw_img(im, x, y, frame, nframes, vertical, tint, raw)
  local cw, ch = im.x1 - im.x0, im.y1 - im.y0
  local fw, fh, fx0, fy0 = cw, ch, im.x0, im.y0
  nframes = nframes or 1; frame = frame or 0
  if vertical then fh = ch / nframes; fy0 = im.y0 + frame * fh
  else fw = cw / nframes; fx0 = im.x0 + frame * fw end
  local k = im.k * G.s
  local sx, sy = X(x), Y(y)
  if not raw then sx, sy = sx - im.L * k, sy - im.T * k end
  ImGui.DrawList_AddImage(G.dl, im.img, sx, sy, sx + fw * k, sy + fh * k,
    fx0 / im.w, fy0 / im.h, (fx0 + fw) / im.w, (fy0 + fh) / im.h, tint or 0xFFFFFFFF)
end

-- core size (design units) of a 3-state button image
local function btn_core(im)
  local fw = (im.x1 - im.x0) / 3
  return (fw - im.L - im.R) * im.k, (im.y1 - im.y0 - im.T - im.B) * im.k
end

-- 9-slice: pink runs = fixed borders, middle stretches (per frame for stacked images)
local function nine(im, x1, y1, x2, y2, frame, nframes, tint)
  frame, nframes = frame or 0, nframes or 1
  local fh = (im.y1 - im.y0) / nframes
  local fy0 = im.y0 + frame * fh
  local k = im.k * G.s
  local sx = { X(x1), X(x1) + im.L * k, X(x2) - im.R * k, X(x2) }
  local sy = { Y(y1), Y(y1) + im.T * k, Y(y2) - im.B * k, Y(y2) }
  local u = { im.x0, im.x0 + im.L, im.x1 - im.R, im.x1 }
  local v = { fy0, fy0 + im.T, fy0 + fh - im.B, fy0 + fh }
  if sx[3] < sx[2] then local m = (sx[1] + sx[4]) / 2; sx[2], sx[3] = m, m end
  if sy[3] < sy[2] then local m = (sy[1] + sy[4]) / 2; sy[2], sy[3] = m, m end
  -- stretched pieces are sampled half a pixel inside their own area, so smoothing doesn't pull in the
  -- neighbouring piece (that caused the smear next to the FX slot's divider line)
  local function inset(a, b, dest)
    local src = b - a
    if src > 1 and math.abs(dest - src * k) > 0.5 then return a + 0.5, b - 0.5 end
    return a, b
  end
  for i = 1, 3 do for j = 1, 3 do
    if sx[i + 1] > sx[i] and sy[j + 1] > sy[j] and u[i + 1] > u[i] and v[j + 1] > v[j] then
      local u0, u1 = inset(u[i], u[i + 1], sx[i + 1] - sx[i])
      local v0, v1 = inset(v[j], v[j + 1], sy[j + 1] - sy[j])
      ImGui.DrawList_AddImage(G.dl, im.img, sx[i], sy[j], sx[i + 1], sy[j + 1],
        u0 / im.w, v0 / im.h, u1 / im.w, v1 / im.h, tint or 0xFFFFFFFF)
    end
  end end
end

-- theme button: base + overlay, 3 frames (normal / hover / pressed). Falls back to a plain drawn button.
local function theme_button(id, bi, x, y, tip, fb_label, fb_w, fb_h, fb_col)
  if bi then
    -- the visible button is defined by the overlay when there is one (its pink pixels = shadow/overhang);
    -- base images like mcp_io use their pink pixels for something else, so they don't set the size
    local cw, ch = btn_core(bi.ol or bi.base)
    local h = hit(id, X(x), Y(y), X(x + cw), Y(y + ch), tip)
    local f = h.act and 2 or (h.hov and 1 or 0)
    if bi.base then draw_img(bi.base, x, y, f, 3, false, nil, bi.ol ~= nil) end
    if bi.ol then draw_img(bi.ol, x, y, f, 3) end
    return h
  end
  local h = hit(id, X(x), Y(y), X(x + fb_w), Y(y + fb_h), tip)
  btn_bg(X(x), Y(y), X(x + fb_w), Y(y + fb_h), h, fb_col or COL.btn)
  text(font_reg, 15, X(x + fb_w / 2), Y(y + fb_h / 2), COL.text_btn, fb_label, 'c')
  return h
end

local SLOT_P, SLOT_H = 36, 36      -- theme row height 18 @100%; the slot images' own transparent edges make the gaps
local EXT = 'Daniel_FloatingMixer'
state.fx_scroll, state.send_scroll = 0, 0
state.split = tonumber(r.GetExtState(EXT, 'fx_split')) or 0.55

local function list_tint()
  if not track_rgba or LIST_TINT <= 0 then return 0xFFFFFFFF end
  return rgba(255 * (1 - LIST_TINT * (1 - TR)), 255 * (1 - LIST_TINT * (1 - TG)), 255 * (1 - LIST_TINT * (1 - TB)))
end

local UIORD = 0x10000000   -- REAPER 7.75+: index sends/hw outputs in mixer order (may have empty slots)

local function track_info(dest)
  local ok = dest and pcall(r.ValidatePtr2, 0, dest, 'MediaTrack*') and r.ValidatePtr2(0, dest, 'MediaTrack*')
  if not ok then return end
  local num = math.floor(r.GetMediaTrackInfo_Value(dest, 'IP_TRACKNUMBER'))
  local _, name = r.GetSetMediaTrackInfo_String(dest, 'P_NAME', '', false)
  local c, col = math.floor(r.GetMediaTrackInfo_Value(dest, 'I_CUSTOMCOLOR')), nil
  if c & 0x1000000 ~= 0 then local R, G_, B = r.ColorFromNative(c & 0xFFFFFF); col = rgba(R, G_, B) end
  return num, name, col
end

-- returns entries keyed by slot (0-based, may have holes), number of slots, and whether UI ordering is supported
local function send_list(tr)
  local nhw, ns = r.GetTrackNumSends(tr, 1), r.GetTrackNumSends(tr, 0)
  local real = {}
  for i = 0, ns - 1 do
    local e = { cat = 0, ci = i, idx = nhw + i, dest = r.GetTrackSendInfo_Value(tr, 0, i, 'P_DESTTRACK') }
    local num, name, col = track_info(e.dest)
    e.label, e.col = (num or 0) .. ':' .. (name or ''), col
    real[#real + 1] = e
  end
  for i = 0, nhw - 1 do
    local _, name = r.GetTrackSendName(tr, i, '')
    real[#real + 1] = { cat = 1, ci = i, idx = i, label = name }
  end
  for _, e in ipairs(real) do
    e.rname = select(2, r.GetTrackSendName(tr, e.idx, ''))
    e.vol = select(2, r.GetTrackSendUIVolPan(tr, e.idx))
  end

  local list = {}
  local ui = r.GetTrackNumSends(tr, UIORD + 1) == UIORD
  if not ui then
    for k, e in ipairs(real) do e.slot, e.uidx = k - 1, e.idx; list[k - 1] = e end
    return list, #real, false
  end
  local n = r.GetTrackNumSends(tr, UIORD)
  local used = {}
  for slot = 0, n - 1 do
    local ok, nm = r.GetTrackSendName(tr, UIORD + slot, '')
    if ok then
      local _, v = r.GetTrackSendUIVolPan(tr, UIORD + slot)
      -- match the mixer-ordered send to its real send (same name + level)
      local best
      for _, e in ipairs(real) do
        if not used[e] and e.rname == nm then
          if not best or math.abs((e.vol or 0) - (v or 0)) < math.abs((best.vol or 0) - (v or 0)) then best = e end
        end
      end
      local e = best or { label = nm }
      if best then used[best] = true end
      e.slot, e.uidx = slot, UIORD + slot
      list[slot] = e
    end
  end
  return list, n, true
end

-- move send in slot a to slot b (swap if b is taken) using the sends' I_SLOT_HINT
local function move_send(tr, a, b)
  local list, n = send_list(tr)
  local ea = list[a]
  if not ea or not ea.cat or a == b then return end
  local eb = list[b]
  undo_wrap('Move send', function()
    r.PreventUIRefresh(1)
    for slot = 0, n - 1 do        -- pin every send to where it is now, so nothing else shifts
      local e = list[slot]
      if e and e.cat then r.SetTrackSendInfo_Value(tr, e.cat, e.ci, 'I_SLOT_HINT', slot) end
    end
    if eb and eb.cat then r.SetTrackSendInfo_Value(tr, eb.cat, eb.ci, 'I_SLOT_HINT', a) end
    r.SetTrackSendInfo_Value(tr, ea.cat, ea.ci, 'I_SLOT_HINT', b)
    r.PreventUIRefresh(-1)
  end)
end

local function send_drag_source(tr, slot, label)
  if ImGui.BeginDragDropSource(ctx) then
    ImGui.SetDragDropPayload(ctx, 'DTS_SEND', r.GetTrackGUID(tr) .. '|' .. slot)
    ImGui.Text(ctx, label)
    ImGui.EndDragDropSource(ctx)
  end
end
local SEND_PARAMS = { 'D_VOL', 'D_PAN', 'D_PANLAW', 'B_MUTE', 'B_PHASE', 'B_MONO', 'I_SENDMODE',
                      'I_AUTOMODE', 'I_SRCCHAN', 'I_DSTCHAN', 'I_MIDIFLAGS' }

-- duplicate send/hw output e (from src_tr) onto dst_tr with the same settings; returns category, index
local function copy_send(src_tr, e, dst_tr)
  local dest = nil
  if e.cat == 0 then
    dest = r.GetTrackSendInfo_Value(src_tr, 0, e.ci, 'P_DESTTRACK')
    if not dest or dest == dst_tr then return end           -- a track can't send to itself
  end
  local idx = r.CreateTrackSend(dst_tr, dest)
  if not idx or idx < 0 then return end
  local cat = dest and 0 or 1
  for _, p in ipairs(SEND_PARAMS) do
    r.SetTrackSendInfo_Value(dst_tr, cat, idx, p, r.GetTrackSendInfo_Value(src_tr, e.cat, e.ci, p))
  end
  return cat, idx
end

-- put send (cat, idx) of tr into slot S; sends in the way shift down one (only until the next gap)
local function send_insert_slot(tr, cat, idx, S)
  local list = send_list(tr)
  local function is_new(e) return e and e.cat == cat and e.ci == idx end
  for slot, e in pairs(list) do
    if e.cat and not is_new(e) then r.SetTrackSendInfo_Value(tr, e.cat, e.ci, 'I_SLOT_HINT', slot) end
  end
  local last = S
  while list[last] and not is_new(list[last]) do last = last + 1 end
  for sl = last - 1, S, -1 do
    local e = list[sl]
    if e and e.cat then r.SetTrackSendInfo_Value(tr, e.cat, e.ci, 'I_SLOT_HINT', sl + 1) end
  end
  r.SetTrackSendInfo_Value(tr, cat, idx, 'I_SLOT_HINT', S)
end

-- same track: reorder. Other track: copy the send there (Option/Alt: move it)
local function send_drop_target(tr, slot, ui_order)
  if ImGui.BeginDragDropTarget(ctx) then
    local ok, data = ImGui.AcceptDragDropPayload(ctx, 'DTS_SEND', ImGui.DragDropFlags_AcceptNoDrawDefaultRect)
    if ok and data then
      local guid, src = data:match('^(.-)|(%d+)$')
      src = tonumber(src)
      local src_tr = guid and track_from_guid(guid)
      if src_tr and src then
        if src_tr == tr then
          if ui_order then move_send(tr, src, slot) end
        else
          local e = send_list(src_tr)[src]
          local move = is_alt()
          if e and e.cat then
            undo_wrap(move and 'Move send to track' or 'Copy send to track', function()
              r.PreventUIRefresh(1)
              local cat, idx = copy_send(src_tr, e, tr)
              if cat and ui_order then send_insert_slot(tr, cat, idx, slot) end
              if cat and move then r.RemoveTrackSend(src_tr, e.cat, e.ci) end
              r.PreventUIRefresh(-1)
            end)
          end
        end
      end
    end
    ImGui.EndDragDropTarget(ctx)
  end
end

local function list_scroll(key, y0, y1, maxscroll, blocked)
  local mx, my = ImGui.GetMousePos(ctx)
  if not blocked and ImGui.IsWindowHovered(ctx) and mx >= X(0) and mx <= X(DESIGN_W) and my >= Y(y0) and my < Y(y1) then
    local w = ImGui.GetMouseWheel(ctx)
    if w ~= 0 then state[key] = state[key] - (w > 0 and 1 or -1) end
  end
  state[key] = clamp(state[key], 0, math.max(0, maxscroll))
end

-- REAPER 7.75+: FX can sit in particular slots with empty slots between them.
-- chain index -> slot via TrackFX_GetNamedConfigParm('chain_index_to_slot'); falls back to 1:1.
local function fx_slot_map(tr, nfx)
  local map, last, ok_all = {}, -1, true
  local used = {}
  for i = 0, nfx - 1 do
    local ok, v = r.TrackFX_GetNamedConfigParm(tr, i, 'chain_index_to_slot')
    local sl = ok and tonumber(v)
    if not sl or sl < i or used[sl] then ok_all = false; break end
    used[sl] = true
    map[i] = math.floor(sl)
  end
  if not ok_all then map = {}; for i = 0, nfx - 1 do map[i] = i end end
  for i = 0, nfx - 1 do if map[i] > last then last = map[i] end end
  return map, last, ok_all and nfx > 0 or (nfx == 0 and r.TrackFX_GetNamedConfigParm(tr, 0, 'chain_slot_to_index'))
end

-- drag an FX slot onto another slot to move it (hold Cmd/Ctrl when dropping to copy)
local function fx_drag_source(tr, i, label)
  if ImGui.BeginDragDropSource(ctx) then
    ImGui.SetDragDropPayload(ctx, 'DTS_FX', r.GetTrackGUID(tr) .. '|' .. i)
    ImGui.Text(ctx, label)
    ImGui.EndDragDropSource(ctx)
  end
end
-- dest = chain index of the FX in the target slot, or nil for an empty slot (slot = its slot number)
local function find_fx(tr, guid)
  for i = 0, r.TrackFX_GetCount(tr) - 1 do if r.TrackFX_GetFXGUID(tr, i) == guid then return i end end
end

-- Put an FX (already on tr, by GUID) into slot S. Anything in the way shifts down one slot (only until
-- the next gap), then the chain order is made to match the slot order and every FX gets its slot_hint.
local function place_fx(tr, guid, S)
  local n = r.TrackFX_GetCount(tr)
  local map = fx_slot_map(tr, n)
  local L = {}
  for i = 0, n - 1 do
    local g = r.TrackFX_GetFXGUID(tr, i)
    if g ~= guid then L[#L + 1] = { guid = g, slot = map[i] } end
  end
  table.sort(L, function(a, b) return a.slot < b.slot end)
  local want = S
  for _, e in ipairs(L) do
    if e.slot == want then e.slot = want + 1; want = want + 1
    elseif e.slot > want then break end
  end
  L[#L + 1] = { guid = guid, slot = S }
  table.sort(L, function(a, b) return a.slot < b.slot end)
  for k, e in ipairs(L) do
    local cur = find_fx(tr, e.guid)
    if cur and cur ~= k - 1 then r.TrackFX_CopyToTrack(tr, cur, tr, k - 1, true) end
  end
  for k, e in ipairs(L) do r.TrackFX_SetNamedConfigParm(tr, k - 1, 'slot_hint', tostring(e.slot)) end
end

-- dest = chain index of the FX in the target slot (nil if empty); slot = the target slot
local function fx_drop_target(tr, dest, slot, nfx, slots_ok)
  if ImGui.BeginDragDropTarget(ctx) then
    local ok, data = ImGui.AcceptDragDropPayload(ctx, 'DTS_FX', ImGui.DragDropFlags_AcceptNoDrawDefaultRect)
    if ok and data then
      local guid, src = data:match('^(.-)|(%d+)$')
      src = tonumber(src)
      local src_tr = guid and track_from_guid(guid)
      if src_tr and src then
        -- REAPER: same track = move (Cmd/Ctrl copies); other track = copy (Option/Alt moves)
        local copy
        if src_tr == tr then copy = is_ctrl() else copy = not is_alt() end
        if slots_ok then
          local same = (src_tr == tr and not copy)
          if not (same and dest == src) then
            undo_wrap(copy and 'Copy FX' or 'Move FX', function()
              r.PreventUIRefresh(1)
              local fg
              if same then fg = r.TrackFX_GetFXGUID(tr, src)
              else
                local n = r.TrackFX_GetCount(tr)
                r.TrackFX_CopyToTrack(src_tr, src, tr, n, not copy)
                fg = r.TrackFX_GetFXGUID(tr, n)
              end
              if fg then place_fx(tr, fg, slot) end
              r.PreventUIRefresh(-1)
            end)
          end
        else
          local d = dest or ((src_tr == tr and not copy) and (nfx - 1) or nfx)
          if not (src_tr == tr and src == d and not copy) then
            undo_wrap(copy and 'Copy FX' or 'Move FX', function() r.TrackFX_CopyToTrack(src_tr, src, tr, d, not copy) end)
          end
        end
      end
    end
    ImGui.EndDragDropTarget(ctx)
  end
end

-- after "Add FX" from an empty slot: when the FX browser adds the plugin, move it into that slot
local function check_pending_add(tr)
  local pa = state.pending_add
  if not pa then return end
  if r.time_precise() - pa.t > 90 or pa.guid ~= r.GetTrackGUID(tr) then state.pending_add = nil; return end
  local n = r.TrackFX_GetCount(tr)
  if n > pa.count then
    state.pending_add = nil
    undo_wrap('Move FX to slot', function() local g = r.TrackFX_GetFXGUID(tr, n - 1); if g then place_fx(tr, g, pa.slot) end end)
  elseif n < pa.count then pa.count = n end
end

local function draw_fx_area(tr, y0, y1)
  do
    -- FX / send list background, measured on the real mixer (red and blue tracks, selected and not):
    -- a third of the strip color + 13; it does NOT get lighter when the track is selected.
    -- (Empty slots are drawn darker on top of it, so this is the color between the slots.)
    -- Master (no track color): measured 51 gray.
    local mr, mg, mb_ = main_sec_rgb(tr, true)
    if tr == r.GetMasterTrack(0) then
      G.listbg = { mr * 0.3 + 12, mg * 0.3 + 12, mb_ * 0.3 + 12 }
    else
      G.listbg = { mr / 3 + 13, mg / 3 + 13, mb_ / 3 + 13 }
    end
  end
  rect(X(0), Y(y0), X(DESIGN_W), Y(y1), rgba(G.listbg[1], G.listbg[2], G.listbg[3]))
  state.splits = state.splits or {}
  if not state.splits[G.sid] then
    local ok, v = r.GetSetMediaTrackInfo_String(tr, 'P_EXT:Daniel_FloatingMixer_split', '', false)
    state.splits[G.sid] = (ok and tonumber(v)) or state.split
  end
  local split = y0 + (y1 - y0) * state.splits[G.sid]
  local tint = list_tint()
  local x1, x2 = 3, DESIGN_W - 3

  -- FX inserts: fill the area with slots, empty ones use the theme's empty slot image
  local nfx = r.TrackFX_GetCount(tr)
  check_pending_add(tr)
  nfx = r.TrackFX_GetCount(tr)
  local slot_of, last_slot, slots_ok = fx_slot_map(tr, nfx)
  local by_slot = {}
  for i = 0, nfx - 1 do by_slot[slot_of[i]] = i end
  local rows = math.max(1, math.floor((split - y0 - 6 + (SLOT_P - SLOT_H)) / SLOT_P))
  list_scroll('fx_scroll', y0, split, last_slot + 2 - rows)
  for row = 0, rows - 1 do
    local slot = row + state.fx_scroll
    local i = by_slot[slot]
    local sy = y0 + 4 + row * SLOT_P
    if i then
      local en, off = r.TrackFX_GetEnabled(tr, i), r.TrackFX_GetOffline(tr, i)
      local chain_on = r.GetMediaTrackInfo_Value(tr, 'I_FXEN') == 1
      local _, nm = r.TrackFX_GetFXName(tr, i, '')
      local label = clean_fx_name(nm)
      local h = hit('##fx' .. row, X(x1), Y(sy), X(x2), Y(sy + SLOT_H), label ..
        '\nClick: show/hide  |  Shift: bypass  |  Cmd/Ctrl+Shift: offline\nAlt: remove  |  Cmd/Ctrl: FX chain  |  Drag: move here / copy to another track (Option: move)\nRight-click: menu')
      fx_drop_target(tr, i, slot, nfx, slots_ok)
      fx_drag_source(tr, i, label)
      local key = off and 'off' or ((en and chain_on) and 'norm' or 'byp')
      local im = img('mcp_fxlist_' .. key)
      local f = h.act and 2 or (h.hov and 1 or 0)
      if im then nine(im, x1, sy, x2, sy + SLOT_H, f, 3, tint)
      else rect(X(x1), Y(sy), X(x2), Y(sy + SLOT_H), T(160, .2), 4 * G.s) end
      local col = off and theme_col('mcp_fx_offlined', 0xFF8080FF)
               or ((en and chain_on) and theme_col('mcp_fx_normal', 0x262626FF) or theme_col('mcp_fx_bypassed', 0xFFE964FF))
      local ind = im and im.L * im.k or 19
      local tx = x1 + math.max(24, ind + 4)
      local nf, nk = list_name_font('fx')
      -- FX names centered on the whole slot (theme: mcp.fxlist.margin 12 px left and right @100%, align 0.5);
      -- a name too wide for that space starts after the bypass marker and is cut at the right
      local fs = fpx(1, LIST_PX) * nk
      local tw = text_size(nf, fs, label)
      local sx = X((x1 + x2) / 2) - tw / 2
      if sx < X(tx) then sx = X(tx) end
      clip_text(nf, fs, sx, Y(sy + SLOT_H / 2), col, label, X(x2 - 6))
      if h.click then
        local mx = ImGui.GetMousePos(ctx)
        local sh, ct, al = is_fine(), is_ctrl(), is_alt()
        -- REAPER's built-in FX slot clicks (Cmd = Ctrl on macOS)
        if al and not sh and not ct then
          undo_wrap('Remove FX', function() r.TrackFX_Delete(tr, i) end)
        elseif sh and ct then
          undo_wrap('Toggle FX offline', function() r.TrackFX_SetOffline(tr, i, not off) end)
        elseif sh or (mx < X(x1 + ind)) then
          undo_wrap('Toggle FX bypass', function() r.TrackFX_SetEnabled(tr, i, not en) end)
        elseif ct then
          r.TrackFX_Show(tr, i, 1)
        elseif r.TrackFX_GetFloatingWindow(tr, i) then r.TrackFX_Show(tr, i, 2)
        else r.TrackFX_Show(tr, i, 3) end
      end
      if h.rclick then state.menu_fx = i; ImGui.OpenPopup(ctx, 'fx_menu') end
    else
      local h = hit('##fx' .. row, X(x1), Y(sy), X(x2), Y(sy + SLOT_H), 'Click: add FX here  |  Drop an FX here to move it here')
      fx_drop_target(tr, nil, slot, nfx, slots_ok)
      local im = img('mcp_fxlist_empty')
      if im then nine(im, x1, sy, x2, sy + SLOT_H, h.act and 2 or (h.hov and 1 or 0), 3, tint)
      else rect(X(x1), Y(sy), X(x2), Y(sy + SLOT_H), T(34, .36), 4 * G.s) end
      if h.click then
        -- FX browser adds to the selected track; the new FX is then moved into this slot
        if slots_ok and slot < nfx + 64 then
          state.pending_add = { guid = r.GetTrackGUID(tr), slot = slot, count = nfx, t = r.time_precise() }
        end
        if not r.IsTrackSelected(tr) then r.SetOnlyTrackSelected(tr) end
        r.Main_OnCommand(40914, 0)          -- set first selected track as last touched
        r.Main_OnCommand(40271, 0)          -- View: Show FX browser window
      end
    end
  end

  -- divider: drag to resize FX / sends like the real mixer strip
  local hd = hit('##split', X(0), Y(split - 1), X(DESIGN_W), Y(split + 5), 'Drag to resize FX / sends  |  Cmd/Ctrl-drag: all strips')
  if hd.hov or hd.act then ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS) end
  if hd.act then
    local _, dy = ImGui.GetMouseDelta(ctx)
    local nv = clamp(state.splits[G.sid] + dy / G.s / (y1 - y0), 0.08, 0.92)
    if is_ctrl() then                 -- Cmd/Ctrl: all strips together
      for _, t in ipairs(state.cur_tracks or {}) do state.splits[r.GetTrackGUID(t)] = nv end
      state.split = nv
    else
      state.splits[G.sid] = nv
    end
  end
  if hd.deactivated then
    local function save(t)
      r.GetSetMediaTrackInfo_String(t, 'P_EXT:Daniel_FloatingMixer_split', string.format('%.4f', state.splits[r.GetTrackGUID(t)] or state.split), true)
    end
    if is_ctrl() then
      for _, t in ipairs(state.cur_tracks or {}) do save(t) end
      r.SetExtState(EXT, 'fx_split', tostring(state.split), true)
    else save(tr) end
  end
  do -- divider, measured on the real mixer: one physical pixel, the list background lifted ~11% toward white
       -- (no track tint), 23 px in from the left edge and 25 px from the right; same color always
    local bg = G.listbg
    local a = 0.11
    local lc = rgba(bg[1] + (255 - bg[1]) * a, bg[2] + (255 - bg[2]) * a, bg[3] + (255 - bg[3]) * a)
    local ly = math.floor(split)
    G.hline(X(23), X(DESIGN_W - 25), Y(ly), lc)
  end

  -- sends
  local list, nslots, ui_order = send_list(tr)
  local sy0 = split + 6
  local srows = math.max(0, math.floor((y1 - sy0 - 2 + (SLOT_P - SLOT_H)) / SLOT_P))
  local knob_hovered = false
  local st = img('mcp_send_knob_stack')
  for row = 0, srows - 1 do
    local slot = row + state.send_scroll
    local s = list[slot]
    local sy = sy0 + row * SLOT_P
    if s then
      local _, vol = r.GetTrackSendUIVolPan(tr, s.uidx)
      local _, muted = r.GetTrackSendUIMute(tr, s.uidx)
      local im = img(muted and 'mcp_sendlist_mute' or 'mcp_sendlist_norm')
      local kw = im and im.R * im.k or 36
      local hn = hit('##sn' .. row, X(x1), Y(sy), X(x2 - kw), Y(sy + SLOT_H),
        s.label .. '\nShift-click: mute  |  Cmd-click: routing  |  Option-click: remove\nDrag: move here / copy to another track (Option: move)')
      send_drop_target(tr, slot, ui_order); send_drag_source(tr, slot, s.label)
      local p = pos_of(val2db(vol))
      local hk = hit('##sk' .. row, X(x2 - kw), Y(sy), X(x2), Y(sy + SLOT_H),
        'Send level: ' .. fmt_peak(val2db(vol)) .. ' dB\nDrag / wheel  |  Double-click: 0 dB')
      knob_hovered = knob_hovered or hk.hov
      local per = 1 / (150 * G.s)
      local nv, done = drag_value('send' .. s.uidx, hk, p, 0, 1, pos_of(0), per, per, 0.01)
      if nv then r.SetTrackSendUIVol(tr, s.uidx, vol_of_pos(nv), done and 1 or 0); p = nv end
      local f = (hn.act or hk.act) and 2 or ((hn.hov or hk.hov) and 1 or 0)
      if im then nine(im, x1, sy, x2, sy + SLOT_H, f, 3, tint)
      else rect(X(x1), Y(sy), X(x2), Y(sy + SLOT_H), T(160, .2), 16 * G.s) end
      -- level bar across the name area (like the mixer's send list)
      if p > 0 and im then
        -- Level bar = destination track color blended over the slot underneath, across the full slot width
        -- (the knob sits on top). Blend measured from the real mixer: result = 0.845 * slot + 0.345 * color,
        -- so a muted (red) slot gives a darker bar, like REAPER. Drawn with the normal slot image's shape.
        local lim = img('mcp_sendlist_norm') or im
        local lx2 = x1 + (x2 - x1) * p
        local lc = s.col or theme_col('mcp_sends_levels', 0x304247FF)
        local cR, cG, cB = (lc >> 24) & 255, (lc >> 16) & 255, (lc >> 8) & 255
        local bg = G.listbg or { 45, 40, 35 }
        -- hardware outputs (and everything on the master) have no destination track color: REAPER draws
        -- their level light gray like an FX slot (white @ ~55% over the list background, measured)
        local plain = (tr == r.GetMasterTrack(0)) or s.cat == 1 or not s.col
        -- slot color underneath (the theme images: normal = white @ 35%, muted = (191,48,74) @ 25%)
        local sR, sG, sB
        if muted then
          sR, sG, sB = bg[1] * 0.749 + 191 * 0.251, bg[2] * 0.749 + 48 * 0.251, bg[3] * 0.749 + 74 * 0.251
        else
          sR, sG, sB = bg[1] * 0.647 + 90, bg[2] * 0.647 + 90, bg[3] * 0.647 + 90
        end
        local tc = rgba(0.845 * sR + 0.345 * cR, 0.845 * sG + 0.345 * cG, 0.845 * sB + 0.345 * cB)
        if plain and muted then
          -- master, muted: the muted (red) slot lifted ~12% toward white (measured on the real mixer)
          local a = 0.123
          tc = rgba(sR + (255 - sR) * a, sG + (255 - sG) * a, sB + (255 - sB) * a)
        elseif plain then
          -- the theme's send slot is white @ 35% normally but @ 50% when hovered/pressed, which is exactly the
          -- level gray; so while hovered the level steps up the same way an FX slot brightens (to ~63%)
          local a = (f == 0) and 0.555 or 0.65
          tc = rgba(bg[1] * (1 - a) + 255 * a, bg[2] * (1 - a) + 255 * a, bg[3] * (1 - a) + 255 * a)
        end
        ImGui.DrawList_PushClipRect(G.dl, X(x1), Y(sy), X(lx2), Y(sy + SLOT_H), true)
        for _ = 1, 6 do nine(lim, x1, sy, x2, sy + SLOT_H, f, 3, tc) end
        ImGui.DrawList_PopClipRect(G.dl)
      end
      if st then
        local fs = st.x1 - st.x0
        local n = math.max(1, math.floor((st.y1 - st.y0) / fs))
        local side = fs * st.k
        draw_img(st, x2 - kw / 2 - side / 2, sy + SLOT_H / 2 - side / 2, math.floor(p * (n - 1) + 0.5), n, true, nil, true)
      end
      local col = muted and theme_col('mcp_sends_muted', 0xFF8080FF) or theme_col('mcp_sends_normal', 0x000000FF)
      local nf, nk = list_name_font()
      clip_text(nf, fpx(1, LIST_PX) * nk, X(x1 + 4), Y(sy + SLOT_H / 2), col, s.label, X(x2 - kw))
      -- a click that wasn't a drag (a drag that ends back on the slot must not count as a click)
      if hn.activated then state.send_press = { ImGui.GetMousePos(ctx) } end
      local moved = false
      if hn.click and state.send_press then
        local mx, my = ImGui.GetMousePos(ctx)
        moved = math.abs(mx - state.send_press[1]) > 4 or math.abs(my - state.send_press[2]) > 4
      end
      if hn.click and not moved then
        if is_fine() then                                    -- Shift: mute
          r.ToggleTrackSendUIMute(tr, s.uidx)
        elseif is_ctrl() then                                -- Cmd: routing window
          if not r.IsTrackSelected(tr) then r.SetOnlyTrackSelected(tr) end
          r.Main_OnCommand(40914, 0); r.Main_OnCommand(40293, 0); state.no_refocus = true
        elseif is_alt() and s.cat then                       -- Option: remove the send
          undo_wrap('Remove send', function() r.RemoveTrackSend(tr, s.cat, s.ci) end)
        end
      end
    else
      local he = hit('##se' .. row, X(x1), Y(sy), X(x2), Y(sy + SLOT_H), 'Click: add send')
      send_drop_target(tr, slot, ui_order)
      if he.click then
        state.add_send_slot = ui_order and slot or nil
        ImGui.OpenPopup(ctx, 'add_send')
      end
      local im = img('mcp_sendlist_empty')
      if im then nine(im, x1, sy, x2, sy + SLOT_H, he.act and 2 or (he.hov and 1 or 0), 3, tint)
      else rect(X(x1), Y(sy), X(x2), Y(sy + SLOT_H), T(34, .36), 16 * G.s) end
    end
  end
  list_scroll('send_scroll', sy0, y1, nslots + 1 - srows, knob_hovered)
end

local function knob(tr, id, cx, cy, v, reset, label, setter, stack_names)
  local rad = 20
  local h = hit(id, X(cx - rad - 4), Y(cy - rad - 4), X(cx + rad + 4), Y(cy + rad + 4),
    'Drag: adjust  |  Shift: fine\nDouble-click / Alt-click: reset')
  local per = 2 / (160 * G.s)
  local nv, done = drag_value(id, h, v, -1, 1, reset, per, per, 0.05)
  if nv then setter(tr, nv, done); v = nv end
  if drag[(G.sid or '') .. id] then v = drag[(G.sid or '') .. id] end   -- held: follow the mouse, not an envelope
  text(font_list, fpx(1, 23), X(cx), Y(cy - 36), G.pan_label or gray(220), label, 'c')

  local bg = img('mcp_pan_knob_small', 'tcp_pan_knob_small')
  local st = img(table.unpack(stack_names))
  if bg and st then
    local side = (bg.x1 - bg.x0) * bg.k                 -- knob is square: width x width
    draw_img(bg, cx - side / 2, cy - side / 2, 0, 1, false, nil, true)
    local fs = (st.x1 - st.x0)                          -- stack frame is square
    local n = math.max(1, math.floor((st.y1 - st.y0) / fs))
    local f = math.floor((v + 1) / 2 * (n - 1) + 0.5)
    local fside = fs * st.k
    draw_img(st, cx - fside / 2, cy - fside / 2, f, n, true, nil, true)
  else
    local s = G.s
    ImGui.DrawList_PathArcTo(G.dl, X(cx), Y(cy), (rad - 3.5) * s, 0, math.pi * 2, 40)
    ImGui.DrawList_PathStroke(G.dl, COL.knob_ring, ImGui.DrawFlags_Closed, 7 * s)
    local a = -math.pi / 2 + v * (math.pi * 0.75)
    ImGui.DrawList_AddLine(G.dl, X(cx) + math.cos(a) * (rad - 7) * s, Y(cy) + math.sin(a) * (rad - 7) * s,
      X(cx) + math.cos(a) * rad * s, Y(cy) + math.sin(a) * rad * s, COL.pan_ptr, 4 * s)
  end
end

-- dropdown: the theme's dropdownBg_h (9-slice, its right end has the circle cut-out) + arrow image
local function dropdown_bg(x1, y1, x2, y2, hov)
  local bg = img('dropdownBg_h')
  if bg then
    nine(bg, x1, y1, x2, y2, 0, 1, hov and 0xFFFFFFFF or 0xFFFFFFE0)
    if hov then nine(bg, x1, y1, x2, y2, 0, 1, 0xFFFFFF40) end
  else
    rect(X(x1), Y(y1), X(x2), Y(y2), hov and 0x00000050 or 0x00000040, 8 * G.s)
  end
  return x2 - 20.5, (y1 + y2) / 2        -- center of the circle cut-out
end

local function dropdown(id, x1, y1, x2, y2, label, tip)
  local h = hit(id, X(x1), Y(y1), X(x2), Y(y2), tip)
  local ccx, ccy = dropdown_bg(x1, y1, x2, y2, h.hov)
  local arrow = img('mcp_recinput')
  if arrow then
    -- arrow glyph sits at ~61% / 57% of the image content
    local cw, ch = (arrow.x1 - arrow.x0) * arrow.k, (arrow.y1 - arrow.y0) * arrow.k
    draw_img(arrow, ccx - cw * 0.606, ccy - ch * 0.571, 0, 1, false, nil, true)
  else
    ImGui.DrawList_AddTriangleFilled(G.dl, X(ccx - 7), Y(ccy - 4), X(ccx + 7), Y(ccy - 4), X(ccx), Y(ccy + 6), 0xF2F2F2FF)
  end
  text(font_list, fpx(1, 23), X(x1 + 8), Y(ccy), gray(235), fit(font_list, fpx(1, 23), label, (x2 - 40 - x1 - 8) * G.s))
  return h
end

-- run the action REAPER has assigned in Preferences > Mouse modifiers for a click/double-click context
local function run_mouse_modifier(context)
  if not r.GetMouseModifier then return false end
  local f = 0
  if is_fine() then f = f | 1 end                                    -- shift
  if is_ctrl() then f = f | 2 end                                    -- cmd (mac) / ctrl
  if is_alt() then f = f | 4 end                                     -- opt / alt
  if (mods() & ImGui.Mod_Super) ~= 0 then f = f | 8 end              -- control (mac) / win
  local a = r.GetMouseModifier(context, f)
  if not a or a == '' or a == '-1' then return false end
  local id, kind = a:match('^(%S+)%s*(%a?)$')
  if not id or kind == 'm' then return false end                    -- built-in mouse behaviors can't be run from a script
  local cmd = tonumber(id) or r.NamedCommandLookup(id:sub(1, 1) == '_' and id or ('_' .. id))
  if cmd and cmd > 0 then r.Main_OnCommand(cmd, 0); return true end
  return false
end

-- Drag a strip (number bar or name) onto another strip to move the track in the project, like the mixer.
-- Dropping on the left half puts it before that track, the right half after. If the dragged track is
-- selected, all selected tracks move together (REAPER's behavior); otherwise just that track.
local function track_drag_source(tr)
  if tr == r.GetMasterTrack(0) then return end
  if ImGui.BeginDragDropSource(ctx) then
    ImGui.SetDragDropPayload(ctx, 'DTS_TRACK', r.GetTrackGUID(tr))
    local n, nm = track_name(tr)
    ImGui.Text(ctx, 'Move track ' .. n .. (nm ~= n and (': ' .. nm) or ''))
    ImGui.EndDragDropSource(ctx)
  end
end

-- theme "drag and drop preview indicator" color = col_repos in the .ReaperTheme (yours: 69, 92, 120).
-- Read live from REAPER; set DND_COLOR (0xRRGGBBAA) only if you want to override it.
local DND_COLOR = nil
local function dnd_color()
  return DND_COLOR or theme_col('col_repos', 0x455C78FF)
end

local function move_track(src, dst, after)
  local sel = {}
  local moving_selection = r.IsTrackSelected(src)
  if not moving_selection then
    for i = 0, r.CountSelectedTracks(0) - 1 do sel[#sel + 1] = r.GetSelectedTrack(0, i) end
  end
  local idx = math.floor(r.GetMediaTrackInfo_Value(dst, 'IP_TRACKNUMBER')) - 1 + (after and 1 or 0)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  if not moving_selection then r.SetOnlyTrackSelected(src) end
  r.ReorderSelectedTracks(idx, 0)
  if not moving_selection then                       -- put the selection back the way it was
    for i = 0, r.CountTracks(0) - 1 do r.SetTrackSelected(r.GetTrack(0, i), false) end
    for _, t in ipairs(sel) do if r.ValidatePtr2(0, t, 'MediaTrack*') then r.SetTrackSelected(t, true) end end
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock('Move tracks', -1)
end

-- drop zone: the item just submitted (bar / name / input section) of strip tr
local function track_drop_target(tr)
  if tr == r.GetMasterTrack(0) then return end
  if ImGui.BeginDragDropTarget(ctx) then
    local mx = ImGui.GetMousePos(ctx)
    local after = mx > X(DESIGN_W / 2)
    -- while dragging (every frame, not just on release): insertion line on the side it will land
    -- would dropping here actually change the order? (landing right next to where it already is = no)
    local function changes(src)
      if not src or src == tr then return false end
      local si = r.GetMediaTrackInfo_Value(src, 'IP_TRACKNUMBER')
      local ins = r.GetMediaTrackInfo_Value(tr, 'IP_TRACKNUMBER') + (after and 1 or 0)
      return ins ~= si and ins ~= si + 1
    end
    local rv, typ, payload = ImGui.GetDragDropPayload(ctx)
    if rv and typ == 'DTS_TRACK' then
      local src = track_from_guid(payload)
      if changes(src) then
        local lx = after and X(DESIGN_W) or X(0)
        ImGui.DrawList_AddRectFilled(ImGui.GetForegroundDrawList(ctx), lx - 2, G.oy, lx + 2, G.oy + G.h, dnd_color())
      end
    end
    -- spacers: left half = spacer before this track, right half = before the next track in the project
    local function spacer_dest()
      if not after then return tr end
      return r.GetTrack(0, math.floor(r.GetMediaTrackInfo_Value(tr, 'IP_TRACKNUMBER')))
    end
    if rv and typ == 'DTS_SPACER' then
      local src, dst = track_from_guid(payload), spacer_dest()
      if src and dst and dst ~= src and r.GetMediaTrackInfo_Value(dst, 'I_SPACER') ~= 1 then
        local lx = after and X(DESIGN_W) or X(0)
        ImGui.DrawList_AddRectFilled(ImGui.GetForegroundDrawList(ctx), lx - 2, G.oy, lx + 2, G.oy + G.h, dnd_color())
      end
    end
    local oks, sdata = ImGui.AcceptDragDropPayload(ctx, 'DTS_SPACER', ImGui.DragDropFlags_AcceptNoDrawDefaultRect)
    if oks and sdata then
      local src, dst = track_from_guid(sdata), spacer_dest()
      if src and dst and dst ~= src and r.GetMediaTrackInfo_Value(dst, 'I_SPACER') ~= 1 then
        undo_wrap('Move spacer', function()
          r.SetMediaTrackInfo_Value(src, 'I_SPACER', 0)
          r.SetMediaTrackInfo_Value(dst, 'I_SPACER', 1)
          r.TrackList_AdjustWindows(false)
        end)
      end
    end
    -- on release: move it
    local ok, data = ImGui.AcceptDragDropPayload(ctx, 'DTS_TRACK', ImGui.DragDropFlags_AcceptNoDrawDefaultRect)
    if ok and data then
      local src = track_from_guid(data)
      if changes(src) then move_track(src, tr, after) end
    end
    ImGui.EndDragDropTarget(ctx)
  end
end

-- REAPER's own track context menu (the one you get right-clicking a track's control panel), at the mouse
-- kind: 'track_panel' (default) or another ShowPopupMenu name, e.g. 'track_input' (the meter's recording menu)
local function show_track_menu(tr, kind)
  local mx, my = ImGui.GetMousePos(ctx)
  local nx, ny = ImGui.PointConvertNative(ctx, mx, my, true)
  r.ShowPopupMenu(kind or 'track_panel', math.floor(nx), math.floor(ny), nil, tr, 0, 0)
end

local function select_click(tr)
  local master = r.GetMasterTrack(0)
  -- anchor: the last track clicked here, or REAPER's last touched track (e.g. clicked in the main window)
  local anchor = (state.sel_anchor and track_from_guid(state.sel_anchor)) or r.GetLastTouchedTrack()
  if is_fine() and anchor and anchor ~= master and tr ~= master then
    -- Shift: everything between the last clicked track and this one (Cmd/Ctrl+Shift keeps the rest)
    local a = math.floor(r.GetMediaTrackInfo_Value(anchor, 'IP_TRACKNUMBER'))
    local b = math.floor(r.GetMediaTrackInfo_Value(tr, 'IP_TRACKNUMBER'))
    if a > b then a, b = b, a end
    r.PreventUIRefresh(1)
    if not is_ctrl() then
      for i = 0, r.CountTracks(0) - 1 do r.SetTrackSelected(r.GetTrack(0, i), false) end
      r.SetTrackSelected(master, false)
    end
    for n = a, b do r.SetTrackSelected(r.GetTrack(0, n - 1), true) end
    r.PreventUIRefresh(-1)
    return                                        -- the anchor stays, like REAPER
  end
  if is_ctrl() then r.SetTrackSelected(tr, not r.IsTrackSelected(tr)) else r.SetOnlyTrackSelected(tr) end
  state.sel_anchor = r.GetTrackGUID(tr)
end

local function panel_background_hit(tr, y0)
  local hb = hit('##panelbg', X(0), Y(y0 + 5), X(DESIGN_W), Y(y0 + 193))
  track_drag_source(tr)
  if hb.click then select_click(tr) end
  if hb.rclick then show_track_menu(tr) end
  if hb.dbl then
    if not r.IsTrackSelected(tr) then r.SetOnlyTrackSelected(tr) end
    r.Main_OnCommand(40914, 0)                  -- make it the last touched track too
    run_mouse_modifier('MM_CTX_MCP_DBLCLK')      -- e.g. your color palette script
  end
end

local function draw_panel(tr, is_master, y0)
  local pr, pg, pb = main_sec_rgb(tr)
  G.panel = rgba(pr, pg, pb)
  G.pan_label = (brightness(pr, pg, pb) < 150) and gray(220) or gray(38)
  rect(X(0), Y(y0), X(DESIGN_W), Y(y0 + 193), G.panel)
  if not is_master then
    -- positions from the theme's rtconfig (recinputBg_h / recmodeBg_h / fxin), at 200%
    local ri = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_RECINPUT'))
    local hri = dropdown('##recin', 12, y0 + 12, DESIGN_W - 12, y0 + 52, recinput_name(ri), 'Record input')
    if hri.click then ImGui.OpenPopup(ctx, 'recin_menu') end
    if hri.rclick then show_track_menu(tr, 'track_input') end
    local rm = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_RECMODE'))
    local rmimg = img('mcp_recmode_' .. ((rm == 2) and 'off' or ((rm == 0 or rm == 7 or rm == 8 or rm == 9) and 'in' or 'out')))
    local h = hit('##recmode', X(12), Y(y0 + 60), X(92), Y(y0 + 100), 'Record mode: ' .. (RECMODE[rm] and RECMODE[rm][2] or rm))
    local ccx, ccy = dropdown_bg(12, y0 + 60, 92, y0 + 100, h.hov)
    if rmimg then
      -- the image's lower half holds the horizontal "in / out / x + arrow" row
      local fw, fh = (rmimg.x1 - rmimg.x0) / 3, rmimg.y1 - rmimg.y0
      local f = h.act and 2 or (h.hov and 1 or 0)
      local u0, v0 = rmimg.x0 + f * fw, rmimg.y0 + fh * 0.475
      local k = rmimg.k * G.s
      local sx, sy = X(ccx) - fw * 0.744 * k, Y(ccy) - fh * 0.275 * k
      ImGui.DrawList_AddImage(G.dl, rmimg.img, sx, sy, sx + fw * k, sy + fh * 0.5 * k,
        u0 / rmimg.w, v0 / rmimg.h, (u0 + fw) / rmimg.w, (v0 + fh * 0.5) / rmimg.h)
    else
      text(font_list, fpx(1, 23), X(20), Y(ccy), gray(235), RECMODE[rm] and RECMODE[rm][1] or tostring(rm))
    end
    if h.click then ImGui.OpenPopup(ctx, 'recmode_menu') end

    local nrec = r.TrackFX_GetRecCount(tr)
    local hf = theme_button('##infx', bimg(nrec > 0 and 'track_fx_in_norm' or 'track_fx_in_empty'),
      DESIGN_W - 52, y0 + 60, 'Input FX (' .. nrec .. ')', 'IN FX', 40, 40, COL.infx)
    if hf.click then r.TrackFX_Show(tr, 0x1000000, 1) end
  end
  G.panel_y0 = y0

  local _, p1, p2, pmode = r.GetTrackUIPan(tr)
  local ky = y0 + 160
  local PAN = { 'mcp_pan_knob_stack', 'tcp_pan_knob_stack' }
  local WID = { 'mcp_wid_knob_stack', 'tcp_wid_knob_stack', 'tcp_pan_knob_stack' }
  if pmode == 6 then
    knob(tr, '##panL', DESIGN_W * 0.30, ky, p1, -1, fmt_pan(p1, 'center'), set_pan, PAN)
    knob(tr, '##panR', DESIGN_W * 0.69, ky, p2, 1, fmt_pan(p2, 'center'), set_width, PAN)
  elseif pmode == 5 then
    knob(tr, '##pan', DESIGN_W * 0.30, ky, p1, 0, fmt_pan(p1), set_pan, PAN)
    knob(tr, '##width', DESIGN_W * 0.69, ky, p2, 1, math.floor(p2 * 100 + 0.5) .. '%W', set_width, WID)
  else
    knob(tr, '##pan', DESIGN_W * 0.477, ky, p1, 0, fmt_pan(p1), set_pan, PAN)
  end
  panel_background_hit(tr, y0)
end

local function cfg_num(name, fallback)
  if not r.get_config_var_string then return fallback end
  local ok, v = r.get_config_var_string(name)
  return (ok and tonumber(v)) or fallback
end

-- Meter ballistics like REAPER's mixer: instant rise, held until the next update tick,
-- then falls at the decay rate (Preferences > Track Control Panels: meter update frequency / meter decay).
-- REAPER's values are read if found; otherwise these defaults are used (change them here if you like).
local METER_HZ, METER_DECAY = 12, 120      -- your REAPER prefs: meter update frequency (Hz), meter decay (dB/s)
local meter_hz, meter_decay
local meter_state = {}
local function meter_db(tr, ch)
  if not meter_hz then meter_hz, meter_decay = METER_HZ, METER_DECAY end
  local key = r.GetTrackGUID(tr) .. ch
  local now = r.time_precise()
  local raw = val2db(r.Track_GetPeakInfo(tr, ch))
  local st = meter_state[key]
  if not st then st = { disp = raw, acc = -150, t = now }; meter_state[key] = st end
  if raw > st.acc then st.acc = raw end
  local dt = now - st.t
  if dt >= 1 / meter_hz then
    st.disp = math.max(st.acc, st.disp - meter_decay * dt)
    st.acc, st.t = -150, now
  end
  return st.disp
end

local function draw_meter(tr, mt, mb)
  local M = G.meter or { a1 = 0, a2 = 25, b1 = 27, b2 = 52, lx = 26 }
  -- REAPER Preferences > Appearance > Track control panels: meter range
  local vmax = cfg_num('vumaxvol', 6)
  local vmin = cfg_num('vuminvol', -62)
  if vmax <= vmin then vmax, vmin = 6, -62 end
  local function my(db) return mt + (vmax - clamp(db, vmin, vmax)) / (vmax - vmin) * (mb - mt) end

  local hold = math.max(r.Track_GetPeakHoldDB(tr, 0, false), r.Track_GetPeakHoldDB(tr, 1, false)) * 100
  local armed = r.GetMediaTrackInfo_Value(tr, 'I_RECARM') == 1
  -- meter_strip_v column pairs (unlit, lit): 0 = normal, 1 = clipped (orange), 2 = record armed,
  -- 3 = clipped while armed (red)
  local pair = (hold > 0) and (armed and 3 or 1) or (armed and 2 or 0)
  local strip = img('meter_strip_v')
  local lvl = {}
  -- the track's meter mode (right-click the meter > Meters): stereo peaks is drawn below as before;
  -- the other modes are drawn here. RMS / loudness values come from channels 1024 / 1025.
  local vum = M.master and 0 or math.floor(r.GetMediaTrackInfo_Value(tr, 'I_VUMODE'))
  local vmode, vdis = vum & 30, (vum & 1) ~= 0
  if vdis or vmode ~= 0 then
    local rs = img('meter_strip_v_rms')
    local function column(x1, x2, db, use_rms)
      local im = use_rms and rs or strip
      local p = use_rms and 0 or pair
      local ly = my(db)
      if im then
        local cw = (im.x1 - im.x0) / 8
        local uu, ul = im.x0 + p * 2 * cw, im.x0 + p * 2 * cw + cw
        ImGui.DrawList_AddImage(G.dl, im.img, X(x1), Y(mt), X(x2), Y(mb),
          (uu + 0.5) / im.w, (im.y0 + 0.5) / im.h, (uu + cw - 0.5) / im.w, (im.y1 - 0.5) / im.h)
        if not vdis and db > vmin and ly < mb then
          local v0 = use_rms and (im.y0 + 0.5) or (im.y0 + (ly - mt) / (mb - mt) * (im.y1 - im.y0))
          ImGui.DrawList_AddImage(G.dl, im.img, X(x1), Y(ly), X(x2), Y(mb),
            (ul + 0.5) / im.w, v0 / im.h, (ul + cw - 0.5) / im.w, (im.y1 - 0.5) / im.h)
        end
      else
        rect(X(x1), Y(mt), X(x2), Y(mb), COL.bg)
        if not vdis and db > vmin then rect(X(x1), Y(ly), X(x2), Y(mb), theme_col('col_vubot', 0x23A101FF)) end
      end
    end
    lvl[0], lvl[1] = -150, -150
    if vdis then                                         -- meter disabled: unlit only
      column(M.a1, M.a2, -150, false); column(M.b1, M.b2, -150, false)
    elseif vmode == 2 then                               -- multichannel peaks: one column per track channel
      local n = math.max(2, math.floor(r.GetMediaTrackInfo_Value(tr, 'I_NCHAN')))
      local gap = 2
      local w = (M.b2 - M.a1 - gap * (n - 1)) / n
      for ch = 0, n - 1 do
        local db = meter_db(tr, ch)
        lvl[0] = math.max(lvl[0], db)
        local x1 = M.a1 + ch * (w + gap)
        column(x1, x1 + w, db, false)
      end
    elseif vmode == 4 then                               -- stereo RMS
      for ch = 0, 1 do
        local db = meter_db(tr, 1024 + ch); lvl[ch] = db
        column(ch == 0 and M.a1 or M.b1, ch == 0 and M.a2 or M.b2, db, true)
      end
    else                                                 -- combined RMS / LUFS: one column
      local db = meter_db(tr, 1024); lvl[0] = db
      column(M.a1, M.b2, db, true)
    end
  end
  for ch = 0, 1 do
    if vdis or vmode ~= 0 then break end
    local x1 = ch == 0 and M.a1 or M.b1
    local x2 = ch == 0 and M.a2 or M.b2
    local db = meter_db(tr, ch); lvl[ch] = db
    local ly = my(db)
    if strip then
      local cw = (strip.x1 - strip.x0) / 8
      local ch_h = strip.y1 - strip.y0
      local uu = strip.x0 + pair * 2 * cw          -- unlit column
      local ul = uu + cw                           -- lit column
      ImGui.DrawList_AddImage(G.dl, strip.img, X(x1), Y(mt), X(x2), Y(mb),
        (uu + 0.5) / strip.w, strip.y0 / strip.h, (uu + cw - 0.5) / strip.w, strip.y1 / strip.h)
      if db > vmin and ly < mb then
        local f = (ly - mt) / (mb - mt)
        ImGui.DrawList_AddImage(G.dl, strip.img, X(x1), Y(ly), X(x2), Y(mb),
          (ul + 0.5) / strip.w, (strip.y0 + f * ch_h) / strip.h, (ul + cw - 0.5) / strip.w, strip.y1 / strip.h)
      end
    else
      rect(X(x1), Y(mt), X(x2), Y(mb), armed and 0x402820FF or COL.bg)
      if db > vmin then rect(X(x1), Y(ly), X(x2), Y(mb), theme_col('col_vubot', 0x23A101FF)) end
    end
  end

  -- clip light: the meter's top section (above 0 dB) shows the peak; red when clipped. Click to reset.
  -- tracks: one light across both channels; master: one per channel, each with its own peak readout
  local cy2 = math.max(my(0), mt + 22)
  local clip = img('meter_clip_v')
  local function clip_box(x1, x2, h, cx)
    if clip then
      local fh = (clip.y1 - clip.y0) / 2
      local v0 = clip.y0 + ((h > 0) and fh or 0)
      ImGui.DrawList_AddImage(G.dl, clip.img, X(x1), Y(mt), X(x2), Y(cy2),
        (clip.x0 + 0.5) / clip.w, (v0 + 0.5) / clip.h, (clip.x1 - 0.5) / clip.w, (v0 + fh - 0.5) / clip.h)
    else
      rect(X(x1), Y(mt), X(x2), Y(cy2), (h > 0) and theme_col('col_vuclip', 0xFF0000FF) or COL.bg)
    end
    local show_ro = M.master and tp('masterMcpMeterVals', 1) == 1 or (not M.master and lp('mcpMeterReadout', 1) == 1)
    if show_ro then
      local ptxt = (h > 0 and '+' or '') .. fmt_peak(h)
      local pc = (h > 0) and rgba(clamp(255 * tbm(), 0, 255), clamp(183 * tbm(), 0, 255), clamp(171 * tbm(), 0, 255))
                 or gray(M.master and 150 or 100)
      text(font_bold, 20, X(cx), Y((mt + cy2) / 2), pc, ptxt, 'c')
    end
  end
  if M.master then
    clip_box(M.a1, M.a2, r.Track_GetPeakHoldDB(tr, 0, false) * 100, (M.a1 + M.a2) / 2)
    clip_box(M.b1, M.b2, r.Track_GetPeakHoldDB(tr, 1, false) * 100, (M.b1 + M.b2) / 2)
  else
    clip_box(M.a1, M.b2, hold, M.lx)
  end
  -- scale labels (theme: mcp.meter.scale.color.*; shown per "Mixer Meter Values" layout options)
  local sel = r.IsTrackSelected(tr)
  local show = (armed and lp('mcpMeterValsRecarm', 1) == 1) or (sel and lp('mcpMeterValsSel', 0) == 1)
            or (lp('mcpMeterVals', 0) == 1)
  if M.master then show = tp('masterMcpMeterVals', 1) == 1 end
  if show then
    local unlit = armed and rgba(255, 64, 0, 255)
      or rgba(255, 255, 255, clamp((M.master and 120 or 60) + (tbm() - 1) * 100, 0, 255))
    local litc = rgba(0, 0, 0, 170)
    -- REAPER spaces the labels by 6 dB, doubling the step until they have room
    local px = 6 / (vmax - vmin) * (mb - mt)
    local step = 6
    while px * (step / 6) < 35.5 and step < 48 do step = step * 2 end
    local top = math.max(lvl[0], lvl[1])
    local m = (step == 6) and ((px >= 42) and 0 or -6) or -6
    while m > vmin + 1 do
      local label = '-' .. math.abs(m) .. '-'
      text(font_bold, 18, X(M.lx), Y(my(m)), (top >= m) and litc or unlit, label, 'c')   -- matched to the real mixer
      m = m - step
    end
  end
  local h = hit('##clip', X(M.a1), Y(mt), X(M.b2), Y(cy2), 'Peak hold / clip indicator (click to reset)')
  if h.rclick and not M.master then show_track_menu(tr, 'track_input') end
  if h.click then r.Track_GetPeakHoldDB(tr, 0, true); r.Track_GetPeakHoldDB(tr, 1, true) end
end

-- empty background of the fader section: drag to move the window (submitted after the controls,
-- so buttons, meter clip lights etc. still get their clicks)
local function window_drag_area(id, x1, y1, x2, y2)
  local h = hit(id, X(x1), Y(y1), X(x2), Y(y2))
  if h.act and not state.docked then
    local dx, dy = ImGui.GetMouseDelta(ctx)
    if dx ~= 0 or dy ~= 0 then
      local wx, wy = ImGui.GetWindowPos(ctx)
      ImGui.SetWindowPos(ctx, wx + dx, wy + dy)
    end
  end
  return h
end

-- Fader background color for the track's automation mode, like the mixer. REAPER takes it from the theme:
--   col_fadearm2 = automation playing (READ), col_fadearm3 = TOUCH / LATCH / LATCH PREVIEW not writing,
--   col_fadearm  = automation writing (WRITE, and TOUCH / LATCH once the fader is touched during playback).
-- Drawn at 50% over the strip (measured: READ 19,69,55 and TOUCH 83,59,19 on the 38,38,38 background).
-- TRIM/READ and the global "bypass" override: no color.
-- Faders grabbed in REAPER itself (mixer or track panel). REAPER doesn't report mouse touches to scripts,
-- so with js_ReaScriptAPI: when the left button goes down, whatever is under the mouse is checked; if
-- it's a track's volume fader (mcp.volume / tcp.volume), that track counts as touched until release.
-- Called once per frame from the main loop.
local function update_reaper_touch()
  local playing = (r.GetPlayState() & 5) ~= 0          -- counts stops, for LATCH
  if state.was_playing and not playing then state.stops = (state.stops or 0) + 1 end
  state.was_playing = playing
  if not r.JS_Mouse_GetState then return end
  local down = (r.JS_Mouse_GetState(1) & 1) == 1
  if down and not state.mouse_was_down then
    local x, y = r.GetMousePosition()
    local t, info = r.GetThingFromPoint(x, y)
    state.reaper_touch = (t and info and info:match('^[mt]cp%.volume')) and r.GetTrackGUID(t) or nil
  elseif not down then
    state.reaper_touch = nil
  end
  state.mouse_was_down = down
end

local function auto_fader_col(tr)
  local am = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_AUTOMODE'))
  local ov = r.GetGlobalAutomationOverride and r.GetGlobalAutomationOverride() or -1
  if ov == 6 then return end
  if ov >= 0 and ov <= 5 then am = ov end
  if am <= 0 then return end
  local key
  if am == 1 then key = 'col_fadearm2'
  elseif am == 3 then key = 'col_fadearm'
  else
    local g = r.GetTrackGUID(tr)
    state.latched = state.latched or {}
    -- once grabbed: LATCH stays red until playback stops; LATCH PREVIEW stays red (also after stopping)
    -- until the track leaves that mode
    -- switching between LATCH and LATCH PREVIEW keeps it red, like REAPER (as LATCH it then clears at the next stop)
    local L = state.latched[g]
    if L and L.mode ~= am and (am == 4 or am == 5) then L.mode, L.stops = am, state.stops or 0 end
    if L and (L.mode ~= am or (am == 4 and L.stops ~= (state.stops or 0))) then state.latched[g] = nil end
    -- touched: this window's fader, REAPER's fader (mouse), or a control surface's touch-sensitive fader
    -- (red while held even when stopped, like REAPER)
    local touching = state.fader_touch == g or state.reaper_touch == g
      or (r.CSurf_GetTouchState and r.CSurf_GetTouchState(tr, 0) == true)
    if (am == 4 or am == 5) and touching then state.latched[g] = { mode = am, stops = state.stops or 0 } end
    key = (touching or state.latched[g]) and 'col_fadearm' or 'col_fadearm3'
  end
  -- like the mixer: no color while the track's volume envelope is hidden (or doesn't exist)
  if not state.vol_env_visible(tr) then return end
  local fb = ({ col_fadearm = 0xC6113CFF, col_fadearm2 = 0x006448FF, col_fadearm3 = 0x805000FF })[key]
  return (theme_col(key, fb) & ~0xFF) | 0x80
end

-- Is the track's volume envelope (the fader's, post-FX) shown? REAPER 7 answers directly ("VISIBLE");
-- otherwise the envelope's "VIS" line is read, checked again every half second.
-- (A state field, not a local: the main chunk is at Lua's 200-local limit.)
state.env_vis = {}
state.vol_env_visible = function(tr)
  local env = r.GetTrackEnvelopeByChunkName(tr, '<VOLENV2')
  if not env then return false end
  local ok, v = r.GetSetEnvelopeInfo_String(env, 'VISIBLE', '', false)
  if ok and v ~= '' then return v ~= '0' end
  local k, now = tostring(env), r.time_precise()
  local c = state.env_vis[k]
  if not c or now - c.t > 0.5 then
    local ok2, ch = r.GetEnvelopeStateChunk(env, '', true)
    local vis = ok2 and ch:match('\n%s*VIS%s+(%d)')
    c = { v = vis ~= nil and vis ~= '0', t = now }
    state.env_vis[k] = c
  end
  return c.v
end

local function draw_fader(tr, gt, gb)
  local _, vol = r.GetTrackUIVolPan(tr)
  local db = val2db(vol)
  local GX = G.fader_x or 81          -- groove center (design)
  local thumb = img('mcp_volthumb')
  local groove = img('mcp_volbg')
  local cap_h = thumb and (thumb.y1 - thumb.y0) * thumb.k or 86
  local cap_w = thumb and (thumb.x1 - thumb.x0) * thumb.k or 42
  local HALF = 43
  local tt, tb = gt + HALF, gb - HALF

  local acol = auto_fader_col(tr)
  if groove then
    local gw = (groove.x1 - groove.x0) * groove.k
    -- tracks: REAPER draws the groove image 2 px wider than it is, and its middle (the black groove)
    -- stretches: 6 px instead of 4 (measured). The master keeps the image's own width (4 px, measured).
    if tr ~= r.GetMasterTrack(0) then gw = gw + 2 end
    local x1, y1, x2, y2 = GX - gw / 2, gt - groove.T * groove.k, GX + gw / 2, gb + groove.B * groove.k
    nine(groove, x1, y1, x2, y2)
    -- automation mode: REAPER lays the mode's color over the whole groove image area at 50%
    -- (measured: groove image 50 px wide incl. its transparent edges, 18 px above / below the groove)
    if acol then rect(X(x1), Y(y1), X(x2), Y(y2), acol) end
  else
    rect(X(GX - 3), Y(gt), X(GX + 3), Y(gb), COL.groove)
    if acol then rect(X(GX - 25), Y(gt - 18), X(GX + 25), Y(gb + 18), acol) end
  end

  local h = hit('##fader', X(GX - 26), Y(gt), X(GX + 26), Y(gb),
    'Drag the cap: volume  |  Shift: fine\nDrag the empty fader track: move the window\nDouble-click / Alt-click: 0 dB')
  local p = pos_of(db)
  -- pressing the empty fader track (not the cap) moves the whole window instead
  if h.activated then
    local _, my = ImGui.GetMousePos(ctx)
    local vy0 = tb - p * (tb - tt)
    local on_cap = my >= Y(vy0 - 44) and my <= Y(vy0 + 44)
    state.fader_win = (not on_cap) and G.sid or nil
  end
  local moving = state.fader_win == G.sid
  if moving then
    if h.act and not state.docked then
      local dx, dy = ImGui.GetMouseDelta(ctx)
      if dx ~= 0 or dy ~= 0 then
        local wx, wy = ImGui.GetWindowPos(ctx)
        ImGui.SetWindowPos(ctx, wx + dx, wy + dy)
      end
    end
    if h.dbl then set_vol(tr, 1, true); p = pos_of(0) end
    if h.deactivated or not h.act then state.fader_win = nil end
  else
    -- remembered for the automation color: touching the fader makes TOUCH / LATCH write
    if h.act then state.fader_touch = G.sid elseif state.fader_touch == G.sid then state.fader_touch = nil end
    local nv, done = drag_value('fader', h, p, 0, 1, pos_of(0), 0, 1 / ((tb - tt) * G.s), 0.01)
    if nv then set_vol(tr, vol_of_pos(nv), done); p = nv end
    -- while held, the cap follows the mouse even if an envelope is playing (READ mode), like the mixer;
    -- on release it goes back to whatever the automation says
    if drag[G.sid .. 'fader'] then p = drag[G.sid .. 'fader'] end
    if h.act then ImGui.SetTooltip(ctx, fmt_vol(val2db(vol_of_pos(p)))) end
  end

  -- 0 dB line (unity): like REAPER, a 1-pixel line across the groove at the fader's 0 dB position, under the cap.
  -- Color = the theme's mcp_vol_zeroline (rtconfig, AARRGGBB). Measured: 1 px left of the cap to 2 px right of it.
  do
    if Theme.zl_dir ~= Theme.dir then
      Theme.zl_dir, Theme.zl_col = Theme.dir, nil
      local d = Theme.dir and read_all(Theme.dir .. '/rtconfig.txt')
      local hx = d and d:match('\nmcp_vol_zeroline%s+(%x%x%x%x%x%x%x%x)')
      if hx then
        local A, R, Gc, B = tonumber(hx:sub(1, 2), 16), tonumber(hx:sub(3, 4), 16), tonumber(hx:sub(5, 6), 16), tonumber(hx:sub(7, 8), 16)
        Theme.zl_col = (R << 24) | (Gc << 16) | (B << 8) | A
      end
    end
    local zc = Theme.zl_col or 0x666666FF
    if zc & 0xFF > 0 then
      local zy = math.floor(tb - pos_of(0) * (tb - tt))
      local zx1, zx2 = GX - cap_w / 2 - 1, GX + cap_w / 2 + 2
      G.hline(X(zx1), X(zx2), Y(zy), zc)
    end
  end

  local vy = tb - p * (tb - tt)
  if thumb then
    draw_img(thumb, GX - cap_w / 2, vy - cap_h / 2, 0, 1, false, nil, true)
  else
    rect(X(GX - 21), Y(vy - 43), X(GX + 21), Y(vy + 43), T(170, .4), 3 * G.s)
    ImGui.DrawList_AddLine(G.dl, X(GX - 21), Y(vy), X(GX + 21), Y(vy), 0x202020FF, 2 * G.s)
  end
  return db
end

-- track under the mouse: one of this window's strips, or anywhere in REAPER (TCP/MCP)
route_target = function()
  local mx, my = ImGui.GetMousePos(ctx)
  for _, sr in ipairs(state.strip_rects or {}) do
    if mx >= sr[1] and mx < sr[2] and my >= sr[3] and my < sr[4] then return sr[5] end
  end
  if ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_RootAndChildWindows) then return end
  local nx, ny = ImGui.PointConvertNative(ctx, mx, my, true)
  return (r.GetTrackFromPoint(math.floor(nx), math.floor(ny)))
end

local ENV_SUFFIX = { [0] = '', '_read', '_touch', '_write', '_latch', '_preview' }

local function draw_lower(tr, is_master, LT, MT, MB)
  -- volume / peak readouts (theme text, not images)
  -- the meter/fader side moves right as the strip gets wider than 86 pt (measured: +6 at 90 pt)
  local ox0 = G.ox
  G.ox = ox0 + (DESIGN_W - 172) * 0.75 * G.s
  local _, vol = r.GetTrackUIVolPan(tr)
  local h = hit('##volread', X(5), Y(LT + 17), X(100), Y(LT + 38), 'Click to type a value')
  text(font_list, fpx(1, 23) * 0.88, X(50), Y(LT + 27), gray(h.hov and 190 or 150), fmt_vol(val2db(vol)), 'c')
  if h.click then state.vol_buf = fmt_peak(val2db(vol)); state.focus = true; ImGui.OpenPopup(ctx, 'vol_input') end


  draw_meter(tr, MT, MB)
  G.meter_rect = { X(0), Y(MT), X(52), Y(MB) }
  draw_fader(tr, LT + 70, MB - 17)
  G.ox = ox0

  local BX = DESIGN_W - 52
  -- theme rule (mcpFollow): a button whose bottom + 6 pt margin reaches past the buttons section
  -- (= the top of the name area) is hidden. Heights are the theme's (verbose layout), in design units.
  local function fits(y, hh) return not G.btn_limit or (y + hh + 12) <= G.btn_limit end
  -- mute / solo
  local _, muted = r.GetTrackUIMute(tr)
  h = theme_button('##mute', bimg(muted and 'mcp_mute_on' or 'mcp_mute_off', muted and 'track_mute_on' or 'track_mute_off'),
    BX, LT + 14, 'Mute', 'M', 40, 40, muted and COL.mute_on)
  if h.click then r.SetTrackUIMute(tr, -1, IGN) end

  if not is_master then
    local soloed = r.GetMediaTrackInfo_Value(tr, 'I_SOLO') > 0
    h = theme_button('##solo', bimg(soloed and 'mcp_solo_on' or 'mcp_solo_off', soloed and 'track_solo_on' or 'track_solo_off'),
      BX, LT + 58, 'Solo  |  Ctrl/Cmd-click: exclusive', 'S', 40, 40, soloed and COL.solo_on)
    if h.click then
      if is_ctrl() then
        r.PreventUIRefresh(1); r.Main_OnCommand(40340, 0); r.SetTrackUISolo(tr, 1, IGN); r.PreventUIRefresh(-1)
      else r.SetTrackUISolo(tr, -1, IGN) end
    end
  end

  -- ROUTE (image changes with sends / receives / master send off)
  local sends = r.GetTrackNumSends(tr, 0) + r.GetTrackNumSends(tr, 1) > 0
  local recvs = r.GetTrackNumSends(tr, -1) > 0
  local dis = (not is_master) and r.GetMediaTrackInfo_Value(tr, 'B_MAINSEND') == 0
  local io = 'mcp_io' .. (sends and '_s' or '') .. (recvs and '_r' or '') .. (dis and '_dis' or '')
  if fits(LT + 106, 64) then
  h = theme_button('##route', bimg(io, 'mcp_io'), BX, LT + 106,
    'Routing  |  Option-click: toggle master send\nDrag onto another track (here or in REAPER) to send to it', 'ROUTE', 40, 40)
  if h.rclick then show_track_menu(tr, 'track_routing') end   -- REAPER's own routing menu
  if h.activated then state.route_drag = { moved = false } end
  if h.act and state.route_drag and ImGui.IsMouseDragging(ctx, ImGui.MouseButton_Left, 6) then
    state.route_drag.moved = true
    local t = route_target()
    local tip = 'Drop on a track to send to it'
    if t and t ~= tr then local n, nm = track_name(t); tip = 'Send to ' .. n .. (nm ~= n and (': ' .. nm) or '') end
    ImGui.SetTooltip(ctx, tip)
  end
  local dragged = false
  if h.deactivated and state.route_drag then
    dragged = state.route_drag.moved
    state.route_drag = nil
    if dragged then
      local t = route_target()
      if t and t ~= tr then undo_wrap('Create send', function() r.CreateTrackSend(tr, t) end) end
    end
  end
  if h.click and not dragged and is_alt() and not is_master then
    -- Option/Alt-click: toggle the track's master/parent send, like the mixer
    local on = r.GetMediaTrackInfo_Value(tr, 'B_MAINSEND') == 1
    undo_wrap('Toggle master/parent send', function() r.SetMediaTrackInfo_Value(tr, 'B_MAINSEND', on and 0 or 1) end)
  elseif h.click and not dragged then
    if not r.IsTrackSelected(tr) then r.SetOnlyTrackSelected(tr) end
    r.Main_OnCommand(40914, 0) -- set first selected track as last touched
    r.Main_OnCommand(40293, 0); state.no_refocus = true -- routing window for last touched track
  end
  end

  -- FX + bypass
  local nfx = r.TrackFX_GetCount(tr)
  local fx_en = r.GetMediaTrackInfo_Value(tr, 'I_FXEN') == 1
  local fxn = nfx == 0 and 'empty' or (fx_en and 'norm' or 'dis')
  if fits(LT + 182, 72) then
  h = theme_button('##fx', bimg('mcp_fx_' .. fxn, 'track_fx_' .. fxn), BX, LT + 182, 'FX chain', 'FX', 40, 40, COL.btn_dark)
  if h.click then
    if r.TrackFX_GetChainVisible(tr) ~= -1 then r.TrackFX_Show(tr, 0, 0) else r.TrackFX_Show(tr, 0, 1) end
  end
  local byn = nfx == 0 and 'track_fxempty_v' or (fx_en and 'track_fxon_v' or 'track_fxoff_v')
  h = theme_button('##fxbyp', bimg(byn), BX, LT + 222, fx_en and 'Bypass all FX' or 'FX bypassed', 'on', 40, 34,
    fx_en and COL.btn_light or COL.fxbyp_on)
  if h.click then
    undo_wrap('Toggle track FX bypass', function() r.SetMediaTrackInfo_Value(tr, 'I_FXEN', fx_en and 0 or 1) end)
  end
  end

  -- automation (image includes the TRIM / READ / TOUCH... label)
  local am = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_AUTOMODE'))
  if fits(LT + 265, 64) then
    h = theme_button('##env', bimg('mcp_env' .. (ENV_SUFFIX[am] or ''), 'mcp_env'), BX, LT + 265, 'Automation mode',
      (AUTO[am] or AUTO[0])[2], 40, 40)
    if h.click then ImGui.OpenPopup(ctx, 'automode_menu') end
  end

  -- polarity sits under TRIM
  if not is_master and fits(LT + 336, 32) then
    local ph = r.GetMediaTrackInfo_Value(tr, 'B_PHASE') == 1
    h = theme_button('##phase', bimg(ph and 'mcp_phase_inv' or 'mcp_phase_norm', ph and 'track_phase_inv' or 'track_phase_norm'),
      BX, LT + 336, 'Invert polarity', 'ø', 40, 32, ph and COL.phase_on)
    if h.click then
      undo_wrap('Toggle track phase', function() r.SetMediaTrackInfo_Value(tr, 'B_PHASE', ph and 0 or 1) end)
    end
    if h.rclick then show_track_menu(tr) end   -- REAPER's own track menu
  end

  -- bottom row: monitor, rec arm, phase
  if not is_master then
    local mon = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_RECMON'))
    local mn = ({ [0] = 'off', 'on', 'auto' })[mon] or 'off'
    local LX = (DESIGN_W - 172) * 0.75
    h = theme_button('##mon', bimg('mcp_monitor_' .. mn, 'track_monitor_' .. mn), 8 + LX, MB + 8,
      'Input monitoring: off > on > auto', mn, 40, 40)
    if h.click then r.SetTrackUIInputMonitor(tr, (mon + 1) % 3, IGN) end

    local armed = r.GetMediaTrackInfo_Value(tr, 'I_RECARM') == 1
    local auto = r.GetMediaTrackInfo_Value(tr, 'B_AUTO_RECARM') == 1
    local norec = armed and r.GetMediaTrackInfo_Value(tr, 'I_RECMODE') == 2
    local rn = 'track_recarm' .. (auto and '_auto' or '') .. (norec and '_norec' or (armed and '_on' or (auto and '' or '_off')))
    h = theme_button('##arm', bimg(rn, armed and 'track_recarm_on' or 'track_recarm_off'), 56 + LX, MB + 8,
      'Record arm', 'R', 44, 44, armed and COL.rec_on)
    if h.click then r.SetTrackUIRecArm(tr, -1, IGN) end
    if h.rclick then show_track_menu(tr, 'track_input') end   -- REAPER's own recording menu

  end
end

local function start_rename(tr)
  if tr == r.GetMasterTrack(0) then return end
  local _, n = r.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', false)
  state.name_buf, state.renaming, state.rename_focus = n, r.GetTrackGUID(tr), true
end

-- track name (theme rule: red when armed, track-colored label when the track has a color, else light gray)
local function draw_name(tr, y1, y2)
  local _, name = r.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', false)
  local fs = fpx(lp('mcpLabelSize', 4), 32)

  -- typing the name right in the label, like the mixer
  if state.renaming == G.sid then
    -- ImGui text fields are left-aligned. To keep the name centered while typing, the (invisible) field
    -- starts wherever the centered text should start and runs to the right edge, so it never has to
    -- scroll; it's moved every frame as the name gets longer or shorter.
    ImGui.PushFont(ctx, font_rename or font_list)
    local left, right = X(4), X(DESIGN_W - 4)
    local tw = ImGui.CalcTextSize(ctx, state.name_buf)
    local sx = math.max(left, X(DESIGN_W / 2) - tw / 2 - 1)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 2)
    local fh = ImGui.GetFrameHeight(ctx)
    rect(left, (Y(y1) + Y(y2) - fh) / 2, right, (Y(y1) + Y(y2) + fh) / 2, 0xFFFFFFFF)   -- white field while renaming, like REAPER
    ImGui.SetCursorScreenPos(ctx, sx, (Y(y1) + Y(y2) - fh) / 2)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x00000000)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x000000FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_TextSelectedBg, 0x3D8BFF70)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 0)
    ImGui.SetNextItemWidth(ctx, right - sx)
    if state.rename_focus then ImGui.SetKeyboardFocusHere(ctx); state.rename_focus = false end
    local enter, buf = ImGui.InputText(ctx, '##rename_inline', state.name_buf,
      ImGui.InputTextFlags_EnterReturnsTrue | ImGui.InputTextFlags_AutoSelectAll)
    state.name_buf = buf
    local deact = ImGui.IsItemDeactivated(ctx)
    ImGui.PopStyleVar(ctx, 2); ImGui.PopStyleColor(ctx, 3)
    ImGui.PopFont(ctx)
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
      state.renaming = nil                                   -- Esc: cancel
    elseif enter or deact then                               -- Enter or click away: keep it
      state.renaming = nil
      if buf ~= name then
        undo_wrap('Rename track', function() r.GetSetMediaTrackInfo_String(tr, 'P_NAME', buf, true) end)
      end
    end
    return
  end

  local h = hit('##name', X(0), Y(y1), X(DESIGN_W), Y(y2), 'Double-click: rename track  |  Drag: move track  |  Right-click: choose tracks')
  track_drag_source(tr)
  if h.rclick then ImGui.OpenPopup(ctx, 'bar_menu') end
  if name ~= '' then
    local armed = r.GetMediaTrackInfo_Value(tr, 'I_RECARM') == 1
    local col
    if tp('selInvertLabels', 0) == 1 and r.IsTrackSelected(tr) then
      rect(X(0), Y(y1), X(DESIGN_W), Y(y2), rgba(255, 255, 255, 100))
      col = armed and rgba(180, 0, 10) or rgba(38, 38, 38)
    elseif armed then col = rgba(255, 80, 100)
    elseif track_rgba and tp('colorTrackLabels', 1) == 1 then
      local R, G_, B = (track_rgba >> 24) & 255, (track_rgba >> 16) & 255, (track_rgba >> 8) & 255
      if brightness(R, G_, B) < 85 then R, G_, B = 100 + 2 * R, 100 + 2 * G_, 100 + 2 * B end
      col = rgba(R, G_, B)
    else col = gray(200) end
    local lf = font_label or font_list
    local lfs = fs * label_fix(lf)
    text(lf, lfs, X(DESIGN_W / 2), Y((y1 + y2) / 2), col, fit(lf, lfs, name, (DESIGN_W - 8) * G.s), 'c')
  end
  if h.dbl then start_rename(tr) end
end

local function draw_bar(tr, BT, BB)
  local num, name = track_name(tr)
  local bg = track_rgba or rgba(tp('mcpBgColR', 129), tp('mcpBgColG', 137), tp('mcpBgColB', 137))
  rect(X(0), Y(BT), X(DESIGN_W), Y(BB), bg)
  local bb = brightness((bg >> 24) & 255, (bg >> 16) & 255, (bg >> 8) & 255)
  G.idx_col = (bb > 128) and gray(50 / tbm()) or rgba(clamp(110 * tbm() + 120, 0, 255), clamp(110 * tbm() + 120, 0, 255), clamp(110 * tbm() + 120, 0, 255))
  -- folder button (theme mcp.folder): folders get the collapse button on the left of the bar (40 x 40),
  -- the last track of a folder gets the folder-end edge on the right (12 x 40). The number and the
  -- selection dot move right by 18 on folders, like the theme.
  local fstate = (tr == r.GetMasterTrack(0)) and 0 or r.GetMediaTrackInfo_Value(tr, 'I_FOLDERDEPTH')
  local folder = fstate == 1
  local bx1, bx2 = folder and 40 or 0, DESIGN_W
  local last_im = fstate < 0 and img('mcp_folder_last') or nil
  if last_im then bx2 = DESIGN_W - 12 end
  local h = hit('##bar', X(bx1), Y(BT), X(bx2), Y(BB),
    name .. '\nClick: select (Shift: range, Cmd/Ctrl: toggle)  |  Drag: move track\nDouble-click: rename  |  Right-click: options')
  track_drag_source(tr)
  if h.click and not h.dbl then select_click(tr) end
  if folder then
    local coll = mcp_collapsed(tr)
    local hb = theme_button('##fcomp', bimg(coll and 'mcp_fcomp_tiny' or 'mcp_fcomp_off'), 0, BT,
      coll and 'Show this folder\'s tracks' or 'Hide this folder\'s tracks', coll and '>' or 'v', 40, 40, COL.btn_dark)
    if hb.click then set_mcp_collapsed(tr, not coll) end
    if hb.rclick then show_track_menu(tr) end
  end
  if last_im then draw_img(last_im, DESIGN_W - 12, BT, 0, 3, false, nil, true) end
  local cx = DESIGN_W * 0.465 + (folder and 18 or 0)
  text(font_list, fpx(3, 28), X(cx), Y((BT + BB) / 2), G.idx_col, num, 'c')
  if r.IsTrackSelected(tr) then
    local dot = img('mcp_selectionDot_sel', 'tcp_selectionDot_sel')
    if dot then
      local d = (dot.x1 - dot.x0) * dot.k
      draw_img(dot, cx - d / 2, BT - d / 2, 0, 1, false, nil, true)
    else
      ImGui.DrawList_AddCircleFilled(G.dl, X(cx), Y(BT), 4.5 * G.s, 0xFFFFFFFF)
    end
  end
  if h.dbl then start_rename(tr) end
  if h.rclick then ImGui.OpenPopup(ctx, 'bar_menu') end
end

--------------------------------------------------------------------------------
-- Popups
--------------------------------------------------------------------------------
local function input_popup(id, key, width, on_enter)
  if ImGui.BeginPopup(ctx, id) then
    if state.focus then ImGui.SetKeyboardFocusHere(ctx); state.focus = false end
    ImGui.SetNextItemWidth(ctx, width)
    local enter, buf = ImGui.InputText(ctx, '##' .. id, state[key],
      ImGui.InputTextFlags_EnterReturnsTrue | ImGui.InputTextFlags_AutoSelectAll)
    state[key] = buf
    if enter then on_enter(buf); ImGui.CloseCurrentPopup(ctx) end
    ImGui.EndPopup(ctx)
  end
end

-- choose which tracks the window shows
-- Dock / Undock items (REAPER dockers are negative dock IDs in ReaImGui: -1 = docker 1, -2 = docker 2 ...)
-- Snapshots (like the X32 / XR18 scene list): a fixed number of numbered slots, saved in the project.
-- A snapshot stores which tracks are shown; loading it shows those tracks.
-- Stored in the project as lines "slot<TAB>name<TAB>guid,guid,..." (older "name<TAB>guids" lines get slots 1, 2, ...).
do
  local SLOTS = 64
  local function load_snaps()
    local _, raw = r.GetProjExtState(0, 'Daniel_FloatingMixer', 'snapshots')
    local t, old = {}, {}
    for line in (raw or ''):gmatch('[^\n]+') do
      local slot, name, list = line:match('^(%d+)\t(.-)\t(.*)$')
      if not slot then name, list = line:match('^(.-)\t(.*)$') end
      if name then
        local g = {}
        for x in list:gmatch('[^,]+') do g[#g + 1] = x end
        slot = tonumber(slot)
        if slot and slot >= 1 and slot <= SLOTS then t[slot] = { name = name, guids = g }
        else old[#old + 1] = { name = name, guids = g } end
      end
    end
    for _, sn in ipairs(old) do                -- older format: first free slots
      for i = 1, SLOTS do if not t[i] then t[i] = sn; break end end
    end
    return t
  end
  local function save_snaps(t)
    local out = {}
    for i = 1, SLOTS do
      local sn = t[i]
      if sn then out[#out + 1] = i .. '\t' .. sn.name .. '\t' .. table.concat(sn.guids, ',') end
    end
    r.SetProjExtState(0, 'Daniel_FloatingMixer', 'snapshots', table.concat(out, '\n'))
    r.MarkProjectDirty(0)
  end
  local function clean(n) return ((n or ''):gsub('[\t\r\n]', ' '):gsub('^%s+', ''):gsub('%s+$', '')) end
  local function current_guids()
    local g = {}
    for _, t in ipairs(state.cur_tracks or {}) do g[#g + 1] = r.GetTrackGUID(t) end
    return g
  end
  local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
  end
  local function find_name(t, nm, skip)        -- slot that already uses this name (any case)
    for i = 1, SLOTS do
      if i ~= skip and t[i] and t[i].name:lower() == nm:lower() then return i end
    end
  end
  local function same_set(a, b)                -- same tracks, in any order
    if #a ~= #b then return false end
    local m = {}
    for _, g in ipairs(a) do m[g] = (m[g] or 0) + 1 end
    for _, g in ipairs(b) do if not m[g] or m[g] == 0 then return false end; m[g] = m[g] - 1 end
    return true
  end
  local function find_tracks(t, guids, skip)   -- slot that already holds these tracks
    for i = 1, SLOTS do
      if i ~= skip and t[i] and same_set(t[i].guids, guids) then return i end
    end
  end
  local function recall(sn)
    state.list = {}
    for _, g in ipairs(sn.guids) do state.list[#state.list + 1] = g end
    state.mode = 'list'; save_choice()
  end

  -- Snapshots window: numbered slots. Click a slot to select it, then Load / Save / Rename / Delete
  -- (or right-click the slot). Double-click: load a full slot, save into an empty one.
  -- Saving into an empty slot asks for the name right in the slot; saving over a full one asks first.
  state.snapshot_window = function()
    state.snap_typing = false
    if not state.snap_win then return end
    ImGui.SetNextWindowSize(ctx, 300, 420, ImGui.Cond_FirstUseEver)
    local title = 'Snapshots (Mixer ' .. CUR_WIN .. ')###DFM_snapshots'
    local wcol = state.win_color(CUR_WIN)            -- the color of the mixer window it belongs to
    ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive, wcol)
    ImGui.PushStyleColor(ctx, ImGui.Col_TitleBg, state.dim_color(wcol, 0.55))
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, state.text_on(wcol))
    local visible, open = ImGui.Begin(ctx, title, true, ImGui.WindowFlags_NoCollapse)
    ImGui.PopStyleColor(ctx, 3)
    if visible then
      do -- a colored strip along the top (the only color you see when it's docked)
        local px, py = ImGui.GetWindowPos(ctx)
        local y = py + (ImGui.IsWindowDocked(ctx) and 0 or ImGui.GetFrameHeight(ctx))
        ImGui.DrawList_AddRectFilled(ImGui.GetWindowDrawList(ctx), px, y, px + ImGui.GetWindowWidth(ctx), y + 4, wcol)
      end
      local snaps = load_snaps()
      local cur = current_guids()
      local sel = state.snap_sel
      local act                                -- action requested this frame: 'load' 'save' 'rename' 'delete'
      local edit = state.snap_edit             -- inline name entry: { slot, buf, kind = 'new' | 'rename', focus }

      local fh = ImGui.GetFrameHeightWithSpacing(ctx)
      -- table: "#" and "Name" columns with a header row, lines between the slots
      local tflags = ImGui.TableFlags_ScrollY | ImGui.TableFlags_BordersOuter | ImGui.TableFlags_BordersInnerH
                   | ImGui.TableFlags_BordersInnerV
      if ImGui.BeginTable(ctx, '##snapslots', 2, tflags, 0, -(fh * 3 + 6)) then
        ImGui.TableSetupScrollFreeze(ctx, 0, 1)                  -- header row stays on top while scrolling
        ImGui.TableSetupColumn(ctx, '#', ImGui.TableColumnFlags_WidthFixed, (ImGui.CalcTextSize(ctx, '000')))
        ImGui.TableSetupColumn(ctx, 'Name', ImGui.TableColumnFlags_WidthStretch)
        ImGui.TableHeadersRow(ctx)
        for i = 1, SLOTS do
          local sn = snaps[i]
          local num = string.format('%02d', i)
          ImGui.TableNextRow(ctx)
          ImGui.TableNextColumn(ctx)
          if edit and edit.slot == i then
            -- typing the name inside the slot: Enter = OK, Escape / click elsewhere = cancel
            ImGui.AlignTextToFramePadding(ctx)
            ImGui.Text(ctx, num)
            ImGui.TableNextColumn(ctx)
            ImGui.SetNextItemWidth(ctx, -1)
            if edit.focus then ImGui.SetKeyboardFocusHere(ctx); edit.focus = false end
            local _, buf = ImGui.InputText(ctx, '##snapedit', edit.buf, ImGui.InputTextFlags_AutoSelectAll)
            edit.buf = buf
            state.snap_typing = ImGui.IsItemActive(ctx)
            if ImGui.IsItemDeactivated(ctx) then
              local ok = ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)
              local nm = clean(edit.buf)
              local ex = (ok and nm ~= '') and find_name(snaps, nm, i)
              if ok and nm ~= '' and ex then
                if edit.kind == 'new' then
                  -- that name is already a snapshot: ask to overwrite it instead of making a second one
                  state.snap_ask = { kind = 'overwrite', slot = ex, name = snaps[ex].name, guids = edit.guids, open = true }
                else
                  state.snap_msg = 'Slot ' .. string.format('%02d', ex) .. ' already uses that name'
                end
              elseif ok and nm ~= '' then
                if edit.kind == 'new' then
                  snaps[i] = { name = nm, guids = edit.guids }; state.snap_msg = 'Saved to ' .. num
                elseif sn then
                  sn.name = nm; state.snap_msg = 'Renamed ' .. num
                end
                save_snaps(snaps)
              end
              state.snap_edit, edit = nil, nil
            end
          else
            -- active slot (its tracks are showing) = whole row in ImGui's blue; selected slot (clicked) = gray row.
            -- Only one fill per row, so the colors never mix. Text keeps its normal color.
            local shown = sn and state.mode == 'list' and same(state.list, sn.guids)
            local blue = ImGui.GetStyleColor(ctx, ImGui.Col_Header)
            local blue_hov = ImGui.GetStyleColor(ctx, ImGui.Col_HeaderHovered)
            local blue_act = ImGui.GetStyleColor(ctx, ImGui.Col_HeaderActive)
            if shown then
              ImGui.PushStyleColor(ctx, ImGui.Col_Header, sel == i and blue_hov or blue)
              ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, blue_hov)
              ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, blue_act)
            else
              ImGui.PushStyleColor(ctx, ImGui.Col_Header, 0xFFFFFF30)          -- selected
              ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, 0xFFFFFF18)   -- mouse over
              ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, 0xFFFFFF38)    -- pressed
            end
            if not sn then ImGui.PushStyleColor(ctx, ImGui.Col_Text, ImGui.GetStyleColor(ctx, ImGui.Col_TextDisabled)) end
            local flags = ImGui.SelectableFlags_SpanAllColumns | ImGui.SelectableFlags_AllowDoubleClick
            if ImGui.Selectable(ctx, num .. '##slot' .. i, shown or sel == i, flags) then
              sel = i
              if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then act = sn and 'load' or 'save' end
            end
            if sn and ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then sel = i; act = 'rename' end   -- right-click: rename
            -- drag a snapshot onto another slot to move it there (the ones in between shift up / down)
            if sn and ImGui.BeginDragDropSource(ctx) then
              ImGui.SetDragDropPayload(ctx, 'DFM_SNAPSLOT', tostring(i))
              ImGui.Text(ctx, 'Move ' .. num .. '  ' .. sn.name)
              ImGui.EndDragDropSource(ctx)
            end
            if ImGui.BeginDragDropTarget(ctx) then
              local rv, data = ImGui.AcceptDragDropPayload(ctx, 'DFM_SNAPSLOT')
              local from = rv and tonumber(data)
              if from and from ~= i and snaps[from] then
                local item = snaps[from]
                if from < i then for k = from, i - 1 do snaps[k] = snaps[k + 1] end
                else for k = from, i + 1, -1 do snaps[k] = snaps[k - 1] end end
                snaps[i] = item
                save_snaps(snaps)
                sel, state.snap_msg = i, 'Moved to ' .. num
              end
              ImGui.EndDragDropTarget(ctx)
            end
            ImGui.TableNextColumn(ctx)
            ImGui.Text(ctx, sn and sn.name or '-')
            ImGui.PopStyleColor(ctx, sn and 3 or 4)
          end
        end
        ImGui.EndTable(ctx)
      end
      state.snap_sel = sel
      local full = sel and snaps[sel] ~= nil

      -- buttons for the selected slot
      local bw = (ImGui.GetContentRegionAvail(ctx) - 2 * 6) / 3
      ImGui.BeginDisabled(ctx, not full)
      if ImGui.Button(ctx, 'Load', bw, 0) then act = 'load' end
      ImGui.EndDisabled(ctx)
      ImGui.SameLine(ctx, 0, 6)
      ImGui.BeginDisabled(ctx, not sel or #cur == 0)
      if ImGui.Button(ctx, 'Save', bw, 0) then act = 'save' end
      ImGui.EndDisabled(ctx)
      ImGui.SameLine(ctx, 0, 6)
      ImGui.BeginDisabled(ctx, not full)
      if ImGui.Button(ctx, 'Delete', bw, 0) then act = 'delete' end
      ImGui.EndDisabled(ctx)

      if act and sel then
        local sn, num = snaps[sel], string.format('%02d', sel)
        if act == 'load' and sn then
          recall(sn); state.snap_msg = 'Loaded ' .. num .. ' ' .. sn.name
        elseif act == 'save' and #cur > 0 then
          local dup = find_tracks(snaps, cur)
          if dup == sel then
            state.snap_msg = num .. ' already has these tracks'
          elseif dup then                       -- another slot already has exactly these tracks
            state.snap_ask = { kind = 'same', slot = dup, name = snaps[dup].name, open = true }
          elseif sn then
            state.snap_ask = { kind = 'overwrite', slot = sel, name = sn.name, guids = cur, open = true }
          else
            state.snap_edit = { slot = sel, buf = 'Snapshot ' .. sel, kind = 'new', guids = cur, focus = true }
          end
        elseif act == 'rename' and sn then
          state.snap_edit = { slot = sel, buf = sn.name, kind = 'rename', focus = true }
        elseif act == 'delete' and sn then
          state.snap_ask = { kind = 'delete', slot = sel, name = sn.name, open = true }
        end
      end

      -- status line + SWS (the mix: levels, mutes, sends... are left to SWS's Snapshots window)
      ImGui.TextDisabled(ctx, state.snap_msg or 'Click a slot, then Load / Save / Delete. Right-click: rename')
      local sws = r.NamedCommandLookup('_SWSSNAPSHOT_OPEN')
      ImGui.BeginDisabled(ctx, sws == 0)
      if ImGui.Button(ctx, 'SWS Snapshots (mix)...', -1, 0) then r.Main_OnCommand(sws, 0); state.no_refocus = true end
      ImGui.EndDisabled(ctx)

      -- confirmation (Yes / No)
      local ask = state.snap_ask
      if ask then
        local ptitle = (ask.kind == 'delete' and 'Delete snapshot?' or ask.kind == 'same' and 'Already saved'
                        or 'Overwrite snapshot?') .. '###snap_ask'
        if ask.open then ImGui.OpenPopup(ctx, ptitle); ask.open = false; ask.frames = 0 end
        ask.frames = (ask.frames or 0) + 1
        local cx, cy = ImGui.Viewport_GetCenter(ImGui.GetWindowViewport(ctx))
        ImGui.SetNextWindowPos(ctx, cx, cy, ImGui.Cond_Appearing, 0.5, 0.5)
        if ImGui.BeginPopupModal(ctx, ptitle, nil, ImGui.WindowFlags_AlwaysAutoResize) then
          local num = string.format('%02d', ask.slot)
          if ask.kind == 'same' then
            ImGui.Text(ctx, 'These tracks are already saved in snapshot ' .. num .. ' "' .. ask.name .. '".')
            ImGui.Spacing(ctx)
            local keys = ask.frames > 2
            if ImGui.Button(ctx, 'OK', 80, 0) or (keys and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter, false)
               or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter, false) or ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false))) then
              state.snap_sel, state.snap_ask = ask.slot, nil
              ImGui.CloseCurrentPopup(ctx)
            end
            ImGui.EndPopup(ctx)
            goto snap_done
          end
          if ask.kind == 'delete' then
            ImGui.Text(ctx, 'Delete snapshot ' .. num .. ' "' .. ask.name .. '"?')
          else
            ImGui.Text(ctx, 'Snapshot ' .. num .. ' "' .. ask.name .. '" already exists.')
            ImGui.Text(ctx, 'Overwrite it with the tracks shown now?')
          end
          ImGui.Spacing(ctx)
          -- keys only count once the window is up, so the Enter that confirmed a name can't also answer Yes
          local keys = ask.frames > 2
          local yes = ImGui.Button(ctx, 'Yes', 80, 0) or (keys and
            (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter, false) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter, false)))
          ImGui.SameLine(ctx)
          local no = ImGui.Button(ctx, 'No', 80, 0) or (keys and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false))
          if yes then
            local list = load_snaps()
            if ask.kind == 'delete' then
              list[ask.slot] = nil; state.snap_msg = 'Deleted ' .. num
            else
              list[ask.slot] = { name = ask.name, guids = ask.guids }
              state.snap_msg = 'Overwrote ' .. num .. ' ' .. ask.name
            end
            save_snaps(list)
            state.snap_sel = ask.slot
          end
          if yes or no then state.snap_ask = nil; ImGui.CloseCurrentPopup(ctx) end
          ImGui.EndPopup(ctx)
        elseif ask.frames > 2 then
          state.snap_ask = nil                   -- closed some other way
        end
      end
      ::snap_done::
      ImGui.End(ctx)
    end
    if not open then state.snap_win, state.snap_edit = false, nil end
  end
end

-- Menu items that don't close their menu when clicked (same as the Meter Bridge). The script uses the
-- ReaImGui 0.9.3 API, where that's a selectable with DontClosePopups; the checkmark is drawn in front of
-- it like a menu item's. (If the newer AutoClosePopups item flag is available, real menu items are used.)
do
  local function const(name) local ok, v = pcall(function() return ImGui[name] end); return ok and v or nil end
  local AUTOCLOSE = const('ItemFlags_AutoClosePopups')
  local NOCLOSE = const('SelectableFlags_NoAutoClosePopups') or const('SelectableFlags_DontClosePopups')
  state.keep_open_begin = function()
    if AUTOCLOSE and const('PushItemFlag') then ImGui.PushItemFlag(ctx, AUTOCLOSE, false); return 'flag' end
    return NOCLOSE and 'selectable' or nil
  end
  state.keep_open_end = function(how) if how == 'flag' then ImGui.PopItemFlag(ctx) end end
  state.check_item = function(label, checked, how)
    if how ~= 'selectable' then return ImGui.MenuItem(ctx, label, nil, checked) end
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local h = ImGui.GetTextLineHeight(ctx)
    local clicked = ImGui.Selectable(ctx, '     ' .. label, false, NOCLOSE)
    if checked then
      local dl, col = ImGui.GetWindowDrawList(ctx), ImGui.GetStyleColor(ctx, ImGui.Col_Text)
      local cy = y + h / 2
      ImGui.DrawList_AddLine(dl, x + 2, cy, x + 5, cy + 3.5, col, 1.6)
      ImGui.DrawList_AddLine(dl, x + 5, cy + 3.5, x + 11, cy - 4, col, 1.6)
    end
    return clicked
  end
end

tracks_menu = function(id)
  if not ImGui.BeginPopup(ctx, id) then return end
  if ImGui.MenuItem(ctx, 'Follow selected tracks', nil, state.mode == 'follow') then
    state.mode = 'follow'; save_choice()
  end
  if ImGui.MenuItem(ctx, 'Show selected tracks') then
    state.list = {}
    for i = 0, r.CountSelectedTracks2(0, true) - 1 do
      local t = r.GetSelectedTrack2(0, i, true)
      if not state.hidden_track(t) then state.list[#state.list + 1] = r.GetTrackGUID(t) end
    end
    state.mode = 'list'; save_choice()
  end
  if ImGui.MenuItem(ctx, 'Clear list') then state.list = {}; state.mode = 'list'; save_choice() end
  ImGui.Separator(ctx)
  ImGui.TextDisabled(ctx, 'Tracks to show:')
  -- the track list stays open while you tick tracks; clicking outside the menu closes it
  local keep = state.keep_open_begin()
  local m = r.GetMasterTrack(0)
  if state.check_item('MASTER', state.mode == 'list' and in_list(r.GetTrackGUID(m)) ~= nil, keep) then
    toggle_in_list(r.GetTrackGUID(m))
  end
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    if not state.hidden_track(t) then
      local g = r.GetTrackGUID(t)
      local _, nm = r.GetSetMediaTrackInfo_String(t, 'P_NAME', '', false)
      if state.check_item((i + 1) .. ': ' .. nm .. '##' .. g, state.mode == 'list' and in_list(g) ~= nil, keep) then
        toggle_in_list(g)
      end
    end
  end
  state.keep_open_end(keep)
  ImGui.EndPopup(ctx)
end

local function fx_menu(tr)
  if not ImGui.BeginPopup(ctx, 'fx_menu') then return end
  local i = state.menu_fx
  if i and i < r.TrackFX_GetCount(tr) then
    local _, nm = r.TrackFX_GetFXName(tr, i, '')
    ImGui.TextDisabled(ctx, clean_fx_name(nm))
    ImGui.Separator(ctx)
    local en, off = r.TrackFX_GetEnabled(tr, i), r.TrackFX_GetOffline(tr, i)
    local floating = r.TrackFX_GetFloatingWindow(tr, i) ~= nil
    if ImGui.MenuItem(ctx, 'Float FX window', nil, floating) then r.TrackFX_Show(tr, i, floating and 2 or 3) end
    if ImGui.MenuItem(ctx, 'Show in FX chain') then r.TrackFX_Show(tr, i, 1) end
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, 'Bypass', 'Shift+click', not en) then
      undo_wrap('Toggle FX bypass', function() r.TrackFX_SetEnabled(tr, i, not en) end)
    end
    if ImGui.MenuItem(ctx, 'Offline', 'Cmd/Ctrl+Shift+click', off) then
      undo_wrap('Toggle FX offline', function() r.TrackFX_SetOffline(tr, i, not off) end)
    end
    if ImGui.MenuItem(ctx, 'Rename FX instance...') then
      local _, cur = r.TrackFX_GetNamedConfigParm(tr, i, 'renamed_name')
      state.fxname_buf, state.fxname_idx, state.focus = cur or '', i, true
      state.open_fx_rename = true
    end
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, 'Delete', 'Alt+click') then
      undo_wrap('Remove FX', function() r.TrackFX_Delete(tr, i) end)
    end
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, 'Add FX...') then
      if not r.IsTrackSelected(tr) then r.SetOnlyTrackSelected(tr) end
      r.Main_OnCommand(40914, 0); r.Main_OnCommand(40271, 0)
    end
    if ImGui.MenuItem(ctx, 'Show FX chain') then r.TrackFX_Show(tr, 0, 1) end
  end
  ImGui.EndPopup(ctx)
end

-- add a send (or hardware output) from an empty send slot; lands in that slot when the mixer allows it
local function add_send_menu(tr)
  if not ImGui.BeginPopup(ctx, 'add_send') then return end
  local function add(dest, hwch)
    undo_wrap('Add send', function()
      local idx = r.CreateTrackSend(tr, dest)
      if idx and idx >= 0 then
        local cat = dest and 0 or 1
        if hwch then r.SetTrackSendInfo_Value(tr, 1, idx, 'I_DSTCHAN', hwch) end
        if state.add_send_slot then r.SetTrackSendInfo_Value(tr, cat, idx, 'I_SLOT_HINT', state.add_send_slot) end
      end
    end)
  end
  ImGui.TextDisabled(ctx, 'Send to:')
  local m = r.GetMasterTrack(0)
  if tr ~= m then
    for i = 0, r.CountTracks(0) - 1 do
      local t = r.GetTrack(0, i)
      if t ~= tr then
        local _, nm = r.GetSetMediaTrackInfo_String(t, 'P_NAME', '', false)
        if ImGui.MenuItem(ctx, (i + 1) .. ': ' .. nm .. '##snd' .. i) then add(t) end
      end
    end
  end
  ImGui.Separator(ctx)
  if ImGui.BeginMenu(ctx, 'Hardware output') then
    local n = r.GetNumAudioOutputs()
    for ch = 0, n - 2, 2 do
      local a, b = r.GetOutputChannelName(ch) or ('Out ' .. (ch + 1)), r.GetOutputChannelName(ch + 1) or ('Out ' .. (ch + 2))
      if ImGui.MenuItem(ctx, a .. ' / ' .. b .. '##hw' .. ch) then add(nil, ch) end
    end
    ImGui.EndMenu(ctx)
  end
  ImGui.EndPopup(ctx)
end


local function draw_popups(tr)
  fx_menu(tr)
  add_send_menu(tr)
  if state.open_fx_rename then ImGui.OpenPopup(ctx, 'fx_rename'); state.open_fx_rename = false end
  input_popup('fx_rename', 'fxname_buf', 200, function(buf)
    local i = state.fxname_idx
    if i and i < r.TrackFX_GetCount(tr) then
      undo_wrap('Rename FX', function() r.TrackFX_SetNamedConfigParm(tr, i, 'renamed_name', buf) end)
    end
  end)
  if ImGui.BeginPopup(ctx, 'automode_menu') then
    local am = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_AUTOMODE'))
    for i = 0, #AUTO do
      if ImGui.Selectable(ctx, AUTO[i][1], i == am) then r.SetTrackAutomationMode(tr, i) end
    end
    ImGui.EndPopup(ctx)
  end
  if ImGui.BeginPopup(ctx, 'recmode_menu') then
    local rm = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_RECMODE'))
    for i = 0, #RECMODE do
      if ImGui.Selectable(ctx, RECMODE[i][2], i == rm) then
        undo_wrap('Set record mode', function() r.SetMediaTrackInfo_Value(tr, 'I_RECMODE', i) end)
      end
    end
    ImGui.EndPopup(ctx)
  end
  if ImGui.BeginPopup(ctx, 'recin_menu') then
    local cur = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_RECINPUT'))
    local function item(label, v)
      if ImGui.Selectable(ctx, label, cur == v) then
        undo_wrap('Set record input', function() r.SetMediaTrackInfo_Value(tr, 'I_RECINPUT', v) end)
      end
    end
    item('Input: None', -1)
    local n = r.GetNumAudioInputs()
    if ImGui.BeginMenu(ctx, 'Input: Mono') then
      for i = 0, n - 1 do item(r.GetInputChannelName(i) or ('In ' .. (i + 1)), i) end
      ImGui.EndMenu(ctx)
    end
    if ImGui.BeginMenu(ctx, 'Input: Stereo') then
      for i = 0, n - 2 do item((r.GetInputChannelName(i) or '') .. ' / ' .. (r.GetInputChannelName(i + 1) or ''), 1024 + i) end
      ImGui.EndMenu(ctx)
    end
    item('Input: MIDI (all inputs, all channels)', 4096 + (63 << 5))
    ImGui.EndPopup(ctx)
  end
  tracks_menu('bar_menu')
  input_popup('vol_input', 'vol_buf', 90, function(buf)
    local s = buf:lower()
    local d = s:find('inf') and -150 or tonumber((s:gsub('db', '')))
    if d then set_vol(tr, d <= -150 and 0 or db2val(clamp(d, -150, max_db())), true) end
  end)
  input_popup('rename', 'name_buf', 180, function(buf)
    undo_wrap('Rename track', function() r.GetSetMediaTrackInfo_String(tr, 'P_NAME', buf, true) end)
  end)
end

--------------------------------------------------------------------------------
-- Strip layout
--------------------------------------------------------------------------------
local function layout_letter(tr)
  local _, lay = r.GetSetMediaTrackInfo_String(tr, 'P_MCP_LAYOUT', '', false)
  if tr ~= r.GetMasterTrack(0) then lay = '' end   -- tracks always use the theme's default layout (A)
  if lay == '' and r.ThemeLayout_GetLayout then local ok, d = r.ThemeLayout_GetLayout('mcp', -1); lay = ok and d or 'A' end
  return (lay:gsub('^%d+%%_', '')):match('^%a') or 'A'
end

-- width in points, exactly like the theme: armed -> mcpWidthRecarm, selected -> mcpWidthSel, else mcpWidth
local function strip_width(tr)
  if tr == r.GetMasterTrack(0) then return tp('masterMcpWidth', 130) end
  local L = 'Layout' .. layout_letter(tr) .. '-'
  local w
  if r.GetMediaTrackInfo_Value(tr, 'I_RECARM') == 1 then w = tp(L .. 'mcpWidthRecarm', nil)
  elseif r.IsTrackSelected(tr) then w = tp(L .. 'mcpWidthSel', nil) end
  w = w or tp(L .. 'mcpWidth', 88)
  return math.max(40, w)
end


-- Master meter, like REAPER's master VU (Peak / RMS / Peak+RMS per the Master VU settings):
--   outer columns = RMS bars with their own scale (value + RMS display offset/gain),
--   inner columns = peak bars (theme meter image) with the normal scale, one clip light + peak readout per side,
--   "RMS" readout underneath.
local rms_state = {}
local function rms_db(tr, ch)
  local key = r.GetTrackGUID(tr) .. 'rms' .. ch
  local now = r.time_precise()
  local raw = val2db(r.Track_GetPeakInfo(tr, 1024 + ch))     -- master: RMS/loudness values
  local st = rms_state[key]
  if not st then st = { disp = raw, acc = -150, t = now }; rms_state[key] = st end
  if raw > st.acc then st.acc = raw end
  local dt = now - st.t
  if dt >= 1 / METER_HZ then
    st.disp = math.max(st.acc, st.disp - METER_DECAY * dt)
    st.acc, st.t = -150, now
  end
  return st.disp
end

local function draw_master_meter(tr, mx1, my1, mx2, my2)
  local vmax = cfg_num('vumaxvol', 6)
  local vmin = cfg_num('vuminvol', -62)
  if vmax <= vmin then vmax, vmin = 6, -62 end
  local function my(db) return my1 + (vmax - clamp(db, vmin, vmax)) / (vmax - vmin) * (my2 - my1) end

  -- Master VU settings (right-click the master meter in REAPER)
  local mode = math.floor(cfg_num('mvu_rmsmode', 1)) & 3          -- 0 peak, 1 peak+RMS, 2 RMS only
  local offs = cfg_num('mvu_rmsoffs2', 140) / 10                   -- RMS display offset (dB)
  local gain = cfg_num('mvu_rmsgain', 0) / 10                      -- RMS display gain (dB)
  local show_peak, show_rms = mode ~= 2, mode ~= 0
  local c = (mx1 + mx2) / 2
  local RW = 28
  local pa1, pa2, pb1, pb2 = mx1, c - 1, c + 1, mx2          -- 2 px (theme vu.div) between L and R
  if show_rms and show_peak then pa1, pb2 = mx1 + RW + 4, mx2 - RW - 4 end   -- 4 px (theme rmsdiv) to the RMS columns

  local hold0 = r.Track_GetPeakHoldDB(tr, 0, false) * 100
  local hold1 = r.Track_GetPeakHoldDB(tr, 1, false) * 100
  local strip = img('meter_strip_v')
  local peak = {}
  if show_peak then
    for ch = 0, 1 do
      local x1, x2 = (ch == 0) and pa1 or pb1, (ch == 0) and pa2 or pb2
      local db = meter_db(tr, ch); peak[ch] = db
      local pair = ((ch == 0 and hold0 or hold1) > 0) and 1 or 0   -- clipped: orange (the master can't be armed)
      if strip then
        local cw = (strip.x1 - strip.x0) / 8
        local uu, ul = strip.x0 + pair * 2 * cw, strip.x0 + pair * 2 * cw + cw
        ImGui.DrawList_AddImage(G.dl, strip.img, X(x1), Y(my1), X(x2), Y(my2),
          (uu + 0.5) / strip.w, strip.y0 / strip.h, (uu + cw - 0.5) / strip.w, strip.y1 / strip.h)
        local ly = my(db)
        if db > vmin and ly < my2 then
          local f = (ly - my1) / (my2 - my1)
          ImGui.DrawList_AddImage(G.dl, strip.img, X(x1), Y(ly), X(x2), Y(my2),
            (ul + 0.5) / strip.w, (strip.y0 + f * (strip.y1 - strip.y0)) / strip.h, (ul + cw - 0.5) / strip.w, strip.y1 / strip.h)
        end
      end
    end
  end
  local rms = {}
  local rms_col = rgba(clamp(42 * tbm(), 0, 255), clamp(168 * tbm(), 0, 255), clamp(116 * tbm(), 0, 255))
  if show_rms then
    local ra1, ra2, rb1, rb2 = mx1, mx1 + RW, mx2 - RW, mx2
    if not show_peak then ra1, ra2, rb1, rb2 = mx1, c - 1, c + 1, mx2 end
    for ch = 0, 1 do
      local x1, x2 = (ch == 0) and ra1 or rb1, (ch == 0) and ra2 or rb2
      local db = rms_db(tr, ch) + gain; rms[ch] = db
      -- like REAPER: the RMS column runs up to just under the top (8 px lower than the peak clip lights),
      -- colored by zone on the RMS scale: below 0 = green, 0..+4 = bright green, above +4 = red (clip color).
      -- Green / bright green are the lit colors of the theme's meter_strip_v_rms image.
      local rtop = my1 + 8
      local function ry(v) return math.max(rtop, my(v)) end
      local rs = img('meter_strip_v_rms')
      local function lit(ya, yb, pair, fallback)
        if yb <= ya or pair < 0 then return end
        if rs then
          local cw = (rs.x1 - rs.x0) / 8
          local u = rs.x0 + (pair * 2 + 1) * cw
          ImGui.DrawList_AddImage(G.dl, rs.img, X(x1), Y(ya), X(x2), Y(yb),
            (u + 0.5) / rs.w, (rs.y0 + 0.5) / rs.h, (u + cw - 0.5) / rs.w, (rs.y1 - 0.5) / rs.h)
        else rect(X(x1), Y(ya), X(x2), Y(yb), fallback) end
      end
      if rs then                                   -- unlit background (pair 0, unlit)
        local cw = (rs.x1 - rs.x0) / 8
        ImGui.DrawList_AddImage(G.dl, rs.img, X(x1), Y(rtop), X(x2), Y(my2),
          (rs.x0 + 0.5) / rs.w, (rs.y0 + 0.5) / rs.h, (rs.x0 + cw - 0.5) / rs.w, (rs.y1 - 0.5) / rs.h)
      end
      if db > vmin then
        local ytop = ry(db)
        local y0z, y4z = ry(0 - offs), ry(4 - offs)          -- RMS-scale 0 and +4 (scale shows level + offset)
        lit(math.max(ytop, y0z), my2, 0, rms_col)              -- green
        lit(math.max(ytop, y4z), y0z, 1, rgba(0, 255, 148))     -- bright green
        if ytop < y4z then rect(X(x1), Y(ytop), X(x2), Y(y4z), theme_col('col_vuclip', 0xFF0100FF)) end
      end
    end
  end

  -- clip lights + peak readouts (one per side), top section above 0 dB
  local cy2 = math.max(my(0), my1 + 22)
  local clip = img('meter_clip_v')
  -- x1, x2: the clip light; t1, t2: where the readout is centered (each half of the meter, like REAPER)
  local function clip_box(x1, x2, h, t1, t2)
    if clip then
      local fh = (clip.y1 - clip.y0) / 2
      local v0 = clip.y0 + ((h > 0) and fh or 0)
      ImGui.DrawList_AddImage(G.dl, clip.img, X(x1), Y(my1), X(x2), Y(cy2),
        (clip.x0 + 0.5) / clip.w, (v0 + 0.5) / clip.h, (clip.x1 - 0.5) / clip.w, (v0 + fh - 0.5) / clip.h)
    else
      rect(X(x1), Y(my1), X(x2), Y(cy2), (h > 0) and theme_col('col_vuclip', 0xFF0000FF) or COL.bg)
    end
    if tp('masterMcpMeterVals', 1) == 1 then
      -- measured on the real master: the readout stays gray (150) even when clipped
      text(font_bold, 18, X(((t1 or x1) + (t2 or x2)) / 2), Y((my1 + cy2) / 2), gray(150), (h > 0 and '+' or '') .. fmt_peak(h), 'c')
    end
  end
  if show_peak and show_rms then
    -- clip lights only over the peak (middle) meters; the RMS meters run up to the top on their own
    clip_box(pa1, pa2, hold0, mx1, c - 1)
    clip_box(pb1, pb2, hold1, c + 1, mx2)
  else
    clip_box(mx1, c - 1, hold0)
    clip_box(c + 1, mx2, hold1)
  end
  local hc = hit('##clip', X(mx1), Y(my1), X(mx2), Y(cy2), 'Peak hold / clip indicators (click to reset)')
  if hc.click then r.Track_GetPeakHoldDB(tr, 0, true); r.Track_GetPeakHoldDB(tr, 1, true) end

  -- scales
  if tp('masterMcpMeterVals', 1) == 1 then
    local unlit = rgba(255, 255, 255, clamp(60 + (tbm() - 1) * 100, 0, 255))   -- measured on the real master
    local litc = rgba(0, 0, 0, 170)
    local px = 6 / (vmax - vmin) * (my2 - my1)
    local step = 6
    while px * (step / 6) < 35.5 and step < 48 do step = step * 2 end
    if show_peak then                                   -- inner: peak scale
      local top = math.max(peak[0] or -150, peak[1] or -150)
      local m = (step == 6) and ((px >= 42) and 0 or -6) or -6
      while m > vmin + 1 do
        text(font_bold, 17, X(c), Y(my(m)), (top >= m) and litc or unlit, '-' .. math.abs(m) .. '-', 'c')
        m = m - step
      end
    end
    if show_rms then                                    -- outer: RMS scale (shown value = level + offset)
      local v = math.floor((vmax + offs) / 6) * 6
      while v - offs > vmin + 1 do
        local y = my(v - offs)
        if y > cy2 + 8 then
          local lit_l = (rms[0] or -150) >= v - offs
          local lit_r = (rms[1] or -150) >= v - offs
          local lt = (v > 0) and tostring(v) or (math.abs(v) .. '-')
          local rt = (v > 0) and tostring(v) or ('-' .. math.abs(v))
          text(font_bold, 17, X(mx1 + 2), Y(y), lit_l and litc or unlit, lt)
          text(font_bold, 17, X(mx2 - 2), Y(y), lit_r and litc or unlit, rt, 'r')
        end
        v = v - step
      end
    end
  end

  -- RMS readout underneath
  if show_rms and tp('masterMcpMeterVals', 1) == 1 then
    local rv = math.max(rms[0] or -150, rms[1] or -150)
    text(font_bold, 21, X(mx1 + 12), Y(my2 + 14), rms_col, 'RMS')
    text(font_bold, 21, X(mx2 - 12), Y(my2 + 14), rms_col, fmt_peak(rv), 'r')
  end
end

-- Master strip, laid out like the theme's master mixer panel (rtconfig drawMasterMcp, x2 at 200%):
-- pan section on top, a dark box with volume readout / wide stereo meter + fader / MASTER label,
-- and a button column: MONO, M, S, ROUTE, FX + bypass, TRIM.
local function draw_master(tr, P, D)
  local W = DESIGN_W
  local sel = r.IsTrackSelected(tr) and tp('selectStrength', 25) / 100 or 0
  local function mc(v) return (1 - sel) * v + sel * 255 end
  local bR, bG, bB = mc(tp('masterMcpBgColR', 51)), mc(tp('masterMcpBgColG', 51)), mc(tp('masterMcpBgColB', 51))
  rect(X(0), Y(P), X(W), Y(D), rgba(bR, bG, bB))
  G.pan_label = (brightness(bR, bG, bB) < 150) and gray(220) or gray(38)

  -- pan section: x 0..W-64, 92 tall (value label + knob)
  local panW = W - 64
  local _, p1, p2, pmode = r.GetTrackUIPan(tr)
  local PAN = { 'mcp_pan_knob_stack', 'tcp_pan_knob_stack' }
  if pmode == 5 or pmode == 6 then
    knob(tr, '##pan', panW / 2 - 22, P + 53, p1, (pmode == 6) and -1 or 0, fmt_pan(p1), set_pan, PAN)
    knob(tr, '##width', panW / 2 + 22, P + 53, p2, 1,
      (pmode == 6) and fmt_pan(p2) or (math.floor(p2 * 100 + 0.5) .. '%W'), set_width,
      { 'mcp_wid_knob_stack', 'tcp_wid_knob_stack', 'tcp_pan_knob_stack' })
  else
    knob(tr, '##pan', panW / 2, P + 53, p1, 0, fmt_pan(p1), set_pan, PAN)
  end

  -- dark box: x 12..W-64, from the pan section to the bottom
  local dx1, dx2, dy1, dy2 = 12, W - 64, P + 92, D
  rect(X(dx1), Y(dy1), X(dx2), Y(dy2), rgba(38, 38, 38))

  -- volume readout (top 40 of the dark box)
  local _, vol = r.GetTrackUIVolPan(tr)
  local h = hit('##volread', X(dx1), Y(dy1), X(dx2), Y(dy1 + 40), 'Click to type a value')
  if tp('masterMcpVals', 1) == 1 then
    text(font_list, fpx(1, 23) * 0.95, X((dx1 + dx2) / 2), Y(dy1 + 20), gray(h.hov and 190 or 150), fmt_vol(val2db(vol)), 'c')
  end
  if h.click then state.vol_buf = fmt_peak(val2db(vol)); state.focus = true; ImGui.OpenPopup(ctx, 'vol_input') end

  -- meter: dark box + [0 6 -24 -26] + [0 14 0 -14] (x2); fader 48 wide right of it
  local mx1, my1 = dx1, dy1 + 12 + 28
  local mx2, my2 = dx2 - 48, dy2 - 64          -- measured: meter ends 64 above the dark box bottom
  draw_master_meter(tr, mx1, my1, mx2, my2)
  G.fader_x = mx2 + 24
  draw_fader(tr, my1 + 10, my2 - 17)
  G.fader_x = nil

  -- MASTER label (bottom 40 of the dark box)
  if tp('masterMcpLabels', 1) == 1 then
    local lc = gray(220)
    if tp('selInvertLabels', 0) == 1 and r.IsTrackSelected(tr) then
      rect(X(dx1), Y(dy2 - 40), X(dx2), Y(dy2), rgba(255, 255, 255, 200)); lc = rgba(38, 38, 38)
    end
    text(font_list, fpx(3, 28), X((dx1 + dx2) / 2), Y(dy2 - 20), lc, 'MASTER', 'c')
  end
  if r.IsTrackSelected(tr) and tp('selDot', 1) == 1 then
    local dot = img('mcp_selectionDot_sel', 'tcp_selectionDot_sel')
    if dot then local d = (dot.x1 - dot.x0) * dot.k; draw_img(dot, dx2 - 8 - d / 2, dy2 - 28 - d / 2, 0, 1, false, nil, true) end
  end
  local hb = hit('##masterbg', X(dx1), Y(dy2 - 40), X(dx2), Y(dy2), 'Right-click: choose tracks')
  if hb.click then select_click(tr) end
  if hb.rclick then ImGui.OpenPopup(ctx, 'bar_menu') end

  -- button column: x W-52, stacked like the theme (masterMcpFollow)
  local BX = W - 52
  local mono = r.GetToggleCommandState(40917) == 1        -- Master track: Toggle stereo/mono (L+R)
  -- theme images: mcp_stereo = normal (stereo), mcp_mono = mono active
  local hm = theme_button('##mono', bimg(mono and 'mcp_mono' or 'mcp_stereo', 'mcp_stereo'), BX, P + 12,
    mono and 'Master is mono (click for stereo)' or 'Master is stereo (click for mono)', 'MONO', 40, 64, mono and COL.solo_on)
  if hm.click then r.Main_OnCommand(40917, 0) end

  local _, muted = r.GetTrackUIMute(tr)
  local h2 = theme_button('##mute', bimg(muted and 'mcp_mute_on' or 'mcp_mute_off', muted and 'track_mute_on' or 'track_mute_off'),
    BX, P + 84, 'Mute', 'M', 40, 40, muted and COL.mute_on)
  if h2.click then r.SetTrackUIMute(tr, -1, IGN) end
  local soloed = r.GetMediaTrackInfo_Value(tr, 'I_SOLO') > 0
  h2 = theme_button('##solo', bimg(soloed and 'mcp_solo_on' or 'mcp_solo_off', soloed and 'track_solo_on' or 'track_solo_off'),
    BX, P + 124, 'Solo', 'S', 40, 40, soloed and COL.solo_on)
  if h2.click then r.SetTrackUISolo(tr, -1, IGN) end

  local sends = r.GetTrackNumSends(tr, 0) + r.GetTrackNumSends(tr, 1) > 0
  local recvs = r.GetTrackNumSends(tr, -1) > 0
  local io = 'mcp_io' .. (sends and '_s' or '') .. (recvs and '_r' or '')
  h2 = theme_button('##route', bimg(io, 'mcp_io'), BX, P + 176, 'Routing', 'ROUTE', 40, 64)
  if h2.rclick then show_track_menu(tr, 'track_routing') end
  if h2.click then
    if not r.IsTrackSelected(tr) then r.SetOnlyTrackSelected(tr) end
    r.Main_OnCommand(40914, 0); r.Main_OnCommand(40293, 0); state.no_refocus = true
  end

  local nfx = r.TrackFX_GetCount(tr)
  local fx_en = r.GetMediaTrackInfo_Value(tr, 'I_FXEN') == 1
  local fxn = nfx == 0 and 'empty' or (fx_en and 'norm' or 'dis')
  h2 = theme_button('##fx', bimg('mcp_fx_' .. fxn, 'track_fx_' .. fxn), BX, P + 252, 'FX chain', 'FX', 40, 40, COL.btn_dark)
  if h2.click then
    if r.TrackFX_GetChainVisible(tr) ~= -1 then r.TrackFX_Show(tr, 0, 0) else r.TrackFX_Show(tr, 0, 1) end
  end
  local byn = nfx == 0 and 'track_fxempty_v' or (fx_en and 'track_fxon_v' or 'track_fxoff_v')
  h2 = theme_button('##fxbyp', bimg(byn), BX, P + 292, fx_en and 'Bypass all FX' or 'FX bypassed', 'on', 40, 32,
    fx_en and COL.btn_light or COL.fxbyp_on)
  if h2.click then
    undo_wrap('Toggle master FX bypass', function() r.SetMediaTrackInfo_Value(tr, 'I_FXEN', fx_en and 0 or 1) end)
  end

  local am = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_AUTOMODE'))
  h2 = theme_button('##env', bimg('mcp_env' .. (ENV_SUFFIX[am] or ''), 'mcp_env'), BX, P + 336, 'Automation mode',
    (AUTO[am] or AUTO[0])[2], 40, 64)
  if h2.click then ImGui.OpenPopup(ctx, 'automode_menu') end


  -- empty background (dark box and button column, not the pan section or MASTER label): drag to move the window
  window_drag_area('##masterbgdrag', 0, dy1, W, dy2 - 40)
  -- divider on the left edge, like the other strips
  local div_a = clamp(tp('mcpDivOpacity', 80), 0, 255)
  if div_a > 0 then rect(X(0), Y(P), X(2), Y(D), rgba(0, 0, 0, div_a)) end
end

local function draw_strip(tr, wx, wy, W, H)
  local is_master = (tr == r.GetMasterTrack(0))
  set_tint(tr)
  set_track_layout(tr)
  -- fixed scale: 1 design unit = one pixel of the theme's 200% images = half a point (same size as the mixer)
  G.ox, G.oy, G.s, G.dl = wx, wy, 0.5 * (state.draw_k or 1), ImGui.GetWindowDrawList(ctx)   -- see draw_k (Windows display scaling)
  G.h = H
  DESIGN_W = W / G.s
  G.sid = r.GetTrackGUID(tr)
  G.layout = layout_letter(tr)
  state.scroll = state.scroll or {}
  local sc = state.scroll[G.sid] or { 0, 0 }
  state.fx_scroll, state.send_scroll = sc[1], sc[2]

  -- vertical layout (design units). The FX/send area height is set by dragging the top of the
  -- input section, like the real mixer; the fader takes the rest.
  local D = H / G.s
  local PANEL, HEAD, BOTROW, GAP, BAR = 193, 54, 60, 48, 40   -- GAP = mcpNameBg (24), BAR = mcpIdxBg (20), x2 at 200%
  local MH_MIN = 310                                   -- keeps TRIM / polarity clear of the bottom row
  local fixed = PANEL + HEAD + BOTROW + GAP + BAR
  state.fx_h = state.fx_h or tonumber(r.GetExtState(EXT, 'fx_h')) or 412     -- default for new strips
  state.fxh = state.fxh or {}
  if not state.fxh[G.sid] then
    local ok, v = r.GetSetMediaTrackInfo_String(tr, 'P_EXT:Daniel_FloatingMixer_fxh', '', false)
    state.fxh[G.sid] = (ok and tonumber(v)) or state.fx_h
  end
  -- folder indent, like the theme: each folder level makes the fader section shorter by "MCP Folder Indent"
  -- and lifts the name + number bar, with the theme's gray infill (51,51,51) under the bar.
  -- "MCP Folder Balance Type" 1: the name area of shallower tracks grows instead, so the bars line up.
  local isz = tp('mcpfolderIndentSize', 10) * 2         -- theme points -> design units (200%)
  local depth = is_master and 0 or math.max(0, r.GetTrackDepth(tr))
  local IND = depth * isz
  local BAL = (not is_master and tp('mcpfolderBalanceType', 0) == 1) and math.max(0, (state.max_depth or 0) - depth) * isz or 0
  G.indent = IND
  -- the FX/sends area is sized as for a top-level track, so it lines up across strips; the fader gives way
  local maxfx = math.max(0, D - fixed - MH_MIN)
  local fxh = clamp(state.fxh[G.sid], 0, maxfx)
  if fxh < 24 then fxh = 0 end            -- snaps shut: FX and sends are hidden, like the real mixer
  local mh = math.max(120, D - fixed - IND - BAL - fxh)
  local LT = fxh + PANEL
  local MT, MB = LT + HEAD, LT + HEAD + mh
  local BT = MB + BOTROW + GAP + BAL
  G.btn_limit = MB + BOTROW              -- buttons that would reach into the name area are hidden (theme rule)

  if is_master then
    -- master: FX/sends area on top (resizable), then the master panel
    local mfix = 92 + 40 + 80 + 260            -- pan + readout + label/margins + minimum meter
    local mmax = math.max(0, D - mfix)
    local mfx = clamp(state.fxh[G.sid], 0, mmax)
    if mfx < 24 then mfx = 0 end
    if mfx > 0 then draw_fx_area(tr, 0, mfx) end
    draw_master(tr, mfx, D)
    local hr = hit('##resize', X(0), Y(math.max(0, mfx - 3)), X(DESIGN_W), Y(math.max(0, mfx - 3) + 8), 'Drag to resize')
    if hr.hov or hr.act then ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS) end
    if hr.act then
      local _, dy = ImGui.GetMouseDelta(ctx)
      state.fxh[G.sid] = clamp(state.fxh[G.sid] + dy / G.s, 0, mmax)
    end
    if hr.deactivated then
      r.GetSetMediaTrackInfo_String(tr, 'P_EXT:Daniel_FloatingMixer_fxh', tostring(math.floor(state.fxh[G.sid])), true)
    end
    draw_popups(tr)
    state.scroll[G.sid] = { state.fx_scroll, state.send_scroll }
    return
  end
  if fxh > 0 then draw_fx_area(tr, 0, fxh) end
  draw_panel(tr, is_master, fxh)
  -- resize handle: top edge of the input section
  local hr = hit('##resize', X(0), Y(math.max(0, fxh - 3)), X(DESIGN_W), Y(math.max(0, fxh - 3) + 8), 'Drag to resize  |  Cmd/Ctrl-drag: resize all strips')
  if hr.hov or hr.act then ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS) end
  if hr.act then
    local _, dy = ImGui.GetMouseDelta(ctx)
    local nv = clamp(state.fxh[G.sid] + dy / G.s, 0, maxfx)
    if is_ctrl() then            -- Cmd/Ctrl: resize every strip in the window together
      for _, t in ipairs(state.cur_tracks or {}) do state.fxh[r.GetTrackGUID(t)] = nv end
      state.fx_h = nv
    else
      state.fxh[G.sid] = nv
    end
  end
  if hr.deactivated then
    local function save(t) r.GetSetMediaTrackInfo_String(t, 'P_EXT:Daniel_FloatingMixer_fxh', tostring(math.floor(state.fxh[r.GetTrackGUID(t)] or 0)), true) end
    if is_ctrl() then
      for _, t in ipairs(state.cur_tracks or {}) do save(t) end
      r.SetExtState(EXT, 'fx_h', tostring(math.floor(state.fx_h)), true)
    else save(tr) end
  end
  draw_lower(tr, is_master, LT, MT, MB)
  local hlb = window_drag_area('##lowerbg', 0, LT, DESIGN_W, MB + BOTROW)
  if hlb.rclick then
    local mx, my = ImGui.GetMousePos(ctx)
    local m = G.meter_rect
    local on_meter = m and mx >= m[1] and mx <= m[3] and my >= m[2] and my <= m[4]
    show_track_menu(tr, on_meter and 'track_input' or nil)
  end
  draw_name(tr, MB + BOTROW, BT)
  draw_bar(tr, BT, BT + BAR)
  if IND > 0 then rect(X(0), Y(BT + BAR), X(DESIGN_W), Y(BT + BAR + IND), rgba(51, 51, 51)) end   -- mcp.custom.indentInfill
  -- strip divider (theme: mcp.custom.mcpDiv = 1 px @100% on the strip's left edge, black at "MCP Div Opacity");
  -- in the FX/sends area the lists cover it, so it starts at the input section
  local div_a = clamp(tp('mcpDivOpacity', 80), 0, 255)
  if div_a > 0 then rect(X(0), Y(fxh), X(2), Y(BT + BAR), rgba(0, 0, 0, div_a)) end
  draw_popups(tr)
  -- whole-strip drop zone for moving tracks
  ImGui.SetCursorScreenPos(ctx, X(0), Y(0))
  ImGui.Dummy(ctx, math.max(1, X(DESIGN_W) - X(0)), math.max(1, G.h))
  track_drop_target(tr)
  state.scroll[G.sid] = { state.fx_scroll, state.send_scroll }
end

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------
local WFLAGS = ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse | ImGui.WindowFlags_NoCollapse

local TOOLBAR_H = 22

-- Keyboard stays with REAPER: after a click in the strip, focus goes back to the REAPER window that had it
-- (needs SWS or js_ReaScriptAPI). Not while typing (rename / value entry) or while a menu is open.
local function set_focus(hwnd)
  if r.JS_Window_SetFocus then r.JS_Window_SetFocus(hwnd); return true end
  if r.BR_Win32_SetFocus then r.BR_Win32_SetFocus(hwnd); return true end
end

-- called after all windows are drawn (so clicks in the Snapshots window are known); state.kf_ours is set
-- inside the mixer window: one of this script's windows has focus
keep_reaper_focus = function()
  if not state.kf_ours then return end
  if ImGui.IsMouseReleased(ctx, ImGui.MouseButton_Left) or ImGui.IsMouseReleased(ctx, ImGui.MouseButton_Right) then
    state.refocus = true
  end
  if state.no_refocus then          -- the routing window just opened: it closes if REAPER's main window takes focus
    state.no_refocus, state.refocus = false, false
    return
  end
  if not state.refocus then return end
  -- wait only while typing (rename / value entry) or while a menu is open; nothing else holds the keyboard
  local menu = ImGui.IsPopupOpen(ctx, '', ImGui.PopupFlags_AnyPopupId)
  if state.renaming or menu or state.snap_typing or state.snap_edit then return end   -- typing a snapshot name keeps the keyboard
  state.refocus = false
  set_focus(r.GetMainHwnd())       -- always REAPER's main window (not whatever script/window had focus before)
end

-- per-window state: swapped into `state` while that window is drawn
-- (kept in a do-block on `state`: the main chunk is close to Lua's 200-local limit)
do
  local WIN_FIELDS = { 'mode', 'list', 'proj', 'docked', 'dock_req', 'cur_tracks', 'strip_rects' }
  state.win_in = function(W)
    CUR_WIN = W.n
    for _, f in ipairs(WIN_FIELDS) do state[f] = W[f] end
  end
  state.win_out = function(W)
    for _, f in ipairs(WIN_FIELDS) do W[f] = state[f] end
  end
  state.save_win_list = function()
    local t = {}
    for _, W in ipairs(state.wins) do t[#t + 1] = tostring(W.n) end
    r.SetProjExtState(0, 'Daniel_FloatingMixer', 'windows', table.concat(t, ','))   -- per project
  end

  -- Window colors: window 1 is the mixer's background gray (the theme's col_mixerbg); the others get a color
  -- from this palette by their number (2 = Blue, 3 = Teal...).
  -- Right-click the top row > Window color to pick one; a picked color is saved per window in the project.
  -- "Automatic" goes back to the palette color.
  state.PALETTE = {
    { 'Blue',   0x3F6FB5FF }, { 'Teal',   0x2E9A8EFF }, { 'Green',  0x4F9A45FF }, { 'Amber',  0xC08A2EFF },
    { 'Orange', 0xC0612EFF }, { 'Red',    0xB5443FFF }, { 'Purple', 0x7E5BB5FF }, { 'Pink',   0xB0508AFF },
  }
  state.mixer_gray = function() return theme_col('col_mixerbg', 0x333333FF) end
  local function color_key(n) return n == 1 and 'color' or ('color_' .. n) end
  -- returns the window's color (0xRRGGBBAA) and whether it was picked by hand
  state.win_color = function(n)
    local _, v = r.GetProjExtState(0, 'Daniel_FloatingMixer', color_key(n))
    local c = tonumber(v or '', 16)
    if c then return (c << 8) | 0xFF, true end
    if n == 1 then return state.mixer_gray(), false end
    return state.PALETTE[(n - 2) % #state.PALETTE + 1][2], false
  end
  -- col = 0xRRGGBBAA, or nil for automatic
  state.set_win_color = function(n, col)
    r.SetProjExtState(0, 'Daniel_FloatingMixer', color_key(n), col and string.format('%06X', col >> 8) or '')
    r.MarkProjectDirty(0)
  end
  state.forget_win_color = function(n) r.SetProjExtState(0, 'Daniel_FloatingMixer', color_key(n), '') end
  -- a darker / dimmer version of a color (for inactive title bars)
  state.dim_color = function(c, k)
    return rgba(((c >> 24) & 255) * k, ((c >> 16) & 255) * k, ((c >> 8) & 255) * k, c & 255)
  end
  -- black or white text, whichever reads better on the color
  state.text_on = function(c)
    return brightness((c >> 24) & 255, (c >> 16) & 255, (c >> 8) & 255) > 150 and 0x1A1A1AFF or 0xFFFFFFFF
  end

  -- the color submenu (used in the top row's right-click menu)
  state.color_menu = function(n)
    if not ImGui.BeginMenu(ctx, 'Window color') then return end
    local cur, picked = state.win_color(n)
    if ImGui.MenuItem(ctx, 'Automatic', nil, not picked) then state.set_win_color(n, nil) end
    ImGui.Separator(ctx)
    local gray = state.mixer_gray()
    ImGui.ColorButton(ctx, '##swGray', gray, ImGui.ColorEditFlags_NoTooltip | ImGui.ColorEditFlags_NoBorder, 12, 12)
    ImGui.SameLine(ctx)
    if ImGui.MenuItem(ctx, 'Default', nil, picked and cur == gray) then state.set_win_color(n, gray) end
    for _, p in ipairs(state.PALETTE) do
      ImGui.ColorButton(ctx, '##sw' .. p[1], p[2], ImGui.ColorEditFlags_NoTooltip | ImGui.ColorEditFlags_NoBorder, 12, 12)
      ImGui.SameLine(ctx)
      if ImGui.MenuItem(ctx, p[1], nil, picked and cur == p[2]) then state.set_win_color(n, p[2]) end
    end
    ImGui.Separator(ctx)
    if ImGui.BeginMenu(ctx, 'Custom') then
      local rv, rgb = ImGui.ColorPicker3(ctx, '##custom_color', cur >> 8,
        ImGui.ColorEditFlags_NoSidePreview | ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoAlpha)
      if rv then state.set_win_color(n, (rgb << 8) | 0xFF) end
      ImGui.EndMenu(ctx)
    end
    ImGui.EndMenu(ctx)
  end
end

state.draw_mixer_window = function(W)
  if W.close_req then W.close_req = nil; return false end      -- "Close window" from the title-bar menu
  local tracks = strip_tracks()
  state.max_depth = 0                              -- deepest folder level shown (for "MCP Folder Balance Type")
  for _, t in ipairs(tracks) do
    if t ~= r.GetMasterTrack(0) then state.max_depth = math.max(state.max_depth, r.GetTrackDepth(t)) end
  end
  -- Windows display scaling (e.g. 125%): ReaImGui enlarges everything by it, REAPER's mixer doesn't,
  -- so the strips are drawn smaller by the same factor to stay the mixer's size. K is measured after
  -- Begin (the window's display scale) and used from the next frame on; 1 on macOS / Linux.
  local K = state.ui_k or 1
  state.draw_k = K
  local widths, total = {}, 0
  -- track spacers (right-click a track > "Add spacer before/after track"): REAPER marks the track that
  -- has a spacer before it (I_SPACER); shown as a gap between strips, like the mixer
  local gaps, SPACER_W = {}, 16   -- measured on the real mixer: 32 px on Retina = 16 pt
  for k, tr in ipairs(tracks) do
    widths[k] = strip_width(tr) * K
    local prev = tracks[k - 1]
    gaps[k] = (prev and prev ~= r.GetMasterTrack(0) and tr ~= r.GetMasterTrack(0)
               and r.GetMediaTrackInfo_Value(tr, 'I_SPACER') == 1) and SPACER_W * K or 0
    total = total + widths[k] + gaps[k]
  end
  local winw = total                               -- exactly the strips' width
  if #tracks == 0 then                             -- empty: one normal strip wide, so selecting a track doesn't resize it
    local lay = 'A'
    if r.ThemeLayout_GetLayout then
      local ok, d = r.ThemeLayout_GetLayout('mcp', -1)
      if ok and d then lay = (d:gsub('^%d+%%_', '')):match('^%a') or 'A' end
    end
    winw = math.max(40, tp('Layout' .. lay .. '-mcpWidth', 88)) * K
  end
  ImGui.SetNextWindowSize(ctx, winw, 560, ImGui.Cond_FirstUseEver)
  do -- first launch ever: centered on screen; after that ReaImGui remembers where it was left
    local cx, cy = ImGui.Viewport_GetCenter(ImGui.GetMainViewport(ctx))
    local off = (W.n - 1) * 30                        -- later windows open a little offset
    ImGui.SetNextWindowPos(ctx, cx + off, cy + off, ImGui.Cond_FirstUseEver, 0.5, 0.5)
  end
  ImGui.SetNextWindowSizeConstraints(ctx, winw, 380, winw, 5000)   -- width is fixed by the strips
  local wcol = state.win_color(W.n)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 0, 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, COL.bg)
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive, wcol)                     -- title bar: the window's color
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBg, state.dim_color(wcol, 0.55))    -- (dimmer when not focused)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, state.text_on(wcol))

  local title = 'Mixer ' .. W.n                  -- short, so it fits a one-strip window
  if state.dock_req then ImGui.SetNextWindowDockID(ctx, state.dock_req); state.dock_req = nil end
  local visible, open = ImGui.Begin(ctx, title .. '###DanielFloatingMixer' .. (W.n > 1 and W.n or ''), true, WFLAGS)
  ImGui.PopStyleColor(ctx, 4); ImGui.PopStyleVar(ctx)
  if visible then ImGui.PushStyleColor(ctx, ImGui.Col_DragDropTarget, 0x00000000) end
  state.docked = visible and ImGui.IsWindowDocked(ctx) or false
  if visible then
    local d = 1
    if ImGui.GetWindowDpiScale and (r.GetOS() or ''):find('Win') then d = ImGui.GetWindowDpiScale(ctx) or 1 end
    state.ui_k = (d > 0) and 1 / d or 1
  end
  if state.docked then
    local id = ImGui.GetWindowDockID(ctx)
    if id < 0 and tostring(id) ~= r.GetExtState('Daniel_FloatingMixer', inst_key('dock')) then
      r.SetExtState('Daniel_FloatingMixer', inst_key('dock'), tostring(id), true)
    end
  end
  -- right-click the title bar or the colored top row (not on a button): dock / undock, window color
  if visible and ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows)
     and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) then
    local _, wy = ImGui.GetWindowPos(ctx)
    local _, my = ImGui.GetMousePos(ctx)
    local top = (state.docked and 0 or ImGui.GetFrameHeight(ctx)) + TOOLBAR_H
    if my < wy + top and not ImGui.IsAnyItemHovered(ctx) then ImGui.OpenPopup(ctx, 'title_menu') end
  end
  -- same as the Meter Bridge's: New window, Window color | Dock / Undock, Close window
  if visible and ImGui.BeginPopup(ctx, 'title_menu') then
    if ImGui.MenuItem(ctx, 'New window') then state.new_win_req = true end
    state.color_menu(W.n)
    ImGui.Separator(ctx)
    if state.docked then
      if ImGui.MenuItem(ctx, 'Undock window') then state.dock_req = 0 end
    elseif ImGui.MenuItem(ctx, 'Dock window') then
      state.dock_req = tonumber(r.GetExtState('Daniel_FloatingMixer', inst_key('dock'))) or -1   -- last-used docker
    end
    if ImGui.MenuItem(ctx, 'Close window') then W.close_req = true end   -- same as its X
    ImGui.EndPopup(ctx)
  end
  if visible then
    -- always-visible track chooser
    local tx, ty = ImGui.GetCursorScreenPos(ctx)
    -- the top row in the window's color, with the window's number on the left
    local wpx = ImGui.GetWindowPos(ctx)
    local tcol = state.text_on(wcol)
    ImGui.DrawList_AddRectFilled(ImGui.GetWindowDrawList(ctx), wpx, ty, wpx + ImGui.GetWindowWidth(ctx), ty + TOOLBAR_H, wcol)
    local num = tostring(W.n)
    local num_w, num_h = ImGui.CalcTextSize(ctx, num)
    ImGui.DrawList_AddText(ImGui.GetWindowDrawList(ctx), tx + 7, ty + (TOOLBAR_H - num_h) / 2, tcol, num)
    local badge_w = num_w + 14
    ImGui.SetCursorScreenPos(ctx, tx + badge_w, ty + 2)
    local label = (state.mode == 'list') and 'Tracks' or 'Follow selection'
    -- three menus on top: tracks to show | snapshots | window (dock, new / close window).
    -- Labels get shorter when the window is narrow (e.g. a single strip); full names in the tooltips.
    local avail = ImGui.GetWindowWidth(ctx) - 8 - badge_w
    local sets = {
      { label, 'Snapshots', '+' },
      { 'Tracks', 'Snapshots', '+' },
      { 'Tracks', 'Snap', '+' },
      { 'Trk', 'Snap', '+' },
      { 'Trk', 'Sn', '+' },
      { 'Tr', 'Sn', '+' },
      { 'T', 'S', '+' },          -- last resort, so the + button is never cut off
    }
    local lab = sets[#sets]
    for _, set in ipairs(sets) do
      local w = 0
      for _, t in ipairs(set) do w = w + ImGui.CalcTextSize(ctx, t) + 8 + 4 end
      if w <= avail then lab = set; break end
    end
    -- the buttons stay neutral (translucent dark) on the colored row
    local function small_btn(text)
      ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x00000055)
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x00000080)
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x000000B0)
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFFFFFFF)
      local clicked = ImGui.SmallButton(ctx, text)
      ImGui.PopStyleColor(ctx, 4)
      return clicked
    end
    local function topbtn(text, id, popup, tip)
      if small_btn(text .. '###' .. id) then ImGui.OpenPopup(ctx, popup) end
      if tip and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayNormal) then ImGui.SetTooltip(ctx, tip) end
    end
    topbtn(lab[1], 'tracksbtn', 'tracks_top', 'Tracks to show')
    tracks_menu('tracks_top')
    ImGui.SameLine(ctx, 0, 4)
    if small_btn(lab[2] .. '###snapsbtn') then             -- opens / closes the Snapshots window (for this mixer window)
      state.snap_for = (state.snap_for == W.n) and nil or W.n
    end
    if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayNormal) then ImGui.SetTooltip(ctx, 'Snapshots') end
    ImGui.SameLine(ctx, 0, 4)
    if small_btn(lab[3] .. '###newwin') then state.new_win_req = true end   -- opens another mixer window
    if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayNormal) then ImGui.SetTooltip(ctx, 'Open a new mixer window') end

    local wx, wy = tx, ty + TOOLBAR_H
    local H = select(2, ImGui.GetWindowSize(ctx)) - (wy - select(2, ImGui.GetWindowPos(ctx)))
    state.cur_tracks = tracks
    state.strip_rects = {}
    do
      local x = wx
      for k, tr in ipairs(tracks) do
        x = x + gaps[k]
        state.strip_rects[k] = { x, x + widths[k], wy, wy + H, tr }; x = x + widths[k]
      end
    end
    if #tracks > 0 then
      local x = wx
      for k, tr in ipairs(tracks) do
        if gaps[k] > 0 then        -- the spacer: empty mixer background; drag it to move it
          ImGui.SetCursorScreenPos(ctx, x, wy)
          ImGui.InvisibleButton(ctx, '##spacer' .. r.GetTrackGUID(tr), gaps[k], math.max(1, H))
          -- grabbed: lighter gray, like REAPER's spacer while held (measured: 82,82,82)
          local lit = ImGui.IsItemActive(ctx)
          ImGui.DrawList_AddRectFilled(ImGui.GetWindowDrawList(ctx), x, wy, x + gaps[k], wy + H,
            lit and 0x525252FF or theme_col('col_mixerbg', 0x333333FF))
          if ImGui.BeginDragDropSource(ctx) then
            ImGui.SetDragDropPayload(ctx, 'DTS_SPACER', r.GetTrackGUID(tr))
            ImGui.Text(ctx, 'Move spacer')
            ImGui.EndDragDropSource(ctx)
          end
          x = x + gaps[k]
        end
        ImGui.PushID(ctx, r.GetTrackGUID(tr))
        draw_strip(tr, x, wy, widths[k], H)
        ImGui.PopID(ctx)
        x = x + widths[k]
      end
    else
      -- wrapped to the window, so nothing is cut off in a one-strip window
      local msg = state.mode == 'list'
        and 'No tracks chosen.\n\nClick the first button on the top row to choose tracks.'
        or 'No track selected.\n\nSelect a track, or click the first button on the top row to choose tracks.'
      ImGui.SetCursorScreenPos(ctx, wx + 8, wy + 10)
      ImGui.PushTextWrapPos(ctx, ImGui.GetWindowWidth(ctx) - 8)
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, ImGui.GetStyleColor(ctx, ImGui.Col_TextDisabled))
      ImGui.TextWrapped(ctx, msg)
      ImGui.PopStyleColor(ctx)
      ImGui.PopTextWrapPos(ctx)
    end
    if ImGui.IsWindowFocused(ctx) and not ImGui.IsAnyItemActive(ctx)
       and ImGui.IsKeyPressed(ctx, ImGui.Key_Space, false) then
      r.Main_OnCommand(40044, 0)
    end
    state.kf_ours = state.kf_ours or ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_AnyWindow)
    ImGui.PopStyleColor(ctx)
    ImGui.End(ctx)
  end
  return open
end

local function loop()
  theme_check()
  G.sync_fonts()
  update_reaper_touch()
  -- the windows open in this project come back (a new project: just window 1). Switching project tabs
  -- switches to that project's windows.
  local proj = r.EnumProjects(-1)
  if not state.wins or state.wins_proj ~= proj then
    state.wins_proj = proj
    state.wins = {}
    local seen = {}
    local _, list = r.GetProjExtState(0, 'Daniel_FloatingMixer', 'windows')
    for n in (list or ''):gmatch('%d+') do
      n = tonumber(n)
      if n and n >= 1 and not seen[n] then seen[n] = true; state.wins[#state.wins + 1] = { n = n } end
    end
    if #state.wins == 0 then state.wins[1] = { n = 1 } end
    table.sort(state.wins, function(a, b) return a.n < b.n end)
  end
  if state.new_win_req then                       -- the + button: new window, first free number
    state.new_win_req = nil
    local used, n = {}, 1
    for _, W in ipairs(state.wins) do used[W.n] = true end
    while used[n] do n = n + 1 end
    state.wins[#state.wins + 1] = { n = n }
    table.sort(state.wins, function(a, b) return a.n < b.n end)
    state.save_win_list()
  end

  ImGui.PushFont(ctx, font_ui)
  state.kf_ours = false
  local closed = {}
  for _, W in ipairs(state.wins) do
    state.win_in(W)
    local open = state.draw_mixer_window(W)
    state.win_out(W)
    if not open then closed[W] = true end
  end
  -- the Snapshots window works on the mixer window it was opened from
  local SW
  for _, W in ipairs(state.wins) do if W.n == state.snap_for then SW = W end end
  if SW and not closed[SW] then
    state.win_in(SW)
    state.snap_win = true
    state.snapshot_window()
    if not state.snap_win then state.snap_for = nil end
    state.win_out(SW)
  else
    state.snap_for, state.snap_win = nil, false
    state.snapshot_window()                       -- (just resets its typing state)
  end
  keep_reaper_focus()
  ImGui.PopFont(ctx)

  -- closing windows: the last one closing ends the script (and is reopened next time)
  if next(closed) then
    local keep = {}
    for _, W in ipairs(state.wins) do if not closed[W] then keep[#keep + 1] = W end end
    if #keep == 0 then
      DFM_closed_by_user = true   -- closed on purpose: don't reopen it at the next startup
      return
    end
    for W in pairs(closed) do state.forget_win_color(W.n) end
    state.wins = keep
    state.save_win_list()
  end
  r.defer(loop)
end

-- label font: the theme's lb_font face, created before drawing starts so it can be attached
do
  local face = 'Calibri'
  local ok, _, ini = pcall(resolve_theme_dir, r.GetLastColorThemeFile())
  local d = ok and ini and read_all(ini)
  local hx = d and d:match('\nlb_font=(%x+)')
  if hx and #hx >= 92 then
    local chars = {}
    for i = 57, math.min(#hx, 120), 2 do
      local c = tonumber(hx:sub(i, i + 1), 16)
      if not c or c == 0 then break end
      chars[#chars + 1] = string.char(c)
    end
    if #chars > 0 then face = table.concat(chars) end
  end
  local home = os.getenv('HOME') or ''
  local lf = face:lower()
  local cands = {
    '/Library/Fonts/' .. face .. '.ttf', '/Library/Fonts/' .. lf .. '.ttf',
    home .. '/Library/Fonts/' .. face .. '.ttf', home .. '/Library/Fonts/' .. lf .. '.ttf',
    '/Applications/Microsoft Word.app/Contents/Resources/DFonts/' .. lf .. '.ttf',
    '/Applications/Microsoft Excel.app/Contents/Resources/DFonts/' .. lf .. '.ttf',
    '/Applications/Microsoft PowerPoint.app/Contents/Resources/DFonts/' .. lf .. '.ttf',
    '/Applications/Microsoft Outlook.app/Contents/Resources/DFonts/' .. lf .. '.ttf',
    'C:/Windows/Fonts/' .. lf .. '.ttf',
  }
  local src = face
  for _, c in ipairs(cands) do if file_exists(c) then src = c; break end end
  local okf, f = pcall(ImGui.CreateFont, src, FONT_BASE)
  if okf and f and pcall(ImGui.Attach, ctx, f) then font_label = f end
  -- smaller copy for the rename field (fonts have a fixed size here, so it's created up front too)
  local okr, fr = pcall(ImGui.CreateFont, src, 14)
  if okr and fr and pcall(ImGui.Attach, ctx, fr) then font_rename = fr end
  G.label_src = src
end

-- Windows display scaling: the strips are drawn smaller by K (see draw_k). Their text would then be
-- shrunk from the size its fonts were made at and look soft, so the strip fonts are made again at
-- K x their size; the text then keeps the same proportions as at 100%. Runs at the start of a frame,
-- only when K changes (never on macOS / Linux, where K stays 1). The top row and menus keep font_ui.
G.sync_fonts = function()
  local K = state.ui_k or 1
  if math.abs(K - (G.font_k or 1)) < 0.001 then return end
  G.font_k = K
  local function mk(face, size, flags)
    local ok, f = pcall(ImGui.CreateFont, face, size, flags)
    if ok and f and pcall(ImGui.Attach, ctx, f) then return f end
  end
  local base = math.max(6, math.floor(FONT_BASE * K + 0.5))
  local old = { font_reg, font_bold, font_list, font_label, font_rename }
  local list_is_reg = font_list == font_reg
  local nr = mk('sans-serif', base)
  local nb = mk('sans-serif', base, ImGui.FontFlags_Bold)
  if not (nr and nb) then G.font_k = 1; return end    -- couldn't make them: keep the old fonts as they are
  font_reg, font_bold = nr, nb
  G.font_base = base
  if list_is_reg then font_list = font_reg
  elseif Theme.face then font_list = mk(Theme.face, base) or font_reg end
  if G.label_src then
    font_label = mk(G.label_src, base) or font_label
    font_rename = mk(G.label_src, math.max(6, math.floor(14 * K + 0.5))) or font_rename
  end
  state_list_fix = nil                                  -- measured again with the new fonts
  local now = { [font_reg] = true, [font_bold] = true, [font_list] = true }
  if font_label then now[font_label] = true end
  if font_rename then now[font_rename] = true end
  for _, f in ipairs(old) do
    if f and not now[f] then pcall(ImGui.Detach, ctx, f) end
  end
end

r.defer(loop)
