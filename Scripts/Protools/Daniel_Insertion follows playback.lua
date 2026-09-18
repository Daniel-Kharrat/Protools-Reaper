reaper.set_action_options(1)

local was_playing = false
local play_cursor = nil
local is_active = true

local personal_settings = reaper.GetResourcePath() .. "/Personal Settings"
local toggle_file = personal_settings .. "/Toolbar_Toggles.ini"

reaper.RecursiveCreateDirectory(personal_settings, 0)

local function set_button_state(value)
  local lines = {}
  local found = false

  local file = io.open(toggle_file, "r")

  if file then
    for line in file:lines() do
      if line:match("^Horizontal_Scroll_50=") then
        table.insert(lines, "Horizontal_Scroll_50=" .. tostring(value))
        found = true
      else
        table.insert(lines, line)
      end
    end
    file:close()
  end

  if not found then
    table.insert(lines, "Horizontal_Scroll_50=" .. tostring(value))
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

function exit()
  is_active = false
  update_toolbar_button()
end

function follow()
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
    reaper.atexit(exit)
end

update_toolbar_button()
follow()
