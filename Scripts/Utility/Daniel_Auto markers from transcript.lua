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

  USAGE:
    1. REAPER: Actions > Show action list > New action... > Load
       ReaScript, select this file.
    2. Run it, pick your transcript -- .doc, .docx, or .txt all work
       directly. Word files are converted to text automatically using
       macOS's built-in 'textutil' command (Mac only; on Windows/Linux,
       save the Word doc as .txt yourself first and pick that instead).
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

-- Is REAPER running on a Mac? (textutil, used for auto-converting Word
-- docs, only exists on macOS.) reaper.GetOS() returns strings like
-- "OSX32", "OSX64", "macOS-arm64" on Mac, and "Win32"/"Win64"/"Other"
-- elsewhere.
local function is_mac()
  local os_str = reaper.GetOS() or ""
  return os_str:find("OSX") ~= nil or os_str:find("macOS") ~= nil or os_str:find("Mac") ~= nil
end

-- If the selected file is a Word doc, convert it to plain text via
-- macOS's built-in `textutil` command and return the path to the
-- resulting .txt file. If it's already .txt, just return it as-is --
-- this part works identically on every OS. Returns txt_path, err (err
-- is nil on success).
local function get_text_path(file_path)
  local ext = file_path:match("%.([%a%d]+)$")
  ext = ext and ext:lower() or ""

  if ext == "txt" then
    return file_path, nil
  end

  if ext ~= "doc" and ext ~= "docx" then
    return nil, "Please select a .doc, .docx, or .txt file."
  end

  if not is_mac() then
    return nil, "Word file auto-conversion only works when REAPER is running on a Mac " ..
      "(it uses macOS's built-in 'textutil' command, which doesn't exist on Windows or Linux).\n\n" ..
      "On this system, please convert the file to plain text yourself first " ..
      "(e.g. Word: File > Save As > Plain Text, or LibreOffice: " ..
      "libreoffice --headless --convert-to txt yourfile.docx), " ..
      "then run this script again and select the resulting .txt file."
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
  local retval, file_path = reaper.GetUserFileNameForRead("", "Select transcript (.doc, .docx, or .txt)", "")
  if not retval then return end

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
