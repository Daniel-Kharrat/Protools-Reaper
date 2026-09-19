local IMAGE_NAME = "Daniel_Splash Screen.jpg"

local TITLE = "Splash Screen"

local RESOURCE_PATH = reaper.GetResourcePath()
local IS_WIN = reaper.GetOS():find("Win") ~= nil
local THEMES_FOLDER = RESOURCE_PATH .. "/ColorThemes"
local REAPER_INI = RESOURCE_PATH .. "/reaper.ini"


------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function message(text)
    reaper.ShowMessageBox(text, TITLE, 0)
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

-- Paths are written the way the operating system writes them
local function native(path)
    if IS_WIN then
        return (path:gsub("/", "\\"))
    end
    return (path:gsub("\\", "/"))
end

local function is_image(name)
    local lower = name:lower()
    return lower:match("%.jpe?g$") ~= nil or lower:match("%.png$") ~= nil
end


------------------------------------------------------------
-- Find the image in ColorThemes
------------------------------------------------------------

local function list_folder()
    local names = {}
    reaper.EnumerateFiles(THEMES_FOLDER, -1)
    local i = 0
    while true do
        local name = reaper.EnumerateFiles(THEMES_FOLDER, i)
        if not name then
            break
        end
        names[#names + 1] = name
        i = i + 1
    end
    return names
end

local files = list_folder()
local found = nil

-- 1. the exact name, ignoring capitals
for _, name in ipairs(files) do
    if name:lower() == IMAGE_NAME:lower() then
        found = name
        break
    end
end

-- 2. otherwise an image whose name has both "daniel" and "splash" in it
if not found then
    for _, name in ipairs(files) do
        local lower = name:lower()
        if is_image(name) and lower:find("daniel", 1, true) and lower:find("splash", 1, true) then
            found = name
            break
        end
    end
end

if not found then
    local splash_files = {}
    for _, name in ipairs(files) do
        if name:lower():find("splash", 1, true) then
            splash_files[#splash_files + 1] = name
        end
    end

    local listing = "(none)"
    if #splash_files > 0 then
        listing = table.concat(splash_files, "\n")
    end

    message(
        "Could not find the splash screen image:\n\n" ..
        native(THEMES_FOLDER .. "/" .. IMAGE_NAME) ..
        "\n\nThe ColorThemes folder has " .. #files .. " files.\n" ..
        "Files with \"splash\" in the name:\n" .. listing
    )
    return
end

local splash_path = native(THEMES_FOLDER .. "/" .. found)


------------------------------------------------------------
-- Write the splashimage= line into reaper.ini
------------------------------------------------------------

local contents = read_file(REAPER_INI)

if not contents then
    message("Could not open reaper.ini:\n\n" .. native(REAPER_INI))
    return
end

local eol = "\n"
if contents:find("\r\n", 1, true) then
    eol = "\r\n"
end

local line = "splashimage=" .. splash_path

-- a function as the replacement, so characters such as % in a path stay as they are
local new_contents, count = contents:gsub("(\n)splashimage=[^\r\n]*", function(newline)
    return newline .. line
end)

if count == 0 then
    -- the key might be the very first line of the file
    new_contents, count = contents:gsub("^splashimage=[^\r\n]*", function()
        return line
    end)
end

local action = "updated"

if count == 0 then
    -- no splashimage line at all: add it to the [reaper] section
    local _, header_end = contents:find("\n%[[Rr][Ee][Aa][Pp][Ee][Rr]%]\r?\n")
    if not header_end then
        _, header_end = contents:find("^%[[Rr][Ee][Aa][Pp][Ee][Rr]%]\r?\n")
    end

    if not header_end then
        message("There is no [reaper] section in reaper.ini, so the splash screen line could not be added.")
        return
    end

    new_contents = contents:sub(1, header_end) .. line .. eol .. contents:sub(header_end + 1)
    action = "added"
end

if not write_file(REAPER_INI, new_contents) then
    message("Could not write to reaper.ini:\n\n" .. native(REAPER_INI))
    return
end

message(
    "Splash screen " .. action .. ":\n\n" .. splash_path ..
    "\n\nIt shows the next time REAPER starts."
)
