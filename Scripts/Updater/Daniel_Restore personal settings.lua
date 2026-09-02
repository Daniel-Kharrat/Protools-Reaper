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
local newprojtmpl = GetSetting("newprojtmpl")
local vstpath = GetSetting("vstpath")
local vstpath64 = GetSetting("vstpath64")
local vstpath_arm64 = GetSetting("vstpath_arm64")


------------------------------------------------------------
-- Restore settings to reaper.ini
------------------------------------------------------------

local splash_restored = false
local project_restored = false
local vst_restored = false
local vst64_restored = false
local vst_arm64_restored = false


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

if vstpath64 ~= nil then
    vst64_restored =
          SetIniValue(
              "vstpath64",
              vstpath64
        )
end

if vstpath_arm64 ~= nil then
    vst_arm64_restored =
        SetIniValue(
            "vstpath_arm64",
            vstpath_arm64
        )
end


------------------------------------------------------------
-- Restore helper path
------------------------------------------------------------

local restore_script =
    RESOURCE_PATH ..
    "/Scripts/Daniel Kharrat/Updater/Daniel_Restore_ini_files.sh"


------------------------------------------------------------
-- Check that restore helper exists
------------------------------------------------------------

local restore_script_file =
    io.open(restore_script, "rb")

if not restore_script_file then

    reaper.ShowMessageBox(
        "Could not find the restore helper:\n\n" ..
        restore_script,
        "Settings Restore",
        0
    )

    return
end

restore_script_file:close()


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
    "\n" ..
    
    "VST 64-bit paths: " ..
    (vst64_restored and "Restored" or "Failed") ..
    "\n" ..
    
    "VST ARM64 paths: " ..
    (vst_arm64_restored and "Restored" or "Failed")


reaper.ShowMessageBox(
    message,
    "Settings Restored",
    0
)


------------------------------------------------------------
-- Launch restore helper in background
------------------------------------------------------------

local command =
    'nohup /bin/bash "' ..
    restore_script ..
    '" "' ..
    RESOURCE_PATH ..
    '" >/dev/null 2>&1 &'

os.execute(command)


------------------------------------------------------------
-- Quit REAPER
------------------------------------------------------------

reaper.Main_OnCommand(40004, 0)
