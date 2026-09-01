local RESOURCE_PATH = reaper.GetResourcePath()
local SETTINGS_FOLDER = RESOURCE_PATH .. "/Personal Settings"
local REAPER_INI = RESOURCE_PATH .. "/reaper.ini"
local SAVE_FILE = SETTINGS_FOLDER .. "/Personal_Settings.ini"


------------------------------------------------------------
-- Create Personal Settings folder if it doesn't exist
------------------------------------------------------------

reaper.RecursiveCreateDirectory(SETTINGS_FOLDER, 0)


------------------------------------------------------------
-- Read exact REAPER ini key
------------------------------------------------------------

local function GetIniValue(key)

    local file = io.open(REAPER_INI, "rb")

    if not file then
        return nil
    end

    local contents = file:read("*all")
    file:close()

    local pattern = "\n" .. key .. "=([^\r\n]*)"
    local value = contents:match(pattern)

    if value == nil then
        value = contents:match("^" .. key .. "=([^\r\n]*)")
    end

    return value
end


------------------------------------------------------------
-- Copy a file
------------------------------------------------------------

local function CopyFile(source, destination)

    local source_file = io.open(source, "rb")

    if not source_file then
        return false
    end

    local data = source_file:read("*all")
    source_file:close()

    local destination_file = io.open(destination, "wb")

    if not destination_file then
        return false
    end

    destination_file:write(data)
    destination_file:close()

    return true
end


------------------------------------------------------------
-- Read settings from reaper.ini
------------------------------------------------------------

local splashimage = GetIniValue("splashimage")
local newprojtmpl  = GetIniValue("newprojtmpl")
local vstpath      = GetIniValue("vstpath")


------------------------------------------------------------
-- Convert missing values to empty strings
------------------------------------------------------------

if splashimage == nil then
    splashimage = ""
end

if newprojtmpl == nil then
    newprojtmpl = ""
end

if vstpath == nil then
    vstpath = ""
end


------------------------------------------------------------
-- Save settings to Personal_Settings.ini
------------------------------------------------------------

local file = io.open(SAVE_FILE, "w")

if not file then

    reaper.ShowMessageBox(
        "Could not create:\n\n" ..
        SAVE_FILE,
        "Personal Config",
        0
    )

    return
end


file:write("[PERSONAL]\n")
file:write("splashimage=" .. splashimage .. "\n")
file:write("newprojtmpl=" .. newprojtmpl .. "\n")
file:write("vstpath=" .. vstpath .. "\n")

file:close()


------------------------------------------------------------
-- File paths
------------------------------------------------------------

local screensets_source =
    RESOURCE_PATH .. "/reaper-screensets.ini"

local screensets_destination =
    SETTINGS_FOLDER .. "/reaper-screensets.ini"


local sws_autocolor_source =
    RESOURCE_PATH .. "/sws-autocoloricon.ini"

local sws_autocolor_destination =
    SETTINGS_FOLDER .. "/sws-autocoloricon.ini"


local keyboard_source =
    RESOURCE_PATH .. "/reaper-kb.ini"

local keyboard_destination =
    SETTINGS_FOLDER .. "/reaper-kb.ini"


local mouse_source =
    RESOURCE_PATH .. "/reaper-mouse.ini"

local mouse_destination =
    SETTINGS_FOLDER .. "/reaper-mouse.ini"


------------------------------------------------------------
-- Copy files
------------------------------------------------------------

local screensets_saved =
    CopyFile(
        screensets_source,
        screensets_destination
    )


local sws_autocolor_saved =
    CopyFile(
        sws_autocolor_source,
        sws_autocolor_destination
    )


local keyboard_saved =
    CopyFile(
        keyboard_source,
        keyboard_destination
    )


local mouse_saved =
    CopyFile(
        mouse_source,
        mouse_destination
    )


------------------------------------------------------------
-- Display result
------------------------------------------------------------

local message =
    "Personal REAPER settings saved.\n\n" ..

    "Splash screen:\n" ..
    (splashimage ~= "" and splashimage or "(none)") ..
    "\n\n" ..

    "Default project:\n" ..
    (newprojtmpl ~= "" and newprojtmpl or "(none)") ..
    "\n\n" ..

    "VST paths:\n" ..
    (vstpath ~= "" and vstpath or "(none)") ..
    "\n\n" ..

    "Files:\n" ..

    "reaper-screensets.ini: " ..
    (screensets_saved and "Saved" or "Not found") ..
    "\n" ..

    "sws-autocoloricon.ini: " ..
    (sws_autocolor_saved and "Saved" or "Not found") ..
    "\n\n" ..

    "Backup-only files:\n" ..

    "reaper-kb.ini: " ..
    (keyboard_saved and "Saved" or "Not found") ..
    "\n" ..

    "reaper-mouse.ini: " ..
    (mouse_saved and "Saved" or "Not found") ..
    "\n\n" ..

    "Saved to:\n" ..
    SETTINGS_FOLDER


reaper.ShowMessageBox(
    message,
    "Settings Saved",
    0
)
