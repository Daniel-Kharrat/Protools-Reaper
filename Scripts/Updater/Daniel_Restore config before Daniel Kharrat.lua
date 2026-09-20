-- Daniel_Restore config before Daniel Kharrat.lua
--
-- Puts back the settings the person had before they used the configuration: every
-- file in Data/Daniel Kharrat/Config Before Daniel Kharrat (saved by the updater on
-- their first update) is copied back into the REAPER resource folder, under the
-- same name.
--
-- It uses the same helper as Daniel_Restore personal settings.lua
-- (Daniel_Restore_ini_files.bat / .sh): the files are prepared in
-- Data/Daniel Kharrat/Restore, REAPER quits, and the helper copies them into the
-- resource folder once REAPER has closed and relaunches REAPER.

local TITLE = "Restore Config Before Daniel Kharrat"

local RESOURCE_PATH = reaper.GetResourcePath():gsub("\\", "/")
local OS      = reaper.GetOS()
local IS_WIN  = OS:find("Win") ~= nil

local DAN_FOLDER    = RESOURCE_PATH .. "/Data/Daniel Kharrat"
local SOURCE_FOLDER = DAN_FOLDER .. "/Config Before Daniel Kharrat"
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


------------------------------------------------------------
-- What is there to restore?
------------------------------------------------------------

if not file_exists(HELPER) then
    message("Could not find the restore helper:\n\n" .. HELPER)
    return
end

local files = list_files(SOURCE_FOLDER)
table.sort(files)

if #files == 0 then
    message("There is nothing to restore.\n\n" ..
        "No settings from before the configuration were found in " ..
        "Data/Daniel Kharrat/Config Before Daniel Kharrat.")
    return
end


------------------------------------------------------------
-- Confirm
------------------------------------------------------------

local summary = "This will put back the settings you had before the configuration.\n" ..
    "Your current versions of these files will be replaced:\n\n"

for i, name in ipairs(files) do
    if i > 15 then
        summary = summary .. "and " .. (#files - 15) .. " more\n"
        break
    end
    summary = summary .. "  " .. name .. "\n"
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

for _, name in ipairs(files) do
    if not copy_file(SOURCE_FOLDER .. "/" .. name, STAGED_FILES .. "/" .. name) then
        remove_stage()
        message("Could not prepare:\n\n" .. SOURCE_FOLDER .. "/" .. name)
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
