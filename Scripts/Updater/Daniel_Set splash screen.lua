local RESOURCE_PATH = reaper.GetResourcePath()
local SPLASH_PATH = RESOURCE_PATH .. "/ColorThemes/Daniel_Splash Screen.jpg"
local REAPER_INI = RESOURCE_PATH .. "/reaper.ini"

-- Check if splash image exists

local file = io.open(SPLASH_PATH, "rb")

if not file then
reaper.ShowMessageBox(
"Could not find the splash screen image:\n\n" .. SPLASH_PATH,
"Splash Screen",
0
)
return
end

file:close()

-- Read reaper.ini

local file = io.open(REAPER_INI, "rb")

if not file then
reaper.ShowMessageBox(
"Could not open reaper.ini:\n\n" .. REAPER_INI,
"Splash Screen",
0
)
return
end

local contents = file:read("*all")
file:close()

-- Replace splashimage= line

local new_contents, count = contents:gsub(
"splashimage=[^\r\n]*",
"splashimage=" .. SPLASH_PATH
)

-- Check whether the setting was found

if count == 0 then
reaper.ShowMessageBox(
"The splashimage= setting was not found in reaper.ini.",
"Splash Screen",
0
)
return
end

-- Write updated reaper.ini

file = io.open(REAPER_INI, "wb")

if not file then
reaper.ShowMessageBox(
"Could not write to reaper.ini:\n\n" .. REAPER_INI,
"Splash Screen",
0
)
return
end

file:write(new_contents)
file:close()

-- Done

reaper.ShowMessageBox(
"Splash screen path updated successfully:\n\n" .. SPLASH_PATH,
"Splash Screen",
0
)
