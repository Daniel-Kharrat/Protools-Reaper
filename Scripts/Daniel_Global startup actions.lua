-- Master script to run multiple actions at startup

--Check for armed tracks
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RSe07de25faddbad1a82edccb0cf675ab4014f4a5a"), 0)
--Check for muted tracks
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS089967a15b5ae97c96687243d33f3cfb3cce8071"), 0)
--Check for soloed tracks
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS73872e52305a191a83f55f1811ac45c380e98ff5"), 0)


