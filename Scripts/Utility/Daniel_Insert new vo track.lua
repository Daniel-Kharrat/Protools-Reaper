--Track: Insert new track
reaper.Main_OnCommand(40001,0)

--Xenakios/SWS: Set selected tracks record armed
reaper.Main_OnCommand(reaper.NamedCommandLookup("_XENAKIOS_SELTRAX_RECARMED"),0)

--Track: Rename last touched track
reaper.Main_OnCommand(40696,0)
