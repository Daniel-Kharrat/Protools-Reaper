-- Master script to run multiple actions at startup

--Check for armed tracks
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS316a89c3c279b2fc864b69a9d4445aaf32444a6a"), 0)
--Check for muted tracks
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS64a0c50d779925fa7bd9a2c794273ad512b78e23"), 0)
--Check for soloed tracks
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS12cfa74a9cb866735aed4af132544a9a111a5f7b"), 0)


