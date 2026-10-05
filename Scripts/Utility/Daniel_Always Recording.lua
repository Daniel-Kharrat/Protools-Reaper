-- Daniel_Always Recording.lua
-- Live waveform viewer + click-select + drag-to-anywhere for the paired
-- Daniel_Always Recording.jsfx. A plain gfx window has no automatic dock
-- menu, so this builds its own via gfx.showmenu() + gfx.dock().
--
-- RIGHT-CLICK MENU:
--   Dock Window in Docker / Undock Window
--   Source ->
--     Effect on a track (manual) : the original behavior. You put the JSFX
--                                  on any track / Input FX / Monitor FX.
--     Hardware input (automatic) : the script creates its own hidden track
--                                  that listens to a physical input on your
--                                  interface -- independent of which tracks
--                                  exist, which are armed, or who is
--                                  recording where.
--   Hardware input -> pick a mono input or a stereo pair (picking one also
--                     switches the source to "Hardware input").
--   Buffer length  -> 5-60 seconds (presets or Custom...). Changing it
--                     restarts the buffer, so earlier audio is cleared.
--   Your choices are remembered across projects and restarts.
--
-- HIDDEN TRACK (Hardware input mode):
--   Hidden from arrange + mixer, armed with record mode "input monitoring
--   only" (so it NEVER writes files when you press record), master send and
--   hardware outputs off (so it makes no sound). It exists only while this
--   script runs: it's deleted from every open project when the script
--   closes, and any leftover (e.g. after a crash) is cleaned up the next
--   time the script runs. It's created/removed outside the undo system.
--
-- TO USE: click-drag inside the waveform to select a region. Release to fix
-- the selection. Click again, starting INSIDE that selection, and drag --
-- you're now carrying the clip. Release over any track/position in the
-- arrange view to drop it there.
--
-- Requires the SWS extension (for BR_GetMouseCursorContext*).
--
-- MULTIPLE PROJECTS OPEN AT ONCE: only the instance in your CURRENTLY
-- FOCUSED project is kept on; every other instance (other projects, and in
-- Hardware input mode any manually placed copies too) is switched offline,
-- so only one instance ever processes audio and nothing collides over the
-- shared gmem channel.

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
local REAPER_INI = reaper.GetResourcePath() .. "/reaper.ini"
local INI_KEY = "Always_Recording"   -- the key the startup action reads

-- The toolbar button's script: Daniel_Always Recording (toolbar toggle).lua
local toggle_button_cmd_id = reaper.NamedCommandLookup("_RS1d334413686175f313d60578bea01a827ae4e954")

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

local function write_ini_value(value) SetIniValue(INI_KEY, value) end

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

------------------------------------------------------------
-- SOURCE MODE + HARDWARE INPUT (persisted globally)
------------------------------------------------------------

-- "input" = hidden track listening to a chosen hardware input (DEFAULT)
-- "track" = effect placed manually (original behavior)
-- Nothing saved yet (first run) -> Hardware input mode on mono input 1.
-- Once the user picks something from the menu, that choice is remembered.
local mode = reaper.GetExtState(EXT_SECTION, "mode")
if mode ~= "track" then mode = "input" end

-- I_RECINPUT value: channel index for mono, 1024 + first channel for a
-- stereo pair. Defaults to mono input 1.
local saved_input = tonumber(reaper.GetExtState(EXT_SECTION, "input")) or 0

-- Rolling buffer length in seconds (the JSFX's slider, 5..60). Defaults to
-- the JSFX's own default of 30. In Hardware input mode it's applied to the
-- hidden track's effect automatically; in manual mode picking a value from
-- the menu sets the placed effect's slider directly.
local BUFFER_MIN, BUFFER_MAX = 5, 60
local BUFFER_PRESETS = { 10, 30, 60 }
local saved_buffer = tonumber(reaper.GetExtState(EXT_SECTION, "buffer_seconds")) or 30

local HIDDEN_KEY = "P_EXT:Daniel_Always_Recording_Hidden"
local HIDDEN_NAME = "Always Recording (auto)"
local JSFX_NAMES = {
  "JS:Daniel_Always Recording",
  "JS:Daniel_Always Recording.jsfx",
  "Daniel_Always Recording",
}

local force_scan = false
local jsfx_load_failed = false

local function is_hidden_track(track)
  local ok, v = reaper.GetSetMediaTrackInfo_String(track, HIDDEN_KEY, "", false)
  return ok and v == "1"
end

local function get_hidden_tracks(proj)
  local list = {}
  for ti = 0, reaper.CountTracks(proj) - 1 do
    local tr = reaper.GetTrack(proj, ti)
    if is_hidden_track(tr) then list[#list + 1] = tr end
  end
  return list
end

-- Only writes a value if it's actually different, so the re-enforcing done
-- on every scan doesn't keep marking the project as modified.
local function set_if_different(track, key, value)
  if reaper.GetMediaTrackInfo_Value(track, key) ~= value then
    reaper.SetMediaTrackInfo_Value(track, key, value)
  end
end

-- (Re)applies every setting the hidden track needs. Called on every scan,
-- so things like "unarm all tracks" or an input change are corrected
-- within a fraction of a second.
local function apply_hidden_settings(track)
  set_if_different(track, "B_SHOWINTCP", 0)
  set_if_different(track, "B_SHOWINMIXER", 0)
  set_if_different(track, "B_MAINSEND", 0)    -- no sound to master/parent
  set_if_different(track, "I_RECMODE", 2)     -- record: disable (input monitoring only)
  set_if_different(track, "I_RECMON", 1)      -- monitoring on (so FX receive the input)
  set_if_different(track, "I_RECINPUT", saved_input)
  set_if_different(track, "I_RECARM", 1)
  -- strip any hardware outputs (e.g. from default track settings)
  while reaper.GetTrackNumSends(track, 1) > 0 do
    reaper.RemoveTrackSend(track, 1, 0)
  end
end

local function add_jsfx(track)
  for _, name in ipairs(JSFX_NAMES) do
    local fx = reaper.TrackFX_AddByName(track, name, false, -1)
    if fx and fx >= 0 then
      reaper.TrackFX_Show(track, fx, 2) -- make sure no floating window pops up
      return fx
    end
  end
  return -1
end

-- Creates the hidden track at the end of the ACTIVE project.
local function create_hidden_track()
  reaper.PreventUIRefresh(1)
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, false)
  local tr = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", HIDDEN_NAME, true)
  reaper.GetSetMediaTrackInfo_String(tr, HIDDEN_KEY, "1", true)
  reaper.SetTrackSelected(tr, false)
  apply_hidden_settings(tr)
  local fx = add_jsfx(tr)
  if fx < 0 then
    reaper.DeleteTrack(tr)
    tr = nil
    jsfx_load_failed = true
  end
  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)
  return tr
end

local function delete_tracks(list)
  if #list == 0 then return end
  reaper.PreventUIRefresh(1)
  for _, tr in ipairs(list) do
    reaper.DeleteTrack(tr)
  end
  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)
end

local function remove_all_hidden_tracks()
  local i = 0
  while true do
    local proj = reaper.EnumProjects(i)
    if not proj then break end
    delete_tracks(get_hidden_tracks(proj))
    i = i + 1
  end
end

------------------------------------------------------------
-- FINDING + SWITCHING INSTANCES
------------------------------------------------------------

-- Collects every Daniel_Always Recording instance on one track: normal FX
-- chain and input/record FX chain (which is also how the master track's
-- Monitor FX chain is addressed).
local function collect_track_fx(track, out)
  for fi = 0, reaper.TrackFX_GetCount(track) - 1 do
    local ok, fxname = reaper.TrackFX_GetFXName(track, fi, "")
    if ok and fxname and fxname:match("Daniel_Always Recording") then
      out[#out + 1] = { track = track, fx = fi }
    end
  end
  for fi = 0, reaper.TrackFX_GetRecCount(track) - 1 do
    local idx = 0x1000000 + fi
    local ok, fxname = reaper.TrackFX_GetFXName(track, idx, "")
    if ok and fxname and fxname:match("Daniel_Always Recording") then
      out[#out + 1] = { track = track, fx = idx }
    end
  end
end

local function collect_project_fx(proj, out)
  collect_track_fx(reaper.GetMasterTrack(proj), out)
  for ti = 0, reaper.CountTracks(proj) - 1 do
    collect_track_fx(reaper.GetTrack(proj, ti), out)
  end
end

-- Walks every open project. Picks exactly one "winner" instance (in the
-- active project, according to the current mode), turns it ON and turns
-- every other instance OFF. Also creates/removes/repairs hidden tracks as
-- the mode requires. Returns true if a winner exists. Remembers the
-- winner's track for mono/stereo detection on drop.
local active_track = nil
local active_fx = nil

local function manage_instances()
  local active_proj = reaper.EnumProjects(-1)
  local input_mode = (mode == "input")
  local all = {}
  local winner = nil
  active_track = nil
  active_fx = nil

  local i = 0
  while true do
    local proj = reaper.EnumProjects(i)
    if not proj then break end

    local hidden = get_hidden_tracks(proj)
    if not input_mode then
      -- manual mode: hidden tracks must not exist anywhere
      delete_tracks(hidden)
      hidden = {}
    else
      -- never more than one (e.g. after an undo/redo brought one back)
      if #hidden > 1 then
        local extras = {}
        for k = 2, #hidden do extras[#extras + 1] = hidden[k] end
        delete_tracks(extras)
        hidden = { hidden[1] }
      end
      if proj == active_proj then
        if not hidden[1] and not jsfx_load_failed then
          hidden[1] = create_hidden_track()
        end
        if hidden[1] then apply_hidden_settings(hidden[1]) end
      end
    end

    local proj_fx = {}
    collect_project_fx(proj, proj_fx)

    if proj == active_proj then
      if input_mode then
        if hidden[1] then
          for _, inst in ipairs(proj_fx) do
            if inst.track == hidden[1] then winner = inst break end
          end
          -- hidden track somehow lost its effect: put it back
          if not winner and not jsfx_load_failed then
            local fx = add_jsfx(hidden[1])
            if fx >= 0 then
              winner = { track = hidden[1], fx = fx }
              proj_fx[#proj_fx + 1] = winner
            else
              jsfx_load_failed = true
            end
          end
        end
      else
        winner = proj_fx[1] -- master (Monitor FX) first, then tracks in order
      end
    end

    for _, inst in ipairs(proj_fx) do all[#all + 1] = inst end
    i = i + 1
  end

  for _, inst in ipairs(all) do
    local should_be_on = (inst == winner)
    local currently_offline = reaper.TrackFX_GetOffline(inst.track, inst.fx)
    if should_be_on and currently_offline then
      reaper.TrackFX_SetOffline(inst.track, inst.fx, false)
    elseif (not should_be_on) and (not currently_offline) then
      reaper.TrackFX_SetOffline(inst.track, inst.fx, true)
    end
  end

  if winner then
    active_track = winner.track
    active_fx = winner.fx
    -- Hidden track: keep its buffer-length slider on the saved value
    -- (only written when different, since changing it resets the buffer).
    if input_mode then
      local cur = reaper.TrackFX_GetParam(winner.track, winner.fx, 0)
      if math.abs(cur - saved_buffer) > 0.01 then
        reaper.TrackFX_SetParam(winner.track, winner.fx, 0, saved_buffer)
      end
    end
  end
  return winner ~= nil
end

-- True if the host track's record input is a single mono channel rather
-- than a stereo pair (I_RECINPUT bit 1024 marks a stereo input pair). The
-- master track (used for Monitor FX) has no meaningful record input at
-- all, so it's always treated as stereo rather than misread as mono.
-- In Hardware input mode the host is the hidden track, whose record input
-- IS the input you picked -- so this works unchanged for both modes.
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

-- true once the window was closed with its X (a deliberate "off", unlike
-- REAPER quitting) -- exit() then clears the startup flag too
local closed_by_user = false

local function should_keep_running()
  if gfx.getchar() < 0 then
    closed_by_user = true
    return false
  end
  return reaper.GetToggleCommandStateEx(section_id, cmd_id) == 1
end

local function try_drop()
  reaper.BR_GetMouseCursorContext()
  local track = reaper.BR_GetMouseCursorContext_Track()
  local pos = reaper.BR_GetMouseCursorContext_Position()

  if track and pos and pos >= 0 and reaper.ValidatePtr(track, "MediaTrack*")
     and not is_hidden_track(track) then
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

      -- Deselect every item first (e.g. the one left selected after you
      -- stop recording), so the freshly dropped item ends up being the
      -- ONLY selected item and you can move it without dragging others.
      reaper.SelectAllMediaItems(0, false)
      reaper.UpdateArrange()

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
-- RIGHT-CLICK MENU
------------------------------------------------------------

local function set_mode(m)
  mode = m
  reaper.SetExtState(EXT_SECTION, "mode", m, true)
  jsfx_load_failed = false
  sel_start, sel_end = nil, nil
  state = STATE_IDLE
  force_scan = true
end

local function set_input(v)
  saved_input = v
  reaper.SetExtState(EXT_SECTION, "input", tostring(v), true)
  if mode ~= "input" then
    set_mode("input")
  else
    jsfx_load_failed = false
    force_scan = true
  end
end

local function set_buffer(seconds)
  seconds = math.floor(clamp(seconds, BUFFER_MIN, BUFFER_MAX) + 0.5)
  saved_buffer = seconds
  reaper.SetExtState(EXT_SECTION, "buffer_seconds", tostring(seconds), true)
  -- apply right away to whichever instance is currently active
  if active_track and active_fx and reaper.ValidatePtr(active_track, "MediaTrack*") then
    reaper.TrackFX_SetParam(active_track, active_fx, 0, seconds)
  end
  -- the buffer restarts at the new length, so any old selection is stale
  sel_start, sel_end = nil, nil
  state = STATE_IDLE
end

-- Current length as reported by the running effect, or the saved value.
local function current_buffer_seconds()
  local s = reaper.gmem_read(4)
  if not s or s < BUFFER_MIN then s = saved_buffer end
  return s
end

local function ask_custom_buffer()
  local ok, str = reaper.GetUserInputs("Always Recording", 1,
    "Buffer length (" .. BUFFER_MIN .. "-" .. BUFFER_MAX .. " seconds):",
    tostring(math.floor(current_buffer_seconds() + 0.5)))
  if ok then
    local v = tonumber(str)
    if v then set_buffer(v) end
  end
end

-- Makes a device-provided channel name safe to use as a menu label.
local function menu_safe(s)
  s = tostring(s or "")
  s = (s:gsub("|", "/"))
  s = (s:gsub("&", "&&"))
  if s:match("^[!#<>]") then s = " " .. s end
  return s
end

local function show_context_menu(mx, my)
  local items, actions = {}, {}
  local function add(label, fn, checked, last)
    items[#items + 1] = (last and "<" or "") .. (checked and "!" or "") .. label
    actions[#actions + 1] = fn
  end
  local function sep() items[#items + 1] = "" end
  local function sub(label) items[#items + 1] = ">" .. label end

  local currently_docked = gfx.dock(-1) ~= 0
  add(currently_docked and "Undock Window" or "Dock Window in Docker", function()
    if currently_docked then gfx.dock(0) else gfx.dock(513) end
  end)
  sep()

  sub("Source")
  add("Effect on a track (manual)", function() set_mode("track") end, mode == "track")
  add("Hardware input (automatic)", function() set_mode("input") end, mode == "input", true)

  sub("Hardware input")
  local n = reaper.GetNumAudioInputs()
  if n < 1 then
    add("No audio inputs (check audio device)", function() end, false, true)
  else
    for ch = 0, n - 1 do
      local val = ch
      add("Mono: " .. menu_safe(reaper.GetInputChannelName(ch)),
          function() set_input(val) end,
          mode == "input" and saved_input == val,
          n < 2 and ch == n - 1)
    end
    if n >= 2 then
      sep()
      local last_pair = (n % 2 == 0) and (n - 2) or (n - 3)
      for ch = 0, n - 2, 2 do
        local val = 1024 + ch
        add("Stereo: " .. menu_safe(reaper.GetInputChannelName(ch)) ..
            " / " .. menu_safe(reaper.GetInputChannelName(ch + 1)),
            function() set_input(val) end,
            mode == "input" and saved_input == val,
            ch == last_pair)
      end
    end
  end

  sub("Buffer length")
  local cur = math.floor(current_buffer_seconds() + 0.5)
  local is_preset = false
  for _, s in ipairs(BUFFER_PRESETS) do
    local val = s
    if cur == s then is_preset = true end
    add(s .. " seconds", function() set_buffer(val) end, cur == s)
  end
  sep()
  add(is_preset and "Custom..." or ("Custom (" .. cur .. " seconds)..."),
      ask_custom_buffer, not is_preset, true)

  gfx.x, gfx.y = mx, my
  local choice = gfx.showmenu(table.concat(items, "|"))
  if choice > 0 and actions[choice] then actions[choice]() end
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
-- after a drag-and-drop, and after the right-click menu closes.
local function keepFocusOnReaper()
  local flags = gfx.getchar(65536)
  if flags > 0 and (flags & 2) == 2 and (gfx.mouse_cap & 67) == 0 then
    returnFocusToReaper()
  end
end

------------------------------------------------------------
-- MAIN LOOP
------------------------------------------------------------

local frame_count = 0
local found_active = false

local function draw_message(lines)
  gfx.setfont(1, "Arial", 14)
  gfx.set(0.7, 0.7, 0.7, 1)
  local line_h = 18
  for i, text in ipairs(lines) do
    gfx.x, gfx.y = 10, 10 + (i - 1) * line_h
    gfx.drawstr(text)
  end
end

local function main()
  keepFocusOnReaper()

  -- Throttled to every 10 frames (~a few times a second, not 60x/sec) --
  -- scanning every open project's tracks doesn't need to happen every
  -- single frame, especially with a couple dozen projects open at once.
  -- force_scan makes a menu change take effect on the very next frame.
  frame_count = frame_count + 1
  if force_scan or frame_count % 10 == 1 then
    force_scan = false
    found_active = manage_instances()
  end

  gfx.set(51/255, 51/255, 51/255, 1)
  gfx.rect(0, 0, gfx.w, gfx.h, 1)

  local mx, my = gfx.mouse_x, gfx.mouse_y
  local rdown = (gfx.mouse_cap & 2) == 2

  -- RIGHT-CLICK: our own menu (gfx windows have no native one). Handled
  -- before the "nothing found" early return, so you can always switch
  -- source/input even when no instance exists yet.
  if rdown and not last_rdown then
    show_context_menu(mx, my)
  end
  last_rdown = rdown

  if not found_active then
    if mode == "input" then
      if jsfx_load_failed then
        draw_message({
          "Couldn't load the Daniel_Always Recording effect.",
          "Check the JSFX is installed, then pick the source again.",
        })
      else
        draw_message({ "Setting up the hidden input track..." })
      end
    else
      draw_message({
        "No effect found. Please insert",
        '"Daniel_Always Recording" on a track.',
      })
    end
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

  local raw = {}
  for i = 0, disp_n - 1 do
    raw[i] = reaper.gmem_read(DISP_BASE + i)
  end

  -- SMOOTHING: each point is blended with its neighbours (weighted so the
  -- closest ones count most), which rounds off sharp spiky peaks.
  -- 0 = original sharp look. 2-4 = gently smoothed. 6+ = very soft/blobby.
  local SMOOTH = 1
  local peaks = {}
  local maxpeak = 0
  for i = 0, disp_n - 1 do
    local sum, wsum = 0, 0
    for k = -SMOOTH, SMOOTH do
      local j = i + k
      if j >= 0 and j < disp_n then
        local w = SMOOTH + 1 - math.abs(k)
        sum = sum + raw[j] * w
        wsum = wsum + w
      end
    end
    local v = sum / wsum
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

  local over_wf = mx >= wf_x and mx <= wf_x + wf_w and my >= wf_y and my <= wf_y + wf_h
  local mdown = (gfx.mouse_cap & 1) == 1
  local mnorm = clamp((mx - wf_x) / wf_w, 0, 1)

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
  set_visual_state(false) -- buttons off; the ini flag is left alone when REAPER is quitting
  if closed_by_user then write_ini_value(0) end -- window X: don't reopen at the next startup
  pcall(remove_all_hidden_tracks) -- no leftovers once the script is closed
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
-- Started via defer (not called directly) so the hidden-track creation
-- happens outside the script's initial run -- that keeps REAPER from
-- adding an automatic "ReaScript" undo point for it.
reaper.defer(main)
