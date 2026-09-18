local personal_settings = reaper.GetResourcePath() .. "/Personal Settings"
local toggle_file = personal_settings .. "/Toolbar_Toggles.ini"

reaper.RecursiveCreateDirectory(personal_settings, 0)

local function set_button_state(value)
  local lines = {}
  local found = false

  local file = io.open(toggle_file, "r")

  if file then
    for line in file:lines() do
      if line:match("^Always_Recording=") then
        table.insert(lines, "Always_Recording=" .. tostring(value))
        found = true
      else
        table.insert(lines, line)
      end
    end
    file:close()
  end

  if not found then
    table.insert(lines, "Always_Recording=" .. tostring(value))
  end

  file = io.open(toggle_file, "w")

  if file then
    file:write(table.concat(lines, "\n"))
    file:write("\n")
    file:close()
  end
end

local personal_settings = reaper.GetResourcePath() .. "/Personal Settings"
local toggle_file = personal_settings .. "/Toolbar_Toggles.ini"

reaper.RecursiveCreateDirectory(personal_settings, 0)

local function set_button_state(value)
  local lines = {}
  local found = false

  local file = io.open(toggle_file, "r")

  if file then
    for line in file:lines() do
      if line:match("^Always_Recording=") then
        table.insert(lines, "Always_Recording=" .. tostring(value))
        found = true
      else
        table.insert(lines, line)
      end
    end
    file:close()
  end

  if not found then
    table.insert(lines, "Always_Recording=" .. tostring(value))
  end

  file = io.open(toggle_file, "w")

  if file then
    file:write(table.concat(lines, "\n"))
    file:write("\n")
    file:close()
  end
end

local _, _, _, command_id = reaper.get_action_context()
local state = reaper.GetToggleCommandState(command_id)

function update_toolbar_button()

    if state == 1 then
        reaper.SetToggleCommandState(0, command_id, 0)
        set_button_state(0)
    else
        reaper.SetToggleCommandState(0, command_id, 1)
        set_button_state(1)
    end

    reaper.RefreshToolbar2(0, command_id)
end

update_toolbar_button()

--Script: Daniel_Always Recording.lua
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS22184bfd14ba6fe71f7c982d8354aec893c6d2ba"),0)
