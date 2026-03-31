--Disarm all tracks
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS02a24eb9425299db445e21d1ed1a08a2f6818766"),0)

--Track: Insert new track
reaper.Main_OnCommand(40001,0)

--Xenakios/SWS: Set selected tracks record armed
reaper.Main_OnCommand(reaper.NamedCommandLookup("_XENAKIOS_SELTRAX_RECARMED"),0)

--Track: Rename last touched track
reaper.Main_OnCommand(40696,0)
