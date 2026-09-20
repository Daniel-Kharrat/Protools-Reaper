-- Daniel_Save personal settings.lua
--
-- Saves the person's own settings, so they can be restored after the configuration
-- has been imported:
--
--   * reaper-screensets.ini (screen sets) and reaper-hwoutfx.ini (monitoring FX) are
--     copied into Data/Daniel Kharrat/Backup, replacing the copies already there.
--   * The record and save settings from reaper.ini are written to
--     Data/Daniel Kharrat/Personal_Settings.ini. That file is not in the Backup
--     folder, so an update (which replaces the Backup folder) does not remove it.
--     A setting that reaper.ini does not have is left out of the file.

local RESOURCE_PATH = reaper.GetResourcePath()
local DAN_FOLDER    = RESOURCE_PATH .. "/Data/Daniel Kharrat"
local BACKUP_FOLDER = DAN_FOLDER .. "/Backup"
local REAPER_INI    = RESOURCE_PATH .. "/reaper.ini"
local SAVE_FILE     = DAN_FOLDER .. "/Personal_Settings.ini"

local TITLE = "Personal Settings Saved"

-- Files copied into the Backup folder (if they exist)
local FILES = {
    "reaper-screensets.ini",
    "reaper-hwoutfx.ini",
}

-- reaper.ini values saved to Personal_Settings.ini, and how they are shown
local SETTINGS = {
    { key = "deftrackrecflags", label = "Default record configuration" },
    { key = "deftrackrecinput", label = "Default record input" },
    { key = "saveFlags",        label = "Save project options" },
}


------------------------------------------------------------
-- Helpers
------------------------------------------------------------

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

-- Copies a file. Returns false if the source does not exist or the copy fails.
local function copy_file(source, destination)
    local data = read_file(source)
    if not data then
        return false
    end
    return write_file(destination, data)
end

-- Value of a key in the [REAPER] section of reaper.ini (nil if it is not there)
local function get_ini_value(ini_text, key)
    local in_reaper = false
    for line in (ini_text .. "\n"):gmatch("(.-)\r?\n") do
        local section = line:match("^%[(.-)%]%s*$")
        if section then
            in_reaper = (section:lower() == "reaper")
        elseif in_reaper then
            local name, value = line:match("^([^=]+)=(.*)$")
            if name == key then
                return value
            end
        end
    end
    return nil
end


------------------------------------------------------------
-- Folders
------------------------------------------------------------

reaper.RecursiveCreateDirectory(BACKUP_FOLDER, 0)


------------------------------------------------------------
-- Save the settings from reaper.ini
------------------------------------------------------------

local ini_text = read_file(REAPER_INI)
if not ini_text then
    reaper.ShowMessageBox("Could not read:\n\n" .. REAPER_INI, TITLE, 0)
    return
end

local values = {}
local lines = { "[PERSONAL]" }
for _, setting in ipairs(SETTINGS) do
    local value = get_ini_value(ini_text, setting.key)
    values[setting.key] = value
    if value ~= nil then
        lines[#lines + 1] = setting.key .. "=" .. value
    end
end

if not write_file(SAVE_FILE, table.concat(lines, "\n") .. "\n") then
    reaper.ShowMessageBox("Could not create:\n\n" .. SAVE_FILE, TITLE, 0)
    return
end


------------------------------------------------------------
-- Copy the files into the Backup folder
------------------------------------------------------------

local saved = {}
for _, name in ipairs(FILES) do
    saved[name] = copy_file(RESOURCE_PATH .. "/" .. name, BACKUP_FOLDER .. "/" .. name)
end


------------------------------------------------------------
-- Result
------------------------------------------------------------

local message = "Preferences:\n"

for _, setting in ipairs(SETTINGS) do
    local value = values[setting.key]
    message = message .. setting.label .. ": " ..
        (value ~= nil and value or "(not set)") .. "\n"
end

message = message .. "\nSaved to: Data/Daniel Kharrat/Personal_Settings.ini"
message = message .. "\n=======================\n"
message = message .. "\nFiles:\n"

for _, name in ipairs(FILES) do
    message = message .. name .. ": " ..
        (saved[name] and "Saved" or "Not found") .. "\n"
end

message = message .. "\nSaved to: Data/Daniel Kharrat/Backup"

reaper.ShowMessageBox(message, TITLE, 0)
