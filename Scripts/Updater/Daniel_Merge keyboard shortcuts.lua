-- Daniel_Merge keyboard shortcuts.lua
--
-- Merges the shipped keymap (Data/Daniel_Modified keyboard shortcuts only.ReaperKeyMap)
-- into the person's reaper-kb.ini WITHOUT replacing the rest of the file.
-- This is separate from the Personal Settings save/restore scripts and does
-- not use their helper.
--
--   SCR lines (script registration): added only if that script ID is not
--     already registered. The person's other SCR lines are never touched, so
--     scripts they installed themselves keep showing up in the action list.
--   KEY lines (shortcuts): a shortcut is identified by modifier + key code +
--     section. If the person already has a line for that key combination it is
--     replaced with yours; otherwise yours is added. Every other KEY line of
--     theirs is left alone.
--   Any other line type in the shipped file is appended if not already there.
--
-- PREPARE-ONLY MODE: another script (Daniel_Update configuration.lua) can run this
-- file with dofile() after setting the global DANIEL_KB_MERGE = {
--   shipped_file = <keymap to merge in>, merged_file = <where to write the result> }.
-- In that mode there is no dialog, no helper and no REAPER quit: it only writes
-- the merged file and returns { ok = true/false, changed = ..., stats = ... }.
--
-- REAPER rewrites reaper-kb.ini from memory when it quits, so this script does
-- NOT edit reaper-kb.ini directly. It writes the merged result to
-- Data/reaper-kb.merged.ini, then quits REAPER. Its own helper
-- (Daniel_Merge_keyboard_shortcuts.bat / .sh) waits for REAPER to close,
-- copies the merged file over reaper-kb.ini, and relaunches REAPER.

local RESOURCE_PATH  = reaper.GetResourcePath()
local DATA_FOLDER   = RESOURCE_PATH .. "/Data"
local PREPARE = rawget(_G, "DANIEL_KB_MERGE") -- nil when run as a normal action

local SHIPPED_FILE = (PREPARE and PREPARE.shipped_file) or
    (DATA_FOLDER .. "/Daniel_Modified keyboard shortcuts only.ReaperKeyMap")
local KB_FILE      = RESOURCE_PATH .. "/reaper-kb.ini"
local MERGED_FILE  = (PREPARE and PREPARE.merged_file) or
    (DATA_FOLDER .. "/reaper-kb.merged.ini")
local BACKUP_FILE  = DATA_FOLDER .. "/reaper-kb.original-backup.ini"

local TITLE = "Keyboard Shortcuts"


------------------------------------------------------------
-- File helpers
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

local function file_exists(path)
    local file = io.open(path, "rb")
    if file then
        file:close()
        return true
    end
    return false
end

local function message(text)
    reaper.ShowMessageBox(text, TITLE, 0)
end


------------------------------------------------------------
-- Line helpers
------------------------------------------------------------

-- Splits text into lines, accepting both CRLF and LF.
local function split_lines(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        lines[#lines + 1] = line
    end
    if lines[#lines] == "" then
        lines[#lines] = nil -- the newline at the end of the file
    end
    return lines
end

-- "SCR 4 0 RS1234... "Custom: name.lua" path.lua" -> "RS1234..."
local function parse_scr_id(line)
    return line:match("^SCR%s+%S+%s+%S+%s+(%S+)")
end

-- "KEY 13 83 0 0  # comment" -> identity "13 83 0" (modifier, key, section)
-- and the action ("0", "40029", "_RS...", "_SWS_...")
local function parse_key(line)
    local mod, key, action, section =
        line:match("^KEY%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
    if not mod then
        return nil
    end
    return mod .. " " .. key .. " " .. section, action
end


------------------------------------------------------------
-- Merge
------------------------------------------------------------

local function merge(target_text, shipped_text)

    -- keep whatever line ending the person's file already uses
    local eol = "\n"
    if target_text:find("\r\n", 1, true) then
        eol = "\r\n"
    end

    local target  = split_lines(target_text)
    local shipped = split_lines(shipped_text)

    local stats = {
        scr_added = 0,
        scr_present = 0,
        key_added = 0,
        key_replaced = 0,
        key_unchanged = 0,
        other_added = 0,
        duplicates_removed = 0,
        changed = false,
    }

    ----------------------------------------------------
    -- Index the person's file
    ----------------------------------------------------

    local scr_ids = {}     -- script IDs already registered
    local key_index = {}   -- key identity -> list of line numbers
    local existing = {}    -- exact lines already in the file
    local last_scr = nil   -- line number of the last SCR line
    local first_key = nil  -- line number of the first KEY line

    for i, line in ipairs(target) do
        existing[line] = true

        local id = parse_scr_id(line)
        if id then
            scr_ids[id] = true
            last_scr = i
        end

        local identity = parse_key(line)
        if identity then
            key_index[identity] = key_index[identity] or {}
            table.insert(key_index[identity], i)
            first_key = first_key or i
        end
    end

    ----------------------------------------------------
    -- Walk the shipped file
    ----------------------------------------------------

    local new_scr, new_key, new_other = {}, {}, {}
    local replace = {}  -- line number -> replacement line
    local remove = {}   -- line number -> true (extra duplicates of a replaced key)

    for _, line in ipairs(shipped) do

        if line:match("^%s*$") then
            -- blank line: nothing to merge

        elseif line:match("^SCR%s") and parse_scr_id(line) then
            local id = parse_scr_id(line)
            if scr_ids[id] then
                stats.scr_present = stats.scr_present + 1
            else
                new_scr[#new_scr + 1] = line
                scr_ids[id] = true
                stats.scr_added = stats.scr_added + 1
            end

        elseif line:match("^KEY%s") and parse_key(line) then
            local identity, action = parse_key(line)
            local rows = key_index[identity]
            if rows then
                local _, current_action = parse_key(target[rows[1]])
                if #rows == 1 and current_action == action then
                    stats.key_unchanged = stats.key_unchanged + 1
                else
                    replace[rows[1]] = line
                    for n = 2, #rows do
                        remove[rows[n]] = true
                        stats.duplicates_removed = stats.duplicates_removed + 1
                    end
                    stats.key_replaced = stats.key_replaced + 1
                end
            else
                new_key[#new_key + 1] = line
                stats.key_added = stats.key_added + 1
            end

        else
            if not existing[line] then
                new_other[#new_other + 1] = line
                existing[line] = true
                stats.other_added = stats.other_added + 1
            end
        end
    end

    stats.changed = (stats.scr_added + stats.key_added + stats.key_replaced +
                     stats.other_added + stats.duplicates_removed) > 0

    ----------------------------------------------------
    -- Rebuild the file
    ----------------------------------------------------
    -- New SCR lines go right after the person's last SCR line (or in front of
    -- their first KEY line if they have none). New KEY lines go at the very
    -- end, so a script is always registered before a shortcut refers to it.

    local out = {}
    local scr_done = false

    local function flush_new_scr()
        for _, l in ipairs(new_scr) do
            out[#out + 1] = l
        end
        scr_done = true
    end

    for i, line in ipairs(target) do
        if not remove[i] then
            if not last_scr and i == first_key and not scr_done then
                flush_new_scr()
            end
            out[#out + 1] = replace[i] or line
        end
        if i == last_scr then
            flush_new_scr()
        end
    end

    if not scr_done then
        flush_new_scr()
    end

    for _, l in ipairs(new_key) do
        out[#out + 1] = l
    end
    for _, l in ipairs(new_other) do
        out[#out + 1] = l
    end

    local text = ""
    if #out > 0 then
        text = table.concat(out, eol) .. eol
    end

    return text, stats
end


------------------------------------------------------------
-- Read both files and merge
------------------------------------------------------------

local shipped_text = read_file(SHIPPED_FILE)

if not shipped_text then
    if PREPARE then
        return { ok = false, error = "Could not find " .. SHIPPED_FILE }
    end
    message("Could not find:\n\n" .. SHIPPED_FILE)
    return
end

-- a missing reaper-kb.ini is treated as empty (fresh install)
local kb_text = read_file(KB_FILE) or ""

local merged_text, stats = merge(kb_text, shipped_text)

if PREPARE then
    if stats.changed and not write_file(MERGED_FILE, merged_text) then
        return { ok = false, error = "Could not write " .. MERGED_FILE }
    end
    return { ok = true, changed = stats.changed, stats = stats }
end

if not stats.changed then
    message("Your keyboard shortcuts are already up to date.\n\nNothing was changed.")
    return
end


------------------------------------------------------------
-- Confirm
------------------------------------------------------------

local summary =
    "This will merge your keyboard shortcuts into REAPER.\n\n" ..

    "Scripts added to the action list: " .. stats.scr_added .. "\n" ..
    "Shortcuts added: " .. stats.key_added .. "\n" ..
    "Shortcuts replaced: " .. stats.key_replaced .. "\n" ..
    "Shortcuts already identical: " .. stats.key_unchanged .. "\n\n" ..

    "All other shortcuts and scripts stay as they are.\n" ..
    "REAPER will close and restart to apply the changes.\n\n" ..
    "Continue?"

if reaper.ShowMessageBox(summary, TITLE, 4) ~= 6 then
    return
end


------------------------------------------------------------
-- Save backup (first run only) and the merged file
------------------------------------------------------------

reaper.RecursiveCreateDirectory(DATA_FOLDER, 0)

-- Only the very first backup is kept, so it always holds the person's
-- original file from before any merge.
if kb_text ~= "" and not file_exists(BACKUP_FILE) then
    if not write_file(BACKUP_FILE, kb_text) then
        message("Could not write the backup:\n\n" .. BACKUP_FILE)
        return
    end
end

if not write_file(MERGED_FILE, merged_text) then
    message("Could not write:\n\n" .. MERGED_FILE)
    return
end


------------------------------------------------------------
-- Restore helper path
------------------------------------------------------------

local OS = reaper.GetOS()
local restore_script

if OS:find("Win") then
    restore_script = RESOURCE_PATH ..
    "/Scripts/Daniel Kharrat/Updater/Daniel_Merge_keyboard_shortcuts.bat"
else
    restore_script = RESOURCE_PATH ..
    "/Scripts/Daniel Kharrat/Updater/Daniel_Merge_keyboard_shortcuts.sh"
end

if not file_exists(restore_script) then
    os.remove(MERGED_FILE)
    message("Could not find the restore helper:\n\n" .. restore_script)
    return
end


------------------------------------------------------------
-- Launch restore helper in background
------------------------------------------------------------

local command

if OS:find("Win") then
    command = 'start "" /min cmd /c ""' ..
    restore_script ..
    '" "' ..
    RESOURCE_PATH ..
    '""'
else
    command = 'nohup /bin/bash "' ..
    restore_script ..
    '" "' ..
    RESOURCE_PATH ..
    '" >/dev/null 2>&1 &'
end

os.execute(command)


------------------------------------------------------------
-- Quit REAPER
------------------------------------------------------------

reaper.Main_OnCommand(40004, 0)
