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
-- Gain is written to the take volume (item volume is left alone).
-- No peak limiting is applied.

local SCRIPT = "Daniel_Normalize Track Items to LUFS"
local EXT    = "Daniel_NormalizeLUFS"

local BLOCK       = 1.0   -- analysis block length (s)
local XFADE       = 0.02  -- crossfade length at each cut (s)
local SEARCH_WIN  = 0.03  -- window used to look for gaps between words (s)
local SEARCH_HOP  = 0.01
local SEARCH_SPAN = 1.5   -- how far from the level change to look for a gap (s)
local MIN_GAP     = 0.06  -- shortest quiet stretch that counts as a gap (s)

local SIL_MIN  = 0.30  -- shortest pause that is left unboosted (s)
local SIL_PAD  = 0.05  -- speech tail/lead that stays on the boosted side (s)
local ENV_RATE = 8000  -- sample rate used to scan for pauses
local ENV_WIN  = 0.02  -- scan window (s)
local CLICK_GAP = 0.20 -- silence needed on each side of a click (s)
local PAUSE_FADE = 0.15 -- fade into/out of a lowered pause (s)

local function amp2db(a) return 20 * math.log(a, 10) end

local function bad(g) return (not g) or g ~= g or g <= 0 or g == math.huge end

local function getDefault(key, fallback)
  local v = reaper.GetExtState(EXT, key)
  if v == "" then return fallback end
  return v
end

-- ---------------------------------------------------------------- input
local keys     = { "target", "minlen", "maxboost", "split", "thresh", "minsect3", "gapdb", "silboost10", "pausedip10", "delpause", "clickms" }
local fallback = { "-20",    "1.0",    "30",       "1",     "4",      "3",        "20",    "10",         "10",         "1.0",      "120" }
local defaults = {}
for i, k in ipairs(keys) do defaults[i] = getDefault(k, fallback[i]) end

local ok, csv = reaper.GetUserInputs(SCRIPT, 11,
  "Target loudness (LUFS-I),Skip items shorter than (s),Max boost (dB),"
  .. "Split on level changes (1=yes 0=no),"
  .. "Split when sections differ by (LU),Min section length (s),"
  .. "Gap = this many dB below speech,Lower pauses when boost over (dB),"
  .. "Pauses sit this many dB under speech,"
  .. "Delete pauses longer than (s 0=off),Treat sounds under (ms) as clicks,extrawidth=60",
  table.concat(defaults, ","))
if not ok then return end

local vals = {}
for v in (csv .. ","):gmatch("([^,]*),") do vals[#vals + 1] = tonumber(v) end
for i = 1, 11 do
  if not vals[i] then
    reaper.MB("Please enter numbers only.", SCRIPT, 0)
    return
  end
end
local target, minlen, maxboost, doSplit, thresh, minSection, gapDb, silBoost, pauseDip, delPause, clickMs = table.unpack(vals)
local clickMax = clickMs / 1000
doSplit = doSplit ~= 0
for i, k in ipairs(keys) do reaper.SetExtState(EXT, k, tostring(vals[i]), true) end

local trackCount = reaper.CountSelectedTracks(0)
if trackCount == 0 then
  reaper.MB("Select the track(s) whose items you want to normalize.", SCRIPT, 0)
  return
end

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
local function setGain(item, gain)
  local take = reaper.GetActiveTake(item)
  if not take then return end
  -- keep polarity if the take was flipped
  local oldVol = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
  local sign = oldVol < 0 and -1 or 1
  reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", sign * gain)
end

local function normalizeItem(item)
  local take = reaper.GetActiveTake(item)
  if not take or reaper.TakeIsMIDI(take) then return end

  local src, s, e = sourceRange(item, take)
  local itemLen = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local itemPos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")

  -- too short, silent, or needing more than the max boost: leave it alone
  if itemLen < minlen or e - s <= 0 then return end
  local gain = reaper.CalculateNormalization(src, 0, target, s, e) -- 0 = LUFS-I
  if bad(gain) then return end
  local boostDb = amp2db(gain)
  if boostDb > maxboost then return end

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
