reaper.set_action_options(2)

-- Get current arrange view position (start and end)
local view_start, view_end = reaper.BR_GetArrangeView(0)

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

function isNumpad0Pressed()
    local state = reaper.JS_VKeys_GetState(0)
    return string.byte(state, 96) > 0
end

function isNumpad2Pressed()
    local state = reaper.JS_VKeys_GetState(0)
    return string.byte(state, 98) > 0
end

function isGreaterthanPressed()
    local state = reaper.JS_VKeys_GetState(0)
    return string.byte(state, 190) > 0
end

function jogLeft()
    if isSpaceBarPressed() or isNumpad0Pressed() or isNumpad2Pressed() or isGreaterthanPressed() or timeInSeconds == 0 then
      --Transport: Stop
      reaper.Main_OnCommand(1016,0)
      return
    end
    
    timeInSeconds = reaper.GetCursorPosition()
    reaper.SetEditCurPos(timeInSeconds - moveAmount, false, false)
    
    if timeInSeconds < view_start then
        -- Calculate the width of the current arrange view
        local view_width = view_end - view_start
    
        -- Move the view backward by one full page (the width of the view)
        reaper.BR_SetArrangeView(0, view_start - view_width, view_end - view_width)
        view_start, view_end = reaper.BR_GetArrangeView(0)
    end
    
    reaper.defer(jogLeft)
end

jogLeft()

