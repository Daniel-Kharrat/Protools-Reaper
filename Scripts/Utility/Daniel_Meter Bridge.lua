-- @description Daniel_Meter Bridge
-- @version 1.6
-- @changelog
--   Meter look window (right-click > Meter look...), shared by all bridge windows:
--   - Bottom of the meter: -24 to -120 dB (was fixed at -60)
--   - Colour zones: where red, amber and light green start (red can start below 0 dB, not only the clip LED)
--   - LEDs: Auto (LED size + maximum, follows the height) or a fixed number. Replaces Meter resolution
--   - Mono tracks show one meter: tracks whose items are all mono, or (without items) a mono input.
--     The meter shows the louder of L / R, so a panned mono track still reads right
--   - Zone sizes: how much of the meter's height each colour zone takes (25-400 %)
--   - Continuous meter: a smooth bar instead of LEDs (same zones and sizes), peak hold as a thin line.
--     It rises at once and falls smoothly at REAPER's meter decay (120 dB/s); the LED meters keep
--     their own timing (Release)
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
--   - One meter per track channel (stereo, 5.1, 7.1...); mono tracks (mono items, or a mono input)
--     show a single meter
--   - Meter look window: bottom of the scale, colour zones, number of LEDs, mono tracks
--   - VCA lead tracks show the summed level of the tracks that follow them (REAPER shows no meter
--     for a VCA): an estimate from their peak meters (as there's no real bus)
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
--   - Drag a strip (meter, name or number bar) onto another: move the track in the project, like the
--     mixer (left half: before it, right half: after it; selected tracks move together)
--   - Spacers (REAPER's track spacers, the same as the mixer's) show as gaps; drag one onto a strip to
--     move it. Right-click: add / remove spacers before or after the selected tracks
--   - Drop a track on a spacer: left half puts it before the spacer, right half after it
--   - Double-click name: rename the track (Enter: keep, Esc: cancel)
--   - Double-click number bar: recolor the track with the Daniel_Color Palette script
--   - Click an input selector: change the track's record input
--   - Click a clip light: reset that track (Cmd/Ctrl-click: reset all)
--   - + (top of the dB column, level with the input selectors): open a new bridge window
--   - Heart (bottom of the dB column, level with the number bars): support the script on Ko-fi
--   - Right-click the title bar or the dB column: New window, Window color, Dock / Undock, Close window
--   - Right-click a meter: meter mode (peaks / RMS / LUFS, as in the mixer; selected tracks change together)
--   - Right-click anywhere else: options (tracks, width, peak hold, release, names, input selector,
--     Meter look...)
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
--
--   Support: ko-fi.com/danielkharrat

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
-- the Meter look window's fonts (the Auto Mixer Panel look: Helvetica Neue / Segoe UI / DejaVu Sans)
local LOOK_FONT = r.GetOS():find('Win') and 'Segoe UI'
               or ((r.GetOS():find('OSX') or r.GetOS():find('mac')) and 'Helvetica Neue') or 'DejaVu Sans'
local font_lk   = ImGui.CreateFont(LOOK_FONT, 13)
local font_lk_b = ImGui.CreateFont(LOOK_FONT, 13, ImGui.FontFlags_Bold)
local font_lk_s = ImGui.CreateFont(LOOK_FONT, 11)
ImGui.Attach(ctx, font_lk); ImGui.Attach(ctx, font_lk_b); ImGui.Attach(ctx, font_lk_s)

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
  -- Meter look (all windows): see the Meter look window
  m_floor = -60,         -- bottom of the meter (dB)
  m_red = 0,             -- red from (dB); 0 = only the clip LED is red
  m_amber = -6,          -- amber from (dB)
  m_light = -18,         -- light green from (dB); deep green below
  led_mode = 'auto',     -- 'auto' (LED size + maximum, follows the height) | 'fixed' (a number of LEDs)
  led_size = 7,          -- auto: one LED per this many pixels (gap included)
  led_max = 40,          -- auto: at most this many LEDs (the clip LED included)
  led_count = 30,        -- fixed: this many LEDs (the clip LED included); fewer when the meter is too short
  mono = 1,              -- mono tracks show one meter
  sz_red = 100, sz_amber = 100, sz_light = 100, sz_deep = 100,   -- zone sizes (% of the normal scale)
  continuous = 0,        -- 1 = a continuous bar instead of LEDs
}
local LOOK_KEYS = { 'm_floor', 'm_red', 'm_amber', 'm_light', 'led_mode', 'led_size', 'led_max', 'led_count', 'mono',
                    'sz_red', 'sz_amber', 'sz_light', 'sz_deep', 'continuous' }
-- view options are per window; window 1 uses the original names (its settings carry over), others '_2'...
local WIN_KEYS = { filter = true, skip_hidden = true, width = true, names = true, input = true, dock = true }
local function opt_key(k, n) return (n == 1 or not WIN_KEYS[k]) and k or (k .. '_' .. n) end
local function load_opt(k, n)
  local v, d = r.GetExtState(EXT, opt_key(k, n)), DEFAULTS[k]
  if v == '' or (k == 'release' and not ({ fast = 1, medium = 1, slow = 1 })[v]) then return d end
  if k == 'led_mode' and v ~= 'fixed' then return 'auto' end
  if type(d) == 'number' then return tonumber(v) or d end
  if k == 'filter' and v == 'selected' then return 'follow' end   -- (older name)
  if k == 'input' and v ~= 'off' then return 'number' end        -- (channel names were dropped)
  return v
end
for k in pairs(DEFAULTS) do if not WIN_KEYS[k] then G[k] = load_opt(k, 1) end end
-- the old Meter resolution (window 1) becomes the LED size and maximum
if r.GetExtState(EXT, 'led_size') == '' then
  local old = ({ low = { 10, 20 }, high = { 5, 60 }, max = { 5, 60 } })[r.GetExtState(EXT, 'res')]
  if old then G.led_size, G.led_max = old[1], old[2] end
end
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

local WIDTHS  = { narrow = 24, normal = 36, wide = 48 }   -- a stereo strip
-- strip width for n meters: each meter keeps the width it has in a stereo strip (narrow: 7 px),
-- so 6 meters make a strip about 3 times as wide as stereo. Mono and stereo stay the base width.
local function strip_width(n)
  local base = WIDTHS[S.width] or 24
  if n <= 2 then return base end
  local mw = (base - 10) / 2               -- 2 px strip inset + 6 px meter padding + 2 px gap, halved
  return math.floor(8 + n * mw + (n - 1) * 1 + 0.5)
end
-- dB per second. REAPER's own meter decay (Preferences > Track control panels) also applies:
-- the meter can't fall faster than that.
local RELEASE = { fast = 120, medium = 60, slow = 30 }
-- The continuous meter rises at once and falls smoothly (every frame) at REAPER's meter decay rate
-- (Preferences > Track control panels: meter decay; the same value as the Floating Mixer). No update
-- tick: stepping at REAPER's 12 Hz felt laggy here.
local REAPER_DECAY = 120

--------------------------------------------------------------------------------
-- Look
--------------------------------------------------------------------------------
-- The scale steps (dB, top to bottom): each step is one unit of meter height, so the scale is finer
-- near the top. SEG is these steps down to the bottom of the meter (Meter look), the bottom included.
local BASE_SEG = { 0, -1, -2, -3, -4, -6, -8, -10, -12, -15, -18, -21, -24, -27, -30, -35, -40, -45, -50, -60,
                   -70, -80, -90, -100, -110, -120 }
local SEG = {}
-- dB labels by priority: placed in this order wherever they don't overlap a label already placed
-- (built with the scale: the bottom of the meter comes second)
local LABEL_PRIO = { 0, 'floor', -18, -60, -6, -30, -12, -40, -3, -24, -80, -100, -120 }
local LABEL_ORDER = {}
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
-- The meter scale: unit 0..1 is the red clip LED, unit 1 is 0 dB, unit #SEG the bottom of the meter.
-- Every color zone keeps its place and height whatever the number of LEDs (the defaults: amber 0 to
-- -6 dB 1..6, light green -6 to -18 dB 6..11, deep green -18 to -60 dB 11..20). More LEDs split each
-- zone into more, smaller LEDs; fewer into bigger LEDs, so the dB labels stay in the same spots too.
local function db_to_u(t)
  if t >= SEG[1] then return 1 end
  for k = 1, #SEG - 1 do
    if t >= SEG[k + 1] then return k + (SEG[k] - t) / (SEG[k] - SEG[k + 1]) end
  end
  return #SEG
end
local function u_to_db(u)
  local k = math.floor(u)
  if k < 1 then return SEG[1] elseif k >= #SEG then return SEG[#SEG] end
  return SEG[k] - (u - k) * (SEG[k] - SEG[k + 1])
end
local ZONES = {}  -- top / bottom (units) and color of each zone below the red clip LED (Look.apply)
-- counts = LEDs in the amber, light green and deep green zones (+1 red clip LED)
local function seg_set(counts)
  local set = { t = {}, u0 = {}, u1 = {}, lit = {}, unlit = {} }
  local function add(t, u0, u1, c)
    local i = #set.t + 1
    set.t[i], set.u0[i], set.u1[i], set.lit[i], set.unlit[i] = t, u0, u1, c, dim(c, 0.16)
  end
  add(0, 0, 1, COL.red)
  local min_u = 99
  for z, zone in ipairs(ZONES) do
    local n, top, bot = counts[z], zone[1], zone[2]       -- (display units: zone sizes applied)
    local ntop, nbot = zone[4], zone[5]                     -- (scale units: for the dB)
    for j = 1, n do
      local u0, u1 = top + (bot - top) * (j - 1) / n, top + (bot - top) * j / n
      -- lights when the level reaches the LED's bottom edge
      add(u_to_db(ntop + (nbot - ntop) * j / n), u0, u1, zone[3])
    end
    min_u = math.min(min_u, (bot - top) / n)
  end
  set.min_u = min_u                            -- the smallest LED (the red one aside), for fitting
  return set
end
-- The number of LEDs (Meter look, all windows), the clip LED included:
-- Auto: one LED per led_size pixels (gap included), so a taller window shows more LEDs and a shorter
-- one fewer, bigger LEDs, up to led_max. Fixed: led_count LEDs, fewer when the meter is too short
-- for them (an LED needs 3 px). Always at least the clip LED + one per zone.
local function led_count(mh)
  local min_leds = 1 + #ZONES
  if G.led_mode == 'fixed' then
    return math.max(min_leds, math.min(G.led_count, math.floor(mh / 3)))
  end
  return clamp(math.floor(mh / math.max(2, G.led_size)), min_leds, math.max(min_leds, G.led_max))
end
local set_cache = {}
-- the LED set for a meter mh pixels tall: N LEDs (1 red + the rest shared out by zone size)
local function seg_for(mh)
  local n = led_count(mh) - 1                       -- LEDs below the red one, at least 1 per zone
  if set_cache[n] then return set_cache[n] end
  local total, counts, rem, used = 0, {}, {}, 0
  for _, z in ipairs(ZONES) do total = total + (z[2] - z[1]) end
  for i, z in ipairs(ZONES) do
    local exact = n * (z[2] - z[1]) / total
    counts[i] = math.max(1, math.floor(exact)); rem[i] = exact - math.floor(exact)
    used = used + counts[i]
  end
  while used < n do                                 -- the leftover LEDs go to the biggest remainders
    local best = 1
    for i = 2, #ZONES do if rem[i] > rem[best] then best = i end end
    counts[best], rem[best], used = counts[best] + 1, -1, used + 1
  end
  while used > n do                                 -- (only when a zone was raised to its minimum of 1)
    local big = 1
    for i = 2, #ZONES do if counts[i] > counts[big] then big = i end end
    counts[big], used = counts[big] - 1, used - 1
  end
  set_cache[n] = seg_set(counts)
  return set_cache[n]
end

-- Meter look: the settings shared by all windows (scale bottom, color zones, LEDs, mono tracks)
local Look = { open = false }
-- keeps the zones in order (0 >= red >= amber >= light green >= bottom); the setting just changed wins
function Look.order(k)
  G.m_floor = clamp(math.floor(G.m_floor), -120, -24)
  local fl = G.m_floor
  if k == 'm_red' then
    G.m_amber = math.min(G.m_amber, G.m_red); G.m_light = math.min(G.m_light, G.m_amber)
  elseif k == 'm_amber' then
    G.m_red = math.max(G.m_red, G.m_amber); G.m_light = math.min(G.m_light, G.m_amber)
  elseif k == 'm_light' then
    G.m_amber = math.max(G.m_amber, G.m_light); G.m_red = math.max(G.m_red, G.m_amber)
  end
  G.m_red   = clamp(G.m_red, fl, 0)
  G.m_amber = clamp(G.m_amber, fl, G.m_red)
  G.m_light = clamp(G.m_light, fl, G.m_amber)
end
-- rebuilds the scale, the labels and the zones from the settings
function Look.apply()
  Look.order()
  local fl = G.m_floor
  for i = #SEG, 1, -1 do SEG[i] = nil end
  for _, d in ipairs(BASE_SEG) do if d > fl then SEG[#SEG + 1] = d end end
  SEG[#SEG + 1] = fl
  for i = #LABEL_ORDER, 1, -1 do LABEL_ORDER[i] = nil end
  local seen = {}
  for _, t in ipairs(LABEL_PRIO) do
    if t == 'floor' then t = fl end
    if t >= fl and not seen[t] then seen[t] = true; LABEL_ORDER[#LABEL_ORDER + 1] = t end
  end
  for i = #ZONES, 1, -1 do ZONES[i] = nil end
  -- each zone: from the zone above down to db (empty zones are skipped), in scale units, then its size
  -- applied: the zones are stretched / shrunk by their size and fit back into the meter's height (the
  -- clip LED keeps its 1 unit). ZONES[i] = { top, bottom (display units), color, top, bottom (scale units) }
  local nat, top, sum = {}, 1, 0
  local function zone(db, col, size)
    local u = db_to_u(db)
    if u > top + 1e-6 then
      local f = clamp(size or 100, 25, 400) / 100
      nat[#nat + 1] = { top, u, col, f }; sum = sum + (u - top) * f; top = u
    end
  end
  zone(G.m_red, COL.red, G.sz_red); zone(G.m_amber, COL.amber, G.sz_amber)
  zone(G.m_light, COL.green_light, G.sz_light); zone(fl, COL.green_deep, G.sz_deep)
  local sc, d = (#SEG - 1) / math.max(1e-6, sum), 1
  for _, z in ipairs(nat) do
    local len = (z[2] - z[1]) * z[4] * sc
    ZONES[#ZONES + 1] = { d, d + len, z[3], z[1], z[2] }
    d = d + len
  end
  for k in pairs(set_cache) do set_cache[k] = nil end
end
-- scale units -> display units (where on the meter, with the zone sizes applied)
function Look.disp(u)
  if u <= 1 then return u end
  for _, z in ipairs(ZONES) do
    if u <= z[5] then return z[1] + (u - z[4]) / math.max(1e-6, z[5] - z[4]) * (z[2] - z[1]) end
  end
  return #SEG
end
Look.apply()

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

-- the track's channel count (2 if REAPER reports nothing)
local function n_chan(tr)
  local nch = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_NCHAN') or 2)
  return nch >= 1 and nch or 2
end
local function is_armed(tr)
  return tr ~= r.GetMasterTrack(0) and r.GetMediaTrackInfo_Value(tr, 'I_RECARM') == 1
end
local function mono_input(tr)
  local ri = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_RECINPUT'))
  return ri >= 0 and ri < 4096 and ri & (1024 | 2048) == 0
end
-- Mono tracks (Meter look > One meter for mono tracks): Mono.map[track] = true when all its items
-- play mono (the active take's source is mono, or its channel mode is mono downmix / left / right),
-- false when any item doesn't (or is MIDI), nil when it has no items. Rebuilt when the project changes.
local Mono = { map = {}, stamp = -1 }
function Mono.refresh()
  local proj = r.EnumProjects(-1)
  local sc = r.GetProjectStateChangeCount(proj)
  if proj == Mono.proj and sc == Mono.stamp then return end
  Mono.proj, Mono.stamp, Mono.map = proj, sc, {}
  for i = 0, r.CountMediaItems(0) - 1 do
    local it = r.GetMediaItem(0, i)
    local tr = r.GetMediaItem_Track(it)
    if Mono.map[tr] ~= false then
      local tk = r.GetActiveTake(it)
      if tk then
        local mono = false
        if not r.TakeIsMIDI(tk) then
          local src = r.GetMediaItemTake_Source(tk)
          local cm = math.floor(r.GetMediaItemTakeInfo_Value(tk, 'I_CHANMODE'))
          mono = (src and r.GetMediaSourceNumChannels(src) == 1) or (cm >= 2 and cm <= 4)
        end
        Mono.map[tr] = mono
      end
    end
  end
end
-- one meter per track channel. With Meter look > "One meter for mono tracks" on, a 2-channel track
-- shows one meter when it's mono: armed with a mono audio input; or not armed, with only mono items,
-- or no items and a mono input (not a folder parent, and no receives: those carry stereo from other
-- tracks). Off: always two meters.
local function n_peak_meters(tr)
  local nch = n_chan(tr)
  if nch ~= 2 then return nch end
  if tr == r.GetMasterTrack(0) then return 2 end
  if G.mono ~= 1 then return 2 end
  if is_armed(tr) then return mono_input(tr) and 1 or 2 end
  local m = Mono.map[tr]
  if m ~= nil then return m and 1 or 2 end
  if r.GetMediaTrackInfo_Value(tr, 'I_FOLDERDEPTH') == 1 or r.GetTrackNumSends(tr, -1) > 0 then return 2 end
  return mono_input(tr) and 1 or 2
end
-- a mono track that isn't armed: its output may be panned, so its one meter shows the louder of L / R
-- (meter channel -1). Armed: channel 1 is the input, as before.
local function mono_out(tr) return n_chan(tr) == 2 and not is_armed(tr) and n_peak_meters(tr) == 1 end
local function peak_lr(tr) return math.max(r.Track_GetPeakInfo(tr, 0) or 0, r.Track_GetPeakInfo(tr, 1) or 0) end
-- the peak-hold channels (clip light): both sides for a mono track that isn't armed
local function hold_chans(tr) return mono_out(tr) and 2 or n_peak_meters(tr) end
-- The track's meter mode, the same setting as REAPER's mixer (right-click a meter > the Meters options,
-- I_VUMODE): stereo peaks (2 meters, or 1 for a mono input as above), multichannel peaks (one per channel),
-- stereo RMS, or one combined RMS / LUFS-M / LUFS-S meter. RMS / loudness are read from channels
-- 1024 / 1025. Disabled: unlit meters. The master keeps peaks (its mode is in REAPER's master VU settings).
local function vu_mode(tr)
  if tr == r.GetMasterTrack(0) then return 0, false end
  local v = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_VUMODE'))
  return v & 30, (v & 1) ~= 0
end
--------------------------------------------------------------------------------
-- VCA meters. A VCA lead track (Track grouping: VCA lead) has no audio of its own, and REAPER shows
-- no meter for it. Here it meters the tracks that follow it, as if their audio went through it:
-- every follower (and the followers of a nested VCA that follows it) is added up. The script only
-- sees the tracks' peak meters, not their audio, so the sum is an estimate between a power sum
-- (right for unrelated tracks; real buses usually read higher) and the peaks added up (right for
-- tracks in phase; real buses read lower), set by VCA.BLEND below. The followers' meters are
-- post-fader, so moving the VCA moves its meter. A follower whose folder parent also follows the VCA
-- isn't counted twice (its audio is already in the parent).
--------------------------------------------------------------------------------
local VCA = { map = {}, stamp = -1, t = 0, cache = {} }   -- map[lead track] = its contributing tracks
-- where the estimate sits between the power sum (0) and the peaks added up (1), in dB:
-- 0.35 -> two equal tracks read +4 dB, four +8 dB, ten +13.5 dB. Lower = quieter VCA meters
VCA.BLEND = 0.15
-- the group bits (1-128 on REAPER 7, 1-64 before) of a track for one group setting
function VCA.groups(tr, name)
  local out = {}
  local words = {}
  if r.GetSetTrackGroupMembershipEx then
    for w = 0, 3 do words[w + 1] = r.GetSetTrackGroupMembershipEx(tr, name, w * 32, 0, 0) end
  else
    words[1] = r.GetSetTrackGroupMembership(tr, name, 0, 0)
    words[2] = r.GetSetTrackGroupMembershipHigh(tr, name, 0, 0)
  end
  for w, m in ipairs(words) do
    m = math.floor(m or 0) & 0xFFFFFFFF
    if m ~= 0 then for b = 0, 31 do if m & (1 << b) ~= 0 then out[#out + 1] = (w - 1) * 32 + b end end end
  end
  return out
end
-- rebuilt when the project changes (group settings included), and once a second anyway
function VCA.refresh(now)
  local proj = r.EnumProjects(-1)
  local sc = r.GetProjectStateChangeCount(proj)
  if proj == VCA.proj and sc == VCA.stamp and now - VCA.t < 1 then return end
  VCA.proj, VCA.stamp, VCA.t = proj, sc, now
  local lead, followers = {}, {}             -- lead[track] = its VCA groups; followers[group] = tracks
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if not hidden_track(tr) then
      local lg = VCA.groups(tr, 'VOLUME_VCA_LEAD')
      if #lg > 0 then lead[tr] = lg end
      for _, g in ipairs(VCA.groups(tr, 'VOLUME_VCA_FOLLOW')) do
        followers[g] = followers[g] or {}
        followers[g][#followers[g] + 1] = tr
      end
    end
  end
  local function collect(L, out, seen)
    for _, g in ipairs(lead[L]) do
      for _, f in ipairs(followers[g] or {}) do
        if not seen[f] then
          seen[f] = true; out[#out + 1] = f
          if lead[f] then collect(f, out, seen) end        -- a nested VCA: its followers count too
        end
      end
    end
  end
  VCA.map = {}
  for L in pairs(lead) do
    local out, seen = {}, { [L] = true }
    collect(L, out, seen)
    local list = {}
    for _, f in ipairs(out) do                 -- skip tracks already inside a counted folder parent
      local inside, cur = false, f
      while r.GetMediaTrackInfo_Value(cur, 'B_MAINSEND') == 1 do
        local p = r.GetParentTrack(cur)
        if not p then break end
        if seen[p] and p ~= L then inside = true; break end
        cur = p
      end
      if not inside then list[#list + 1] = f end
    end
    VCA.map[L] = list
  end
  VCA.cache = {}
end
-- a follower's peak channels (as its own meter shows them)
function VCA.peak_chans(f)
  local k = n_peak_meters(f)
  if vu_mode(f) ~= 2 and k > 2 then k = 2 end
  return k
end
-- the summed level (dB) for each of the VCA's n meters. A mono follower feeds every meter; the
-- channels of a wider follower go round the meters (1 -> L, 2 -> R, 3 -> L...)
function VCA.sum(tr, n, now)
  local c = VCA.cache[tr]
  if c and c.now == now and c.n == n then return c.db end
  local amp, pw = {}, {}                  -- per meter: the peaks added up, and their squares added up
  for i = 1, n do amp[i], pw[i] = 0, 0 end
  local function add(i, v) amp[i] = amp[i] + v; pw[i] = pw[i] + v * v end
  for _, f in ipairs(VCA.map[tr] or {}) do
    local k = VCA.peak_chans(f)
    if k == 1 then
      local v = mono_out(f) and peak_lr(f) or (r.Track_GetPeakInfo(f, 0) or 0)
      for i = 1, n do add(i, v) end
    else
      for ch = 0, k - 1 do add(ch % n + 1, r.Track_GetPeakInfo(f, ch) or 0) end
    end
  end
  -- between the power sum and the added peaks, VCA.BLEND of the way (in dB) toward the added peaks
  local db, w = {}, VCA.BLEND
  for i = 1, n do
    local rms = math.sqrt(pw[i])
    db[i] = (rms > 0) and val2db((amp[i] ^ w) * (rms ^ (1 - w))) or -150.0
  end
  VCA.cache[tr] = { now = now, n = n, db = db }
  return db
end
-- the highest peak hold (dB) of the VCA's tracks, for its clip light
function VCA.hold(tr)
  local h = -150
  for _, f in ipairs(VCA.map[tr] or {}) do
    local k = mono_out(f) and 2 or VCA.peak_chans(f)
    for ch = 0, k - 1 do h = math.max(h, r.Track_GetPeakHoldDB(f, ch, false) * 100) end
  end
  return h
end

-- the channels a strip's meters show (one meter each)
local function meter_chans(tr)
  -- a VCA: peaks, stereo (or one per channel in multichannel peaks mode)
  if VCA.map[tr] then
    local cnt = (vu_mode(tr) == 2) and n_chan(tr) or math.min(2, n_chan(tr))
    local t = {}
    for c = 0, cnt - 1 do t[#t + 1] = c end
    return t
  end
  local mode = vu_mode(tr)
  if mode == 4 then return { 1024, 1025 } end                  -- stereo RMS
  if mode ~= 0 and mode ~= 2 then return { 1024 } end          -- combined RMS / LUFS
  -- stereo peaks: REAPER only meters channels 1-2 then, so at most 2 meters (the master keeps all)
  local cnt = n_peak_meters(tr)
  if mode == 0 and cnt > 2 and tr ~= r.GetMasterTrack(0) then cnt = 2 end
  if cnt == 1 and mono_out(tr) then return { -1 } end         -- mono: the louder of L / R
  local t = {}
  for c = 0, cnt - 1 do t[#t + 1] = c end
  return t
end
local function n_meters(tr) return #meter_chans(tr) end

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
-- fingerprint of a zip: its size + the zip's own table of contents (central directory), which holds
-- the CRC32, size and date of every file inside. Same as the Floating Mixer's, so both scripts agree
-- on whether the shared cache is current and neither re-extracts what the other just extracted.
function Theme.zip_stamp(p)
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
  local h1, h2 = 5381, 0
  for i = 1, #cd do
    local b = cd:byte(i)
    h1 = (h1 * 33 + b) & 0xFFFFFFFF
    h2 = (h2 + b * i) & 0xFFFFFFFF
  end
  return string.format('%d-%d-%08x%08x', n, #cd, h1, h2)
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
  -- shared theme cache in Data/Daniel Kharrat (the Floating Mixer reads the same folder and uses the
  -- same stamp, so there's one copy; the folder is created if it isn't there)
  local dest = r.GetResourcePath() .. '/Data/Daniel Kharrat/theme_cache/' .. name
  local stamp = Theme.zip_stamp(zip)
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
-- Meter ballistics: instant rise, then a fall at the chosen rate (LED meters: Release; continuous:
-- REAPER_DECAY). Peak hold for both.
--------------------------------------------------------------------------------
local meters = {}
-- raw_db: a level given by the caller (a VCA's sum) instead of the track's own meter
local function meter(tr, ch, now, raw_db)
  local key = r.GetTrackGUID(tr) .. ':' .. ch
  local raw = raw_db or val2db(ch == -1 and peak_lr(tr) or r.Track_GetPeakInfo(tr, ch))
  local st = meters[key]
  if not st then st = { disp = raw, hold = raw, hold_t = now, t = now }; meters[key] = st end
  local dt, rel = now - st.t, RELEASE[S.release] or 20
  st.t = now
  if G.continuous == 1 then rel = REAPER_DECAY end           -- continuous: REAPER's decay, every frame
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

local function reset_track(tr, no_vca)
  -- a VCA's clip light comes from its tracks: reset them too
  if not no_vca and VCA.map[tr] then for _, f in ipairs(VCA.map[tr]) do reset_track(f, true) end end
  local g = r.GetTrackGUID(tr)
  for ch = 0, n_chan(tr) - 1 do
    r.Track_GetPeakHoldDB(tr, ch, true)
    local st = meters[g .. ':' .. ch]; if st then st.hold, st.hold_t = st.disp, 0 end
  end
  for _, ch in ipairs({ -1, 1024, 1025 }) do local st = meters[g .. ':' .. ch]; if st then st.hold, st.hold_t = st.disp, 0 end end
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
  return { click = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left), hov = hov, ok = true,
           act = ImGui.IsItemActive(ctx), released = ImGui.IsItemDeactivated(ctx),
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
  L.seg, L.mh = seg_for(mh), mh                    -- LEDs follow the height and the resolution
  return L
end
local function geom(y0, h)
  local ct = y0 + 3 + (D.lay.input and INPUT_H + 4 or 0)
  local mt = ct + CLIP_H + 2
  local mb = y0 + h - NUM_H - (D.lay.name and NAME_H or 0) - 3
  return ct, mt, mb
end
local function seg_y(i, mt, mb)
  local set, k = D.lay.seg, (mb - mt) / #SEG
  local a, b = mt + set.u0[i] * k, mt + set.u1[i] * k
  return a, b, b - a
end

-- the continuous meter (Meter look > Continuous meter): each zone a solid bar in its color, lit from the
-- level down; the clip area at the top lights at 0 dBFS; peak hold = a 2 px line in its zone's color
local function cont_meter(dl, x1, x2, mt, mb, disp, hold)
  local k = (mb - mt) / #SEG
  local fl = SEG[#SEG]
  local function y_of(db) return mt + Look.disp(db_to_u(db)) * k end
  local ly = (disp <= fl) and mb or y_of(disp)
  local g = (k >= 4) and 1 or 0
  ImGui.DrawList_AddRectFilled(dl, x1, mt, x2, math.floor(mt + k) - g, disp >= 0 and COL.red or dim(COL.red, 0.16))
  for _, z in ipairs(ZONES) do
    local a, b = math.floor(mt + z[1] * k), math.floor(mt + z[2] * k)
    ImGui.DrawList_AddRectFilled(dl, x1, a, x2, b, dim(z[3], 0.16))
    local top = math.max(a, math.floor(ly))
    if top < b then ImGui.DrawList_AddRectFilled(dl, x1, top, x2, b, z[3]) end
  end
  if hold > fl and hold < 0 and hold > disp + 0.5 then
    local hy = math.floor(y_of(hold))
    for _, z in ipairs(ZONES) do
      if hy <= mt + z[2] * k then ImGui.DrawList_AddRectFilled(dl, x1, hy - 1, x2, hy + 1, z[3]); break end
    end
  end
end

local function draw_scale(x, y0, h, bg, row_h, txt)
  local _, mt, mb = geom(y0, h)
  -- covers everything left of the strips, from the window's own edge (the padding included),
  -- so strips scrolled sideways don't show through
  local wx = ImGui.GetWindowPos(ctx)
  rect(math.min(wx, x), y0 - 2, x + SCALE_W, y0 + row_h, bg)
  local placed = {}
  local k = (mb - mt) / #SEG
  ImGui.PushFont(ctx, font_small)
  for _, t in ipairs(LABEL_ORDER) do
    do   -- at the same spot for every resolution (the middle of the Medium meter's LED for t)
      local cy = mt + Look.disp(db_to_u(t) - 0.5) * k
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

--------------------------------------------------------------------------------
-- Moving tracks and spacers (same as the Floating Mixer): drag a strip (meter, name or number bar)
-- onto another strip to move the track in the project. Left half: before that track, right half:
-- after it. If the dragged track is selected, all selected tracks move together (REAPER's behavior).
-- Spacers are REAPER's own track spacers (I_SPACER, shared with the mixer): shown as a gap; drag one
-- onto a strip to move it.
--------------------------------------------------------------------------------
-- click on a strip: select. Pressing on a track that's already selected (no modifier) keeps the
-- selection until the mouse is released, so several selected tracks can be dragged together; a
-- click without a drag then selects only that track, like REAPER's mixer
local function strip_click(h, tr)
  if h.click then
    D.dragged = false
    if r.IsTrackSelected(tr) and mods() == 0 then D.press_tr = tr else D.press_tr = nil; select_click(tr) end
  end
  if h.act and ImGui.IsMouseDragging(ctx, ImGui.MouseButton_Left) then D.dragged = true end
  if h.released and D.press_tr == tr then
    if not D.dragged then select_click(tr) end
    D.press_tr = nil
  end
end

local DnD = {}
do
  DnD.track = function(g)
    for i = 0, r.CountTracks(0) - 1 do
      local t = r.GetTrack(0, i)
      if r.GetTrackGUID(t) == g then return t end
    end
  end
  -- theme "drag and drop preview indicator" color (col_repos), like the Floating Mixer
  DnD.color = function()
    if r.GetThemeColor then
      local c = r.GetThemeColor('col_repos', 0)
      if c and c >= 0 then local R, G_, B = r.ColorFromNative(c); return rgba(R, G_, B) end
    end
    return 0x455C78FF
  end
  DnD.move_track = function(src, dst, after)
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
  -- the item just submitted (meter / name / number bar) of strip tr, whose rect is x1..x2, y1..y2:
  -- drag it to move the track, and drop tracks / spacers on it
  DnD.strip = function(h, tr, x1, x2, y1, y2)
    if not h.ok or tr == r.GetMasterTrack(0) then return end
    if ImGui.BeginDragDropSource(ctx) then
      ImGui.SetDragDropPayload(ctx, 'DTS_TRACK', r.GetTrackGUID(tr))
      local num, nm = track_info(tr)
      ImGui.Text(ctx, 'Move track ' .. num .. ': ' .. nm)
      ImGui.EndDragDropSource(ctx)
    end
    if not ImGui.BeginDragDropTarget(ctx) then return end
    local mx = ImGui.GetMousePos(ctx)
    local after = mx > (x1 + x2) / 2
    local fg = ImGui.GetForegroundDrawList(ctx)
    local lx = after and x2 or x1
    -- would dropping here actually change the order? (landing right next to where it already is = no)
    local function changes(src)
      if not src or src == tr then return false end
      local si = r.GetMediaTrackInfo_Value(src, 'IP_TRACKNUMBER')
      local ins = r.GetMediaTrackInfo_Value(tr, 'IP_TRACKNUMBER') + (after and 1 or 0)
      return ins ~= si and ins ~= si + 1
    end
    -- spacers: left half = spacer before this track, right half = before the next track in the project
    local function spacer_dest()
      if not after then return tr end
      return r.GetTrack(0, math.floor(r.GetMediaTrackInfo_Value(tr, 'IP_TRACKNUMBER')))
    end
    local rv, typ, payload = ImGui.GetDragDropPayload(ctx)
    if rv and typ == 'DTS_TRACK' and changes(DnD.track(payload)) then
      ImGui.DrawList_AddRectFilled(fg, lx - 2, y1, lx + 2, y2, DnD.color())
    end
    if rv and typ == 'DTS_SPACER' then
      local src, dst = DnD.track(payload), spacer_dest()
      if src and dst and dst ~= src and r.GetMediaTrackInfo_Value(dst, 'I_SPACER') ~= 1 then
        ImGui.DrawList_AddRectFilled(fg, lx - 2, y1, lx + 2, y2, DnD.color())
      end
    end
    local oks, sdata = ImGui.AcceptDragDropPayload(ctx, 'DTS_SPACER', ImGui.DragDropFlags_AcceptNoDrawDefaultRect)
    if oks and sdata then
      local src, dst = DnD.track(sdata), spacer_dest()
      if src and dst and dst ~= src and r.GetMediaTrackInfo_Value(dst, 'I_SPACER') ~= 1 then
        r.Undo_BeginBlock()
        r.SetMediaTrackInfo_Value(src, 'I_SPACER', 0)
        r.SetMediaTrackInfo_Value(dst, 'I_SPACER', 1)
        r.TrackList_AdjustWindows(false)
        r.Undo_EndBlock('Move spacer', -1)
      end
    end
    local ok, data = ImGui.AcceptDragDropPayload(ctx, 'DTS_TRACK', ImGui.DragDropFlags_AcceptNoDrawDefaultRect)
    if ok and data then
      local src = DnD.track(data)
      if changes(src) then DnD.move_track(src, tr, after) end
    end
    ImGui.EndDragDropTarget(ctx)
  end
  -- a spacer: the window background as a gap; held = lighter gray, like REAPER's; drag it to move it
  DnD.spacer = function(tr, x1, y1, x2, y2)
    local h = hit('##spacer', x1, y1, x2, y2, 'Spacer\nDrag onto a strip: move it\nDrop a track on its left / right half: before / after the spacer')
    if not h.ok then return end
    if h.act then rect(x1, y1, x2, y2, 0x525252FF) end
    if ImGui.BeginDragDropSource(ctx) then
      ImGui.SetDragDropPayload(ctx, 'DTS_SPACER', r.GetTrackGUID(tr))
      ImGui.Text(ctx, 'Move spacer')
      ImGui.EndDragDropSource(ctx)
    end
    -- drop a track on the spacer: left half = before the spacer, right half = after it
    if ImGui.BeginDragDropTarget(ctx) then
      local mx = ImGui.GetMousePos(ctx)
      local after = mx > (x1 + x2) / 2
      local rv, typ = ImGui.GetDragDropPayload(ctx)
      if rv and typ == 'DTS_TRACK' then
        local lx = after and x2 or x1
        ImGui.DrawList_AddRectFilled(ImGui.GetForegroundDrawList(ctx), lx - 2, y1, lx + 2, y2, DnD.color())
      end
      local ok, data = ImGui.AcceptDragDropPayload(ctx, 'DTS_TRACK', ImGui.DragDropFlags_AcceptNoDrawDefaultRect)
      local src = ok and data and DnD.track(data)
      if src and r.ValidatePtr2(0, tr, 'MediaTrack*') then DnD.move_to_spacer(src, tr, after) end
      ImGui.EndDragDropTarget(ctx)
    end
  end
  -- move the dragged track (or the selected tracks, if it's one of them) next to the spacer that sits
  -- before track sp: placed where sp is, then the spacer goes after them (before) or before them (after)
  DnD.move_to_spacer = function(src, sp, after)
    local moved = {}
    if r.IsTrackSelected(src) then
      for i = 0, r.CountSelectedTracks(0) - 1 do moved[r.GetSelectedTrack(0, i)] = true end
    else
      moved[src] = true
    end
    -- the first track at or after the spacer that isn't moving: the tracks go in before it
    local anchor
    for i = math.floor(r.GetMediaTrackInfo_Value(sp, 'IP_TRACKNUMBER')) - 1, r.CountTracks(0) - 1 do
      local t = r.GetTrack(0, i)
      if not moved[t] then anchor = t; break end
    end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    r.SetMediaTrackInfo_Value(sp, 'I_SPACER', 0)
    if anchor then DnD.move_track(src, anchor, false)
    else DnD.move_track(src, r.GetTrack(0, r.CountTracks(0) - 1), true) end
    local first                                   -- the first moved track, where it is now
    for i = 0, r.CountTracks(0) - 1 do
      local t = r.GetTrack(0, i)
      if moved[t] then first = t; break end
    end
    if after then
      if first then r.SetMediaTrackInfo_Value(first, 'I_SPACER', 1) end
    elseif anchor then
      r.SetMediaTrackInfo_Value(anchor, 'I_SPACER', 1)
    end
    r.TrackList_AdjustWindows(false)
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock('Move tracks', -1)
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
  local chans = meter_chans(tr)
  local n = #chans
  local _, vu_off = vu_mode(tr)
  local mx1, mx2 = x1 + 3, x2 - 3
  -- gap between meters: 2 px for stereo, 1 px for more channels (the strip is widened for them)
  local gap = (n <= 2) and 2 or 1
  local cw = (mx2 - mx1 - gap * (n - 1)) / n
  local vca = VCA.map[tr]
  local vsum = vca and VCA.sum(tr, n, now)                   -- a VCA: its followers, summed
  for c = 0, n - 1 do
    local disp, hold = meter(tr, chans[c + 1], now, vsum and vsum[c + 1])
    if vu_off and not vca then disp, hold = -150, -150 end   -- meter disabled in REAPER: unlit
    local cx1 = math.floor(mx1 + c * (cw + gap))
    local cx2 = math.floor(mx1 + c * (cw + gap) + cw)
    if cx2 <= cx1 then cx2 = cx1 + 1 end
    rect(cx1, mt, cx2, mb, COL.meter_bg)
    if G.continuous == 1 then
      cont_meter(D.dl, cx1, cx2, mt, mb, disp, hold)
    else
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
  end

  local hm = hit('##meter', x1, ct + CLIP_H + 2, x2, mb + 2)
  strip_click(hm, tr)
  -- right-click in the middle half of the meter: the meter mode menu (see the window); the top and
  -- bottom quarters open the options menu, like empty space
  if hm.rclick and not is_master then
    local _, my = ImGui.GetMousePos(ctx)
    local q = (mb - mt) / 4
    if my >= mt + q and my <= mb - q then D.meter_menu_tr = tr end
  end
  DnD.strip(hm, tr, x1, x2, y0, y0 + h)

  -- clip light on top (latched: REAPER's peak hold went above 0 dBFS). Click: reset
  local hold_db = -150
  if vca then
    hold_db = VCA.hold(tr)                                   -- a VCA: any of its tracks clipped
  else
    local pk = hold_chans(tr)                                -- the clip light always follows the peaks
    for c = 0, pk - 1 do hold_db = math.max(hold_db, r.Track_GetPeakHoldDB(tr, c, false) * 100) end
  end
  local clipped = hold_db > 0
  -- REAPER reset its peaks (on record start if it's set to, Cmd/Ctrl-click in its mixer...): drop our
  -- held LEDs for this track too
  do
    local g = r.GetTrackGUID(tr)
    D.rhold = D.rhold or {}
    local prev = D.rhold[g]
    if prev and hold_db < prev - 0.5 then
      for _, ch in ipairs(chans) do local st = meters[g .. ':' .. ch]; if st then st.hold, st.hold_t = st.disp, 0 end end
    end
    D.rhold[g] = hold_db
  end
  rect(mx1, ct, mx2, ct + CLIP_H, clipped and COL.red or COL.clip_off)
  local hr = hit('##clip', x1, ct - 2, x2, ct + CLIP_H + 2,
    'Max peak ' .. fmt_peak(hold_db) .. ' dB\nClick: reset  |  Cmd/Ctrl-click: reset all')
  if hr.click then if is_ctrl() or is_alt() then reset_all() else reset_track(tr) end end

  local tip = num .. ': ' .. name .. '\nClick: select (Cmd/Ctrl: toggle, Shift: range)'
    .. (vca and ('\nVCA: meter = the sum of its ' .. #vca .. ' track' .. (#vca == 1 and '' or 's')) or '')
    .. (is_master and '' or '\nDrag: move the track')

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
      strip_click(hn, tr)
      DnD.strip(hn, tr, x1, x2, y0, y0 + h)
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
  strip_click(hb, tr)
  DnD.strip(hb, tr, x1, x2, y0, y0 + h)
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
-- support link (Ko-fi): the heart at the bottom of the dB column and the window menu item
local Support = { url = 'https://ko-fi.com/danielkharrat' }
Support.open = function()
  local url = Support.url
  if r.CF_ShellExecute then r.CF_ShellExecute(url)                       -- SWS
  elseif r.GetOS():find('Win') then os.execute('start "" "' .. url .. '"')
  elseif r.GetOS():find('OSX') or r.GetOS():find('mac') then os.execute('open "' .. url .. '"')
  else os.execute('xdg-open "' .. url .. '" &') end
end
-- a small button like the + : translucent dark, heart in the column's text colour
Support.button = function(x1, y1, x2, y2, col)
  local hb = hit('##support', x1, y1, x2, y2, 'Support the Meter Bridge: buy me a coffee\nko-fi.com/danielkharrat')
  rect(x1, y1, x2, y2, hb.hov and 0x00000080 or 0x00000055, 4)
  local cx, cy = (x1 + x2) / 2, (y1 + y2) / 2 - 0.5
  ImGui.DrawList_AddCircleFilled(D.dl, cx - 2.2, cy - 1.0, 2.5, col)
  ImGui.DrawList_AddCircleFilled(D.dl, cx + 2.2, cy - 1.0, 2.5, col)
  ImGui.DrawList_AddTriangleFilled(D.dl, cx - 4.6, cy - 0.2, cx + 4.6, cy - 0.2, cx, cy + 4.6, col)
  if hb.click then Support.open() end
end

local function window_menu(W)
  if not ImGui.BeginPopup(ctx, 'win_menu') then return end
  if ImGui.MenuItem(ctx, 'New window') then Win.new_req = true end
  Win.color_menu(W.n)
  if ImGui.MenuItem(ctx, 'Meter look...', nil, Look.open) then Look.open = true end
  ImGui.Separator(ctx)
  if W.docked then
    if ImGui.MenuItem(ctx, 'Undock window') then W.dock_req = 0 end
  elseif ImGui.MenuItem(ctx, 'Dock window') then
    W.dock_req = tonumber(r.GetExtState(EXT, opt_key('dock', W.n))) or -1   -- last-used docker
  end
  if ImGui.MenuItem(ctx, 'Close window') then W.close_req = true end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, 'Support (Ko-fi)') then Support.open() end
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
local METER_MODES = {
  { 'Stereo peaks', 0 }, { 'Multichannel peaks', 2 }, { 'Stereo RMS', 4 }, { 'Combined RMS', 8 },
  { 'LUFS-M', 12 }, { 'LUFS-S (readout=max)', 16 }, { 'LUFS-S (readout=current)', 20 },
}
-- set the meter mode (I_VUMODE mode bits) of every track in a list, as one undo step
local function set_meter_mode(list, mode)
  r.Undo_BeginBlock()
  for _, t in ipairs(list) do
    local v = math.floor(r.GetMediaTrackInfo_Value(t, 'I_VUMODE'))
    r.SetMediaTrackInfo_Value(t, 'I_VUMODE', (v & ~30) | mode)
  end
  r.Undo_EndBlock('Set meter mode', -1)
end

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
  -- scale, color zones, LEDs, mono tracks: the Meter look window (all bridge windows)
  if item('Meter look...', Look.open) then Look.open = true; ImGui.CloseCurrentPopup(ctx) end
  -- the meter mode of every track in this window at once (the master keeps peaks)
  if submenu('Meter mode (all tracks in window)') then
    local list, common = {}, nil
    for _, t in ipairs(bridge_tracks(W)) do
      if t ~= r.GetMasterTrack(0) then
        list[#list + 1] = t
        local m = math.floor(r.GetMediaTrackInfo_Value(t, 'I_VUMODE')) & 30
        if common == nil then common = m elseif common ~= m then common = false end
      end
    end
    for _, m in ipairs(METER_MODES) do
      if item(m[1], common == m[2]) and #list > 0 then set_meter_mode(list, m[2]) end
    end
    ImGui.EndMenu(ctx)
  end
  -- (the continuous meter falls at REAPER's meter decay, so Release is for the LED meters only)
  local led = G.continuous ~= 1
  if ImGui.BeginMenu(ctx, Menu.pad(led and 'Release' or 'Release (LED meters only)', keep), led) then
    for _, k in ipairs({ 'fast', 'medium', 'slow' }) do
      if item(k:sub(1, 1):upper() .. k:sub(2) .. ' (' .. RELEASE[k] .. ' dB/s)', S.release == k) then set_opt('release', k) end
    end
    ImGui.EndMenu(ctx)
  end
  if item('Show track names', S.names == 1) then set_opt('names', 1 - S.names) end
  if item('Show input selector', S.input ~= 'off') then set_opt('input', S.input == 'off' and 'number' or 'off') end
  Menu.keep_open_end(keep)
  -- spacers before / after the selected tracks (REAPER's track spacers, the same as in the mixer).
  -- Each run of neighbouring selected tracks gets one spacer before it / after it.
  do
    local before, after = {}, {}
    local nt = r.CountTracks(0)
    for i = 0, nt - 1 do
      local t = r.GetTrack(0, i)
      if r.IsTrackSelected(t) then
        if i == 0 or not r.IsTrackSelected(r.GetTrack(0, i - 1)) then before[#before + 1] = t end
        local nx = (i + 1 < nt) and r.GetTrack(0, i + 1) or nil
        if nx and not r.IsTrackSelected(nx) then after[#after + 1] = nx end
      end
    end
    local function spacer_item(what, list)
      local all = #list > 0
      for _, t in ipairs(list) do if r.GetMediaTrackInfo_Value(t, 'I_SPACER') ~= 1 then all = false; break end end
      local label = (all and 'Remove spacer ' or 'Add spacer ') .. what .. ' selected tracks'
      if ImGui.MenuItem(ctx, label, nil, false, #list > 0) then
        r.Undo_BeginBlock()
        for _, t in ipairs(list) do r.SetMediaTrackInfo_Value(t, 'I_SPACER', all and 0 or 1) end
        r.TrackList_AdjustWindows(false)
        r.Undo_EndBlock(all and 'Remove spacer' or 'Add spacer', -1)
      end
    end
    ImGui.Separator(ctx)
    spacer_item('before', before)
    spacer_item('after', after)
  end
  ImGui.EndPopup(ctx)
end

-- The meter mode menu (right-click a meter): the same modes as REAPER's mixer meter menu, stored in the
-- track's I_VUMODE, so the mixer and the Floating Mixer follow too. Bits other than the mode and the
-- LUFS option are left as they are. If the clicked track is selected, all selected tracks change.
local function meter_menu(W)
  if not ImGui.BeginPopup(ctx, 'meter_menu') then return end
  local tr = W.meter_tr
  if not (tr and r.ValidatePtr2(0, tr, 'MediaTrack*')) then ImGui.CloseCurrentPopup(ctx); ImGui.EndPopup(ctx); return end
  local cur = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_VUMODE'))
  local function targets()
    local t = {}
    if r.IsTrackSelected(tr) then
      for i = 0, r.CountSelectedTracks(0) - 1 do t[#t + 1] = r.GetSelectedTrack(0, i) end
    else
      t[1] = tr
    end
    return t
  end
  local function apply(fn, undo)   -- (the LUFS option)
    r.Undo_BeginBlock()
    for _, t in ipairs(targets()) do
      local v = math.floor(r.GetMediaTrackInfo_Value(t, 'I_VUMODE'))
      r.SetMediaTrackInfo_Value(t, 'I_VUMODE', fn(v))
    end
    r.Undo_EndBlock(undo, -1)
  end
  for _, m in ipairs(METER_MODES) do
    if ImGui.MenuItem(ctx, m[1], nil, (cur & 30) == m[2]) then
      set_meter_mode(targets(), m[2])
    end
  end
  ImGui.Separator(ctx)
  local lufs12 = (cur & 32) ~= 0
  if ImGui.MenuItem(ctx, 'LUFS measures first two channels only (ignore sidechain)', nil, lufs12) then
    apply(function(v) return lufs12 and (v & ~32) or (v | 32) end, 'Set LUFS channels')
  end
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
  -- multichannel input (tracks with more than 2 channels): as many inputs as the track has channels,
  -- starting at the chosen input (REAPER's 2048 flag: multichannel, using the track's channel count)
  local nch = math.floor(r.GetMediaTrackInfo_Value(tr, 'I_NCHAN'))
  if nch > 2 and nch <= n and ImGui.BeginMenu(ctx, 'Input: ' .. nch .. ' channels') then
    for i = 0, n - nch do
      item((i + 1) .. '-' .. (i + nch) .. ': ' .. INP.chan_name(i) .. ' ... ' .. INP.chan_name(i + nch - 1) .. '##mc' .. i, 2048 + i)
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
-- Meter look window: the meter settings shared by all bridge windows. Daniel's Apple-style house style,
-- dark (macOS settings / Finder vibe): plain window, soft grey rounded groups with a hairline edge,
-- Apple sliders with a value readout (click it to type a value), a segmented control, a switch,
-- notes behind small (i) buttons. Changes show right away; they're saved when a control is let go.
--------------------------------------------------------------------------------
do
  local C = {
    win = 0x1E1E20FF, group = 0x262629FF, hair = 0xFFFFFF14, text = 0xFFFFFFD9, text2 = 0xEBEBF599,
    accent = 0x2F6FD0FF, fill = 0x7878801F, fill_hov = 0x7878802E, track = 0x7878803D, seg_on = 0x636366FF,
    sw_off = 0x78788052, knob = 0xF5F5F7FF, shadow = 0x00000059, well = 0x161618FF, popup = 0x2C2C2EF7,
  }
  -- GW = the settings column's width: it follows the window width (at least MIN_GW)
  local GW, ROW_H, LABEL_W, VAL_W, GAP, PREV_W, MIN_GW = 380, 36, 132, 72, 18, 112, 380
  local dl                                                  -- the window's draw list (this frame)

  Look.save = function()
    for _, k in ipairs(LOOK_KEYS) do r.SetExtState(EXT, k, tostring(G[k]), true) end
  end
  Look.set = function(k, v)
    if G[k] == v then return end
    G[k] = v
    Look.apply()
  end
  local function set_zone(k, v) G[k] = v; Look.order(k); Look.apply() end   -- the zone just moved wins

  -- text with its vertical centre at cy; returns its width
  local function text_at(font, x, cy, col, s)
    ImGui.PushFont(ctx, font)
    local w, h = ImGui.CalcTextSize(ctx, s)
    ImGui.DrawList_AddText(dl, math.floor(x), math.floor(cy - h / 2), col, s)
    ImGui.PopFont(ctx)
    return w
  end
  local function text_width(font, s) ImGui.PushFont(ctx, font); local w = ImGui.CalcTextSize(ctx, s); ImGui.PopFont(ctx); return w end
  local function button(id, x1, y1, x2, y2)
    ImGui.SetCursorScreenPos(ctx, x1, y1)
    ImGui.InvisibleButton(ctx, id, math.max(1, x2 - x1), math.max(1, y2 - y1))
    return ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left), ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  end

  -- a small circular (i) button that opens a popover with the note
  local function info(id, x, cy, str)
    local clicked, hov = button('##i' .. id, x - 9, cy - 9, x + 9, cy + 9)
    if clicked then ImGui.OpenPopup(ctx, '##pop' .. id) end
    local col = hov and C.text or C.text2
    ImGui.DrawList_AddCircle(dl, x, cy, 7.5, col, 24, 1.2)
    ImGui.DrawList_AddCircleFilled(dl, x, cy - 3.2, 1.1, col)   -- drawn, so it's centred on every OS
    ImGui.DrawList_AddRectFilled(dl, x - 0.8, cy - 1.2, x + 0.8, cy + 4, col)
    if ImGui.BeginPopup(ctx, '##pop' .. id) then
      ImGui.PushFont(ctx, font_lk)
      ImGui.PushTextWrapPos(ctx, 260)
      ImGui.TextColored(ctx, C.text, str)
      ImGui.PopTextWrapPos(ctx)
      ImGui.PopFont(ctx)
      ImGui.EndPopup(ctx)
    end
  end

  -- a group: bold header (with an optional (i)), then a rounded area of n rows with inset separators.
  -- Returns the top of the rows.
  local function group(x, y, title, n, note, id)
    text_at(font_lk_b, x + 4, y + 9, C.text, title)
    if note then info(id, x + GW - 12, y + 9, note) end
    local ty, h = y + 24, n * ROW_H
    local rnd = n == 1 and 14 or 20
    ImGui.DrawList_AddRectFilled(dl, x, ty, x + GW, ty + h, C.group, rnd)
    ImGui.DrawList_AddRect(dl, x + 0.5, ty + 0.5, x + GW - 0.5, ty + h - 0.5, C.hair, rnd, 0, 1)
    for i = 1, n - 1 do
      ImGui.DrawList_AddLine(dl, x + 14, ty + i * ROW_H, x + GW - 14, ty + i * ROW_H, C.hair, 1)
    end
    return ty
  end

  -- a slider row: label, Apple slider (filled track, lozenge thumb), value readout. Drag to
  -- change; click the readout to type a value (Enter: keep, Esc: cancel)
  local function slider(x, y, label, k, lo, hi, fmt, zone)
    local cy = y + ROW_H / 2
    text_at(font_lk, x + 14, cy, C.text, label)
    local vx2 = x + GW - 14
    local vx1 = vx2 - VAL_W
    local tx1, tx2 = x + LABEL_W, vx1 - 18
    local v = G[k]
    local _, hov, act = button('##s' .. k, tx1 - 10, y, tx2 + 10, y + ROW_H)
    local nv = v
    if act then
      local mx = ImGui.GetMousePos(ctx)
      nv = lo + math.floor(clamp((mx - tx1) / (tx2 - tx1), 0, 1) * (hi - lo) + 0.5)
    end                                                       -- (no mouse wheel: it scrolls the window)
    if nv ~= v then
      if zone then set_zone(k, nv) else Look.set(k, nv) end
      v = G[k]
    end
    if ImGui.IsItemDeactivated(ctx) then Look.save() end
    local tx = tx1 + (v - lo) / math.max(1, hi - lo) * (tx2 - tx1)
    ImGui.DrawList_AddRectFilled(dl, tx1, cy - 2, tx2, cy + 2, C.track, 2)
    ImGui.DrawList_AddRectFilled(dl, tx1, cy - 2, tx, cy + 2, C.accent, 2)
    ImGui.DrawList_AddRectFilled(dl, tx - 10, cy - 6, tx + 10, cy + 8, C.shadow, 7)
    ImGui.DrawList_AddRectFilled(dl, tx - 10, cy - 7, tx + 10, cy + 7, (act or hov) and 0xFFFFFFFF or C.knob, 7)
    -- value readout
    if Look.edit == k then
      ImGui.SetCursorScreenPos(ctx, vx1, cy - 11)
      ImGui.SetNextItemWidth(ctx, VAL_W)
      if Look.edit_focus then ImGui.SetKeyboardFocusHere(ctx); Look.edit_focus = false end
      local enter, buf = ImGui.InputText(ctx, '##e' .. k, Look.buf,
        ImGui.InputTextFlags_CharsDecimal | ImGui.InputTextFlags_EnterReturnsTrue | ImGui.InputTextFlags_AutoSelectAll)
      Look.buf = buf
      if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
        Look.edit = nil
      elseif enter or ImGui.IsItemDeactivated(ctx) then
        local n = tonumber(buf)
        if n then
          n = clamp(math.floor(n + 0.5), lo, hi)
          if zone then set_zone(k, n) else Look.set(k, n) end
          Look.save()
        end
        Look.edit = nil
      end
    else
      local clicked, vh = button('##v' .. k, vx1, cy - 11, vx2, cy + 11)
      if vh and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayNormal) then ImGui.SetTooltip(ctx, 'Click to type a value') end
      ImGui.DrawList_AddRectFilled(dl, vx1, cy - 11, vx2, cy + 11, vh and C.fill_hov or C.fill, 11)
      local s = fmt(v)
      text_at(font_lk, (vx1 + vx2 - text_width(font_lk, s)) / 2, cy, C.text, s)
      if clicked then Look.edit, Look.buf, Look.edit_focus = k, tostring(v), true end
    end
  end

  -- a segmented control row (equal segments; the chosen one a lighter grey, like macOS dark mode)
  local function segmented(x, y, label, k, opts)
    local cy = y + ROW_H / 2
    text_at(font_lk, x + 14, cy, C.text, label)
    local sx1, sx2 = x + LABEL_W, x + GW - 14
    ImGui.DrawList_AddRectFilled(dl, sx1, cy - 12, sx2, cy + 12, C.track, 12)
    local sw = (sx2 - sx1) / #opts
    for i, o in ipairs(opts) do
      local a = sx1 + (i - 1) * sw
      local clicked, hov = button('##g' .. k .. i, a, cy - 12, a + sw, cy + 12)
      local on = G[k] == o[2]
      if on then ImGui.DrawList_AddRectFilled(dl, a + 2, cy - 10, a + sw - 2, cy + 10, C.seg_on, 10) end
      text_at(font_lk, a + (sw - text_width(font_lk, o[1])) / 2, cy, (on or hov) and C.text or C.text2, o[1])
      if clicked and not on then Look.set(k, o[2]); Look.save() end
    end
  end

  -- a switch row (on = accent)
  local function switch(x, y, label, k)
    local cy = y + ROW_H / 2
    text_at(font_lk, x + 14, cy, C.text, label)
    local sx2 = x + GW - 14
    local sx1 = sx2 - 38
    local clicked = button('##w' .. k, sx1, cy - 11, sx2, cy + 11)
    local on = G[k] == 1
    ImGui.DrawList_AddRectFilled(dl, sx1, cy - 11, sx2, cy + 11, on and C.accent or C.sw_off, 11)
    local kx = on and (sx2 - 11) or (sx1 + 11)
    ImGui.DrawList_AddCircleFilled(dl, kx, cy + 1, 9.5, C.shadow)
    ImGui.DrawList_AddCircleFilled(dl, kx, cy, 9, C.knob)
    if clicked then Look.set(k, on and 0 or 1); Look.save() end
  end

  -- a read-only row: label left, value right in the secondary color
  local function readout(x, y, label, value)
    local cy = y + ROW_H / 2
    text_at(font_lk, x + 14, cy, C.text, label)
    text_at(font_lk, x + GW - 14 - text_width(font_lk, value), cy, C.text2, value)
  end

  -- a secondary capsule button
  local function capsule(id, x, y, label)
    local w = text_width(font_lk, label) + 28
    local clicked, hov = button(id, x, y, x + w, y + 28)
    ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + 28, hov and C.fill_hov or C.fill, 14)
    text_at(font_lk, x + 14, y + 14, C.text, label)
    return clicked
  end

  -- a meter drawn with the current settings, all LEDs lit, with its dB labels
  local function preview(x, y, w, h)
    ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.group, 20)
    ImGui.DrawList_AddRect(dl, x + 0.5, y + 0.5, x + w - 0.5, y + h - 0.5, C.hair, 20, 0, 1)
    local mw, lw = 18, 30
    local mx1 = math.floor(x + (w - (lw + 8 + mw)) / 2 + lw + 8)
    local mt, mb = y + 22, y + h - 28
    ImGui.DrawList_AddRectFilled(dl, mx1 - 4, mt - 4, mx1 + mw + 4, mb + 4, C.well, 6)
    local set = seg_for(mb - mt)
    local k = (mb - mt) / #SEG
    if G.continuous == 1 then
      cont_meter(dl, mx1, mx1 + mw, mt, mb, 1, -150)          -- all lit
    else
      for i in ipairs(set.t) do
        local a, b = mt + set.u0[i] * k, mt + set.u1[i] * k
        local g = (b - a >= 4) and 1 or 0
        ImGui.DrawList_AddRectFilled(dl, mx1, math.floor(a), mx1 + mw, math.floor(b) - g, set.lit[i])
      end
    end
    local placed = {}
    for _, t in ipairs(LABEL_ORDER) do
      local cy = mt + Look.disp(db_to_u(t) - 0.5) * k
      local ok = true
      for _, py in ipairs(placed) do if math.abs(py - cy) < 12 then ok = false; break end end
      if ok then
        placed[#placed + 1] = cy
        local s = tostring(t)
        text_at(font_lk_s, mx1 - 8 - text_width(font_lk_s, s), cy, C.text2, s)
      end
    end
    -- the LED count at this height, under the meter
    local cnt = G.continuous == 1 and 'Continuous' or (#set.t .. ' LEDs')
    text_at(font_lk_s, x + (w - text_width(font_lk_s, cnt)) / 2, y + h - 10, C.text2, cnt)
  end

  local function db(v) return v .. ' dB' end
  local function plain(v) return tostring(v) end
  -- the settings column (in a child that scrolls when the window is shorter than the settings)
  local function settings()
    dl = ImGui.GetWindowDrawList(ctx)
    GW = math.floor((ImGui.GetContentRegionAvail(ctx)))       -- (the scrollbar, when shown, is left out)
    local x0, y0 = ImGui.GetCursorScreenPos(ctx)
    local y = y0
    -- Scale
    local ty = group(x0, y, 'Scale', 1,
      'The lowest level the meters show (-24 to -120 dB).\n\nDrag the slider, or click a value to type it.', 'scale')
    slider(x0, ty, 'Bottom of meter', 'm_floor', -120, -24, db, true)
    y = ty + ROW_H + GAP
    -- Colour zones
    ty = group(x0, y, 'Colour Zones', 3,
      'Each colour starts at its level and goes up to the next zone. Deep green is below light green.\n\n'
      .. 'Red at 0 dB: only the clip LED at the top is red.\n\nA zone set to the same level as the one above it is left out.', 'zones')
    slider(x0, ty, 'Red from', 'm_red', G.m_floor, 0, function(v) return v == 0 and 'Clip only' or db(v) end, true)
    slider(x0, ty + ROW_H, 'Amber from', 'm_amber', G.m_floor, 0, db, true)
    slider(x0, ty + 2 * ROW_H, 'Light green from', 'm_light', G.m_floor, 0, db, true)
    y = ty + 3 * ROW_H + GAP
    -- Zone sizes
    ty = group(x0, y, 'Zone Sizes', 4,
      'How much of the meter\'s height each colour zone takes. 100% is the normal scale; 200% makes the '
      .. 'zone twice as tall, and the other zones get shorter to fit.\n\nThe dB levels don\'t change, only where '
      .. 'they sit on the meter. A zone that is left out (see Colour Zones) has no size.', 'sizes')
    local function pct(v) return v .. '%' end
    slider(x0, ty, 'Red', 'sz_red', 25, 400, function(v) return G.m_red == 0 and 'Not used' or pct(v) end)
    slider(x0, ty + ROW_H, 'Amber', 'sz_amber', 25, 400, pct)
    slider(x0, ty + 2 * ROW_H, 'Light green', 'sz_light', 25, 400, pct)
    slider(x0, ty + 3 * ROW_H, 'Deep green', 'sz_deep', 25, 400, pct)
    y = ty + 4 * ROW_H + GAP
    -- LEDs
    -- (continuous: only the switch; the LED settings come back when it's off)
    local cont = G.continuous == 1
    local fixed = G.led_mode == 'fixed'
    local rows = cont and 1 or (fixed and 4 or 5)
    ty = group(x0, y, 'Segments', rows,
      'Continuous meter: a smooth bar instead of LEDs. The colour zones and sizes stay the same; the peak hold '
      .. 'is a thin line.\n\nAuto: one LED per "LED size" pixels of meter height, up to "Maximum LEDs". Taller '
      .. 'windows show more LEDs, shorter ones fewer, bigger LEDs.\n\nFixed: always this many LEDs, fewer only '
      .. 'when the meter is too short for them (an LED needs 3 px).\n\nLED counts include the clip LED.', 'leds')
    switch(x0, ty, 'Continuous meter', 'continuous')
    if not cont then
      segmented(x0, ty + ROW_H, 'LEDs', 'led_mode', { { 'Auto', 'auto' }, { 'Fixed', 'fixed' } })
      if fixed then
        slider(x0, ty + 2 * ROW_H, 'Number of LEDs', 'led_count', 4, 120, plain)
      else
        slider(x0, ty + 2 * ROW_H, 'LED size', 'led_size', 3, 16, function(v) return v .. ' px' end)
        slider(x0, ty + 3 * ROW_H, 'Maximum LEDs', 'led_max', 8, 120, plain)
      end
      readout(x0, ty + (rows - 1) * ROW_H, 'In the bridge now', Look.mh and (led_count(Look.mh) .. ' LEDs') or '-')
    end
    y = ty + rows * ROW_H + GAP
    -- Tracks
    ty = group(x0, y, 'Tracks', 1,
      'Mono tracks: record-armed tracks with a mono input; other tracks with only mono items, or no items and a '
      .. 'mono input (not folders or tracks with '
      .. 'receives). The one meter shows the louder of L / R, so a panned track still reads right.', 'tracks')
    switch(x0, ty, 'One meter for mono tracks', 'mono')
    y = ty + ROW_H + GAP
    if capsule('##reset', x0, y, 'Reset to Defaults') then
      for _, k in ipairs(LOOK_KEYS) do G[k] = DEFAULTS[k] end
      Look.edit = nil
      Look.apply(); Look.save()
    end
    ImGui.SetCursorScreenPos(ctx, x0, y0)
    ImGui.Dummy(ctx, GW, y + 28 - y0)
  end

  -- Stretch: wider = longer sliders, taller = taller preview meter. A window shorter than the settings
  -- scrolls the settings column; the preview always fills the height.
  local function body()
    local aw, ah = ImGui.GetContentRegionAvail(ctx)
    local x0, y0 = ImGui.GetCursorScreenPos(ctx)
    local lw = math.max(MIN_GW + 8, aw - 16 - PREV_W)         -- (+8: room for the scrollbar)
    if ImGui.BeginChild(ctx, '##lk_settings', lw, ah) then
      settings()
      ImGui.EndChild(ctx)
    end
    dl = ImGui.GetWindowDrawList(ctx)
    local px = x0 + lw + 16
    text_at(font_lk_b, px + 4, y0 + 9, C.text, 'Preview')
    preview(px, y0 + 24, PREV_W, math.max(60, ah - 24))
    ImGui.SetCursorScreenPos(ctx, x0, y0)
    ImGui.Dummy(ctx, lw + 16 + PREV_W, ah)
  end

  Look.draw = function()
    local cols = {
      { ImGui.Col_WindowBg, C.win }, { ImGui.Col_PopupBg, C.popup }, { ImGui.Col_Border, C.hair },
      { ImGui.Col_Text, C.text }, { ImGui.Col_TitleBg, C.win }, { ImGui.Col_TitleBgActive, 0x2A2A2DFF },
      { ImGui.Col_TitleBgCollapsed, C.win }, { ImGui.Col_FrameBg, C.fill_hov }, { ImGui.Col_FrameBgHovered, C.fill_hov },
      { ImGui.Col_FrameBgActive, C.fill_hov }, { ImGui.Col_TextSelectedBg, 0x2F6FD066 },
      { ImGui.Col_ChildBg, 0x00000000 }, { ImGui.Col_ScrollbarBg, 0x00000000 },
      { ImGui.Col_ScrollbarGrab, C.sw_off }, { ImGui.Col_ScrollbarGrabHovered, 0x7878807A },
      { ImGui.Col_ScrollbarGrabActive, 0x7878807A },
    }
    for _, c in ipairs(cols) do ImGui.PushStyleColor(ctx, c[1], c[2]) end
    local vars = {
      { ImGui.StyleVar_WindowPadding, 20, 18 }, { ImGui.StyleVar_ItemSpacing, 0, 0 },
      { ImGui.StyleVar_FramePadding, 10, 3 }, { ImGui.StyleVar_FrameRounding, 11 },
      { ImGui.StyleVar_WindowRounding, 12 }, { ImGui.StyleVar_PopupRounding, 12 },
      { ImGui.StyleVar_WindowBorderSize, 1 }, { ImGui.StyleVar_PopupBorderSize, 1 },
      { ImGui.StyleVar_ScrollbarSize, 8 }, { ImGui.StyleVar_ScrollbarRounding, 4 },
    }
    for _, v in ipairs(vars) do ImGui.PushStyleVar(ctx, v[1], v[2], v[3]) end
    ImGui.PushFont(ctx, font_lk)
    -- resizable (stretch): at least as wide as the settings + preview, any height down to a short meter
    local min_w = 40 + MIN_GW + 8 + 16 + PREV_W
    ImGui.SetNextWindowSize(ctx, min_w, 600, ImGui.Cond_FirstUseEver)
    ImGui.SetNextWindowSizeConstraints(ctx, min_w, 160, 10000, 10000)
    local visible, open = ImGui.Begin(ctx, 'Meter Look###DanielMeterBridgeLook', true,
      ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
    if visible then
      body()
      ImGui.End(ctx)
    end
    ImGui.PopFont(ctx)
    ImGui.PopStyleVar(ctx, #vars)
    ImGui.PopStyleColor(ctx, #cols)
    if not open then Look.open = false; Look.edit = nil end
  end
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
  -- no yellow drag-and-drop highlight rectangle on the strips (the insertion line shows where it lands)
  ImGui.PushStyleColor(ctx, ImGui.Col_DragDropTarget, 0x00000000)

  D.dl = ImGui.GetWindowDrawList(ctx)
  D.meter_menu_tr = nil
  W.docked = ImGui.IsWindowDocked(ctx)
  if W.docked then
    local id = ImGui.GetWindowDockID(ctx)
    local key = opt_key('dock', W.n)
    if id < 0 and tostring(id) ~= r.GetExtState(EXT, key) then r.SetExtState(EXT, key, tostring(id), true) end
  end

  local ox, oy = ImGui.GetCursorScreenPos(ctx)
  local aw, ah = ImGui.GetContentRegionAvail(ctx)
  local n = #tracks
  -- as many rows as fit at full height (at least one); if the strips are wider than the window it
  -- scrolls sideways. Each strip is as wide as its meters need (multichannel tracks are wider), so
  -- the strips are shared out by width, so the rows come out about the same width
  local sbar = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ScrollbarSize)
  -- track spacers (REAPER's, shared with the mixer): the track with a spacer before it has I_SPACER;
  -- shown as a gap before that strip, like the mixer (not before the first strip of a row)
  local SPACER_W = 16                  -- the real mixer's spacer: 16 pt
  local sw, gap, total = {}, {}, 0
  local master = r.GetMasterTrack(0)
  for k, tr in ipairs(tracks) do
    sw[k] = strip_width(n_meters(tr))
    local prev = tracks[k - 1]
    gap[k] = (prev and prev ~= master and tr ~= master and r.GetMediaTrackInfo_Value(tr, 'I_SPACER') == 1)
             and SPACER_W or 0
    total = total + sw[k] + gap[k]
  end
  local rows = math.max(1, math.min(math.ceil(total / math.max(1, aw - SCALE_W)), math.floor(ah / ROW_FULL)))
  local row_of, row_x = {}, {}         -- which row each strip is in, and its x offset in that row
  local widest = 0
  do
    local target, row, x = total / rows, 1, 0
    for k = 1, n do
      if x > 0 and row < rows and x + gap[k] + sw[k] / 2 > target then
        widest = math.max(widest, x); row, x = row + 1, 0
      end
      if x == 0 then gap[k] = 0 end    -- a row starts here: no gap
      x = x + gap[k]
      row_of[k], row_x[k] = row, x
      x = x + sw[k]
    end
    widest = math.max(widest, x)
    rows = math.max(1, row_of[n] or 1)
  end
  local content_w = SCALE_W + widest
  if content_w > aw then ah = ah - sbar end      -- the horizontal scrollbar takes some height
  local rh = math.max(MIN_ROW_H, math.floor(ah / rows))
  D.lay = strip_layout(rh - 4)
  Look.mh = D.lay.mh                                 -- (the Meter look window shows the LED count)
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
      for k, tr in ipairs(tracks) do
        if row_of[k] == row + 1 then
          ImGui.PushID(ctx, r.GetTrackGUID(tr))
          local sx1 = ox + SCALE_W + row_x[k]
          if gap[k] > 0 then DnD.spacer(tr, sx1 - gap[k], y0, sx1, y0 + rh - 4) end
          draw_strip(tr, sx1, y0, sw[k], rh - 4, now)
          ImGui.PopID(ctx)
        end
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
  -- heart: bottom of the dB column, level with the number bars of the last row (always there)
  do
    local y2 = oy + (rows - 1) * rh + (rh - 4)
    local hc = (wcol ~= bg) and Win.text_on(wcol) or 0xD0D0D0FF
    Support.button(sx + 2, y2 - NUM_H, sx + SCALE_W - 2, y2, hc)
  end
  ImGui.SetCursorScreenPos(ctx, ox, oy)
  ImGui.Dummy(ctx, content_w, rows * rh - 4)     -- content size, so the window scrolls when strips don't fit

  -- right-click: the title bar or the dB column -> window menu; anywhere else -> options
  if ImGui.IsWindowHovered(ctx) and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) then
    local mx, my = ImGui.GetMousePos(ctx)
    local wmenu = my < oy - 1 or mx < sx + SCALE_W
    local mtr = D.meter_menu_tr
    if not wmenu and mtr and r.ValidatePtr2(0, mtr, 'MediaTrack*') then
      -- a track's meter: the meter mode menu (the bridge keeps running while it's open)
      W.meter_tr = mtr
      ImGui.OpenPopup(ctx, 'meter_menu')
    else
      ImGui.OpenPopup(ctx, wmenu and 'win_menu' or 'options')
    end
  end
  window_menu(W)
  options_menu(W)
  meter_menu(W)
  if D.open_input then D.open_input = nil; ImGui.OpenPopup(ctx, 'input_menu') end
  input_menu()

  local focused = ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows)
  if focused and not ImGui.IsAnyItemActive(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Space, false) then
    r.Main_OnCommand(40044, 0)    -- Transport: Play/stop
  end
  ImGui.PopStyleColor(ctx)
  ImGui.End(ctx)
  return open, focused
end

local function loop()
  local now = r.time_precise()
  Theme.check()

  Win.load()
  Mono.refresh()
  VCA.refresh(now)
  if Win.new_req then Win.new_req = nil; Win.add() end

  ImGui.PushFont(ctx, font_ui)
  local closed, any_focus = {}, false
  for _, W in ipairs(Win.list) do
    local open, focused = draw_window(W, now)
    if not open then closed[W] = true end
    any_focus = any_focus or focused
  end
  ImGui.PopFont(ctx)
  if Look.open then Look.draw() end
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
