reaper.set_action_options(2) 

--View: Move edit cursor to play cursor
reaper.Main_OnCommand(40434,0)
--Transport: Stop
reaper.Main_OnCommand(1016,0)

local moveAmount = 0.2
local timeInSeconds = reaper.GetCursorPosition()

function isSpaceBarPressed()
    local state = reaper.JS_VKeys_GetState(0)
    return string.byte(state, 32) > 0
end

function isNumpad1Pressed()
    local state = reaper.JS_VKeys_GetState(0)
    return string.byte(state, 97) > 0
end

function isNumpad0Pressed()
    local state = reaper.JS_VKeys_GetState(0)
    return string.byte(state, 96) > 0
end

function islLessthenPressed()
    local state = reaper.JS_VKeys_GetState(0)
    return string.byte(state, 188) > 0
end

function jogRight()
    if isSpaceBarPressed() or isNumpad0Pressed() or isNumpad1Pressed() or islLessthenPressed() then
      --Transport: Stop
      reaper.Main_OnCommand(1016,0)
      return
    
    else
    timeInSeconds = reaper.GetCursorPosition()
    reaper.SetEditCurPos(timeInSeconds + moveAmount, true, true)

    reaper.defer(jogRight)
    end
end

jogRight()

