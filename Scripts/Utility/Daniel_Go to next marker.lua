--Get the state of "toggle horizontal scroll 50%" action
local command_id = reaper.NamedCommandLookup("_RSb188ca992fb7f08eba2ac3633ab1972d2a6604bd")
local state = reaper.GetToggleCommandState(command_id)

--Time selection: Remove (unselect) time selection and loop points
reaper.Main_OnCommand(40020,0)

--Razor edit: Clear all areas
reaper.Main_OnCommand(42406,0)

--Item: Unselect (clear selection of) all items
reaper.Main_OnCommand(40289,0)

--Markers: Go to next marker/project end
reaper.Main_OnCommand(40173,0)

if state == 1 then
  --SWS: Horizontal scroll to put edit cursor at 50%
  reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_HSCROLL50"),0)
end
