local RESOURCE_PATH = reaper.GetResourcePath()
local SETTINGS_FOLDER = RESOURCE_PATH .. "/Personal Settings"
local REAPER_INI = RESOURCE_PATH .. "/reaper.ini"
local SAVE_FILE = SETTINGS_FOLDER .. "/Personal_Settings.ini"


------------------------------------------------------------
-- Read setting from Personal_Settings.ini
------------------------------------------------------------

local function GetSetting(key)

    local file = io.open(SAVE_FILE, "rb")

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
-- Set value in reaper.ini
------------------------------------------------------------

local function SetIniValue(key, value)

    local file = io.open(REAPER_INI, "rb")

    if not file then
        return false
    end

    local contents = file:read("*all")
    file:close()

    local pattern = "\n" .. key .. "=[^\r\n]*"

    local new_contents, count =
        contents:gsub(
            pattern,
            "\n" .. key .. "=" .. value
        )

    -- If the key is the first line of the file
    if count == 0 then

        local first_pattern =
            "^" .. key .. "=[^\r\n]*"

        new_contents, count =
            contents:gsub(
                first_pattern,
                key .. "=" .. value
            )
    end

    -- If the key doesn't already exist, add it
    -- to the [reaper] section.
    if count == 0 then

        local section_start =
            contents:find("\n%[reaper%]\r?\n")

        if not section_start then
            return false
        end

        local insert_position =
            contents:find(
                "\n",
                section_start + 1
            )

        if not insert_position then
            return false
        end

        new_contents =
            contents:sub(1, insert_position) ..
            key .. "=" .. value .. "\n" ..
            contents:sub(insert_position + 1)
    end


    --------------------------------------------------------
    -- Write updated reaper.ini
    --------------------------------------------------------

    file = io.open(REAPER_INI, "wb")

    if not file then
        return false
    end

    file:write(new_contents)
    file:close()

    return true
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


    local destination_file =
        io.open(destination, "wb")

    if not destination_file then
        return false
    end

    destination_file:write(data)
    destination_file:close()

    return true
end


------------------------------------------------------------
-- Check that Personal_Settings.ini exists
------------------------------------------------------------

local settings_file =
    io.open(SAVE_FILE, "rb")

if not settings_file then

    reaper.ShowMessageBox(
        "Could not find:\n\n" ..
        SAVE_FILE,
        "Personal Config",
        0
    )

    return
end

settings_file:close()


------------------------------------------------------------
-- Read saved REAPER settings
------------------------------------------------------------

local splashimage = GetSetting("splashimage")
local newprojtmpl  = GetSetting("newprojtmpl")
local vstpath      = GetSetting("vstpath")


------------------------------------------------------------
-- Restore settings to reaper.ini
------------------------------------------------------------

local splash_restored = false
local project_restored = false
local vst_restored = false


if splashimage ~= nil then
    splash_restored =
        SetIniValue(
            "splashimage",
            splashimage
        )
end


if newprojtmpl ~= nil then
    project_restored =
        SetIniValue(
            "newprojtmpl",
            newprojtmpl
        )
end


if vstpath ~= nil then
    vst_restored =
        SetIniValue(
            "vstpath",
            vstpath
        )
end


------------------------------------------------------------
-- File paths
------------------------------------------------------------

local screensets_source =
    SETTINGS_FOLDER .. "/reaper-screensets.ini"

local screensets_destination =
    RESOURCE_PATH .. "/reaper-screensets.ini"


local sws_autocolor_source =
    SETTINGS_FOLDER .. "/sws-autocoloricon.ini"

local sws_autocolor_destination =
    RESOURCE_PATH .. "/sws-autocoloricon.ini"


local vstplugins_source =
    SETTINGS_FOLDER .. "/reaper-vstplugins64.ini"

local vstplugins_destination =
    RESOURCE_PATH .. "/reaper-vstplugins64.ini"


local vstshells_source =
    SETTINGS_FOLDER .. "/reaper-vstshells64.ini"

local vstshells_destination =
    RESOURCE_PATH .. "/reaper-vstshells64.ini"


------------------------------------------------------------
-- Restore files
------------------------------------------------------------

local screensets_restored =
    CopyFile(
        screensets_source,
        screensets_destination
    )


local sws_autocolor_restored =
    CopyFile(
        sws_autocolor_source,
        sws_autocolor_destination
    )


local vstplugins_restored =
    CopyFile(
        vstplugins_source,
        vstplugins_destination
    )


local vstshells_restored =
    CopyFile(
        vstshells_source,
        vstshells_destination
    )


------------------------------------------------------------
-- Display result
------------------------------------------------------------

local message =
    "Personal REAPER settings restored.\n\n" ..

    "Splash screen: " ..
    (splash_restored and "Restored" or "Failed") ..
    "\n" ..

    "Default project: " ..
    (project_restored and "Restored" or "Failed") ..
    "\n" ..

    "VST paths: " ..
    (vst_restored and "Restored" or "Failed") ..
    "\n\n" ..

    "Files:\n" ..

    "reaper-screensets.ini: " ..
    (screensets_restored and "Restored" or "Not found") ..
    "\n" ..

    "sws-autocoloricon.ini: " ..
    (sws_autocolor_restored and "Restored" or "Not found") ..
    "\n\n" ..

    "VST scan database:\n" ..
    
    "reaper-vstplugins64.ini: " ..
    (vstplugins_restored and "Restored" or "Not found") ..
    "\n" ..

    "reaper-vstshells64.ini: " ..
    (vstshells_restored and "Restored" or "Not found")


reaper.ShowMessageBox(
    message,
    "Settings Restored",
    0
)
