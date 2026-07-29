local command_id = reaper.NamedCommandLookup("_RSb188ca992fb7f08eba2ac3633ab1972d2a6604bd")
local state = reaper.GetToggleCommandState(command_id)

function update_toolbar_button()

    if state == 1 then
        reaper.SetToggleCommandState(0, command_id, 0)
    else
        reaper.SetToggleCommandState(0, command_id, 1)
    end

    reaper.RefreshToolbar2(0, command_id)
end

update_toolbar_button()
