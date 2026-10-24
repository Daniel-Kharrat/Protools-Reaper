-- @description Daniel_Auto Mixer Panel
-- @author Daniel Kharrat
-- @version 2.16
-- @changelog
--   Dragging one of several selected strips moves all the selected strips together.
--   Fixed: Cmd-click (Ctrl-click on Windows/Linux) didn't toggle a strip's selection.
--   Fixed: switching from one hardware output to another kept the first output.
--   2.15:
--   Hardware-input strips have a segmented input meter, so they're easy to tell from track strips.
--   Inputs already in use are shown in soft red in the input lists.
--   2.12:
--   Every strip has an input selector (left), output selector (middle) and group (right).
--   Input: No input or a hardware input. Output: Main mix, a hardware output, or None.
--   2.11:
--   Output selector on hardware-input strips (left of the group chip):
--   Main mix (as before), a hardware output (0 dB post-fader send, main send off),
--   or None (main send off, no hardware outputs).
--   2.10:
--   Group labels (G1, G2…) are centred in their chips on every OS (they sat low on Windows).
--   2.9:
--   Opening or closing the panel from the action list or a shortcut now saves its on/off
--   state for the startup action too (before, only the toolbar button did), like the
--   Floating Mixer.
--   2.8:
--   Right-click the title bar or any empty space: Dock window / Undock window, Close window.
--   Reopens docked if it was docked (and in the same docker).
--   2.7:
--   A small heart (Ko-fi support link) at the top of the side column, above the settings.
--   2.6:
--   4 groups instead of 8, each with its own accent colour (1 blue, 2 green, 3 amber,
--   4 purple); a strip takes its group's colour. No red group, so mute stays unmistakable.
--   2.4:
--   Side column: two buttons add a hardware input or an existing track in one step
--   (fills the first empty slot, otherwise adds a strip). Starts with 3 empty slots.
--   2.3:
--   Back to the 2.0 input meter (2.1 / 2.2 meter changes removed).
--   Calmer blue gain meter (display only): rises quickly, falls slowly.
--   2.0:
--   Goes with Daniel_Auto Mixer 2.0 (no plugin window, always automatic); still works with 1.x.
--   Settings (gear at the top of the + column): Last mic hold, Hold below and Release
--   for all channels, saved with the project.
--   1.11:
--   Strips keep a constant width (164); the window is never wider than one row of strips.
--   Making it narrower moves strips to more rows; making it taller lengthens the meters and faders.
--   1.9:
--   Resizable: strips stretch with the window (wider up to a limit, taller meters and faders).
--   Top row removed (the title is in the title bar); errors show in a small bar only when needed.
--   Adding a slot keeps your strip size and grows the window to fit.
--   1.8:
--   Double-click a track name to rename it (Enter or click away keeps it, Esc cancels).
--   Status line: thicker, fully rounded, quicker colour changes.
--   1.7:
--   Status is a thin line instead of a word: blue when open, desaturated blue when ducked,
--   red when the track is muted; the colour glides between states. Hover it for the word.
--   1.6:
--   Status label: fixed width, changes calmly (a new state must last a moment, then fades in).
--   Fixed: a muted track showed "Offline" after a few seconds; it now stays "Track muted".
--   1.5:
--   Fixed: dragging one fader or weight moved them all.
--   Status per channel: OPEN / HOLDING (the open mic), SHARING, DUCKED.
--   Empty slot: click the + for a menu with Hardware input and Existing track.
--   Drag strips to reorder them (saved with the project).
--   1.4:
--   Volume fader next to the meters (same fader curve and behaviour as Daniel_Floating Mixer).
--   Weight is a vertical slider beside the fader.
--   Click a strip to select its track; Shift selects a range, Cmd/Ctrl toggles.
--   Always automatic: the Auto / Manual / Mute switch is gone.
--   Blue accent.
--   1.3: new look in the style of Marker based cleanup.
--   Toolbar sync like the other Daniel scripts: the toggle button and the panel
--   follow each other however the panel is opened or closed.
--   Tracks created for hardware inputs are hidden from the arrange view and mixer.
--   Removing a channel that the panel created deletes its track straight away.
-- @about
--   Control panel for "Daniel_Auto Mixer" (JSFX), a Dugan-style gain-sharing
--   automatic mic mixer for live sound.
--   * Starts with 4 empty slots. "+" adds a slot; the window grows and wraps
--     into rows.
--   * Each slot takes a hardware input (creates a hidden, monitor-only track
--     with the auto mixer on it) or an existing track (adds the auto mixer to it).
--   * Tracks that already have the auto mixer appear automatically.
--   * Live gain-share and input meters, mode, group and weight per channel.
--   * Muting a track takes it out of the gain sharing.
--   * The slot layout is saved with the project.
--   Requires ReaImGui 0.9 or newer.
--   Support: ko-fi.com/danielkharrat

local SCRIPT_NAME = "Auto Mixer"
local EXT         = "Daniel_AutoMixerPanel"
local INI_KEY     = "Auto_Mixer_Panel"
local INI_SECTION = "toolbar button states"
local GMEM_NAME   = "Daniel_AutoMixer"
local FX_MATCH    = "Daniel_Auto Mixer"
local FX_ADD_NAMES = { "JS:Daniel_Auto Mixer", "JS: Daniel_Auto Mixer", "Daniel_Auto Mixer" }
local HIDDEN_TRACK = "Always Recording (auto)"

---------------------------------------------------------------------
-- Start / stop and toolbar sync
-- The toolbar button runs "Daniel_Auto Mixer Panel (toolbar toggle).lua".
-- This script keeps that button and its own toggle state matching whether
-- the panel is really open, however it was started or closed.
-- reaper.ini [toolbar button states] Auto_Mixer_Panel: 1 while open,
-- 0 when you close it (window X, toolbar button, action or shortcut). Quitting REAPER while
-- it's open leaves it at 1 so the startup action reopens it.
---------------------------------------------------------------------

-- the toolbar button's script: Daniel_Auto Mixer Panel (toolbar toggle).lua
local TOGGLE_BUTTON = "_RS6a841203ee0f0c1ce567f92c49dd4924626d0a8f"

local _, _, SECTION_ID, CMD_ID = reaper.get_action_context()

-- writes KEY=value in reaper.ini under [toolbar button states] (adds the line if missing)
local function set_ini_flag(value)
  local path = reaper.get_ini_file()
  local f = io.open(path, "rb")
  if not f then return end
  local d = f:read("a")
  f:close()
  local nl = d:find("\r\n", 1, true) and "\r\n" or "\n"
  local val = tostring(value)
  local nd, n = d:gsub("(\n" .. INI_KEY .. "=)[^\r\n]*", function(p) return p .. val end)
  if n == 0 then
    nd, n = d:gsub("(%[" .. INI_SECTION .. "%][^\r\n]*\r?\n)", function(h) return h .. INI_KEY .. "=" .. val .. nl end, 1)
  end
  if n == 0 then
    nd = d .. ((d:sub(-1) == "\n") and "" or nl) .. "[" .. INI_SECTION .. "]" .. nl .. INI_KEY .. "=" .. val .. nl
  end
  if nd == d then return end
  f = io.open(path, "wb")
  if f then f:write(nd) f:close() end
end

local function set_visual_state(on)
  local v = on and 1 or 0
  if CMD_ID and CMD_ID ~= 0 then
    reaper.SetToggleCommandState(SECTION_ID, CMD_ID, v)
    reaper.RefreshToolbar2(SECTION_ID, CMD_ID)
  end
  local tid = reaper.NamedCommandLookup(TOGGLE_BUTTON)
  if tid and tid ~= 0 then
    reaper.SetToggleCommandState(0, tid, v)
    reaper.RefreshToolbar2(0, tid)
  end
end

-- Running the action while the panel is open turns it off, from anywhere (action list, shortcut,
-- toolbar). REAPER stops the running panel and, with set_action_options(1 + 2), starts it again
-- right away; the stopped one left the time it stopped, so this new start knows it's a "turn off":
-- it writes 0 and doesn't open. REAPER quitting stops it without starting it again, so the flag
-- stays 1 and the panel comes back at the next startup.
local stopped_at = tonumber(reaper.GetExtState(EXT, "stopped_at"))
reaper.DeleteExtState(EXT, "stopped_at", false)
if stopped_at and reaper.time_precise() - stopped_at < 1 then
  set_visual_state(false)
  set_ini_flag(0)
  return
end
reaper.set_action_options(1 | 2)

if not reaper.ImGui_GetBuiltinPath then
  reaper.MB("This script needs ReaImGui (0.9 or newer).\nInstall it with ReaPack: Extensions > ReaPack > Browse packages > ReaImGui.", SCRIPT_NAME, 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua"
local ImGui = require "imgui" "0.9"


---------------------------------------------------------------------
-- Look (same family as "Daniel_Marker based cleanup")
---------------------------------------------------------------------
local OS = reaper.GetOS()
local FONT = (OS:find("OSX") or OS:find("mac")) and "Helvetica Neue"
          or (OS:find("Win") and "Segoe UI" or "DejaVu Sans")

local COL = {
  bg      = 0x17171B,
  panel   = 0x222228,
  panel_sel = 0x262A34,
  line    = 0x2E2E36,
  text    = 0xEDEDF2,
  muted   = 0x8A8A96,
  dim     = 0x5C5C68,
  key     = 0x2F2F38,
  keyedge = 0x45454F,
  keyhov  = 0x383842,
  well    = 0x131317,
  note    = 0xF2C46D,
  clip    = 0xF2555A,
  in_ok   = 0x4CC38A,
  in_use  = 0xE08A8E,   -- soft red: input already used by a strip (menus)
}
local BLUE = 0x5B9BF0
local ACCENT = BLUE        -- the panel's accent; inside a channel strip it's that channel's group colour
-- one accent colour per group (no red, so nothing looks like mute / clip)
local GROUP_COL = { BLUE, 0x4CC38A, 0xF2C46D, 0xB07CF0 }
local N_GROUPS = #GROUP_COL

local function rgba(hex, a) return (hex << 8) | math.floor((a or 1) * 255 + 0.5) end
local function on_accent(hex)
  local r, g, b = (hex >> 16) & 255, (hex >> 8) & 255, hex & 255
  return (0.299 * r + 0.587 * g + 0.114 * b > 150) and COL.bg or 0xFFFFFF
end

local SW_MIN       = 164        -- strip width (constant)
local SH_MIN       = 380        -- smallest strip height (strips get taller with the window)
local SW, SH       = SW_MIN, SH_MIN  -- current strip size, worked out every frame
local PLUS_W     = 40
local GAP        = 8
local PAD        = 12
local METER_FIXED = SH_MIN - 230  -- strip height that isn't the control well
local METER_H    = 230      -- height of the control well (meters, fader, weight); grows with the strip
local GAIN_FLOOR = -30      -- bottom of the gain meter (dB)
local IN_FLOOR   = -60      -- bottom of the input meter (dBFS)

local ctx        = ImGui.CreateContext(SCRIPT_NAME)
local font       = ImGui.CreateFont(FONT, 14)
local font_small = ImGui.CreateFont(FONT, 12)
local font_label = ImGui.CreateFont(FONT, 11, ImGui.FontFlags_Bold)
local font_title = ImGui.CreateFont(FONT, 18, ImGui.FontFlags_Bold)
local font_big   = ImGui.CreateFont(FONT, 26, ImGui.FontFlags_Bold)
for _, f in ipairs({ font, font_small, font_label, font_title, font_big }) do ImGui.Attach(ctx, f) end

reaper.gmem_attach(GMEM_NAME)

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local S = {
  proj        = nil,
  slots       = {},      -- { guid = "...", created = bool } or {} for empty
  disp        = {},      -- per-guid meter display state
  last_scan   = 0,
  want_resize = true,
  last_count  = -1,
  docked      = false,
  last_time   = reaper.time_precise(),
  error_msg   = nil,
  closed_by_user = false,
  sel_anchor  = nil,     -- last strip clicked (for Shift range selection)
  pending_move = nil,    -- { from, to } strip reorder, applied after drawing
  cfg         = { hold = 1, thr = -55, rel = 120 },
  renaming    = nil,     -- guid of the track being renamed
  dock_req    = nil,     -- dock id to apply before the next frame (0 = undock)
  close_req   = false,
  name_buf    = "",
  rename_focus = false,
}

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function track_name(tr)
  local _, name = reaper.GetTrackName(tr)
  return name
end

local function find_fx(tr)
  for i = 0, reaper.TrackFX_GetCount(tr) - 1 do
    local _, name = reaper.TrackFX_GetFXName(tr, i, "")
    if name:find(FX_MATCH, 1, true) then return i end
  end
  return nil
end

local function track_by_guid(guid)
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if reaper.GetTrackGUID(tr) == guid then return tr end
  end
  return nil
end

local function db(v) return (v and v > 0) and 20 * math.log(v, 10) or -150 end

-- the plugin's parameters, found by name so slider order doesn't matter
local PARAM_KEYS = { mode = "Mode", weight = "Weight", group = "Group", rel = "Release",
                     hold = "Last mic hold", thr = "Hold below", slot = "Slot" }
local function params_of(tr, fx)
  local P = {}
  for p = 0, reaper.TrackFX_GetNumParams(tr, fx) - 1 do
    local _, name = reaper.TrackFX_GetParamName(tr, fx, p)
    for k, key in pairs(PARAM_KEYS) do
      if not P[k] and name:find(key, 1, true) then P[k] = p end
    end
  end
  return P
end

local function save_state()
  local parts = {}
  for _, s in ipairs(S.slots) do
    parts[#parts + 1] = s.guid and (s.guid .. "|" .. (s.created and "1" or "0")) or "-"
  end
  reaper.SetProjExtState(0, EXT, "slots", table.concat(parts, ";"))
end

-- settings shared by all channels (applied to every Auto Mixer instance)
local CFG_DEFAULT = { hold = 1, thr = -55, rel = 120 }

local function save_cfg()
  reaper.SetProjExtState(0, EXT, "settings",
    string.format("hold=%d;thr=%g;rel=%g", S.cfg.hold, S.cfg.thr, S.cfg.rel))
end

local function load_cfg()
  S.cfg = { hold = CFG_DEFAULT.hold, thr = CFG_DEFAULT.thr, rel = CFG_DEFAULT.rel }
  local ok, str = reaper.GetProjExtState(0, EXT, "settings")
  if ok == 1 then
    for k, v in str:gmatch("(%a+)=([%-%d%.]+)") do
      if S.cfg[k] ~= nil then S.cfg[k] = tonumber(v) or S.cfg[k] end
    end
  end
end

local function load_state()
  load_cfg()
  S.slots = {}
  local ok, str = reaper.GetProjExtState(0, EXT, "slots")
  if ok == 1 and str ~= "" then
    for item in (str .. ";"):gmatch("([^;]*);") do
      if item == "-" or item == "" then
        S.slots[#S.slots + 1] = {}
      else
        local guid, cr = item:match("^(.-)|(%d)$")
        S.slots[#S.slots + 1] = guid and { guid = guid, created = cr == "1" } or {}
      end
    end
  end
  if #S.slots == 0 then for _ = 1, 3 do S.slots[#S.slots + 1] = {} end end
  S.want_resize = true
end

-- keep slots in sync with the project: drop deleted tracks / removed plugins,
-- add tracks that got the plugin by hand
local function scan()
  local present = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if track_name(tr) ~= HIDDEN_TRACK and find_fx(tr) then
      present[reaper.GetTrackGUID(tr)] = true
    end
  end
  local changed, known = false, {}
  for i, s in ipairs(S.slots) do
    if s.guid then
      if present[s.guid] and not known[s.guid] then
        known[s.guid] = true
      else
        S.slots[i] = {}
        changed = true
      end
    end
  end
  for i = 0, reaper.CountTracks(0) - 1 do
    local guid = reaper.GetTrackGUID(reaper.GetTrack(0, i))
    if present[guid] and not known[guid] then
      local placed = false
      for _, s in ipairs(S.slots) do
        if not s.guid then s.guid, s.created, placed = guid, false, true break end
      end
      if not placed then S.slots[#S.slots + 1] = { guid = guid, created = false } end
      known[guid] = true
      changed = true
    end
  end
  if changed then save_state() end
end

local function add_fx(tr)
  for _, name in ipairs(FX_ADD_NAMES) do
    local idx = reaper.TrackFX_AddByName(tr, name, false, -1)
    if idx >= 0 then return idx end
  end
  return -1
end

local function insert_index()
  -- after the last track used by the panel, otherwise at the end
  local idx = reaper.CountTracks(0)
  local last = -1
  for _, s in ipairs(S.slots) do
    if s.guid then
      local tr = track_by_guid(s.guid)
      if tr then last = math.max(last, reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") - 1) end
    end
  end
  if last >= 0 then idx = last + 1 end
  return idx
end

local function assign_input(slot, ch)
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local idx = insert_index()
  reaper.InsertTrackAtIndex(idx, true)
  local tr = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "Mic " .. (ch + 1), true)
  reaper.SetMediaTrackInfo_Value(tr, "I_RECINPUT", ch)  -- mono hardware input
  reaper.SetMediaTrackInfo_Value(tr, "I_RECMODE", 2)    -- record: none (monitor only)
  reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", 1)
  reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", 1)
  reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", 0)     -- hidden: the panel is its interface
  reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 0)
  local fx = add_fx(tr)
  reaper.PreventUIRefresh(-1)
  if fx < 0 then
    reaper.DeleteTrack(tr)
    reaper.Undo_EndBlock("Auto Mixer: add input (failed)", -1)
    S.error_msg = "Couldn't find the Daniel_Auto Mixer plugin. Is it in your Effects folder?"
    return
  end
  slot.guid, slot.created = reaper.GetTrackGUID(tr), true
  reaper.Undo_EndBlock("Auto Mixer: add input " .. (ch + 1), -1)
  save_state()
end

local function assign_track(slot, tr)
  reaper.Undo_BeginBlock()
  local fx = add_fx(tr)
  if fx < 0 then
    reaper.Undo_EndBlock("Auto Mixer: add track (failed)", -1)
    S.error_msg = "Couldn't find the Daniel_Auto Mixer plugin. Is it in your Effects folder?"
    return
  end
  slot.guid, slot.created = reaper.GetTrackGUID(tr), false
  reaper.Undo_EndBlock("Auto Mixer: add track \"" .. track_name(tr) .. "\"", -1)
  save_state()
end

local function remove_slot(i, delete_track)
  local s = S.slots[i]
  if s.guid then
    local tr = track_by_guid(s.guid)
    if tr then
      reaper.Undo_BeginBlock()
      if delete_track then
        reaper.DeleteTrack(tr)
      else
        local fx = find_fx(tr)
        if fx then reaper.TrackFX_Delete(tr, fx) end
      end
      reaper.Undo_EndBlock(delete_track and "Auto Mixer: remove channel and delete track"
                                         or "Auto Mixer: remove channel", -1)
    end
  end
  if #S.slots > 1 then table.remove(S.slots, i) else S.slots[i] = {} end
  save_state()
end

local function input_label(tr)
  local inp = reaper.GetMediaTrackInfo_Value(tr, "I_RECINPUT")
  if inp < 0 then return "In off" end
  if inp >= 4096 then return "MIDI" end
  local ch = math.floor(inp) & 1023
  if inp >= 2048 then return "In " .. (ch + 1) .. "+" end
  if inp >= 1024 then return "In " .. (ch + 1) .. "/" .. (ch + 2) end
  return "In " .. (ch + 1)
end

local function used_inputs()
  local used = {}
  for _, s in ipairs(S.slots) do
    if s.guid then
      local tr = track_by_guid(s.guid)
      if tr then
        local inp = reaper.GetMediaTrackInfo_Value(tr, "I_RECINPUT")
        if inp >= 0 and inp < 1024 then used[math.floor(inp)] = true end
      end
    end
  end
  return used
end

-- output of a hardware-input track: "main" (main send on), a hardware output index, or "none".
-- Read from the track itself, so it's always what REAPER really does.
local function track_output(tr)
  if reaper.GetMediaTrackInfo_Value(tr, "B_MAINSEND") == 1 then return "main" end
  if reaper.GetTrackNumSends(tr, 1) > 0 then
    return math.floor(reaper.GetTrackSendInfo_Value(tr, 1, 0, "I_DSTCHAN")) & 1023
  end
  return "none"
end

local function set_output(tr, out)
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  reaper.SetMediaTrackInfo_Value(tr, "B_MAINSEND", (out == "main") and 1 or 0)
  if type(out) == "number" then
    out = math.floor(out)
    -- keep one hardware send and point it at the new output (instead of deleting and
    -- re-creating it, which left the first output in place); create it if there's none
    local s = 0
    if reaper.GetTrackNumSends(tr, 1) == 0 then s = reaper.CreateTrackSend(tr, nil) end
    -- remove any other hardware sends, last first so the indexes stay valid
    for k = reaper.GetTrackNumSends(tr, 1) - 1, 1, -1 do reaper.RemoveTrackSend(tr, 1, k) end
    if s >= 0 and reaper.GetTrackNumSends(tr, 1) > 0 then
      -- a mono-input track sends channel 1; anything else sends channels 1/2 mixed to mono
      local inp = reaper.GetMediaTrackInfo_Value(tr, "I_RECINPUT")
      local mono_src = inp >= 0 and inp < 1024
      reaper.SetTrackSendInfo_Value(tr, 1, 0, "D_VOL", 1)            -- 0 dB
      reaper.SetTrackSendInfo_Value(tr, 1, 0, "I_SENDMODE", 0)       -- post-fader: gets the auto mixing and the fader
      reaper.SetTrackSendInfo_Value(tr, 1, 0, "I_SRCCHAN", mono_src and 1024 or 0)
      reaper.SetTrackSendInfo_Value(tr, 1, 0, "I_DSTCHAN", 1024 | out) -- mono, to this output
    end
  else
    for k = reaper.GetTrackNumSends(tr, 1) - 1, 0, -1 do reaper.RemoveTrackSend(tr, 1, k) end
  end
  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)   -- refresh the routing / I/O buttons
  local what = (out == "main") and "Main mix" or (out == "none") and "None" or ("Out " .. (out + 1))
  reaper.Undo_EndBlock("Auto Mixer: output " .. what, -1)
end

-- input: -1 = no input, otherwise a mono hardware input.
-- A panel-made track still called "Mic <old input>" is renamed to follow the new input.
local function set_input(tr, ch, created)
  reaper.Undo_BeginBlock()
  local old = math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_RECINPUT"))
  reaper.SetMediaTrackInfo_Value(tr, "I_RECINPUT", ch)
  if created and ch >= 0 and old >= 0 and old < 1024 then
    local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if name == "Mic " .. (old + 1) then reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "Mic " .. (ch + 1), true) end
  end
  reaper.Undo_EndBlock("Auto Mixer: input " .. ((ch < 0) and "none" or tostring(ch + 1)), -1)
end

---------------------------------------------------------------------
-- Value conversion (same as Daniel_Floating Mixer: REAPER's own fader curve)
---------------------------------------------------------------------
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function val2db(v)
  if not v or v < 0.0000000298023223876953125 then return -150.0 end
  local d = math.log(v) * 8.6858896380650365530225783783321
  return d < -150 and -150.0 or d
end
local function db2val(d) return math.exp(d * 0.11512925464970228420089957273422) end
local function pos_of(db) if db <= -149.9 then return 0 end return clamp(reaper.DB2SLIDER(db) / 1000, 0, 1) end
local function vol_of_pos(p) if p <= 0 then return 0 end return db2val(reaper.SLIDER2DB(p * 1000)) end
local function max_db() return reaper.SLIDER2DB(1000) end
local function fmt_vol(d)
  if d <= -149.9 then return "-inf" end
  local s = string.format("%.1f", d)
  if s == "-0.0" then s = "0.0" end
  return s
end
-- UI path: touch automation and undo like REAPER's own faders
local function set_vol(tr, v, done)
  reaper.SetTrackUIVolume(tr, clamp(v, 0, db2val(max_db())), false, done and true or false, 0)
end

---------------------------------------------------------------------
-- Drawing helpers (screen coordinates)
---------------------------------------------------------------------
local DL -- window draw list, set every frame

local function rr(x, y, w, h, r, hex, a)
  ImGui.DrawList_AddRectFilled(DL, x, y, x + w, y + h, rgba(hex, a), r)
end

local function text_w(f, str)
  ImGui.PushFont(ctx, f)
  local w, h = ImGui.CalcTextSize(ctx, str)
  ImGui.PopFont(ctx)
  return w, h
end

local function text_at(f, str, x, y, hex, align, a)
  ImGui.PushFont(ctx, f)
  local w, h = ImGui.CalcTextSize(ctx, str)
  if align == "center" then x = x - w / 2 elseif align == "right" then x = x - w end
  ImGui.DrawList_AddText(DL, math.floor(x + 0.5), math.floor(y + 0.5), rgba(hex, a), str)
  ImGui.PopFont(ctx)
  return w, h
end

local function clip_text(f, str, max_w)
  if text_w(f, str) <= max_w then return str end
  while #str > 1 and text_w(f, str .. "...") > max_w do str = str:sub(1, -2) end
  return str .. "..."
end

local function mods() return ImGui.GetKeyMods(ctx) end
local function is_fine() return (mods() & ImGui.Mod_Shift) ~= 0 end
local function is_alt()  return (mods() & ImGui.Mod_Alt) ~= 0 end
-- Cmd on macOS, Ctrl on Windows/Linux. ImGui alone missed Cmd on macOS (it can report it as
-- Super, or not at all when the panel isn't the focused window), so also ask the OS via js_ReaScriptAPI.
local function is_ctrl()
  local m = mods()
  if (m & ImGui.Mod_Ctrl) ~= 0 then return true end
  if reaper.GetOS():match("^OSX") or reaper.GetOS():match("^macOS") then
    if (m & ImGui.Mod_Super) ~= 0 then return true end
  end
  if reaper.JS_Mouse_GetState then return (reaper.JS_Mouse_GetState(4) & 4) ~= 0 end   -- 4 = Cmd / Ctrl
  return false
end

-- invisible hit area at screen position
local function hit(id, x, y, w, h, tip)
  ImGui.SetCursorScreenPos(ctx, x, y)
  local clicked = ImGui.InvisibleButton(ctx, id, math.max(1, w), math.max(1, h))
  local hov = ImGui.IsItemHovered(ctx)
  if tip and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayNormal) and not ImGui.IsItemActive(ctx) then
    ImGui.SetTooltip(ctx, tip)
  end
  return { click = clicked, hov = hov, act = ImGui.IsItemActive(ctx),
    activated = ImGui.IsItemActivated(ctx), deactivated = ImGui.IsItemDeactivated(ctx),
    dbl = hov and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) }
end

-- REAPER Preferences > Editing Behavior > Mouse: "Ignore mousewheel on faders" (like the Floating Mixer)
local wheel_cache, wheel_t = nil, 0
local function wheel_on_faders()
  local now = reaper.time_precise()
  if wheel_cache == nil or now - wheel_t > 3 then
    wheel_t = now
    local v = 0
    if reaper.get_config_var_string then
      local ok, sv = reaper.get_config_var_string("mousewheelmode")
      v = (ok and tonumber(sv)) or 0
    end
    wheel_cache = (math.floor(v) & 3) == 0
  end
  return wheel_cache
end

-- vertical drag: value change per screen pixel; Shift = fine; Alt-click / double-click = reset
local drag = {}
local function drag_value(id, h, v, lo, hi, reset, per_dy, wheel_step)
  local nv, done
  if h.activated then drag[id] = v if is_alt() then drag[id] = reset nv = reset end end
  if h.dbl then drag[id] = reset nv = reset end
  if h.act and drag[id] then
    local _, dy = ImGui.GetMouseDelta(ctx)
    local d = -dy * per_dy * (is_fine() and 0.1 or 1)
    if d ~= 0 then drag[id] = clamp(drag[id] + d, lo, hi) nv = drag[id] end
  end
  if h.deactivated and drag[id] then nv = drag[id] done = true drag[id] = nil end
  if h.hov and not h.act and wheel_on_faders() then
    local w = ImGui.GetMouseWheel(ctx)
    if w ~= 0 then nv = clamp(v + w * wheel_step * (is_fine() and 0.2 or 1), lo, hi) done = true end
  end
  return nv, done
end

local function keycap(x, y, label, hl)
  local w = math.max(22, text_w(font_label, label) + 14)
  rr(x, y + 1, w, 21, 5, hl and ACCENT or COL.keyedge, hl and 0.7 or 1)
  rr(x, y, w, 20, 5, hl and ACCENT or COL.key)
  text_at(font_label, label, x + w / 2, y + 4, hl and on_accent(ACCENT) or COL.text, "center")
  return w
end

local function close_x(id, x, y)
  local h = hit(id, x - 3, y - 3, 16, 16)
  local c = rgba(h.hov and COL.text or COL.dim)
  ImGui.DrawList_AddLine(DL, x + 1, y + 1, x + 9, y + 9, c, 1.5)
  ImGui.DrawList_AddLine(DL, x + 9, y + 1, x + 1, y + 9, c, 1.5)
  return h.click
end

local function key_button(id, x, y, w, h, label)
  local hh = hit(id, x, y, w, h)
  rr(x, y + 1, w, h, 6, COL.keyedge)
  rr(x, y, w, h, 6, hh.hov and COL.keyhov or COL.key)
  local _, th = text_w(font_small, label)
  text_at(font_small, label, x + w / 2, y + (h - th) / 2, COL.text, "center")
  return hh.click
end

-- status line under the readout: one fixed-size bar whose colour glides to the channel's state
local STATUS_W, STATUS_H = 104, 8
local STATUS_FADE = 0.2       -- seconds to glide to a new colour

local function mix(c1, c2, t)
  local r1, g1, b1 = (c1 >> 16) & 255, (c1 >> 8) & 255, c1 & 255
  local r2, g2, b2 = (c2 >> 16) & 255, (c2 >> 8) & 255, c2 & 255
  return (math.floor(r1 + (r2 - r1) * t + 0.5) << 16) | (math.floor(g1 + (g2 - g1) * t + 0.5) << 8)
       | math.floor(b1 + (b2 - b1) * t + 0.5)
end

local function draw_status(d, cx, y, target, tip, dt)
  d.bar_col = d.bar_col and mix(d.bar_col, target, math.min(1, dt / STATUS_FADE)) or target
  local x1 = cx - STATUS_W / 2
  rr(x1, y, STATUS_W, STATUS_H, STATUS_H / 2, d.bar_col)
  if ImGui.IsMouseHoveringRect(ctx, x1, y - 4, x1 + STATUS_W, y + STATUS_H + 4) then ImGui.SetTooltip(ctx, tip) end
end

---------------------------------------------------------------------
-- Selection (like the Floating Mixer: Shift = range, Cmd/Ctrl = toggle)
-- The range follows the order of the strips in the panel.
---------------------------------------------------------------------
local function select_click(i, tr)
  local anchor_i
  if S.sel_anchor then
    for k, s in ipairs(S.slots) do if s.guid == S.sel_anchor then anchor_i = k break end end
  end
  if is_fine() and anchor_i then
    local a, b = math.min(anchor_i, i), math.max(anchor_i, i)
    reaper.PreventUIRefresh(1)
    if not is_ctrl() then
      for t = 0, reaper.CountTracks(0) - 1 do reaper.SetTrackSelected(reaper.GetTrack(0, t), false) end
      reaper.SetTrackSelected(reaper.GetMasterTrack(0), false)
    end
    for k = a, b do
      local s = S.slots[k]
      local t = s and s.guid and track_by_guid(s.guid)
      if t then reaper.SetTrackSelected(t, true) end
    end
    reaper.PreventUIRefresh(-1)
    return                                   -- the anchor stays, like REAPER
  end
  if is_ctrl() then reaper.SetTrackSelected(tr, not reaper.IsTrackSelected(tr)) else reaper.SetOnlyTrackSelected(tr) end
  S.sel_anchor = reaper.GetTrackGUID(tr)
end

---------------------------------------------------------------------
-- Pieces of a strip
---------------------------------------------------------------------
-- meters: gain share (wide) + input (slim), with the dB scale on the left
local SEG_PITCH, SEG_GAP = 6, 2   -- segmented meters (hardware-input strips): 4 px lit, 2 px gap

local function draw_meters(x, top, bot, d, segmented)
  local gain_w, in_w = 26, 6
  local gx = x + 24
  local ix = gx + gain_w + 5
  local h = bot - top
  local function gy(v) return top + h * (math.min(0, math.max(GAIN_FLOOR, v)) / GAIN_FLOOR) end
  local function iy(v) return top + h * (math.min(0, math.max(IN_FLOOR, v)) / IN_FLOOR) end

  rr(gx, top, gain_w, h, 4, COL.key, 0.55)
  rr(ix, top, in_w, h, 3, COL.key, 0.55)
  local _, th = text_w(font_label, "0")
  for _, t in ipairs({ 0, -3, -6, -10, -15, -20, -30 }) do
    local ty = math.floor(gy(t) + 0.5)
    ImGui.DrawList_AddLine(DL, gx - 4, ty, gx - 1, ty, rgba(COL.dim), 1)
    text_at(font_label, tostring(t), gx - 7, ty - th / 2, COL.dim, "right")
  end
  if d.gain_db > GAIN_FLOOR then
    local gtop = gy(d.gain_db)
    rr(gx, gtop, gain_w, bot - gtop, 4, ACCENT)
    rr(gx, gtop, gain_w, math.min(3, bot - gtop), 2, 0xFFFFFF, 0.35)  -- bright cap
  end
  if d.in_db > IN_FLOOR then
    local col = d.in_db > -1 and COL.clip or d.in_db > -6 and COL.note or COL.in_ok
    local itop = iy(d.in_db)
    rr(ix, itop, in_w, bot - itop, 3, col)
  end
  -- hardware input: cut the input meter into segments with gaps in the well colour, from the bottom up
  if segmented then
    local wc = rgba(COL.well)
    local gy0 = math.floor(bot + 0.5) - SEG_PITCH
    while gy0 > top + 2 do
      ImGui.DrawList_AddRectFilled(DL, ix, gy0, ix + in_w, gy0 + SEG_GAP, wc)
      gy0 = gy0 - SEG_PITCH
    end
  end
  return ix + in_w
end

-- track volume fader (REAPER's fader curve, like the Floating Mixer)
local function draw_fader(id, tr, cx, top, bot)
  local _, vol = reaper.GetTrackUIVolPan(tr)
  local p = pos_of(val2db(vol))
  local CAP_W, CAP_H = 28, 14
  local tt, tb = top + CAP_H / 2, bot - CAP_H / 2

  rr(cx - 2, top, 4, bot - top, 2, COL.key)
  local zy = math.floor(tb - pos_of(0) * (tb - tt) + 0.5)                  -- 0 dB line
  ImGui.DrawList_AddLine(DL, cx - 10, zy, cx + 10, zy, rgba(COL.dim), 1)

  local h = hit(id, cx - 16, top, 32, bot - top,
    "Track volume\nDrag: adjust  |  Shift: fine\nDouble-click / Alt-click: 0 dB")
  local nv, done = drag_value(id, h, p, 0, 1, pos_of(0), 1 / (tb - tt), 0.01)
  if nv then set_vol(tr, vol_of_pos(nv), done) p = nv end
  if drag[id] then p = drag[id] end   -- while held, the cap follows the mouse even with automation playing

  local vy = tb - p * (tb - tt)
  rr(cx - CAP_W / 2, vy - CAP_H / 2 + 1, CAP_W, CAP_H, 4, COL.keyedge)
  rr(cx - CAP_W / 2, vy - CAP_H / 2, CAP_W, CAP_H, 4, (h.hov or h.act) and COL.keyhov or COL.key)
  ImGui.DrawList_AddLine(DL, cx - CAP_W / 2 + 4, vy, cx + CAP_W / 2 - 4, vy, rgba(COL.text), 1.5)
  return val2db(vol_of_pos(p))
end

-- weight: vertical, fills from the centre (0 dB) up or down
local function draw_weight(id, tr, fx, pi, cx, top, bot, weight)
  local h = hit(id, cx - 12, top, 24, bot - top,
    "Weight: bias this mic in the gain sharing\nDrag: adjust  |  Shift: fine\nDouble-click / Alt-click: 0 dB")
  local nv, done = drag_value(id, h, weight, -12, 12, 0, 24 / (bot - top), 0.5)
  if nv then
    nv = math.floor(nv * 2 + 0.5) / 2
    if nv ~= weight then reaper.TrackFX_SetParam(tr, fx, pi, nv) end
    weight = nv
  end
  if drag[id] then weight = math.floor(drag[id] * 2 + 0.5) / 2 end

  rr(cx - 4, top, 8, bot - top, 4, COL.key, 0.55)
  local my = (top + bot) / 2
  local vy = bot - (weight + 12) / 24 * (bot - top)
  if weight ~= 0 then
    local a, b = math.min(my, vy), math.max(my, vy)
    rr(cx - 4, a, 8, b - a, 3, ACCENT, (h.hov or h.act) and 0.85 or 0.65)
  end
  ImGui.DrawList_AddLine(DL, cx - 7, my, cx + 7, my, rgba(COL.dim), 1)
  rr(cx - 9, vy - 3, 18, 6, 3, (h.hov or h.act) and COL.text or 0xC8C8D0)
  return weight
end

local function group_chip(x, y, tr, fx, pi, group)
  local label = "G" .. group
  local w = text_w(font_label, label) + 22
  local h = hit("##grp", x - w, y, w, 18, "Group: channels only share gain within their group")
  rr(x - w, y, w, 18, 9, ACCENT, h.hov and 0.3 or 0.18)
  ImGui.DrawList_AddCircleFilled(DL, x - w + 9, y + 9, 3.5, rgba(ACCENT))
  -- centred by the font's real line height (it differs per OS font: Segoe UI sat low with a fixed offset)
  local _, th = text_w(font_label, label)
  text_at(font_label, label, x - w + 16, y + (18 - th) / 2, ACCENT)
  if h.click then ImGui.OpenPopup(ctx, "group") end
  if ImGui.BeginPopup(ctx, "group") then
    for g = 1, N_GROUPS do
      if ImGui.Selectable(ctx, "      Group " .. g, g == group, 0, 110, 0) then reaper.TrackFX_SetParam(tr, fx, pi, g) end
      local mx1, my1 = ImGui.GetItemRectMin(ctx)
      local _, my2 = ImGui.GetItemRectMax(ctx)
      ImGui.DrawList_AddCircleFilled(ImGui.GetWindowDrawList(ctx), mx1 + 9, (my1 + my2) / 2, 4, rgba(GROUP_COL[g]))
    end
    ImGui.EndPopup(ctx)
  end
  return w
end

-- plain selector chip (input / output): same height and rounding as the group chip
local function chip_width(label) return text_w(font_label, label) + 16 end

local function plain_chip(id, popup, x, y, label, tip, off)
  local w = chip_width(label)
  local open = ImGui.IsPopupOpen(ctx, popup)
  local h = hit(id, x, y, w, 18, tip .. "\nClick to change")
  rr(x, y, w, 18, 9, (h.hov or open) and COL.keyhov or COL.key)
  local col = (h.hov or open) and COL.text or off and COL.dim or COL.muted
  local _, th = text_w(font_label, label)
  text_at(font_label, label, x + w / 2, y + (18 - th) / 2, col, "center")
  if h.click then ImGui.OpenPopup(ctx, popup) end
  return w
end

-- input chip, left edge at x: No input / a mono hardware input
local function input_chip(x, y, tr, created)
  local inp = reaper.GetMediaTrackInfo_Value(tr, "I_RECINPUT")
  local cur = (inp >= 0 and inp < 1024) and math.floor(inp) or nil
  local tip
  if inp < 0 then tip = "Input: none"
  elseif cur then
    local name = reaper.GetInputChannelName(cur) or ""
    tip = "Input: hardware input " .. (cur + 1) .. ((name ~= "") and ("  (" .. name .. ")") or "")
  else tip = "Input: " .. input_label(tr) end
  local w = plain_chip("##in", "input", x, y, input_label(tr), tip, inp < 0)
  if ImGui.BeginPopup(ctx, "input") then
    if ImGui.MenuItem(ctx, "No input", nil, inp < 0) and inp >= 0 then set_input(tr, -1, created) end
    ImGui.Separator(ctx)
    local n = reaper.GetNumAudioInputs()
    if n == 0 then ImGui.TextColored(ctx, rgba(COL.muted), "No audio inputs (check Audio device settings)") end
    local used = used_inputs()
    for ch = 0, n - 1 do
      local name = reaper.GetInputChannelName(ch) or ""
      local taken = used[ch] and ch ~= cur
      local label = string.format("%2d   %s%s", ch + 1, name, taken and "   (in use)" or "")
      if taken then ImGui.PushStyleColor(ctx, ImGui.Col_Text, rgba(COL.in_use)) end
      local picked = ImGui.MenuItem(ctx, label, nil, ch == cur)
      if taken then ImGui.PopStyleColor(ctx) end
      if picked and ch ~= cur then set_input(tr, ch, created) end
    end
    ImGui.EndPopup(ctx)
  end
  return w
end

local function output_label(out)
  if out == "main" then return "Main" elseif out == "none" then return "None" end
  return "Out " .. (out + 1)
end

-- output chip, centred on cx: Main mix / a hardware output / None
local function output_chip(cx, y, tr)
  local out = track_output(tr)
  local label, tip = output_label(out)
  if out == "main" then
    tip = "Output: Main mix"
  elseif out == "none" then
    tip = "Output: None (not heard anywhere)"
  else
    local name = reaper.GetOutputChannelName(out) or ""
    tip = "Output: hardware output " .. (out + 1) .. ((name ~= "") and ("  (" .. name .. ")") or "")
  end
  plain_chip("##out", "output", math.floor(cx - chip_width(label) / 2 + 0.5), y, label, tip, out == "none")
  if ImGui.BeginPopup(ctx, "output") then
    if ImGui.MenuItem(ctx, "Main mix", nil, out == "main") and out ~= "main" then set_output(tr, "main") end
    if ImGui.BeginMenu(ctx, "Hardware output") then
      local n = reaper.GetNumAudioOutputs()
      if n == 0 then ImGui.TextColored(ctx, rgba(COL.muted), "No audio outputs (check Audio device settings)") end
      for ch = 0, n - 1 do
        local name = reaper.GetOutputChannelName(ch) or ""
        if ImGui.MenuItem(ctx, string.format("%2d   %s", ch + 1, name), nil, out == ch) and out ~= ch then
          set_output(tr, ch)
        end
      end
      ImGui.EndMenu(ctx)
    end
    if ImGui.MenuItem(ctx, "None", nil, out == "none") and out ~= "none" then set_output(tr, "none") end
    ImGui.EndPopup(ctx)
  end
end

---------------------------------------------------------------------
-- Reordering: drag a strip onto another; an accent bar shows where it lands
---------------------------------------------------------------------
local DND_TYPE = "DANIEL_AUTOMIXER_SLOT"

-- the strips that move with strip `from`: all strips whose track is selected when the dragged
-- strip is one of them, otherwise just the dragged strip. Returns a set and a count.
local function moving_set(from)
  local function sel(k)
    local s = S.slots[k]
    local t = s and s.guid and track_by_guid(s.guid)
    return t and reaper.IsTrackSelected(t)
  end
  local set, n = {}, 0
  if sel(from) then
    for k = 1, #S.slots do if sel(k) then set[k] = true n = n + 1 end end
  end
  if n == 0 then set[from] = true n = 1 end
  return set, n
end

local function card_dnd(i, x, y, label)
  if ImGui.BeginDragDropSource(ctx) then
    ImGui.SetDragDropPayload(ctx, DND_TYPE, tostring(i))
    local _, n = moving_set(i)
    ImGui.Text(ctx, (n > 1) and ("Move  " .. n .. " strips") or ("Move  " .. label))
    ImGui.EndDragDropSource(ctx)
  end
  if ImGui.BeginDragDropTarget(ctx) then
    local ok, payload = ImGui.AcceptDragDropPayload(ctx, DND_TYPE, nil,
      ImGui.DragDropFlags_AcceptBeforeDelivery | ImGui.DragDropFlags_AcceptNoDrawDefaultRect)
    local from = ok and tonumber(payload)
    if from and not moving_set(from)[i] then   -- can't drop onto a strip that's moving itself
      local bx = (from < i) and (x + SW + GAP / 2 - 1.5) or (x - GAP / 2 - 1.5)
      rr(bx, y + 6, 3, SH - 12, 1.5, ACCENT)
      if ImGui.IsMouseReleased(ctx, ImGui.MouseButton_Left) then S.pending_move = { from, i } end
    end
    ImGui.EndDragDropTarget(ctx)
  end
end

---------------------------------------------------------------------
-- Strips
---------------------------------------------------------------------
-- the lists behind "Hardware input" and "Existing track"; pick(fn, arg) is called with the choice
local function input_items(pick)
  local n = reaper.GetNumAudioInputs()
  if n == 0 then ImGui.TextColored(ctx, rgba(COL.muted), "No audio inputs (check Audio device settings)") end
  local used = used_inputs()
  for ch = 0, n - 1 do
    local name = reaper.GetInputChannelName(ch) or ""
    local label = string.format("%2d   %s%s", ch + 1, name, used[ch] and "   (in use)" or "")
    if used[ch] then ImGui.PushStyleColor(ctx, ImGui.Col_Text, rgba(COL.in_use)) end
    local picked = ImGui.MenuItem(ctx, label)
    if used[ch] then ImGui.PopStyleColor(ctx) end
    if picked then pick(assign_input, ch) end
  end
end

local function track_items(pick)
  local any = false
  for t = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, t)
    local name = track_name(tr)
    if name ~= HIDDEN_TRACK and not find_fx(tr) then
      any = true
      if ImGui.MenuItem(ctx, string.format("%2d   %s", t + 1, name)) then pick(assign_track, tr) end
    end
  end
  if not any then ImGui.TextColored(ctx, rgba(COL.muted), "No tracks available") end
end

local function source_menu_items(slot)
  local function pick(fn, arg) fn(slot, arg) end
  if ImGui.BeginMenu(ctx, "Hardware input") then input_items(pick) ImGui.EndMenu(ctx) end
  if ImGui.BeginMenu(ctx, "Existing track") then track_items(pick) ImGui.EndMenu(ctx) end
end

-- from the side column: fill the first empty slot, or add a new one at the end
local function pick_new(fn, arg)
  for _, sl in ipairs(S.slots) do
    if not sl.guid then fn(sl, arg) return end
  end
  local sl = {}
  fn(sl, arg)
  if sl.guid then
    S.slots[#S.slots + 1] = sl
    save_state()
  end
end

local function empty_strip(i, slot, x, y)
  rr(x, y, SW, SH, 10, COL.panel, 0.55)
  ImGui.DrawList_AddRect(DL, x + 0.5, y + 0.5, x + SW - 0.5, y + SH - 0.5, rgba(COL.line), 10, 0, 1)
  keycap(x + 12, y + 12, tostring(i))
  if close_x("##close", x + SW - 22, y + 18) then remove_slot(i, false) return end

  -- the plus: click for the source menu
  local cx, cy = x + SW / 2, y + SH / 2 - 20
  local h = hit("##plus", cx - 30, cy - 30, 60, 60, "Choose a source")
  local open = ImGui.IsPopupOpen(ctx, "source")
  rr(cx - 26, cy - 26, 52, 52, 26, ACCENT, (h.hov or open) and 0.32 or 0.16)
  ImGui.DrawList_AddCircle(DL, cx, cy, 26, rgba(ACCENT, (h.hov or open) and 1 or 0.7), 0, 1.5)
  ImGui.DrawList_AddLine(DL, cx - 9, cy, cx + 9, cy, rgba(ACCENT), 2)
  ImGui.DrawList_AddLine(DL, cx, cy - 9, cx, cy + 9, rgba(ACCENT), 2)
  text_at(font, "Empty slot", cx, cy + 42, COL.muted, "center")
  text_at(font_small, "Click + to choose a source", cx, cy + 62, COL.dim, "center")
  if h.click then ImGui.OpenPopup(ctx, "source") end
  if ImGui.BeginPopup(ctx, "source") then
    source_menu_items(slot)
    ImGui.EndPopup(ctx)
  end

  -- the rest of the card: drag to move, drop target
  hit("##select", x, y, SW, SH)
  card_dnd(i, x, y, "Empty slot")
end

local function channel_strip(i, slot, tr, x, y, now, dt)
  local fx = find_fx(tr)
  if not fx then return end
  local P = params_of(tr, fx)
  if not (P.weight and P.group and P.slot) then return end
  -- always automatic: put back any version-1 instance left in Manual / Mute
  if P.mode and math.floor(reaper.TrackFX_GetParam(tr, fx, P.mode) + 0.5) ~= 0 then reaper.TrackFX_SetParam(tr, fx, P.mode, 0) end
  -- the shared settings from the settings popover
  local function apply(pk, v) if P[pk] and math.abs(reaper.TrackFX_GetParam(tr, fx, P[pk]) - v) > 0.001 then reaper.TrackFX_SetParam(tr, fx, P[pk], v) end end
  apply("hold", S.cfg.hold) apply("thr", S.cfg.thr) apply("rel", S.cfg.rel)
  local slot_idx = math.floor(reaper.TrackFX_GetParam(tr, fx, P.slot) + 0.5)
  local base = (slot_idx >= 0) and (16 + slot_idx * 16) or nil
  local age = base and (now - reaper.gmem_read(base + 1)) or 99
  local online = age < 0.5
  local muted = reaper.GetMediaTrackInfo_Value(tr, "B_MUTE") == 1
  local enabled = reaper.TrackFX_GetEnabled(tr, fx)
  local group = math.floor(reaper.TrackFX_GetParam(tr, fx, P.group) + 0.5)
  if group < 1 or group > N_GROUPS then                -- older setups could use groups 5-8
    group = math.max(1, math.min(N_GROUPS, group))
    reaper.TrackFX_SetParam(tr, fx, P.group, group)
  end
  ACCENT = GROUP_COL[group]   -- this strip in its group's colour (put back to blue after the strip)
  local weight = reaper.TrackFX_GetParam(tr, fx, P.weight)

  -- muted tracks leave the gain sharing
  if base and online then reaper.gmem_write(base + 7, muted and 1 or 0) end

  -- meter values
  local d = S.disp[slot.guid]
  if not d then d = { in_db = -150, gain_db = -150 } S.disp[slot.guid] = d end
  if online and enabled then
    d.in_db = math.max(db(reaper.gmem_read(base + 6)), d.in_db - 24 * dt)
    local g = db(reaper.gmem_read(base + 5))
    -- display only (the audio isn't affected): rises in ~80 ms, falls in ~350 ms, so it reads calmly
    local tc = (g > d.gain_db) and 0.08 or 0.35
    d.gain_db = d.gain_db + (g - d.gain_db) * math.min(1, dt / tc)
  else
    d.in_db, d.gain_db = -150, -150
  end
  local holding = online and reaper.gmem_read(base + 11) > 0

  -- card
  local selected = reaper.IsTrackSelected(tr)
  rr(x, y, SW, SH, 10, selected and COL.panel_sel or COL.panel)
  if selected then
    ImGui.DrawList_AddRect(DL, x + 0.5, y + 0.5, x + SW - 0.5, y + SH - 0.5, rgba(ACCENT, 0.7), 10, 0, 1.5)
  end
  local ix, iw = x + 12, SW - 24

  -- header: number, name, close
  local kw = keycap(ix, y + 12, tostring(i), selected)
  local name_x = ix + kw + 8
  local name_w = x + SW - 26 - name_x
  if S.renaming == slot.guid then
    -- typing the new name right in place (like the Floating Mixer): Enter or click away keeps it, Esc cancels
    rr(name_x - 4, y + 10, name_w + 6, 24, 6, COL.bg)
    ImGui.DrawList_AddRect(DL, name_x - 4, y + 10, name_x + name_w + 2, y + 34, rgba(ACCENT), 6, 0, 1)
    ImGui.SetCursorScreenPos(ctx, name_x, y + 12)
    ImGui.PushFont(ctx, font)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 2)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x00000000)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0x00000000)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, 0x00000000)
    ImGui.PushStyleColor(ctx, ImGui.Col_TextSelectedBg, rgba(ACCENT, 0.45))
    ImGui.SetNextItemWidth(ctx, name_w - 2)
    if S.rename_focus then ImGui.SetKeyboardFocusHere(ctx) S.rename_focus = false end
    local enter, buf = ImGui.InputText(ctx, "##rename", S.name_buf,
      ImGui.InputTextFlags_EnterReturnsTrue | ImGui.InputTextFlags_AutoSelectAll)
    S.name_buf = buf
    local deact = ImGui.IsItemDeactivated(ctx)
    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopStyleVar(ctx, 2)
    ImGui.PopFont(ctx)
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
      S.renaming = nil
    elseif enter or deact then
      S.renaming = nil
      local _, old = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
      if buf ~= old then
        reaper.Undo_BeginBlock()
        reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", buf, true)
        reaper.Undo_EndBlock("Rename track", -1)
      end
    end
  else
    local nh = hit("##name", name_x, y + 10, name_w, 24,
      "Click: select (Shift: range, Cmd/Ctrl: toggle)\nDouble-click: rename\nDrag: move")
    if nh.dbl then
      local _, n = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
      S.renaming, S.name_buf, S.rename_focus = slot.guid, n, true
    elseif nh.click then
      select_click(i, tr)
    end
    card_dnd(i, x, y, track_name(tr))
    text_at(font, clip_text(font, track_name(tr), name_w), name_x, y + 14, COL.text)
  end
  if close_x("##close", x + SW - 22, y + 18) then
    remove_slot(i, slot.created)   -- created by the panel: delete the track; otherwise just remove the plugin
    return
  end

  -- source and group
  -- input (left) | output (middle) | group (right); the output sits centred in the space
  -- between the other two so the gaps on both sides look equal
  local inw = input_chip(ix, y + 41, tr, slot.created)
  local gw = group_chip(ix + iw, y + 41, tr, fx, P.group, group)
  output_chip(((ix + inw) + (ix + iw - gw)) / 2, y + 41, tr)

  -- control well: meters | fader | weight
  local wy, wh = y + 68, METER_H
  rr(ix, wy, iw, wh, 8, COL.well)
  local top, bot = wy + 26, wy + wh - 26
  local meters_end = draw_meters(ix + 6, top, bot, d, slot.created)   -- segmented = hardware input
  local weight_cx_ = ix + iw - 18
  local fader_cx = math.floor((meters_end + weight_cx_ - 12) / 2 + 0.5)   -- centred in the space left
  local weight_cx = ix + iw - 18
  text_at(font_label, "GAIN", ix + 6 + 24 + 13, wy + 8, COL.dim, "center")
  text_at(font_label, "VOL", fader_cx, wy + 8, COL.dim, "center")
  text_at(font_label, "WT", weight_cx, wy + 8, COL.dim, "center")
  local vol_db = draw_fader("##fader" .. slot.guid, tr, fader_cx, top, bot)
  weight = draw_weight("##weight" .. slot.guid, tr, fx, P.weight, weight_cx, top, bot, weight)
  text_at(font_label, fmt_vol(vol_db), fader_cx, bot + 8, COL.muted, "center")
  text_at(font_label, (weight == 0) and "0" or string.format("%+.1f", weight), weight_cx, bot + 8, COL.muted, "center")

  -- big gain-share readout
  local ry = wy + wh + 12
  local num = (online and enabled and d.gain_db > -99) and string.format("%.1f", d.gain_db) or "--"
  local nw = text_w(font_big, num)
  local uw = text_w(font_small, " dB")
  local rx = x + (SW - nw - uw) / 2
  text_at(font_big, num, rx, ry, COL.text)
  text_at(font_small, " dB", rx + nw, ry + 11, COL.muted)

  -- status
  -- status line: blue = open, desaturated blue = ducked (in between while sharing), red = muted
  -- (a muted track may stop processing, so "muted" is checked before "offline")
  local bar, tip
  if muted then bar, tip = COL.clip, "Track muted"
  elseif not enabled then bar, tip = COL.key, "Plugin bypassed"
  elseif not online then bar, tip = COL.key, "Offline (plugin not running)"
  else
    local t = math.max(0, math.min(1, (d.gain_db + 15) / 12))    -- -15 dB ducked .. -3 dB open
    bar = mix(mix(ACCENT, COL.key, 0.85), ACCENT, t)   -- ducked = a greyed-out version of the group colour
    tip = (t >= 1) and (holding and "Open (holding last mic)" or "Open")
       or (t <= 0) and "Ducked" or "Sharing"
  end
  draw_status(d, x + SW / 2, ry + 42, bar, tip, dt)

  -- the rest of the card selects the track (submitted last, so the controls above win)
  local bg = hit("##select", x, y, SW, SH, "Click: select (Shift: range, Cmd/Ctrl: toggle)\nDrag: move")
  if bg.click then select_click(i, tr) end
  card_dnd(i, x, y, track_name(tr))
end

-- horizontal drag (same gestures as the fader: Shift = fine, double-click / Alt-click = reset, wheel)
local function hdrag_value(id, h, v, lo, hi, reset, per_dx, wheel_step)
  local nv, done
  if h.activated then drag[id] = v if is_alt() then drag[id] = reset nv = reset end end
  if h.dbl then drag[id] = reset nv = reset end
  if h.act and drag[id] then
    local dx = ImGui.GetMouseDelta(ctx)
    local d = dx * per_dx * (is_fine() and 0.1 or 1)
    if d ~= 0 then drag[id] = clamp(drag[id] + d, lo, hi) nv = drag[id] end
  end
  if h.deactivated and drag[id] then nv = drag[id] done = true drag[id] = nil end
  if h.hov and not h.act then
    local w = ImGui.GetMouseWheel(ctx)
    if w ~= 0 then nv = clamp(v + w * wheel_step, lo, hi) done = true end
  end
  return nv, done
end

local function setting_slider(id, x, y, w, label, v, lo, hi, def, step, fmt, enabled)
  text_at(font_small, label, x, y, enabled and COL.text or COL.dim)
  text_at(font_label, string.format(fmt, v), x + w, y + 1, enabled and COL.muted or COL.dim, "right")
  local by = y + 22
  local h = hit(id, x - 4, by - 6, w + 8, 20, "Drag: adjust  |  Shift: fine\nDouble-click / Alt-click: default")
  if enabled then
    local nv = hdrag_value(id, h, v, lo, hi, def, (hi - lo) / w, step)
    if nv then v = math.floor(nv / step + 0.5) * step end
    if drag[id] then v = math.floor(drag[id] / step + 0.5) * step end
  end
  local t = (v - lo) / (hi - lo)
  rr(x, by, w, 8, 4, COL.key, 0.7)
  if t > 0 then rr(x, by, math.max(8, w * t), 8, 4, enabled and ACCENT or COL.keyedge, enabled and ((h.hov or h.act) and 1 or 0.85) or 1) end
  local kx = x + w * t
  ImGui.DrawList_AddCircleFilled(DL, kx, by + 4, 7, rgba(enabled and ((h.hov or h.act) and 0xFFFFFF or COL.text) or COL.dim))
  return v
end

local function switch(id, x, y, on)
  local h = hit(id, x, y, 36, 20)
  rr(x, y, 36, 20, 10, on and ACCENT or COL.key, (h.hov and not on) and 1 or (on and 1 or 0.8))
  ImGui.DrawList_AddCircleFilled(DL, on and (x + 26) or (x + 10), y + 10, 7, rgba(0xFFFFFF, on and 1 or 0.75))
  return h.click
end

-- support link
local SUPPORT_URL = "ko-fi.com/danielkharrat"
local HEART_COL = 0xF2788A
local function heart(cx, cy, col)
  ImGui.DrawList_AddCircleFilled(DL, cx - 2.6, cy - 1.2, 3.1, col)
  ImGui.DrawList_AddCircleFilled(DL, cx + 2.6, cy - 1.2, 3.1, col)
  ImGui.DrawList_AddTriangleFilled(DL, cx - 5.6, cy - 0.2, cx + 5.6, cy - 0.2, cx, cy + 5.6, col)
end

local function open_url(url)
  if reaper.CF_ShellExecute then reaper.CF_ShellExecute(url) return end   -- SWS
  local os_name = reaper.GetOS()
  if os_name:find("Win") then os.execute('start "" "' .. url .. '"')
  elseif os_name:find("OSX") or os_name:find("mac") then os.execute('open "' .. url .. '"')
  else os.execute('xdg-open "' .. url .. '" &') end
end

local function settings_popup()
  if not ImGui.BeginPopup(ctx, "settings") then return end
  local old_dl = DL
  DL = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local W = 240
  local c = S.cfg
  local changed = false

  text_at(font, "Settings", x, y, COL.text)
  text_at(font_small, "For all channels", x, y + 20, COL.dim)

  local ry = y + 52
  text_at(font_small, "Last mic hold", x, ry + 2, COL.text)
  if switch("##hold", x + W - 36, ry, c.hold == 1) then c.hold = (c.hold == 1) and 0 or 1 changed = true end
  text_at(font_label, "Keeps the last talker open when everyone stops", x, ry + 24, COL.dim)

  local thr = setting_slider("##thr", x, ry + 52, W, "Hold below", c.thr, -80, -20, CFG_DEFAULT.thr, 1, "%d dBFS", c.hold == 1)
  if thr ~= c.thr then c.thr = thr changed = true end
  local rel = setting_slider("##rel", x, ry + 100, W, "Release", c.rel, 20, 600, CFG_DEFAULT.rel, 5, "%d ms", true)
  if rel ~= c.rel then c.rel = rel changed = true end

  local fy = ry + 150
  ImGui.DrawList_AddLine(DL, x, fy, x + W, fy, rgba(COL.line), 1)
  local rh = hit("##reset", x, fy + 8, text_w(font_label, "Reset to defaults") + 4, 16)
  text_at(font_label, "Reset to defaults", x, fy + 10, rh.hov and COL.text or COL.muted)
  if rh.click then
    c.hold, c.thr, c.rel = CFG_DEFAULT.hold, CFG_DEFAULT.thr, CFG_DEFAULT.rel
    changed = true
  end


  if changed then save_cfg() end
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.Dummy(ctx, W, fy + 30 - y)
  DL = old_dl
  ImGui.EndPopup(ctx)
end

local function gear(cx, cy, col)
  for k = 0, 7 do
    local a = k * math.pi / 4
    ImGui.DrawList_AddLine(DL, cx + math.cos(a) * 5, cy + math.sin(a) * 5, cx + math.cos(a) * 8, cy + math.sin(a) * 8, col, 2.5)
  end
  ImGui.DrawList_AddCircle(DL, cx, cy, 5.5, col, 0, 2)
end

-- side column icons
local function icon_input(cx, cy, col)      -- microphone
  ImGui.DrawList_AddRectFilled(DL, cx - 4, cy - 11, cx + 4, cy + 2, col, 4)
  ImGui.DrawList_AddBezierQuadratic(DL, cx - 7, cy - 2, cx - 7, cy + 7, cx, cy + 7, col, 1.6)
  ImGui.DrawList_AddBezierQuadratic(DL, cx + 7, cy - 2, cx + 7, cy + 7, cx, cy + 7, col, 1.6)
  ImGui.DrawList_AddLine(DL, cx, cy + 7, cx, cy + 11, col, 1.6)
  ImGui.DrawList_AddLine(DL, cx - 4, cy + 11, cx + 4, cy + 11, col, 1.6)
end

local function icon_track(cx, cy, col)      -- track lanes
  for k = -1, 1 do
    ImGui.DrawList_AddRectFilled(DL, cx - 8, cy + k * 7 - 2, cx + 8, cy + k * 7 + 2, col, 2)
  end
end

local function add_badge(cx, cy, col)       -- small + in the corner of an icon
  ImGui.DrawList_AddCircleFilled(DL, cx, cy, 5.5, rgba(COL.bg))
  ImGui.DrawList_AddLine(DL, cx - 3, cy, cx + 3, cy, col, 1.6)
  ImGui.DrawList_AddLine(DL, cx, cy - 3, cx, cy + 3, col, 1.6)
end

local function side_button(id, x, y, w, h, popup, icon, tip)
  local hh = hit(id, x, y, w, h, tip)
  local open = ImGui.IsPopupOpen(ctx, popup)
  if hh.hov or open then rr(x + 3, y, w - 6, h, 8, ACCENT, open and 0.28 or 0.18) end
  local col = rgba((hh.hov or open) and ACCENT or COL.muted)
  icon(x + w / 2, y + h / 2, col)
  add_badge(x + w / 2 + 9, y + h / 2 + 9, col)
  if hh.click then ImGui.OpenPopup(ctx, popup) end
end

-- the side column: settings at the top, then add a hardware input / add a track
local function plus_strip(x, y)
  rr(x, y, PLUS_W, SH, 10, COL.panel, 0.4)

  -- support (Ko-fi) at the very top, in its own colour so it's easy to spot
  local sh = hit("##support", x, y, PLUS_W, 38, "Support the Auto Mixer: buy me a coffee\n" .. SUPPORT_URL)
  if sh.hov then rr(x + 3, y + 3, PLUS_W - 6, 32, 8, HEART_COL, 0.18) end
  heart(x + PLUS_W / 2, y + 19, rgba(HEART_COL, sh.hov and 1 or 0.8))
  if sh.click then open_url("https://" .. SUPPORT_URL) end

  -- settings below it
  local gy = y + 40
  local gh = hit("##settings", x, gy, PLUS_W, 38, "Settings")
  local open = ImGui.IsPopupOpen(ctx, "settings")
  if gh.hov or open then rr(x + 3, gy + 3, PLUS_W - 6, 32, 8, COL.panel, 0.9) end
  gear(x + PLUS_W / 2, gy + 19, rgba((gh.hov or open) and ACCENT or COL.muted))
  if gh.click then ImGui.OpenPopup(ctx, "settings") end
  settings_popup()

  local my = y + SH / 2
  side_button("##add_in", x, my - 50, PLUS_W, 44, "add_input", icon_input, "Add a hardware input")
  side_button("##add_tr", x, my + 6, PLUS_W, 44, "add_track", icon_track, "Add an existing track")

  if ImGui.BeginPopup(ctx, "add_input") then input_items(pick_new) ImGui.EndPopup(ctx) end
  if ImGui.BeginPopup(ctx, "add_track") then track_items(pick_new) ImGui.EndPopup(ctx) end
end

---------------------------------------------------------------------
-- Window
---------------------------------------------------------------------
local function desired_size()
  local vp = ImGui.GetMainViewport(ctx)
  local vw = select(1, ImGui.Viewport_GetWorkSize(vp))
  local n = math.max(1, #S.slots)
  local max_cols = math.max(1, math.floor((vw * 0.92 - 2 * PAD - PLUS_W) / (SW + GAP)))
  local cols = math.min(n, max_cols)
  local rows = math.ceil(n / cols)
  local w = 2 * PAD + cols * (SW + GAP) + PLUS_W
  local h = ImGui.GetFrameHeight(ctx) + 2 * PAD + rows * SH + (rows - 1) * GAP
  return w + 2, h + 2
end

local function min_size()
  return 2 * PAD + SW_MIN + GAP + PLUS_W + 2, ImGui.GetFrameHeight(ctx) + 2 * PAD + SH_MIN + 2
end

-- never wider than all the strips in one row
local function max_width()
  local n = math.max(1, #S.slots)
  return 2 * PAD + n * (SW_MIN + GAP) + PLUS_W + 14   -- + room for a vertical scrollbar
end

local function strips(now, dt)
  local ox, oy = ImGui.GetCursorScreenPos(ctx)
  local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)

  -- only shown when something went wrong (click to dismiss)
  if S.error_msg then
    local h = hit("##err", ox, oy, avail_w, 22)
    rr(ox, oy, avail_w, 22, 6, COL.note, 0.14)
    text_at(font_small, S.error_msg, ox + 10, oy + 4, COL.note)
    if h.click then S.error_msg = nil end
    oy, avail_h = oy + 28, avail_h - 28
  end

  -- strips keep their width: as many columns as fit (narrower window = more rows);
  -- the height is shared, so a taller window gives taller meters and faders
  local n = #S.slots
  local cols = math.max(1, math.floor((avail_w - PLUS_W) / (SW_MIN + GAP)))
  cols = math.min(cols, math.max(1, n))
  SW = SW_MIN
  local rows = math.max(1, math.ceil(n / cols))
  SH = math.floor(math.max(SH_MIN, (avail_h - (rows - 1) * GAP) / rows))
  METER_H = SH - METER_FIXED

  local i = 1
  while i <= #S.slots do
    local slot = S.slots[i]
    local count_before = #S.slots
    local sx = ox + ((i - 1) % cols) * (SW + GAP)
    local sy = oy + math.floor((i - 1) / cols) * (SH + GAP)
    local tr = slot.guid and track_by_guid(slot.guid)
    ImGui.PushID(ctx, slot.guid or ("empty" .. i))
    if tr then channel_strip(i, slot, tr, sx, sy, now, dt) else empty_strip(i, slot, sx, sy) end
    ACCENT = BLUE
    ImGui.PopID(ctx)
    if #S.slots == count_before then i = i + 1 end -- a removed slot shifts the rest down
  end
  -- the + column sits after the last strip (each row keeps room for it)
  local k = #S.slots
  local prow = (k > 0) and math.floor((k - 1) / cols) or 0
  local pcol = (k > 0) and ((k - 1) % cols + 1) or 0
  plus_strip(ox + pcol * (SW + GAP), oy + prow * (SH + GAP))

  if S.pending_move then
    local from, to = S.pending_move[1], S.pending_move[2]
    S.pending_move = nil
    if S.slots[from] and S.slots[to] then
      -- move the dragged strip, plus every other selected strip with it, as one block in their
      -- current order: after the target when dragging right, before it when dragging left
      local set = moving_set(from)
      if not set[to] then
        local target = S.slots[to]
        local block, rest = {}, {}
        for k, s in ipairs(S.slots) do
          if set[k] then block[#block + 1] = s else rest[#rest + 1] = s end
        end
        local at
        for k, s in ipairs(rest) do if s == target then at = k break end end
        if from < to then at = at + 1 end
        for k, s in ipairs(block) do table.insert(rest, at + k - 1, s) end
        S.slots = rest
        save_state()
      end
    end
  end

  -- reserve the space so the window can scroll if it's smaller than the content
  ImGui.SetCursorScreenPos(ctx, ox, oy)
  ImGui.Dummy(ctx, math.max(1, cols * (SW + GAP) + PLUS_W), rows * SH + (rows - 1) * GAP)
end

local function push_style()
  local c = {
    { ImGui.Col_WindowBg, rgba(COL.bg) }, { ImGui.Col_PopupBg, rgba(COL.panel) },
    { ImGui.Col_TitleBg, rgba(COL.bg) }, { ImGui.Col_TitleBgActive, rgba(0x1D1D22) },
    { ImGui.Col_TitleBgCollapsed, rgba(COL.bg) },
    { ImGui.Col_Text, rgba(COL.text) }, { ImGui.Col_TextDisabled, rgba(COL.muted) },
    { ImGui.Col_Header, rgba(COL.key) }, { ImGui.Col_HeaderHovered, rgba(COL.keyhov) },
    { ImGui.Col_HeaderActive, rgba(COL.keyedge) },
    { ImGui.Col_Border, rgba(COL.line) }, { ImGui.Col_Separator, rgba(COL.line) },
    { ImGui.Col_ScrollbarBg, rgba(COL.bg) }, { ImGui.Col_ScrollbarGrab, rgba(COL.key) },
    { ImGui.Col_ScrollbarGrabHovered, rgba(COL.keyhov) }, { ImGui.Col_ScrollbarGrabActive, rgba(COL.keyedge) },
    { ImGui.Col_ModalWindowDimBg, 0x00000066 },
  }
  for _, p in ipairs(c) do ImGui.PushStyleColor(ctx, p[1], p[2]) end
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, PAD, PAD)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 6, 4)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 6)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_PopupRounding, 8)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowBorderSize, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_PopupBorderSize, 1)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 6, 4)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ScrollbarSize, 10)
  return #c, 9
end

local function loop()
  local now = reaper.time_precise()
  local dt = math.min(0.2, now - S.last_time)
  S.last_time = now

  local proj = reaper.EnumProjects(-1)
  if proj ~= S.proj then S.proj = proj load_state() S.disp = {} S.last_scan = 0 end
  if now - S.last_scan > 0.3 then scan() S.last_scan = now end

  if #S.slots ~= S.last_count then S.want_resize = true S.last_count = #S.slots end

  local ncol, nvar = push_style()
  ImGui.PushFont(ctx, font)
  -- dock / undock asked for from the right-click menu (or remembered from last time)
  if S.dock_req then
    ImGui.SetNextWindowDockID(ctx, S.dock_req)
    if S.dock_req == 0 then S.want_resize = true end     -- undocked: back to its natural size
    S.dock_req = nil
  end
  if not S.docked then
    if S.want_resize then
      local w, h = desired_size()
      ImGui.SetNextWindowSize(ctx, w, h, ImGui.Cond_Always)
      S.want_resize = false
    end
    local min_w, min_h = min_size()
    ImGui.SetNextWindowSizeConstraints(ctx, min_w, min_h, math.max(min_w, max_width()), 100000)
  end
  local visible, open = ImGui.Begin(ctx, SCRIPT_NAME, true, ImGui.WindowFlags_NoCollapse)
  if visible then
    local docked = ImGui.IsWindowDocked(ctx)
    if docked ~= S.docked then reaper.SetExtState(EXT, "docked", docked and "1" or "0", true) end
    S.docked = docked
    if docked then
      local id = ImGui.GetWindowDockID(ctx)
      if id < 0 then reaper.SetExtState(EXT, "dock", tostring(id), true) end   -- remember the docker
    end
    DL = ImGui.GetWindowDrawList(ctx)
    strips(now, dt)

    -- right-click the title bar or any empty space: Dock / Undock, Close
    if ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows)
       and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) and not ImGui.IsAnyItemHovered(ctx) then
      ImGui.OpenPopup(ctx, "window_menu")
    end
    if ImGui.BeginPopup(ctx, "window_menu") then
      if S.docked then
        if ImGui.MenuItem(ctx, "Undock window") then S.dock_req = 0 end
      elseif ImGui.MenuItem(ctx, "Dock window") then
        S.dock_req = tonumber(reaper.GetExtState(EXT, "dock")) or -1        -- the last docker used
      end
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, "Close window") then S.close_req = true end
      ImGui.EndPopup(ctx)
    end
    -- give keyboard focus back to REAPER after a click (unless typing)
    if reaper.JS_Window_SetFocus and ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows)
       and ImGui.IsMouseReleased(ctx, 0) and not ImGui.IsAnyItemActive(ctx) and not S.renaming
       and not ImGui.IsPopupOpen(ctx, "", ImGui.PopupFlags_AnyPopupId) then
      reaper.JS_Window_SetFocus(reaper.GetMainHwnd())
    end
    ImGui.End(ctx)
  end
  ImGui.PopFont(ctx)
  ImGui.PopStyleVar(ctx, nvar)
  ImGui.PopStyleColor(ctx, ncol)

  if S.close_req then open = false end
  if open then
    reaper.defer(loop)
  else
    S.closed_by_user = true   -- closed with the window's X (or Close window in the menu)
  end
end

-- (see "turn off" above)
reaper.atexit(function()
  set_visual_state(false)
  if S.closed_by_user then
    set_ini_flag(0)                               -- closed with X: stays closed
  else                                            -- stopped by running it again (or REAPER quitting)
    reaper.SetExtState(EXT, "stopped_at", tostring(reaper.time_precise()), false)
  end
end)

-- open docked if it was docked when last closed
if reaper.GetExtState(EXT, "docked") == "1" then
  S.dock_req = tonumber(reaper.GetExtState(EXT, "dock")) or -1
end

set_visual_state(true)
set_ini_flag(1)
reaper.defer(loop)
