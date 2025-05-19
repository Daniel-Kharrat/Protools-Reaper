local was_playing = false
local play_cursor = nil
local is_active = true
local is_pressed = true

function update_toolbar_button()

    local command_id = reaper.NamedCommandLookup("_RS3954f4d6fde790290a4c7e86538380193bf6db74")

    if is_active then
        reaper.SetToggleCommandState(0, command_id, 1)
    else
        reaper.SetToggleCommandState(0, command_id, 0)
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


