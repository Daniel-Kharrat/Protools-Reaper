local RESOURCE_PATH = reaper.GetResourcePath()

------------------------------------------------------------
-- Detect operating system
------------------------------------------------------------

local OS = reaper.GetOS()

if OS:find("Win") then

    reaper.ShowMessageBox(
        "Windows is not supported yet.\n\n" ..
        "The toolbar icon updater currently supports macOS and Linux only.",
        "Toolbar Icons",
        0
    )

    return

end


------------------------------------------------------------
-- Update helper path
------------------------------------------------------------

local update_script =
    RESOURCE_PATH ..
    "/Scripts/Daniel Kharrat/Updater/Daniel_Replace toolbar_icons.sh"


------------------------------------------------------------
-- Check that update helper exists
------------------------------------------------------------

local script_file =
    io.open(update_script, "rb")

if not script_file then

    reaper.ShowMessageBox(
        "Could not find the toolbar icon updater:\n\n" ..
        update_script,
        "Toolbar Icons",
        0
    )

    return

end

script_file:close()


------------------------------------------------------------
-- Launch updater
------------------------------------------------------------

local command =
    'nohup /bin/bash "' ..
    update_script ..
    '" "' ..
    RESOURCE_PATH ..
    '" >/dev/null 2>&1 &'

os.execute(command)


------------------------------------------------------------
-- Quit REAPER
------------------------------------------------------------

reaper.Main_OnCommand(40004, 0)
