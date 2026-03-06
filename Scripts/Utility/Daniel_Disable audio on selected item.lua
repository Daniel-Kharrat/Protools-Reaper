reaper.Undo_BeginBlock()

local item = reaper.GetSelectedMediaItem(0,0)

local _, chunk = reaper.GetItemStateChunk(item, "", false)

chunk = chunk:gsub("<SOURCE VIDEO", "<SOURCE VIDEO\nAUDIO 0\n")

reaper.SetItemStateChunk(item, chunk, false)

reaper.UpdateArrange()
reaper.Undo_EndBlock("Disable audio in video items", -1)
