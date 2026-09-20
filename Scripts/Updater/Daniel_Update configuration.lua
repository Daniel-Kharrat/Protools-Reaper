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
-- Existing configuration: if the person already has your configuration (there is a
-- recorded version, or your repository is in their reapack.ini), the files in
-- KEEP_IF_CONFIGURED are NOT copied, so their own screen sets, SWS auto colors,
-- S&M settings and ReaPack repositories stay. On a first installation
-- everything is copied.


------------------------------------------------------------
-- Settings
------------------------------------------------------------

local BASE_URL = "https://raw.githubusercontent.com/Daniel-Kharrat/Protools-Reaper/master/Configurations/"
local POINTER_FILE = "latest.txt"

local TITLE = "Update Configuration"

-- Your ReaPack repository (as it appears in the URL in reapack.ini). If it is there,
-- the person already has your configuration.
local MY_REPOSITORY = "Daniel-Kharrat/Protools-Reaper"

-- Files that are copied on a first installation only. Once the person has your
-- configuration they are left alone.
local KEEP_IF_CONFIGURED = {
    "reaper-screensets.ini",
    "sws-autocoloricon.ini",
    "S&M.ini",
    "reapack.ini",
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

-- Deletes a staging or backup folder. Refuses any other path.
local function remove_dir(path)
    if not path:find("Daniel_Update", 1, true) then
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

local function repository_in_reapack()
    local reapack = read_file(RESOURCE_PATH .. "/reapack.ini")
    return reapack ~= nil and reapack:lower():find(MY_REPOSITORY:lower(), 1, true) ~= nil
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

    local installed = trim((read_file(VERSION_FILE) or ""):match("[^\r\n]*") or "")
    if installed == "" then
        installed = nil
    end

    -- an installed version was recorded by an earlier update, or your repository
    -- is in their ReaPack list (older installs made by importing the configuration)
    local configured = (installed ~= nil) or repository_in_reapack()

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

        "Settings in your own reaper.ini that are not part of the configuration are kept.\n" ..
        (configured
            and "Existing configuration found: your screen sets, SWS auto colors, S&M settings and ReaPack repositories are kept.\n"
            or  "First installation: all files are copied.\n") ..
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

    ----------------------------------------------------
    -- Existing configuration: leave their own copies of some files alone
    ----------------------------------------------------

    if configured then
        local leave = {}
        for _, name in ipairs(KEEP_IF_CONFIGURED) do
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
