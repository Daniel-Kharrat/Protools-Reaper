-- @description Daniel_Marker based cleanup
-- @about
--   Select your voice track and run this script. At the top of the window, choose
--   which markers to clean: by COLOUR (click a colour) or by NAME (click a name, or
--   type one, e.g. "clipping"). The script jumps to each of those markers and
--   razor-selects the space between the words around it (the marker is always
--   inside the selection). When the chosen markers run out it stops; choosing
--   other markers is always up to you. Red markers are selected by default.
--
--   Keys (while the window is focused) - click any key in the window to change it:
--     Enter = cut & next
--     A = start earlier (expand left)     D = start later (shrink left)
--     S = end earlier   (shrink right)    F = end later   (expand right)
--     Cmd/Ctrl+Z = undo   Cmd/Ctrl+Shift+Z = redo
--   Shortcuts can include modifiers (Cmd/Ctrl, Shift, Option/Alt, Control/Win).
--     C / V = edit cursor back / forward (small step)
--     Z / X = edit cursor back / forward (big step)
--     G = loop playback on / off
--     Space = play/stop
--     B = Space plays from the start of the selection / from the cursor (toggle)
--     Option/Alt+Z or [ = previous marker   Option/Alt+X or ] = next marker
--     Esc = clear selection (close the window with its close button)

---------------------------------------------------------------- SETTINGS
local NUDGE    = 0.02  -- how much A/S/D/F move an edge (seconds)
local PAD      = 0.02  -- how far the selection stays from the words (seconds)
local MAX_SEL  = 0.8   -- longest selection allowed (seconds)
local CURSOR_SMALL = 0.2 -- how far C/V move the edit cursor (seconds)
local CURSOR_BIG   = 1.0 -- how far Z/X move the edit cursor (seconds)

local OS_IS_MAC = reaper.GetOS():find("OSX") ~= nil or reaper.GetOS():find("mac") ~= nil
-- settings are saved in reaper-extstate.ini under a section named after this script
local SECTION = "Daniel_Marker based cleanup"
local EPS = 0.0001

---------------------------------------------------------------- WHICH MARKERS
-- target = "c:RRGGBB" / "c:default" (by colour) or "n:<name>" (by name), nil = not chosen
local target = reaper.GetExtState(SECTION, "target2")
if target == "" then target = nil end
local pick_mode = (target and target:sub(1, 2) == "n:") and "name" or "colour"

local function rgb_of(color)
  if not color or color == 0 then return nil end
  return reaper.ColorFromNative((color // 1) & 0xFFFFFF)
end

local function color_key(color)
  local r, g, b = rgb_of(color)
  return r and string.format("%02X%02X%02X", r, g, b) or "default"
end

local function norm(s)
  s = (s or ""):lower()
  s = s:gsub("^%s+", "")
  s = s:gsub("%s+$", "")
  return s
end

local function by_colour() return target and target:sub(1, 2) == "c:" end

local function matches(m)
  if not target or m.isrgn then return false end
  if by_colour() then return color_key(m.color) == target:sub(3) end
  return norm(m.name) == target:sub(3)
end

---------------------------------------------------------------- MARKERS
local function list_markers()
  local t, i = {}, 0
  while true do
    local rv, isrgn, pos, rend, name, id, color = reaper.EnumProjectMarkers3(0, i)
    if rv == 0 then break end
    t[#t + 1] = { isrgn = isrgn, pos = pos, rend = rend, name = name, id = id, color = color }
    i = i + 1
  end
  return t
end

local function target_markers()
  local t = {}
  for _, m in ipairs(list_markers()) do
    if matches(m) then t[#t + 1] = m end
  end
  return t
end

local function next_target(from)
  for _, m in ipairs(target_markers()) do
    if m.pos >= from then return m end
  end
end

-- the marker currently being worked on (remembered in the project)
local function get_current()
  local _, v = reaper.GetProjExtState(0, SECTION, "pending")
  local id = tonumber(v:match("^(%-?%d+)|"))
  if not id then return nil end
  for _, m in ipairs(target_markers()) do
    if m.id == id then return m end
  end
end

local function set_current(m)
  reaper.SetProjExtState(0, SECTION, "pending",
    m and string.format("%d|%.10f", m.id, m.pos) or "")
end

---------------------------------------------------------------- RAZOR
local function clear_all_razors()
  for i = 0, reaper.CountTracks(0) - 1 do
    reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, i), "P_RAZOREDITS", "", true)
  end
end

local function get_razor(tr)
  local _, str = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  for a, b, g in str:gmatch('(%S+)%s+(%S+)%s+"([^"]*)"') do
    if g == "" then return tonumber(a), tonumber(b) end
  end
end

-- time selection + loop points always follow the razor selection, so loop playback works
local function set_time_and_loop(a, b)
  reaper.GetSet_LoopTimeRange2(0, true, false, a, b, false) -- time selection
  reaper.GetSet_LoopTimeRange2(0, true, true, a, b, false)  -- loop points
end

local function set_razor(tr, a, b)
  reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS",
    string.format('%.10f %.10f ""', a, b), true)
  set_time_and_loop(a, b)
end

---------------------------------------------------------------- FIND THE SPACE BETWEEN WORDS
-- Starts AT the marker and looks before and after it for where the words are.
-- The selection is the space around the marker, so the marker is always inside it.
local function find_gap(track, mpos)
  local t0 = math.max(0, mpos - 1.0)
  local t1 = mpos + 1.0
  local sr, fl = 16000, 160 -- 10 ms frames
  local fdur = fl / sr
  local nframes = math.floor((t1 - t0) / fdur)
  if nframes < 10 then return nil end
  local n = nframes * fl

  local acc = reaper.CreateTrackAudioAccessor(track)
  local buf = reaper.new_array(n)
  local ok = reaper.GetAudioAccessorSamples(acc, sr, 1, t0, n, buf)
  reaper.DestroyAudioAccessor(acc)
  if ok ~= 1 then return nil end
  local s = buf.table()

  -- level of each 10 ms slice
  local db, peak = {}, -200
  for f = 1, nframes do
    local sum, base = 0, (f - 1) * fl
    for i = base + 1, base + fl do local v = s[i]; sum = sum + v * v end
    db[f] = 10 * math.log(sum / fl + 1e-12, 10)
    if db[f] > peak then peak = db[f] end
  end
  local sorted = { table.unpack(db) }
  table.sort(sorted)
  local floor = sorted[math.max(1, math.floor(nframes * 0.1))]
  if peak - floor < 10 then return nil end
  local thr = floor + 0.4 * (peak - floor)

  -- words = loud and long enough; short/weak bits (clicks, smacks) count as space
  local word = {}
  for f = 1, nframes do word[f] = db[f] > thr end
  local mf = math.max(1, math.min(nframes, math.floor((mpos - t0) / fdur) + 1))
  local f = 1
  while f <= nframes do
    if word[f] then
      local g, mx = f, db[f]
      while g + 1 <= nframes and word[g + 1] do g = g + 1; if db[g] > mx then mx = db[g] end end
      local len = g - f + 1
      local noise = (f > 1 and g < nframes) and (len < 8 or mx < peak - 18)
      -- the loud bit right under the marker is probably the noise itself
      if f <= mf and mf <= g and len < 18 and mx < peak - 6 then noise = true end
      if noise then for k = f, g do word[k] = false end end
      f = g + 1
    else
      f = f + 1
    end
  end

  local function t_of(fr) return t0 + (fr - 1) * fdur end

  if word[mf] then
    -- marker sits on a word: use the nearest space right next to it (within 0.3 s)
    local l, r = mf, mf
    while l > 1 and word[l] do l = l - 1 end
    while r < nframes and word[r] do r = r + 1 end
    local dl = word[l] and math.huge or (mf - l) * fdur
    local dr = word[r] and math.huge or (r - mf) * fdur
    if math.min(dl, dr) > 0.3 then return nil end
    mf = (dl <= dr) and l or r
  end

  -- grow left and right from the marker until we hit a word
  local l, r = mf, mf
  while l > 1 and not word[l - 1] do l = l - 1 end
  while r < nframes and not word[r + 1] do r = r + 1 end
  local a, b = t_of(l), t_of(r + 1)

  -- stay a little away from the words, but never past the marker
  local anchor = t_of(mf) + fdur / 2
  if not (anchor >= mpos - fdur and anchor <= mpos + fdur) then anchor = math.min(math.max(mpos, a), b) end
  if l > 1 then a = math.min(a + PAD, anchor - 0.01) end
  if r < nframes then b = math.max(b - PAD, anchor + 0.01) end

  -- very long pause: keep MAX_SEL around the marker
  if b - a > MAX_SEL then
    local half = MAX_SEL / 2
    local na, nb = anchor - half, anchor + half
    if na < a then nb = math.min(b, nb + (a - na)); na = a end
    if nb > b then na = math.max(a, na - (nb - b)); nb = b end
    a, b = na, nb
  end
  return math.max(0, a), b
end

---------------------------------------------------------------- SELECT
local function select_marker(track, m)
  local a, b = find_gap(track, m.pos)
  if not a then a, b = math.max(0, m.pos - 0.15), m.pos + 0.15 end -- fallback: around the marker
  clear_all_razors()
  set_razor(track, a, b)
  set_current(m)

  -- keep it in view
  local vs, ve = reaper.GetSet_ArrangeView2(0, false, 0, 0, 0, 0)
  local w = ve - vs
  local zoom = w > 30
  if zoom then w = 6 end
  local c = (a + b) / 2
  if zoom or c < vs + (ve - vs) * 0.2 or c > vs + (ve - vs) * 0.8 then
    local ns = math.max(0, c - w / 2)
    reaper.GetSet_ArrangeView2(0, true, 0, 0, ns, ns + w)
  end
  reaper.SetEditCurPos(a, false, false)
end

local function select_next(track, from)
  local m = next_target(from) or next_target(-1)
  if m then select_marker(track, m); return true end
  clear_all_razors()
  set_time_and_loop(0, 0)
  set_current(nil)
  return false
end

---------------------------------------------------------------- CUT
local function cut_track(tr, a, b)
  local items = {}
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do items[#items + 1] = reaper.GetTrackMediaItem(tr, i) end
  for _, it in ipairs(items) do
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local q = p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if p < b - EPS and q > a + EPS then
      local mid = it
      if p < a - EPS then
        mid = reaper.SplitMediaItem(it, a)
        if mid then
          reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN",
            math.max(reaper.GetMediaItemInfo_Value(it, "D_FADEOUTLEN"), 0.005))
        end
      end
      local safe = mid ~= nil
      if mid and q > b + EPS then
        local right = reaper.SplitMediaItem(mid, b)
        if right then
          reaper.SetMediaItemInfo_Value(right, "D_FADEINLEN",
            math.max(reaper.GetMediaItemInfo_Value(right, "D_FADEINLEN"), 0.005))
        else
          safe = false -- never delete audio past the selection
        end
      end
      if safe then reaper.DeleteTrackMediaItem(tr, mid) end
    end
  end
end

local function shift_items(tr, a, len)
  local items = {}
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do items[#items + 1] = reaper.GetTrackMediaItem(tr, i) end
  for _, it in ipairs(items) do
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    if p > a + EPS then reaper.SetMediaItemInfo_Value(it, "D_POSITION", p - len) end
  end
end

local function shift_markers(a, b, targetOnly)
  local len = b - a
  local function moved(x)
    if x >= b - EPS then return x - len end
    if x > a then return a end
    return x
  end
  for _, m in ipairs(list_markers()) do
    if m.isrgn then
      if not targetOnly then
        local np, ne = moved(m.pos), moved(m.rend)
        if np ~= m.pos or ne ~= m.rend then reaper.SetProjectMarker3(0, m.id, true, np, ne, m.name, m.color) end
      end
    elseif (not targetOnly) or matches(m) then
      local np = moved(m.pos)
      if np ~= m.pos then reaper.SetProjectMarker3(0, m.id, false, np, 0, m.name, m.color) end
    end
  end
end

-- follows your ripple editing mode
local function cut_range(track, a, b)
  local rAll   = reaper.GetToggleCommandState(40311) == 1
  local rTrack = reaper.GetToggleCommandState(40310) == 1
  local tracks = { track }
  if rAll then
    tracks = {}
    for i = 0, reaper.CountTracks(0) - 1 do tracks[#tracks + 1] = reaper.GetTrack(0, i) end
  end
  for _, tr in ipairs(tracks) do
    cut_track(tr, a, b)
    if rAll or rTrack then shift_items(tr, a, b - a) end
  end
  if rAll then shift_markers(a, b, false)
  elseif rTrack then shift_markers(a, b, true) end
end

---------------------------------------------------------------- ACTIONS
local message, message_time = "", 0
local function say(msg) message, message_time = msg or "", reaper.time_precise() end

local initial_count = 0

local function with_track(fn, undo_name)
  local track = reaper.GetSelectedTrack(0, 0)
  if not track then say("Select your voice track first"); return end
  if undo_name then reaper.Undo_BeginBlock() end
  reaper.PreventUIRefresh(1)
  local ok, err = pcall(fn, track)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  if undo_name then reaper.Undo_EndBlock(undo_name, -1) end
  if not ok then
    say("Error - see console")
    reaper.ShowConsoleMsg("Marker Cleanup error: " .. tostring(err) .. "\n")
  end
end

-- switch which markers we clean, and go to the first one
local function switch_target(key, track, from)
  target = key
  reaper.SetExtState(SECTION, "target2", key, true)
  set_current(nil)
  initial_count = #target_markers()
  clear_all_razors()
  return select_next(track, from or (reaper.GetCursorPosition() - 0.001))
end

local function start(track)
  if not target then return end
  local m = get_current()
  if m and get_razor(track) then return end -- resume where you left off
  if m then select_marker(track, m); return end
  if not select_next(track, reaper.GetCursorPosition() - 0.001) then say("No markers to clean") end
end

local function cut_and_next(track)
  local m = get_current()
  local a, b = get_razor(track)
  if not (m and a) then return start(track) end
  -- remove this marker and any other matching marker inside the selection
  for _, r in ipairs(target_markers()) do
    if r.id == m.id or (r.pos >= a - EPS and r.pos <= b + EPS) then
      reaper.DeleteProjectMarker(0, r.id, false)
    end
  end
  cut_range(track, a, b)
  clear_all_razors()
  set_current(nil)
  if select_next(track, a) then say("Cut") else say("All clean!") end
end

local function nudge(edge, dir)
  return function(track)
    local a, b = get_razor(track)
    if not a then return end
    if edge == "start" then a = math.max(0, a + dir * NUDGE) else b = b + dir * NUDGE end
    if b - a >= 0.01 then set_razor(track, a, b) end
  end
end

-- after undo/redo: keep the loop points and current marker in step with the restored selection
local function after_undo()
  local track = reaper.GetSelectedTrack(0, 0)
  if not track then return end
  local a, b = get_razor(track)
  if not a then return end
  set_time_and_loop(a, b)
  local best, bd
  for _, m in ipairs(target_markers()) do
    local d = (m.pos < a) and (a - m.pos) or ((m.pos > b) and (m.pos - b) or 0)
    if d < 1 and (not bd or d < bd) then best, bd = m, d end
  end
  if best then set_current(best) end
end

local function do_undo() reaper.Main_OnCommand(40029, 0); after_undo(); say("Undo") end
local function do_redo() reaper.Main_OnCommand(40030, 0); after_undo(); say("Redo") end

local function move_cursor(amount)
  local playing = reaper.GetPlayState() & 1 == 1
  local pos = playing and reaper.GetPlayPosition() or reaper.GetCursorPosition()
  reaper.SetEditCurPos(math.max(0, pos + amount), true, true)
end

local function toggle_loop()
  reaper.Main_OnCommand(1068, 0) -- Transport: Toggle repeat
  say(reaper.GetToggleCommandState(1068) == 1 and "Loop on" or "Loop off")
end

-- the red marker colour used in this project (if any)
local function red_target()
  for _, m in ipairs(list_markers()) do
    local r, g, b = rgb_of(m.color)
    if not m.isrgn and r and r >= 150 and g <= 110 and b <= 110 then
      return "c:" .. color_key(m.color)
    end
  end
end

-- the switch happens at the start of the next frame (see loop), so the frame being drawn
-- doesn't mix the old marker with the new selection (that made the waveform flicker)
local PENDING = {}
local function set_target(key)
  if key == target then return end
  PENDING.target = key
end

---------------------------------------------------------------- PREVIOUS / NEXT MARKER
-- jump to the previous / next marker of the chosen kind and select its gap (nothing is cut)
local function goto_marker(dir)
  return function(track)
    if not target then say("Choose which markers to clean first"); return end
    local list = target_markers()
    if #list == 0 then say("No markers to clean"); return end
    local cur = get_current()
    local ref = cur and cur.pos or reaper.GetCursorPosition()
    local pick
    if dir < 0 then
      for i = #list, 1, -1 do
        if list[i].pos < ref - EPS then pick = list[i]; break end
      end
      if not pick then say("This is the first marker"); return end
    else
      for i = 1, #list do
        if list[i].pos > ref + EPS then pick = list[i]; break end
      end
      if not pick then say("This is the last marker"); return end
    end
    select_marker(track, pick)
  end
end

---------------------------------------------------------------- KEYS (customizable)
-- Space plays from the start of the selection (true) or like normal REAPER play (false)
local play_from_sel = reaper.GetExtState(SECTION, "play_from_sel") ~= "0"

-- A shortcut = a key + modifiers. Modifier bits (from gfx.mouse_cap):
--   4 = Cmd (Mac) / Ctrl,  8 = Shift,  16 = Option (Mac) / Alt,  32 = Control (Mac) / Win
local MOD_MASK = 4 | 8 | 16 | 32
local IS_MAC = OS_IS_MAC

local ACTION_FN = {
  cut           = function() with_track(cut_and_next, "Marker cleanup: cut") end,
  play          = function()
    if reaper.GetPlayState() & 1 == 1 then reaper.OnStopButton(); return end
    -- play from the start of the time selection (if that mode is on and there is one)
    if play_from_sel then
      local ts, te = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
      if te > ts then reaper.SetEditCurPos(ts, false, false) end
    end
    reaper.OnPlayButton()
  end,
  prev_marker   = function() with_track(goto_marker(-1)) end,
  prev_marker2  = function() with_track(goto_marker(-1)) end,
  next_marker   = function() with_track(goto_marker( 1)) end,
  next_marker2  = function() with_track(goto_marker( 1)) end,
  play_mode     = function()
    play_from_sel = not play_from_sel
    reaper.SetExtState(SECTION, "play_from_sel", play_from_sel and "1" or "0", true)
    say(play_from_sel and "Space plays from selection start" or "Space plays normally")
  end,
  clear         = function()
    clear_all_razors()
    set_time_and_loop(0, 0)
    reaper.UpdateArrange()
    say("Selection cleared")
  end,
  start_earlier = function() with_track(nudge("start", -1)) end,
  start_later   = function() with_track(nudge("start",  1)) end,
  end_earlier   = function() with_track(nudge("end",   -1)) end,
  end_later     = function() with_track(nudge("end",    1)) end,
  undo          = do_undo,
  redo          = do_redo,
  back_small    = function() move_cursor(-CURSOR_SMALL) end,
  fwd_small     = function() move_cursor( CURSOR_SMALL) end,
  back_big      = function() move_cursor(-CURSOR_BIG) end,
  fwd_big       = function() move_cursor( CURSOR_BIG) end,
  loop          = toggle_loop,
}

local ACTION_LABEL = {
  cut = "Cut & next", play = "Play / stop",
  start_earlier = "Start earlier", start_later = "Start later",
  end_earlier = "End earlier", end_later = "End later",
  undo = "Undo", redo = "Redo",
  back_small = "Cursor back (small)", fwd_small = "Cursor forward (small)",
  back_big = "Cursor back (big)", fwd_big = "Cursor forward (big)", loop = "Loop on / off",
  clear = "Clear selection",
  play_mode = "Play from selection / normal",
  prev_marker = "Previous marker", prev_marker2 = "Previous marker (2nd key)",
  next_marker = "Next marker", next_marker2 = "Next marker (2nd key)",
}

local DEFAULT_KEYS = {
  cut           = { 13, 0 },   -- Enter
  play          = { 32, 0 },   -- Space
  start_earlier = { 97, 0 },   -- A
  start_later   = { 100, 0 },  -- D
  end_earlier   = { 115, 0 },  -- S
  end_later     = { 102, 0 },  -- F
  undo          = { 122, 4 },  -- Cmd/Ctrl+Z
  redo          = { 122, 12 }, -- Cmd/Ctrl+Shift+Z
  back_small    = { 99, 0 },   -- C
  fwd_small     = { 118, 0 },  -- V
  back_big      = { 122, 0 },  -- Z
  fwd_big       = { 120, 0 },  -- X
  loop          = { 103, 0 },  -- G
  clear         = { 27, 0 },   -- Esc
  play_mode     = { 98, 0 },   -- B
  prev_marker   = { 122, 16 }, -- Option/Alt+Z
  prev_marker2  = { 91, 0 },   -- [
  next_marker   = { 120, 16 }, -- Option/Alt+X
  next_marker2  = { 93, 0 },   -- ]
}

local KEYMAP = {}

local function reset_keys()
  for k, v in pairs(DEFAULT_KEYS) do KEYMAP[k] = { v[1], v[2] } end
end

local function load_keys()
  reset_keys()
  for id, code, mods in reaper.GetExtState(SECTION, "keys2"):gmatch("([%w_]+)=(%d+):?(%d*)") do
    if KEYMAP[id] then KEYMAP[id] = { tonumber(code), tonumber(mods) or 0 } end
  end
  -- saved from the version where B was loop and G was play mode: swap to the new layout
  local l, pm = KEYMAP.loop, KEYMAP.play_mode
  if l[1] == 98 and l[2] == 0 and pm[1] == 103 and pm[2] == 0 then
    KEYMAP.loop, KEYMAP.play_mode = pm, l
  end
end

local function save_keys()
  local t = {}
  for k, v in pairs(KEYMAP) do t[#t + 1] = string.format("%s=%d:%d", k, v[1], v[2]) end
  reaper.SetExtState(SECTION, "keys2", table.concat(t, ";"), true)
end

-- turn what gfx.getchar gives us into (base key, modifiers)
-- macOS (US layout): Option+letter types these characters; map them back to the letter
local MAC_OPTION_CHARS = {
  [229] = "a", [8747] = "b", [231] = "c", [8706] = "d", [402] = "f", [169] = "g", [729] = "h",
  [8710] = "j", [730] = "k", [172] = "l", [181] = "m", [248] = "o", [960] = "p", [339] = "q",
  [174] = "r", [223] = "s", [8224] = "t", [8730] = "v", [8721] = "w", [8776] = "x", [165] = "y",
  [937] = "z",
}

local function decode(ch, cap)
  local mods = cap & MOD_MASK
  -- unicode characters can arrive as 'u'<<24 + code
  if ch >= 0x75000000 and ch < 0x76000000 then ch = ch - 0x75000000 end
  if MAC_OPTION_CHARS[ch] then
    return string.byte(MAC_OPTION_CHARS[ch]), mods | 16
  end
  local base = ch
  -- Ctrl/Cmd + letter arrives as 1..26 (but keep Enter, Tab, Backspace as they are)
  if (mods & 4) ~= 0 and ch >= 1 and ch <= 26 and ch ~= 8 and ch ~= 9 and ch ~= 13 then base = ch + 96 end
  -- Alt + key can arrive offset by 256
  if (mods & 16) ~= 0 and ch > 256 and ch < 512 then base = ch - 256 end
  if base >= 65 and base <= 90 then base = base + 32 end -- letters: one name per key
  return base, mods
end

local KEY_NAMES = {
  [13] = "Enter", [32] = "Space", [27] = "Esc", [8] = "Backspace", [9] = "Tab",
  [1818584692] = "Left", [1919379572] = "Right", [30064] = "Up", [1685026670] = "Down",
  [6579564] = "Delete", [1752132965] = "Home", [6647396] = "End",
  [1885828464] = "PgUp", [1885824110] = "PgDn",
}

local function key_name(k)
  local code, mods = k[1], k[2]
  local name = KEY_NAMES[code]
    or ((code >= 33 and code <= 126) and string.char(code):upper())
    or ("#" .. code)
  local parts = {}
  if IS_MAC then
    if mods & 32 ~= 0 then parts[#parts + 1] = "Ctrl" end
    if mods & 16 ~= 0 then parts[#parts + 1] = "Opt" end
    if mods & 8  ~= 0 then parts[#parts + 1] = "Shift" end
    if mods & 4  ~= 0 then parts[#parts + 1] = "Cmd" end
  else
    if mods & 4  ~= 0 then parts[#parts + 1] = "Ctrl" end
    if mods & 16 ~= 0 then parts[#parts + 1] = "Alt" end
    if mods & 8  ~= 0 then parts[#parts + 1] = "Shift" end
    if mods & 32 ~= 0 then parts[#parts + 1] = "Win" end
  end
  parts[#parts + 1] = name
  return table.concat(parts, "+")
end

local function handle_key(ch)
  local base, mods = decode(ch, gfx.mouse_cap)
  for id, k in pairs(KEYMAP) do
    if k[1] == base and k[2] == mods then ACTION_FN[id](); return end
  end
  -- Cmd/Ctrl + the undo key = undo, with Shift = redo (works on top of your own keys)
  if (mods & 4) ~= 0 and base == KEYMAP.undo[1] then
    if (mods & 8) ~= 0 then do_redo() else do_undo() end
  end
end

-- the action waiting for a new key (after you click its key in the window)
local capturing = nil

-- shortcut list shown or hidden (remembered)
local shortcuts_hidden = reaper.GetExtState(SECTION, "shortcuts_hidden") == "1"
local last_nrows = 5        -- rows the shortcut list used last time it was drawn
local resize_by = 0         -- window height change waiting to be applied (logical px)
local show_at_h = nil       -- when expanding: show the list once the window is this tall
local show_deadline = 0     -- ...or after this time, in case the window couldn't grow

local function assign_key(id, ch)
  local base, mods = decode(ch, gfx.mouse_cap)
  if base < 32 and base ~= 8 and base ~= 9 and base ~= 13 and base ~= 27 then say("That key can't be used"); return end
  local old = KEYMAP[id]
  for other, k in pairs(KEYMAP) do
    if other ~= id and k[1] == base and k[2] == mods then KEYMAP[other] = old end -- swap
  end
  KEYMAP[id] = { base, mods }
  save_keys()
  say(key_name(KEYMAP[id]) .. " = " .. ACTION_LABEL[id])
end

load_keys()

---------------------------------------------------------------- LOOK
local COL = {
  bg     = 0x17171B,
  panel  = 0x222228,
  line   = 0x2E2E36,
  text   = 0xEDEDF2,
  muted  = 0x8A8A96,
  dim    = 0x5C5C68,
  accent = 0xF2555A,
  wave   = 0x70707E,
  key    = 0x2F2F38,
  keyon  = 0x474754,
  keyedge= 0x45454F,
  note   = 0xF2C46D,
  white  = 0xFFFFFF,
  on_accent = 0xFFFFFF, -- text drawn on top of the accent colour
}

local OS = reaper.GetOS()
local FONT = (OS:find("OSX") or OS:find("mac")) and "Helvetica Neue"
          or (OS:find("Win") and "Segoe UI" or "DejaVu Sans")

local S, fontScale = 1, nil

local function setup_fonts()
  gfx.setfont(1, FONT, 14 * S)
  gfx.setfont(2, FONT, 26 * S, string.byte("b"))
  gfx.setfont(3, FONT, 12 * S)
  gfx.setfont(4, FONT, 11 * S, string.byte("b"))
  gfx.setfont(5, FONT, 12.5 * S, string.byte("b")) -- Colour / Name switch
  fontScale = S
end

local function color(hex, a)
  gfx.set(((hex >> 16) & 255) / 255, ((hex >> 8) & 255) / 255, (hex & 255) / 255, a or 1)
end

-- all drawing below works in logical units (scaled for Retina screens)
local function rect(x, y, w, h, hex, a)
  color(hex, a)
  gfx.rect(math.floor(x * S), math.floor(y * S), math.ceil(w * S), math.ceil(h * S), 1)
end

-- Shapes are filled row by row with gfx.rect only (with smooth, anti-aliased edges), so they
-- look the same on macOS, Windows and Linux. (gfx.circle draws a different size on each OS,
-- which made rounded shapes bulge at the ends on Linux.)
local SUB = { 0.125, 0.375, 0.625, 0.875 }   -- 4 sample lines per pixel row
local Ls, Rs = {}, {}

-- fill a shape given by span(y) -> left, right (pixel units), between pixel rows y0 and y1
local function fill_rows(y0, y1, span, a)
  local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
  for j = floor(y0), ceil(y1) - 1 do
    local n = 0
    for k = 1, 4 do
      local yc = j + SUB[k]
      if yc > y0 and yc < y1 then
        local l, r = span(yc)
        if l and r > l then n = n + 1; Ls[n], Rs[n] = l, r end
      end
    end
    if n > 0 then
      local minL, maxL, minR, maxR = Ls[1], Ls[1], Rs[1], Rs[1]
      for k = 2, n do
        minL = min(minL, Ls[k]); maxL = max(maxL, Ls[k])
        minR = min(minR, Rs[k]); maxR = max(maxR, Rs[k])
      end
      local function edge(p0, p1)
        for p = p0, p1 do
          local cov = 0
          for k = 1, n do
            local o = min(p + 1, Rs[k]) - max(p, Ls[k])
            if o > 0 then cov = cov + o end
          end
          if cov > 0.01 then gfx.a = a * cov / 4; gfx.rect(p, j, 1, 1, 1) end
        end
      end
      local i0, i1 = ceil(maxL), floor(minR)
      if i1 > i0 then
        gfx.a = a * n / 4
        gfx.rect(i0, j, i1 - i0, 1, 1)
        edge(floor(minL), i0 - 1)
        edge(i1, ceil(maxR) - 1)
      else
        edge(floor(minL), ceil(maxR) - 1)
      end
    end
  end
end

local function rrect(x, y, w, h, r, hex, a)
  a = a or 1
  color(hex, a)
  local X, Y, W, H = x * S, y * S, w * S, h * S
  local R = math.min(r * S, H / 2, W / 2)
  if W <= 0 or H <= 0 then return end
  local function span(yc)
    local dy = 0
    if yc < Y + R then dy = Y + R - yc elseif yc > Y + H - R then dy = yc - (Y + H - R) end
    local ins = R - math.sqrt(math.max(0, R * R - dy * dy))
    return X + ins, X + W - ins
  end
  -- the straight middle part in one go (fast), the rounded top and bottom row by row
  local m0, m1 = math.ceil(Y + R), math.floor(Y + H - R)
  if m1 > m0 then
    fill_rows(Y, m0, span, a)
    local i0, i1 = math.ceil(X), math.floor(X + W)
    gfx.a = a
    if i1 > i0 then gfx.rect(i0, m0, i1 - i0, m1 - m0, 1) end
    local lc = i0 - X                       -- left edge column coverage
    if lc > 0.01 then gfx.a = a * lc; gfx.rect(i0 - 1, m0, 1, m1 - m0, 1) end
    local rc = X + W - i1                   -- right edge column coverage
    if rc > 0.01 then gfx.a = a * rc; gfx.rect(i1, m0, 1, m1 - m0, 1) end
    fill_rows(m1, Y + H, span, a)
  else
    fill_rows(Y, Y + H, span, a)
  end
end

-- filled circle, or a ring (fill = false) drawn on the window background
local function circle(x, y, r, hex, fill, a)
  rrect(x - r, y - r, 2 * r, 2 * r, r, hex, a)
  if not fill then rrect(x - r + 1.25, y - r + 1.25, 2 * r - 2.5, 2 * r - 2.5, r - 1.25, COL.bg) end
end

-- filled triangle pointing down: flat top edge from (xl, yt) to (xr, yt), tip at (xm, yb); logical units
local function tri_down(xl, xr, yt, xm, yb, hex, a)
  a = a or 1
  color(hex, a)
  local XL, XR, YT, XM, YB = xl * S, xr * S, yt * S, xm * S, yb * S
  fill_rows(YT, YB, function(yc)
    local t = (yc - YT) / (YB - YT)
    return XL + (XM - XL) * t, XR + (XR - XM) * -t
  end, a)
end

local function text_w(str, font)
  gfx.setfont(font)
  return (gfx.measurestr(str)) / S
end

local function text(str, x, y, font, hex, align, a)
  gfx.setfont(font)
  color(hex, a)
  local w = gfx.measurestr(str)
  local px = x * S
  if align == "right" then px = px - w elseif align == "center" then px = px - w / 2 end
  gfx.x, gfx.y = math.floor(px), math.floor(y * S)
  gfx.drawstr(str)
end

-- where the letters actually are (top and bottom of the ink, in logical px from the draw y),
-- measured once by drawing into an off-screen buffer. Used to centre text exactly top to bottom.
local ink_cache = {}
local function ink_span(str, font)
  local key = font .. "|" .. S .. "|" .. str
  local c = ink_cache[key]
  if c then return c[1], c[2] end
  gfx.setfont(font)
  local w, h = gfx.measurestr(str)
  local bw, bh = math.ceil(w) + 4, math.ceil(h) + 4
  local old_dest = gfx.dest
  gfx.dest = 127
  gfx.setimgdim(127, 0, 0)
  gfx.setimgdim(127, bw, bh)
  gfx.set(0, 0, 0, 1); gfx.rect(0, 0, bw, bh, 1)
  gfx.set(1, 1, 1, 1); gfx.x, gfx.y = 2, 2; gfx.drawstr(str)
  local top, bot
  for py = 0, bh - 1 do
    for px = 0, bw - 1 do
      gfx.x, gfx.y = px, py
      local r = gfx.getpixel()
      if r > 0.35 then
        top = top or py
        bot = py
        break
      end
    end
  end
  gfx.dest = old_dest
  if not top then top, bot = 2, 2 + h end
  c = { (top - 2) / S, (bot + 1 - 2) / S }
  ink_cache[key] = c
  return c[1], c[2]
end

-- draw text centred on (cx, cy): left to right by its width, top to bottom by its ink
local function text_centred(str, cx, cy, font, hex, ref)
  local t, b = ink_span(ref or str, font)
  text(str, cx, cy - (t + b) / 2, font, hex, "center")
end

local function keycap(label, x, y, hl)
  local w = math.max(22, text_w(label, 4) + 14)
  rrect(x, y + 1, w, 22, 5, hl and COL.accent or COL.keyedge)
  rrect(x, y, w, 21, 5, hl and COL.accent or COL.key)
  text(label, x + w / 2, y + 4, 4, hl and COL.on_accent or COL.text, "center")
  return x + w
end

---------------------------------------------------------------- SUPPORT (Ko-fi)
local SUPPORT_URL = "https://ko-fi.com/danielkharrat"


local function heart(cx, cy, hex, a, k)
  k = k or 1
  circle(cx - 2.6 * k, cy - 1.2 * k, 3.1 * k, hex, true, a)
  circle(cx + 2.6 * k, cy - 1.2 * k, 3.1 * k, hex, true, a)
  tri_down(cx - 5.6 * k, cx + 5.6 * k, cy - 0.2 * k, cx, cy + 5.6 * k, hex, a)
end

local function open_url(url)
  if reaper.CF_ShellExecute then reaper.CF_ShellExecute(url) return end -- SWS
  local os_name = reaper.GetOS()
  if os_name:find("Win") then os.execute('start "" "' .. url .. '"')
  elseif os_name:find("OSX") or os_name:find("mac") then os.execute('open "' .. url .. '"')
  else os.execute('xdg-open "' .. url .. '" &') end
end

-- tooltip for the heart: shows after the mouse rests on it for half a second.
-- Drawn inside the window in the script's own style (REAPER's tooltip is yellow).
local TIP_TEXT = "Support my work on Ko-fi"
local tip_since, tip_visible = nil, false
local function support_tooltip(hover)
  if hover then
    tip_since = tip_since or reaper.time_precise()
    tip_visible = reaper.time_precise() - tip_since > 0.5
  else
    tip_since, tip_visible = nil, false
  end
end

---------------------------------------------------------------- MOUSE
local mx, my, clicked, mouse_prev = 0, 0, false, false
local press_x, press_y

local function hit(x, y, w, h, px, py)
  px, py = px or mx, py or my
  return px and px >= x and px < x + w and py >= y and py < y + h
end

local function was_clicked(x, y, w, h)
  return clicked and hit(x, y, w, h) and hit(x, y, w, h, press_x, press_y)
end

---------------------------------------------------------------- WAVEFORM
local wave = { key = nil, peaks = {}, cols = 0 }

local function update_wave(track, t0, t1, cols)
  local key = string.format("%s|%.3f|%.3f|%d|%d", tostring(track), t0, t1, cols,
    reaper.GetProjectStateChangeCount(0))
  if key == wave.key then return end
  wave = { key = key, peaks = {}, cols = cols }
  local sr = 8000
  local n = math.floor((t1 - t0) * sr)
  if n < cols or cols < 2 then return end
  local acc = reaper.CreateTrackAudioAccessor(track)
  local buf = reaper.new_array(n)
  reaper.GetAudioAccessorSamples(acc, sr, 1, t0, n, buf)
  reaper.DestroyAudioAccessor(acc)
  local s = buf.table()
  local per, top = n / cols, 0
  for c = 1, cols do
    local p = 0
    for i = math.floor((c - 1) * per) + 1, math.floor(c * per) do
      local v = s[i]; if v < 0 then v = -v end
      if v > p then p = v end
    end
    wave.peaks[c] = p
    if p > top then top = p end
  end
  if top > 0 then
    for c = 1, cols do wave.peaks[c] = (wave.peaks[c] / top) ^ 0.7 end
  end
end

local function draw_wave(x, y, w, h, track, cur)
  rrect(x, y, w, h, 8, COL.panel)
  local function empty(a, b)
    text(a, x + w / 2, y + h / 2 - (b and 16 or 8), 1, COL.muted, "center")
    if b then text(b, x + w / 2, y + h / 2 + 4, 3, COL.dim, "center") end
  end
  if not target then return empty("Choose which markers to clean", "Pick a colour or a name at the top") end
  if not track then return empty("Select your voice track") end
  if not cur then return empty("No marker selected") end

  local a, b = get_razor(track)
  local t0 = math.max(0, cur.pos - 1.2)
  local t1 = t0 + 2.4
  if a and a < t0 + 0.1 then t0 = math.max(0, a - 0.3) end
  if b and b > t1 - 0.1 then t1 = b + 0.3 end

  local ix, iw = x + 10, w - 20
  local cols = math.max(2, math.floor(iw * S))
  update_wave(track, t0, t1, cols)
  local function tx(t) return ix + (t - t0) / (t1 - t0) * iw end

  -- selection
  if a then
    rect(tx(a), y + 6, tx(b) - tx(a), h - 12, COL.accent, 0.16)
    rect(tx(a), y + 6, 1.5, h - 12, COL.accent)
    rect(tx(b) - 1.5, y + 6, 1.5, h - 12, COL.accent)
  end

  -- waveform (drawn per pixel column)
  local mid = (y + h / 2) * S
  local half = (h / 2 - 10) * S
  local px0 = ix * S
  local sa, sb = a and tx(a) * S, b and tx(b) * S
  for c = 1, #wave.peaks do
    local px = px0 + c - 1
    local hh = math.max(0.5, wave.peaks[c] * half)
    if sa and px >= sa and px <= sb then color(COL.accent) else color(COL.wave) end
    gfx.line(px, mid - hh, px, mid + hh)
  end

  -- the marker
  local mkx = tx(cur.pos)
  rect(mkx - 0.5, y + 4, 1, h - 8, COL.accent, 0.9)
  color(COL.accent)
  gfx.triangle(mkx * S - 5 * S, (y + 4) * S, mkx * S + 5 * S, (y + 4) * S, mkx * S, (y + 10) * S)
end

---------------------------------------------------------------- PICKER (top of window)
-- colour REAPER's theme uses for markers that have no colour set
local function default_marker_hex()
  local ok, c = pcall(reaper.GetThemeColor, "marker", 0)
  if ok and c and c >= 0 then
    local r, g, b = reaper.ColorFromNative(c)
    return (r << 16) | (g << 8) | b
  end
  return 0xE8C547
end

local function marker_colors(markers)
  local list, seen = {}, {}
  for _, m in ipairs(markers) do
    if not m.isrgn then
      local key = color_key(m.color)
      if not seen[key] then
        local r, g, b = rgb_of(m.color)
        seen[key] = { key = key, n = 0,
          hex = r and ((r << 16) | (g << 8) | b) or default_marker_hex() }
        list[#list + 1] = seen[key]
      end
      seen[key].n = seen[key].n + 1
    end
  end
  return list
end

local function marker_names(markers)
  local list, seen = {}, {}
  for _, m in ipairs(markers) do
    local k = norm(m.name)
    if not m.isrgn and k ~= "" then
      if not seen[k] then seen[k] = { key = k, label = m.name, n = 0 }; list[#list + 1] = seen[k] end
      seen[k].n = seen[k].n + 1
    end
  end
  table.sort(list, function(p, q) return p.n > q.n end)
  -- a typed name that isn't in the project yet still shows as selected
  if target and target:sub(1, 2) == "n:" and not seen[target:sub(3)] then
    table.insert(list, 1, { key = target:sub(3), label = target:sub(3), n = 0 })
  end
  return list
end

local function ask_name()
  local cur = (target and target:sub(1, 2) == "n:") and target:sub(3) or ""
  local ok, str = reaper.GetUserInputs("Marker name", 1, "Name of the markers to clean:,extrawidth=120", cur)
  if ok and norm(str) ~= "" then set_target("n:" .. norm(str)) end
end

local function chip(label, x, y, selected)
  local w = text_w(label, 3) + 20
  local over = hit(x, y, w, 24)
  rrect(x, y, w, 24, 12, selected and COL.accent or (over and COL.keyon or COL.key))
  text(label, x + w / 2, y + 5, 3, selected and COL.on_accent or COL.text, "center")
  return w, was_clicked(x, y, w, 24)
end

local function draw_picker(x, y, w, markers)
  -- outline the picker in red until something is chosen, so it's obvious
  if not target then
    rrect(x - 8, y - 8, w + 16, 40, 10, COL.accent)
    rrect(x - 6.5, y - 6.5, w + 13, 37, 9, COL.bg)
  end

  -- Colour | Name switch
  local sw = 62
  -- 25 px tall, the same height as the support square next to it
  rrect(x, y - 0.5, sw * 2, 25, 12.5, COL.key)
  for i, mode in ipairs({ "colour", "name" }) do
    local bx = x + (i - 1) * sw
    if pick_mode == mode then rrect(bx + 2, y + 1.5, sw - 4, 21, 10.5, COL.keyon) end
    -- both labels measured together so they sit on the same line
    text_centred(mode == "colour" and "Colour" or "Name", bx + sw / 2, y + 12, 5,
      pick_mode == mode and COL.text or COL.muted, "ColourName")
    if was_clicked(bx, y - 0.5, sw, 25) then pick_mode = mode end
  end

  local right = x + w

  -- support (Ko-fi): a coral heart on a small grey rounded square (same grey as the
  -- Colour / Name switch), before the colours / names. The square is a bit bigger than the
  -- colour dots so it looks the same size; the gaps either side match the gaps between the dots.
  local gap = 8                                 -- switch | square | first colour (outer edge of its ring)
  local bh = 12.5                               -- background square: 25 px
  local hcx, hcy = x + sw * 2 + gap + bh, y + 12
  local hover = hit(hcx - bh, hcy - bh, 2 * bh, 2 * bh)
  rrect(hcx - bh, hcy - bh, 2 * bh, 2 * bh, 7, hover and COL.keyon or COL.key)
  -- heart centred top to bottom: the tops of the lobes and the bottom point are the same
  -- distance from the square's edges
  local hk = 1.13
  heart(hcx, hcy - 0.65 * hk, hover and COL.text or 0xA8A8B4, 1, hk) -- soft grey, lighter on hover
  if was_clicked(hcx - bh, hcy - bh, 2 * bh, 2 * bh) then open_url(SUPPORT_URL) end
  support_tooltip(hover)
  -- the colour slot starts at the outer edge of the selection ring, so the gap is the same both sides
  local cx = hcx + bh + gap
  if pick_mode == "colour" then
    local list = marker_colors(markers)
    if #list == 0 then text("No markers in this project", cx, y + 5, 3, COL.dim) end
    for _, c in ipairs(list) do
      if cx + 22 > right then break end
      local ccx, ccy = cx + 11, y + 12
      local selected = target == "c:" .. c.key
      if selected then
        circle(ccx, ccy, 11, COL.white, false)
      elseif hit(ccx - 11, ccy - 11, 22, 22) then
        circle(ccx, ccy, 11, COL.white, false, 0.35)
      end
      circle(ccx, ccy, 7.5, c.hex, true)
      if was_clicked(ccx - 11, ccy - 11, 22, 22) then set_target("c:" .. c.key) end
      cx = cx + 26
    end
  else
    local list = marker_names(markers)
    local typew = text_w("Type...", 3) + 20
    for _, nm in ipairs(list) do
      local label = nm.label
      if #label > 14 then label = label:sub(1, 13) .. "." end
      label = label .. "  " .. nm.n
      if cx + text_w(label, 3) + 20 > right - typew - 6 then break end
      local cw, click = chip(label, cx, y, target == "n:" .. nm.key)
      if click then set_target("n:" .. nm.key) end
      cx = cx + cw + 6
    end
    local _, click = chip("Type...", cx, y, false)
    if click then ask_name() end
  end
end

---------------------------------------------------------------- ACCENT = MARKER COLOUR
local DEFAULT_ACCENT = 0xF2555A

-- colour of the markers being cleaned (by colour, or the colour of the named markers)
local function marker_accent(markers)
  if not target then return DEFAULT_ACCENT end
  if by_colour() then
    local k = target:sub(3)
    if k == "default" then return default_marker_hex() end
    return tonumber(k, 16) or DEFAULT_ACCENT
  end
  for _, m in ipairs(markers) do
    if matches(m) then
      local r, g, b = rgb_of(m.color)
      if r then return (r << 16) | (g << 8) | b end
      return default_marker_hex()
    end
  end
  return DEFAULT_ACCENT
end

-- make very dark colours readable on the dark background, and pick dark or white text on top
local function apply_accent(hex)
  local r, g, b = (hex >> 16) & 255, (hex >> 8) & 255, hex & 255
  -- red markers: use the softer red, it's easier on the eyes than a pure marker red
  if r >= 150 and g <= 110 and b <= 110 then
    r, g, b = (DEFAULT_ACCENT >> 16) & 255, (DEFAULT_ACCENT >> 8) & 255, DEFAULT_ACCENT & 255
  end
  local lum = 0.299 * r + 0.587 * g + 0.114 * b
  if lum < 90 then
    local k = (90 - lum) / 160 + 0.2
    r, g, b = r + (255 - r) * k, g + (255 - g) * k, b + (255 - b) * k
    lum = 0.299 * r + 0.587 * g + 0.114 * b
  end
  COL.accent = (math.floor(r) << 16) | (math.floor(g) << 8) | math.floor(b)
  COL.on_accent = (lum > 150) and 0x17171B or 0xFFFFFF
end

---------------------------------------------------------------- WINDOW
local function draw()
  if gfx.ext_retina and gfx.ext_retina > 0 then S = gfx.ext_retina end
  if fontScale ~= S then setup_fonts() end
  local W, H = gfx.w / S, gfx.h / S
  local pad = 18

  -- the window has finished growing: now show the shortcut list
  if show_at_h and (H >= show_at_h - 2 or reaper.time_precise() > show_deadline) then
    show_at_h = nil
    shortcuts_hidden = false
    reaper.SetExtState(SECTION, "shortcuts_hidden", "0", true)
  end

  rect(0, 0, W, H, COL.bg)

  local track = reaper.GetSelectedTrack(0, 0)
  local markers = list_markers()
  apply_accent(marker_accent(markers))
  local targets = {}
  for _, m in ipairs(markers) do if matches(m) then targets[#targets + 1] = m end end
  if #targets > initial_count then initial_count = #targets end
  local cur = get_current()
  local idx
  if cur then for i, m in ipairs(targets) do if m.id == cur.id then idx = i end end end

  -- header
  text("MARKER CLEANUP", pad, 14, 4, COL.dim)
  if target and #targets > 0 then
    text(string.format("%d left", #targets), W - pad, 14, 4, COL.dim, "right")
  end

  -- 1. which markers (first thing to do)
  draw_picker(pad, 40, W - 2 * pad, markers)

  -- 2. where we are
  local title, sub
  local name = cur and (cur.name or ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
  if not target then title = "Get started"
  elseif #targets == 0 then title = (initial_count > 0) and "All clean" or "No markers"
  elseif idx and name ~= "" then
    title, sub = name, string.format("%d of %d", idx, #targets)        -- named marker: show its name
  elseif idx then
    title, sub = string.format("Marker %d", idx), string.format("of %d", #targets)
  else title = string.format("%d markers", #targets) end
  -- shorten long names so they fit next to the counter
  local room = W - 2 * pad - (sub and (text_w(sub, 1) + 10) or 0)
  if text_w(title, 2) > room then
    while #title > 1 and text_w(title .. "...", 2) > room do title = title:gsub("[%z\1-\127\194-\244][\128-\191]*$", "") end -- drop last character (UTF-8 safe)
    title = title .. "..."
  end
  text(title, pad, 82, 2, COL.text)
  if sub then
    text(sub, pad + text_w(title, 2) + 8, 94, 1, COL.muted)
  end

  local done = (initial_count > 0) and ((initial_count - #targets) / initial_count) or 0
  rrect(pad, 122, W - 2 * pad, 4, 2, COL.line)
  if done > 0 then rrect(pad, 122, math.max(4, (W - 2 * pad) * done), 4, 2, COL.accent) end

  -- shortcuts: 2 columns when there's room, 1 column when the window is narrow
  local items = {
    { ids = { "cut" },                       label = "Cut & next" },
    { ids = { "play" },                      label = "Play / stop" },
    { ids = { "start_earlier", "start_later" }, label = "Start earlier / later" },
    { ids = { "end_earlier", "end_later" },  label = "End earlier / later" },
    { ids = { "undo", "redo" },              label = "Undo / redo" },
    { ids = { "back_small", "fwd_small" },   label = "Cursor back / fwd (small)" },
    { ids = { "back_big", "fwd_big" },       label = "Cursor back / fwd (big)" },
    { ids = { "clear" },                     label = "Clear selection" },
    { ids = { "prev_marker", "prev_marker2" }, label = "Previous marker" },
    { ids = { "next_marker", "next_marker2" }, label = "Next marker" },
    { ids = { "play_mode" }, label = play_from_sel and "Play from: selection" or "Play from: cursor" },
    { ids = { "loop" }, label = reaper.GetToggleCommandState(1068) == 1 and "Loop: on" or "Loop: off" },
  }
  local function cap_label(id) return capturing == id and "?" or key_name(KEYMAP[id]) end
  local function item_width(it)
    local iw = text_w(it.label, 1) + 8
    for _, id in ipairs(it.ids) do iw = iw + math.max(22, text_w(cap_label(id), 4) + 14) + 4 end
    return iw
  end
  -- two columns whenever the keys plus a bit of label fit (labels that are too long get shortened),
  -- so wider fonts (Windows, Linux) don't push the list into one tall column
  local widest_keys = 0
  for _, it in ipairs(items) do widest_keys = math.max(widest_keys, item_width(it) - text_w(it.label, 1)) end
  local colw = (W - 2 * pad) / 2
  local ncols = (widest_keys + 90 <= colw) and 2 or 1
  if ncols == 1 then colw = W - 2 * pad end
  local nrows = math.ceil(#items / ncols)

  -- layout from the bottom up, with a margin at the bottom
  local rowh = 30
  last_nrows = nrows
  local row1 = H - pad - 22 - (nrows - 1) * rowh
  local hdr = shortcuts_hidden and (H - pad - 14) or (row1 - 28) -- "SHORTCUTS" header line
  local sely = hdr - 26
  local wy = 140
  local wh = sely - 10 - wy
  if wh < 70 then
    -- window too short for everything: keep the waveform at its smallest and move the rest
    -- down below it (rows that don't fit are left out) so nothing ever draws on top of it
    local push = 70 - wh
    wh = 70
    sely, hdr, row1 = sely + push, hdr + push, row1 + push
  end

  draw_wave(pad, wy, W - 2 * pad, wh, track, cur)

  -- selection length + messages
  if track and target then
    local a, b = get_razor(track)
    if a then
      text("Selection", pad, sely, 3, COL.dim)
      text(string.format("%.2f s", b - a), pad + text_w("Selection", 3) + 6, sely, 3, COL.text)
    end
  end
  local age = reaper.time_precise() - message_time
  if message ~= "" and age < 4 then
    text(message, W - pad, sely, 3, COL.note, "right", math.min(1, 4 - age))
  end

  -- shortcuts header: click to show / hide
  local lw = text_w("SHORTCUTS", 4)
  local over = hit(pad - 4, hdr - 4, lw + 26, 22)
  local hc = over and COL.text or COL.muted
  color(hc)
  local tx, ty = (pad + 4) * S, (hdr + 7) * S
  if shortcuts_hidden then -- pointing right
    gfx.triangle(tx - 3 * S, ty - 5 * S, tx - 3 * S, ty + 5 * S, tx + 4 * S, ty)
  else                     -- pointing down
    gfx.triangle(tx - 5 * S, ty - 3 * S, tx + 5 * S, ty - 3 * S, tx, ty + 4 * S)
  end
  text("SHORTCUTS", pad + 14, hdr, 4, hc)
  if was_clicked(pad - 4, hdr - 4, lw + 26, 22) then
    -- grow / shrink the window by the list's height so the waveform keeps its size
    local block = 36 + (nrows - 1) * rowh
    capturing = nil
    if shortcuts_hidden then
      -- expanding: grow the window first, show the list once it has grown
      resize_by = block
      show_at_h = H + block
      show_deadline = reaper.time_precise() + 0.3
    else
      -- collapsing: hide the list now, then shrink the window
      resize_by = -block
      shortcuts_hidden = true
      reaper.SetExtState(SECTION, "shortcuts_hidden", "1", true)
    end
  end
  local line_x = pad + 14 + lw + 10

  if shortcuts_hidden then
    rect(line_x, hdr + 7, math.max(0, W - pad - line_x), 1, COL.line)
    return
  end

  -- hint + reset (click a key to change it)
  local hint, hint_col = "Click a key to change it", COL.dim
  if capturing then
    hint, hint_col = "Press a new key for " .. ACTION_LABEL[capturing] .. "  (click to cancel)", COL.note
  end
  local resetw = text_w("Reset", 3)
  local hintw = text_w(hint, 3)
  local hx = W - pad - resetw - 14 - hintw
  rect(line_x, hdr + 7, math.max(0, hx - 10 - line_x), 1, COL.line)
  text(hint, hx, hdr, 3, hint_col)
  local rx = W - pad - resetw
  text("Reset", rx, hdr, 3, hit(rx - 4, hdr - 3, resetw + 8, 20) and COL.text or COL.muted)
  if was_clicked(rx - 4, hdr - 3, resetw + 8, 20) then
    reset_keys(); save_keys(); capturing = nil; say("Keys reset")
  end

  local key_clicked = false
  for i, it in ipairs(items) do
    local x = pad + ((i - 1) % ncols) * colw
    local y = row1 + ((i - 1) // ncols) * rowh
    if y + 22 > H then break end              -- doesn't fit in the window
    for n, id in ipairs(it.ids) do
      local x0 = x
      x = keycap(cap_label(id), x, y, capturing == id)
      if was_clicked(x0, y, x - x0, 22) then
        key_clicked = true
        if capturing == id then capturing = nil; say("Cancelled") else capturing = id end
      end
      if n < #it.ids then x = x + 4 end
    end
    local label, room = it.label, pad + ((i - 1) % ncols) * colw + colw - 12 - (x + 8)
    if text_w(label, 1) > room then
      while #label > 1 and text_w(label .. "...", 1) > room do label = label:sub(1, -2) end
      label = label .. "..."
    end
    text(label, x + 8, y + 4, 1, COL.muted)
  end
  if clicked and capturing and not key_clicked then capturing = nil; say("Cancelled") end
end

local function save_window()
  local d, x, y, w, h = gfx.dock(-1, 0, 0, 0, 0)
  reaper.SetExtState(SECTION, "win7", string.format("%d %d %d %d %d", d, x, y, w, h), true)
end

-- drawn last, so it sits on top of everything
-- it appears where the mouse is when it pops up, then stays put (doesn't follow the cursor)
local tip_ax, tip_ay
local function draw_tooltip()
  if not tip_visible or not mx then tip_ax, tip_ay = nil, nil; return end
  if not tip_ax then tip_ax, tip_ay = mx, my end
  local mx, my = tip_ax, tip_ay
  local W, H = gfx.w / S, gfx.h / S
  local tw = text_w(TIP_TEXT, 3) + 20
  local th = 26
  local tx = math.min(mx + 2, W - tw - 6)   -- starts at the cursor tip
  local ty = my + 15                          -- just under the arrow
  if ty + th > H - 6 then ty = my - th - 4 end
  rrect(tx, ty + 1, tw, th, 7, 0x000000, 0.35)           -- soft shadow
  rrect(tx, ty, tw, th, 7, COL.line)                      -- border
  rrect(tx + 1, ty + 1, tw - 2, th - 2, 6, COL.panel)     -- card
  text_centred(TIP_TEXT, tx + tw / 2, ty + th / 2, 3, COL.text)
end

local frame = 0
-- Window size on Windows / Linux: gfx.init doesn't size an open window the same way on every
-- system. With the JS extension the window's outside height is simply changed by the needed
-- amount. Without it, gfx.init is used and any error is corrected on the next resize.
local WIN = { off_w = 0, off_h = 0 }
local function loop()
  local ch = gfx.getchar()
  if ch < 0 then return end
  if capturing then
    if ch > 0 then assign_key(capturing, ch); capturing = nil end
  else
    if ch > 0 then handle_key(ch) end
  end

  -- after a resize: see how far off the window came out, and fix that for the next resize
  if WIN.check_at and reaper.time_precise() > WIN.check_at then
    if gfx.dock(-1) & 1 == 0 then
      WIN.off_w = math.max(-80, math.min(80, WIN.off_w + (WIN.want_w - gfx.w / S)))
      WIN.off_h = math.max(-80, math.min(80, WIN.off_h + (WIN.want_h - gfx.h / S)))
    end
    WIN.check_at = nil
  end
  -- a new marker colour / name chosen last frame: switch now, before anything is drawn
  if PENDING.target then
    local key = PENDING.target
    PENDING.target = nil
    with_track(function(track)
      if not switch_target(key, track) then say("No markers to clean") end
    end)
  end

  mx, my = gfx.mouse_x / S, gfx.mouse_y / S
  local down = (gfx.mouse_cap & 1) == 1
  if down and not mouse_prev then press_x, press_y = mx, my end
  clicked = (not down) and mouse_prev
  mouse_prev = down

  draw()
  draw_tooltip()
  if clicked then press_x, press_y = nil, nil end

  -- apply a window resize from showing / hiding the shortcuts (not when docked)
  if resize_by ~= 0 then
    local d, wx, wy = gfx.dock(-1, 0, 0, 0, 0)
    if d & 1 ~= 0 and show_at_h then show_at_h = gfx.h / S end -- docked: show right away
    if d & 1 == 0 then
      local w, h = gfx.w / S, gfx.h / S
      local nh = math.max(200, h + resize_by)
      local ok, l, t, r, b
      if WIN.hwnd then
        WIN.hwnd = reaper.JS_Window_Find("Marker Cleanup", true) or WIN.hwnd -- (changes after docking)
        ok, l, t, r, b = reaper.JS_Window_GetRect(WIN.hwnd)
      end
      if ok then
        -- Windows / Linux with the JS extension: change the window's current outside height by
        -- exactly the amount needed. Nothing is re-measured, so the size can't drift.
        local top, oh = math.min(t, b), math.abs(b - t)
        reaper.JS_Window_SetPosition(WIN.hwnd, l, top, r - l, math.floor(oh + (nh - h) * S + 0.5))
      else
        -- macOS measures window position from the bottom of the screen: move it so the TOP edge stays put
        if OS_IS_MAC then wy = wy + (h - nh) end
        gfx.init("", w + WIN.off_w, nh + WIN.off_h, d, wx, wy)
        if not OS_IS_MAC then
          WIN.want_w, WIN.want_h, WIN.check_at = w, nh, reaper.time_precise() + 0.25
        end
      end
    end
    resize_by = 0
  end
  gfx.update()
  frame = frame + 1
  if frame % 60 == 0 then save_window() end
  reaper.defer(loop)
end

---------------------------------------------------------------- START
local d, x, y, w, h = reaper.GetExtState(SECTION, "win7"):match("^(%-?%d+) (%-?%d+) (%-?%d+) (%d+) (%d+)$")
gfx.ext_retina = 1
-- first run: big enough for the waveform and the full shortcut list in two columns;
-- after that the saved size/position is used
gfx.init("Marker Cleanup", tonumber(w) or 540, tonumber(h) or 540,
  tonumber(d) or 0, tonumber(x) or 200, tonumber(y) or 200)
-- Windows / Linux: with the JS extension the window is resized directly (see the loop)
if not OS_IS_MAC and reaper.JS_Window_Find and reaper.JS_Window_SetPosition then
  WIN.hwnd = reaper.JS_Window_Find("Marker Cleanup", true)
end

initial_count = #target_markers()
if target then with_track(start) end
loop()
