-- Daniel_Always Recording.lua
-- Live waveform viewer + click-select + drag-to-anywhere for the paired
-- Daniel_Always Recording.jsfx. A plain gfx window has no automatic dock
-- menu, so this builds its own via gfx.showmenu() + gfx.dock().
--
-- TO DOCK: right-click anywhere in the window -> "Dock Window in Docker".
-- This is a custom menu built by this script (not a REAPER-native one) --
-- the dock state is then remembered and restored automatically next time
-- you run the script.
--
-- TO USE: click-drag inside the waveform to select a region. Release to fix
-- the selection. Click again, starting INSIDE that selection, and drag --
-- you're now carrying the clip. Release over any track/position in the
-- arrange view to drop it there.
--
-- Requires the SWS extension (for BR_GetMouseCursorContext*).
--
-- MULTIPLE PROJECTS OPEN AT ONCE: every project uses the SAME single
-- Daniel_Always Recording.jsfx file -- no numbering, no per-project setup.
-- This script keeps only the instance in your CURRENTLY FOCUSED project
-- turned on, and automatically switches every other open project's
-- instance off (TrackFX offline/bypass), so only one instance is ever
-- actually processing audio at a time and there's nothing left to collide
-- over the shared channel. Switching project tabs re-enables/disables
-- automatically within a fraction of a second.

-- TOOLBAR TOGGLE BUTTON: this script's own command ID/state is used so the
-- toolbar button lights up while running and turns off when closed. A
-- second press of the button (while already running) sets the toggle state
-- to 0 and exits immediately -- the ALREADY-RUNNING instance notices that
-- (checked once per loop) and shuts itself down, which is what actually
-- closes the window.
reaper.set_action_options(1)
local _, _, section_id, cmd_id = reaper.get_action_context()

-- Keeps the SEPARATE toolbar-toggle script's button + the shared ini file
-- in sync with this script's actual running state, no matter how THIS
-- script was launched (toolbar button, action list, keyboard shortcut,
-- startup action) -- so they can never show a different on/off state than
-- what's actually true.
local personal_settings = reaper.GetResourcePath() .. "/Personal Settings"
local toggle_file = personal_settings .. "/Toolbar_Toggles.ini"
local toggle_button_cmd_id = reaper.NamedCommandLookup("_RS1d334413686175f313d60578bea01a827ae4e954")

local function write_ini_value(value)
  reaper.RecursiveCreateDirectory(personal_settings, 0)
  local lines = {}
  local found = false
  local file = io.open(toggle_file, "r")
  if file then
    for line in file:lines() do
      if line:match("^Always_Recording=") then
        table.insert(lines, "Always_Recording=" .. tostring(value))
        found = true
      else
        table.insert(lines, line)
      end
    end
    file:close()
  end
  if not found then
    table.insert(lines, "Always_Recording=" .. tostring(value))
  end
  file = io.open(toggle_file, "w")
  if file then
    file:write(table.concat(lines, "\n"))
    file:write("\n")
    file:close()
  end
end

local function set_visual_state(on)
  local v = on and 1 or 0
  -- this script's own action (used internally for reentrancy handling)
  reaper.SetToggleCommandState(section_id, cmd_id, v)
  reaper.RefreshToolbar2(section_id, cmd_id)
  -- the actual visible toolbar button, bound to the separate toggle script
  if toggle_button_cmd_id and toggle_button_cmd_id ~= 0 then
    reaper.SetToggleCommandState(0, toggle_button_cmd_id, v)
    reaper.RefreshToolbar2(0, toggle_button_cmd_id)
  end
end

-- Use this ONLY for genuine, intentional on/off decisions (starting up, or
-- the deliberate "second press closes it" branch) -- it persists to the
-- ini file that the startup action reads. Do NOT call this from atexit:
-- REAPER quitting also fires atexit, and if that wrote 0 to the file, a
-- normal quit-while-on would wipe out the "relaunch me on next startup"
-- flag, which defeats the entire point of that file.
local function set_button_state(on)
  set_visual_state(on)
  write_ini_value(on and 1 or 0)
end

if reaper.GetToggleCommandStateEx(section_id, cmd_id) == 1 then
  -- already running elsewhere: this press means "turn it off"
  set_button_state(false)
  return
end
set_button_state(true)

local GMEM_NAME = "Daniel_Always_Recording"
reaper.gmem_attach(GMEM_NAME)

local DISP_BASE = 7
local EXT_SECTION = "AlwaysRecording_Display"

-- Checks one track's FX chains (normal insert chain, and the input/record
-- FX chain -- which is also how the master track's Monitor FX chain is
-- addressed) for an instance of Daniel_Always Recording.
local function scan_track_fx(track)
  local count = reaper.TrackFX_GetCount(track)
  for fi = 0, count - 1 do
    local ok, fxname = reaper.TrackFX_GetFXName(track, fi, "")
    if ok and fxname and fxname:match("Daniel_Always Recording") then
      return fi
    end
  end
  local rec_count = reaper.TrackFX_GetRecCount(track)
  for fi = 0, rec_count - 1 do
    local ok, fxname = reaper.TrackFX_GetFXName(track, 0x1000000 + fi, "")
    if ok and fxname and fxname:match("Daniel_Always Recording") then
      return 0x1000000 + fi
    end
  end
  return nil
end

-- Scans one project's tracks (including master, for Monitor FX) for a
-- track hosting Daniel_Always Recording, on any FX chain. Returns track,
-- fx_index or nil, nil if not found.
local function find_instance_in_project(proj)
  local master = reaper.GetMasterTrack(proj)
  local fx_idx = scan_track_fx(master)
  if fx_idx then return master, fx_idx end

  local track_count = reaper.CountTracks(proj)
  for ti = 0, track_count - 1 do
    local track = reaper.GetTrack(proj, ti)
    fx_idx = scan_track_fx(track)
    if fx_idx then return track, fx_idx end
  end
  return nil, nil
end

-- Walks every currently open project, turns the instance in the active one
-- ON and every other one OFF. Returns true if an instance was found (and
-- is now enabled) in the active project. Also remembers the active track
-- (the one hosting the enabled instance) for mono/stereo detection on drop.
local active_track = nil

local function manage_instances()
  local active_proj = reaper.EnumProjects(-1)
  local found_active = false
  active_track = nil
  local i = 0
  while true do
    local proj = reaper.EnumProjects(i)
    if not proj then break end
    local track, fx_idx = find_instance_in_project(proj)
    if track then
      local should_be_on = (proj == active_proj)
      local currently_offline = reaper.TrackFX_GetOffline(track, fx_idx)
      if should_be_on and currently_offline then
        reaper.TrackFX_SetOffline(track, fx_idx, false)
      elseif (not should_be_on) and (not currently_offline) then
        reaper.TrackFX_SetOffline(track, fx_idx, true)
      end
      if should_be_on then
        found_active = true
        active_track = track
      end
    end
    i = i + 1
  end
  return found_active
end

-- True if the host track's record input is a single mono channel rather
-- than a stereo pair (I_RECINPUT bit 1024 marks a stereo input pair). The
-- master track (used for Monitor FX) has no meaningful record input at
-- all, so it's always treated as stereo rather than misread as mono.
local function host_track_is_mono()
  if not active_track then return false end
  local track_num = reaper.GetMediaTrackInfo_Value(active_track, "IP_TRACKNUMBER")
  local is_master = track_num <= 0 -- -1 = master track, 0 = not found; either way, no real record input to read
  if is_master then return false end
  local rec_input = reaper.GetMediaTrackInfo_Value(active_track, "I_RECINPUT")
  if rec_input < 0 then return false end -- no input assigned; default to stereo
  if (rec_input & 4096) ~= 0 then return false end -- MIDI input; not applicable, default to stereo
  return (rec_input & 1024) == 0
end

local STATE_IDLE, STATE_SELECTING, STATE_CARRYING = 0, 1, 2
local state = STATE_IDLE
local sel_start, sel_end = nil, nil -- normalized 0..1 positions in the buffer
local last_mdown = false
local last_rdown = false

local function clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi else return v end
end

local function inside_selection(n)
  if not sel_start or not sel_end then return false end
  local a, b = sel_start, sel_end
  if a > b then a, b = b, a end
  return n >= a and n <= b
end

-- Clears [start, finish) on a track before dropping new audio into it --
-- deletes items fully inside the range, splits and removes the middle of
-- items that span across it, and trims items that only partially overlap
-- at one edge. This gives tape-style "overwrite", not overlap/blend.
local function clear_track_range(track, start, finish)
  local item_count = reaper.CountTrackMediaItems(track)
  for i = item_count - 1, 0, -1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = item_start + item_len

    if item_end > start and item_start < finish then
      if item_start >= start and item_end <= finish then
        -- fully inside the drop range: remove entirely
        reaper.DeleteTrackMediaItem(track, item)
      elseif item_start < start and item_end > finish then
        -- spans the whole range: split off both ends, delete the middle
        local right_part = reaper.SplitMediaItem(item, finish)
        local middle_part = reaper.SplitMediaItem(item, start)
        if middle_part then
          reaper.DeleteTrackMediaItem(track, middle_part)
        end
      elseif item_start < start then
        -- overlaps only the range's start: trim this item's tail back
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", start - item_start)
      else
        -- overlaps only the range's end: trim this item's head forward
        local trim_amount = finish - item_start
        local take = reaper.GetActiveTake(item)
        if take then
          local cur_offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
          reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", cur_offs + trim_amount)
        end
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", finish)
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", item_end - finish)
      end
    end
  end
end

local function should_keep_running()
  return gfx.getchar() >= 0 and reaper.GetToggleCommandStateEx(section_id, cmd_id) == 1
end

local function try_drop()
  reaper.BR_GetMouseCursorContext()
  local track = reaper.BR_GetMouseCursorContext_Track()
  local pos = reaper.BR_GetMouseCursorContext_Position()

  if track and pos and pos >= 0 and reaper.ValidatePtr(track, "MediaTrack*") then
    local track_num = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    local track_idx = track_num - 1 -- 0-based for the JSFX
    if track_idx >= 0 then
      local a, b = sel_start, sel_end
      if a > b then a, b = b, a end

      local buf_seconds = reaper.gmem_read(4)
      local duration = (b - a) * buf_seconds
      if duration > 0 then
        reaper.Undo_BeginBlock()
        clear_track_range(track, pos, pos + duration)
        reaper.Undo_EndBlock("Clear space for Always Recording drop", -1)
      end

      reaper.SetEditCurPos(pos, false, false)
      reaper.gmem_write(8, track_idx)
      reaper.gmem_write(1, a)
      reaper.gmem_write(2, b - a)
      reaper.gmem_write(13, host_track_is_mono() and 1 or 0)
      reaper.gmem_write(0, 1) -- trigger export in the JSFX
    end
  end
  -- if not over a valid track/position, the drop is simply cancelled
end

------------------------------------------------------------
-- RETURN KEYBOARD FOCUS TO REAPER (needs js_ReaScriptAPI)
------------------------------------------------------------

local MAIN_HWND = reaper.GetMainHwnd()
local HAS_JS    = reaper.APIExists("JS_Window_SetFocus")

if not HAS_JS then
  reaper.ShowConsoleMsg(
    "Daniel_Always Recording: js_ReaScriptAPI not found.\n" ..
    "Install it via ReaPack so focus can return to REAPER after clicking.\n"
  )
end

local function returnFocusToReaper()
  if not HAS_JS then return end
  -- Prefer the arrange view so shortcuts behave as if you clicked the timeline
  local arrange = reaper.JS_Window_FindChildByID(MAIN_HWND, 1000)
  reaper.JS_Window_SetFocus(arrange or MAIN_HWND)
end

-- gfx.getchar(65536) flags: 2 = this window has keyboard focus.
-- Hand focus back whenever this window has it and no mouse button
-- (left 1, right 2, middle 64) is held -- i.e. on open, after a click,
-- after a drag-and-drop, and after the right-click dock menu closes.
local function keepFocusOnReaper()
  local flags = gfx.getchar(65536)
  if flags > 0 and (flags & 2) == 2 and (gfx.mouse_cap & 67) == 0 then
    returnFocusToReaper()
  end
end

local frame_count = 0
local found_active = false

local function main()
  keepFocusOnReaper()

  -- Throttled to every 10 frames (~a few times a second, not 60x/sec) --
  -- scanning every open project's tracks doesn't need to happen every
  -- single frame, especially with a couple dozen projects open at once.
  frame_count = frame_count + 1
  if frame_count % 10 == 1 then
    found_active = manage_instances()
  end

  gfx.set(51/255, 51/255, 51/255, 1)
  gfx.rect(0, 0, gfx.w, gfx.h, 1)

  if not found_active then
    gfx.setfont(1, "Arial", 14)
    gfx.set(0.7, 0.7, 0.7, 1)
    local line_h = 18
    gfx.x, gfx.y = 10, 10
    gfx.drawstr("No effect found. Please insert")
    gfx.x, gfx.y = 10, 10 + line_h
    gfx.drawstr('"Daniel_Always Recording" on Input FX (or anywhere else).')
    gfx.update()
    if should_keep_running() then reaper.defer(main) end
    return
  end

  local disp_n = math.floor(reaper.gmem_read(3) + 0.5)
  if disp_n < 1 then disp_n = 600 end
  local buf_seconds = reaper.gmem_read(4)
  local have_wrapped = reaper.gmem_read(5)
  local write_head = reaper.gmem_read(6)

  -- colors matched exactly to your REAPER theme
  -- background: exact theme grey (51,51,51) -- uncompensated so it stays
  -- correct across platforms, not just tuned for macOS rendering
  local BLUE_R, BLUE_G, BLUE_B = 50/255, 105/255, 175/255

  -- waveform fills the entire window -- no header, no reserved rows
  local wf_x, wf_y = 2, 2
  local wf_w, wf_h = gfx.w - 4, gfx.h - 4
  if wf_w < 10 then wf_w = 10 end
  if wf_h < 10 then wf_h = 10 end
  local center_y = wf_y + wf_h / 2

  local peaks = {}
  local maxpeak = 0
  for i = 0, disp_n - 1 do
    local v = reaper.gmem_read(DISP_BASE + i)
    peaks[i] = v
    if v > maxpeak then maxpeak = v end
  end
  -- Auto-scale to the loudest recent point, but never zoom in past this
  -- floor -- so quiet speech doesn't balloon up to fill the whole window.
  -- Raise this (closer to 1.0) for less zoom, lower it for more.
  local MIN_SCALE = 0.2
  local scale = math.max(maxpeak, MIN_SCALE)

  -- mirrored (top+bottom) waveform: a solid filled shape between each pair
  -- of points (no per-point spoke lines, so no visible vertical lines),
  -- plus a full-brightness outline stroke along the envelope for crispness
  local FILL_ALPHA = 0.4
  local step = wf_w / disp_n
  local lx, ly1, ly2
  for i = 0, disp_n - 1 do
    local v = peaks[i] / scale
    if v > 1 then v = 1 end
    local half = v * (wf_h / 2)
    local x = wf_x + i * step
    local y1 = center_y - half
    local y2 = center_y + half

    if i > 0 then
      gfx.set(BLUE_R, BLUE_G, BLUE_B, FILL_ALPHA)
      gfx.triangle(lx, center_y, lx, ly1, x, y1, x, center_y)
      gfx.triangle(lx, center_y, lx, ly2, x, y2, x, center_y)

      -- glowing outline: midpoint between the too-strong and too-faint
      -- versions -- moderate brightening, visible but not dominant
      local GLOW_R = math.min(1, BLUE_R + 0.18)
      local GLOW_G = math.min(1, BLUE_G + 0.24)
      local GLOW_B = math.min(1, BLUE_B + 0.35)
      gfx.set(GLOW_R, GLOW_G, GLOW_B, 0.18)
      gfx.line(lx, ly1 - 1, x, y1 - 1)
      gfx.line(lx, ly1 + 1, x, y1 + 1)
      gfx.line(lx, ly2 - 1, x, y2 - 1)
      gfx.line(lx, ly2 + 1, x, y2 + 1)
      gfx.set(GLOW_R, GLOW_G, GLOW_B, 0.8)
      gfx.line(lx, ly1, x, y1)
      gfx.line(lx, ly2, x, y2)
    end

    lx, ly1, ly2 = x, y1, y2
  end

  -- center line
  gfx.set(BLUE_R, BLUE_G, BLUE_B, 0.3)
  gfx.line(wf_x, center_y, wf_x + wf_w, center_y)

  -- write-head marker
  gfx.set(1, 1, 0.2, 0.85)
  local head_x = wf_x + write_head * wf_w
  gfx.line(head_x, wf_y, head_x, wf_y + wf_h)

  local mx, my = gfx.mouse_x, gfx.mouse_y
  local over_wf = mx >= wf_x and mx <= wf_x + wf_w and my >= wf_y and my <= wf_y + wf_h
  local mdown = (gfx.mouse_cap & 1) == 1
  local rdown = (gfx.mouse_cap & 2) == 2
  local mnorm = clamp((mx - wf_x) / wf_w, 0, 1)

  -- RIGHT-CLICK: build our own dock menu (gfx windows
  -- have no automatic native one). Toggle between dock/undock based on the
  -- window's actual current state.
  if rdown and not last_rdown then
    gfx.x, gfx.y = mx, my
    local currently_docked = gfx.dock(-1) ~= 0
    local label = currently_docked and "Undock Window" or "Dock Window in Docker"
    local option = gfx.showmenu(label)
    if option == 1 then
      if currently_docked then
        gfx.dock(0)
      else
        gfx.dock(513)
      end
    end
  end
  last_rdown = rdown

  if state == STATE_IDLE then
    if over_wf and mdown and not last_mdown then
      if inside_selection(mnorm) then
        state = STATE_CARRYING -- clicked inside the existing selection: pick it up
      else
        state = STATE_SELECTING -- clicked elsewhere: define a new selection
        sel_start = mnorm
        sel_end = mnorm
      end
    end
  elseif state == STATE_SELECTING then
    if mdown then
      sel_end = mnorm -- mnorm is already clamped 0..1
    else
      state = STATE_IDLE -- released: selection is fixed, nothing dropped yet
    end
  elseif state == STATE_CARRYING then
    if not mdown then
      try_drop()
      state = STATE_IDLE
    end
  end
  last_mdown = mdown

  if sel_start and sel_end then
    local a, b = sel_start, sel_end
    if a > b then a, b = b, a end
    gfx.set(1, 1, 1, state == STATE_CARRYING and 0.45 or 0.25)
    gfx.rect(wf_x + a * wf_w, wf_y, math.max(1, (b - a) * wf_w), wf_h, 1)
  end

  gfx.update()
  if should_keep_running() then
    reaper.defer(main)
  end
end

local function exit()
  local window_state = gfx.dock(-1)
  reaper.SetExtState(EXT_SECTION, "dockstate", tostring(window_state), true)
  set_visual_state(false) -- visual only -- does NOT touch the persisted ini value
end

local w, h = 520, 130
local _, _, sw, sh = reaper.my_getViewport(0, 0, 0, 0, 0, 0, 0, 0, 1)
gfx.init("Daniel_Always Recording", w, h, 0, sw/2 - w/2, sh/2 - h/2)


local DEFAULT_DOCK = 769
local saved_dock = tonumber(reaper.GetExtState(EXT_SECTION, "dockstate"))
if saved_dock and saved_dock ~= 0 then
  gfx.dock(saved_dock)
else
  gfx.dock(DEFAULT_DOCK)
end

reaper.atexit(exit)
main()
