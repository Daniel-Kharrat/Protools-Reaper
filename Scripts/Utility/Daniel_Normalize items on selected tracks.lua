-- Daniel_Normalize items on selected tracks.lua
-- Normalizes every audio item on the selected track(s) to the same
-- integrated loudness (LUFS-I), so the "body" of each clip matches.
-- LUFS-I is gated: pauses and near-silence don't drag the reading down.
--
-- Optional splitting: if part of an item is consistently quieter or
-- louder than another part for a sustained stretch (not brief moments),
-- the item is cut inside a gap between words near that change (never
-- mid-word; if no gap is found, that change isn't cut), the pieces get
-- a short crossfade, and each piece is normalized separately.
--
-- Pauses get less boost: when a piece needs a big boost, its pauses
-- are cut out right after the speech ends and right before it starts
-- again, and sit a set amount below the speech boost (with a gentle
-- fade) so room noise is tamed without the pauses sounding dead.
-- Long silences (over a set length) are deleted outright; the rest of
-- the item stays where it is in time. Very short sounds with silence on
-- both sides (mouth clicks, small noises) count as part of the pause.
--
-- Gain is written to the take volume, compensating for any item volume
-- already set, so take x item volume always lands on the target.
-- No peak limiting is applied.
--
-- Window: settings plus a preset list (save / delete), like an FX window.
-- Presets are saved in REAPER's presets folder, next to the FX presets:
--   <resource path>/presets/Daniel_Normalize items on selected tracks.ini
-- Requires ReaImGui (install it from ReaPack).

local SCRIPT = "Daniel_Normalize items on selected tracks"
local TITLE  = "Normalize items on selected tracks" -- shown in title bars
local EXT    = "Daniel_NormalizeItemsOnSelectedTracks"
local OLD_EXT = "Daniel_NormalizeItemsOnSelectedTrack" -- before the rename

local BLOCK       = 1.0   -- analysis block length (s)
local XFADE       = 0.02  -- crossfade length at each cut (s)
local SEARCH_WIN  = 0.03  -- window used to look for gaps between words (s)
local SEARCH_HOP  = 0.01
local SEARCH_SPAN = 1.5   -- how far from the level change to look for a gap (s)
local MIN_GAP     = 0.06  -- shortest quiet stretch that counts as a gap (s)

local SIL_MIN  = 0.30  -- shortest pause that is handled separately (s)
local SIL_PAD  = 0.05  -- speech tail/lead that stays on the boosted side (s)
local ENV_RATE = 8000  -- sample rate used to scan for pauses
local ENV_WIN  = 0.02  -- scan window (s)
local CLICK_GAP = 0.20 -- silence needed on each side of a click (s)
local PAUSE_FADE = 0.15 -- fade into/out of a lowered pause (s)

local function amp2db(a) return 20 * math.log(a, 10) end

local function bad(g) return (not g) or g ~= g or g <= 0 or g == math.huge end

-- ---------------------------------------------------------------- ReaImGui
if not reaper.ImGui_GetBuiltinPath then
  reaper.MB("This script needs the ReaImGui extension.\n\n"
    .. "Install it from Extensions > ReaPack > Browse packages (search \"ReaImGui\"), "
    .. "restart REAPER, then run the script again.", TITLE, 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua"
local ImGui = require "imgui" "0.9"

-- ---------------------------------------------------------------- settings
local FIELDS = {
  { key = "target",   max = 0, label = "Target loudness (LUFS-I)",             def = -22, step = 0.5, fmt = "%.1f", group = "Loudness" },
  { key = "minlen", min = 0,   label = "Skip items shorter than (s)",          def = 0.4, step = 0.1, fmt = "%.2f" },
  { key = "maxgain",  min = 0, max = 24, label = "Max gain change (dB)", def = 24,  step = 1,   fmt = "%.1f" },
  { key = "split",    label = "Split on level changes",               def = 1,   bool = true, group = "Splitting" },
  { key = "thresh", min = 0, needs = "split", label = "Split when sections differ by (LU)",   def = 4,   step = 0.5, fmt = "%.1f" },
  { key = "minsect", min = 0, needs = "split", label = "Min section length (s)",               def = 3,   step = 0.5, fmt = "%.1f" },
  { key = "gapdb", min = 0,    label = "Gap = this many dB below speech",      def = 20,  step = 1,   fmt = "%.1f", group = "Pauses" },
  { key = "silboost", min = 0, label = "Lower pauses when boost over (dB)",    def = 10,  step = 1,   fmt = "%.1f" },
  { key = "pausedip", min = 0, label = "Pauses sit this many dB under speech", def = 10,  step = 1,   fmt = "%.1f" },
  { key = "delpause", min = 0, label = "Delete pauses longer than (s, 0 = off)", def = 1.0, step = 0.1, fmt = "%.2f" },
  { key = "clickms", min = 0,  label = "Treat sounds under (ms) as clicks",    def = 120, step = 10,  fmt = "%.0f" },
}

local FIELD = {}
for _, f in ipairs(FIELDS) do FIELD[f.key] = f end

-- keeps a value inside its allowed range (no negative lengths etc.)
local function clamp(key, v)
  local f = FIELD[key]
  if f.min and v < f.min then v = f.min end
  if f.max and v > f.max then v = f.max end
  return v
end

local function defaults()
  local t = {}
  for _, f in ipairs(FIELDS) do t[f.key] = f.def end
  return t
end

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

-- last-used settings live in reaper-extstate.ini as "key=value;key=value"
local function loadLastUsed()
  local t = defaults()
  local saved = reaper.GetExtState(EXT, "last")
  if saved == "" then saved = reaper.GetExtState(OLD_EXT, "last") end
  for k, v in saved:gmatch("(%w+)=([^;]*)") do
    if t[k] ~= nil and tonumber(v) then t[k] = clamp(k, tonumber(v)) end
  end
  return t
end

local function saveLastUsed(t)
  local parts = {}
  for _, f in ipairs(FIELDS) do parts[#parts + 1] = f.key .. "=" .. tostring(t[f.key]) end
  reaper.SetExtState(EXT, "last", table.concat(parts, ";"), true)
end

-- ---------------------------------------------------------------- presets
local PRESET_DIR  = reaper.GetResourcePath() .. "/presets"
local PRESET_FILE = PRESET_DIR .. "/" .. SCRIPT .. ".ini"
local OLD_PRESET_FILE = PRESET_DIR .. "/Daniel_Normalize items on selected track.ini"

local function loadPresets()
  local list = {}
  -- falls back to the file from before the rename; saving writes the new one
  local f = io.open(PRESET_FILE, "r") or io.open(OLD_PRESET_FILE, "r")
  if not f then return list end
  local cur
  for line in f:lines() do
    line = line:gsub("\r$", "")
    local name = line:match("^%[(.*)%]$")
    if name then
      cur = { name = name, vals = defaults() }
      list[#list + 1] = cur
    elseif cur then
      local k, v = line:match("^(%w+)=(.*)$")
      if k and cur.vals[k] ~= nil and tonumber(v) then cur.vals[k] = clamp(k, tonumber(v)) end
    end
  end
  f:close()
  return list
end

local function savePresets(list)
  reaper.RecursiveCreateDirectory(PRESET_DIR, 0)
  local f = io.open(PRESET_FILE, "w")
  if not f then
    reaper.MB("Couldn't write the preset file:\n" .. PRESET_FILE, TITLE, 0)
    return
  end
  for _, p in ipairs(list) do
    f:write("[", p.name, "]\n")
    for _, fd in ipairs(FIELDS) do f:write(fd.key, "=", tostring(p.vals[fd.key]), "\n") end
    f:write("\n")
  end
  f:close()
end

local function cleanName(s)
  return ((s or ""):gsub("[%[%]\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- ---------------------------------------------------------------- run-time values
-- set from the window when you click Normalize
local target, minlen, maxgain, doSplit, thresh, minSection
local gapDb, silBoost, pauseDip, delPause, clickMax
local trackCount
-- ---------------------------------------------------------------- measuring
local function measureLUFS(src, s, e)
  local g = reaper.CalculateNormalization(src, 0, 0, s, e) -- 0 = LUFS-I
  if bad(g) then return nil end
  local l = -amp2db(g)
  if l < -60 then return nil end -- treat as silence
  return l
end

local function rmsDB(src, s, e)
  local g = reaper.CalculateNormalization(src, 1, 0, s, e) -- 1 = RMS
  if bad(g) then return -math.huge end
  return -amp2db(g)
end

-- part of the source an item plays, in source seconds
local function sourceRange(item, take)
  local src     = reaper.GetMediaItemTake_Source(take)
  local itemLen = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local offs    = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local rate    = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  local srcLen  = reaper.GetMediaSourceLength(src)
  local s = math.max(0, offs)
  local e = math.min(srcLen, offs + itemLen * rate)
  return src, s, e, offs, rate
end

-- ---------------------------------------------------------------- splitting
-- Splits the item at the given cuts, overlapping the pieces with a
-- crossfade at each cut. A cut is a project time (XFADE long) or
-- { t = time, xf = crossfade length }. Returns the pieces in order.
local function splitAt(item, cutList)
  local pieces, current = {}, item
  for _, c in ipairs(cutList) do
    local projT = type(c) == "table" and c.t or c
    local xf    = type(c) == "table" and c.xf or XFADE
    local right = reaper.SplitMediaItem(current, projT)
    if right then
      local h    = xf / 2
      local rTake = reaper.GetActiveTake(right)
      local rate = reaper.GetMediaItemTakeInfo_Value(rTake, "D_PLAYRATE")

      local leftLen = reaper.GetMediaItemInfo_Value(current, "D_LENGTH")
      reaper.SetMediaItemInfo_Value(current, "D_LENGTH", leftLen + h)

      local rPos  = reaper.GetMediaItemInfo_Value(right, "D_POSITION")
      local rLen  = reaper.GetMediaItemInfo_Value(right, "D_LENGTH")
      local rOffs = reaper.GetMediaItemTakeInfo_Value(rTake, "D_STARTOFFS")
      reaper.SetMediaItemInfo_Value(right, "D_POSITION", rPos - h)
      reaper.SetMediaItemInfo_Value(right, "D_LENGTH", rLen + h)
      reaper.SetMediaItemTakeInfo_Value(rTake, "D_STARTOFFS", rOffs - h * rate)

      reaper.SetMediaItemInfo_Value(current, "D_FADEOUTLEN", xf)
      reaper.SetMediaItemInfo_Value(right,   "D_FADEINLEN",  xf)
      pieces[#pieces + 1] = current
      current = right
    end
  end
  pieces[#pieces + 1] = current
  return pieces
end

-- Returns cut points in source time where the level changes for a sustained stretch.
local function findCuts(src, s, e)
  local minBlocks = math.max(2, math.floor(minSection / BLOCK + 0.5))
  local n = math.floor((e - s) / BLOCK)
  if n < 2 * minBlocks then return {} end

  -- loudness of each block
  local lv = {}
  for i = 1, n do
    lv[i] = measureLUFS(src, s + (i - 1) * BLOCK, s + i * BLOCK)
  end

  -- median of 3 neighbours, so single loud/quiet moments don't count
  local sm = {}
  for i = 1, n do
    local v = {}
    for k = i - 1, i + 1 do if lv[k] then v[#v + 1] = lv[k] end end
    table.sort(v)
    if #v == 3 then sm[i] = v[2]
    elseif #v == 2 then sm[i] = (v[1] + v[2]) / 2
    elseif #v == 1 then sm[i] = v[1] end
  end

  local function avg(a, b)
    local sum, c = 0, 0
    for k = a, b do if sm[k] then sum = sum + sm[k]; c = c + 1 end end
    if c < (b - a + 1) / 2 then return nil end -- mostly silence
    return sum / c
  end

  -- compare the stretch before vs after each possible boundary
  local cand = {}
  for j = minBlocks + 1, n - minBlocks + 1 do
    local L = avg(j - minBlocks, j - 1)
    local R = avg(j, j + minBlocks - 1)
    if L and R and math.abs(L - R) >= thresh then
      cand[#cand + 1] = { j = j, score = math.abs(L - R), quiet = math.min(L, R) }
    end
  end

  -- strongest changes first; each must land in a real gap between words,
  -- otherwise that change is not cut at all
  table.sort(cand, function(a, b) return a.score > b.score end)
  local cuts = {}
  local minDist = minSection
  for _, c in ipairs(cand) do
    local bt = s + (c.j - 1) * BLOCK
    local lo = math.max(s + 0.5, bt - SEARCH_SPAN)
    local hi = math.min(e - 0.5, bt + SEARCH_SPAN)
    local silence = c.quiet - gapDb

    -- find quiet stretches; keep the longest (closest to the change on ties)
    local bestLen, bestT = 0, nil
    local runStart = nil
    local t = lo
    while true do
      local isQuiet = (t + SEARCH_WIN <= hi) and rmsDB(src, t, t + SEARCH_WIN) < silence
      if isQuiet then
        runStart = runStart or t
      elseif runStart then
        local runEnd = t - SEARCH_HOP + SEARCH_WIN
        local len = runEnd - runStart
        local mid = (runStart + runEnd) / 2
        if len >= MIN_GAP and (len > bestLen + 0.01 or
           (math.abs(len - bestLen) <= 0.01 and bestT and math.abs(mid - bt) < math.abs(bestT - bt))) then
          bestLen, bestT = len, mid
        end
        runStart = nil
      end
      if t + SEARCH_WIN > hi then break end
      t = t + SEARCH_HOP
    end

    if bestT then
      local free = true
      for _, ct in ipairs(cuts) do
        if math.abs(ct - bestT) < minDist then free = false; break end
      end
      if free and bestT - s >= minDist and e - bestT >= minDist then
        cuts[#cuts + 1] = bestT
      end
    end
  end
  table.sort(cuts)
  return cuts
end

-- ---------------------------------------------------------------- pauses
-- Scans the item and returns its pauses as {a, b} in seconds from the
-- item start, already trimmed so a little speech tail/lead stays outside.
local function findPauses(item, take)
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local src = reaper.GetMediaItemTake_Source(take)
  local nch = math.max(1, reaper.GetMediaSourceNumChannels(src))
  local winN = math.floor(ENV_RATE * ENV_WIN + 0.5)
  local chunkWins = 50
  local chunkN = winN * chunkWins
  local buf = reaper.new_array(chunkN * nch)
  local acc = reaper.CreateTakeAudioAccessor(take)

  -- level of each short window
  local env = {}
  local t = 0
  while t < len do
    buf.clear()
    reaper.GetAudioAccessorSamples(acc, ENV_RATE, nch, t, chunkN, buf)
    local data = buf.table()
    for w = 0, chunkWins - 1 do
      if t + (w + 1) * ENV_WIN > len then break end
      local sum, base = 0, w * winN * nch
      for k = 1, winN * nch do
        local x = data[base + k] or 0
        sum = sum + x * x
      end
      local rms = math.sqrt(sum / (winN * nch))
      env[#env + 1] = rms > 0 and amp2db(rms) or -200
    end
    t = t + chunkWins * ENV_WIN
  end
  reaper.DestroyAudioAccessor(acc)
  if #env == 0 then return {} end

  -- speech level = the loud end of the windows (90th percentile)
  local sorted = {}
  for i = 1, #env do if env[i] > -150 then sorted[#sorted + 1] = env[i] end end
  if #sorted == 0 then return {} end
  table.sort(sorted)
  local speech = sorted[math.max(1, math.floor(#sorted * 0.9))]
  local floor = speech - gapDb

  local q = {}
  for k = 1, #env do q[k] = env[k] < floor end

  -- mouth clicks and small noises: a very short sound with silence on
  -- both sides counts as part of the pause
  if clickMax > 0 then
    local maxW = math.max(1, math.floor(clickMax / ENV_WIN + 0.5))
    local gapW = math.floor(CLICK_GAP / ENV_WIN + 0.5)
    local function quietRun(from, step)
      local c, k = 0, from
      while k >= 1 and k <= #env and q[k] do c = c + 1; k = k + step end
      if k < 1 or k > #env then return math.huge end -- reached the item edge
      return c
    end
    local k = 1
    while k <= #env do
      if not q[k] then
        local j = k
        while j + 1 <= #env and not q[j + 1] do j = j + 1 end
        if j - k + 1 <= maxW and quietRun(k - 1, -1) >= gapW and quietRun(j + 1, 1) >= gapW then
          for m = k, j do q[m] = true end
        end
        k = j + 1
      else
        k = k + 1
      end
    end
  end

  -- runs of quiet windows long enough to be a pause
  local pauses = {}
  local i = 1
  while i <= #env do
    if q[i] then
      local j = i
      while j + 1 <= #env and q[j + 1] do j = j + 1 end
      local a = (i - 1) * ENV_WIN
      local b = j * ENV_WIN
      if b - a >= SIL_MIN then
        local pa = (i == 1) and 0 or a + SIL_PAD
        local pb = (j == #env) and len or b - SIL_PAD
        if pb - pa >= SIL_MIN - 2 * SIL_PAD then
          pauses[#pauses + 1] = { pa, pb, raw = b - a }
        end
      end
      i = j + 1
    else
      i = i + 1
    end
  end
  return pauses
end

-- ---------------------------------------------------------------- normalizing
-- Sets the take volume so that take x item volume = gain. Loudness is
-- measured on the raw file, so any existing item volume is compensated
-- for (an item already at +6 dB gets 6 dB less take volume). The take
-- volume itself is replaced, not added to.
local function setGain(item, gain)
  local take = reaper.GetActiveTake(item)
  if not take then return end
  local itemVol = reaper.GetMediaItemInfo_Value(item, "D_VOL")
  if itemVol <= 0 then return end -- item turned all the way down: leave it
  -- keep polarity if the take was flipped
  local oldVol = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
  local sign = oldVol < 0 and -1 or 1
  reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", sign * gain / itemVol)
end

local function normalizeItem(item)
  local take = reaper.GetActiveTake(item)
  if not take or reaper.TakeIsMIDI(take) then return end

  local src, s, e = sourceRange(item, take)
  local itemLen = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local itemPos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")

  -- too short, silent, or needing more than the max gain change (up or
  -- down): leave it alone
  if itemLen < minlen or e - s <= 0 then return end
  local gain = reaper.CalculateNormalization(src, 0, target, s, e) -- 0 = LUFS-I
  if bad(gain) then return end
  local boostDb = amp2db(gain)
  if math.abs(boostDb) > maxgain then return end

  local bigBoost = boostDb > silBoost
  local deleting = delPause > 0

  -- small boost and nothing to delete: just apply it to the whole item
  if not bigBoost and not deleting then
    setGain(item, gain)
    return
  end

  -- which pauses to cut out: all of them on a big boost (kept unboosted),
  -- otherwise only the long ones that will be deleted
  local chosen = {}
  for _, p in ipairs(findPauses(item, take)) do
    p.del = deleting and p.raw >= delPause
    if bigBoost or p.del then chosen[#chosen + 1] = p end
  end
  if #chosen == 0 then
    setGain(item, gain)
    return
  end

  -- cut where each pause starts and ends (unless it touches the item edge).
  -- Kept pauses get a longer crossfade that sits entirely inside the pause,
  -- so the level eases down after the speech and back up before it.
  local times = {}
  for _, p in ipairs(chosen) do
    local xf, inset = XFADE, 0
    if not p.del then
      xf = math.min(PAUSE_FADE, (p[2] - p[1]) / 2)
      inset = xf / 2
    end
    if p[1] > 1e-6 then times[#times + 1] = { t = itemPos + p[1] + inset, xf = xf } end
    if p[2] < itemLen - 1e-6 then times[#times + 1] = { t = itemPos + p[2] - inset, xf = xf } end
  end
  table.sort(times, function(a, b) return a.t < b.t end)

  -- pauses sit pauseDip below the speech boost (never below their original level)
  local pauseGain = 10 ^ (math.max(0, boostDb - pauseDip) / 20)

  local track = reaper.GetMediaItem_Track(item)
  local pieces = splitAt(item, times)

  if #pieces ~= #times + 1 then
    -- a cut failed; fall back to boosting everything rather than guessing
    for _, pc in ipairs(pieces) do setGain(pc, gain) end
    return
  end

  -- pieces alternate speech / pause
  local isSpeech = chosen[1][1] > 1e-6
  local pi = 0
  for _, pc in ipairs(pieces) do
    if isSpeech then
      setGain(pc, gain)
    else
      pi = pi + 1
      if chosen[pi].del then
        reaper.DeleteTrackMediaItem(track, pc)
      else
        setGain(pc, pauseGain)
      end
    end
    isSpeech = not isSpeech
  end
end

-- ---------------------------------------------------------------- main
local function run(S)
  target, minlen, maxgain = S.target, S.minlen, S.maxgain
  doSplit, thresh, minSection = S.split ~= 0, S.thresh, S.minsect
  gapDb, silBoost, pauseDip = S.gapdb, S.silboost, S.pausedip
  delPause, clickMax = S.delpause, S.clickms / 1000

  trackCount = reaper.CountSelectedTracks(0)
  if trackCount == 0 then return false end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  for ti = 0, trackCount - 1 do
    local track = reaper.GetSelectedTrack(0, ti)

    -- collect first: splitting changes the track's item list
    local items = {}
    for ii = 0, reaper.CountTrackMediaItems(track) - 1 do
      items[#items + 1] = reaper.GetTrackMediaItem(track, ii)
    end

    for _, item in ipairs(items) do
      local take = reaper.GetActiveTake(item)
      local pieces = { item }

      if doSplit and take and not reaper.TakeIsMIDI(take) then
        local src, s, e, offs, rate = sourceRange(item, take)
        local cuts = findCuts(src, s, e)
        if #cuts > 0 then
          local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
          local times = {}
          for _, srcT in ipairs(cuts) do times[#times + 1] = pos + (srcT - offs) / rate end
          pieces = splitAt(item, times)
        end
      end

      for _, piece in ipairs(pieces) do normalizeItem(piece) end
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(string.format("Normalize items to %.1f LUFS-I", target), -1)
  return true
end

-- ---------------------------------------------------------------- window
local ctx      = ImGui.CreateContext(SCRIPT)
local S        = loadLastUsed()
local presets  = loadPresets()
local curName  = nil   -- preset currently loaded
local curVals  = nil   -- its values, to show " *" when edited
local saveName = ""
local warn     = false

local function modified()
  if not curVals then return false end
  for _, f in ipairs(FIELDS) do
    if math.abs((S[f.key] or 0) - (curVals[f.key] or 0)) > 1e-9 then return true end
  end
  return false
end

local function presetRow()
  local preview = curName and (curName .. (modified() and " *" or "")) or "No preset"
  ImGui.SetNextItemWidth(ctx, 240)
  if ImGui.BeginCombo(ctx, "##preset", preview) then
    if ImGui.Selectable(ctx, "Factory defaults", false) then
      S, curName, curVals = defaults(), nil, nil
    end
    if #presets > 0 then ImGui.Separator(ctx) end
    for _, p in ipairs(presets) do
      if ImGui.Selectable(ctx, p.name, p.name == curName) then
        S, curName, curVals = copy(p.vals), p.name, copy(p.vals)
      end
    end
    ImGui.EndCombo(ctx)
  end

  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Save...") then
    saveName = curName or ""
    ImGui.OpenPopup(ctx, "Save preset")
  end
  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, curName == nil)
  if ImGui.Button(ctx, "Delete") then ImGui.OpenPopup(ctx, "Delete preset") end
  ImGui.EndDisabled(ctx)

  -- save dialog
  if ImGui.BeginPopupModal(ctx, "Save preset", nil, ImGui.WindowFlags_AlwaysAutoResize) then
    if ImGui.IsWindowAppearing(ctx) then ImGui.SetKeyboardFocusHere(ctx) end
    ImGui.SetNextItemWidth(ctx, 240)
    local _, txt = ImGui.InputText(ctx, "##name", saveName)
    saveName = txt
    local name = cleanName(saveName)
    local enter = ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)

    local exists = false
    for _, p in ipairs(presets) do if p.name == name then exists = true end end
    if exists then ImGui.TextDisabled(ctx, "Overwrites the existing preset") end

    ImGui.BeginDisabled(ctx, name == "")
    if ImGui.Button(ctx, exists and "Overwrite" or "Save") or (enter and name ~= "") then
      local found = false
      for _, p in ipairs(presets) do
        if p.name == name then p.vals = copy(S); found = true end
      end
      if not found then presets[#presets + 1] = { name = name, vals = copy(S) } end
      savePresets(presets)
      curName, curVals = name, copy(S)
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel") or ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndPopup(ctx)
  end

  -- delete confirmation
  if ImGui.BeginPopupModal(ctx, "Delete preset", nil, ImGui.WindowFlags_AlwaysAutoResize) then
    ImGui.Text(ctx, 'Delete "' .. (curName or "") .. '"?')
    if ImGui.Button(ctx, "Delete") then
      for i = #presets, 1, -1 do
        if presets[i].name == curName then table.remove(presets, i) end
      end
      savePresets(presets)
      curName, curVals = nil, nil
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel") or ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndPopup(ctx)
  end
end

-- labels on the left, values lined up in a column on the right
local VALUE_W = 130
local editing = {} -- which number box is being typed in
local function settings()
  local labelW = 0
  for _, f in ipairs(FIELDS) do
    labelW = math.max(labelW, (ImGui.CalcTextSize(ctx, f.label)))
  end
  labelW = labelW + 16

  for _, f in ipairs(FIELDS) do
    if f.group then ImGui.SeparatorText(ctx, f.group) end

    -- options that depend on a checkbox are grayed out while it's off
    if f.needs then ImGui.BeginDisabled(ctx, S[f.needs] == 0) end

    local startX = ImGui.GetCursorPosX(ctx)
    local rowW = ImGui.GetContentRegionAvail(ctx)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, f.label)
    ImGui.SameLine(ctx)
    ImGui.SetCursorPosX(ctx, startX + math.max(labelW, rowW - VALUE_W))

    if f.bool then
      local _, v = ImGui.Checkbox(ctx, "##" .. f.key, S[f.key] ~= 0)
      S[f.key] = v and 1 or 0
    else
      -- [-][+][ value ]  (buttons on the left, number on the right)
      local fh = ImGui.GetFrameHeight(ctx)
      local sp = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemInnerSpacing)
      local step = f.step
      if ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl) then step = step * 10 end
      local v = S[f.key]

      ImGui.PushID(ctx, f.key)
      if ImGui.PushButtonRepeat then ImGui.PushButtonRepeat(ctx, true) end
      if ImGui.Button(ctx, "-", fh, fh) then v = v - step end
      ImGui.SameLine(ctx, 0, sp)
      if ImGui.Button(ctx, "+", fh, fh) then v = v + step end
      if ImGui.PopButtonRepeat then ImGui.PopButtonRepeat(ctx) end
      ImGui.SameLine(ctx, 0, sp)
      ImGui.SetNextItemWidth(ctx, VALUE_W - 2 * (fh + sp))
      -- ImGui can't center text in an input box, so while it's not being
      -- edited its own text is hidden and a centered copy is drawn on top
      local showOwn = editing[f.key]
      if not showOwn then ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0) end
      local _, typed = ImGui.InputDouble(ctx, "##v", v, 0, 0, f.fmt)
      if not showOwn then ImGui.PopStyleColor(ctx) end
      editing[f.key] = ImGui.IsItemActive(ctx)
      if not showOwn then
        local x1, y1 = ImGui.GetItemRectMin(ctx)
        local x2, y2 = ImGui.GetItemRectMax(ctx)
        local txt = string.format(f.fmt, typed)
        local tw, th = ImGui.CalcTextSize(ctx, txt)
        ImGui.DrawList_AddText(ImGui.GetWindowDrawList(ctx),
          math.floor((x1 + x2 - tw) / 2), math.floor((y1 + y2 - th) / 2),
          ImGui.GetColor(ctx, ImGui.Col_Text), txt)
      end
      ImGui.PopID(ctx)

      v = math.floor(typed / 1e-6 + 0.5) * 1e-6 -- tidy float steps (0.1 + 0.2)
      S[f.key] = clamp(f.key, v)
    end

    if f.needs then ImGui.EndDisabled(ctx) end
  end
end

-- ---------------------------------------------------------------- colors
-- ReaImGui's default dark look, with only its blue accents swapped for
-- neutral grays (same transparency as the originals).
local function gray(v, a) -- v and a are 0..1
  local x = math.floor(v * 255 + 0.5)
  return (x << 24) | (x << 16) | (x << 8) | math.floor(a * 255 + 0.5)
end

local COLORS = {
  { ImGui.Col_FrameBg,          gray(0.30, 0.54) },
  { ImGui.Col_FrameBgHovered,   gray(0.45, 0.40) },
  { ImGui.Col_FrameBgActive,    gray(0.55, 0.67) },
  { ImGui.Col_TitleBgActive,    gray(0.22, 1.00) },
  { ImGui.Col_CheckMark,        gray(0.85, 1.00) },
  { ImGui.Col_SliderGrab,       gray(0.60, 1.00) },
  { ImGui.Col_SliderGrabActive, gray(0.75, 1.00) },
  { ImGui.Col_Button,           gray(0.45, 0.40) },
  { ImGui.Col_ButtonHovered,    gray(0.55, 1.00) },
  { ImGui.Col_ButtonActive,     gray(0.65, 1.00) },
  { ImGui.Col_Header,           gray(0.45, 0.31) },
  { ImGui.Col_HeaderHovered,    gray(0.50, 0.80) },
  { ImGui.Col_HeaderActive,     gray(0.55, 1.00) },
  { ImGui.Col_SeparatorHovered, gray(0.50, 0.78) },
  { ImGui.Col_SeparatorActive,  gray(0.60, 1.00) },
  { ImGui.Col_ResizeGrip,       gray(0.45, 0.20) },
  { ImGui.Col_ResizeGripHovered,gray(0.55, 0.67) },
  { ImGui.Col_ResizeGripActive, gray(0.65, 0.95) },
  { ImGui.Col_TextSelectedBg,   gray(0.55, 0.35) },
}

local function frame()
  presetRow()
  settings()

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)
  -- Apply sits on the right; the "select a track" note goes to its left
  -- same width as the number boxes, lined up under them
  local BTN_W = VALUE_W - 2 * (ImGui.GetFrameHeight(ctx)
    + ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemInnerSpacing))
  if warn then
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextDisabled(ctx, "Select a track first")
    ImGui.SameLine(ctx)
  end
  local avail = ImGui.GetContentRegionAvail(ctx)
  ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, avail - BTN_W))
  if ImGui.Button(ctx, "Apply", BTN_W) then
    saveLastUsed(S)
    warn = not run(S)
  end
end

local function loop()
  local flags = ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoCollapse
  for _, c in ipairs(COLORS) do ImGui.PushStyleColor(ctx, c[1], c[2]) end
  local visible, open = ImGui.Begin(ctx, TITLE .. "###main", true, flags)
  if visible then
    frame()
    ImGui.End(ctx)
  end
  ImGui.PopStyleColor(ctx, #COLORS)
  if open then
    reaper.defer(loop)
  else
    saveLastUsed(S)
  end
end

reaper.defer(loop)
