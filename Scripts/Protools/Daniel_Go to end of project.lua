--Time selection: Remove (unselect) time selection and loop points
reaper.Main_OnCommand(40020,0)

--Razor edit: Clear all areas
reaper.Main_OnCommand(42406,0)

--Transport: Stop
reaper.Main_OnCommand(1016,0)

--Transport: Go to end of project
reaper.Main_OnCommand(40043,0)
