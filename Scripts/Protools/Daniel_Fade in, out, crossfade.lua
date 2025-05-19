local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

--Razor edit: Select media items within razor edit area
reaper.Main_OnCommand(42957,0)

--fade
--Razor edit: Select media items within razor edit area
reaper.Main_OnCommand(42957,0)

--SWS/AW: Fade in/out/crossfade selected area of selected items
reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_AWFADESEL"),0)
