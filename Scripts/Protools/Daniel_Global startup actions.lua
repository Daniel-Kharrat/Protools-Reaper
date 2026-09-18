-- Master script to run multiple actions at startup

local personal_settings = reaper.GetResourcePath() .. "/Personal Settings"
local toggle_file = personal_settings .. "/Toolbar_Toggles.ini"

--Check for armed tracks
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RSe07de25faddbad1a82edccb0cf675ab4014f4a5a"), 0)

--Check for muted tracks
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS089967a15b5ae97c96687243d33f3cfb3cce8071"), 0)

--Check for soloed tracks
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS73872e52305a191a83f55f1811ac45c380e98ff5"), 0)

--------------------------------------------------
--Read Toolbar_Toggles.ini file
--------------------------------------------------

local toggles = {}
local file = io.open(toggle_file, "r")
if file then
    for line in file:lines() do
        local key, value = line:match("^([%w_]+)=(%d+)$")
        if key then
            toggles[key] = value
        end
    end
    file:close()
end

--------------------------------------------------
--Horizontal Scroll 50%
--------------------------------------------------

if toggles["Horizontal_Scroll_50"] == "1" then
    local id1 = reaper.NamedCommandLookup("_RSb188ca992fb7f08eba2ac3633ab1972d2a6604bd")
    reaper.SetToggleCommandState(0, id1, 1)
    reaper.RefreshToolbar2(0, id1)
end

--------------------------------------------------
--Insertion follows playback
--------------------------------------------------

if toggles["Insertion_Follows_Playback"] == "1" then
    local id2 = reaper.NamedCommandLookup("_RSa29e1e48bb9514773a2b5118f69ddff709c406db")
    reaper.SetToggleCommandState(0, id2, 1)
    reaper.RefreshToolbar2(0, id2)
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS3954f4d6fde790290a4c7e86538380193bf6db74"), 0)
end

--------------------------------------------------
--Link Timeline and Edit Selection
--------------------------------------------------

if toggles["Link_Timeline_and_Edit_Selection"] == "1" then
    local id3 = reaper.NamedCommandLookup("_RSdd4ba6262e05c57604ab621179a4552cf2bad49b")
    reaper.SetToggleCommandState(0, id3, 1)
    reaper.RefreshToolbar2(0, id3)
end

--------------------------------------------------
--Always Recording
--------------------------------------------------

if toggles["Always_Recording"] == "1" then
    local id4 = reaper.NamedCommandLookup("_RS1d334413686175f313d60578bea01a827ae4e954")
    reaper.SetToggleCommandState(0, id4, 1)
    reaper.RefreshToolbar2(0, id4)
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS22184bfd14ba6fe71f7c982d8354aec893c6d2ba"), 0)
end
