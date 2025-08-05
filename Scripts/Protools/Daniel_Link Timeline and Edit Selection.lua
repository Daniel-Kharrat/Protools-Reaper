local command_id = reaper.NamedCommandLookup("_RSdd4ba6262e05c57604ab621179a4552cf2bad49b")
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
