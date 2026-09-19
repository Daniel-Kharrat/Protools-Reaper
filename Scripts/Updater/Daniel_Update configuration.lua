-- Daniel_Update configuration.lua
--
-- Updates an existing installation to the latest published configuration.
--
--   1. Downloads Configurations/latest.txt from GitHub. Line 1 names the newest
--      .ReaperConfigZip; an optional line 2 holds its SHA-256.
--   2. Asks: Full install (replace everything) or Merge keyboard shortcuts.
--   3. Downloads and unpacks the archive into Data/Daniel_Update (staging).
--   4. Prepares merged files, backs up everything that will change, and quits REAPER.
--   5. Daniel_Update_configuration.bat / .sh waits for REAPER to close, copies the
--      staged files into the resource folder, and relaunches REAPER.
--
-- Nothing in the resource folder changes until REAPER has closed. Any failure
-- before that point cleans up the staging folder and leaves REAPER running.
--
-- Files are replaced as they are, EXCEPT:
--   reaper.ini       merged key by key: yours replace theirs, everything else of
--                    theirs stays. Never touched: the audio setup ([audioconfig]),
--                    their toolbar toggle states, and the audio / MIDI device,
--                    window position and folder path keys listed below.
--                    A blank value in your file never overwrites theirs.
--   reaper-kb.ini    replaced in a Full install; in "Merge keyboard shortcuts" it
--                    is merged by Daniel_Merge keyboard shortcuts.lua instead.
--   reaper-configzip-info is never copied.


------------------------------------------------------------
-- Settings
------------------------------------------------------------

local BASE_URL = "https://raw.githubusercontent.com/Daniel-Kharrat/Protools-Reaper/master/Configurations/"
local POINTER_FILE = "latest.txt"

local TITLE = "Update Configuration"

-- reaper.ini: whole sections that are never touched
local KEEP_SECTIONS = {
    ["audioconfig"] = true,             -- audio device, inputs/outputs, sample rate, buffer sizes
    ["toolbar button states"] = true,   -- their own toolbar toggle states
}

-- reaper.ini, section [reaper]: keys that stay theirs (Lua patterns)
local KEEP_KEYS_SECTION = "reaper"
local KEEP_KEYS = {
    -- audio
    "^alsa_", "^linux_audio_", "^jack_", "^audiocloseinactive", "^audiothreadpr$",
    -- MIDI devices
    "^midiins$", "^midiouts$", "^midiinflag%d+$",
    -- window position and size
    "^wnd_[xywh]$", "^wnd_state$", "^fullscreenRect",
    -- folders and files on their machine
    "path$", "paths$", "pathlist$", "dir$", "^vstpath", "^lv2path",
    "^newprojtmpl$", "^splashimage$",
}


------------------------------------------------------------
-- Paths
------------------------------------------------------------

local RESOURCE_PATH = reaper.GetResourcePath():gsub("\\", "/")
local OS = reaper.GetOS()
local IS_WIN = OS:find("Win") ~= nil
local IS_MAC = OS:find("OSX") ~= nil or OS:find("macOS") ~= nil

local DATA_FOLDER  = RESOURCE_PATH .. "/Data"
local STAGE        = DATA_FOLDER .. "/Daniel_Update"
local EXTRACTED    = STAGE .. "/extracted"
local BACKUP       = DATA_FOLDER .. "/Daniel_Update_Backup"
local VERSION_FILE = DATA_FOLDER .. "/Daniel_Config_Version.txt"

local UPDATER_DIR  = RESOURCE_PATH .. "/Scripts/Daniel Kharrat/Updater"
local MERGE_SCRIPT = UPDATER_DIR .. "/Daniel_Merge keyboard shortcuts.lua"
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

-- Runs a command line. Returns the exit code (or nil) and its output.
local function run(command, timeout_ms)
    local result = reaper.ExecProcess(command, timeout_ms or 60000)
    if not result then
        return nil, ""
    end
    local code, output = result:match("^(%-?%d+)\n?(.*)$")
    return tonumber(code), output or ""
end

-- Deletes a staging or backup folder. Refuses any other path.
local function remove_dir(path)
    if not path:find("Daniel_Update", 1, true) then
        return
    end
    if IS_WIN then
        run("cmd.exe /c if exist " .. q(path) .. " rmdir /s /q " .. q(path), 60000)
    else
        run("rm -rf " .. q(path), 60000)
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
    local command = "curl -f -s -S -L --connect-timeout 15 --max-time " .. max_seconds ..
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
        command = "shasum -a 256 " .. q(path)
    else
        command = "sha256sum " .. q(path)
    end
    local code, output = run(command, 120000)
    if code ~= 0 then
        return nil
    end
    return (output:gsub("%s", ""):lower())
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
            "unzip -q -o " .. q(zip_path) .. " -d " .. q(destination),
            "tar -xf " .. q(zip_path) .. " -C " .. q(destination),
            "python3 -m zipfile -e " .. q(zip_path) .. " " .. q(destination),
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

local function keep_key(section, key)
    if section ~= KEEP_KEYS_SECTION then
        return false
    end
    for _, pattern in ipairs(KEEP_KEYS) do
        if key:find(pattern) then
            return true
        end
    end
    return false
end

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

    local section, skip = nil, false

    for _, line in ipairs(shipped) do
        local name = line:match("^%[(.-)%]%s*$")
        if name then
            section = name
            skip = KEEP_SECTIONS[name] or false
            if not skip and not sections[name] and not new_by_name[name] then
                local entry = { name = name, lines = {} }
                new_sections[#new_sections + 1] = entry
                new_by_name[name] = entry
            end
        elseif section and not skip then
            local key, value = line:match("^([^=]+)=(.*)$")
            if key then
                if value == "" or keep_key(section, key) then
                    stats.kept = stats.kept + 1
                elseif sections[section] then
                    local at = sections[section].keys[key]
                    if at then
                        if target[at] ~= line then
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

    reaper.RecursiveCreateDirectory(DATA_FOLDER, 0)
    remove_dir(STAGE)
    reaper.RecursiveCreateDirectory(STAGE, 0)

    ----------------------------------------------------
    -- Which version is the latest?
    ----------------------------------------------------

    local code = run("curl --version", 15000)
    if code ~= 0 then
        return abort("The tool 'curl' was not found, so the update could not be downloaded.")
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

    local installed = trim((read_file(VERSION_FILE) or ""):match("[^\r\n]*") or "")
    if installed == "" then
        installed = nil
    end

    ----------------------------------------------------
    -- Ask
    ----------------------------------------------------

    local text = ""
    if installed and compare_versions(installed, latest) == 0 then
        text = "You already have this version.\n\n"
    end

    text = text ..
        "Latest configuration: v" .. latest .. "\n" ..
        "Installed: " .. (installed and ("v" .. installed) or "not recorded") .. "\n\n" ..

        "YES = Full install\n" ..
        "Replaces everything, including your keyboard shortcuts and action list.\n\n" ..

        "NO = Merge keyboard shortcuts\n" ..
        "Replaces everything else. Your own shortcuts and scripts stay, and mine are merged in.\n\n" ..

        "CANCEL = Do nothing\n\n" ..

        "Your audio and MIDI devices, window position and folder paths are always kept.\n" ..
        "REAPER will close and restart to apply the update."

    local answer = reaper.ShowMessageBox(text, TITLE, 3)
    if answer ~= 6 and answer ~= 7 then
        remove_dir(STAGE)
        return
    end
    local merge_shortcuts = (answer == 7)

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
        local actual = sha256_of(zip_path)
        if not actual then
            return abort("Could not check the download's checksum, so nothing was changed.")
        end
        if not actual:find(expected_hash, 1, true) then
            return abort("The downloaded file does not match its checksum, so nothing was changed.")
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

    ----------------------------------------------------
    -- Back up everything that is about to change
    ----------------------------------------------------

    remove_dir(BACKUP)
    for _, rel in ipairs(files) do
        if rel ~= "reaper-configzip-info" then
            local current = RESOURCE_PATH .. "/" .. rel
            if file_exists(current) then
                if not copy_file(current, BACKUP .. "/" .. rel) then
                    return abort("Could not back up:\n\n" .. current)
                end
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
            '""'
    else
        command = 'nohup /bin/bash "' ..
            HELPER ..
            '" "' ..
            RESOURCE_PATH ..
            '" >/dev/null 2>&1 &'
    end

    os.execute(command)

    reaper.Main_OnCommand(40004, 0)
end

local ok, err = pcall(main)
if not ok then
    remove_dir(STAGE)
    message("The update stopped because of an error:\n\n" .. tostring(err))
end
