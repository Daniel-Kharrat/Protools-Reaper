--[[
  Transcript to Markers
  ----------------------
  Reads an episode script (.doc, .docx, or .txt) and inserts a project
  marker, named after the speaker, at each point the speaker changes.
  If the same person speaks several times in a row, only one marker is
  added, at the first occurrence.

  PARSING: works on the whole document as one continuous block of text
  (no reliance on line breaks or separators). It scans for every
  "(timestamp)" occurrence, e.g. "(0:19)", then walks backward from
  each one, word by word, to find the speaker name. A word counts as
  part of the name if it's Title-Case (not ALL CAPS -- that's reserved
  for section headings), a known title abbreviation ending in a period
  (Dr., Pr., ... see TITLE_ABBREVIATIONS), or a bare number immediately
  before the timestamp (Man 1, Man 2). Anything else stops the walk,
  which is what lets it split something like "...SHOW TITLE 2024
  Dr. Smith (0:19)" into the heading and the real name "Dr. Smith".

  SPEAKER-LINE FORMAT: Name (timestamp) [optional : or dash] dialogue

  WORD DOCUMENT SUPPORT: .docx is read natively with a pure-Lua ZIP +
  DEFLATE reader built into this file -- nothing to install, works the
  same on Windows/Mac/Linux. .doc (old binary format) only auto-
  converts on macOS via the built-in 'textutil'; elsewhere, save it as
  .docx or .txt first.

  Timestamps are treated as seconds from project start. If your audio
  doesn't start at 0:00 in the timeline, set OFFSET_SECONDS below.
--]]

local OFFSET_SECONDS = 0.0
local DEDUPE_CONSECUTIVE_SPEAKERS = true  -- true = only mark when the speaker changes from the previous one
local INCLUDE_UNNAMED_TIMESTAMPS = false  -- true = also mark timestamps where no name could be determined, as "Note"

local MARKER_COLOR_R = 245
local MARKER_COLOR_G = 195
local MARKER_COLOR_B = 72

-- Title abbreviations that count as part of a name (Dr., Pr., ...).
local TITLE_ABBREVIATIONS = {
  DR = true, PR = true, MR = true, MRS = true, MS = true, ST = true,
  FR = true, JR = true, SR = true, REV = true, PROF = true,
  PASTOR = true, CAPT = true,
}

-- Names that get matched but aren't real speakers (production labels
-- etc). Skipped entirely -- no marker, doesn't break the dedup.
local EXCLUDED_SPEAKER_NAMES = {
  "Vozerio",
}

-- Set to true to only mark turns inside segments matching the keywords
-- below (segments are detected via a run of 10+ underscores followed
-- by the segment name). Leave false if your scripts don't use that.
local ONLY_WANTED_SECTIONS = false
local WANTED_SECTION_KEYWORDS = {
  "DRAMA",
  "OPEN YOUR HEART",
  "TESTIMON",              -- covers TESTIMONY and TESTIMONIES
  "QUESTIONS AND ANSWERS",
  "Q&A",
  "Q & A",
}

-- ---------------------------------------------------------------------
-- Pure-Lua .docx reader: parses the ZIP container and inflates the
-- DEFLATE-compressed word/document.xml entry, no external tools.
-- ---------------------------------------------------------------------

local Docx = {}

do
  -- raw DEFLATE (RFC 1951) decompressor

  local function new_bitreader(data)
    return { data = data, pos = 1, buf = 0, bitcnt = 0, len = #data }
  end

  local function getbits(br, n)
    while br.bitcnt < n do
      local b = br.pos <= br.len and string.byte(br.data, br.pos) or 0
      br.pos = br.pos + 1
      br.buf = br.buf | (b << br.bitcnt)
      br.bitcnt = br.bitcnt + 8
    end
    local v = br.buf & ((1 << n) - 1)
    br.buf = br.buf >> n
    br.bitcnt = br.bitcnt - n
    return v
  end

  local function align_byte(br)
    br.buf = 0
    br.bitcnt = 0
  end

  local function build_huffman(lengths)
    local max_len = 0
    for _, l in ipairs(lengths) do
      if l > max_len then max_len = l end
    end
    local bl_count = {}
    for i = 0, max_len do bl_count[i] = 0 end
    for _, l in ipairs(lengths) do
      if l > 0 then bl_count[l] = bl_count[l] + 1 end
    end
    local code = 0
    local next_code = {}
    for bits = 1, max_len do
      code = (code + (bl_count[bits - 1] or 0)) << 1
      next_code[bits] = code
    end
    local map = {}
    for sym = 0, #lengths do
      local l = lengths[sym + 1]
      if l and l > 0 then
        map[(l << 16) | next_code[l]] = sym
        next_code[l] = next_code[l] + 1
      end
    end
    return { map = map, max_len = max_len }
  end

  local function decode_symbol(br, huff)
    local code = 0
    for l = 1, huff.max_len do
      code = (code << 1) | getbits(br, 1)
      local sym = huff.map[(l << 16) | code]
      if sym then return sym end
    end
    error("bad huffman code in deflate stream")
  end

  local LENGTH_BASE = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
  local LENGTH_EXTRA = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
  local DIST_BASE = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
  local DIST_EXTRA = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
  local CL_ORDER = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}

  local FIXED_LIT_HUFF, FIXED_DIST_HUFF

  local function get_fixed_lit_huff()
    if not FIXED_LIT_HUFF then
      local l = {}
      for i = 0, 143 do l[i + 1] = 8 end
      for i = 144, 255 do l[i + 1] = 9 end
      for i = 256, 279 do l[i + 1] = 7 end
      for i = 280, 287 do l[i + 1] = 8 end
      FIXED_LIT_HUFF = build_huffman(l)
    end
    return FIXED_LIT_HUFF
  end

  local function get_fixed_dist_huff()
    if not FIXED_DIST_HUFF then
      local l = {}
      for i = 1, 30 do l[i] = 5 end
      FIXED_DIST_HUFF = build_huffman(l)
    end
    return FIXED_DIST_HUFF
  end

  local function inflate(data)
    local br = new_bitreader(data)
    local out = {}
    local outlen = 0

    while true do
      local final = getbits(br, 1)
      local btype = getbits(br, 2)

      if btype == 0 then
        align_byte(br)
        local lo = string.byte(br.data, br.pos)
        local hi = string.byte(br.data, br.pos + 1)
        local length = lo | (hi << 8)
        br.pos = br.pos + 4
        for i = 0, length - 1 do
          outlen = outlen + 1
          out[outlen] = string.byte(br.data, br.pos + i)
        end
        br.pos = br.pos + length

      elseif btype == 1 or btype == 2 then
        local lit_huff, dist_huff
        if btype == 1 then
          lit_huff = get_fixed_lit_huff()
          dist_huff = get_fixed_dist_huff()
        else
          local hlit = getbits(br, 5) + 257
          local hdist = getbits(br, 5) + 1
          local hclen = getbits(br, 4) + 4
          local cl_lengths = {}
          for i = 0, 18 do cl_lengths[i + 1] = 0 end
          for i = 0, hclen - 1 do
            cl_lengths[CL_ORDER[i + 1] + 1] = getbits(br, 3)
          end
          local cl_huff = build_huffman(cl_lengths)

          local all_lengths = {}
          local n = 0
          while n < hlit + hdist do
            local sym = decode_symbol(br, cl_huff)
            if sym < 16 then
              n = n + 1
              all_lengths[n] = sym
            elseif sym == 16 then
              local rep = getbits(br, 2) + 3
              local prev = all_lengths[n]
              for _ = 1, rep do n = n + 1; all_lengths[n] = prev end
            elseif sym == 17 then
              local rep = getbits(br, 3) + 3
              for _ = 1, rep do n = n + 1; all_lengths[n] = 0 end
            else
              local rep = getbits(br, 7) + 11
              for _ = 1, rep do n = n + 1; all_lengths[n] = 0 end
            end
          end
          local lit_lengths, dist_lengths = {}, {}
          for i = 1, hlit do lit_lengths[i] = all_lengths[i] end
          for i = 1, hdist do dist_lengths[i] = all_lengths[hlit + i] end
          lit_huff = build_huffman(lit_lengths)
          dist_huff = build_huffman(dist_lengths)
        end

        while true do
          local sym = decode_symbol(br, lit_huff)
          if sym < 256 then
            outlen = outlen + 1
            out[outlen] = sym
          elseif sym == 256 then
            break
          else
            local idx = sym - 257 + 1
            local length = LENGTH_BASE[idx] + getbits(br, LENGTH_EXTRA[idx])
            local dsym = decode_symbol(br, dist_huff)
            local dist = DIST_BASE[dsym + 1] + getbits(br, DIST_EXTRA[dsym + 1])
            local start = outlen - dist
            for i = 1, length do
              outlen = outlen + 1
              out[outlen] = out[start + i]
            end
          end
        end
      else
        error("bad deflate block type")
      end

      if final == 1 then break end
    end

    -- string.char/table.unpack choke past ~8000 args; stitch in chunks
    local CHUNK = 4096
    local chunks = {}
    local ci = 0
    for i = 1, outlen, CHUNK do
      local j = math.min(i + CHUNK - 1, outlen)
      ci = ci + 1
      chunks[ci] = string.char(table.unpack(out, i, j))
    end
    return table.concat(chunks)
  end

  -- minimal ZIP central-directory reader

  local function find_eocd(data)
    local sig = "PK\5\6"
    local search_start = math.max(1, #data - 65557)
    local last, from = nil, search_start
    while true do
      local s = data:find(sig, from, true)
      if not s then break end
      last, from = s, s + 1
    end
    return last
  end

  local function read_central_directory(data)
    local eocd = find_eocd(data)
    if not eocd then return nil, "not a valid .docx file (no end-of-central-directory record found)" end
    local total_entries, cd_size, cd_offset = string.unpack("<I2I4I4", data, eocd + 10)
    local pos = cd_offset + 1
    local entries = {}
    for _ = 1, total_entries do
      local sig = data:sub(pos, pos + 3)
      if sig ~= "PK\1\2" then break end
      local ver_made, ver_need, flags, method = string.unpack("<I2I2I2I2", data, pos + 4)
      local comp_size, uncomp_size, name_len, extra_len, comment_len =
        string.unpack("<I4I4I2I2I2", data, pos + 20)
      local local_offset = string.unpack("<I4", data, pos + 42)
      local name = data:sub(pos + 46, pos + 46 + name_len - 1)
      entries[name] = {
        method = method, comp_size = comp_size,
        uncomp_size = uncomp_size, local_offset = local_offset,
      }
      pos = pos + 46 + name_len + extra_len + comment_len
    end
    return entries
  end

  local function get_entry_bytes(data, entry)
    local off = entry.local_offset + 1
    local name_len, extra_len = string.unpack("<I2I2", data, off + 4 + 22)
    local data_start = off + 30 + name_len + extra_len
    return data:sub(data_start, data_start + entry.comp_size - 1)
  end

  -- w:t-aware text reconstruction: Word splits a single word across
  -- multiple <w:t> runs with no space between them, so runs are
  -- concatenated directly, and a space is only inserted at paragraph/
  -- tab/line-break boundaries.

  local function decode_entities(s)
    s = s:gsub("&lt;", "<")
    s = s:gsub("&gt;", ">")
    s = s:gsub("&quot;", '"')
    s = s:gsub("&apos;", "'")
    s = s:gsub("&#(%d+);", function(n) return utf8.char(tonumber(n)) end)
    s = s:gsub("&#x(%x+);", function(n) return utf8.char(tonumber(n, 16)) end)
    s = s:gsub("&amp;", "&")
    return s
  end

  local function extract_text(xml)
    local out = {}
    local pos = 1
    local n = #xml
    while pos <= n do
      local ts, te, inner = xml:find("<w:t[^>]*>(.-)</w:t>", pos)
      local ps, pe = xml:find("</w:p>", pos, true)
      local bs, be = xml:find("<w:tab[^>]*/>", pos)
      local brs, bre = xml:find("<w:br[^>]*/>", pos)

      local best_s, kind = nil, nil
      for _, cand in ipairs({ {ts, "t"}, {ps, "p"}, {bs, "tab"}, {brs, "br"} }) do
        if cand[1] and (not best_s or cand[1] < best_s) then
          best_s, kind = cand[1], cand[2]
        end
      end
      if not best_s then break end

      if kind == "t" then
        table.insert(out, decode_entities(inner))
        pos = te + 1
      elseif kind == "p" then
        table.insert(out, " ")
        pos = pe + 1
      else
        table.insert(out, " ")
        pos = (kind == "tab" and be or bre) + 1
      end
    end
    return table.concat(out)
  end

  -- Reads a .docx file and returns its plain-text content, or nil+err.
  function Docx.to_text(file_path)
    local f, ferr = io.open(file_path, "rb")
    if not f then return nil, "couldn't open file: " .. tostring(ferr) end
    local data = f:read("*a")
    f:close()

    local entries, err = read_central_directory(data)
    if not entries then return nil, err end

    local entry = entries["word/document.xml"]
    if not entry then return nil, "this doesn't look like a Word .docx file (no word/document.xml inside)" end

    local raw = get_entry_bytes(data, entry)

    local xml
    if entry.method == 0 then
      xml = raw
    elseif entry.method == 8 then
      local ok
      ok, xml = pcall(inflate, raw)
      if not ok then return nil, "couldn't decompress the document (it may be corrupt): " .. tostring(xml) end
    else
      return nil, "unsupported compression method in this .docx (method " .. tostring(entry.method) .. ")"
    end

    if #xml ~= entry.uncomp_size then
      return nil, string.format(
        "decompressed size mismatch (got %d bytes, expected %d) -- the file may be corrupt",
        #xml, entry.uncomp_size)
    end

    return extract_text(xml)
  end
end

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------

local function timestamp_to_seconds(ts)
  local parts = {}
  for chunk in ts:gmatch("[^:]+") do
    table.insert(parts, chunk)
  end
  local h, m, s
  if #parts == 3 then
    h, m, s = tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3])
  elseif #parts == 2 then
    h, m, s = 0, tonumber(parts[1]), tonumber(parts[2])
  else
    return nil
  end
  if not (h and m and s) then return nil end
  return h * 3600 + m * 60 + s
end

local MARKER_COLOR = nil
local function get_marker_color()
  if not MARKER_COLOR then
    MARKER_COLOR = reaper.ColorToNative(MARKER_COLOR_R, MARKER_COLOR_G, MARKER_COLOR_B) | 0x1000000
  end
  return MARKER_COLOR
end

local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

-- Strip stray markdown bold markers / backslash escapes some converters leave behind
local function clean_text(text)
  text = text:gsub("%*%*", "")
  text = text:gsub("\\([%'\"_%[%]%.%-])", "%1")
  text = text:gsub("\\%.%.%.", "...")
  return text
end

local function matches_wanted_keyword(snippet)
  local upper = snippet:upper()
  for _, kw in ipairs(WANTED_SECTION_KEYWORDS) do
    if upper:find(kw, 1, true) then
      return true
    end
  end
  return false
end

local function is_excluded_speaker(name)
  local upper = name:upper()
  for _, excluded in ipairs(EXCLUDED_SPEAKER_NAMES) do
    if upper == excluded:upper() then
      return true
    end
  end
  return false
end

local function shell_quote(path)
  return '"' .. path:gsub('"', '\\"') .. '"'
end

-- reaper.GetOS() returns "OSX32"/"OSX64"/"macOS-arm64" on Mac.
local function is_mac()
  local os_str = reaper.GetOS() or ""
  return os_str:find("OSX") ~= nil or os_str:find("macOS") ~= nil or os_str:find("Mac") ~= nil
end

-- Convert an old binary .doc file via macOS's built-in 'textutil'
-- (Mac only -- no pure-Lua path for the old binary format).
local function convert_doc_via_textutil(file_path)
  if not is_mac() then
    return nil, "Old-format .doc files aren't supported on this OS.\n\n" ..
      "Please open it in Word (or LibreOffice/Google Docs) and use " ..
      "\"Save As\" to save it as .docx or .txt, then run this script " ..
      "again and select that file instead."
  end

  local base = file_path:match("^(.*)%.[%a%d]+$") or file_path
  local txt_path = base .. "_converted.txt"

  local cmd = "textutil -convert txt -output " .. shell_quote(txt_path) .. " " .. shell_quote(file_path)
  os.execute(cmd)

  local check = io.open(txt_path, "r")
  if not check then
    return nil, "Couldn't convert the Word document to text.\n\n" ..
      "Make sure the file isn't currently open in Word.\n\nCommand attempted:\n" .. cmd
  end
  check:close()
  return txt_path, nil
end

-- .docx -> pure-Lua reader (any OS). .doc -> textutil (macOS only).
-- .txt -> returned as-is. Returns txt_path, err.
local function get_text_path(file_path)
  local ext = file_path:match("%.([%a%d]+)$")
  ext = ext and ext:lower() or ""

  if ext == "txt" then
    return file_path, nil
  end

  if ext == "doc" then
    return convert_doc_via_textutil(file_path)
  end

  if ext ~= "docx" then
    return nil, "Please select a .doc, .docx, or .txt file."
  end

  local text, err = Docx.to_text(file_path)
  if not text then
    return nil, "Couldn't read the Word document:\n\n" .. tostring(err)
  end

  local base = file_path:match("^(.*)%.[%a%d]+$") or file_path
  local txt_path = base .. "_converted.txt"
  local out, werr = io.open(txt_path, "w")
  if not out then
    return nil, "Couldn't write converted text file: " .. tostring(werr)
  end
  out:write(text)
  out:close()

  return txt_path, nil
end

-- A "plain" name word: Title-Case, not ALL CAPS (that's headings/
-- labels, not names). \195 + \128-\191 covers UTF-8 accented letters
-- (á é í ó ú ñ ã õ ç, upper and lower) so accented names match too.
local function is_plain_name_word(tok)
  local ascii_start = tok:match("^%u[%a'%-\195\128-\191]*$")
  local accented_start = tok:match("^\195[\128-\158][%a'%-\195\128-\191]*$")
  if not (ascii_start or accented_start) then
    return false
  end
  local letters = tok:gsub("[^%a]", "")
  if #letters > 1 and letters == letters:upper() then
    return false  -- ALL-CAPS word -> heading/label, not a name
  end
  return true
end

local function is_title_abbreviation(tok)
  local word = tok:match("^(%u[%a]*)%.$")
  return word ~= nil and TITLE_ABBREVIATIONS[word:upper()] == true
end

-- Walks backward from just before a "(timestamp)" to find the speaker
-- name. Returns the name, or nil if nothing name-like was found.
local function extract_name_before(window)
  local tokens = {}
  for tok in window:gmatch("%S+") do
    table.insert(tokens, tok)
  end
  if #tokens == 0 then return nil end

  local name_tokens = {}
  local i = #tokens

  -- A bare number only counts if it's the token right before the
  -- timestamp (e.g. "1" in "Man 1") -- not further back, which is more
  -- likely an unrelated number (a year, a verse reference, etc).
  if tokens[i]:match("^%d+$") then
    table.insert(name_tokens, 1, tokens[i])
    i = i - 1
  end

  while i >= 1 do
    local tok = tokens[i]
    if is_plain_name_word(tok) or is_title_abbreviation(tok) then
      table.insert(name_tokens, 1, tok)
      i = i - 1
    else
      break
    end
  end

  if #name_tokens == 0 then return nil end

  -- Safety net: a real name is at most a few words.
  if #name_tokens > 4 then
    local trimmed = {}
    for j = #name_tokens - 3, #name_tokens do
      table.insert(trimmed, name_tokens[j])
    end
    name_tokens = trimmed
  end

  return table.concat(name_tokens, " ")
end

-- Finds every "(timestamp)" in the text and its speaker name. Returns
-- a list of {pos, seconds, speaker, has_name}, in document order.
local function find_matches(text)
  local out = {}
  local prev_end = 1
  local search_from = 1
  while true do
    local s, e, ts = text:find("%((%d+:%d+:?%d*)%)", search_from)
    if not s then break end
    local window = text:sub(prev_end, s - 1)
    local name = extract_name_before(window)
    local seconds = timestamp_to_seconds(ts)
    if seconds then
      if name then
        table.insert(out, { pos = s, seconds = seconds, speaker = name, has_name = true })
      elseif INCLUDE_UNNAMED_TIMESTAMPS then
        table.insert(out, { pos = s, seconds = seconds, speaker = "Note", has_name = false })
      end
    end
    prev_end = e + 1
    search_from = e + 1
  end
  return out
end

-- Segment dividers: runs of 10+ underscores, flagged by whether the
-- text right after matches a wanted-section keyword.
local function find_dividers(text)
  local out = {}
  local search_from = 1
  while true do
    local s, e = text:find("_________+", search_from)  -- 10+ underscores
    if not s then break end
    local snippet = text:sub(e + 1, e + 150)
    table.insert(out, { pos = e, wanted = matches_wanted_keyword(snippet) })
    search_from = e + 1
  end
  return out
end

-- ---------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------

local function main()
  -- Remember the last folder picked from, across REAPER sessions too.
  local last_path = reaper.GetExtState("TranscriptToMarkers", "last_path")

  local retval, file_path = reaper.GetUserFileNameForRead(last_path, "Select transcript (.doc, .docx, or .txt)", "")
  if not retval then return end

  reaper.SetExtState("TranscriptToMarkers", "last_path", file_path, true)

  local txt_path, err = get_text_path(file_path)
  if not txt_path then
    reaper.ShowMessageBox(err, "Conversion failed", 0)
    return
  end

  local f = io.open(txt_path, "r")
  if not f then
    reaper.ShowMessageBox("Could not open file:\n" .. txt_path, "Error", 0)
    return
  end
  local raw = f:read("*a")
  f:close()

  raw = clean_text(raw)
  -- Collapse all whitespace to single spaces, so parsing is
  -- independent of line breaks/paragraph structure entirely.
  local text = raw:gsub("%s+", " ")
  text = trim(text)

  local matches = find_matches(text)
  local dividers = find_dividers(text)  -- already in position order

  reaper.Undo_BeginBlock()

  local added = 0
  local last_speaker = nil
  local divider_idx = 1
  local in_wanted_section = false

  for _, m in ipairs(matches) do
    while divider_idx <= #dividers and dividers[divider_idx].pos <= m.pos do
      in_wanted_section = dividers[divider_idx].wanted
      divider_idx = divider_idx + 1
    end

    local should_consider = (not ONLY_WANTED_SECTIONS) or in_wanted_section

    if should_consider and not is_excluded_speaker(m.speaker) then
      local is_repeat = DEDUPE_CONSECUTIVE_SPEAKERS and (m.speaker == last_speaker)
      if not is_repeat then
        local pos = m.seconds + OFFSET_SECONDS
        reaper.AddProjectMarker2(0, false, pos, 0, m.speaker, -1, get_marker_color())
        added = added + 1
      end
      last_speaker = m.speaker
    end
  end

  reaper.Undo_EndBlock("Add markers from transcript", -1)
  reaper.UpdateArrange()

  local msg = string.format(
    "Found %d speaker tag(s) total, added %d marker(s) (consecutive repeats collapsed into one).",
    #matches, added)
  if txt_path ~= file_path then
    msg = msg .. "\n\nConverted text saved to:\n" .. txt_path
  end
  if #matches == 0 then
    msg = msg .. "\n\nNo speaker tags were found at all -- open the converted .txt file above and check it actually contains readable '(timestamp)' text with names before them, not garbled characters."
  end
  reaper.ShowMessageBox(msg, "Transcript to Markers", 0)
end

main()
