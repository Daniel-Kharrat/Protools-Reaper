local track = reaper.GetSelectedTrack(0, 0)
if track == nil then
  reaper.ShowMessageBox("No track selected!", "Error", 0)
  return
end

-- Define the JSFX plugin name
local fxName = "Daniel_Floating Meter"

-- Check if the JSFX already exists in the normal track FX chain
local fxIndex = reaper.TrackFX_AddByName(track, fxName, false, 0) -- false for normal FX, 0 to search for existing instances

if fxIndex ~= -1 then
  -- If the FX already exists, check if the window is open
  local hwnd = reaper.TrackFX_GetFloatingWindow(track, fxIndex)
  
  if hwnd ~= nil then
    -- If the window is open, close it and remove the FX
    reaper.TrackFX_Show(track, fxIndex, 2) -- '2' closes the window
    reaper.TrackFX_Delete(track, fxIndex) -- Remove the FX from the normal FX chain
  else
    -- If the window is not open, open it in floating mode
    reaper.TrackFX_Show(track, fxIndex, 3) -- '3' opens the window in floating mode
  end
else
  -- If the plugin is not found, insert it into the normal FX chain
  fxIndex = reaper.TrackFX_AddByName(track, fxName, false, 1) -- false for normal FX, 1 to add if not found
  
  -- Move the FX to the first position if it's not already there
  if fxIndex > 0 then
    reaper.TrackFX_CopyToTrack(track, fxIndex, track, 0, true) -- Move FX to first position (index 0)
    reaper.TrackFX_Delete(track, fxIndex + 1) -- Delete the old instance
    fxIndex = 0 -- Now the FX is at index 0
  end
  
  -- Open the FX in floating mode
  reaper.TrackFX_Show(track, fxIndex, 3) -- '3' opens the FX in a floating window
end

-- Resize the window if it was opened (adjust these values for meter width/height)
local hwnd = reaper.TrackFX_GetFloatingWindow(track, fxIndex)
if hwnd ~= nil then
  reaper.JS_Window_SetPosition(hwnd, 1850, 150, 54, 550) -- Position and size the floating window
end

