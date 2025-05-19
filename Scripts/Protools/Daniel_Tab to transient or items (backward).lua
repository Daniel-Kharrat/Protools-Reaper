reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- Save selected items in a list
local count = reaper.CountSelectedMediaItems(0)
local selected_items = {}
for i=0, count-1 do
  selected_items[i] = reaper.GetSelectedMediaItem(0,i)
end

if count == 0 then
  -- Unselect all items
  reaper.Main_OnCommand(40289,0)
  -- Select all items on selected track
  reaper.Main_OnCommand(40421,0)
  -- Move edit cursor left
  reaper.Main_OnCommand(40318,0)
  -- Unselect all items
  reaper.Main_OnCommand(40289,0)
  -- Recover selection
  for i=0, count-1 do
    reaper.SetMediaItemSelected(selected_items[i],true)
  end
  
  --Xenakios/SWS: Select items under edit cursor on selected tracks
  local id2 = reaper.NamedCommandLookup("_XENAKIOS_SELITEMSUNDEDCURSELTX") 
  reaper.Main_OnCommand(id2, 0)
  else
  --Item navigation: Move cursor to previous transient in items
  reaper.Main_OnCommand(40376, 0)
end

--Razor edit: Clear all areas
reaper.Main_OnCommand(42406, 0)

--Time selection: Remove (unselect) time selection and loop points
reaper.Main_OnCommand(40020, 0)

reaper.Undo_EndBlock("Move cursor right to nearest item edge in selected tracks and set time selection",0)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
