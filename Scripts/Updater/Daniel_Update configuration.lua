-- Daniel_Update configuration.lua
--
-- Updates an existing installation to the latest published configuration.
--
--   1. Downloads Configurations/latest.txt from GitHub. Line 1 names the newest
--      .ReaperConfigZip; an optional line 2 holds its SHA-256.
--   2. Asks (Update / Cancel) what to do with the keyboard shortcuts: replace all of
--      them, merge mine into theirs (the default), or leave them alone entirely.
--   3. Downloads and unpacks the archive into Data/Daniel Kharrat/Update (staging).
--   4. Prepares merged files, backs up the important settings files (see
--      BACKUP_FILES) and quits REAPER.
--   5. Daniel_Update_configuration.bat / .sh waits for REAPER to close, copies the
--      staged files into the resource folder, and relaunches REAPER.
--
-- Nothing in the resource folder changes until REAPER has closed. Any failure
-- before that point cleans up the staging folder and leaves REAPER running.
--
-- Files are replaced as they are, EXCEPT:
--   reaper.ini       merged, not replaced: EVERY line in your file is written
--                    into theirs (a value they already have is overwritten, a
--                    line they don't have is added), and everything of theirs
--                    that isn't in your file stays. Nothing is skipped - keep
--                    personal settings out by deleting them from the reaper.ini
--                    inside the archive. One exception: the toolbar toggle
--                    states ([toolbar button states]) keep the values they
--                    already have, and only the lines they are missing are added.
--   reaper-themeconfig.ini  merged by section: only the sections that are in your
--                    file (your theme) are replaced in theirs. Any other section
--                    in their file is kept. Sections they don't have are added.
--   reaper-kb.ini    replaced in a Full install; in "Merge keyboard shortcuts" it
--                    is merged by Daniel_Merge keyboard shortcuts.lua instead.
--   reaper-configzip-info is never copied.
--
-- Which of the person's own files are left alone:
--   reapack.ini            never copied (importing your repository is not the same
--                          as having your configuration).
--   reaper-screensets.ini  copied only if the person has no screen sets yet.
--   sws-autocoloricon.ini  copied only if the person does not have your configuration
--   S&M.ini                yet (see has_my_configuration()); once they do, theirs stay.
--
-- Backups: files that are about to be replaced are backed up first. A person who does
-- not have your configuration yet gets their own settings saved once in
-- "Config Before Daniel Kharrat"; from then on the latest backup goes in "Backup".


------------------------------------------------------------
-- Settings
------------------------------------------------------------

local BASE_URL = "https://raw.githubusercontent.com/Daniel-Kharrat/Protools-Reaper/master/Configurations/"
local POINTER_FILE = "latest.txt"

local TITLE = "Update Configuration"

-- Files that are never copied
local NEVER_COPY = {
    "reapack.ini",
}

-- Files that are copied only if the person does not have that file yet
local COPY_IF_MISSING = {
    "reaper-screensets.ini",
}

-- Files that are copied only if the person does not have your configuration yet
local COPY_IF_NOT_CONFIGURED = {
    "sws-autocoloricon.ini",
    "S&M.ini",
}

-- How each of those files is described in the dialog
local KEEP_LABELS = {
    ["reaper-screensets.ini"] = "screen sets",
    ["sws-autocoloricon.ini"] = "SWS auto colors",
    ["S&M.ini"]               = "S&M settings",
    ["reapack.ini"]           = "ReaPack repositories",
}

-- Toolbar icons (file names inside REAPER's Data/toolbar_icons folder) that exist only
-- with your configuration. They have been in it since version 1, so finding one of
-- them means the person already has your configuration. One is enough. Use a name
-- REAPER does not install itself.
local MY_TOOLBAR_ICONS = {
    "Rec_Tally_Light.png",
    "Insertion_Follows_Playback.png",
}

-- reaper.ini: sections where their values are kept, but lines they don't have
-- yet are added from the configuration (the toolbar button toggle states)
local ADD_ONLY_SECTIONS = {
    ["toolbar button states"] = true,
}

-- Theme config: only the sections that appear in the shipped file are replaced
-- (your theme's section). Every other section in the person's file is kept.
local THEMECONFIG_FILE = "reaper-themeconfig.ini"

------------------------------------------------------------
-- Paths
------------------------------------------------------------

local RESOURCE_PATH = reaper.GetResourcePath():gsub("\\", "/")
local OS = reaper.GetOS()
local IS_WIN = OS:find("Win") ~= nil
local IS_MAC = OS:find("OSX") ~= nil or OS:find("macOS") ~= nil

local DATA_FOLDER  = RESOURCE_PATH .. "/Data"
local DAN_FOLDER   = DATA_FOLDER .. "/Daniel Kharrat"   -- everything of this updater lives here
local STAGE        = DAN_FOLDER .. "/Update"
local EXTRACTED    = STAGE .. "/extracted"
local BACKUP       = DAN_FOLDER .. "/Backup"
-- Backup of a person's own settings from before they had your configuration. Made
-- once, on their first update, and never overwritten by later updates.
local PRE_CONFIG_BACKUP = DAN_FOLDER .. "/Config Before Daniel Kharrat"
local VERSION_FILE = DAN_FOLDER .. "/Config_Version.txt"

-- Where earlier versions of this updater kept things. They are moved or
-- removed the first time the new version runs, so Data stays uncluttered.
local OLD_STAGE        = DATA_FOLDER .. "/Daniel_Update"
local OLD_BACKUP       = DATA_FOLDER .. "/Daniel_Update_Backup"
local OLD_VERSION_FILE = DATA_FOLDER .. "/Daniel_Config_Version.txt"
local OLD_LOG          = DATA_FOLDER .. "/Daniel_Update_log.txt"

-- Files that are backed up before an update if the person has them, whether or not
-- the update changes them
local ALWAYS_BACKUP_FILES = {
    "reaper-screensets.ini",   -- screen sets
    "reaper-hwoutfx.ini",      -- monitoring FX
}

-- The other files that are backed up before an update (when they are about to change)
local BACKUP_FILES = {
    ["reaper-kb.ini"]          = true,   -- keyboard shortcuts
    ["reaper-menu.ini"]        = true,   -- menus
    ["reaper-mouse.ini"]       = true,   -- mouse modifiers
    ["reaper-themeconfig.ini"] = true,   -- theme config
    ["reaper.ini"]             = true,
    ["sws-autocoloricon.ini"]  = true,   -- SWS auto colors
    ["S&M.ini"]                = true,   -- S&M settings
}

local UPDATER_DIR  = RESOURCE_PATH .. "/Scripts/Daniel Kharrat/Updater"
local MERGE_SCRIPT = UPDATER_DIR .. "/Daniel_Merge keyboard shortcuts.lua"
local REAPER_EXE  = (reaper.GetExePath():gsub("\\", "/")) .. (IS_WIN and "/reaper.exe" or "/reaper")   -- passed to the helper (not used on macOS)
local HELPER = UPDATER_DIR .. (IS_WIN and "/Daniel_Update_configuration.bat"
                                       or "/Daniel_Update_configuration.sh")


------------------------------------------------------------
-- Small helpers
------------------------------------------------------------

local function message(text)
    reaper.ShowMessageBox(text, TITLE, 0)
end

local function native(path)
    if IS_WIN then
        return (path:gsub("/", "\\"))
    end
    return path
end

-- quote a path for the command line
local function q(path)
    if IS_WIN then
        return '"' .. path:gsub("/", "\\") .. '"'
    end
    return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local contents = file:read("*all")
    file:close()
    return contents
end

local function write_file(path, contents)
    local file = io.open(path, "wb")
    if not file then
        return false
    end
    file:write(contents)
    file:close()
    return true
end

local function file_exists(path)
    local file = io.open(path, "rb")
    if file then
        file:close()
        return true
    end
    return false
end

-- Full path of a command-line tool. A program started from the Finder or Dock
-- may not have the same PATH as Terminal, so on macOS and Linux look in the
-- usual folders first and fall back to the bare name.
local function tool(name)
    if IS_WIN then
        return name
    end
    for _, folder in ipairs({ "/usr/bin", "/bin", "/usr/local/bin", "/opt/homebrew/bin" }) do
        local path = folder .. "/" .. name
        if file_exists(path) then
            return path
        end
    end
    return name
end

local function copy_file(source, destination)
    local data = read_file(source)
    if not data then
        return false
    end
    local folder = destination:match("^(.*)/[^/]+$")
    if folder then
        reaper.RecursiveCreateDirectory(folder, 0)
    end
    return write_file(destination, data)
end

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Runs a command line. Returns the exit code (or nil), its output, and exactly
-- what REAPER returned (for error messages).
local function run(command, timeout_ms)
    local result = reaper.ExecProcess(command, timeout_ms or 60000)
    if not result then
        return nil, "", nil
    end
    local code, output = result:match("^(%-?%d+)\n?(.*)$")
    return tonumber(code), output or "", result
end

-- Deletes a staging or backup folder. Only folders inside Data/Daniel Kharrat
-- (never that folder itself) and the two old folders of earlier versions.
local function remove_dir(path)
    local inside = path:sub(1, #DAN_FOLDER + 1) == DAN_FOLDER .. "/"
    if not inside and path ~= OLD_STAGE and path ~= OLD_BACKUP then
        return
    end
    if IS_WIN then
        run("cmd.exe /c if exist " .. q(path) .. " rmdir /s /q " .. q(path), 60000)
    else
        run(tool("rm") .. " -rf " .. q(path), 60000)
    end
end

-- Every file below root, as paths relative to root ("Data/toolbar_icons/x.png")
local function list_files(root, rel, out)
    rel = rel or ""
    out = out or {}
    local dir = (rel == "") and root or (root .. "/" .. rel)

    reaper.EnumerateFiles(dir, -1)
    local i = 0
    while true do
        local name = reaper.EnumerateFiles(dir, i)
        if not name then
            break
        end
        out[#out + 1] = (rel == "") and name or (rel .. "/" .. name)
        i = i + 1
    end

    reaper.EnumerateSubdirectories(dir, -1)
    i = 0
    while true do
        local name = reaper.EnumerateSubdirectories(dir, i)
        if not name then
            break
        end
        list_files(root, (rel == "") and name or (rel .. "/" .. name), out)
        i = i + 1
    end

    return out
end

-- Splits text into lines, accepting both CRLF and LF.
local function split_lines(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        lines[#lines + 1] = line
    end
    if lines[#lines] == "" then
        lines[#lines] = nil
    end
    return lines
end


------------------------------------------------------------
-- Versions ("Daniel_Reaper_Protools_v4_2.ReaperConfigZip" -> "4.2")
------------------------------------------------------------

local function parse_version(archive_name)
    local raw = archive_name:match("[_ ][vV](%d[%d_%.]*)%.ReaperConfigZip$")
    if not raw then
        return nil
    end
    return (raw:gsub("_", "."))
end

-- Compares "4.2" with "4.10" number by number: returns -1, 0 or 1
local function compare_versions(a, b)
    local pa, pb = {}, {}
    for n in a:gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in b:gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x < y then return -1 end
        if x > y then return 1 end
    end
    return 0
end


------------------------------------------------------------
-- Download and checksum
------------------------------------------------------------

local function download(url, destination, max_seconds)
    os.remove(destination)
    local command = tool("curl") .. " -f -s -S -L --connect-timeout 15 --max-time " .. max_seconds ..
        " -o " .. q(destination) .. ' "' .. url .. '"'
    local code, output = run(command, (max_seconds + 15) * 1000)
    local data = read_file(destination)
    if code == 0 and data and #data > 0 then
        return true
    end
    os.remove(destination)
    return false, trim(output:match("[^\r\n]*") or "")
end

local function sha256_of(path)
    local command
    if IS_WIN then
        command = "certutil -hashfile " .. q(path) .. " SHA256"
    elseif IS_MAC then
        command = tool("shasum") .. " -a 256 " .. q(path)
    else
        command = tool("sha256sum") .. " " .. q(path)
    end
    local code, output = run(command, 120000)
    if code ~= 0 then
        return nil
    end

    -- the hash as a single 64-character word, if the tool printed it that way
    local hash = nil
    for word in output:gmatch("%S+") do
        if #word == 64 and word:match("^%x+$") then
            hash = word:lower()
            break
        end
    end

    -- everything without whitespace (some tools print the hash in groups)
    return (output:gsub("%s", ""):lower()), hash
end


------------------------------------------------------------
-- Unpack
------------------------------------------------------------

local function extract(zip_path, destination)
    reaper.RecursiveCreateDirectory(destination, 0)

    local attempts
    if IS_WIN then
        attempts = {
            "tar -xf " .. q(zip_path) .. " -C " .. q(destination),
        }
    else
        attempts = {
            tool("unzip") .. " -q -o " .. q(zip_path) .. " -d " .. q(destination),
            tool("tar") .. " -xf " .. q(zip_path) .. " -C " .. q(destination),
            tool("python3") .. " -m zipfile -e " .. q(zip_path) .. " " .. q(destination),
        }
    end

    for _, command in ipairs(attempts) do
        run(command, 120000)
        if file_exists(destination .. "/reaper.ini") or
           file_exists(destination .. "/reaper-kb.ini") or
           file_exists(destination .. "/reaper-configzip-info") then
            return true
        end
    end
    return false
end


------------------------------------------------------------
-- reaper.ini merge
------------------------------------------------------------

-- Merges the shipped reaper.ini into the person's. Keeps their line ending,
-- their order and every key of theirs that the shipped file doesn't mention.
local function merge_ini(target_text, shipped_text)

    local eol = "\n"
    if target_text:find("\r\n", 1, true) then
        eol = "\r\n"
    end

    local target  = split_lines(target_text)
    local shipped = split_lines(shipped_text)

    local stats = { replaced = 0, added = 0, kept = 0, sections_added = 0, changed = false }

    -- index the person's file: section -> { keys = {key -> line}, last = last line }
    local sections = {}
    local last_line_of = {}   -- line number -> section name (last line of that section)
    local current = nil

    for i, line in ipairs(target) do
        local name = line:match("^%[(.-)%]%s*$")
        if name then
            current = sections[name]
            if not current then
                current = { keys = {}, last = i }
                sections[name] = current
            end
        elseif current then
            local key = line:match("^([^=]+)=")
            if key and not current.keys[key] then
                current.keys[key] = i
            end
            if line:match("%S") then
                current.last = i
            end
        end
    end
    for name, info in pairs(sections) do
        last_line_of[info.last] = name
    end

    -- walk the shipped file
    local replace = {}        -- line number -> new line
    local additions = {}      -- section -> lines to add at its end
    local new_sections = {}   -- sections the person doesn't have yet
    local new_by_name = {}

    local section, add_only = nil, false

    for _, line in ipairs(shipped) do
        local name = line:match("^%[(.-)%]%s*$")
        if name then
            section = name
            add_only = ADD_ONLY_SECTIONS[name] or false
            if not sections[name] and not new_by_name[name] then
                local entry = { name = name, lines = {} }
                new_sections[#new_sections + 1] = entry
                new_by_name[name] = entry
            end
        elseif section then
            local key, value = line:match("^([^=]+)=(.*)$")
            if key then
                if sections[section] then
                    local at = sections[section].keys[key]
                    if at then
                        if add_only then
                            stats.kept = stats.kept + 1    -- they already have this line
                        elseif target[at] ~= line then
                            replace[at] = line
                            stats.replaced = stats.replaced + 1
                        end
                    else
                        additions[section] = additions[section] or {}
                        table.insert(additions[section], line)
                        stats.added = stats.added + 1
                    end
                else
                    table.insert(new_by_name[section].lines, line)
                    stats.added = stats.added + 1
                end
            end
        end
    end

    -- rebuild
    local out = {}
    for i, line in ipairs(target) do
        out[#out + 1] = replace[i] or line
        local name = last_line_of[i]
        if name and additions[name] then
            for _, added in ipairs(additions[name]) do
                out[#out + 1] = added
            end
        end
    end

    for _, entry in ipairs(new_sections) do
        if #entry.lines > 0 then
            if #out > 0 and out[#out] ~= "" then
                out[#out + 1] = ""
            end
            out[#out + 1] = "[" .. entry.name .. "]"
            for _, added in ipairs(entry.lines) do
                out[#out + 1] = added
            end
            stats.sections_added = stats.sections_added + 1
        end
    end

    stats.changed = (stats.replaced + stats.added) > 0

    local text = ""
    if #out > 0 then
        text = table.concat(out, eol) .. eol
    end
    return text, stats
end

------------------------------------------------------------
-- Theme config merge (section level)
------------------------------------------------------------

-- Replaces, section by section, the sections that exist in the shipped file.
-- Sections that are only in the person's file are left untouched; sections that
-- are only in the shipped file are appended.
local function merge_sections(target_text, shipped_text)

    local eol = "\n"
    if target_text:find("\r\n", 1, true) then
        eol = "\r\n"
    end

    local function parse(text)
        local result = { preamble = {}, order = {}, map = {} }
        local current = nil
        for _, line in ipairs(split_lines(text)) do
            local name = line:match("^%[(.-)%]%s*$")
            if name then
                current = { name = name, header = line, body = {} }
                result.order[#result.order + 1] = current
                if not result.map[name:lower()] then
                    result.map[name:lower()] = current
                end
            elseif current then
                current.body[#current.body + 1] = line
            else
                result.preamble[#result.preamble + 1] = line
            end
        end
        return result
    end

    local function trailing_blanks(body)
        local n = 0
        for i = #body, 1, -1 do
            if body[i]:match("%S") then break end
            n = n + 1
        end
        return n
    end

    local target  = parse(target_text)
    local shipped = parse(shipped_text)

    local stats = { replaced = 0, added = 0, kept = 0 }
    local out = {}
    local used = {}   -- shipped sections already written

    for _, line in ipairs(target.preamble) do
        out[#out + 1] = line
    end

    for _, section in ipairs(target.order) do
        local key = section.name:lower()
        local new = shipped.map[key]
        if new then
            if not used[key] then
                used[key] = true
                out[#out + 1] = new.header
                local blanks = trailing_blanks(new.body)
                for i = 1, #new.body - blanks do
                    out[#out + 1] = new.body[i]
                end
                -- keep the spacing the person's file had after this section
                for _ = 1, trailing_blanks(section.body) do
                    out[#out + 1] = ""
                end
                stats.replaced = stats.replaced + 1
            end
            -- a duplicate of the same section in their file is dropped
        else
            out[#out + 1] = section.header
            for _, line in ipairs(section.body) do
                out[#out + 1] = line
            end
            stats.kept = stats.kept + 1
        end
    end

    -- shipped sections they don't have yet
    for _, section in ipairs(shipped.order) do
        local key = section.name:lower()
        if not used[key] and target.map[key] == nil then
            used[key] = true
            if #out > 0 and out[#out] ~= "" then
                out[#out + 1] = ""
            end
            out[#out + 1] = section.header
            local blanks = trailing_blanks(section.body)
            for i = 1, #section.body - blanks do
                out[#out + 1] = section.body[i]
            end
            stats.added = stats.added + 1
        end
    end

    local text = ""
    if #out > 0 then
        text = table.concat(out, eol) .. eol
    end
    return text, stats
end

------------------------------------------------------------
-- Does the person already have your configuration?
------------------------------------------------------------

-- True if the person already has your configuration: an earlier update recorded a
-- version, or one of your toolbar icons is in their toolbar_icons folder (older
-- installs made by importing the configuration). Having imported your ReaPack
-- repository does NOT count.
local function has_my_configuration(installed_version)
    if installed_version ~= nil then
        return true
    end
    for _, name in ipairs(MY_TOOLBAR_ICONS) do
        if file_exists(RESOURCE_PATH .. "/Data/toolbar_icons/" .. name) then
            return true
        end
    end
    return false
end

-- True if this update saves the person's own settings in "Config Before Daniel Kharrat":
-- they do not have your configuration yet, and that folder has not been filled before
local function uses_pre_config_backup(configured)
    return not configured and not reaper.EnumerateFiles(PRE_CONFIG_BACKUP, 0)
end

-- The files of the configuration that must not be replaced on this machine
local function files_to_leave(configured)
    local leave = {}
    for _, name in ipairs(NEVER_COPY) do
        leave[#leave + 1] = name
    end
    for _, name in ipairs(COPY_IF_MISSING) do
        if file_exists(RESOURCE_PATH .. "/" .. name) then
            leave[#leave + 1] = name
        end
    end
    if configured then
        for _, name in ipairs(COPY_IF_NOT_CONFIGURED) do
            leave[#leave + 1] = name
        end
    end
    return leave
end


------------------------------------------------------------
-- Dialog
--
-- Uses REAPER's built-in gfx window, so nothing extra has to be installed.
-- Look: Daniel's house style (macOS Finder vibe, dark): plain window colour,
-- soft grey rounded areas with a hairline edge, capsule buttons, a small (i)
-- button with a popover for the secondary notes. Every rounded shape is filled
-- row by row with gfx.rect (gfx.circle draws a different size on each OS).
--
-- Three choices for the keyboard shortcuts (reaper-kb.ini):
--   merge = merge keyboard shortcuts (default), replace = full install,
--   skip    = don't import reaper-kb.ini at all.
-- Update proceeds, Cancel (or Esc, or closing the window) does nothing.
-- Enter = Update, Up/Down arrows = change the choice, Esc closes the popover first.
------------------------------------------------------------

local function show_dialog(info, on_ok, on_cancel)
    local WIN_W, WIN_H = 560, 560
    local mode = "merge"
    local SHORTCUT_OPTIONS = {
        { id = "merge",
          label = "Merge with my keyboard shortcuts",
          text  = "Everything from this configuration is applied. If you changed any of my shortcuts, they go back to my settings. Shortcuts, scripts and actions that are not part of this configuration, such as ones you added yourself, stay untouched." },
        { id = "replace",
          label = "Replace all my keyboard shortcuts and actions",
          text  = "Your current shortcuts and action list are swapped for the ones in this configuration. Any shortcuts you added yourself will be gone." },
        { id = "skip",
          label = "Don't touch my keyboard shortcuts",
          text  = "Keyboard shortcuts and actions are not imported at all. Yours stay exactly as they are." },
    }
    local decided = false
    local scale = 1
    local mouse_was_down = false
    local press_target = nil
    local rects = {}
    local popover = false

    -- colours (dark appearance)
    local function hex(v)
        return { ((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255 }
    end
    local C = {
        bg        = hex(0x1E1E20),   -- window
        card      = hex(0x262629),   -- soft grey area
        hover     = hex(0x2D2D31),   -- row under the mouse
        edge      = hex(0x303033),   -- hairline (8% white over the window)
        sep       = hex(0x37373A),   -- separator inside an area
        text      = hex(0xF2F2F5),
        muted     = hex(0x9D9DA4),
        accent    = hex(0x2F6FD0),
        accent_hi = hex(0x3B7BDC),
        fill      = hex(0x37373A),   -- secondary button
        fill_hi   = hex(0x434347),
        capsule   = hex(0x363639),
        ring      = hex(0x5C5C62),
        well      = hex(0x2E2E31),
        green     = hex(0x30D158),
        pop       = hex(0x2C2C2F),   -- popover
        pop_edge  = hex(0x3F3F43),
        white     = { 1, 1, 1 },
        black     = { 0, 0, 0 },
        icon_top  = hex(0x5A9BFF),
        icon_bot  = hex(0x1F5FD6),
    }

    local FONT = IS_WIN and "Segoe UI" or (IS_MAC and "Helvetica Neue" or "DejaVu Sans")
    local FONTS = {             -- slot, size, bold, line height
        title = { 1, 18, true,  22 },
        bold  = { 2, 14, true,  19 },
        body  = { 3, 14, false, 19 },
        small = { 4, 13, false, 18 },
        label = { 5, 12, true,  16 },
        glyph = { 6, 13, true,  16 },
    }
    local font_now = "body"

    local function finish(accepted)
        if decided then
            return
        end
        decided = true
        gfx.quit()
        if accepted then
            on_ok(mode)   -- "replace", "merge" or "skip"
        else
            on_cancel()
        end
    end

    -- centre the window on the screen the mouse is on
    local mx, my = reaper.GetMousePosition()
    local l, t, r, b = reaper.my_getViewport(mx, my, mx, my, mx, my, mx, my, true)
    local left, right = math.min(l, r), math.max(l, r)
    local top, bottom = math.min(t, b), math.max(t, b)
    local x = left + math.floor((right - left - WIN_W) / 2)
    local y = top + math.floor((bottom - top - WIN_H) / 2)

    gfx.ext_retina = 1
    if gfx.init(TITLE, WIN_W, WIN_H, 0, x, y) == 0 then
        message("Could not open the dialog window.")
        on_cancel()
        return
    end

    -- Sizes are worked out from the window that was actually created, not from
    -- what was asked for: with screen scaling (Windows, macOS Retina) the window
    -- can have a different number of pixels than WIN_W x WIN_H.
    --   base_scale = actual pixels per requested pixel (set on the first frame)
    --   zoom       = extra shrink factor, used only when the text would not fit
    local base_scale, zoom = 1, 1
    local design_w, design_h = nil, nil

    local function S(v)
        return math.floor(v * scale + 0.5)
    end

    local function set_font(kind)
        local f = FONTS[kind]
        font_now = kind
        gfx.setfont(f[1], FONT, math.max(1, math.floor(f[2] * scale + 0.5)), f[3] and string.byte("b") or 0)
    end

    local function line_h()
        return S(FONTS[font_now][4])
    end

    local function color(c, a)
        gfx.set(c[1], c[2], c[3], a or 1)
    end

    local function inside(rect, px, py)
        return rect and px >= rect.x and px < rect.x + rect.w and py >= rect.y and py < rect.y + rect.h
    end

    --------------------------------------------------------
    -- shapes (anti-aliased, filled row by row)
    --------------------------------------------------------

    -- Rounded rectangle. c2 = optional bottom colour (vertical gradient).
    -- clip_top / clip_bottom = optional pixel rows to limit the drawing to.
    local function fill_round(rx, ry, rw, rh, radius, c, a, c2, clip_top, clip_bottom)
        rx, ry = math.floor(rx + 0.5), math.floor(ry + 0.5)
        rw, rh = math.floor(rw + 0.5), math.floor(rh + 0.5)
        if rw <= 0 or rh <= 0 then
            return
        end
        a = a or 1
        local rad = math.floor(math.min(radius, rw / 2, rh / 2) + 0.5)
        local row_from = math.max(0, (clip_top or ry) - ry)
        local row_to = math.min(rh - 1, (clip_bottom or (ry + rh)) - ry - 1)
        local function set_row(j)
            if c2 then
                local k = (rh > 1) and (j / (rh - 1)) or 0
                gfx.set(c[1] + (c2[1] - c[1]) * k, c[2] + (c2[2] - c[2]) * k, c[3] + (c2[3] - c[3]) * k, a)
            else
                gfx.set(c[1], c[2], c[3], a)
            end
        end
        -- straight middle band in one go (no gradient), else row by row
        local band_from = math.max(row_from, rad)
        local band_to = math.min(row_to, rh - rad - 1)
        if not c2 and band_to >= band_from then
            set_row(0)
            gfx.rect(rx, ry + band_from, rw, band_to - band_from + 1, 1)
        end
        for j = row_from, row_to do
            local in_band = (j >= rad and j <= rh - rad - 1)
            if in_band then
                if c2 then
                    set_row(j)
                    gfx.rect(rx, ry + j, rw, 1, 1)
                end
            else
                -- distance of this row from the corner circle's centre row
                local jj = (j < rad) and j or (rh - 1 - j)
                local e = {}
                local emin, emax = math.huge, -math.huge
                for s = 0, 3 do
                    local dy = rad - (jj + (s + 0.5) / 4)
                    local inset = rad - math.sqrt(math.max(0, rad * rad - dy * dy))
                    e[#e + 1] = inset
                    if inset < emin then emin = inset end
                    if inset > emax then emax = inset end
                end
                local full_from = math.ceil(emax)
                -- edge pixels with partial coverage
                for px = math.floor(emin), full_from - 1 do
                    local cover = 0
                    for s = 1, 4 do
                        cover = cover + math.max(0, math.min(1, px + 1 - e[s]))
                    end
                    cover = cover / 4
                    if cover > 0 then
                        set_row(j)
                        gfx.a = a * cover
                        gfx.rect(rx + px, ry + j, 1, 1, 1)
                        gfx.rect(rx + rw - 1 - px, ry + j, 1, 1, 1)
                    end
                end
                if rw - 2 * full_from > 0 then
                    set_row(j)
                    gfx.rect(rx + full_from, ry + j, rw - 2 * full_from, 1, 1)
                end
            end
        end
    end

    local function fill_circle(cx, cy, radius, c, a)
        fill_round(cx - radius, cy - radius, radius * 2, radius * 2, radius, c, a)
    end

    -- area with a hairline edge
    local function area(rx, ry, rw, rh, radius, fill, edge)
        local px = math.max(1, math.floor(scale / 2 + 0.5))   -- 0.5 pt hairline
        fill_round(rx, ry, rw, rh, radius, edge)
        fill_round(rx + px, ry + px, rw - 2 * px, rh - 2 * px, radius - px, fill)
    end

    -- triangle, flat side on top (pointing down) or bottom (pointing up)
    local function fill_triangle(cx, ty, half_w, th, c, a, up)
        a = a or 1
        for j = 0, th - 1 do
            local k = (j + 0.5) / th
            local hw = half_w * (up and k or (1 - k))
            local x1, x2 = cx - hw, cx + hw
            local f1, f2 = math.ceil(x1), math.floor(x2)
            color(c, a)
            if f2 > f1 then gfx.rect(f1, ty + j, f2 - f1, 1, 1) end
            gfx.a = a * (f1 - x1)
            gfx.rect(f1 - 1, ty + j, 1, 1, 1)
            gfx.a = a * (x2 - f2)
            gfx.rect(f2, ty + j, 1, 1, 1)
        end
    end

    --------------------------------------------------------
    -- text
    --------------------------------------------------------

    local function wrap(text, max_w)
        local lines = {}
        for paragraph in (text .. "\n"):gmatch("(.-)\n") do
            if paragraph == "" then
                lines[#lines + 1] = ""
            else
                local line = ""
                for word in paragraph:gmatch("%S+") do
                    local candidate = (line == "") and word or (line .. " " .. word)
                    if line ~= "" and gfx.measurestr(candidate) > max_w then
                        lines[#lines + 1] = line
                        line = word
                    else
                        line = candidate
                    end
                end
                lines[#lines + 1] = line
            end
        end
        return lines
    end

    -- Where the capital letters sit inside a text line (top and bottom of "H",
    -- measured from gfx.y). Fonts differ per OS, so this is measured once per
    -- font and size by drawing into an off-screen buffer. Used to centre text
    -- optically in buttons and next to icons. false = could not measure.
    local cap_cache = {}
    local function cap_box()
        local key = font_now .. ":" .. scale
        local hit = cap_cache[key]
        if hit ~= nil then
            return hit
        end
        local result = false
        if gfx.setimgdim and gfx.getpixel then
            local tw, th = gfx.measurestr("H")
            local bw, bh = math.ceil(tw) + 4, math.ceil(th) + 4
            local old_dest = gfx.dest
            gfx.setimgdim(127, bw, bh)
            gfx.dest = 127
            gfx.set(0, 0, 0, 1)
            gfx.rect(0, 0, bw, bh, 1)
            gfx.set(1, 1, 1, 1)
            gfx.x, gfx.y = 2, 2
            gfx.drawstr("H")
            local first, last
            for py = 0, bh - 1 do
                for px = 0, bw - 1 do
                    gfx.x, gfx.y = px, py
                    local red = gfx.getpixel()
                    if red and red > 0.35 then
                        first = first or py
                        last = py
                        break
                    end
                end
            end
            gfx.dest = old_dest or -1
            if first then
                result = { first - 2, last - 2 + 1 }
            end
        end
        cap_cache[key] = result
        return result
    end

    -- y (gfx.y) that puts a text line's capitals centred on mid_y
    local function text_top_for(mid_y)
        local box = cap_box()
        if box then
            return math.floor(mid_y - (box[1] + box[2]) / 2 + 0.5)
        end
        local _, th = gfx.measurestr("H")
        return math.floor(mid_y - th / 2 + 0.5)
    end

    -- one line, centred vertically on mid_y; align = "left" / "center" / "right"
    local function draw_line(text, lx, mid_y, align, box_w)
        local tw = gfx.measurestr(text)
        if align == "center" then
            lx = lx + (box_w - tw) / 2
        elseif align == "right" then
            lx = lx - tw
        end
        gfx.x, gfx.y = math.floor(lx + 0.5), text_top_for(mid_y)
        gfx.drawstr(text)
        return tw
    end

    -- wrapped text; returns the y below it
    local function draw_text(text, tx, ty, max_w, kind)
        set_font(kind)
        local lh = line_h()
        for _, line in ipairs(wrap(text, max_w)) do
            gfx.x, gfx.y = tx, ty
            gfx.drawstr(line)
            ty = ty + lh
        end
        return ty
    end

    local function text_height(text, max_w, kind)
        set_font(kind)
        return #wrap(text, max_w) * line_h()
    end

    --------------------------------------------------------
    -- pieces
    --------------------------------------------------------

    -- app icon: blue tile with a white "download into tray" arrow
    local function draw_icon(ix, iy, size)
        fill_round(ix, iy + math.max(1, S(1)), size, size, size * 0.24, C.black, 0.30)   -- soft shadow
        fill_round(ix, iy, size, size, size * 0.24, C.icon_top, 1, C.icon_bot)
        local cx = ix + size / 2
        local stem_w = size * 0.15
        fill_round(cx - stem_w / 2, iy + size * 0.18, stem_w, size * 0.34, stem_w / 2, C.white)
        fill_triangle(cx, math.floor(iy + size * 0.44), size * 0.25, math.floor(size * 0.24), C.white, 1, false)
        local tray_h = math.max(2, size * 0.09)
        fill_round(ix + size * 0.22, iy + size * 0.75, size * 0.56, tray_h, tray_h / 2, C.white)
    end

    -- green circle with a white check mark
    local function draw_check(cx, cy, radius)
        fill_circle(cx, cy, radius, C.green)
        color(C.white)
        local w = radius * 2
        local x0, y0 = cx - radius, cy - radius
        local ax, ay = x0 + w * 0.28, y0 + w * 0.52
        local bx, by = x0 + w * 0.44, y0 + w * 0.68
        local ex, ey = x0 + w * 0.73, y0 + w * 0.34
        local thick = math.max(1, math.floor(radius / 4))
        for o = 0, thick - 1 do
            gfx.line(ax, ay + o, bx, by + o, 1)
            gfx.line(bx, by + o, ex, ey + o, 1)
        end
    end

    local function draw_button(rect, label, primary, hover)
        local radius = rect.h / 2
        if primary then
            fill_round(rect.x, rect.y + math.max(1, S(1)), rect.w, rect.h, radius, C.black, 0.25)
            fill_round(rect.x, rect.y, rect.w, rect.h, radius, hover and C.accent_hi or C.accent)
            color(C.white)
        else
            fill_round(rect.x, rect.y, rect.w, rect.h, radius, hover and C.fill_hi or C.fill)
            color(C.text)
        end
        set_font(primary and "bold" or "body")
        draw_line(label, rect.x, rect.y + rect.h / 2, "center", rect.w)
    end

    local function button_width(label, primary)
        set_font(primary and "bold" or "body")
        return math.max(S(96), math.floor(gfx.measurestr(label) + S(36)))
    end

    --------------------------------------------------------
    -- frame
    --------------------------------------------------------

    local function draw()
        -- The layout is calculated for the window's original size (design_w x
        -- design_h), not its current size, so resizing the window can never move
        -- the text or the buttons.
        scale = base_scale * zoom
        local M = S(24)
        local W = design_w
        local mouse_x, mouse_y = gfx.mouse_x, gfx.mouse_y
        local can_hover = not popover
        rects = {}

        color(C.bg)
        gfx.rect(0, 0, gfx.w, gfx.h, 1)

        -- header: icon + title on the left, version capsule on the right
        local icon = S(28)
        local hy = M
        draw_icon(M, hy, icon)
        local title_x = M + icon + S(12)
        set_font("title")
        color(C.text)
        draw_line(TITLE, title_x, hy + icon / 2)

        local cap_text
        if info.same_version then
            cap_text = "Up to date \194\183 v" .. info.latest
        elseif info.installed then
            cap_text = "v" .. info.installed .. "  \226\134\146  v" .. info.latest
        else
            cap_text = "Latest: v" .. info.latest
        end
        set_font("small")
        local cap_h = S(28)
        local cap_w = math.floor(gfx.measurestr(cap_text) + S(26))
        local cap_x = W - M - cap_w
        local cap_y = hy + (icon - cap_h) / 2
        fill_round(cap_x, cap_y + math.max(1, S(1)), cap_w, cap_h, cap_h / 2, C.black, 0.25)
        area(cap_x, cap_y, cap_w, cap_h, cap_h / 2, C.capsule, C.edge)
        color(info.same_version and C.green or C.muted)
        draw_line(cap_text, cap_x, cap_y + cap_h / 2, "center", cap_w)

        local cy = hy + icon + S(6)
        color(C.muted)
        cy = draw_text("REAPER closes and restarts to apply the update.", title_x, cy, W - M - title_x, "body")
        cy = cy + S(20)

        -- keyboard shortcuts choice
        set_font("label")
        color(C.muted)
        gfx.x, gfx.y = M + S(4), cy
        gfx.drawstr("Keyboard Shortcuts and Actions")
        cy = cy + line_h() + S(6)

        local pad_x, pad_y = S(16), S(12)
        local dot = S(16)
        local label_x = M + pad_x + dot + S(12)
        local label_w = W - M - pad_x - label_x
        local heights = {}
        local card_h = 0
        for i, option in ipairs(SHORTCUT_OPTIONS) do
            heights[i] = pad_y * 2 + text_height(option.label, label_w, "bold") + S(3) +
                text_height(option.text, label_w, "small")
            card_h = card_h + heights[i]
        end
        local card_x, card_w = M, W - 2 * M
        local card_r = S(14)
        local hair = math.max(1, math.floor(scale / 2 + 0.5))
        area(card_x, cy, card_w, card_h, card_r, C.card, C.edge)

        local row_y = cy
        for i, option in ipairs(SHORTCUT_OPTIONS) do
            local rh = heights[i]
            local rect = { x = card_x, y = row_y, w = card_w, h = rh }
            rects[option.id] = rect
            if can_hover and inside(rect, mouse_x, mouse_y) then
                fill_round(card_x + hair, cy + hair, card_w - 2 * hair, card_h - 2 * hair, card_r - hair,
                    C.hover, 1, nil, row_y + ((i == 1) and hair or 0), row_y + rh - ((i == #SHORTCUT_OPTIONS) and hair or 0))
            end
            if i > 1 then
                color(C.sep)
                gfx.rect(label_x, row_y, card_x + card_w - pad_x - label_x, hair, 1)
            end

            -- label (first line decides where the radio sits)
            set_font("bold")
            local first_mid = row_y + pad_y + line_h() / 2
            local box = cap_box()
            if box then
                first_mid = row_y + pad_y + (box[1] + box[2]) / 2
            end
            color(C.text)
            local ty = draw_text(option.label, label_x, row_y + pad_y, label_w, "bold")
            color(C.muted)
            draw_text(option.text, label_x, ty + S(3), label_w, "small")

            -- radio
            local rcx = M + pad_x + dot / 2
            if mode == option.id then
                fill_circle(rcx, first_mid, dot / 2, C.accent)
                fill_circle(rcx, first_mid, math.max(2, S(3)), C.white)
            else
                fill_circle(rcx, first_mid, dot / 2, C.ring)
                fill_circle(rcx, first_mid, dot / 2 - math.max(1, S(1.5)), C.well)
            end
            row_y = row_y + rh
        end
        cy = cy + card_h + S(16)

        -- backup note. reaper-kb.ini (keyboard shortcuts) is only touched when the
        -- choice is not "skip"; the mouse modifiers are backed up in every case.
        local note
        if info.first_backup then
            note = "Before anything changes, all your current configuration files are backed up in your " ..
                "REAPER resource folder: Data/Daniel Kharrat/Config Before Daniel Kharrat"
        else
            note = "Before anything changes, your current " ..
                ((mode == "skip") and "mouse modifiers are" or "keyboard shortcuts and mouse modifiers are") ..
                " backed up in your REAPER resource folder: Data/Daniel Kharrat/Backup"
        end
        set_font("small")
        local note_mid = cy + line_h() / 2
        local nbox = cap_box()
        if nbox then
            note_mid = cy + (nbox[1] + nbox[2]) / 2
        end
        draw_check(M + pad_x + dot / 2, note_mid, dot / 2)
        color(C.muted)
        cy = draw_text(note, label_x, cy, W - M - label_x, "small")

        -- buttons
        local btn_h = S(30)
        local btn_y = math.floor(design_h - M - btn_h)
        local ok_w = button_width("Update", true)
        local cancel_w = button_width("Cancel", false)
        rects.ok = { x = W - M - ok_w, y = btn_y, w = ok_w, h = btn_h }
        rects.cancel = { x = rects.ok.x - S(10) - cancel_w, y = btn_y, w = cancel_w, h = btn_h }
        draw_button(rects.cancel, "Cancel", false, can_hover and inside(rects.cancel, mouse_x, mouse_y))
        draw_button(rects.ok, "Update", true, can_hover and inside(rects.ok, mouse_x, mouse_y))

        -- (i) button: what stays the person's own
        local info_d = S(22)
        rects.info = { x = M, y = btn_y + (btn_h - info_d) / 2, w = info_d, h = info_d }
        local info_hot = popover or inside(rects.info, mouse_x, mouse_y)
        local icx, icy = M + info_d / 2, btn_y + btn_h / 2
        fill_circle(icx, icy, info_d / 2, info_hot and C.muted or C.ring)
        fill_circle(icx, icy, info_d / 2 - math.max(1, S(1.5)), C.bg)
        set_font("glyph")
        color(info_hot and C.text or C.muted)
        draw_line("i", icx - info_d / 2, icy, "center", info_d)

        -- If the text and buttons need more height than the window has, shrink
        -- everything a little and let the loop draw it again, so nothing is cropped.
        local needed = cy + S(24) + btn_h + M
        if needed > design_h + 1 and zoom > 0.55 then
            zoom = math.max(0.55, zoom * design_h / needed)
            return true
        end

        -- popover above the (i) button
        if popover then
            local names = {}
            for _, name in ipairs(info.leave) do
                names[#names + 1] = KEEP_LABELS[name] or name
            end
            local p1 = "Settings in your own reaper.ini that are not part of the configuration are kept, " ..
                "such as machine-specific settings and some personal preferences."
            local p2 = "These will not be replaced: " .. table.concat(names, ", ") .. "."
            local pw = math.min(S(400), W - 2 * M)
            local ppad = S(16)
            local tw = pw - 2 * ppad
            set_font("bold")
            local head_h = line_h()
            local ph = ppad * 2 + head_h + S(6) + text_height(p1, tw, "small") + S(8) + text_height(p2, tw, "small")
            local nub = S(8)
            local px = M - S(6)
            local py = btn_y - S(10) - nub - ph
            for k = 1, 3 do   -- soft shadow
                fill_round(px - k, py + k * 2 - k, pw + 2 * k, ph + 2 * k, S(14) + k, C.black, 0.10)
            end
            area(px, py, pw, ph, S(14), C.pop, C.pop_edge)
            fill_triangle(icx, py + ph - hair, nub + hair, nub + hair, C.pop_edge, 1, false)
            fill_triangle(icx, py + ph - hair - 1, nub, nub, C.pop, 1, false)
            color(C.text)
            local ty = draw_text("What Stays Yours", px + ppad, py + ppad, tw, "bold")
            color(C.muted)
            ty = draw_text(p1, px + ppad, ty + S(6), tw, "small")
            draw_text(p2, px + ppad, ty + S(8), tw, "small")
            rects.popover = { x = px, y = py, w = pw, h = ph }
        end
        return false
    end

    local function which_target()
        for _, name in ipairs({ "ok", "cancel", "info", "replace", "merge", "skip" }) do
            if inside(rects[name], gfx.mouse_x, gfx.mouse_y) then
                return name
            end
        end
        return nil
    end

    local function loop()
        if decided then
            return
        end

        if not design_w then
            -- wait until the window reports its real size
            if gfx.w < 100 then
                if gfx.getchar() < 0 then
                    finish(false)
                    return
                end
                gfx.update()
                reaper.defer(loop)
                return
            end
            design_w, design_h = gfx.w, gfx.h
            base_scale = gfx.w / WIN_W
        end

        for _ = 1, 4 do
            if not draw() then
                break
            end
        end

        -- mouse: act when the button is released over the thing it was pressed on
        local down = (gfx.mouse_cap & 1) == 1
        if down and not mouse_was_down then
            press_target = which_target()
            if popover and press_target ~= "info" and not inside(rects.popover, gfx.mouse_x, gfx.mouse_y) then
                popover = false      -- a click outside closes the popover and does nothing else
                press_target = "closed_popover"
            end
        elseif not down and mouse_was_down then
            local target = which_target()
            if target and target == press_target then
                if target == "info" then
                    popover = not popover
                elseif not popover then
                    if target == "replace" or target == "merge" or target == "skip" then
                        mode = target
                    elseif target == "ok" then
                        finish(true)
                        return
                    elseif target == "cancel" then
                        finish(false)
                        return
                    end
                end
            end
            press_target = nil
        end
        mouse_was_down = down

        -- keyboard
        local key = gfx.getchar()
        if key < 0 then                       -- window closed
            finish(false)
            return
        elseif key == 27 then                 -- Esc: close the popover first
            if popover then
                popover = false
            else
                finish(false)
                return
            end
        elseif key == 13 then                 -- Enter
            finish(true)
            return
        elseif key == 30064 or key == 1685026670 then   -- Up / Down arrow
            local order = { merge = 1, replace = 2, skip = 3 }
            local names = { "merge", "replace", "skip" }
            local step = (key == 30064) and -1 or 1
            mode = names[math.max(1, math.min(3, order[mode] + step))]
        end

        gfx.update()
        reaper.defer(loop)
    end

    loop()
end


------------------------------------------------------------
-- Main
------------------------------------------------------------

local function abort(text)
    remove_dir(STAGE)
    message(text)
end

local function main()

    if RESOURCE_PATH:find('"', 1, true) then
        message("The REAPER resource path contains a double quote character, which this updater cannot handle.")
        return
    end

    if not file_exists(HELPER) then
        message("Could not find the update helper:\n\n" .. HELPER)
        return
    end

    reaper.RecursiveCreateDirectory(DAN_FOLDER, 0)
    remove_dir(STAGE)
    remove_dir(OLD_STAGE)
    reaper.RecursiveCreateDirectory(STAGE, 0)

    ----------------------------------------------------
    -- Which version is the latest?
    ----------------------------------------------------

    local curl = tool("curl")
    local curl_code, _, curl_raw = run(curl .. " --version", 15000)
    if curl_code == nil then
        curl_code, _, curl_raw = run(curl .. " --version", 0)   -- retry without a time limit
    end
    if curl_code ~= 0 then
        return abort("The tool 'curl' could not be run, so the update could not be downloaded.\n\n" ..
            "Command: " .. curl .. " --version\n" ..
            "REAPER returned: " .. tostring(curl_raw))
    end

    local pointer_path = STAGE .. "/" .. POINTER_FILE
    local ok, err = download(BASE_URL .. POINTER_FILE, pointer_path, 30)
    if not ok then
        return abort("Could not download the version information:\n\n" ..
            BASE_URL .. POINTER_FILE .. "\n\n" .. (err or ""))
    end

    local pointer_lines = split_lines(read_file(pointer_path))
    local archive_name = trim(pointer_lines[1] or "")
    local expected_hash = trim(pointer_lines[2] or ""):lower()

    -- the name comes from the internet: accept only plain file names
    -- (letters, digits, dot, underscore, hyphen and space)
    if not archive_name:match("^[%w%._%- ]+%.ReaperConfigZip$") or archive_name:find("..", 1, true) then
        return abort("The version information (" .. POINTER_FILE .. ") does not contain a valid file name.")
    end
    if expected_hash ~= "" and not (#expected_hash == 64 and expected_hash:match("^%x+$")) then
        return abort("The checksum in " .. POINTER_FILE .. " is not a valid SHA-256.")
    end

    local latest = parse_version(archive_name)
    if not latest then
        return abort("Could not read a version number from:\n\n" .. archive_name)
    end

    -- The recorded version used to live directly in Data: move it to the new folder
    local installed_text = read_file(VERSION_FILE)
    if not installed_text then
        installed_text = read_file(OLD_VERSION_FILE)
        if installed_text and write_file(VERSION_FILE, installed_text) then
            os.remove(OLD_VERSION_FILE)
        end
    end
    local installed = trim((installed_text or ""):match("[^\r\n]*") or "")
    if installed == "" then
        installed = nil
    end

    local configured = has_my_configuration(installed)

    ----------------------------------------------------
    -- Everything after the question. It runs when the person presses OK.
    -- mode is "replace" (full install), "merge" (merge keyboard shortcuts)
    -- or "skip" (reaper-kb.ini is not imported at all).
    ----------------------------------------------------

    local function apply(mode)
        local merge_shortcuts = (mode == "merge")
        local skip_shortcuts  = (mode == "skip")

        ----------------------------------------------------
        -- Download, verify, unpack
        ----------------------------------------------------

        local zip_path = STAGE .. "/config.zip"
        local archive_url = BASE_URL .. archive_name:gsub(" ", "%%20")
        ok, err = download(archive_url, zip_path, 180)
        if not ok then
            return abort("Could not download the configuration:\n\n" ..
                archive_url .. "\n\n" .. (err or ""))
        end

        if expected_hash ~= "" then
            local actual, actual_hash = sha256_of(zip_path)
            if not actual then
                return abort("Could not check the download's checksum, so nothing was changed.")
            end
            if not actual:find(expected_hash, 1, true) then
                return abort("The downloaded file does not match its checksum, so nothing was changed.\n\n" ..
                    "File name:  " .. archive_name .. "\n" ..
                    "Expected:   " .. expected_hash .. "\n" ..
                    "Downloaded: " .. (actual_hash or "(could not be read)") .. "\n\n" ..
                    "Expected is line 2 of latest.txt. It must be the checksum of the exact file uploaded to GitHub.")
            end
        end

        if not extract(zip_path, EXTRACTED) then
            return abort("Could not unpack the downloaded configuration.")
        end
        os.remove(zip_path)

        local files = list_files(EXTRACTED)
        if #files == 0 then
            return abort("The downloaded configuration is empty.")
        end

        -- "Don't touch my keyboard shortcuts": reaper-kb.ini is dropped, so it is
        -- neither backed up nor copied
        if skip_shortcuts then
            os.remove(EXTRACTED .. "/reaper-kb.ini")
            local kept = {}
            for _, rel in ipairs(files) do
                if rel ~= "reaper-kb.ini" then
                    kept[#kept + 1] = rel
                end
            end
            files = kept
        end

        ----------------------------------------------------
        -- Leave their own copies of some files alone
        ----------------------------------------------------

        do
            local leave = {}
            for _, name in ipairs(files_to_leave(configured)) do
                leave[name] = true
                os.remove(EXTRACTED .. "/" .. name)
            end
            local remaining = {}
            for _, rel in ipairs(files) do
                if not leave[rel] then
                    remaining[#remaining + 1] = rel
                end
            end
            files = remaining
        end

        ----------------------------------------------------
        -- Back up the important settings files that are about to change
        ----------------------------------------------------

        remove_dir(BACKUP)
        -- first update of a person who does not have your configuration: keep their own
        -- settings apart, and never overwrite that copy later
        local backup_dir = BACKUP
        if uses_pre_config_backup(configured) then
            backup_dir = PRE_CONFIG_BACKUP
        end
        remove_dir(OLD_BACKUP)     -- backups of earlier versions of this updater
        os.remove(OLD_LOG)
        os.remove(DAN_FOLDER .. "/Update_Log.txt")            -- logs of an earlier test version
        os.remove(DAN_FOLDER .. "/Update_Log_previous.txt")
        for _, rel in ipairs(files) do
            if BACKUP_FILES[rel] then
                local current = RESOURCE_PATH .. "/" .. rel
                if file_exists(current) then
                    if not copy_file(current, backup_dir .. "/" .. rel) then
                        return abort("Could not back up:\n\n" .. current)
                    end
                end
            end
        end

        -- screen sets and monitoring FX are always saved if the person has them
        for _, name in ipairs(ALWAYS_BACKUP_FILES) do
            local current = RESOURCE_PATH .. "/" .. name
            if file_exists(current) then
                if not copy_file(current, backup_dir .. "/" .. name) then
                    return abort("Could not back up:\n\n" .. current)
                end
            end
        end

        ----------------------------------------------------
        -- Prepare the files that are merged instead of replaced
        ----------------------------------------------------

        os.remove(EXTRACTED .. "/reaper-configzip-info")

        local shipped_ini = read_file(EXTRACTED .. "/reaper.ini")
        if shipped_ini then
            local current_ini = read_file(RESOURCE_PATH .. "/reaper.ini") or ""
            local merged_ini = merge_ini(current_ini, shipped_ini)
            if not write_file(STAGE .. "/reaper.ini.merged", merged_ini) then
                return abort("Could not write:\n\n" .. STAGE .. "/reaper.ini.merged")
            end
            os.remove(EXTRACTED .. "/reaper.ini")
        end

        local shipped_theme = read_file(EXTRACTED .. "/" .. THEMECONFIG_FILE)
        if shipped_theme then
            local current_theme = read_file(RESOURCE_PATH .. "/" .. THEMECONFIG_FILE) or ""
            local merged_theme = merge_sections(current_theme, shipped_theme)
            -- written back into the extracted folder, so the helper copies it as a normal file
            if not write_file(EXTRACTED .. "/" .. THEMECONFIG_FILE, merged_theme) then
                return abort("Could not write:\n\n" .. EXTRACTED .. "/" .. THEMECONFIG_FILE)
            end
        end
    
        if merge_shortcuts and file_exists(EXTRACTED .. "/reaper-kb.ini") then
            if not file_exists(MERGE_SCRIPT) then
                return abort("Could not find the keyboard shortcuts merge script:\n\n" .. MERGE_SCRIPT)
            end

            _G.DANIEL_KB_MERGE = {
                shipped_file = EXTRACTED .. "/reaper-kb.ini",
                merged_file  = STAGE .. "/reaper-kb.merged.ini",
            }
            local called, result = pcall(dofile, MERGE_SCRIPT)
            _G.DANIEL_KB_MERGE = nil

            if not called or type(result) ~= "table" or not result.ok then
                return abort("The keyboard shortcuts could not be merged:\n\n" ..
                    tostring(called and result and result.error or result))
            end
            os.remove(EXTRACTED .. "/reaper-kb.ini")
        end

        write_file(STAGE .. "/applied_version.txt", latest .. "\n")

        ----------------------------------------------------
        -- Launch the helper and quit REAPER
        ----------------------------------------------------

        local command
        if IS_WIN then
            command = 'start "" /min cmd /c ""' ..
                native(HELPER) ..
                '" "' ..
                native(RESOURCE_PATH) ..
                '" "' ..
                native(REAPER_EXE) ..
                '""'
        else
            command = 'nohup /bin/bash "' ..
                HELPER ..
                '" "' ..
                RESOURCE_PATH ..
                '" "' ..
                REAPER_EXE ..
                '" >/dev/null 2>&1 &'
        end

        os.execute(command)

        reaper.Main_OnCommand(40004, 0)
    end

    ----------------------------------------------------
    -- Ask
    ----------------------------------------------------

    local function run_update(mode)
        local called, problem = pcall(apply, mode)
        if not called then
            remove_dir(STAGE)
            message("The update stopped because of an error:\n\n" .. tostring(problem))
        end
    end

    show_dialog({
        latest       = latest,
        installed    = installed,
        same_version = (installed ~= nil and compare_versions(installed, latest) == 0),
        leave        = files_to_leave(configured),
        configured   = configured,
        first_backup = uses_pre_config_backup(configured),
    }, run_update, function() remove_dir(STAGE) end)
end

local ok, err = pcall(main)
if not ok then
    remove_dir(STAGE)
    message("The update stopped because of an error:\n\n" .. tostring(err))
end
