--[[
  Transcript to Markers
  ----------------------
  Reads an episode script (.doc, .docx, or .txt) and inserts a project
  marker, named after the speaker, at each point the speaker changes.

  KEY BEHAVIOR: if the same person speaks several times in a row
  (e.g. a repeated song/prayer where Pr. Jayme's name tag appears 20
  times back to back), only ONE marker is added, at the first
  occurrence. A new marker is only added when the speaker actually
  changes from whoever spoke last.

  HOW IT PARSES (no reliance on line breaks, blank lines, or any
  specific separator character at all):
  It scans the whole document as one continuous block of text for every
  "(timestamp)" occurrence -- e.g. "(0:19)" -- regardless of what comes
  right after it (a colon, a dash, an en dash, nothing at all -- real
  scripts turn out to be inconsistent about this). For each one, it
  looks at the text immediately before it and works BACKWARD, word by
  word, to figure out how much of that text is actually the speaker's
  name versus the end of the previous sentence or a section heading.

  A word counts as "part of the name" if it's:
    - a normal Title-Case word (Soares, Angela, Letícia, Gleceir) --
      but NOT if it's written in ALL CAPS (SOARES, SUARES) -- that
      pattern is reserved for section headings and production labels
      in these scripts (OPEN YOUR HEART, SOARES ANSWERS, VOZERIO), not
      real speaker names
    - a short, known title abbreviation ending in a period (Dr., Pr.,
      Mr., St., etc -- see TITLE_ABBREVIATIONS below)
    - a bare number, but ONLY when it's the very last word before the
      timestamp (Man 1, Man 2) -- not a number further back, which is
      far more likely to be an unrelated year or verse number
  Anything else (a lowercase word, an ALL-CAPS word, a word ending in a
  period that isn't a known abbreviation, punctuation) stops the walk
  right there. That's what lets it correctly split apart something like
  "...FAITH SHOW 1991 Dr. Soares (0:19)" into the show's own title (not
  part of any name) and the real name "Dr. Soares" -- without needing
  any blank line, paragraph break, or consistent punctuation to go on.

  SPEAKER-LINE FORMAT: Name (timestamp) [optional : or dash] dialogue

  WORD DOCUMENT SUPPORT: .docx files are read natively, with no
  external programs and nothing to install -- this script parses the
  .docx ZIP container and decompresses it using a pure-Lua DEFLATE
  implementation built into this file. This works identically on
  Windows, Mac, and Linux. Old binary .doc files are only auto-
  converted on macOS, via the built-in 'textutil' command (there's no
  pure-Lua path for that older, more complex format); on Windows/Linux,
  save a .doc as .docx or .txt first.

  USAGE:
    1. REAPER: Actions > Show action list > New action... > Load
       ReaScript, select this file.
    2. Run it, pick your transcript -- .doc, .docx, or .txt all work.
       .docx and .txt work directly on any OS with nothing to install;
       .doc auto-converts on macOS only (see above).
    3. It reports how many markers were added and shows a few sample
       matches, so you can check it read your document correctly.

  Timestamps are treated as seconds from project start. If your audio
  doesn't start at 0:00 in the timeline, set OFFSET_SECONDS below.
--]]

local OFFSET_SECONDS = 0.0
local DEDUPE_CONSECUTIVE_SPEAKERS = true  -- true = only mark when the speaker changes from the previous one
local SKIP_FIRST_SPEAKER = true  -- true = don't add a marker for the very first speaker tag in the episode (you already have that one in your template)
local INCLUDE_UNNAMED_TIMESTAMPS = false  -- true = also mark timestamps where no name could be determined, as "Note"

-- Every marker uses this single RGB color (all speakers alike).
local MARKER_COLOR_R = 245
local MARKER_COLOR_G = 195
local MARKER_COLOR_B = 72

-- Known title abbreviations that count as part of a name even though
-- they end in a period (Dr., Pr., St., ...). Add more here if a script
-- uses one that's missing -- e.g. add "PROF" for "Prof.".
local TITLE_ABBREVIATIONS = {
  DR = true, PR = true, MR = true, MRS = true, MS = true, ST = true,
  FR = true, JR = true, SR = true, REV = true, PROF = true,
  PASTOR = true, CAPT = true,
}

-- Names that get picked up by the pattern but AREN'T actually a
-- speaker (transcription/production labels etc). Treated as if that
-- turn doesn't exist at all -- no marker, and it doesn't break the
-- consecutive-speaker dedup on either side of it. Case-insensitive.
-- (Note: ALL-CAPS labels like "VOZERIO" are usually already excluded
-- automatically -- see the header comment above -- but you can still
-- list them here too, or add ones that aren't all-caps.)
local EXCLUDED_SPEAKER_NAMES = {
  "Vozerio",
}

-- Set to true to only mark turns inside segments matching the keywords
-- below (segments are detected via a run of 10+ underscores followed
-- by the segment name). Leave false if your scripts don't reliably use
-- that separator -- most don't.
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
-- Pure-Lua .docx reader (zero dependencies, works on any OS)
-- .docx is a ZIP file containing XML; this parses the ZIP container
-- and, since Word compresses its entries, includes a small pure-Lua
-- DEFLATE decompressor to unpack word/document.xml -- no unzip, no
-- textutil, no LibreOffice, nothing external at all.
-- ---------------------------------------------------------------------

local Docx = {}

do
  -- ---- raw DEFLATE (RFC 1951) decompressor -----------------------

  local function new_bitreader(data)
    return { data = data, pos = 1, buf = 0, bitcnt = 0, len = #data }
  end

  local function getbits(br, n)
    while br.bitcnt < n do
      local b
      if br.pos <= br.len then
        b = string.byte(br.data, br.pos)
      else
        b = 0
      end
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

  -- ---- minimal ZIP central-directory reader -----------------------

  local function find_eocd(data)
    local sig = "PK\5\6"
    local search_start = math.max(1, #data - 65557)
    local last = nil
    local from = search_start
    while true do
      local s = data:find(sig, from, true)
      if not s then break end
      last = s
      from = s + 1
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

  -- ---- w:t-aware text reconstruction --------------------------------
  -- Word constantly splits a single word across multiple <w:t> runs
  -- (spell-check, revisions), with NO space between them -- so we
  -- concatenate run contents directly and only insert a separating
  -- space at paragraph/tab/line-break boundaries. A blind
  -- "replace every tag with a space" would fracture names like
  -- "Soares" into "So ares".

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
          best_s = cand[1]
          kind = cand[2]
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

  -- Reads a .docx file from disk and returns its plain-text content
  -- (or nil, error-message).
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

    local xml, ierr
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

-- Fixed marker color, computed once (reaper.ColorToNative needs the
-- REAPER API to be loaded, so this happens inside main() instead of here).
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

-- Is REAPER running on a Mac? (textutil, used for auto-converting old
-- .doc files, only exists on macOS.) reaper.GetOS() returns strings
-- like "OSX32", "OSX64", "macOS-arm64" on Mac, and "Win32"/"Win64"/
-- "Other" elsewhere.
local function is_mac()
  local os_str = reaper.GetOS() or ""
  return os_str:find("OSX") ~= nil or os_str:find("macOS") ~= nil or os_str:find("Mac") ~= nil
end

-- Convert an old binary .doc file to text using macOS's built-in
-- 'textutil' command (Mac only -- there's no pure-Lua path for the
-- old binary format, unlike .docx). Returns txt_path, err.
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

-- .docx is read with the pure-Lua reader above (works identically on
-- every OS -- nothing external, no install). .doc (the old binary
-- format) goes through macOS's built-in 'textutil' when running on a
-- Mac, since that format needs a much heavier OLE/binary parser that
-- isn't worth writing from scratch -- on Windows/Linux it isn't
-- supported and the user is asked to save as .docx or .txt instead.
-- .txt is returned as-is. Returns txt_path, err (err is nil on success).
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

-- A "plain" name word: starts with an uppercase ASCII letter, followed
-- by letters/accented-letter-bytes/apostrophe/hyphen -- but rejected if
-- the whole word (letters only) is ALL CAPS and more than one letter
-- long, since that pattern is used for headings/labels in these
-- scripts (OPEN YOUR HEART, VOZERIO), not real names.
-- \195 + \128-\191 covers UTF-8 Latin-1 Supplement accented letters
-- (á é í ó ú ñ ã õ ç etc, upper and lower) -- deliberately NOT a blanket
-- \128-255 allowance, so smart quotes/dashes (different lead byte)
-- correctly break the match instead of being swallowed into a word.
-- The word's FIRST letter can be a plain ASCII uppercase letter (%u)
-- OR an accented uppercase one (Á É Í Ó Ú Ñ Ç etc -- byte 195 followed
-- by a second byte in 128-158, the uppercase half of that block) --
-- names like "Élida" need this, since %u alone only matches A-Z.
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

-- Given the text immediately preceding a "(timestamp)" tag, work
-- backward token by token to find just the speaker name portion.
-- Returns the name string, or nil if nothing name-like was found.
local function extract_name_before(window)
  local tokens = {}
  for tok in window:gmatch("%S+") do
    table.insert(tokens, tok)
  end
  if #tokens == 0 then return nil end

  local name_tokens = {}
  local i = #tokens

  -- A bare number only counts as part of the name if it's the token
  -- immediately before the timestamp (e.g. the "1" in "Man 1") -- not
  -- if it shows up further back, which is far more likely to be an
  -- unrelated number (a year, a verse reference, etc).
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

  -- Safety net: a real name/title is at most a few words. If we
  -- somehow walked back further than that, keep only the words
  -- closest to the timestamp.
  if #name_tokens > 4 then
    local trimmed = {}
    for j = #name_tokens - 3, #name_tokens do
      table.insert(trimmed, name_tokens[j])
    end
    name_tokens = trimmed
  end

  return table.concat(name_tokens, " ")
end

-- Scan the whole text for every "(timestamp)" occurrence and figure
-- out the speaker name before each one. Returns a list of
-- {pos, seconds, speaker, has_name}, in document order.
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

-- Segment dividers: runs of 10+ underscores. For each, capture whether
-- the text right after it matches a wanted-section keyword.
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
  -- Remember the folder the last file was picked from (across REAPER
  -- sessions too, via ExtState), independent of REAPER's own file
  -- dialog memory -- so the picker opens back where you left off even
  -- if REAPER's Finder/Explorer state has since moved elsewhere.
  local last_path = reaper.GetExtState("TranscriptToMarkers", "last_path")

  local retval, file_path = reaper.GetUserFileNameForRead(last_path, "Select transcript (.doc, .docx, or .txt)", "")
  if not retval then return end

  reaper.SetExtState("TranscriptToMarkers", "last_path", file_path, true)  -- true = persist across sessions

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
  -- Collapse ALL whitespace (spaces, tabs, any kind of line break) down
  -- to single spaces. This is what makes parsing independent of line
  -- breaks/paragraph structure entirely.
  local text = raw:gsub("%s+", " ")
  text = trim(text)

  local matches = find_matches(text)
  local dividers = find_dividers(text)  -- already in position order

  reaper.Undo_BeginBlock()

  local added = 0
  local last_speaker = nil
  local seen_first_speaker = false
  local divider_idx = 1
  local in_wanted_section = false
  local sample_matches = {}

  for _, m in ipairs(matches) do
    while divider_idx <= #dividers and dividers[divider_idx].pos <= m.pos do
      in_wanted_section = dividers[divider_idx].wanted
      divider_idx = divider_idx + 1
    end

    local should_consider = (not ONLY_WANTED_SECTIONS) or in_wanted_section

    if should_consider and not is_excluded_speaker(m.speaker) then
      if SKIP_FIRST_SPEAKER and not seen_first_speaker then
        seen_first_speaker = true
        last_speaker = m.speaker
      else
        seen_first_speaker = true
        local is_repeat = DEDUPE_CONSECUTIVE_SPEAKERS and (m.speaker == last_speaker)
        if not is_repeat then
          local pos = m.seconds + OFFSET_SECONDS
          reaper.AddProjectMarker2(0, false, pos, 0, m.speaker, -1, get_marker_color())
          added = added + 1
          if #sample_matches < 10 then
            table.insert(sample_matches, string.format("%s -> %s", tostring(m.seconds), m.speaker))
          end
        end
        last_speaker = m.speaker
      end
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
  if #sample_matches > 0 then
    msg = msg .. "\n\nFirst few markers added:\n- " .. table.concat(sample_matches, "\n- ")
  end
  if #matches == 0 then
    msg = msg .. "\n\nNo speaker tags were found at all -- open the converted .txt file above and check it actually contains readable '(timestamp)' text with names before them, not garbled characters."
  end
  reaper.ShowMessageBox(msg, "Transcript to Markers", 0)
end

main()
