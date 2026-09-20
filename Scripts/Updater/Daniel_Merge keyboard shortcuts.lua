-- Daniel_Merge keyboard shortcuts.lua
--
-- Merges a shipped keymap into the person's reaper-kb.ini WITHOUT replacing the rest
-- of the file. This script is not run by itself: Daniel_Update configuration.lua
-- runs it with dofile() after setting the global
--
--   DANIEL_KB_MERGE = { shipped_file = <keymap to merge in>,
--                       merged_file  = <where to write the result> }
--
-- It only writes the merged file (nothing else is read, changed or deleted, and
-- REAPER is not quit) and returns { ok = true/false, changed = ..., stats = ... }
-- (or { ok = false, error = "..." }). The update script copies the merged file over
-- reaper-kb.ini after REAPER has closed.
--
--   SCR lines (script registration): added only if that script ID is not
--     already registered. The person's other SCR lines are never touched, so
--     scripts they installed themselves keep showing up in the action list.
--   KEY lines (shortcuts): a shortcut is identified by modifier + key code +
--     section. If the person already has a line for that key combination it is
--     replaced with yours; otherwise yours is added. Every other KEY line of
--     theirs is left alone.
--   Any other line type in the shipped file is appended if not already there.

local PREPARE = rawget(_G, "DANIEL_KB_MERGE")

if not PREPARE then
    reaper.ShowMessageBox(
        "This script is used by the update script (Daniel_Update configuration.lua) " ..
        "and is not run on its own.",
        "Keyboard Shortcuts", 0)
    return
end

local SHIPPED_FILE = PREPARE.shipped_file
local MERGED_FILE  = PREPARE.merged_file
local KB_FILE      = reaper.GetResourcePath() .. "/reaper-kb.ini"   -- the person's own file


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
-- Read both files, merge and write the result
------------------------------------------------------------

if not SHIPPED_FILE or not MERGED_FILE then
    return { ok = false, error = "The shipped file and the merged file were not given." }
end

local shipped_text = read_file(SHIPPED_FILE)

if not shipped_text then
    return { ok = false, error = "Could not find " .. SHIPPED_FILE }
end

-- a missing reaper-kb.ini is treated as empty (fresh install)
local kb_text = read_file(KB_FILE) or ""

local merged_text, stats = merge(kb_text, shipped_text)

if stats.changed and not write_file(MERGED_FILE, merged_text) then
    return { ok = false, error = "Could not write " .. MERGED_FILE }
end

return { ok = true, changed = stats.changed, stats = stats }
