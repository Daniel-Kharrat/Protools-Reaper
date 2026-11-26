-- Daniel_Always Recording.lua
-- Version: 2.1
-- Author: Daniel Kharrat
--
-- Live waveform viewer + click-select + drag-to-anywhere. Two sources:
--   Hardware input (extension): the "Daniel_Always Recording" extension
--     (reaper_daniel_always_recording) keeps ONE global rolling buffer of a
--     hardware input in REAPER's audio engine: no effect, no hidden track,
--     nothing saved in your projects, and it keeps recording when you
--     switch project tabs. The buffer runs only while this window is open
--     (on at start, off when it closes). The extension's action
--     "Daniel_Always Recording: Show window (toggle)" opens/closes this window.
--   Application (extension, macOS 14.2+ or Linux with PipeWire): the
--     extension records the audio of one app (for example a web browser
--     playing YouTube), or all system audio except REAPER. On macOS a small
--     helper app does the capture; macOS asks once for "System Audio
--     Recording" permission for it. On Linux no permission is needed.
--   Effect on a track (manual): the paired Daniel_Always Recording.jsfx,
--     placed by you on any track / Input FX / Monitor FX. Only the instance
--     in the CURRENTLY FOCUSED project is kept on; every other instance is
--     switched offline.
-- A plain gfx window has no automatic dock menu, so this builds its own via
-- gfx.showmenu() + gfx.dock().
--
-- RIGHT-CLICK MENU:
--   Dock Window in Docker / Undock Window
--   Source ->  Effect on a track (manual) / Hardware input (extension) /
--              Application (extension, macOS)
--   Application -> pick an app (apps with an open audio stream are first,
--                  marked "audio active": open, not always audible),
--                  or "All system audio (except REAPER)"
--                  (picking one also switches the source to "Application").
--   Hardware input ->  Mono -> pick an input, or Stereo -> pick a pair
--                      (picking one also switches the source to "Hardware input").
--   Buffer length  ->  5-60 seconds (presets or Custom...). Changing the
--                      input or the length restarts the buffer, so earlier
--                      audio is cleared.
--   Support (Ko-fi) :  at the bottom, opens ko-fi.com/danielkharrat
--   Your choices are remembered across projects and restarts.
--
-- TO USE: click-drag inside the waveform to select a region. Release to fix
-- the selection. Click again, starting INSIDE that selection, and drag --
-- you're now carrying the clip. Release over any track/position in the
-- arrange view to drop it there. Drop on the empty area below the last
-- track to put it on a new track. The audio is written to a file in that
-- project's media folder.
--
-- Requires the SWS extension (for BR_GetMouseCursorContext*), plus the
-- Daniel_Always Recording extension for the hardware input source.

-- TOOLBAR BUTTON: put the extension's action "Daniel_Always Recording:
-- Show window (toggle)" on a toolbar button. It runs this script and lights
-- while this window is open. No separate toggle script is needed.
-- Running this script while it is already running closes the window: the
-- ALREADY-RUNNING instance notices that (checked once per loop) and shuts
-- itself down.
-- REMEMBER ACROSS RESTARTS: the extension keeps an "open" flag. It is set
-- when the window opens and cleared only when YOU close it (window X or the
-- button), not when REAPER quits. At the next start the extension opens the
-- window again if the flag is set.
reaper.set_action_options(1)
local _, _, section_id, cmd_id = reaper.get_action_context()

local CAN_REMEMBER = reaper.APIExists("Daniel_AlwaysRec_SetWindowOpen")

-- Version 1 used a "[toolbar button states] Always_Recording=" flag in
-- reaper.ini for a startup action. The extension does this job now, so set
-- that old flag to 0 (if it exists) to stop a second launch at startup.
local function retire_old_ini_flag()
  if reaper.GetExtState("AlwaysRecording_Display", "ini_flag_retired") == "1" then return end
  reaper.SetExtState("AlwaysRecording_Display", "ini_flag_retired", "1", true)
  local path = reaper.GetResourcePath() .. "/reaper.ini"
  local file = io.open(path, "rb")
  if not file then return end
  local contents = file:read("*all")
  file:close()
  local new_contents, count = contents:gsub("(\nAlways_Recording=)1", "%10")
  if count > 0 then
    file = io.open(path, "wb")
    if file then file:write(new_contents) file:close() end
  end
end

local function set_visual_state(on)
  reaper.SetToggleCommandState(section_id, cmd_id, on and 1 or 0)
  reaper.RefreshToolbar2(section_id, cmd_id)
end

-- Use this ONLY for genuine, intentional on/off decisions (starting up, or
-- the deliberate "second press closes it" branch). Not from atexit when
-- REAPER is quitting, so the window comes back at the next start.
local function set_button_state(on)
  set_visual_state(on)
  if CAN_REMEMBER then reaper.Daniel_AlwaysRec_SetWindowOpen(on) end
end

if reaper.GetToggleCommandStateEx(section_id, cmd_id) == 1 then
  -- already running elsewhere: this press means "turn it off"
  set_button_state(false)
  return
end
set_button_state(true)
retire_old_ini_flag()

local EXT_SECTION = "AlwaysRecording_Display"   -- window dock state + source mode

-- the extension (reaper_daniel_always_recording) gives these functions
local HAS_EXT = reaper.APIExists("Daniel_AlwaysRec_GetInfo")
-- application source: needs extension v1.1 on macOS 14.2+
local HAS_APP = reaper.APIExists("Daniel_AlwaysRec_GetApps") and reaper.Daniel_AlwaysRec_GetApps("") == true
local IS_MAC = reaper.GetOS():find("OSX") ~= nil or reaper.GetOS():find("mac") ~= nil
local DISP_N = 600
local peaks_arr = reaper.new_array(DISP_N)

-- SOURCE MODE (remembered):
--   "input" = hardware input, recorded by the extension (DEFAULT)
--   "track" = the Daniel_Always Recording JSFX placed manually on a track
--   "app"   = the audio of an application, recorded by the extension (macOS)
local mode = reaper.GetExtState(EXT_SECTION, "mode")
if mode ~= "track" and not (mode == "app" and HAS_APP) then mode = "input" end

-- JSFX (manual mode) shares a small gmem channel with this window
local GMEM_NAME = "Daniel_Always_Recording"
reaper.gmem_attach(GMEM_NAME)
local DISP_BASE = 7

------------------------------------------------------------
-- LEFTOVERS FROM VERSION 1 (JSFX + hidden track)
------------------------------------------------------------

-- Version 1 made a hidden track "Always Recording (auto)". It was deleted
-- when the window closed; after a crash one could stay behind. Remove any
-- that are still in open projects (outside the undo system).
local HIDDEN_KEY = "P_EXT:Daniel_Always_Recording_Hidden"

local function remove_old_hidden_tracks()
  local i = 0
  while true do
    local proj = reaper.EnumProjects(i)
    if not proj then break end
    local list = {}
    for ti = 0, reaper.CountTracks(proj) - 1 do
      local tr = reaper.GetTrack(proj, ti)
      local ok, v = reaper.GetSetMediaTrackInfo_String(tr, HIDDEN_KEY, "", false)
      if ok and v == "1" then list[#list + 1] = tr end
    end
    if #list > 0 then
      reaper.PreventUIRefresh(1)
      for _, tr in ipairs(list) do reaper.DeleteTrack(tr) end
      reaper.PreventUIRefresh(-1)
      reaper.TrackList_AdjustWindows(false)
    end
    i = i + 1
  end
end

------------------------------------------------------------
-- BUFFER SETTINGS (kept by the extension)
------------------------------------------------------------

local BUFFER_MIN, BUFFER_MAX = 5, 60
local BUFFER_PRESETS = { 10, 30, 60 }

-- state: 0 = off, 1 = waiting for audio/input, 2 = running
local function get_info()
  if not HAS_EXT then return 0, 30, 0, 0, 0 end
  local state, buf_seconds, write_head, wrapped, input = reaper.Daniel_AlwaysRec_GetInfo()
  return state, buf_seconds, write_head, wrapped, input
end

------------------------------------------------------------
-- MANUAL MODE: FINDING + SWITCHING JSFX INSTANCES
------------------------------------------------------------

-- Collects every Daniel_Always Recording instance on one track: normal FX
-- chain and input/record FX chain (which is also how the master track's
-- Monitor FX chain is addressed).
-- skip_rec: leave out the record/input chain. On the master track that
-- chain is the Monitor FX chain, which is GLOBAL (one chain for all
-- projects), so it must be collected only once (from the active project).
local function collect_track_fx(track, out, skip_rec)
  for fi = 0, reaper.TrackFX_GetCount(track) - 1 do
    local ok, fxname = reaper.TrackFX_GetFXName(track, fi, "")
    if ok and fxname and fxname:match("Daniel_Always Recording") then
      out[#out + 1] = { track = track, fx = fi }
    end
  end
  if skip_rec then return end
  for fi = 0, reaper.TrackFX_GetRecCount(track) - 1 do
    local idx = 0x1000000 + fi
    local ok, fxname = reaper.TrackFX_GetFXName(track, idx, "")
    if ok and fxname and fxname:match("Daniel_Always Recording") then
      out[#out + 1] = { track = track, fx = idx }
    end
  end
end

local function collect_project_fx(proj, out, is_active)
  collect_track_fx(reaper.GetMasterTrack(proj), out, not is_active)   -- Monitor FX only once
  for ti = 0, reaper.CountTracks(proj) - 1 do
    collect_track_fx(reaper.GetTrack(proj, ti), out)
  end
end

-- Walks every open project. In manual mode, picks exactly one "winner"
-- instance (the first one in the ACTIVE project), turns it ON and turns
-- every other instance OFF, so only one instance ever processes audio and
-- nothing collides over the shared gmem channel. In hardware input mode
-- (the extension records), every instance is turned OFF.
-- full = false: scan only the active project (the other projects were
-- already switched off by the last full scan). A full scan runs on a tab
-- switch and every ~2 s, so with ~25 open projects most scans stay small.
-- Returns true if a winner exists.
local active_track = nil
local active_fx = nil

local function manage_instances(full)
  local active_proj = reaper.EnumProjects(-1)
  local all = {}
  local winner = nil
  active_track = nil
  active_fx = nil

  local i = 0
  while true do
    local proj = reaper.EnumProjects(i)
    if not proj then break end
    local is_active = (proj == active_proj)
    if full or is_active then
      local proj_fx = {}
      collect_project_fx(proj, proj_fx, is_active)
      if is_active and mode == "track" then
        winner = proj_fx[1] -- master (Monitor FX) first, then tracks in order
      end
      for _, inst in ipairs(proj_fx) do all[#all + 1] = inst end
    end
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
  end
  return winner ~= nil
end

-- True if the host track's record input is a single mono channel rather
-- than a stereo pair (I_RECINPUT bit 1024 marks a stereo input pair). The
-- master track (used for Monitor FX) has no meaningful record input at
-- all, so it's always treated as stereo rather than misread as mono.
local function host_track_is_mono()
  if not active_track then return false end
  local track_num = reaper.GetMediaTrackInfo_Value(active_track, "IP_TRACKNUMBER")
  if track_num <= 0 then return false end -- master or not found: no real record input
  local rec_input = reaper.GetMediaTrackInfo_Value(active_track, "I_RECINPUT")
  if rec_input < 0 then return false end -- no input assigned; default to stereo
  if (rec_input & 4096) ~= 0 then return false end -- MIDI input; default to stereo
  return (rec_input & 1024) == 0
end

-- Buffer length of the current source (seconds)
local function current_buffer_seconds()
  if mode == "track" then
    local s = reaper.gmem_read(4)
    if not s or s < BUFFER_MIN then s = 30 end
    return s
  end
  local _, s = get_info()
  return s
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
  if not reaper.BR_GetMouseCursorContext then return end
  local window, segment = reaper.BR_GetMouseCursorContext()
  local track = reaper.BR_GetMouseCursorContext_Track()
  local pos = reaper.BR_GetMouseCursorContext_Position()

  -- Dropped on the empty area below the last track: make a new track there,
  -- like REAPER does when you drag an item to empty space.
  local new_track = false
  if not track and window == "arrange" and segment == "empty" and pos and pos >= 0 then
    new_track = true
  end

  local function create_track()
    local idx = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(idx, true)   -- true = use default track settings
    reaper.TrackList_AdjustWindows(false)
    return reaper.GetTrack(0, idx)
  end

  if (new_track or track) and pos and pos >= 0 then
    local a, b = sel_start, sel_end
    if a > b then a, b = b, a end

    if mode == "track" then
      if new_track then
        reaper.Undo_BeginBlock()
        track = create_track()
        reaper.Undo_EndBlock("Always Recording: new track for drop", -1)
      end
      if not (track and reaper.ValidatePtr(track, "MediaTrack*")) then return end
      -- manual mode: the JSFX writes the file (same as version 1)
      local track_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
      if track_idx < 0 then return end
      local duration = (b - a) * reaper.gmem_read(4)
      if duration > 0 then
        reaper.Undo_BeginBlock()
        clear_track_range(track, pos, pos + duration)
        reaper.Undo_EndBlock("Clear space for Always Recording drop", -1)
      end
      reaper.SelectAllMediaItems(0, false)
      reaper.UpdateArrange()
      reaper.SetEditCurPos(pos, false, false)
      reaper.gmem_write(8, track_idx)
      reaper.gmem_write(1, a)
      reaper.gmem_write(2, b - a)
      reaper.gmem_write(13, host_track_is_mono() and 1 or 0)
      reaper.gmem_write(0, 1) -- trigger export in the JSFX
      return
    end

    local _, buf_seconds = get_info()
    local duration = (b - a) * buf_seconds
    if duration > 0 then
      reaper.Undo_BeginBlock()
      reaper.PreventUIRefresh(1)
      if new_track then track = create_track() end
      if not (track and reaper.ValidatePtr(track, "MediaTrack*")) then
        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock("Always Recording: drop failed", -1)
        return
      end
      clear_track_range(track, pos, pos + duration)

      -- Deselect every item first (e.g. the one left selected after you
      -- stop recording), so the freshly dropped item ends up being the
      -- ONLY selected item and you can move it without dragging others.
      reaper.SelectAllMediaItems(0, false)
      reaper.SetEditCurPos(pos, false, false)
      local ok = reaper.Daniel_AlwaysRec_Export(track, pos, a, b - a)
      if not ok and new_track then reaper.DeleteTrack(track) end   -- no empty leftover track
      reaper.PreventUIRefresh(-1)
      reaper.UpdateArrange()
      reaper.Undo_EndBlock(ok and "Always Recording: drop audio" or "Always Recording: drop failed", -1)
    end
  end
  -- if not over a valid track/position, the drop is simply cancelled
end

------------------------------------------------------------
-- RIGHT-CLICK MENU
------------------------------------------------------------

local function reset_selection()
  sel_start, sel_end = nil, nil
  state = STATE_IDLE
end

local force_scan = false

-- The extension's buffer runs only while this window is open AND the
-- source is "Hardware input" or "Application". Manual mode uses the JSFX.
local function sync_buffer()
  if not HAS_EXT then return end
  local on = (mode == "input" or mode == "app")
  if not on then reaper.Daniel_AlwaysRec_SetEnabled(false) end
  if HAS_APP then reaper.Daniel_AlwaysRec_SetSource(mode == "app" and 1 or 0) end
  if on then reaper.Daniel_AlwaysRec_SetEnabled(true) end
end

local function set_mode(m)
  mode = m
  reaper.SetExtState(EXT_SECTION, "mode", m, true)
  sync_buffer()
  reset_selection()
  force_scan = true
end

local function set_input(v)
  if HAS_EXT then reaper.Daniel_AlwaysRec_SetInput(v) end
  if mode ~= "input" then set_mode("input")       -- picking an input switches the source (also resets)
  else reset_selection() end                       -- the buffer restarts, so any old selection is stale
end

local function set_app(key)
  if HAS_APP then reaper.Daniel_AlwaysRec_SetApp(key) end
  if mode ~= "app" then set_mode("app") end       -- picking an app switches the source (also resets)
  -- same source: the buffer keeps its audio, so the selection stays valid
end

-- { key, name, playing } list from the extension (first: all system audio)
local function get_apps()
  local list = {}
  if not HAS_APP then return list end
  local ok, text = reaper.Daniel_AlwaysRec_GetApps(string.rep(" ", 16384))
  if not ok or not text then return list end
  for line in text:gmatch("[^\n]+") do
    local key, name, playing = line:match("^([^\t]*)\t([^\t]*)\t(%d)")
    if key and key ~= "" then list[#list + 1] = { key = key, name = name, playing = playing == "1" } end
  end
  return list
end

-- status of the application source: code, key, name, error
-- code: 0 = not supported, 1 = starting, 2 = capturing, 3 = app not playing, 4 = error
local function get_app_status()
  if not HAS_APP then return 0, "", "", 0 end
  local code, key, name, err = reaper.Daniel_AlwaysRec_GetAppStatus("", "")
  return code, key or "", name or "", err or 0
end

local function set_buffer(seconds)
  seconds = math.floor(clamp(seconds, BUFFER_MIN, BUFFER_MAX) + 0.5)
  if mode == "track" then
    -- manual mode: set the placed effect's slider directly
    if active_track and active_fx and reaper.ValidatePtr(active_track, "MediaTrack*") then
      reaper.TrackFX_SetParam(active_track, active_fx, 0, seconds)
    end
  elseif HAS_EXT then
    reaper.Daniel_AlwaysRec_SetBufferSeconds(seconds)
  end
  reset_selection()   -- the buffer restarts at the new length
end

local function ask_custom_buffer()
  local cur = current_buffer_seconds()
  local ok, str = reaper.GetUserInputs("Always Recording", 1,
    "Buffer length (" .. BUFFER_MIN .. "-" .. BUFFER_MAX .. " seconds):",
    tostring(math.floor(cur + 0.5)))
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
  add("Hardware input (extension)", function() set_mode("input") end, mode == "input", not HAS_APP)
  if HAS_APP then
    add("Application (extension)", function() set_mode("app") end, mode == "app", true)
  end

  local _, _, _, _, saved_input = get_info()

  do
    -- Hardware input -> Mono -> ... / Stereo -> ...
    -- ("<>" on a submenu title: it is also the last item of the menu above)
    sub("Hardware input")
    local n = reaper.GetNumAudioInputs()
    if n < 1 then
      add("No audio inputs (check audio device)", function() end, false, true)
    else
      items[#items + 1] = (n < 2 and "<>" or ">") .. "Mono"
      for ch = 0, n - 1 do
        local val = ch
        add(menu_safe(reaper.GetInputChannelName(ch)),
            function() set_input(val) end,
            mode == "input" and HAS_EXT and saved_input == val,
            ch == n - 1)
      end
      if n >= 2 then
        items[#items + 1] = "<>Stereo"
        local last_pair = (n % 2 == 0) and (n - 2) or (n - 3)
        for ch = 0, n - 2, 2 do
          local val = 1024 + ch
          add(menu_safe(reaper.GetInputChannelName(ch)) ..
              " / " .. menu_safe(reaper.GetInputChannelName(ch + 1)),
              function() set_input(val) end,
              mode == "input" and HAS_EXT and saved_input == val,
              ch == last_pair)
        end
      end
    end

    if HAS_APP then
      -- Application -> All system audio / apps (playing ones first)
      sub("Application")
      local apps = get_apps()
      local _, cur_key = get_app_status()
      if #apps == 0 then
        add("No apps found", function() end, false, true)
      else
        for i, app in ipairs(apps) do
          local key = app.key
          add(menu_safe(app.name) .. (app.playing and "   (audio active)" or ""),
              function() set_app(key) end,
              mode == "app" and cur_key == key,
              i == #apps)
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
    sep()
  end

  add("♥ Support (Ko-fi)", function()
    local url = "https://ko-fi.com/danielkharrat"
    if reaper.CF_ShellExecute then reaper.CF_ShellExecute(url)          -- SWS
    elseif reaper.GetOS():find("Win") then os.execute('start "" "' .. url .. '"')
    elseif reaper.GetOS():find("OSX") or reaper.GetOS():find("mac") then os.execute('open "' .. url .. '"')
    else os.execute('xdg-open "' .. url .. '" &') end
  end)

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

-- For the first moment after the window opens, the buffer (or the effect
-- scan) may not be ready yet. Show only the empty background then, so no
-- status message flashes before the waveform.
local START_TIME = reaper.time_precise()
local MESSAGE_DELAY = 1.0

local function draw_message(lines)
  if reaper.time_precise() - START_TIME < MESSAGE_DELAY then return end
  gfx.setfont(1, "Arial", 14)
  gfx.set(0.7, 0.7, 0.7, 1)
  local line_h = 18
  for i, text in ipairs(lines) do
    gfx.x, gfx.y = 10, 10 + (i - 1) * line_h
    gfx.drawstr(text)
  end
end

local frame_count = 0
local found_active = false
local last_sound_time = reaper.time_precise()   -- application source: silence hint
local last_active_proj = nil
local FULL_SCAN_FRAMES = 60   -- ~2 s

-- reused every frame (no new tables per frame)
local raw, peaks = {}, {}

local function main()
  keepFocusOnReaper()

  -- Throttled to every 10 frames (~a few times a second, not 60x/sec) --
  -- scanning every open project's tracks doesn't need to happen every
  -- single frame, especially with a couple dozen projects open at once.
  -- force_scan makes a menu change take effect on the very next frame.
  frame_count = frame_count + 1
  local active_proj = reaper.EnumProjects(-1)
  local tab_switched = active_proj ~= last_active_proj
  if force_scan or tab_switched or frame_count % 10 == 1 then
    local full = force_scan or tab_switched or frame_count % FULL_SCAN_FRAMES == 1
    force_scan = false
    last_active_proj = active_proj
    found_active = manage_instances(full)
  end

  gfx.set(51/255, 51/255, 51/255, 1)
  gfx.rect(0, 0, gfx.w, gfx.h, 1)

  local mx, my = gfx.mouse_x, gfx.mouse_y
  local rdown = (gfx.mouse_cap & 2) == 2

  -- RIGHT-CLICK: our own menu (gfx windows have no native one). Handled
  -- before the "not running" early return, so you can always switch
  -- input or turn the buffer on.
  if rdown and not last_rdown then
    show_context_menu(mx, my)
  end
  last_rdown = rdown

  local ext_state, buf_seconds, write_head = get_info()
  local disp_n = 0

  if mode == "track" then
    if not found_active then
      draw_message({
        "No effect found. Please insert",
        '"Daniel_Always Recording" on a track.',
      })
      gfx.update()
      if should_keep_running() then reaper.defer(main) end
      return
    end
    disp_n = math.floor(reaper.gmem_read(3) + 0.5)
    if disp_n < 1 then disp_n = DISP_N end
    buf_seconds = reaper.gmem_read(4)
    write_head = reaper.gmem_read(6)
    for i = 0, disp_n - 1 do
      raw[i] = reaper.gmem_read(DISP_BASE + i)
    end
  elseif ext_state ~= 2 then
    if not HAS_EXT then
      draw_message({
        "The Daniel_Always Recording extension is not installed.",
        "Install it via ReaPack, then restart REAPER.",
      })
    elseif mode == "app" then
      local code, _, name, err = get_app_status()
      if code == 0 then
        draw_message({ IS_MAC and "Application audio needs macOS 14.2 or later." or "Application audio needs PipeWire." })
      elseif code == 3 then
        draw_message({
          "Waiting for " .. name .. " to play audio...",
          "Right-click to pick another app.",
        })
      elseif code == 4 then
        draw_message({
          err == -1 and "Could not install the helper app." or ("Could not capture " .. name .. " (error " .. tostring(err) .. ")."),
          "Right-click to pick another app.",
        })
      else
        draw_message({ "Starting the capture of " .. name .. "..." })
      end
    elseif ext_state == 0 then
      draw_message({ "Could not start the rolling buffer (audio hook)." })
    else
      draw_message({
        "Waiting for audio from the hardware input...",
        "Check the audio device, or right-click to pick another input.",
      })
    end
    gfx.update()
    if should_keep_running() then reaper.defer(main) end
    return
  else
    disp_n = reaper.Daniel_AlwaysRec_GetPeaks(peaks_arr)
    if disp_n < 1 then disp_n = DISP_N end
    for i = 0, disp_n - 1 do
      raw[i] = peaks_arr[i + 1]
    end
  end

  -- colors matched exactly to your REAPER theme
  -- background: exact theme grey (51,51,51) -- uncompensated so it stays
  -- correct across platforms, not just tuned for macOS rendering
  local BLUE_R, BLUE_G, BLUE_B = 50/255, 105/255, 175/255
  -- glowing outline: midpoint between the too-strong and too-faint
  -- versions -- moderate brightening, visible but not dominant
  local GLOW_R = math.min(1, BLUE_R + 0.18)
  local GLOW_G = math.min(1, BLUE_G + 0.24)
  local GLOW_B = math.min(1, BLUE_B + 0.35)

  -- waveform fills the entire window -- no header, no reserved rows
  local wf_x, wf_y = 2, 2
  local wf_w, wf_h = gfx.w - 4, gfx.h - 4
  if wf_w < 10 then wf_w = 10 end
  if wf_h < 10 then wf_h = 10 end
  local center_y = wf_y + wf_h / 2

  -- SMOOTHING: each point is blended with its neighbours (weighted so the
  -- closest ones count most), which rounds off sharp spiky peaks.
  -- 0 = original sharp look. 2-4 = gently smoothed. 6+ = very soft/blobby.
  local SMOOTH = 1
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

  -- Application source: if the whole buffer stays silent for 8 s, macOS may
  -- block the helper (no permission), or the app plays nothing. Then show a
  -- clean centred note instead of an empty waveform.
  local show_hint = false
  if mode == "app" then
    local now = reaper.time_precise()
    if maxpeak > 0.00001 then last_sound_time = now end
    show_hint = now - last_sound_time > 8
  else
    last_sound_time = reaper.time_precise()
  end

  -- mirrored (top+bottom) waveform: a solid filled shape between each pair
  -- of points (no per-point spoke lines, so no visible vertical lines),
  -- plus a full-brightness outline stroke along the envelope for crispness
  local FILL_ALPHA = 0.4
  local step = wf_w / disp_n
  local lx, ly1, ly2
  if show_hint then
    local _, key, name = get_app_status()
    local lines = {
      key == "ALL" and "No system audio." or ("No audio from " .. name .. "."),
    }
    if IS_MAC then
      lines[2] = 'If sound is playing, allow "Daniel_App Audio Helper" in'
      lines[3] = "System Settings > Privacy & Security > Screen & System Audio Recording."
    end
    gfx.setfont(1, "Arial", 14)
    local line_h = 19
    local y = math.floor(center_y - (#lines * line_h) / 2 + 0.5)
    for i, text in ipairs(lines) do
      if i == 1 then gfx.set(0.85, 0.85, 0.85, 1) else gfx.set(0.6, 0.6, 0.6, 1) end
      local tw = gfx.measurestr(text)
      gfx.x, gfx.y = math.floor(wf_x + (wf_w - tw) / 2 + 0.5), y
      gfx.drawstr(text)
      y = y + line_h
    end
  end
  for i = 0, (show_hint and -1 or disp_n - 1) do
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

  if not show_hint then
    -- center line
    gfx.set(BLUE_R, BLUE_G, BLUE_B, 0.3)
    gfx.line(wf_x, center_y, wf_x + wf_w, center_y)

    -- write-head marker
    gfx.set(1, 1, 0.2, 0.85)
    local head_x = wf_x + write_head * wf_w
    gfx.line(head_x, wf_y, head_x, wf_y + wf_h)
  end

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
  if HAS_EXT then reaper.Daniel_AlwaysRec_SetEnabled(false) end -- buffer off with the window
  set_visual_state(false) -- buttons off; the ini flag is left alone when REAPER is quitting
  if closed_by_user and CAN_REMEMBER then reaper.Daniel_AlwaysRec_SetWindowOpen(false) end -- window X: don't reopen at the next start
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
sync_buffer()   -- buffer on with the window (Hardware input / Application mode)
-- Started via defer (not called directly) so the leftover cleanup happens
-- outside the script's initial run -- that keeps REAPER from adding an
-- automatic "ReaScript" undo point for it.
reaper.defer(function()
  pcall(remove_old_hidden_tracks)
  main()
end)
