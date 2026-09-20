-- Daniel_Restore personal settings.lua
--
-- Restores what Daniel_Save personal settings.lua (or an update) saved:
--
--   * Every file in Data/Daniel Kharrat/Backup is copied back into the REAPER
--     resource folder, under the same name.
--   * Every setting in Data/Daniel Kharrat/Personal_Settings.ini is written to the
--     [REAPER] section of reaper.ini. If that file does not exist there is nothing
--     to write, and it is simply skipped. Settings added to that file later are
--     restored too, without changing this script.
--
-- REAPER rewrites reaper.ini from memory when it quits, so nothing is changed in
-- the resource folder right now. The files are prepared in Data/Daniel Kharrat/Restore,
-- then REAPER quits. Its helper (Daniel_Restore_ini_files.bat / .sh) waits for REAPER to
-- close, copies the prepared files into the resource folder and relaunches REAPER.

local TITLE = "Restore Personal Settings"

local RESOURCE_PATH = reaper.GetResourcePath():gsub("\\", "/")
local OS      = reaper.GetOS()
local IS_WIN  = OS:find("Win") ~= nil

local DAN_FOLDER    = RESOURCE_PATH .. "/Data/Daniel Kharrat"
local BACKUP_FOLDER = DAN_FOLDER .. "/Backup"
local SETTINGS_FILE = DAN_FOLDER .. "/Personal_Settings.ini"
local STAGE         = DAN_FOLDER .. "/Restore"
local STAGED_FILES  = STAGE .. "/files"          -- mirrors the resource folder

local UPDATER_DIR = RESOURCE_PATH .. "/Scripts/Daniel Kharrat/Updater"
local HELPER = UPDATER_DIR .. (IS_WIN and "/Daniel_Restore_ini_files.bat"
                                       or "/Daniel_Restore_ini_files.sh")
local REAPER_EXE = (reaper.GetExePath():gsub("\\", "/")) .. (IS_WIN and "/reaper.exe" or "/reaper")


------------------------------------------------------------
-- Helpers
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

-- Copies a file, creating the destination folder if needed
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

-- Deletes the Restore staging folder. Refuses any other path.
local function remove_stage()
    if STAGE:sub(-8) ~= "/Restore" or not STAGE:find("Daniel Kharrat", 1, true) then
        return
    end
    if IS_WIN then
        reaper.ExecProcess("cmd.exe /c if exist " .. q(STAGE) .. " rmdir /s /q " .. q(STAGE), 60000)
    else
        for _, folder in ipairs({ "/bin", "/usr/bin" }) do
            if file_exists(folder .. "/rm") then
                reaper.ExecProcess(folder .. "/rm -rf " .. q(STAGE), 60000)
                return
            end
        end
        reaper.ExecProcess("rm -rf " .. q(STAGE), 60000)
    end
end

-- Every file below root, as paths relative to root (hidden files are skipped)
local function list_files(root, rel, out)
    rel = rel or ""
    out = out or {}
    local dir = (rel == "") and root or (root .. "/" .. rel)

    local i = 0
    while true do
        local name = reaper.EnumerateFiles(dir, i)
        if not name then
            break
        end
        if name:sub(1, 1) ~= "." then
            out[#out + 1] = (rel == "") and name or (rel .. "/" .. name)
        end
        i = i + 1
    end

    i = 0
    while true do
        local sub = reaper.EnumerateSubdirectories(dir, i)
        if not sub then
            break
        end
        list_files(root, (rel == "") and sub or (rel .. "/" .. sub), out)
        i = i + 1
    end

    return out
end

-- The settings in Personal_Settings.ini ([PERSONAL] section), in file order
local function read_settings(path)
    local text = read_file(path)
    local settings = {}
    if not text then
        return settings
    end
    local in_personal = false
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        local section = line:match("^%[(.-)%]%s*$")
        if section then
            in_personal = (section:upper() == "PERSONAL")
        elseif in_personal then
            local key, value = line:match("^([^=;#][^=]*)=(.*)$")
            if key then
                settings[#settings + 1] = { key = key, value = value }
            end
        end
    end
    return settings
end

-- Sets key=value in the [REAPER] section of a reaper.ini text. Returns the new text,
-- or nil if the file has no [REAPER] section.
local function set_ini_value(text, key, value)
    local eol = text:find("\r\n", 1, true) and "\r\n" or "\n"

    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        lines[#lines + 1] = line
    end
    if lines[#lines] == "" then
        lines[#lines] = nil
    end

    local in_reaper, header, found = false, nil, false
    for i, line in ipairs(lines) do
        local section = line:match("^%[(.-)%]%s*$")
        if section then
            in_reaper = (section:lower() == "reaper")
            if in_reaper and not header then
                header = i
            end
        elseif in_reaper and not found then
            local name = line:match("^([^=]+)=")
            if name == key then
                lines[i] = key .. "=" .. value
                found = true
            end
        end
    end

    if not found then
        if not header then
            return nil
        end
        table.insert(lines, header + 1, key .. "=" .. value)
    end

    return table.concat(lines, eol) .. eol
end


------------------------------------------------------------
-- What is there to restore?
------------------------------------------------------------

if not file_exists(HELPER) then
    message("Could not find the restore helper:\n\n" .. HELPER)
    return
end

local files = list_files(BACKUP_FOLDER)
table.sort(files)

local settings = read_settings(SETTINGS_FILE)

if #files == 0 and #settings == 0 then
    message("There is nothing to restore.\n\n" ..
        "Nothing was found in Data/Daniel Kharrat/Backup, and there are no saved settings in " ..
        "Data/Daniel Kharrat/Personal_Settings.ini.")
    return
end


------------------------------------------------------------
-- Confirm
------------------------------------------------------------

local summary = "This will restore your saved settings.\n"

if #files > 0 then
    summary = summary .. "\nFiles from Data/Daniel Kharrat/Backup:\n"
    for i, name in ipairs(files) do
        if i > 15 then
            summary = summary .. "and " .. (#files - 15) .. " more\n"
            break
        end
        summary = summary .. "  " .. name .. "\n"
    end
end

if #settings > 0 then
    summary = summary .. "\nSettings written to reaper.ini:\n"
    for _, setting in ipairs(settings) do
        summary = summary .. "  " .. setting.key .. "=" .. setting.value .. "\n"
    end
end

summary = summary .. "\nREAPER will close and restart to apply the restore.\n\nContinue?"

-- 1 = OK, 2 = Cancel
if reaper.ShowMessageBox(summary, TITLE, 1) ~= 1 then
    return
end


------------------------------------------------------------
-- Prepare the files
------------------------------------------------------------

remove_stage()
reaper.RecursiveCreateDirectory(STAGED_FILES, 0)

local function fail(text)
    remove_stage()
    message(text)
end

for _, name in ipairs(files) do
    if not copy_file(BACKUP_FOLDER .. "/" .. name, STAGED_FILES .. "/" .. name) then
        fail("Could not prepare:\n\n" .. BACKUP_FOLDER .. "/" .. name)
        return
    end
end

-- reaper.ini: start from the backed up one if there is one, otherwise from the current
-- one, then write the saved settings into it
if #settings > 0 then
    local staged_ini = STAGED_FILES .. "/reaper.ini"
    local ini_text = read_file(staged_ini) or read_file(RESOURCE_PATH .. "/reaper.ini")
    if not ini_text then
        fail("Could not read:\n\n" .. RESOURCE_PATH .. "/reaper.ini")
        return
    end

    for _, setting in ipairs(settings) do
        local changed = set_ini_value(ini_text, setting.key, setting.value)
        if not changed then
            fail("reaper.ini has no [REAPER] section, so the settings could not be restored.")
            return
        end
        ini_text = changed
    end

    if not write_file(staged_ini, ini_text) then
        fail("Could not write:\n\n" .. staged_ini)
        return
    end
end


------------------------------------------------------------
-- Launch the helper and quit REAPER
------------------------------------------------------------

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
