local RESOURCE_PATH = reaper.GetResourcePath()
local OS = reaper.GetOS()

if OS == "Other" then
    local f = io.open("/proc/version", "r")
    if f then
        f:close()
        OS = "Linux"
    end
end

-- ------------------------------------------------------------
-- Windows
-- ------------------------------------------------------------

if OS:find("Win") then
    reaper.ShowMessageBox(
        "Windows is not supported yet.\n\n" ..
        "The toolbar icon updater currently supports macOS and Linux only.",
        "Toolbar Icons",
        0
    )
    return
end

-- ------------------------------------------------------------
-- Updater script
-- ------------------------------------------------------------

local update_script =
    RESOURCE_PATH ..
    "/Scripts/Daniel Kharrat/Updater/Daniel_Replace toolbar_icons.sh"

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

-- ------------------------------------------------------------
-- Terminal command
-- ------------------------------------------------------------

local command =
    'bash "' ..
    update_script ..
    '" "' ..
    RESOURCE_PATH ..
    '"; ' ..
    'STATUS=$?; ' ..
    'if [ "$STATUS" -eq 0 ]; then ' ..
    'exit 0; ' ..
    'else ' ..
    'echo ""; ' ..
    'echo "Updater failed. Press Enter to close this window."; ' ..
    'read; ' ..
    'fi; ' ..
    'exit "$STATUS"'

-- ------------------------------------------------------------
-- macOS
-- ------------------------------------------------------------

if OS:find("macOS") then

    local function apple_escape(str)
        str = str:gsub("\\", "\\\\")
        str = str:gsub('"', '\\"')
        return str
    end

    local function shell_single_quote(str)
        return "'" .. str:gsub("'", "'\\''") .. "'"
    end

    local apple_command =
        'tell application "Terminal" to do script "' ..
        apple_escape(command) ..
        '"' ..
        '\ntell application "Terminal" to activate' ..
        '\ntell application "Terminal" to set miniaturized of front window to false' ..
        '\ntell application "Terminal" to set index of front window to 1'

    local osascript_command =
        "/usr/bin/osascript -e " ..
        shell_single_quote(apple_command) ..
        " >/dev/null 2>&1 &"

    os.execute(osascript_command)

-- ------------------------------------------------------------
-- Linux
-- ------------------------------------------------------------
elseif OS:find("Linux") then

    local function shell_single_quote(str)
        return "'" .. str:gsub("'", "'\\''") .. "'"
    end

    local terminal_command =
        "ptyxis -- bash -c " ..
        shell_single_quote(command)

    os.execute(
        terminal_command ..
        " >/dev/null 2>&1 &"
    )

end

-- ------------------------------------------------------------
-- Close REAPER
-- ------------------------------------------------------------

local start_time = reaper.time_precise()

local function close_reaper_after_delay()
    if reaper.time_precise() - start_time >= 2 then
        reaper.Main_OnCommand(40004, 0)
        return
    end

    reaper.defer(close_reaper_after_delay)
end

reaper.defer(close_reaper_after_delay)
