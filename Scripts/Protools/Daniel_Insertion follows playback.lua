reaper.set_action_options(1)

local _, _, section_id, cmd_id = reaper.get_action_context()

local personal_settings = reaper.GetResourcePath() .. "/Personal Settings"
local toggle_file = personal_settings .. "/Toolbar_Toggles.ini"
local toggle_button_cmd_id = reaper.NamedCommandLookup("_RSb019784d274d4c4efd2649de77c3ce2bc86d5d2e")

local function write_ini_value(value)
  reaper.RecursiveCreateDirectory(personal_settings, 0)
  local lines = {}
  local found = false
  local file = io.open(toggle_file, "r")
  if file then
    for line in file:lines() do
      if line:match("^Insertion_Follows_Playback=") then
        table.insert(lines, "Insertion_Follows_Playback=" .. tostring(value))
        found = true
      else
        table.insert(lines, line)
      end
    end
    file:close()
  end
  if not found then
    table.insert(lines, "Insertion_Follows_Playback=" .. tostring(value))
  end
  file = io.open(toggle_file, "w")
  if file then
    file:write(table.concat(lines, "\n"))
    file:write("\n")
    file:close()
  end
end

local function set_visual_state(on)
  local v = on and 1 or 0
  -- this script's own action (used internally for reentrancy handling)
  reaper.SetToggleCommandState(section_id, cmd_id, v)
  reaper.RefreshToolbar2(section_id, cmd_id)
  -- the actual visible toolbar button, bound to the separate toggle script
  if toggle_button_cmd_id and toggle_button_cmd_id ~= 0 then
    reaper.SetToggleCommandState(0, toggle_button_cmd_id, v)
    reaper.RefreshToolbar2(0, toggle_button_cmd_id)
  end
end

local function set_button_state(on)
  set_visual_state(on)
  write_ini_value(on and 1 or 0)
end

if reaper.GetToggleCommandStateEx(section_id, cmd_id) == 1 then
  -- already running elsewhere: this press means "turn it off"
  set_button_state(false)
  return
end
set_button_state(true)

local was_playing = false
local play_cursor = nil

local function follow()
  local is_playing = reaper.GetPlayState() & 1 == 1

  if is_playing then
    play_cursor = reaper.GetPlayPosition()
    was_playing = true
  else
    if was_playing and play_cursor ~= nil then
      reaper.SetEditCurPos(play_cursor, true, true)
      was_playing = false
    end
  end

  reaper.defer(follow)
end

local function exit()
  set_visual_state(false)
end

reaper.atexit(exit)
follow()
