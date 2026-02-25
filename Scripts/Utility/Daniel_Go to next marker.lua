--Time selection: Remove (unselect) time selection and loop points
reaper.Main_OnCommand(40020,0)

--Razor edit: Clear all areas
reaper.Main_OnCommand(42406,0)

--Item: Unselect (clear selection of) all items
reaper.Main_OnCommand(40289,0)

--Markers: Go to next marker/project end
reaper.Main_OnCommand(40173,0)
