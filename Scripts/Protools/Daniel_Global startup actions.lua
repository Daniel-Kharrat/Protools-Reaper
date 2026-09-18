-- Master script to run multiple actions at startup

--Check for armed tracks
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RSe07de25faddbad1a82edccb0cf675ab4014f4a5a"), 0)

--Check for muted tracks
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS089967a15b5ae97c96687243d33f3cfb3cce8071"), 0)

--Check for soloed tracks
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS73872e52305a191a83f55f1811ac45c380e98ff5"), 0)

--------------------------------------------------
--Link Timeline and Edit Selection
--------------------------------------------------

local personal_settings = reaper.GetResourcePath() .. "/Personal Settings"
local toggle_file = personal_settings .. "/Toolbar_Toggles.ini"

local command_id = reaper.NamedCommandLookup("_RSdd4ba6262e05c57604ab621179a4552cf2bad49b")

local file = io.open(toggle_file, "r")

if file then
    for line in file:lines() do
        local value = line:match("^Link_Timeline_and_Edit_Selection=(%d+)$")

        if value == "1" then
            reaper.SetToggleCommandState(0, command_id, tonumber(1))
            reaper.RefreshToolbar2(0, command_id)
            break
        end
    end

    file:close()
end

--------------------------------------------------
--Always Recording
--------------------------------------------------

local personal_settings = reaper.GetResourcePath() .. "/Personal Settings"
local toggle_file = personal_settings .. "/Toolbar_Toggles.ini"

local command_id = reaper.NamedCommandLookup("_RS1d334413686175f313d60578bea01a827ae4e954")

local file = io.open(toggle_file, "r")

if file then
    for line in file:lines() do
        local value = line:match("^Always_Recording=(%d+)$")

        if value == "1" then
            reaper.SetToggleCommandState(0, command_id, tonumber(1))
            reaper.RefreshToolbar2(0, command_id)
            reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS22184bfd14ba6fe71f7c982d8354aec893c6d2ba"), 0)
            break
        end
    end

    file:close()
end
