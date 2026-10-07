-- @description Daniel_Meter Bridge
-- @version 1.0
-- @author Daniel
-- @about
--   # Meter Bridge
--   A small window with segmented, console-style meters for all tracks (like the meter page in
--   Mixing Station or on a live console), for watching levels while recording with the mixer closed.
--
--   - One strip per track, laid out like the mixer: input selector, clip light, LED meter, name,
--     and the number bar in the track color at the bottom
--   - Input selector drawn with the theme's dropdown image (Default 7 family), showing the input
--     number; click it to change the track's input
--   - Meter colors: deep green below -18, light green -18 to -6, amber -6 to 0, red = clip
--   - Record-armed tracks show their input (as REAPER's meters do), names turn red
--   - Armed tracks with a mono input show a single meter
--   - Peak hold (off / 1 s / 2 s / 5 s / until reset), latched clip lights
--   - Clip lights follow REAPER's own peak hold: when REAPER resets its peaks, they reset too
--   - Strips wrap into rows when there's room; in a short window (e.g. the top docker) they stay in
--     one row that scrolls sideways, and the strip drops the input selector, then moves the name
--     into the colored bar, and uses fewer, bigger LEDs as it gets shorter
--   - Docks like any REAPER window
--   - Several bridge windows at once (the + button, or New window), like the Floating Mixer: each has its
--     own color (title bar, and the dB-scale column) and its own view options; each project remembers
--     its windows. Closing the last window closes the script
--   - Keyboard focus goes straight back to REAPER after a click (Space still plays)
--
--   Mouse:
--   - Tracks per window: all, record-armed, follow the selection, or a fixed list (Show selected
--     tracks / Clear list / Tracks to show), like the Floating Mixer; lists are saved in the project
--   - Click meter / name / number bar: select track (Cmd/Ctrl: toggle, Shift: range)
--   - Double-click name: rename the track (Enter: keep, Esc: cancel)
--   - Double-click number bar: recolor the track with the Daniel_Color Palette script
--   - Click an input selector: change the track's record input
--   - Click a clip light: reset that track (Cmd/Ctrl-click: reset all)
--   - + (top of the dB column, level with the input selectors): open a new bridge window
--   - Right-click the title bar or the dB column: New window, Window color, Dock / Undock, Close window
--   - Right-click anywhere else: options (tracks, width, peak hold, release, names, input selector...)
--   - Running the action again closes the window
--
--   Toolbar / startup (same as the Floating Mixer):
--   - The toolbar button runs "Daniel_Meter Bridge (toolbar toggle).lua"; both buttons always show
--     whether the bridge is really open, however it was opened or closed
--   - reaper.ini [toolbar button states] Meter_Bridge=1 while open. Closing the window writes 0;
--     quitting REAPER leaves 1, so the startup action reopens it next time
--
--   Requirements: REAPER 7, ReaImGui 0.9.3 or newer (ReaPack).
--   Recommended: js_ReaScriptAPI or SWS (keyboard focus back to REAPER).

local r = reaper
if not r.ImGui_GetBuiltinPath then
  r.MB('This script requires the ReaImGui extension (install it via ReaPack).', 'Meter Bridge', 0)
  return
end
package.path = r.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9.3'

local EXT = 'Daniel_MeterBridge'
local ctx = ImGui.CreateContext('Daniel Meter Bridge')
local font_ui    = ImGui.CreateFont('sans-serif', 13)
local font_small = ImGui.CreateFont('sans-serif', 11)
local font_num   = ImGui.CreateFont('sans-serif', 12, ImGui.FontFlags_Bold)
local font_name  = ImGui.CreateFont('sans-serif', 13)   -- track names
ImGui.Attach(ctx, font_ui); ImGui.Attach(ctx, font_small); ImGui.Attach(ctx, font_num); ImGui.Attach(ctx, font_name)

-- toolbar toggle state; launching the script again while it runs closes it
local _, _, sec_id, cmd_id = r.get_action_context()

-- Toolbar sync: the toolbar button runs the separate "(toolbar toggle)" script. This script keeps that
-- button (and its own toggle state) matching whether the bridge is really open, however it was started
-- or closed, and keeps the Meter_Bridge flag in reaper.ini for the startup action.
local Sync = { closed_by_user = false }
do
local TOGGLE_KEY = 'Meter_Bridge'                      -- the key in reaper.ini that the startup action reads
local TOGGLE_FILE = 'Daniel_Meter Bridge (toolbar toggle).lua'
-- a script's command ID, found by its file name in the action list (reaper-kb.ini)
local function find_script_cmd(fname)
  fname = fname:lower()
  local f = io.open(r.GetResourcePath() .. '/reaper-kb.ini', 'rb')
  if not f then return end
  local found
  for line in f:lines() do
    local sec, id = line:match('^SCR%s+%d+%s+(%d+)%s+(%S+)')
    if sec == '0' then
      local file = line:match('"([^"]*)"%s*$') or line:match('(%S+)%s*$') or ''
      if (file:gsub('\\', '/'):match('([^/]+)$') or ''):lower() == fname then
        local cmd = r.NamedCommandLookup('_' .. id)
        if cmd and cmd ~= 0 then found = cmd; break end
      end
    end
  end
  f:close()
  return found
end
local function set_visual_state(on)
  local v = on and 1 or 0
  r.SetToggleCommandState(sec_id, cmd_id, v); r.RefreshToolbar2(sec_id, cmd_id)
  local tid = find_script_cmd(TOGGLE_FILE)
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
set_visual_state(true)
write_ini_flag(true)
-- atexit only updates the buttons: REAPER quitting also runs it, and the ini flag must stay 1 then,
-- so the bridge comes back on the next startup. (The toggle script writes 0 itself when it closes it.)
r.atexit(function()
  set_visual_state(false)
  if Sync.closed_by_user then write_ini_flag(false) end
end)
end
-- launching the script again while it runs closes it (a toggle), without REAPER's dialog
if r.set_action_options then r.set_action_options(1) end

--------------------------------------------------------------------------------
-- Settings (saved in REAPER's extstate)
--------------------------------------------------------------------------------
local S, G = {}, {}   -- S: the settings of the window being drawn; G: the ones shared by all windows
local DEFAULTS = {
  filter = 'all',        -- 'all' | 'armed' | 'follow' (selected tracks, live) | 'list' (chosen tracks)
  skip_hidden = 1,       -- skip tracks hidden in the mixer (on until you turn it off)
  width = 'narrow',      -- 'narrow' | 'normal' | 'wide'
  hold = 1,              -- peak hold seconds; 0 = off, -1 = until reset
  release = 'fast',      -- 'fast' | 'medium' | 'slow'
  names = 1,             -- track names under the meter
  input = 'number',      -- input selector: 'number' (shown) | 'off'
}
-- view options are per window; window 1 uses the original names (its settings carry over), others '_2'...
local WIN_KEYS = { filter = true, skip_hidden = true, width = true, names = true, input = true, dock = true }
local function opt_key(k, n) return (n == 1 or not WIN_KEYS[k]) and k or (k .. '_' .. n) end
local function load_opt(k, n)
  local v, d = r.GetExtState(EXT, opt_key(k, n)), DEFAULTS[k]
  if v == '' or (k == 'release' and not ({ fast = 1, medium = 1, slow = 1 })[v]) then return d end
  if type(d) == 'number' then return tonumber(v) or d end
  if k == 'filter' and v == 'selected' then return 'follow' end   -- (older name)
  if k == 'input' and v ~= 'off' then return 'number' end        -- (channel names were dropped)
  return v
end
for k in pairs(DEFAULTS) do if not WIN_KEYS[k] then G[k] = load_opt(k, 1) end end
local function win_settings(n)
  local t = setmetatable({ _n = n }, { __index = G })
  for k in pairs(WIN_KEYS) do if DEFAULTS[k] ~= nil then t[k] = load_opt(k, n) end end
  return t
end
S = win_settings(1)
local function set_opt(k, v)
  if WIN_KEYS[k] then S[k] = v else G[k] = v end
  r.SetExtState(EXT, opt_key(k, S._n), tostring(v), true)
end

local WIDTHS  = { narrow = 24, normal = 36, wide = 48 }
-- dB per second. REAPER's own meter decay (Preferences > Track control panels) also applies:
-- the meter can't fall faster than that.
local RELEASE = { fast = 120, medium = 60, slow = 30 }

--------------------------------------------------------------------------------
-- Look
--------------------------------------------------------------------------------
-- LED segments (dB thresholds, top to bottom): a segment lights when the level reaches it.
-- Evenly spaced like a console bridge; the scale is finer near the top.
local SEG = { 0, -1, -2, -3, -4, -6, -8, -10, -12, -15, -18, -21, -24, -27, -30, -35, -40, -45, -50, -60 }
-- shorter meters use fewer, bigger LEDs (same color zones)
local SEG_SHORT = { 0, -3, -6, -9, -12, -18, -24, -30, -40, -60 }
-- dB labels by priority: placed in this order wherever they don't overlap a label already placed
local LABEL_ORDER = { 0, -18, -60, -6, -30, -12, -40, -3, -24 }
local COL = {
  red = 0xFF2A1EFF, amber = 0xFFB020FF, green_light = 0x7EE05AFF, green_deep = 0x1E9A34FF,
  strip = 0x1E1E1EFF, meter_bg = 0x0C0C0CFF, text = 0xC8C8C8FF, text_dim = 0x8A8A8AFF,
  clip_off = 0x3A1A18FF, armed = 0xFF5064FF, sel = 0xFFFFFF30, nobar = 0x5A5F5FFF,
  input_bg = 0x2E2E2EFF, input_text = 0xEBEBEBFF, arrow = 0xB8B8B8FF,
}
local SCALE_W, NUM_H, CLIP_H, NAME_H, INPUT_H = 24, 16, 6, 18, 20
local ROW_FULL = 150      -- a row this tall shows everything; shorter windows keep one row
local MIN_ROW_H = 34

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function rgba(R, G, B, A)
  return (math.floor(clamp(R, 0, 255) + 0.5) << 24) | (math.floor(clamp(G, 0, 255) + 0.5) << 16)
       | (math.floor(clamp(B, 0, 255) + 0.5) << 8) | (A or 255)
end
-- unlit LED: the color mixed into the meter background
local function dim(c, k)
  local bg = COL.meter_bg
  local function ch(s) local a, b = (c >> s) & 255, (bg >> s) & 255; return b + (a - b) * k end
  return rgba(ch(24), ch(16), ch(8))
end
local function brightness(c) return 0.299 * ((c >> 24) & 255) + 0.587 * ((c >> 16) & 255) + 0.114 * ((c >> 8) & 255) end
-- a segment lights when the level reaches its threshold t; colors by zone:
-- 0 and above = clip (red), -6..0 = amber, -18..-6 = light green, below -18 = deep green
local function seg_col(t)
  if t >= 0 then return COL.red elseif t >= -6 then return COL.amber elseif t >= -18 then return COL.green_light end
  return COL.green_deep
end
local function seg_set(list)
  local set = { t = list, lit = {}, unlit = {} }
  for i, t in ipairs(list) do set.lit[i] = seg_col(t); set.unlit[i] = dim(seg_col(t), 0.16) end
  return set
end
local SET_FULL, SET_SHORT = seg_set(SEG), seg_set(SEG_SHORT)

local function val2db(v)
  if not v or v < 0.0000000298023223876953125 then return -150.0 end
  local d = math.log(v) * 8.6858896380650365530225783783321
  return d < -150 and -150.0 or d
end
local function fmt_peak(d)
  if d <= -149.9 then return '-inf' end
  local s = string.format(math.abs(d) >= 10 and '%.0f' or '%.1f', d)
  if s == '-0.0' or s == '-0' then s = '0.0' end
  return (d > 0 and '+' or '') .. s
end

--------------------------------------------------------------------------------
-- Tracks
--------------------------------------------------------------------------------
-- helper tracks of other scripts never show up here
local HIDDEN_TRACKS = { ['always recording (auto)'] = true }
local function hidden_track(tr)
  if tr == r.GetMasterTrack(0) then return false end
  local _, nm = r.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', false)
  return HIDDEN_TRACKS[nm:lower()] == true
end

-- Chosen tracks (like the Floating Mixer's list): a window's own list of tracks, saved in the project.
-- "Show selected tracks" copies the selection into it once; changing the selection later doesn't change it.
local List = {}
do
  local PEXT = 'Daniel_MeterBridge'
  local function key(n) return n == 1 and 'tracks' or ('tracks_' .. n) end
  List.get = function(W)
    if not W.list then
      local _, v = r.GetProjExtState(0, PEXT, key(W.n))
      W.list = {}
      for g in (v or ''):gmatch('[^,]+') do W.list[#W.list + 1] = g end
    end
    return W.list
  end
  List.set = function(W, list)
    W.list = list
    r.SetProjExtState(0, PEXT, key(W.n), table.concat(list, ','))
  end
  List.forget = function(n) r.SetProjExtState(0, PEXT, key(n), '') end
  List.has = function(W, g) for k, v in ipairs(List.get(W)) do if v == g then return k end end end
  List.toggle = function(W, g)
    local l = { table.unpack(List.get(W)) }
    local k = List.has(W, g)
    if k then table.remove(l, k) else l[#l + 1] = g end
    List.set(W, l)
  end
  List.from_selection = function(W)
    local l = {}
    local m = r.GetMasterTrack(0)
    if r.IsTrackSelected(m) then l[1] = r.GetTrackGUID(m) end
    for i = 0, r.CountSelectedTracks(0) - 1 do
      local t = r.GetSelectedTrack(0, i)
      if not hidden_track(t) then l[#l + 1] = r.GetTrackGUID(t) end
    end
    List.set(W, l)
  end
end

local function bridge_tracks(W)
  local out = {}
  local m = r.GetMasterTrack(0)
  if S.filter == 'list' then                     -- the chosen tracks, in track order (master first)
    local want = {}
    for _, g in ipairs(List.get(W)) do want[g] = true end
    if want[r.GetTrackGUID(m)] then out[1] = m end
    for i = 0, r.CountTracks(0) - 1 do
      local t = r.GetTrack(0, i)
      if want[r.GetTrackGUID(t)] and not hidden_track(t) then out[#out + 1] = t end
    end
    return out
  end
  -- the master: in All tracks; in Follow selected when it's selected; never in Record-armed
  -- (a list shows it when MASTER is ticked in Tracks to show)
  if S.filter ~= 'armed' and (S.filter ~= 'follow' or r.IsTrackSelected(m)) then out[1] = m end
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    local ok = not hidden_track(t)
    if ok and S.skip_hidden == 1 and r.GetMediaTrackInfo_Value(t, 'B_SHOWINMIXER') == 0 then ok = false end
    if ok and S.filter == 'armed' and r.GetMediaTrackInfo_Value(t, 'I_RECARM') ~= 1 then ok = false end
    if ok and S.filter == 'follow' and not r.IsTrackSelected(t) then ok = false end
    if ok then out[#out + 1] = t end
  end
  return out
end

local function track_info(tr)
  if tr == r.GetMasterTrack(0) then return 'M', 'MASTER', nil end
  local n = math.floor(r.GetMediaTrackInfo_Value(tr, 'IP_TRACKNUMBER'))
  local _, name = r.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', false)
  local c, col = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_CUSTOMCOLOR')), nil
  if c & 0x1000000 ~= 0 then local R, G, B = r.ColorFromNative(c & 0xFFFFFF); col = rgba(R, G, B) end
  return tostring(n), (name ~= '' and name or ('Track ' .. n)), col
end

-- armed with a mono audio input -> one meter column
local function n_meters(tr)
  if tr == r.GetMasterTrack(0) then return 2 end
  if r.GetMediaTrackInfo_Value(tr, 'I_RECARM') ~= 1 then return 2 end
  local ri = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_RECINPUT'))
  if ri >= 0 and ri < 4096 and ri & (1024 | 2048) == 0 then return 1 end
  return 2
end

--------------------------------------------------------------------------------
-- Record input: labels and names
--------------------------------------------------------------------------------
local INP = {}
function INP.chan_name(i)
  local n = r.GetInputChannelName(i)
  return (n and n ~= '') and n or ('Input ' .. (i + 1))
end
-- full description (tooltip / menu)
function INP.full(v)
  if v < 0 then return 'No input' end
  if v >= 4096 then
    local dev, ch = (v >> 5) & 63, v & 31
    local dn = (dev == 63) and 'All inputs' or (dev == 62) and 'Virtual MIDI keyboard'
            or (select(2, r.GetMIDIInputName(dev, '')) or ('MIDI ' .. (dev + 1)))
    return 'MIDI: ' .. dn .. ' (' .. (ch == 0 and 'all channels' or ('channel ' .. ch)) .. ')'
  end
  local idx = v & 1023
  if v & 2048 ~= 0 then return INP.chan_name(idx) .. ' (multichannel)' end
  if v & 1024 ~= 0 then return INP.chan_name(idx) .. ' / ' .. INP.chan_name(idx + 1) end
  return INP.chan_name(idx)
end
-- short label for the selector: the input number(s)
function INP.label(v)
  if v < 0 then return '-' end
  if v >= 4096 then return 'MIDI' end
  local idx = v & 1023
  local stereo, multi = v & 1024 ~= 0, v & 2048 ~= 0
  local pre, base = '', idx + 1
  if idx >= 512 then pre, base = 'R', idx - 511 end           -- ReaRoute / loopback
  if stereo then return pre .. base .. '/' .. (base + 1) end
  return pre .. base .. (multi and '+' or '')
end

--------------------------------------------------------------------------------
-- Theme image for the input selector: dropdownBg_h from the active theme (Default 7 family),
-- the same image REAPER's mixer draws its input selector with. Zipped themes are unpacked once
-- into a cache. If the image isn't found, the selector is drawn by the script.
--------------------------------------------------------------------------------
local Theme = { file = false, next_check = 0 }
function Theme.exists(p) local f = io.open(p, 'rb'); if f then f:close(); return true end end
function Theme.find_dir(dir, depth)
  r.EnumerateFiles(dir, -1)
  if Theme.exists(dir .. '/dropdownBg_h.png') or Theme.exists(dir .. '/rtconfig.txt') then return dir end
  if depth <= 0 then return end
  local i = 0
  while true do
    local sub = r.EnumerateSubdirectories(dir, i)
    if not sub then return end
    local f = Theme.find_dir(dir .. '/' .. sub, depth - 1)
    if f then return f end
    i = i + 1
  end
end
function Theme.resolve(tf)
  if not tf or tf == '' then return end
  local low = tf:lower()
  local base = tf:gsub('%.[Rr][Ee][Aa][Pp][Ee][Rr][Tt][Hh][Ee][Mm][Ee][Zz][Ii][Pp]$', '')
  base = base:gsub('%.[Rr][Ee][Aa][Pp][Ee][Rr][Tt][Hh][Ee][Mm][Ee]$', '')
  local d = Theme.find_dir(base, 2)                           -- unpacked theme folder next to it
  if d then return d end
  local zip = (low:match('%.reaperthemezip$') and tf) or (Theme.exists(base .. '.ReaperThemeZip') and base .. '.ReaperThemeZip')
  if not zip then return end
  local name = base:match('([^/\\]+)$') or 'theme'
  local dest = r.GetResourcePath() .. '/Data/Daniel_MeterBridge/theme_cache/' .. name
  local f = io.open(zip, 'rb'); local stamp = f and tostring(f:seek('end')) or ''; if f then f:close() end
  local sf = io.open(dest .. '/.stamp', 'rb'); local old = sf and sf:read('a'); if sf then sf:close() end
  if old ~= stamp or not Theme.find_dir(dest, 3) then
    r.RecursiveCreateDirectory(dest, 0)
    local os_ = r.GetOS()
    local cmd = os_:match('Win') and ('tar -xf "' .. zip .. '" -C "' .. dest .. '"')
             or ((os_:match('OSX') or os_:match('mac')) and '/usr/bin/unzip' or 'unzip') .. ' -o -qq "' .. zip .. '" -d "' .. dest .. '"'
    r.ExecProcess(cmd, 120000)
    local wf = io.open(dest .. '/.stamp', 'wb'); if wf then wf:write(stamp); wf:close() end
  end
  return Theme.find_dir(dest, 3)
end
-- the pink control pixels on the image's border give its fixed (non-stretching) margins
function Theme.analyze(path)
  local slot = 1000
  if gfx.loadimg(slot, path) < 0 then return end
  local w, h = gfx.getimgdim(slot)
  if not w or w < 3 then return end
  local old = gfx.dest
  gfx.dest = slot
  local function pink(x, y)
    gfx.x, gfx.y = x, y
    local R, G, B = gfx.getpixel()
    return R > 0.9 and G < 0.1 and B > 0.9
  end
  local a = { w = w, h = h, x0 = 0, y0 = 0, x1 = w, y1 = h, L = 0, T = 0, R = 0, B = 0 }
  if pink(0, 0) then
    a.x0, a.y0, a.x1, a.y1 = 1, 1, w - 1, h - 1
    local function run(x, y, dx, dy, max)
      local n = 0
      while n < max and pink(x + dx * n, y + dy * n) do n = n + 1 end
      return n
    end
    a.L = run(1, 0, 1, 0, w - 2);          a.T = run(0, 1, 0, 1, h - 2)
    a.R = run(w - 2, h - 1, -1, 0, w - 2); a.B = run(w - 1, h - 2, 0, -1, h - 2)
  end
  gfx.dest = old
  return a
end
function Theme.check()
  local now = r.time_precise()
  if now < Theme.next_check then return end
  Theme.next_check = now + 2
  local tf = r.GetLastColorThemeFile() or ''
  if tf == Theme.file then return end
  Theme.file = tf
  if Theme.dd and Theme.dd.img then pcall(ImGui.Detach, ctx, Theme.dd.img) end
  Theme.dd = nil
  local ok, dir = pcall(Theme.resolve, tf)
  if not ok or not dir then return end
  -- 1 pt = one pixel of the 100% image, half a pixel of the 200% one
  for _, v in ipairs({ { '200/', 0.5 }, { '150/', 1 / 1.5 }, { '', 1 } }) do
    local p = dir .. '/' .. v[1] .. 'dropdownBg_h.png'
    if Theme.exists(p) then
      local a = Theme.analyze(p)
      local okc, im = pcall(ImGui.CreateImage, p)
      if a and okc and im and pcall(ImGui.Attach, ctx, im) then a.img, a.k = im, v[2]; Theme.dd = a; return end
    end
  end
end

--------------------------------------------------------------------------------
-- Meter ballistics: instant rise, release at the chosen rate, peak hold
--------------------------------------------------------------------------------
local meters = {}
local function meter(tr, ch, now)
  local key = r.GetTrackGUID(tr) .. ':' .. ch
  local raw = val2db(r.Track_GetPeakInfo(tr, ch))
  local st = meters[key]
  if not st then st = { disp = raw, hold = raw, hold_t = now, t = now }; meters[key] = st end
  local dt, rel = now - st.t, RELEASE[S.release] or 20
  st.t = now
  st.disp = math.max(raw, st.disp - rel * dt)
  if S.hold == 0 then
    st.hold = st.disp
  elseif raw >= st.hold then
    st.hold, st.hold_t = raw, now
  elseif S.hold > 0 and now - st.hold_t > S.hold then
    st.hold = math.max(st.disp, st.hold - rel * dt)
  end
  return st.disp, st.hold
end

local function reset_track(tr)
  r.Track_GetPeakHoldDB(tr, 0, true); r.Track_GetPeakHoldDB(tr, 1, true)
  local g = r.GetTrackGUID(tr)
  for ch = 0, 1 do local st = meters[g .. ':' .. ch]; if st then st.hold, st.hold_t = st.disp, 0 end end
end
local function reset_all()
  reset_track(r.GetMasterTrack(0))
  for i = 0, r.CountTracks(0) - 1 do reset_track(r.GetTrack(0, i)) end
end

--------------------------------------------------------------------------------
-- Drawing helpers
--------------------------------------------------------------------------------
local D = {}   -- per-frame drawing state (draw list)
local function rect(x1, y1, x2, y2, col, rnd) ImGui.DrawList_AddRectFilled(D.dl, x1, y1, x2, y2, col, rnd or 0) end
-- 9-slice: the image's fixed margins stay their size, the middle stretches
local function nine(im, x1, y1, x2, y2, tint)
  local k = im.k
  local sx = { x1, x1 + im.L * k, x2 - im.R * k, x2 }
  local sy = { y1, y1 + im.T * k, y2 - im.B * k, y2 }
  local u = { im.x0, im.x0 + im.L, im.x1 - im.R, im.x1 }
  local v = { im.y0, im.y0 + im.T, im.y1 - im.B, im.y1 }
  if sx[3] < sx[2] then local m = (sx[1] + sx[4]) / 2; sx[2], sx[3] = m, m end
  if sy[3] < sy[2] then local m = (sy[1] + sy[4]) / 2; sy[2], sy[3] = m, m end
  for i = 1, 3 do for j = 1, 3 do
    if sx[i + 1] > sx[i] and sy[j + 1] > sy[j] and u[i + 1] > u[i] and v[j + 1] > v[j] then
      ImGui.DrawList_AddImage(D.dl, im.img, sx[i], sy[j], sx[i + 1], sy[j + 1],
        u[i] / im.w, v[j] / im.h, u[i + 1] / im.w, v[j + 1] / im.h, tint or 0xFFFFFFFF)
    end
  end end
end
local function text_w(font, str) ImGui.PushFont(ctx, font); local w, h = ImGui.CalcTextSize(ctx, str); ImGui.PopFont(ctx); return w, h end
-- text centered in a box (or left / right aligned), clipped to it
local function text_in(font, x1, y1, x2, y2, col, str, align)
  local w, h = text_w(font, str)
  local x = (align == 'r' and x2 - w - 2) or (align == 'l' and x1 + 2) or (x1 + x2 - w) / 2
  ImGui.DrawList_PushClipRect(D.dl, x1, y1, x2, y2, true)
  ImGui.DrawList_AddText(D.dl, math.floor(x), math.floor((y1 + y2 - h) / 2), col, str)
  ImGui.DrawList_PopClipRect(D.dl)
end
local function fit(font, str, maxw)
  if text_w(font, str) <= maxw then return str end
  while #str > 1 and text_w(font, str .. '.') > maxw do str = str:sub(1, -2) end
  return str .. '.'
end
local function hit(id, x1, y1, x2, y2, tip)
  if D.clip_x then                                 -- the part under the dB scale isn't clickable
    if x2 <= D.clip_x then return {} end
    x1 = math.max(x1, D.clip_x)
  end
  ImGui.SetCursorScreenPos(ctx, x1, y1)
  ImGui.InvisibleButton(ctx, id, math.max(1, x2 - x1), math.max(1, y2 - y1))
  local hov = ImGui.IsItemHovered(ctx)
  if tip and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayNormal) then ImGui.SetTooltip(ctx, tip) end
  return { click = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left), hov = hov,
           rclick = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right),
           dbl = hov and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) }
end
local function mods() return ImGui.GetKeyMods(ctx) end
local function is_shift() return (mods() & ImGui.Mod_Shift) ~= 0 end
local function is_ctrl()  return (mods() & ImGui.Mod_Ctrl) ~= 0 end
local function is_alt()   return (mods() & ImGui.Mod_Alt) ~= 0 end

local function select_click(tr)
  local m = r.GetMasterTrack(0)
  if is_shift() and D.anchor and D.anchor ~= m and tr ~= m and r.ValidatePtr2(0, D.anchor, 'MediaTrack*') then
    local a = math.floor(r.GetMediaTrackInfo_Value(D.anchor, 'IP_TRACKNUMBER'))
    local b = math.floor(r.GetMediaTrackInfo_Value(tr, 'IP_TRACKNUMBER'))
    if a > b then a, b = b, a end
    r.PreventUIRefresh(1)
    if not is_ctrl() then
      for i = 0, r.CountTracks(0) - 1 do r.SetTrackSelected(r.GetTrack(0, i), false) end
      r.SetTrackSelected(m, false)
    end
    for n = a, b do r.SetTrackSelected(r.GetTrack(0, n - 1), true) end
    r.PreventUIRefresh(-1)
    return
  end
  if is_ctrl() then r.SetTrackSelected(tr, not r.IsTrackSelected(tr)) else r.SetOnlyTrackSelected(tr) end
  D.anchor = tr
end

--------------------------------------------------------------------------------
-- Strip geometry: shared by the strips and the dB scale so they line up
--------------------------------------------------------------------------------
-- what a strip of height h has room for (the same for every strip in a frame)
local function strip_layout(h)
  local L = { input = S.input ~= 'off' and h >= ROW_FULL, name = S.names == 1 and h >= 90 }
  local mh = h - 3 - (L.input and INPUT_H + 4 or 0) - CLIP_H - 2 - NUM_H - (L.name and NAME_H or 0) - 3
  L.seg = (mh >= 4 * #SEG) and SET_FULL or SET_SHORT
  return L
end
local function geom(y0, h)
  local ct = y0 + 3 + (D.lay.input and INPUT_H + 4 or 0)
  local mt = ct + CLIP_H + 2
  local mb = y0 + h - NUM_H - (D.lay.name and NAME_H or 0) - 3
  return ct, mt, mb
end
local function seg_y(i, mt, mb)
  local sh = (mb - mt) / #D.lay.seg.t
  return mt + (i - 1) * sh, mt + i * sh, sh
end

local function draw_scale(x, y0, h, bg, row_h, txt)
  local _, mt, mb = geom(y0, h)
  -- covers everything left of the strips, from the window's own edge (the padding included),
  -- so strips scrolled sideways don't show through
  local wx = ImGui.GetWindowPos(ctx)
  rect(math.min(wx, x), y0 - 2, x + SCALE_W, y0 + row_h, bg)
  local idx = {}
  for i, t in ipairs(D.lay.seg.t) do idx[t] = i end
  local placed = {}
  ImGui.PushFont(ctx, font_small)
  for _, t in ipairs(LABEL_ORDER) do
    local i = idx[t]
    if i then
      local a, b = seg_y(i, mt, mb)
      local cy = (a + b) / 2
      local ok = cy - 5 >= y0 and cy + 5 <= y0 + h
      for _, py in ipairs(placed) do if math.abs(py - cy) < 11 then ok = false; break end end
      if ok then
        placed[#placed + 1] = cy
        text_in(font_small, x, cy - 7, x + SCALE_W - 2, cy + 7, txt or COL.text_dim, tostring(t), 'r')
      end
    end
  end
  ImGui.PopFont(ctx)
end

-- the track's record input, like the mixer's input selector; click: input menu
local function draw_input(tr, x1, y1, x2, y2)
  local v = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_RECINPUT'))
  local hh = hit('##input', x1, y1, x2, y2, 'Input: ' .. INP.full(v) .. '\nClick: change input')
  local im = Theme.dd
  local ax
  if im and (x2 - x1) >= 30 then
    nine(im, x1, y1, x2, y2, hh.hov and 0xFFFFFFFF or 0xFFFFFFE0)
    if hh.hov then nine(im, x1, y1, x2, y2, 0xFFFFFF40) end
    local rw = im.R * im.k                                       -- the fixed right end with the circle
    ax = x2 - rw * 0.54
  else
    rect(x1, y1, x2, y2, hh.hov and 0x3A3A3AFF or COL.input_bg, 4)
    ax = x2 - 6
  end
  local ay = (y1 + y2) / 2
  local tx2 = ax - 5                                             -- the label may run up to the arrow
  -- the arrow steps aside when the label wouldn't fit next to it (narrow strips, '3/4', 'MIDI'...)
  local lab = INP.label(v)
  local arrow = (x2 - x1) >= 26 and text_w(font_small, lab) <= tx2 - x1 - 2
  if not arrow then tx2 = x2 end
  if arrow then ImGui.DrawList_AddTriangleFilled(D.dl, ax - 3.5, ay - 2, ax + 3.5, ay - 2, ax, ay + 2.5, COL.arrow) end
  ImGui.PushFont(ctx, font_small)
  text_in(font_small, x1 + 2, y1, tx2, y2, v < 0 and COL.text_dim or COL.input_text, fit(font_small, lab, tx2 - x1 - 2))
  ImGui.PopFont(ctx)
  if hh.click then D.menu_tr, D.open_input = tr, true end      -- opened at window level (see frame)
end

-- The color palette script: found by name in REAPER's action list (reaper-kb.ini), so no command ID
-- is needed. If it isn't there, the action on the mixer's double-click mouse modifier is used.
local PALETTE_NAME = 'daniel_color palette'
local function palette_command()
  if D.palette_cmd then return D.palette_cmd end
  local f = io.open(r.GetResourcePath() .. '/reaper-kb.ini', 'rb')
  if f then
    for line in f:lines() do
      local sec, id, desc = line:match('^SCR%s+%d+%s+(%d+)%s+(%S+)%s+"(.-)"')
      if sec == '0' and desc:lower():gsub('_', ' '):find(PALETTE_NAME:gsub('_', ' '), 1, true) then
        local cmd = r.NamedCommandLookup('_' .. id)
        if cmd and cmd > 0 then D.palette_cmd = cmd; break end
      end
    end
    f:close()
  end
  if not D.palette_cmd and r.GetMouseModifier then
    local a = r.GetMouseModifier('MM_CTX_MCP_DBLCLK', 0) or ''
    local id, kind = a:match('^(%S+)%s*(%a?)$')
    if id and kind ~= 'm' and id ~= '-1' then
      local cmd = tonumber(id) or r.NamedCommandLookup(id:sub(1, 1) == '_' and id or ('_' .. id))
      if cmd and cmd > 0 then D.palette_cmd = cmd end
    end
  end
  return D.palette_cmd
end
local function recolor(tr)
  local cmd = palette_command()
  if not cmd then
    r.MB('Could not find the "Daniel_Color Palette" script in the action list.', 'Meter Bridge', 0)
    return
  end
  if not r.IsTrackSelected(tr) then r.SetOnlyTrackSelected(tr) end
  r.Main_OnCommand(40914, 0)                    -- make it the last touched track too
  D.no_refocus = true                           -- leave the keyboard with the palette window
  r.Main_OnCommand(cmd, 0)
end

-- inline rename, like the mixer: a white field in the name area. Enter / click away: keep, Esc: cancel
local function rename_field(tr, x1, y1, x2, y2)
  ImGui.PushFont(ctx, font_name)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 2, 1)
  local fh = ImGui.GetFrameHeight(ctx)
  local fy = math.floor((y1 + y2 - fh) / 2)
  rect(x1, fy, x2, fy + fh, 0xFFFFFFFF)
  ImGui.SetCursorScreenPos(ctx, x1, fy)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x00000000)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x000000FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_TextSelectedBg, 0x3D8BFF70)
  ImGui.SetNextItemWidth(ctx, x2 - x1)
  if D.rename_focus then ImGui.SetKeyboardFocusHere(ctx); D.rename_focus = false end
  local enter, buf = ImGui.InputText(ctx, '##rename', D.name_buf,
    ImGui.InputTextFlags_EnterReturnsTrue | ImGui.InputTextFlags_AutoSelectAll)
  D.name_buf = buf
  local deact = ImGui.IsItemDeactivated(ctx)
  ImGui.PopStyleColor(ctx, 3); ImGui.PopStyleVar(ctx); ImGui.PopFont(ctx)
  if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
    D.renaming = nil
  elseif enter or deact then
    D.renaming = nil
    local _, old = r.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', false)
    if buf ~= old then
      r.Undo_BeginBlock()
      r.GetSetMediaTrackInfo_String(tr, 'P_NAME', buf, true)
      r.Undo_EndBlock('Rename track', -1)
    end
    D.refocus = true                            -- keyboard back to REAPER
  end
end

local function draw_strip(tr, x, y0, w, h, now)
  local num, name, tcol = track_info(tr)
  local is_master = tr == r.GetMasterTrack(0)
  local armed = not is_master and r.GetMediaTrackInfo_Value(tr, 'I_RECARM') == 1
  local sel = r.IsTrackSelected(tr)
  local x1, x2 = x + 1, x + w - 1
  rect(x1, y0, x2, y0 + h, COL.strip)
  if sel then rect(x1, y0, x2, y0 + h, COL.sel) end

  if D.lay.input and not is_master then draw_input(tr, x1 + 2, y0 + 3, x2 - 2, y0 + 3 + INPUT_H) end

  -- meters
  local ct, mt, mb = geom(y0, h)
  local n = n_meters(tr)
  local mx1, mx2 = x1 + 3, x2 - 3
  local gap = 2
  local cw = (n == 2) and (mx2 - mx1 - gap) / 2 or (mx2 - mx1)
  for c = 0, n - 1 do
    local disp, hold = meter(tr, c, now)
    local cx1 = math.floor(mx1 + c * (cw + gap))
    local cx2 = math.floor(cx1 + cw)
    rect(cx1, mt, cx2, mb, COL.meter_bg)
    local set = D.lay.seg
    local hold_i
    if hold > -149 then for i, t in ipairs(set.t) do if hold >= t then hold_i = i; break end end end
    for i, t in ipairs(set.t) do
      local a, b, sh = seg_y(i, mt, mb)
      local g = (sh >= 4) and 1 or 0
      local lit = disp >= t or i == hold_i
      rect(cx1, math.floor(a), cx2, math.floor(b) - g, lit and set.lit[i] or set.unlit[i])
    end
  end

  local hm = hit('##meter', x1, ct + CLIP_H + 2, x2, mb + 2)
  if hm.click then select_click(tr) end

  -- clip light on top (latched: REAPER's peak hold went above 0 dBFS). Click: reset
  local hold_db = -150
  for c = 0, (n == 1 and 0 or 1) do hold_db = math.max(hold_db, r.Track_GetPeakHoldDB(tr, c, false) * 100) end
  local clipped = hold_db > 0
  -- REAPER reset its peaks (on record start if it's set to, Cmd/Ctrl-click in its mixer...): drop our
  -- held LEDs for this track too
  do
    local g = r.GetTrackGUID(tr)
    D.rhold = D.rhold or {}
    local prev = D.rhold[g]
    if prev and hold_db < prev - 0.5 then
      for ch = 0, 1 do local st = meters[g .. ':' .. ch]; if st then st.hold, st.hold_t = st.disp, 0 end end
    end
    D.rhold[g] = hold_db
  end
  rect(mx1, ct, mx2, ct + CLIP_H, clipped and COL.red or COL.clip_off)
  local hr = hit('##clip', x1, ct - 2, x2, ct + CLIP_H + 2,
    'Max peak ' .. fmt_peak(hold_db) .. ' dB\nClick: reset  |  Cmd/Ctrl-click: reset all')
  if hr.click then if is_ctrl() or is_alt() then reset_all() else reset_track(tr) end end

  local tip = num .. ': ' .. name .. '\nClick: select (Cmd/Ctrl: toggle, Shift: range)'

  -- name, like the mixer: red when armed, the track color when it has one, else light gray
  local by = y0 + h - NUM_H
  if D.lay.name then
    local ny = by - NAME_H
    local nc = COL.text
    if armed then nc = COL.armed
    elseif tcol then
      local R, G, B = (tcol >> 24) & 255, (tcol >> 16) & 255, (tcol >> 8) & 255
      if brightness(tcol) < 85 then R, G, B = 100 + 2 * R, 100 + 2 * G, 100 + 2 * B end
      nc = rgba(R, G, B)
    end
    if D.renaming == tr and D.rename_win == D.win then
      rename_field(tr, x1 + 1, ny, x2 - 1, by)
    else
      ImGui.PushFont(ctx, font_name)
      text_in(font_name, x1, ny, x2, by, nc, fit(font_name, name, x2 - x1 - 2))
      ImGui.PopFont(ctx)
      local hn = hit('##name', x1, ny, x2, by, tip .. (is_master and '' or '\nDouble-click: rename'))
      if hn.click then select_click(tr) end
      if hn.dbl and not is_master then
        local _, cur = r.GetSetMediaTrackInfo_String(tr, 'P_NAME', '', false)
        D.renaming, D.name_buf, D.rename_focus, D.rename_win = tr, cur, true, D.win
      end
    end
  end

  -- number bar in the track color at the bottom; selection dot on its top edge, like the mixer
  local bar = tcol or COL.nobar
  rect(x1, by, x2, y0 + h, bar)
  ImGui.PushFont(ctx, font_num)
  local bar_text = brightness(bar) > 140 and 0x1A1A1AFF or 0xF0F0F0FF
  if not D.lay.name and S.names == 1 and name ~= 'Track ' .. num then
    -- no room for the name row: the name goes in the bar
    ImGui.PopFont(ctx); ImGui.PushFont(ctx, font_name)
    text_in(font_name, x1, by, x2, y0 + h, bar_text, fit(font_name, name, x2 - x1 - 4))
  else
    text_in(font_num, x1, by, x2, y0 + h, bar_text, num)
  end
  ImGui.PopFont(ctx)
  if sel then ImGui.DrawList_AddCircleFilled(D.dl, (x1 + x2) / 2, by, 2.5, 0xFFFFFFFF) end
  if armed then ImGui.DrawList_AddCircleFilled(D.dl, x2 - 4, by + 4, 2.5, COL.armed) end
  local hb = hit('##bar', x1, by, x2, y0 + h, tip .. (is_master and '' or '\nDouble-click: color palette'))
  if hb.click then select_click(tr) end
  if hb.dbl and not is_master then recolor(tr) end
end

--------------------------------------------------------------------------------
-- Windows (same system as the Floating Mixer): several numbered bridge windows; each project
-- remembers which are open. Window 1 is the theme's mixer gray; the others get a color from the
-- palette by their number (2 = Blue, 3 = Teal...). Right-click > Window color picks one, saved per
-- window in the project; "Automatic" goes back to the palette color.
--------------------------------------------------------------------------------
local Win = {}
do
  local PEXT = 'Daniel_MeterBridge'
  Win.PALETTE = {
    { 'Blue',   0x3F6FB5FF }, { 'Teal',   0x2E9A8EFF }, { 'Green',  0x4F9A45FF }, { 'Amber',  0xC08A2EFF },
    { 'Orange', 0xC0612EFF }, { 'Red',    0xB5443FFF }, { 'Purple', 0x7E5BB5FF }, { 'Pink',   0xB0508AFF },
  }
  Win.mixer_gray = function()
    if r.GetThemeColor then
      local c = r.GetThemeColor('col_mixerbg', 0)
      if c and c >= 0 then local R, G_, B = r.ColorFromNative(c); return rgba(R, G_, B) end
    end
    return 0x333333FF
  end
  local function color_key(n) return n == 1 and 'color' or ('color_' .. n) end
  -- returns the window's color (0xRRGGBBAA) and whether it was picked by hand
  Win.color = function(n)
    local _, v = r.GetProjExtState(0, PEXT, color_key(n))
    local c = tonumber(v or '', 16)
    if c then return (c << 8) | 0xFF, true end
    if n == 1 then return Win.mixer_gray(), false end
    return Win.PALETTE[(n - 2) % #Win.PALETTE + 1][2], false
  end
  -- col = 0xRRGGBBAA, or nil for automatic
  Win.set_color = function(n, col)
    r.SetProjExtState(0, PEXT, color_key(n), col and string.format('%06X', col >> 8) or '')
    r.MarkProjectDirty(0)
  end
  Win.forget = function(n)
    r.SetProjExtState(0, PEXT, color_key(n), '')
    if n > 1 then for k in pairs(WIN_KEYS) do if k ~= 'dock' then r.DeleteExtState(EXT, opt_key(k, n), true) end end end
  end
  -- a darker / dimmer version of a color (for inactive title bars)
  Win.dim = function(c, k)
    return rgba(((c >> 24) & 255) * k, ((c >> 16) & 255) * k, ((c >> 8) & 255) * k, c & 255)
  end
  -- black or white text, whichever reads better on the color
  Win.text_on = function(c) return brightness(c) > 150 and 0x1A1A1AFF or 0xFFFFFFFF end

  Win.save_list = function()
    local t = {}
    for _, W in ipairs(Win.list) do t[#t + 1] = tostring(W.n) end
    r.SetProjExtState(0, PEXT, 'windows', table.concat(t, ','))   -- per project
  end
  -- the windows open in this project come back (a new project: just window 1); switching project
  -- tabs switches to that project's windows
  Win.load = function()
    local proj = r.EnumProjects(-1)
    if Win.list and Win.proj == proj then return end
    Win.proj, Win.list = proj, {}
    local seen = {}
    local _, list = r.GetProjExtState(0, PEXT, 'windows')
    for n in (list or ''):gmatch('%d+') do
      n = tonumber(n)
      if n and n >= 1 and not seen[n] then seen[n] = true; Win.list[#Win.list + 1] = { n = n } end
    end
    if #Win.list == 0 then Win.list[1] = { n = 1 } end
    table.sort(Win.list, function(a, b) return a.n < b.n end)
  end
  Win.add = function()                     -- new window, first free number
    local used, n = {}, 1
    for _, W in ipairs(Win.list) do used[W.n] = true end
    while used[n] do n = n + 1 end
    Win.list[#Win.list + 1] = { n = n }
    table.sort(Win.list, function(a, b) return a.n < b.n end)
    Win.save_list()
  end

  -- the color submenu
  Win.color_menu = function(n)
    if not ImGui.BeginMenu(ctx, 'Window color') then return end
    local cur, picked = Win.color(n)
    if ImGui.MenuItem(ctx, 'Automatic', nil, not picked) then Win.set_color(n, nil) end
    ImGui.Separator(ctx)
    local gray = Win.mixer_gray()
    ImGui.ColorButton(ctx, '##swGray', gray, ImGui.ColorEditFlags_NoTooltip | ImGui.ColorEditFlags_NoBorder, 12, 12)
    ImGui.SameLine(ctx)
    if ImGui.MenuItem(ctx, 'Default', nil, picked and cur == gray) then Win.set_color(n, gray) end
    for _, p in ipairs(Win.PALETTE) do
      ImGui.ColorButton(ctx, '##sw' .. p[1], p[2], ImGui.ColorEditFlags_NoTooltip | ImGui.ColorEditFlags_NoBorder, 12, 12)
      ImGui.SameLine(ctx)
      if ImGui.MenuItem(ctx, p[1], nil, picked and cur == p[2]) then Win.set_color(n, p[2]) end
    end
    ImGui.Separator(ctx)
    if ImGui.BeginMenu(ctx, 'Custom') then
      local rv, rgb = ImGui.ColorPicker3(ctx, '##custom_color', cur >> 8,
        ImGui.ColorEditFlags_NoSidePreview | ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoAlpha)
      if rv then Win.set_color(n, (rgb << 8) | 0xFF) end
      ImGui.EndMenu(ctx)
    end
    ImGui.EndMenu(ctx)
  end
end

--------------------------------------------------------------------------------
-- Options menu (right-click anywhere in a window, title bar included)
--------------------------------------------------------------------------------
-- the window menu: right-click the title bar or the dB column (the colored part, also when docked)
local function window_menu(W)
  if not ImGui.BeginPopup(ctx, 'win_menu') then return end
  if ImGui.MenuItem(ctx, 'New window') then Win.new_req = true end
  Win.color_menu(W.n)
  ImGui.Separator(ctx)
  if W.docked then
    if ImGui.MenuItem(ctx, 'Undock window') then W.dock_req = 0 end
  elseif ImGui.MenuItem(ctx, 'Dock window') then
    W.dock_req = tonumber(r.GetExtState(EXT, opt_key('dock', W.n))) or -1   -- last-used docker
  end
  if ImGui.MenuItem(ctx, 'Close window') then W.close_req = true end
  ImGui.EndPopup(ctx)
end

-- Menu items that don't close their menu when clicked (ReaImGui 0.9.3: the AutoClosePopups item flag).
-- If that flag isn't there (older ReaImGui), a selectable that keeps the menu open is used instead.
local Menu = {}
do
  local function const(name) local ok, v = pcall(function() return ImGui[name] end); return ok and v or nil end
  local AUTOCLOSE = const('ItemFlags_AutoClosePopups')
  local NOCLOSE = const('SelectableFlags_NoAutoClosePopups') or const('SelectableFlags_DontClosePopups')
  Menu.keep_open_begin = function()
    if AUTOCLOSE and ImGui.PushItemFlag then ImGui.PushItemFlag(ctx, AUTOCLOSE, false); return 'flag' end
    return NOCLOSE and 'selectable' or nil
  end
  Menu.keep_open_end = function(how) if how == 'flag' then ImGui.PopItemFlag(ctx) end end
  Menu.pad = function(label, how) return how == 'selectable' and ('     ' .. label) or label end
  Menu.check_item = function(label, checked, how)
    if how ~= 'selectable' then return ImGui.MenuItem(ctx, label, nil, checked) end
    -- a selectable that leaves the menu open, with the checkmark drawn in front (like a menu item's)
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

-- the options: right-click anywhere else
local function options_menu(W)
  if not ImGui.BeginPopup(ctx, 'options') then return end
  -- the whole menu stays open while you change things; clicking outside it closes it
  local keep = Menu.keep_open_begin()
  local function item(label, checked) return Menu.check_item(label, checked, keep) end
  local function submenu(label) return ImGui.BeginMenu(ctx, Menu.pad(label, keep)) end

  if submenu('Tracks to show') then
    if item('All tracks', S.filter == 'all') then set_opt('filter', 'all') end
    -- a fixed list, like the Floating Mixer: changing the selection afterwards doesn't change it
    if item('Show selected tracks', false) then List.from_selection(W); set_opt('filter', 'list') end
    if item('Record-armed tracks only', S.filter == 'armed') then set_opt('filter', 'armed') end
    ImGui.Separator(ctx)
    local m = r.GetMasterTrack(0)
    local inlist = S.filter == 'list'
    local function track_item(label, g)
      if item(label, inlist and List.has(W, g) ~= nil) then
        if not inlist then List.set(W, {}); inlist = true end
        List.toggle(W, g); set_opt('filter', 'list')
      end
    end
    track_item('MASTER', r.GetTrackGUID(m))
    for i = 0, r.CountTracks(0) - 1 do
      local t = r.GetTrack(0, i)
      if not hidden_track(t) then
        local g = r.GetTrackGUID(t)
        local _, nm = r.GetSetMediaTrackInfo_String(t, 'P_NAME', '', false)
        track_item((i + 1) .. ': ' .. nm .. '##' .. g, g)
      end
    end
    ImGui.EndMenu(ctx)
  end
  if item('Follow selected tracks', S.filter == 'follow') then set_opt('filter', 'follow') end
  if item('Clear list', false) then List.set(W, {}); set_opt('filter', 'list') end
  ImGui.Separator(ctx)
  if item('Skip tracks hidden in the mixer', S.skip_hidden == 1) then set_opt('skip_hidden', 1 - S.skip_hidden) end
  ImGui.Separator(ctx)
  if submenu('Strip width') then
    for _, k in ipairs({ 'narrow', 'normal', 'wide' }) do
      if item(k:sub(1, 1):upper() .. k:sub(2), S.width == k) then set_opt('width', k) end
    end
    ImGui.EndMenu(ctx)
  end
  if submenu('Peak hold') then
    for _, o in ipairs({ { 'Off', 0 }, { '1 second', 1 }, { '2 seconds', 2 }, { '5 seconds', 5 }, { 'Until reset', -1 } }) do
      if item(o[1], S.hold == o[2]) then set_opt('hold', o[2]) end
    end
    ImGui.EndMenu(ctx)
  end
  if submenu('Release') then
    for _, k in ipairs({ 'fast', 'medium', 'slow' }) do
      if item(k:sub(1, 1):upper() .. k:sub(2) .. ' (' .. RELEASE[k] .. ' dB/s)', S.release == k) then set_opt('release', k) end
    end
    ImGui.EndMenu(ctx)
  end
  if item('Show track names', S.names == 1) then set_opt('names', 1 - S.names) end
  if item('Show input selector', S.input ~= 'off') then set_opt('input', S.input == 'off' and 'number' or 'off') end
  Menu.keep_open_end(keep)
  ImGui.EndPopup(ctx)
end

-- the record input menu for the clicked selector (like the mixer's)
local function input_menu()
  if not ImGui.BeginPopup(ctx, 'input_menu') then return end
  local tr = D.menu_tr
  if not (tr and r.ValidatePtr2(0, tr, 'MediaTrack*')) then ImGui.CloseCurrentPopup(ctx); ImGui.EndPopup(ctx); return end
  local cur = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_RECINPUT'))
  local num, name = track_info(tr)
  ImGui.TextDisabled(ctx, 'Input for ' .. num .. ': ' .. name)
  ImGui.Separator(ctx)
  local function item(label, v)
    if ImGui.MenuItem(ctx, label, nil, cur == v) then
      r.Undo_BeginBlock()
      r.SetMediaTrackInfo_Value(tr, 'I_RECINPUT', v)
      r.Undo_EndBlock('Set track record input', -1)
    end
  end
  local n = r.GetNumAudioInputs()
  if ImGui.BeginMenu(ctx, 'Input: Mono') then
    for i = 0, n - 1 do item((i + 1) .. ': ' .. INP.chan_name(i) .. '##m' .. i, i) end
    ImGui.EndMenu(ctx)
  end
  if ImGui.BeginMenu(ctx, 'Input: Stereo') then
    for i = 0, n - 2 do
      item((i + 1) .. '/' .. (i + 2) .. ': ' .. INP.chan_name(i) .. ' / ' .. INP.chan_name(i + 1) .. '##s' .. i, 1024 + i)
    end
    ImGui.EndMenu(ctx)
  end
  if ImGui.BeginMenu(ctx, 'Input: MIDI') then
    item('All inputs (all channels)', 4096 + (63 << 5))
    for dev = 0, 63 do
      local ok, dn = r.GetMIDIInputName(dev, '')
      if ok and dn and dn ~= '' then item(dn .. ' (all channels)##d' .. dev, 4096 + (dev << 5)) end
    end
    item('Virtual MIDI keyboard (all channels)', 4096 + (62 << 5))
    ImGui.EndMenu(ctx)
  end
  ImGui.Separator(ctx)
  item('Input: None', -1)
  ImGui.EndPopup(ctx)
end

--------------------------------------------------------------------------------
-- Keyboard focus back to REAPER (needs js_ReaScriptAPI or SWS)
--------------------------------------------------------------------------------
local function keep_reaper_focus(focused)
  if not focused then D.refocus, D.no_refocus = false, false; return end
  local released = ImGui.IsMouseReleased(ctx, ImGui.MouseButton_Left) or ImGui.IsMouseReleased(ctx, ImGui.MouseButton_Right)
  if released then D.refocus = true end
  if D.no_refocus then                            -- the palette just opened: wait for this click to end
    D.refocus = false
    if released then D.no_refocus = false end
    return
  end
  if D.renaming then D.refocus = false; return end           -- typing a name keeps the keyboard
  if not D.refocus or ImGui.IsPopupOpen(ctx, '', ImGui.PopupFlags_AnyPopupId) then return end
  D.refocus = false
  local hwnd = r.GetMainHwnd()
  if r.JS_Window_SetFocus then r.JS_Window_SetFocus(hwnd) elseif r.BR_Win32_SetFocus then r.BR_Win32_SetFocus(hwnd) end
end

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------
local WFLAGS = ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_HorizontalScrollbar

local function draw_window(W, now)
  if W.close_req then W.close_req = nil; return false, false end      -- "Close window" from the menu
  W.S = W.S or win_settings(W.n)
  S = W.S
  D.win = W.n
  local tracks = bridge_tracks(W)
  local SW = WIDTHS[S.width] or 24
  ImGui.SetNextWindowSize(ctx, SCALE_W + 16 * SW + 8, 260, ImGui.Cond_FirstUseEver)
  do -- a new window opens near the middle of the screen, later ones a little offset
    local cx, cy = ImGui.Viewport_GetCenter(ImGui.GetMainViewport(ctx))
    local off = (W.n - 1) * 30
    ImGui.SetNextWindowPos(ctx, cx + off, cy + off, ImGui.Cond_FirstUseEver, 0.5, 0.5)
  end
  if W.dock_req then ImGui.SetNextWindowDockID(ctx, W.dock_req); W.dock_req = nil end
  local bg = Win.mixer_gray()
  local wcol = Win.color(W.n)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 4, 2)
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, bg)
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive, wcol)                -- title bar: the window's color
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBg, Win.dim(wcol, 0.55))       -- (dimmer when not focused)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, Win.text_on(wcol))
  local visible, open = ImGui.Begin(ctx, 'Meter Bridge ' .. W.n .. '###DanielMeterBridge' .. (W.n > 1 and W.n or ''), true, WFLAGS)
  ImGui.PopStyleColor(ctx, 4); ImGui.PopStyleVar(ctx)
  if not visible then return open, false end

  D.dl = ImGui.GetWindowDrawList(ctx)
  W.docked = ImGui.IsWindowDocked(ctx)
  if W.docked then
    local id = ImGui.GetWindowDockID(ctx)
    local key = opt_key('dock', W.n)
    if id < 0 and tostring(id) ~= r.GetExtState(EXT, key) then r.SetExtState(EXT, key, tostring(id), true) end
  end

  local ox, oy = ImGui.GetCursorScreenPos(ctx)
  local aw, ah = ImGui.GetContentRegionAvail(ctx)
  local n = #tracks
  -- as many rows as fit at full height (at least one), then enough columns for every strip;
  -- if they're wider than the window it scrolls sideways
  local sbar = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ScrollbarSize)
  local cols = math.max(1, math.floor((aw - SCALE_W) / SW))
  local rows = math.max(1, math.min(math.ceil(n / cols), math.floor(ah / ROW_FULL)))
  cols = math.max(1, math.ceil(n / rows))
  local content_w = SCALE_W + cols * SW
  if content_w > aw then ah = ah - sbar end      -- the horizontal scrollbar takes some height
  local rh = math.max(MIN_ROW_H, math.floor(ah / rows))
  D.lay = strip_layout(rh - 4)
  local sx = ox + ImGui.GetScrollX(ctx)              -- the scale stays at the left edge
  -- the dB-scale column shows the window's color (the only color you see when it's docked)
  local scale_txt = (wcol ~= bg) and ((Win.text_on(wcol) & ~0xFF) | 0xD0) or nil
  if n == 0 then
    local msg = (S.filter == 'armed' and 'No record-armed tracks.')
             or (S.filter == 'follow' and 'No selected tracks.')
             or (S.filter == 'list' and 'No tracks in the list.') or 'No tracks.'
    draw_scale(sx, oy, rh - 4, wcol, rh, scale_txt)
    ImGui.SetCursorScreenPos(ctx, ox + SCALE_W + 6, oy + 6)
    ImGui.TextDisabled(ctx, msg .. '  Right-click for options.')
  else
    D.clip_x = sx + SCALE_W
    for row = 0, rows - 1 do
      local y0 = oy + row * rh
      for c = 0, cols - 1 do
        local k = row * cols + c + 1
        local tr = tracks[k]
        if not tr then break end
        ImGui.PushID(ctx, r.GetTrackGUID(tr))
        draw_strip(tr, ox + SCALE_W + c * SW, y0, SW, rh - 4, now)
        ImGui.PopID(ctx)
      end
      draw_scale(sx, y0, rh - 4, wcol, rh, scale_txt)
    end
  end
  D.clip_x = nil
  -- + : a new window. Top of the dB column, level with the input selectors (only when they're shown)
  if D.lay.input then
    local bx1, by1, bx2, by2 = sx + 2, oy + 3, sx + SCALE_W - 2, oy + 3 + INPUT_H
    local hb = hit('##newwin', bx1, by1, bx2, by2, 'Open a new meter bridge window')
    rect(bx1, by1, bx2, by2, hb.hov and 0x00000080 or 0x00000055, 4)
    local pc = (wcol ~= bg) and Win.text_on(wcol) or 0xD0D0D0FF
    local cx, cy = math.floor((bx1 + bx2) / 2), math.floor((by1 + by2) / 2)
    rect(cx - 4, cy, cx + 5, cy + 1, pc)                     -- drawn, so it's centered at any font size
    rect(cx, cy - 4, cx + 1, cy + 5, pc)
    if hb.click then Win.new_req = true end
  end
  ImGui.SetCursorScreenPos(ctx, ox, oy)
  ImGui.Dummy(ctx, content_w, rows * rh - 4)     -- content size, so the window scrolls when strips don't fit

  -- right-click: the title bar or the dB column -> window menu; anywhere else -> options
  if ImGui.IsWindowHovered(ctx) and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) then
    local mx, my = ImGui.GetMousePos(ctx)
    ImGui.OpenPopup(ctx, (my < oy - 1 or mx < sx + SCALE_W) and 'win_menu' or 'options')
  end
  window_menu(W)
  options_menu(W)
  if D.open_input then D.open_input = nil; ImGui.OpenPopup(ctx, 'input_menu') end
  input_menu()

  local focused = ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows)
  if focused and not ImGui.IsAnyItemActive(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Space, false) then
    r.Main_OnCommand(40044, 0)    -- Transport: Play/stop
  end
  ImGui.End(ctx)
  return open, focused
end

local function loop()
  local now = r.time_precise()
  Theme.check()

  Win.load()
  if Win.new_req then Win.new_req = nil; Win.add() end

  ImGui.PushFont(ctx, font_ui)
  local closed, any_focus = {}, false
  for _, W in ipairs(Win.list) do
    local open, focused = draw_window(W, now)
    if not open then closed[W] = true end
    any_focus = any_focus or focused
  end
  ImGui.PopFont(ctx)
  keep_reaper_focus(any_focus)

  -- closing windows: the last one closing ends the script (and isn't reopened at the next startup)
  if next(closed) then
    local keep = {}
    for _, W in ipairs(Win.list) do if not closed[W] then keep[#keep + 1] = W end end
    if #keep == 0 then
      Sync.closed_by_user = true
      return
    end
    for W in pairs(closed) do Win.forget(W.n); if W.n > 1 then List.forget(W.n) end end
    Win.list = keep
    Win.save_list()
  end
  r.defer(loop)
end

r.defer(loop)
