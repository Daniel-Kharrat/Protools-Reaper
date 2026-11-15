-- @description Daniel_AutoEQ Integration: headphone correction EQ from AutoEq measurements and targets, written to ReaEQ in Monitoring FX
-- @version 0.1
-- @author Daniel Kharrat

local SEP = package.config:sub(1, 1)
local DATA = reaper.GetResourcePath() .. SEP .. "Data" .. SEP .. "Daniel Kharrat" .. SEP .. "AutoEQ Integration" .. SEP
reaper.RecursiveCreateDirectory(DATA, 0)

if not reaper.ImGui_CreateContext then
  reaper.MB("AutoEQ Integration needs ReaImGui (0.9.3 or newer).", "AutoEQ Integration", 0)
  return
end

local FS = 48000
local FMIN, FMAX = 20, 20000
local DBMIN, DBMAX = -15, 15
local NGRID = 240
local MAXBANDS = 10         -- most bands you can add by hand
local SUG_MAX_BANDS = 5     -- most bands the suggestion uses
local SUGGEST_MIN_F = 150    -- default bands below this are not suggested
local SUGGEST_MAX_F = 5000   -- default bands above this are not suggested
local COL = {
  well = 0x131317, line = 0x2E2E36, text = 0xEDEDF2,
  muted = 0x8A8A96, dim = 0x5C5C68, accent = 0x5B9BF0,
}
local function rgba(c, a) return (c << 8) | (a or 0xFF) end

local GRID = {}
for i = 0, NGRID - 1 do
  GRID[i + 1] = math.exp(math.log(FMIN) + i / (NGRID - 1) * (math.log(FMAX) - math.log(FMIN)))
end

local ctx = reaper.ImGui_CreateContext("AutoEQ Integration")

local S = {
  meas = nil,            -- {f = {}, db = {}}
  tcurve = nil,          -- target curve, same layout
  target_header = {},
  target_rows = {},
  target_col = 0,        -- zero-based combo index
  bands = {},            -- {on, t = "PK"|"LSC"|"HSC", f, g, q}
  preamp = 0,
  gain = 0,          -- output gain in dB (ReaEQ Global Gain)
  auto = true,
  dirty = true,
  sel = 1,           -- selected band in the editor
  push = false,
  last_push = 0,
  drag = nil,
  res = { ready = false },
  rms = nil,
  status = "Load a measurement and a target curve. Select a track to use ReaEQ on.",
}

---------------------------------------------------------------- utils

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function read_lines(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local t = {}
  for l in fh:lines() do t[#t + 1] = l end
  fh:close()
  return t
end

local function split_csv(line)
  local out = {}
  for cell in (line .. ","):gmatch("([^,]*),") do out[#out + 1] = trim(cell) end
  return out
end

-- linear interpolation in log frequency
local function interp(curve, x)
  local f, d = curve.f, curve.db
  local n = #f
  if x <= f[1] then return d[1] end
  if x >= f[n] then return d[n] end
  local lo, hi = 1, n
  while hi - lo > 1 do
    local mid = (lo + hi) // 2
    if f[mid] <= x then lo = mid else hi = mid end
  end
  local t = (math.log(x) - math.log(f[lo])) / (math.log(f[hi]) - math.log(f[lo]))
  return d[lo] + t * (d[hi] - d[lo])
end

local function edit()
  S.dirty = true
  S.push = true
end

---------------------------------------------------------------- loading

local function load_meas(path)
  local lines = read_lines(path)
  if not lines then return nil, "Cannot read the measurement file." end
  local f, d = {}, {}
  for _, l in ipairs(lines) do
    local c = split_csv(l)
    local x, y = tonumber(c[1]), tonumber(c[2])
    if x and y and x > 0 then f[#f + 1] = x; d[#d + 1] = y end
  end
  if #f < 2 then return nil, "No frequency rows found. Expected: frequency,raw" end
  return { f = f, db = d }
end

local function load_target(path)
  local lines = read_lines(path)
  if not lines or #lines < 2 then return nil, "Cannot read the target file." end
  local header = split_csv(lines[1])
  local rows = {}
  for i = 2, #lines do
    local c = split_csv(lines[i])
    if tonumber(c[1]) then rows[#rows + 1] = c end
  end
  if #rows < 2 then return nil, "No data rows in the target file." end
  return header, rows
end

local function rebuild_target()
  local f, d = {}, {}
  local k = S.target_col + 2
  for _, c in ipairs(S.target_rows) do
    local x, y = tonumber(c[1]), tonumber(c[k])
    if x and y then f[#f + 1] = x; d[#d + 1] = y end
  end
  S.tcurve = { f = f, db = d }
end

local function load_peq(path)
  local lines = read_lines(path)
  if not lines then return false, "Cannot read the EQ file." end
  local bands, skipped = {}, 0
  for _, l in ipairs(lines) do
    local pre = l:match("^Preamp:%s*([%-%d%.]+)")
    if pre then S.preamp = tonumber(pre) end
    local on, t, fc, g, q = l:match("Filter%s*%d+:%s*(%a+)%s+(%a+)%s+Fc%s+([%d%.]+)%s+Hz%s+Gain%s+([%-%d%.]+)%s+dB%s+Q%s+([%d%.]+)")
    if on then
      if tonumber(fc) < SUGGEST_MIN_F or tonumber(fc) > SUGGEST_MAX_F then
        skipped = skipped + 1
      elseif t == "PK" or t == "LSC" or t == "HSC" then
        bands[#bands + 1] = { on = (on == "ON"), t = t, f = tonumber(fc), g = tonumber(g), q = tonumber(q) }
      else
        skipped = skipped + 1
      end
    end
  end
  if #bands > MAXBANDS then
    for i = #bands, MAXBANDS + 1, -1 do bands[i] = nil end
  end
  S.bands = bands
  local msg = string.format("Loaded %d bands.", #bands)
  if skipped > 0 then msg = msg .. " Skipped " .. skipped .. " band(s) below 150 Hz, above 5 kHz or of other types." end
  return true, msg
end

---------------------------------------------------------------- filter math (RBJ biquads)

local function coeffs(b)
  local w0 = 2 * math.pi * b.f / FS
  local A = 10 ^ (b.g / 40)
  local cw, sw = math.cos(w0), math.sin(w0)
  local alpha = sw / (2 * b.q)
  local b0, b1, b2, a0, a1, a2
  if b.t == "LSC" then
    local sq = 2 * math.sqrt(A) * alpha
    b0 = A * ((A + 1) - (A - 1) * cw + sq)
    b1 = 2 * A * ((A - 1) - (A + 1) * cw)
    b2 = A * ((A + 1) - (A - 1) * cw - sq)
    a0 = (A + 1) + (A - 1) * cw + sq
    a1 = -2 * ((A - 1) + (A + 1) * cw)
    a2 = (A + 1) + (A - 1) * cw - sq
  elseif b.t == "HSC" then
    local sq = 2 * math.sqrt(A) * alpha
    b0 = A * ((A + 1) + (A - 1) * cw + sq)
    b1 = -2 * A * ((A - 1) + (A + 1) * cw)
    b2 = A * ((A + 1) + (A - 1) * cw - sq)
    a0 = (A + 1) - (A - 1) * cw + sq
    a1 = 2 * ((A - 1) - (A + 1) * cw)
    a2 = (A + 1) - (A - 1) * cw - sq
  else
    b0 = 1 + alpha * A; b1 = -2 * cw; b2 = 1 - alpha * A
    a0 = 1 + alpha / A; a1 = -2 * cw; a2 = 1 - alpha / A
  end
  return { b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0 }
end

-- magnitude in dB of one biquad at frequency x
local function band_db(c, x)
  local w = 2 * math.pi * x / FS
  local cw, c2 = math.cos(w), math.cos(2 * w)
  local sw, s2 = math.sin(w), math.sin(2 * w)
  local nr = c[1] + c[2] * cw + c[3] * c2
  local ni = -(c[2] * sw + c[3] * s2)
  local dr = 1 + c[4] * cw + c[5] * c2
  local di = -(c[4] * sw + c[5] * s2)
  return 10 * math.log((nr * nr + ni * ni) / (dr * dr + di * di), 10)
end

local function refresh()
  local res = { ready = false, raw = {}, targ = {}, eq = {} }
  if S.meas and S.tcurve and #S.tcurve.f > 1 then
    local ref = 1000
    local m1 = interp(S.meas, ref)
    local t1 = interp(S.tcurve, ref)
    local cs = {}
    for _, b in ipairs(S.bands) do
      if b.on then cs[#cs + 1] = coeffs(b) end
    end
    -- EQ curve alone
    local eqv = {}
    for i, x in ipairs(GRID) do
      local v = 0
      for _, c in ipairs(cs) do v = v + band_db(c, x) end
      eqv[i] = v
    end
    local sum = 0
    for i, x in ipairs(GRID) do
      local mv = interp(S.meas, x) - m1
      local tv = interp(S.tcurve, x) - t1
      local ev = mv + eqv[i] + S.gain
      res.raw[i] = mv
      res.targ[i] = tv
      res.eq[i] = ev
    end
    -- gap measures shape only: the level offset is removed (level is the gain's job)
    local off = 0
    for i = 1, NGRID do off = off + (res.targ[i] - res.eq[i]) end
    off = off / NGRID
    for i = 1, NGRID do sum = sum + (res.targ[i] - res.eq[i] - off) ^ 2 end
    res.ready = true
    S.rms = math.sqrt(sum / NGRID)
  else
    S.rms = nil
  end
  S.res = res
end

---------------------------------------------------------------- ReaEQ

local function asinh(x)
  return math.log(x + math.sqrt(x * x + 1))
end

-- the script works on one ReaEQ in Monitoring FX named "AutoEQ" or "AutoEQ: <headphones>"; other FX are never touched
-- Monitoring FX live on the master track at index 0x1000000 + n
local EQ_PREFIX = "AutoEQ"
local LEGACY_NAMES = { ["Corrective EQ"] = true } -- older name, taken over and renamed

local function eq_name()
  return S.hp_name and (EQ_PREFIX .. ": " .. S.hp_name) or EQ_PREFIX
end

local function is_ours(label)
  return label == EQ_PREFIX or label:sub(1, #EQ_PREFIX + 2) == EQ_PREFIX .. ": " or LEGACY_NAMES[label] == true
end
local REC = 0x1000000

local function fx_label(tr, idx)
  local ok, rn = reaper.TrackFX_GetNamedConfigParm(tr, idx, "renamed_name")
  if ok and rn and rn ~= "" then return rn end
  local _, nm = reaper.TrackFX_GetFXName(tr, idx, "")
  return nm or ""
end

-- finds our ReaEQ in Monitoring FX; returns master track and FX index, or nil
local function resolve_target()
  local master = reaper.GetMasterTrack(0)
  for i = 0, (reaper.TrackFX_GetRecCount(master) or 0) - 1 do
    if is_ours(fx_label(master, REC + i)) then return master, REC + i end
  end
  return nil
end

-- gives our EQ the name of the current headphones (only the name; nothing else changes)
local function rename_eq()
  local tr, fx = resolve_target()
  if tr and fx_label(tr, fx) ~= eq_name() then
    reaper.TrackFX_SetNamedConfigParm(tr, fx, "renamed_name", eq_name())
  end
end

-- used by Push: our ReaEQ, or a new ReaEQ added at the end of Monitoring FX and renamed
local function find_fx()
  local tr, fx = resolve_target()
  if tr then return tr, fx end
  local master = reaper.GetMasterTrack(0)
  local before = reaper.TrackFX_GetRecCount(master) or 0
  reaper.TrackFX_AddByName(master, "ReaEQ", true, -1)
  local after = reaper.TrackFX_GetRecCount(master) or 0
  if after <= before then return nil, "Could not add ReaEQ to Monitoring FX." end
  local idx = REC + after - 1
  reaper.TrackFX_SetNamedConfigParm(master, idx, "renamed_name", eq_name())
  -- show the user what happened: open the Monitoring FX chain with the new EQ selected
  reaper.TrackFX_Show(master, idx, 1)
  S.added_eq = true
  return master, idx
end

-- reads the number ReaEQ shows for a parameter, e.g. "212.8 Hz", "+17.6 dB", "4.00 oct", "2.1 kHz"
local function read_shown(tr, fx, p)
  local _, s = reaper.TrackFX_GetFormattedParamValue(tr, fx, p, "")
  if s:lower():find("inf") then return -1000 end -- ReaEQ shows "-inf" for gain at the bottom of its range
  local num, unit = s:match("([%+%-]?[%d%.]+)%s*(%a*)")
  if not num then return nil end
  local v = tonumber(num)
  if v and unit:lower():sub(1, 1) == "k" then v = v * 1000 end
  return v
end

-- finds the 0..1 value that makes ReaEQ show the target number (bisection, no assumed scale)
local function set_shown(tr, fx, p, target)
  local orig = reaper.TrackFX_GetParamNormalized(tr, fx, p)
  reaper.TrackFX_SetParamNormalized(tr, fx, p, 0)
  local v0 = read_shown(tr, fx, p)
  reaper.TrackFX_SetParamNormalized(tr, fx, p, 1)
  local v1 = read_shown(tr, fx, p)
  if not v0 or not v1 or v0 == v1 then
    if orig then reaper.TrackFX_SetParamNormalized(tr, fx, p, orig) end -- leave the value as it was
    return false
  end
  local increasing = v1 > v0
  local lo, hi = 0.0, 1.0
  for _ = 1, 40 do
    local mid = (lo + hi) / 2
    reaper.TrackFX_SetParamNormalized(tr, fx, p, mid)
    local v = read_shown(tr, fx, p)
    if not v then return false end
    if (v < target) == increasing then lo = mid else hi = mid end
  end
  reaper.TrackFX_SetParamNormalized(tr, fx, p, (lo + hi) / 2)
  return true
end

-- ReaEQ slot i (0-based) has three parameters in a row: Freq, Gain, BW.
-- The parameter name shows the slot type, e.g. "Freq-Low Shelf", "Freq-Band 2", "Freq-High Shelf 4".
local TYPE_PAT = {
  LSC = "^Freq%-Low Shelf%s*%d*$",
  HSC = "^Freq%-High Shelf%s*%d*$",
  PK  = "^Freq%-Band%s*%d*$",
}
local TYPE_GUESS = { LSC = 0, HSC = 1, PK = 8 } -- tried first; checked against the name below
local TYPE_CODE = {}                           -- codes confirmed on this machine

local function slot_name(tr, fx, i)
  local _, name = reaper.TrackFX_GetParamName(tr, fx, i * 3, "")
  return name or ""
end

-- sets the type of slot i and checks it by the parameter name; returns true when the type is right
local function set_slot_type(tr, fx, i, t)
  if slot_name(tr, fx, i):match(TYPE_PAT[t]) then return true end
  local tries = {}
  if TYPE_CODE[t] then tries[#tries + 1] = TYPE_CODE[t] end
  tries[#tries + 1] = TYPE_GUESS[t]
  for c = 0, 12 do tries[#tries + 1] = c end
  for _, c in ipairs(tries) do
    reaper.TrackFX_SetNamedConfigParm(tr, fx, "BANDTYPE" .. i, tostring(c))
    if slot_name(tr, fx, i):match(TYPE_PAT[t]) then
      TYPE_CODE[t] = c
      return true
    end
  end
  return false
end

-- ReaEQ band count: parameters come in groups of three per band (Freq, Gain, BW), names start with "Freq-"
local function band_count(tr, fx)
  local n = 0
  for p = 0, reaper.TrackFX_GetNumParams(tr, fx) - 1 do
    local _, nm = reaper.TrackFX_GetParamName(tr, fx, p, "")
    if (nm or ""):match("^Freq%-") then n = n + 1 end
  end
  return n
end

-- base64 (pure Lua)
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64I = {}
for i = 1, 64 do B64I[B64:sub(i, i)] = i - 1 end
local function b64dec(s)
  s = s:gsub("[^%w%+/]", "")
  local out, bits, nb = {}, 0, 0
  for i = 1, #s do
    bits = (bits << 6) | B64I[s:sub(i, i)]
    nb = nb + 6
    if nb >= 8 then
      nb = nb - 8
      out[#out + 1] = string.char((bits >> nb) & 0xFF)
    end
  end
  return table.concat(out)
end
local function b64enc(d)
  local out = {}
  for i = 1, #d, 3 do
    local a, b, c = d:byte(i, i + 2)
    local n = (a << 16) | ((b or 0) << 8) | (c or 0)
    out[#out + 1] = B64:sub((n >> 18) + 1, (n >> 18) + 1) .. B64:sub(((n >> 12) & 63) + 1, ((n >> 12) & 63) + 1)
      .. (b and B64:sub(((n >> 6) & 63) + 1, ((n >> 6) & 63) + 1) or "=") .. (c and B64:sub((n & 63) + 1, (n & 63) + 1) or "=")
  end
  return table.concat(out)
end

-- finds the band table in ReaEQ's state: record size (32 or 33), band count, then the records
-- record: int type, int enabled, double freq, double gain (linear), double bandwidth (octaves) [+1 byte]
local function find_bands(d)
  for o = 1, math.min(#d - 8, 200) do
    local rs, n = string.unpack("<i4i4", d, o)
    if (rs == 32 or rs == 33) and n >= 1 and n <= 64 and o + 8 + n * rs - 1 <= #d then
      local ok = true
      for k = 0, n - 1 do
        local r = o + 8 + k * rs
        local typ, en, f = string.unpack("<i4i4d", d, r)
        if typ < 0 or typ > 20 or (en ~= 0 and en ~= 1) or not (f > 1 and f < 50000) then ok = false; break end
      end
      if ok then return o, rs, n end
    end
  end
end

-- makes the state hold `need` bands by copying the last record (as a Band at 1 kHz, 0 dB, 1 octave)
local function grow_state(d, need)
  local o, rs, n = find_bands(d)
  if not o then return nil, "band table not found" end
  if n >= need then return d end
  local last = d:sub(o + 8 + (n - 1) * rs, o + 8 + n * rs - 1)
  local rec = string.pack("<i4i4ddd", 8, 1, 1000.0, 1.0, 1.0) .. last:sub(33)
  local add = string.rep(rec, need - n)
  local cut = o + 8 + n * rs
  local nd = d:sub(1, o + 3) .. string.pack("<i4", need) .. d:sub(o + 8, cut - 1) .. add .. d:sub(cut)
  -- REAPER's 'qeer' header holds the size of the data that follows it; keep it right
  if nd:sub(1, 4) == "qeer" and o >= 13 then
    local so = o - 12
    local size = string.unpack("<i4", nd, so)
    if size > 0 and so + 12 + size - 1 <= #d + 8 then
      nd = nd:sub(1, so - 1) .. string.pack("<i4", size + #add) .. nd:sub(so + 4)
    end
  end
  return nd
end

-- adds bands to ReaEQ until it has at least `need`; returns the band count it has afterwards
local function ensure_bands(tr, fx, need)
  local have = band_count(tr, fx)
  if have >= need then return have end
  local ok, st = reaper.TrackFX_GetNamedConfigParm(tr, fx, "vst_chunk")
  if not ok or not st or st == "" then return have end
  local nd = grow_state(b64dec(st), need)
  if not nd then return have end
  reaper.TrackFX_SetNamedConfigParm(tr, fx, "vst_chunk", b64enc(nd))
  return band_count(tr, fx)
end

-- reads what ReaEQ shows: bands (type, on, freq, gain, bandwidth) and Global Gain
local CODE_TYPE = { [0] = "LSC", [1] = "HSC", [2] = "PK", [8] = "PK", [9] = "PK" }
local function read_reaeq(tr, fx)
  local out = { bands = {}, gain = 0 }
  local n = math.min(MAXBANDS, band_count(tr, fx))
  for i = 0, n - 1 do
    local _, ts = reaper.TrackFX_GetNamedConfigParm(tr, fx, "BANDTYPE" .. i)
    local _, es = reaper.TrackFX_GetNamedConfigParm(tr, fx, "BANDENABLED" .. i)
    local f = read_shown(tr, fx, i * 3) or 1000
    local g = read_shown(tr, fx, i * 3 + 1) or 0
    local bw = read_shown(tr, fx, i * 3 + 2) or 1
    out.bands[#out.bands + 1] = {
      code = tonumber(ts), on = (tonumber(es) or 1) ~= 0,
      f = math.max(FMIN, math.min(FMAX, f)), g = math.max(-24, math.min(24, g)), bw = math.max(0.05, bw),
    }
  end
  for p = 0, reaper.TrackFX_GetNumParams(tr, fx) - 1 do
    local _, pn = reaper.TrackFX_GetParamName(tr, fx, p, "")
    if pn == "Global Gain" then out.gain = math.max(-24, math.min(24, read_shown(tr, fx, p) or 0)); break end
  end
  return out
end

-- short text form of a ReaEQ reading, used to see if anything changed
local function snap_key(r)
  local t = { string.format("G%.1f", r.gain) }
  for _, b in ipairs(r.bands) do
    t[#t + 1] = string.format("%s%s%.1f/%.1f/%.2f", tostring(b.code), b.on and "+" or "-", b.f, b.g, b.bw)
  end
  return table.concat(t, "|")
end

local function apply_reaeq()
  local tr, fx = find_fx()
  if not tr then
    S.status = fx
    return
  end
  if fx_label(tr, fx) ~= eq_name() then reaper.TrackFX_SetNamedConfigParm(tr, fx, "renamed_name", eq_name()) end
  -- every script band gets one ReaEQ band, in order; bands that are off are written as disabled
  local want = math.min(MAXBANDS, #S.bands)
  local nslots = math.min(MAXBANDS, ensure_bands(tr, fx, want))
  local written, problems = 0, {}

  for k, b in ipairs(S.bands) do
    local i = k - 1
    if i < nslots then
      reaper.TrackFX_SetNamedConfigParm(tr, fx, "BANDENABLED" .. i, b.on and "1" or "0")
      if not set_slot_type(tr, fx, i, b.t) then
        problems[#problems + 1] = "band " .. k .. " type"
      end
      local ok = set_shown(tr, fx, i * 3, b.f)
      ok = set_shown(tr, fx, i * 3 + 1, b.g) and ok
      ok = set_shown(tr, fx, i * 3 + 2, 2 * asinh(1 / (2 * b.q)) / math.log(2)) and ok
      if ok then written = written + 1 else problems[#problems + 1] = "band " .. k .. " values" end
    end
  end

  -- remaining ReaEQ bands: off, and 0 dB (not raw 0, which is -inf)
  local total = band_count(tr, fx)
  for i = math.min(#S.bands, nslots), total - 1 do
    reaper.TrackFX_SetNamedConfigParm(tr, fx, "BANDENABLED" .. i, "0")
    set_shown(tr, fx, i * 3 + 1, 0)
  end

  -- output gain -> ReaEQ Global Gain
  for p = 0, reaper.TrackFX_GetNumParams(tr, fx) - 1 do
    local _, pn = reaper.TrackFX_GetParamName(tr, fx, p, "")
    if pn == "Global Gain" then
      if not set_shown(tr, fx, p, S.gain) then problems[#problems + 1] = "global gain" end
      break
    end
  end

  if want > nslots then
    problems[#problems + 1] = string.format("ReaEQ has only %d bands, %d not written", nslots, want - nslots)
  end

  -- remember what ReaEQ shows now, so later changes made in ReaEQ can be told apart
  S.sync_key = tostring(reaper.TrackFX_GetFXGUID(tr, fx))
  S.snap = snap_key(read_reaeq(tr, fx))

  if S.added_eq and #problems == 0 then
    S.added_eq = false
    S.status = "Added " .. eq_name() .. " to Monitoring FX and wrote " .. written .. " band(s)."
    return
  end
  S.added_eq = false

  if #problems > 0 then
    S.status = string.format("Wrote %d band(s). Problem: %s", written, table.concat(problems, ", "))
  else
    S.status = string.format("Wrote %d band(s) to %s (Monitoring FX).", written, eq_name())
  end
end

-- ReaEQ -> script: if ReaEQ changed since the last push or reading, take its bands into the script
-- takes a ReaEQ reading into the script (no push back)
local function import_reading(r)

  -- keep every band that is on, and every band up to the script's own count
  local last = 0
  for i, b in ipairs(r.bands) do
    if b.on or i <= #S.bands then last = i end
  end
  local nb = {}
  for i = 1, last do
    local b = r.bands[i]
    local x = 2 ^ b.bw
    nb[i] = { on = b.on, t = CODE_TYPE[b.code] or "PK", f = b.f, g = math.floor(b.g * 10 + 0.5) / 10,
      q = math.sqrt(x) / (x - 1) }
  end
  S.bands = nb
  S.gain = r.gain
  S.dirty = true -- redraw only; no push back to ReaEQ
end

local function poll_reaeq()
  local tr, fx = resolve_target()
  if not tr then return end
  local key = tostring(reaper.TrackFX_GetFXGUID(tr, fx))
  local r = read_reaeq(tr, fx)
  local sk = snap_key(r)
  if S.sync_key ~= key then
    -- first sight of this EQ: only remember it, do not import without a change
    S.sync_key, S.snap = key, sk
    return
  end
  if sk == S.snap then return end
  S.snap = sk
  import_reading(r)
  S.status = "Changes from ReaEQ taken into the script."
end

-- on start: if our EQ is already in Monitoring FX, continue from its bands
local function load_existing_eq()
  local tr, fx = resolve_target()
  if not tr then return end
  -- keep the headphone name from the EQ name, so a later push does not rename it back
  local hp = fx_label(tr, fx):match("^" .. EQ_PREFIX .. ": (.+)$")
  if hp then S.hp_name = hp end
  local r = read_reaeq(tr, fx)
  S.sync_key = tostring(reaper.TrackFX_GetFXGUID(tr, fx))
  S.snap = snap_key(r)
  local any = false
  for _, b in ipairs(r.bands) do if b.on then any = true end end
  if any then
    import_reading(r)
    S.status = "Loaded " .. fx_label(tr, fx) .. " from Monitoring FX."
  end
end

---------------------------------------------------------------- presets

local function save_preset(name)
  local lines = { string.format("Preamp: %.1f dB", S.preamp) }
  for i, b in ipairs(S.bands) do
    lines[#lines + 1] = string.format("Filter %d: %s %s Fc %d Hz Gain %.1f dB Q %.2f",
      i, b.on and "ON" or "OFF", b.t, math.floor(b.f + 0.5), b.g, b.q)
  end
  local path = DATA .. name .. ".txt"
  local fh = io.open(path, "w")
  if not fh then return "Could not write " .. path end
  fh:write(table.concat(lines, "\n") .. "\n")
  fh:close()
  return "Saved " .. path
end

---------------------------------------------------------------- AutoEq data (fetched from autoeq.app and GitHub, cached)

local SITE = "https://autoeq.app"
local RAW = "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/"
local CACHE = DATA .. "cache" .. SEP
reaper.RecursiveCreateDirectory(CACHE, 0)

local ENTRIES, ENTRY_NAMES, NORM = {}, {}, {}
local PICK = { filter = "", name = nil, src = 0, last = nil, hits = {} }
local MAX_HITS = 1500

-- search: every word typed must appear in the name, ignoring case, spaces, hyphens and other punctuation
local function find_matches(query)
  local toks = {}
  for w in query:lower():gmatch("%w+") do toks[#toks + 1] = w end
  local hits = {}
  for _, n in ipairs(ENTRY_NAMES) do
    local ok = true
    for _, t in ipairs(toks) do
      if not NORM[n]:find(t, 1, true) then ok = false; break end
    end
    if ok then
      hits[#hits + 1] = n
      if #hits >= MAX_HITS then break end
    end
  end
  return hits
end
local SITE_READY = false

local function url_enc(s)
  return (s:gsub("[^%w%-%._~/]", function(c) return string.format("%%%02X", c:byte()) end))
end

-- downloads run in the background so the window never waits; results are cached in the cache folder
local IS_WIN = (reaper.GetOS() or ""):find("Win") ~= nil
local JOBS = {}

local function exists(p)
  local f = io.open(p, "rb")
  if f then f:close(); return true end
  return false
end

-- starts a download; done(path) or fail() is called later by poll_jobs() (at once if cached)
local function fetch_async(url, cache_name, done, fail)
  local path = CACHE .. (cache_name:gsub('[/\\:*?"<>|]', "_"))
  if exists(path) then done(path); return end
  local part, bad = path .. ".part", path .. ".fail"
  os.remove(part); os.remove(bad)
  local log = DATA .. "fetch.log"
  if IS_WIN then
    -- a .bat file avoids nested quotes; % in URLs must be doubled inside .bat files
    local u = url:gsub("%%", "%%%%")
    local bat = path .. ".bat"
    local fh = io.open(bat, "w")
    if not fh then if fail then fail() end return end
    fh:write("@echo off\r\n")
    fh:write(string.format('curl -sSfL --max-time 60 -A "Mozilla/5.0" "%s" -o "%s" 2>>"%s"\r\n', u, part, log))
    fh:write(string.format('if errorlevel 1 (echo %s>>"%s" & echo fail>"%s") else (move /Y "%s" "%s" >nul)\r\n',
      u, log, bad, part, path))
    fh:close()
    reaper.ExecProcess('cmd.exe /C "' .. bat .. '"', -2)
  else
    os.execute(string.format(
      '( curl -sSfL --max-time 60 -A "Mozilla/5.0" "%s" -o "%s" 2>>"%s" && mv "%s" "%s" || { echo "failed: %s" >>"%s"; echo fail >"%s"; } ) >/dev/null 2>&1 &',
      url, part, log, part, path, url, log, bad))
  end
  JOBS[#JOBS + 1] = { path = path, bad = bad, done = done, fail = fail, t0 = reaper.time_precise() }
end

-- called every frame: hands finished downloads to their callbacks
local function poll_jobs()
  for i = #JOBS, 1, -1 do
    local j = JOBS[i]
    if exists(j.path) then
      table.remove(JOBS, i)
      os.remove(j.path .. ".bat")
      j.done(j.path)
    elseif exists(j.bad) or reaper.time_precise() - j.t0 > 90 then
      table.remove(JOBS, i)
      os.remove(j.bad); os.remove(j.path .. ".bat"); os.remove(j.path .. ".part")
      if j.fail then j.fail() end
    end
  end
end

-- tries each GitHub path in turn (some sources have a rig folder, some do not)
local function fetch_first_async(paths, cache_name, done, fail, k)
  k = k or 1
  local parts = paths[k]
  if not parts then if fail then fail() end return end
  local segs = {}
  for _, q in ipairs(parts) do
    if q ~= "" then segs[#segs + 1] = url_enc(q) end
  end
  fetch_async(RAW .. table.concat(segs, "/"), cache_name, done, function()
    fetch_first_async(paths, cache_name, done, fail, k + 1)
  end)
end

local function meas_paths(e, name)
  return {
    { "measurements", e.source, "data", e.form, e.rig, name .. ".csv" },
    { "measurements", e.source, "data", e.form, name .. ".csv" },
  }
end

-- sets the target column to the AutoEq default for this form factor
local function select_target_for(form)
  local want = (form == "in-ear") and "In-Ear (2016)" or "Over-Ear (2018)"
  for i = 2, #S.target_header do
    if S.target_header[i] == want then
      S.target_col = i - 2
      break
    end
  end
  rebuild_target()
end

-- own suggestion: as few bands as possible, no extreme gains, no filters close together
local SUG = {
  gain_max = 6.0,     -- dB, largest boost or cut
  gain_min = 1.0,     -- dB, smaller bands are not worth adding
  min_oct = 1.0,      -- octaves between band centres
  q_list = { 0.7, 0.85, 1.0, 1.2, 1.4, 1.6 }, -- wide filters only (Q 1.6 = about 0.9 octave)
  min_gain_rms = 0.15, -- dB RMS a new band must improve, or the search stops
}

local function suggest_bands()
  if not (S.meas and S.tcurve) then return {}, nil end
  local xs, raw = {}, {}
  for _, x in ipairs(GRID) do
    if x >= SUGGEST_MIN_F and x <= SUGGEST_MAX_F then
      xs[#xs + 1] = x
      raw[#raw + 1] = interp(S.tcurve, x) - interp(S.meas, x)
    end
  end
  -- 1/3-octave smoothing, so narrow peaks and dips are not chased
  local err = {}
  for i, x in ipairs(xs) do
    local sum, n = 0, 0
    for j, y in ipairs(xs) do
      if math.abs(math.log(y / x, 2)) <= 1 / 6 then sum = sum + raw[j]; n = n + 1 end
    end
    err[i] = sum / n
  end

  -- residual after the bands, with the level offset removed (level does not matter)
  local function residual(bs)
    local cs = {}
    for _, b in ipairs(bs) do cs[#cs + 1] = coeffs(b) end
    local r, mean = {}, 0
    for i, x in ipairs(xs) do
      local v = err[i]
      for _, c in ipairs(cs) do v = v - band_db(c, x) end
      r[i] = v
      mean = mean + v
    end
    mean = mean / #xs
    local sq = 0
    for i = 1, #r do r[i] = r[i] - mean; sq = sq + r[i] ^ 2 end
    return math.sqrt(sq / #xs), r
  end

  local bands = {}
  local function far_enough(f)
    for _, b in ipairs(bands) do
      if math.abs(math.log(f / b.f, 2)) < SUG.min_oct then return false end
    end
    return true
  end
  local function clamp_g(g) return math.max(-SUG.gain_max, math.min(SUG.gain_max, g)) end
  local function clamp_f(f) return math.max(SUGGEST_MIN_F, math.min(SUGGEST_MAX_F, f)) end

  local G_LIST = { -6, -4.5, -3, -2, -1, 1, 2, 3, 4.5, 6 }

  -- improves one band (frequency, Q, gain) while the other bands stay fixed
  local function refine(k)
    local b = bands[k]
    local best = residual(bands)
    local function try(field, v)
      local old = b[field]; b[field] = v
      local c = residual(bands)
      if c < best then best = c else b[field] = old end
    end
    local function far_from_others(f)
      for j, o in ipairs(bands) do
        if j ~= k and math.abs(math.log(f / o.f, 2)) < SUG.min_oct then return false end
      end
      return true
    end
    for _ = 1, 3 do
      for _, q in ipairs(SUG.q_list) do try("q", q) end
      local f0 = b.f
      for st = -6, 6 do
        local f = clamp_f(f0 * 2 ^ (st / 12))
        if far_from_others(f) then try("f", f) end
      end
      local g0 = b.g
      for _, d in ipairs({ -1, -0.5, -0.25, 0.25, 0.5, 1 }) do try("g", clamp_g(g0 + d)) end
    end
    return best
  end

  local cost = residual(bands)
  for _ = 1, SUG_MAX_BANDS do
    -- try a band at every allowed centre and gain; keep the one that helps most
    local cand, best = nil, math.huge
    for _, x in ipairs(xs) do
      if far_enough(x) then
        for _, g in ipairs(G_LIST) do
          bands[#bands + 1] = { on = true, t = "PK", f = x, g = g, q = 1.0 }
          local c = residual(bands)
          if c < best then best, cand = c, bands[#bands] end
          bands[#bands] = nil
        end
      end
    end
    if not cand then break end
    bands[#bands + 1] = cand
    for _ = 1, 2 do
      for k = 1, #bands do best = refine(k) end
    end
    if math.abs(cand.g) < SUG.gain_min or cost - best < SUG.min_gain_rms then
      bands[#bands] = nil
      for k = 1, #bands do refine(k) end
      break
    end
    cost = best
  end
  cost = residual(bands)
  table.sort(bands, function(a, b) return a.f < b.f end)
  return bands, cost
end

-- gain suggested with the bands: makes up for their average level change in 150 Hz - 5 kHz (set once, not automatic)
local function suggested_gain(bands)
  local cs = {}
  for _, b in ipairs(bands) do if b.on then cs[#cs + 1] = coeffs(b) end end
  local sum, n = 0, 0
  for _, x in ipairs(GRID) do
    if x >= SUGGEST_MIN_F and x <= SUGGEST_MAX_F then
      for _, c in ipairs(cs) do sum = sum + band_db(c, x) end
      n = n + 1
    end
  end
  local g = -(sum / math.max(1, n))
  return math.floor(math.max(-12, math.min(12, g)) * 10 + 0.5) / 10
end

local function apply_suggestion()
  local bands, cost = suggest_bands()
  S.bands = bands
  S.gain = suggested_gain(bands)
  if cost then
    S.status = string.format("Suggested %d band(s), 150 Hz - 5 kHz, max %.0f dB, at least %.0f octave apart.",
      #bands, SUG.gain_max, SUG.min_oct)
  end
  edit()
end

local function load_selection(e, name)
  local token = {}
  S.sel_token = token
  S.status = "Loading " .. name .. "..."
  fetch_first_async(meas_paths(e, name), e.source .. " - " .. name .. " - raw.csv", function(mp)
    if S.sel_token ~= token then return end -- another headphone was chosen meanwhile
    local m, merr = load_meas(mp)
    if not m then
      S.status = merr
      return
    end
    S.meas = m
    S.hp_name = name
    rename_eq()
    select_target_for(e.form)
    apply_suggestion()
    S.sel = 1
  end, function()
    if S.sel_token ~= token then return end
    S.status = "No measurement found on AutoEq for " .. name .. " (" .. e.source .. "). Details: fetch.log"
  end)
end

local function unescape(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- headphone list from results/INDEX.md on GitHub: one line per equalization profile
-- line format: - [Name](./Source/Folder/Name) by Source [on rig]
local function parse_entries(path)
  ENTRIES, ENTRY_NAMES = {}, {}
  for _, line in ipairs(read_lines(path) or {}) do
    local name, link = line:match("^%- %[(.-)%]%(%./(.-)%) by .-%s*$")
    if name and link then
      local segs = {}
      for seg in link:gmatch("[^/]+") do segs[#segs + 1] = unescape(seg) end
      local source, folder = segs[1], segs[2]
      if source and folder then
        local form = folder:match("(%S+)$") or ""
        local rig = folder:sub(1, math.max(0, #folder - #form - 1))
        local list = ENTRIES[name]
        if not list then
          list = {}
          ENTRIES[name] = list
          ENTRY_NAMES[#ENTRY_NAMES + 1] = name
          NORM[name] = (name:lower():gsub("[^%w]", ""))
        end
        list[#list + 1] = { source = source, form = form, rig = rig, folder = folder }
      end
    end
  end
  table.sort(ENTRY_NAMES, function(a, b) return a:lower() < b:lower() end)
  if #ENTRY_NAMES == 0 then
    os.remove(path) -- not a valid index (for example an error page); do not keep it cached
    return false
  end
  return true
end

local function init_site()
  S.list_state = "loading"
  fetch_async(RAW .. "results/INDEX.md", "INDEX.md", function(path)
    if parse_entries(path) then
      S.list_state = "ok"
    else
      S.list_state = "fail"
      S.status = "The headphone list from GitHub was not valid. Press Retry in the headphone menu."
    end
  end, function()
    S.list_state = "fail"
    S.status = "Could not load the headphone list from GitHub. Details: Data/Daniel Kharrat/AutoEQ Integration/fetch.log"
  end)
  if #S.target_header == 0 then
    fetch_async(RAW .. url_enc("targets/All Harman Targets.csv"), "All Harman Targets.csv", function(tp)
      local header, rows = load_target(tp)
      if header then
        S.target_header, S.target_rows = header, rows
        select_target_for("over-ear")
        edit()
      end
    end, function()
      S.status = "Could not load the target curves from GitHub. Details: fetch.log"
    end)
  end
end

---------------------------------------------------------------- GUI (dark REAPER style, ReaEQ-like layout)

local C = {
  bg = 0x17171B, card = 0x222228, well = 0x131317, line = 0x2E2E36, grid = 0x24242B, zero = 0x34343D,
  text = 0xEDEDF2, muted = 0x8A8A96, dim = 0x5C5C68, accent = 0x5B9BF0, accent_hi = 0x9CC3F7,
  key = 0x2F2F38, keyedge = 0x45454F, primary = 0x2F6FD0, green = 0x52C478, green_t = 0x8FDCA8,
  amber = 0xE0A84A, heart = 0xE8798A,
}

-- fonts: one family per OS; ReaImGui 0.10 sizes fonts at push time, 0.9 at creation
local OS = reaper.GetOS() or ""
local FAMILY = OS:find("Win") and "Segoe UI" or ((OS:find("OSX") or OS:find("mac")) and "Helvetica Neue" or "DejaVu Sans")
local V10 = (function()
  local _, _, rv = reaper.ImGui_GetVersion()
  local a, b = tostring(rv or ""):match("(%d+)%.(%d+)")
  a, b = tonumber(a) or 0, tonumber(b) or 0
  return a > 0 or b >= 10
end)()
local function mkfont(size, bold)
  local flags = bold and reaper.ImGui_FontFlags_Bold() or reaper.ImGui_FontFlags_None()
  local f
  if V10 then f = reaper.ImGui_CreateFont(FAMILY, flags) else f = reaper.ImGui_CreateFont(FAMILY, size, flags) end
  reaper.ImGui_Attach(ctx, f)
  return { f = f, size = size }
end
local FT = {
  body = mkfont(13, false), bold = mkfont(13, true), cap = mkfont(11, true),
  val = mkfont(17, true), big = mkfont(24, true),
}
-- InputText callback: put the cursor at the end once (focusing from code would select all text)
local CARET_FN
if reaper.ImGui_CreateFunctionFromEEL and reaper.ImGui_InputTextFlags_CallbackAlways then
  CARET_FN = reaper.ImGui_CreateFunctionFromEEL([[
    once ? (
      n = strlen(#Buf);
      CursorPos = n;
      SelectionStart = n;
      SelectionEnd = n;
      once = 0;
    );
  ]])
  if CARET_FN then reaper.ImGui_Attach(ctx, CARET_FN) end
end

local function push(ft)
  if V10 then reaper.ImGui_PushFont(ctx, ft.f, ft.size) else reaper.ImGui_PushFont(ctx, ft.f) end
end
local function pop() reaper.ImGui_PopFont(ctx) end

local DL
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function rect(x1, y1, x2, y2, col, r, fl) reaper.ImGui_DrawList_AddRectFilled(DL, x1, y1, x2, y2, col, r or 0, fl or 0) end
local function stroke(x1, y1, x2, y2, col, r, th) reaper.ImGui_DrawList_AddRect(DL, x1, y1, x2, y2, col, r or 0, 0, th or 1) end
local function line(x1, y1, x2, y2, col, th) reaper.ImGui_DrawList_AddLine(DL, x1, y1, x2, y2, col, th or 1) end
local function tsize(ft, s)
  push(ft); local w, h = reaper.ImGui_CalcTextSize(ctx, s); pop()
  return w, h
end
local function text(ft, x, y, col, s)
  push(ft); reaper.ImGui_DrawList_AddText(DL, x, y, col, s); pop()
end
-- text centred vertically in a box of height h (uses the font's real line height)
local function vtext(ft, x, y, h, col, s)
  local _, th = tsize(ft, s)
  text(ft, x, y + (h - th) / 2, col, s)
end
local function hit(id, x, y, w, h)
  reaper.ImGui_SetCursorScreenPos(ctx, x, y)
  reaper.ImGui_InvisibleButton(ctx, id, math.max(1, w), math.max(1, h))
  return reaper.ImGui_IsItemClicked(ctx, 0), reaper.ImGui_IsItemHovered(ctx), reaper.ImGui_IsItemActive(ctx)
end
local function shift_down()
  return (reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Shift()) ~= 0
end
local function chevron(x, y, col)
  reaper.ImGui_DrawList_AddTriangleFilled(DL, x, y, x + 8, y, x + 4, y + 5, col)
end

-- capsule button "Label value v"; returns clicked, width
local function capsule(id, x, y, label, value, h)
  h = h or 28
  local lw = tsize(FT.body, label)
  local vw = tsize(FT.body, value)
  local w = 12 + lw + 7 + vw + 8 + 8 + 12
  local clicked, hov = hit(id, x, y, w, h)
  rect(x, y, x + w, y + h, rgba(hov and 0x2A2A31 or C.card), h / 2)
  stroke(x, y, x + w, y + h, rgba(C.line), h / 2, 1)
  vtext(FT.body, x + 12, y, h, rgba(C.dim), label)
  vtext(FT.body, x + 12 + lw + 7, y, h, rgba(C.text), value)
  chevron(x + w - 20, y + h / 2 - 2, rgba(C.muted))
  return clicked, w
end

-- capsule push button; returns clicked, width
local function button(id, x, y, label, primary)
  local h = 28
  local lw = tsize(FT.bold, label)
  local w = lw + 32
  local clicked, hov = hit(id, x, y, w, h)
  local col = primary and (hov and 0x3A7BDC or C.primary) or (hov and 0x34343B or 0x2C2C32)
  rect(x, y, x + w, y + h, rgba(col), h / 2)
  vtext(FT.bold, x + 16, y, h, rgba(primary and 0xFFFFFF or C.text), label)
  return clicked, w
end

-- switch with label; returns clicked, width
local function switch(id, x, y, on, label, h)
  h = h or 28
  local lw = label and tsize(FT.body, label) or 0
  local w = 28 + (label and (7 + lw) or 0)
  local clicked, hov = hit(id, x, y, w, h)
  local ty = y + (h - 17) / 2
  rect(x, ty, x + 28, ty + 17, rgba(on and C.accent or C.key), 8.5)
  if not on then stroke(x, ty, x + 28, ty + 17, rgba(C.keyedge), 8.5, 1) end
  local kx = on and (x + 19.5) or (x + 8.5)
  reaper.ImGui_DrawList_AddCircleFilled(DL, kx, ty + 8.5, 6, rgba(on and 0xFFFFFF or C.muted), 16)
  if label then vtext(FT.body, x + 35, y, h, rgba((on or hov) and C.text or C.muted), label) end
  return clicked, w
end

-- horizontal value bar: label left, value right, accent fill; drag anywhere, Shift = fine, double-click = reset
local function hbar(id, x, y, w, h, t, bipolar, label, value, unit, ticks)
  local _, hov, act = hit(id, x, y, w, h)
  local nt
  if reaper.ImGui_IsItemActivated(ctx) and not shift_down() then
    local mx = reaper.ImGui_GetMousePos(ctx)
    nt = clamp((mx - x) / w, 0, 1)
  elseif act then
    local dx = reaper.ImGui_GetMouseDelta(ctx)
    if dx ~= 0 then nt = clamp(t + dx / w * (shift_down() and 0.15 or 1), 0, 1) end
  end
  local reset = hov and reaper.ImGui_IsMouseDoubleClicked(ctx, 0)
  t = nt or t
  rect(x, y, x + w, y + h, rgba(C.well), 8)
  if ticks then
    for _, tt in ipairs(ticks) do line(x + tt * w, y + h - 5, x + tt * w, y + h - 1, rgba(C.line)) end
  end
  local fx = x + 1 + t * (w - 2)
  if bipolar then
    local mid = x + w / 2
    line(mid, y + 1, mid, y + h - 1, rgba(C.line))
    rect(math.min(mid, fx), y + 1, math.max(mid, fx), y + h - 1, rgba(C.accent, 0x3D))
  elseif fx > x + 2 then
    rect(x + 1, y + 1, fx, y + h - 1, rgba(C.accent, 0x3D), 7, reaper.ImGui_DrawFlags_RoundCornersLeft())
  end
  local ex = clamp(fx, x + 3, x + w - 3)
  rect(ex - 1, y + 6, ex + 1, y + h - 6, rgba(C.accent), 1)
  stroke(x, y, x + w, y + h, rgba((hov or act) and C.keyedge or C.line), 8, 1)
  vtext(FT.cap, x + 10, y, h, rgba(C.muted), label)
  local uw = tsize(FT.cap, unit)
  local vw = tsize(FT.val, value)
  vtext(FT.cap, x + w - 10 - uw, y + 2, h, rgba(C.muted), unit)
  vtext(FT.val, x + w - 10 - uw - 4 - vw, y, h, rgba(C.text), value)
  return nt, reset
end

-- vertical value bar (Output gain): fill from the 0 dB middle line
local function vbar(id, x, y, w, h, t)
  local _, hov, act = hit(id, x, y, w, h)
  local nt
  if reaper.ImGui_IsItemActivated(ctx) and not shift_down() then
    local _, my = reaper.ImGui_GetMousePos(ctx)
    nt = clamp((my - y) / h, 0, 1)
  elseif act then
    local _, dy = reaper.ImGui_GetMouseDelta(ctx)
    if dy ~= 0 then nt = clamp(t + dy / h * (shift_down() and 0.15 or 1), 0, 1) end
  end
  local reset = hov and reaper.ImGui_IsMouseDoubleClicked(ctx, 0)
  t = nt or t
  rect(x, y, x + w, y + h, rgba(C.well), 8)
  local mid = y + h / 2
  line(x + 1, mid, x + w - 1, mid, rgba(C.line))
  local fy = y + 1 + t * (h - 2)
  rect(x + 1, math.min(mid, fy), x + w - 1, math.max(mid, fy), rgba(C.accent, 0x3D))
  local ey = clamp(fy, y + 3, y + h - 3)
  rect(x + 6, ey - 1, x + w - 6, ey + 1, rgba(C.accent), 1)
  stroke(x, y, x + w, y + h, rgba((hov or act) and C.keyedge or C.line), 8, 1)
  return nt, reset
end

local function open_url(url)
  if reaper.CF_ShellExecute then reaper.CF_ShellExecute(url); return end
  if OS:find("Win") then os.execute('start "" "' .. url .. '"')
  elseif OS:find("OSX") or OS:find("mac") then os.execute('open "' .. url .. '"')
  else os.execute('xdg-open "' .. url .. '"') end
end

local function heart(x, y, col)
  reaper.ImGui_DrawList_AddCircleFilled(DL, x - 3, y - 1.5, 3.4, col, 12)
  reaper.ImGui_DrawList_AddCircleFilled(DL, x + 3, y - 1.5, 3.4, col, 12)
  reaper.ImGui_DrawList_AddTriangleFilled(DL, x - 6.3, y - 0.6, x + 6.3, y - 0.6, x, y + 6, col)
end

---------------------------------------------------------------- GUI parts

local PTS = reaper.new_array(NGRID * 2)
local BWMIN, BWMAX = 0.2, 4.0
local function bw_of(q) return 2 * asinh(1 / (2 * q)) / math.log(2) end
local function q_of(bw) local x = 2 ^ bw; return math.sqrt(x) / (x - 1) end

local function fmt_freq(f)
  if f >= 1000 then return string.format("%.2f", f / 1000), "kHz" end
  return string.format("%.0f", f), "Hz"
end

local function open_picker()
  PICK.focus = true
  reaper.ImGui_OpenPopup(ctx, "hp_pick")
end

local function draw_header(x, y, w)
  -- left: headphone name (click to search)
  text(FT.cap, x, y, rgba(C.dim), "HEADPHONES")
  local name = PICK.name or "Choose headphones"
  local nw, nh = tsize(FT.val, name)
  local clicked, hov = hit("##hp", x, y + 14, nw + 22, nh + 4)
  text(FT.val, x, y + 15, rgba(hov and 0xFFFFFF or C.text), name)
  local cx, cy = x + nw + 15, y + 15 + nh / 2
  reaper.ImGui_DrawList_AddCircle(DL, cx - 1, cy - 1, 4.2, rgba(hov and C.text or C.muted), 16, 1.6)
  line(cx + 2, cy + 2, cx + 5.5, cy + 5.5, rgba(hov and C.text or C.muted), 1.6)
  if clicked then open_picker() end

  -- right: Target and Source capsules
  local tname = S.target_header[S.target_col + 2] or "-"
  local tw = 12 + tsize(FT.body, "Target") + 7 + tsize(FT.body, tname) + 28
  local tx = x + w - tw
  if capsule("##target", tx, y + 6, "Target", tname) then reaper.ImGui_OpenPopup(ctx, "target_pick") end
  local list = PICK.name and ENTRIES[PICK.name]
  if list then
    local e = list[PICK.src + 1] or list[1]
    local sw = 12 + tsize(FT.body, "Source") + 7 + tsize(FT.body, e.source) + 28
    if capsule("##source", tx - 8 - sw, y + 6, "Source", e.source) then reaper.ImGui_OpenPopup(ctx, "source_pick") end
  end
end

local function draw_popups()
  -- headphone search: typing always goes to the search field; arrows move the highlight; Enter loads it
  reaper.ImGui_SetNextWindowSize(ctx, 380, 0, reaper.ImGui_Cond_Always())
  if reaper.ImGui_BeginPopup(ctx, "hp_pick", reaper.ImGui_WindowFlags_NoNav()) then
    local function key(k) return reaper.ImGui_IsKeyPressed(ctx, k, true) end
    local function choose(n)
      PICK.name, PICK.src = n, 0
      load_selection(ENTRIES[n][1], n)
      S.sel = 1
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    -- keep the search field focused, so typing searches at any time
    if PICK.focus or not reaper.ImGui_IsAnyItemActive(ctx) then
      reaper.ImGui_SetKeyboardFocusHere(ctx)
      if CARET_FN then reaper.ImGui_Function_SetValue(CARET_FN, "once", 1) end
      PICK.focus = false
    end
    reaper.ImGui_SetNextItemWidth(ctx, -1)
    local ch, txt
    if CARET_FN then
      ch, txt = reaper.ImGui_InputTextWithHint(ctx, "##q", "Search, e.g. m40x or hd 650", PICK.filter,
        reaper.ImGui_InputTextFlags_CallbackAlways(), CARET_FN)
    else
      ch, txt = reaper.ImGui_InputTextWithHint(ctx, "##q", "Search, e.g. m40x or hd 650", PICK.filter)
    end
    if ch then PICK.filter = txt end
    if PICK.last ~= PICK.filter or PICK.nlast ~= #ENTRY_NAMES then
      PICK.last, PICK.nlast = PICK.filter, #ENTRY_NAMES
      PICK.hits = find_matches(PICK.filter)
      PICK.idx = 1
      PICK.scroll = true
    end
    local n = #PICK.hits
    PICK.idx = math.max(1, math.min(PICK.idx or 1, math.max(1, n)))
    if key(reaper.ImGui_Key_DownArrow()) then PICK.idx = math.min(n, PICK.idx + 1); PICK.scroll = true end
    if key(reaper.ImGui_Key_UpArrow()) then PICK.idx = math.max(1, PICK.idx - 1); PICK.scroll = true end
    if key(reaper.ImGui_Key_PageDown()) then PICK.idx = math.min(n, PICK.idx + 10); PICK.scroll = true end
    if key(reaper.ImGui_Key_PageUp()) then PICK.idx = math.max(1, PICK.idx - 10); PICK.scroll = true end
    local enter = key(reaper.ImGui_Key_Enter()) or key(reaper.ImGui_Key_KeypadEnter())
    if key(reaper.ImGui_Key_Escape()) then reaper.ImGui_CloseCurrentPopup(ctx) end

    if #ENTRY_NAMES == 0 then
      if S.list_state == "fail" then
        reaper.ImGui_TextColored(ctx, rgba(C.amber), "Could not load the headphone list.")
        if reaper.ImGui_Button(ctx, "Retry") then init_site() end
      else
        reaper.ImGui_TextColored(ctx, rgba(C.muted), "Loading the headphone list...")
      end
    else
      if enter and PICK.hits[PICK.idx] then choose(PICK.hits[PICK.idx]) end
      if reaper.ImGui_BeginListBox(ctx, "##hl", -1, 280) then
        for i, nm in ipairs(PICK.hits) do
          if reaper.ImGui_Selectable(ctx, nm, i == PICK.idx) then choose(nm) end
          if i == PICK.idx and PICK.scroll then
            reaper.ImGui_SetScrollHereY(ctx, 0.5)
            PICK.scroll = false
          end
        end
        reaper.ImGui_EndListBox(ctx)
      end
    end
    local more = (#PICK.hits >= MAX_HITS) and " (type more to narrow)" or ""
    reaper.ImGui_TextColored(ctx, rgba(C.dim), #PICK.hits .. " matches  -  arrows to move, Enter to load" .. more)
    reaper.ImGui_EndPopup(ctx)
  end
  -- source
  if reaper.ImGui_BeginPopup(ctx, "source_pick") then
    local list = PICK.name and ENTRIES[PICK.name] or {}
    for i, e in ipairs(list) do
      local label = e.source .. "  (" .. (e.rig ~= "" and e.rig .. ", " or "") .. e.form .. ")"
      if reaper.ImGui_Selectable(ctx, label, i - 1 == PICK.src) then
        PICK.src = i - 1
        load_selection(e, PICK.name)
        S.sel = 1
      end
    end
    reaper.ImGui_EndPopup(ctx)
  end
  -- target
  if reaper.ImGui_BeginPopup(ctx, "target_pick") then
    for i = 2, #S.target_header do
      if reaper.ImGui_Selectable(ctx, S.target_header[i], i - 2 == S.target_col) then
        S.target_col = i - 2
        rebuild_target()
        edit()
      end
    end
    reaper.ImGui_EndPopup(ctx)
  end
  -- right-click menu on the graph: local files
  if reaper.ImGui_BeginPopup(ctx, "graph_menu") then
    if reaper.ImGui_Selectable(ctx, "Load Measurement CSV...") then
      local ok, path = reaper.GetUserFileNameForRead("", "Open measurement CSV", ".csv")
      if ok then
        local m, err = load_meas(path)
        if m then S.meas = m; S.status = "Measurement loaded."; edit() else S.status = err end
      end
    end
    if reaper.ImGui_Selectable(ctx, "Load Target CSV...") then
      local ok, path = reaper.GetUserFileNameForRead("", "Open target CSV", ".csv")
      if ok then
        local header, rows = load_target(path)
        if header then
          S.target_header, S.target_rows, S.target_col = header, rows, 0
          rebuild_target(); S.status = "Target loaded."; edit()
        else
          S.status = rows
        end
      end
    end
    if reaper.ImGui_Selectable(ctx, "Load EQ File (ParametricEQ.txt)...") then
      local ok, path = reaper.GetUserFileNameForRead("", "Open ParametricEQ.txt", ".txt")
      if ok then
        local done, msg = load_peq(path)
        S.status = msg
        if done then S.sel = 1; edit() end
      end
    end
    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_Selectable(ctx, "Save EQ as Text...") then
      local ok, name = reaper.GetUserInputs("Save EQ", 1, "Name", PICK.name or "headphone")
      if ok and trim(name) ~= "" then S.status = save_preset(trim(name)) end
    end
    reaper.ImGui_EndPopup(ctx)
  end
end

local function draw_graph(x, y, w, h)
  local lfmin, lfmax = math.log(FMIN), math.log(FMAX)
  local function X(f) return x + (math.log(f) - lfmin) / (lfmax - lfmin) * w end
  local function Y(d) return y + (DBMAX - d) / (DBMAX - DBMIN) * h end

  local _, hov, act = hit("##graph", x, y, w, h)
  rect(x, y, x + w, y + h, rgba(C.well), 10)
  reaper.ImGui_DrawList_PushClipRect(DL, x + 1, y + 1, x + w - 1, y + h - 1, true)

  for _, f in ipairs({ 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000 }) do
    line(X(f), y, X(f), y + h, rgba(C.grid))
    text(FT.body, X(f) + 4, y + h - 20, rgba(C.dim), f >= 1000 and (f // 1000 .. "k") or tostring(f))
  end
  for d = -10, 10, 5 do
    line(x, Y(d), x + w, Y(d), rgba(d == 0 and C.zero or C.grid))
    if d ~= 0 then text(FT.body, x + 8, Y(d) - 17, rgba(C.dim), (d > 0 and "+" or "") .. d) end
  end
  -- suggestion range strip
  rect(X(SUGGEST_MIN_F), y + h - 3, X(SUGGEST_MAX_F), y + h, rgba(C.accent, 0x59))

  local mx, my = reaper.ImGui_GetMousePos(ctx)
  if S.res.ready then
    local raw, targ, res = S.res.raw, S.res.targ, S.res.eq
    -- EQ only (result minus headphone minus gain): soft fill to 0 dB like ReaEQ, 1 px columns (no seams)
    local y0 = Y(0)
    local px, pe
    for i = 1, NGRID do
      local ex = X(GRID[i])
      local ey = Y(clamp(res[i] - raw[i] - S.gain, DBMIN - 2, DBMAX + 2))
      if px then
        for cx = math.floor(px), math.floor(ex) - 1 do
          local cy = pe + (ey - pe) * (cx - px) / math.max(0.001, ex - px)
          if math.abs(cy - y0) >= 0.5 then
            rect(cx, math.min(cy, y0), cx + 1, math.max(cy, y0), rgba(C.accent, 0x14))
          end
        end
      end
      PTS[2 * i - 1], PTS[2 * i] = ex, ey
      px, pe = ex, ey
    end
    reaper.ImGui_DrawList_AddPolyline(DL, PTS, rgba(C.accent, 0x59), 0, 1)
    local function curve(vals, col, th)
      for i = 1, NGRID do
        PTS[2 * i - 1], PTS[2 * i] = X(GRID[i]), Y(clamp(vals[i], DBMIN - 2, DBMAX + 2))
      end
      reaper.ImGui_DrawList_AddPolyline(DL, PTS, col, 0, th)
    end
    curve(raw, rgba(C.dim), 1.2)
    curve(targ, rgba(C.text), 1.6)
    curve(res, rgba(C.accent), 2.4)

  elseif #S.bands == 0 then
    local msg = (#ENTRY_NAMES > 0) and "Click the headphone name above to choose your headphones."
      or (S.list_state == "fail" and "Could not load the headphone list. Click the headphone name above to retry."
      or "Loading the headphone list...")
    local tw, th = tsize(FT.body, msg)
    text(FT.body, x + (w - tw) / 2, y + (h - th) / 2, rgba(C.muted), msg)
  end

  -- nodes
  local near, nd = nil, 14
  for i, b in ipairs(S.bands) do
    local d = math.sqrt((X(b.f) - mx) ^ 2 + (Y(b.g) - my) ^ 2)
    if d < nd then near, nd = i, d end
  end
  for i, b in ipairs(S.bands) do
    local bx, by = X(b.f), Y(clamp(b.g, DBMIN, DBMAX))
    local selb = (i == S.sel)
    if selb then reaper.ImGui_DrawList_AddCircleFilled(DL, bx, by, 14, rgba(C.accent, 0x29), 24) end
    local fill = b.on and (selb and C.accent or C.key) or 0x1B1B20
    local edge = b.on and (selb and C.accent_hi or C.accent) or C.keyedge
    reaper.ImGui_DrawList_AddCircleFilled(DL, bx, by, 9.5, rgba(fill), 24)
    reaper.ImGui_DrawList_AddCircle(DL, bx, by, 9.5, rgba((near == i and not selb) and C.accent_hi or edge), 24, 1.5)
    local nw, nh = tsize(FT.cap, tostring(i))
    text(FT.cap, bx - nw / 2, by - nh / 2, rgba(b.on and 0xFFFFFF or C.muted), tostring(i))
  end

  -- interaction: drag a node (frequency, gain), wheel over a node (bandwidth)
  -- press on a node: Alt/Option-click removes it, double-click turns it on/off, else drag it
  if reaper.ImGui_IsItemActivated(ctx) then
    S.drag = nil
    if near then
      local alt = (reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Alt()) ~= 0
      if alt then
        table.remove(S.bands, near)
        S.sel = math.max(1, math.min(S.sel, #S.bands))
        edit()
      elseif reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
        S.bands[near].on = not S.bands[near].on
        S.sel = near
        edit()
      else
        S.drag = near
        S.sel = near
      end
    elseif reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
      -- double-click on empty graph: new band at that frequency and gain
      if #S.bands < MAXBANDS then
        local nf = math.exp(lfmin + clamp((mx - x) / w, 0, 1) * (lfmax - lfmin))
        local ng = clamp(DBMAX - (my - y) / h * (DBMAX - DBMIN), -12, 12)
        S.bands[#S.bands + 1] = { on = true, t = "PK", f = nf, g = math.floor(ng * 10 + 0.5) / 10, q = 1 }
        S.sel = #S.bands
        S.drag = S.sel
        edit()
      else
        S.status = "ReaEQ uses at most " .. MAXBANDS .. " bands here. Remove one first."
      end
    end
  end
  if act and S.drag and S.bands[S.drag] then
    local b = S.bands[S.drag]
    local nf = math.exp(lfmin + clamp((mx - x) / w, 0, 1) * (lfmax - lfmin))
    local ng = clamp(DBMAX - (my - y) / h * (DBMAX - DBMIN), -12, 12)
    if math.abs(nf - b.f) > 0.01 or math.abs(ng - b.g) > 0.001 then
      b.f, b.g = nf, math.floor(ng * 10 + 0.5) / 10
      edit()
    end
  end
  if not act then S.drag = nil end
  if hov and near then
    local wheel = reaper.ImGui_GetMouseWheel(ctx)
    if wheel ~= 0 then
      local b = S.bands[near]
      b.q = q_of(clamp(bw_of(b.q) * (wheel < 0 and 0.926 or 1.08), BWMIN, BWMAX))
      S.sel = near
      edit()
    end
  end

  -- legend and gap readout
  local lx = x + 44
  for _, it in ipairs({ { "Headphone", C.dim }, { "Target", C.text }, { "With EQ", C.accent } }) do
    rect(lx, y + 18, lx + 14, y + 20, rgba(it[2]), 1)
    text(FT.body, lx + 20, y + 11, rgba(C.muted), it[1])
    lx = lx + 20 + tsize(FT.body, it[1]) + 16
  end
  if S.rms then
    local v = string.format("%.2f", S.rms)
    local uw = tsize(FT.cap, "dB")
    local vw = tsize(FT.big, v)
    local kw = tsize(FT.cap, "GAP")
    text(FT.cap, x + w - 14 - kw, y + 10, rgba(C.dim), "GAP")
    text(FT.big, x + w - 14 - uw - 4 - vw, y + 24, rgba(C.text), v)
    text(FT.cap, x + w - 14 - uw, y + 36, rgba(C.muted), "dB")
  end

  reaper.ImGui_DrawList_PopClipRect(DL)
  stroke(x, y, x + w, y + h, rgba(C.line), 10, 1)

  if hov and reaper.ImGui_IsMouseClicked(ctx, 1) then reaper.ImGui_OpenPopup(ctx, "graph_menu") end
end

local function draw_bandcard(x, y, w, h)
  rect(x, y, x + w, y + h, rgba(C.card), 10)
  stroke(x, y, x + w, y + h, rgba(C.line), 10, 1)
  local px, py = x + 14, y + 12
  S.sel = clamp(S.sel, 1, math.max(1, #S.bands))
  local b = S.bands[S.sel]

  -- band tabs
  local tx = px
  for i, bd in ipairs(S.bands) do
    local lbl = tostring(i)
    local tw = math.max(28, tsize(FT.cap, lbl) + 16)
    local clicked, hov = hit("##tab" .. i, tx, py, tw, 26)
    local on = (i == S.sel)
    rect(tx, py, tx + tw, py + 26, rgba(on and C.accent or (hov and 0x36363F or C.key), bd.on and 0xFF or 0x80), 7)
    stroke(tx, py, tx + tw, py + 26, rgba(on and 0x7AB0F5 or C.keyedge, bd.on and 0xFF or 0x80), 7, 1)
    local lw = tsize(FT.cap, lbl)
    vtext(FT.cap, tx + (tw - lw) / 2, py, 26, rgba(on and 0xFFFFFF or C.muted, bd.on and 0xFF or 0x80), lbl)
    if clicked then S.sel = i end
    tx = tx + tw + (#S.bands > 6 and 4 or 6)
  end
  if #S.bands < MAXBANDS then
    local clicked, hov = hit("##add", tx, py, 28, 26)
    rect(tx, py, tx + 28, py + 26, rgba(hov and 0x36363F or C.key), 7)
    stroke(tx, py, tx + 28, py + 26, rgba(C.keyedge), 7, 1)
    line(tx + 9, py + 13, tx + 19, py + 13, rgba(C.muted), 1.5)
    line(tx + 14, py + 8, tx + 14, py + 18, rgba(C.muted), 1.5)
    if clicked then
      S.bands[#S.bands + 1] = { on = true, t = "PK", f = 1000, g = 0, q = 1 }
      S.sel = #S.bands
      edit()
    end
  end

  -- right side: On switch, type segments, delete
  local rx = x + w - 14
  -- delete icon
  local dclicked, dhov = hit("##del", rx - 28, py - 1, 28, 28)
  if dhov then rect(rx - 28, py - 1, rx, py + 27, rgba(0x787880, 0x2E), 7) end
  local ic = rgba((dhov and b) and C.text or C.muted, b and 0xFF or 0x60)
  local cx, cy = rx - 14, py + 13
  line(cx - 5, cy - 4, cx + 5, cy - 4, ic, 1.4)
  line(cx - 2, cy - 6, cx + 2, cy - 6, ic, 1.4)
  line(cx - 4, cy - 3, cx - 3, cy + 6, ic, 1.4)
  line(cx + 4, cy - 3, cx + 3, cy + 6, ic, 1.4)
  line(cx - 3, cy + 6, cx + 3, cy + 6, ic, 1.4)
  if dclicked and b then
    table.remove(S.bands, S.sel)
    S.sel = math.max(1, S.sel - 1)
    edit()
    b = S.bands[S.sel]
  end
  rx = rx - 28 - 10

  local segs = { { "LSC", "Low Shelf" }, { "PK", "Band" }, { "HSC", "High Shelf" } }
  local segw = 4
  for _, sg in ipairs(segs) do segw = segw + tsize(FT.body, sg[2]) + 20 end
  local sx = rx - segw
  rect(sx, py - 1, rx, py + 27, rgba(C.well), 8)
  stroke(sx, py - 1, rx, py + 27, rgba(C.line), 8, 1)
  local cxs = sx + 2
  for _, sg in ipairs(segs) do
    local sw = tsize(FT.body, sg[2]) + 20
    local clicked, hov = hit("##seg" .. sg[1], cxs, py + 1, sw, 24)
    local on = b and b.t == sg[1]
    if on then
      rect(cxs, py + 1, cxs + sw, py + 25, rgba(C.key), 6)
      stroke(cxs, py + 1, cxs + sw, py + 25, rgba(C.keyedge), 6, 1)
    end
    vtext(FT.body, cxs + 10, py + 1, 24, rgba((on or hov) and C.text or C.muted, b and 0xFF or 0x60), sg[2])
    if clicked and b and b.t ~= sg[1] then b.t = sg[1]; edit() end
    cxs = cxs + sw
  end
  local onw = 28 + 7 + tsize(FT.body, "On")
  local oclicked = switch("##on", sx - 12 - onw, py - 1, b and b.on or false, "On")
  if oclicked and b then b.on = not b.on; edit() end

  -- value bars
  local by = py + 26 + 10
  local bh = 44
  local gap = 10
  local bw = (w - 28 - 2 * gap) / 3
  if b then
    local fv, fu = fmt_freq(b.f)
    local nt, rs = hbar("##bf", px, by, bw, bh, math.log(b.f / 20) / math.log(1000), false, "FREQUENCY", fv, fu,
      { 0.10, 0.23, 0.33, 0.47, 0.57, 0.67, 0.80, 0.90 })
    if nt then b.f = 20 * 1000 ^ nt; edit() end
    nt, rs = hbar("##bg", px + bw + gap, by, bw, bh, (b.g + 12) / 24, true, "GAIN",
      string.format("%+.1f", b.g), "dB")
    if nt then b.g = math.floor((nt * 24 - 12) * 10 + 0.5) / 10; edit() end
    if rs then b.g = 0; edit() end
    local bwv = bw_of(b.q)
    nt, rs = hbar("##bb", px + 2 * (bw + gap), by, bw, bh, (bwv - BWMIN) / (BWMAX - BWMIN), false, "BANDWIDTH",
      string.format("%.2f", bwv), "oct")
    if nt then b.q = q_of(BWMIN + nt * (BWMAX - BWMIN)); edit() end
    if rs then b.q = q_of(1); edit() end
  else
    for k = 0, 2 do rect(px + k * (bw + gap), by, px + k * (bw + gap) + bw, by + bh, rgba(C.well, 0x80), 8) end
    local msg = "No bands. Press + to add one, or Suggest."
    local mw = tsize(FT.body, msg)
    vtext(FT.body, x + (w - mw) / 2, by, bh, rgba(C.muted), msg)
  end
end

local function draw_output(x, y, w, h)
  rect(x, y, x + w, y + h, rgba(C.card), 10)
  stroke(x, y, x + w, y + h, rgba(C.line), 10, 1)
  local kw = tsize(FT.cap, "OUTPUT")
  text(FT.cap, x + (w - kw) / 2, y + 12, rgba(C.muted), "OUTPUT")
  local v = string.format("%+.1f", S.gain)
  local vw = tsize(FT.val, v)
  local uw = tsize(FT.cap, "dB")
  local vx = x + (w - vw - 3 - uw) / 2
  text(FT.val, vx, y + 28, rgba(C.text), v)
  text(FT.cap, vx + vw + 3, y + 33, rgba(C.muted), "dB")
  local barw = 48
  local top, bottom = y + 56, y + h - 14
  local nt, rs = vbar("##out", x + (w - barw) / 2, top, barw, bottom - top, (12 - S.gain) / 24)
  if nt then
    S.gain = math.floor((12 - nt * 24) * 10 + 0.5) / 10
    edit()
  end
  if rs then S.gain = 0; edit() end -- double-click: 0 dB
end

local function draw_footer(x, y, w)
  local cx = x
  local c, bw = button("##suggest", cx, y, "Suggest", false)
  if c then apply_suggestion(); S.sel = 1 end
  cx = cx + bw + 8
  cx = cx + 6
  local sw
  c, sw = switch("##autopush", cx, y, S.auto, "Push automatically")
  if c then
    S.auto = not S.auto
    -- when sync comes back on, take a fresh reading of ReaEQ first; nothing changed while off is imported
    if S.auto then S.sync_key = nil end
  end
  cx = cx + sw + 12
  if not S.auto then
    c, bw = button("##push", cx, y, "Push to ReaEQ", true)
    if c then apply_reaeq(); S.push = false end
    cx = cx + bw + 12
  end

  -- heart (Ko-fi), right edge
  local hx = x + w - 10
  local hc, hh = hit("##kofi", hx - 10, y + 4, 20, 20)
  heart(hx, y + 14, rgba(hh and C.heart or C.dim))
  if hh then reaper.ImGui_SetTooltip(ctx, "Support (Ko-fi)") end
  if hc then open_url("https://ko-fi.com/danielkharrat") end

  -- status pill
  local st = S.status or ""
  local ok = (st:find("^Wrote") and not st:find("Problem")) or st:find("^Changes from ReaEQ") or st:find("^Added ")
  local warn = st:find("Problem") or st:find("Could not") or st:find("^No ") or st:find("Select a track")
  local label = ok and (st:match("^Wrote (%d+)") and (st:match("^Wrote (%d+)") .. " band(s) on ReaEQ - in sync")
    or (st:find("^Added ") and ("Added " .. eq_name() .. " to Monitoring FX"))
    or "In sync - taken from ReaEQ") or st
  local maxw = (hx - 20) - cx
  local lw = tsize(FT.body, label)
  while lw > maxw - 30 and #label > 8 do
    label = label:sub(1, #label - 4) .. "..."
    lw = tsize(FT.body, label)
  end
  local pw = lw + (ok and 30 or 22)
  local pxr = hx - 20
  local pxl = pxr - pw
  local tint = ok and C.green or (warn and C.amber or C.muted)
  rect(pxl, y + 1, pxr, y + 27, rgba(tint, 0x1F), 13)
  local tx = pxl + 11
  if ok then
    reaper.ImGui_DrawList_AddCircleFilled(DL, pxl + 14, y + 14, 3.5, rgba(C.green), 12)
    tx = pxl + 23
  end
  vtext(FT.body, tx, y + 1, 26, rgba(ok and C.green_t or (warn and C.amber or C.muted)), label)
end

local function draw_all()
  if not SITE_READY then
    SITE_READY = true
    init_site()
    load_existing_eq()
  end
  poll_jobs()
  if S.dirty then
    refresh()
    S.dirty = false
  end
  DL = reaper.ImGui_GetWindowDrawList(ctx)
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
  local w, h = reaper.ImGui_GetContentRegionAvail(ctx)

  local HEAD, FOOT, CARD, OUTW, GAP = 40, 28, 104, 96, 12
  draw_header(x, y, w)
  local top = y + HEAD + 10
  local fy = y + h - FOOT
  local cardy = fy - GAP - CARD
  local mainw = w - OUTW - GAP
  draw_graph(x, top, mainw, cardy - GAP - top)
  draw_bandcard(x, cardy, mainw, CARD)
  draw_output(x + mainw + GAP, top, OUTW, cardy + CARD - top)
  draw_footer(x, fy, w)

  -- typing anywhere in the window starts a headphone search
  if reaper.ImGui_IsWindowFocused(ctx) and not reaper.ImGui_IsAnyItemActive(ctx)
    and not reaper.ImGui_IsPopupOpen(ctx, "", reaper.ImGui_PopupFlags_AnyPopupId()) then
    local mods = reaper.ImGui_GetKeyMods(ctx)
    if (mods & (reaper.ImGui_Mod_Ctrl() | reaper.ImGui_Mod_Super())) == 0 then
      local typed, i = {}, 0
      while true do
        local ok, c = reaper.ImGui_GetInputQueueCharacter(ctx, i)
        if not ok then break end
        if c and c >= 32 and c ~= 127 then typed[#typed + 1] = utf8.char(c) end
        i = i + 1
      end
      if #typed > 0 then
        PICK.filter = table.concat(typed)
        open_picker()
      end
    end
  end

  draw_popups()

  if S.push and S.auto and reaper.time_precise() - S.last_push > 0.05 then
    apply_reaeq()
    S.last_push = reaper.time_precise()
    S.push = false
  end

  local now = reaper.time_precise()
  -- ReaEQ -> script, a few times per second, never while you edit in the script
  -- sync both ways only while "Push automatically" is on
  if S.auto and now - (S.last_poll or 0) > 0.15 and not S.push and not reaper.ImGui_IsAnyItemActive(ctx) then
    S.last_poll = now
    poll_reaeq()
  end
end

local STYLE_COLORS = {
  { "WindowBg", C.bg }, { "TitleBg", C.bg }, { "TitleBgActive", C.bg }, { "TitleBgCollapsed", C.bg },
  { "PopupBg", C.card }, { "Border", C.line }, { "FrameBg", C.well }, { "FrameBgHovered", 0x1A1A1F },
  { "FrameBgActive", 0x1A1A1F }, { "Header", C.accent, 0x55 }, { "HeaderHovered", C.accent, 0x33 },
  { "HeaderActive", C.accent, 0x77 }, { "Text", C.text }, { "TextDisabled", C.dim }, { "Separator", C.line },
  { "ScrollbarBg", C.well }, { "ScrollbarGrab", C.key }, { "ScrollbarGrabHovered", C.keyedge },
  { "ScrollbarGrabActive", C.keyedge }, { "NavHighlight", C.accent },
}

local MIN_W, MIN_H = 840, 520

local function loop()
  -- first start at the minimum size; after that ReaImGui remembers the size the user gives it
  reaper.ImGui_SetNextWindowSize(ctx, MIN_W, MIN_H, reaper.ImGui_Cond_FirstUseEver())
  reaper.ImGui_SetNextWindowSizeConstraints(ctx, MIN_W, MIN_H, 10000, 10000)
  local pushed = 0
  for _, sc in ipairs(STYLE_COLORS) do
    local fn = reaper["ImGui_Col_" .. sc[1]]
    if fn then
      reaper.ImGui_PushStyleColor(ctx, fn(), rgba(sc[2], sc[3]))
      pushed = pushed + 1
    end
  end
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 16, 12)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupRounding(), 10)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 7)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 10)
  push(FT.body)
  local flags = reaper.ImGui_WindowFlags_NoScrollbar() | reaper.ImGui_WindowFlags_NoScrollWithMouse()
    | reaper.ImGui_WindowFlags_NoCollapse()
  local vis, open = reaper.ImGui_Begin(ctx, "AutoEQ Integration", true, flags)
  if vis then
    draw_all()
    reaper.ImGui_End(ctx)
  end
  pop()
  reaper.ImGui_PopStyleVar(ctx, 4)
  reaper.ImGui_PopStyleColor(ctx, pushed)
  if open then reaper.defer(loop) end
end

loop()
