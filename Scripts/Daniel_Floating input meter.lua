local track = reaper.GetSelectedTrack(0, 0)
if track == nil then
  reaper.ShowMessageBox("No track selected!", "Error", 0)
  return
end

-- Define the JSFX plugin name
local fxName = "Daniel_Floating Meter"

-- Check if the JSFX already exists in the input FX chain
local fxIndex = reaper.TrackFX_AddByName(track, fxName, true, 0) -- true for input FX, 0 to search for existing instances

if fxIndex ~= -1 then
  -- If the FX already exists, check if the window is open
  local hwnd = reaper.TrackFX_GetFloatingWindow(track, 0x1000000 + fxIndex)
  
  if hwnd ~= nil then
    -- If the window is open, close it and remove the FX
    reaper.TrackFX_Show(track, 0x1000000 + fxIndex, 2) -- '2' closes the window
    reaper.TrackFX_Delete(track, 0x1000000 + fxIndex) -- Remove the FX from the input FX chain
  else
    -- If the window is not open, open it in floating mode
    reaper.TrackFX_Show(track, 0x1000000 + fxIndex, 3) -- '3' opens the window in floating mode
  end
else
  -- If the plugin is not found, insert it into the input FX chain
  fxIndex = reaper.TrackFX_AddByName(track, fxName, true, 1) -- true for input FX, 1 to add if not found
  
  -- Open the FX in floating mode
  reaper.TrackFX_Show(track, 0x1000000 + fxIndex, 3) -- '3' opens the FX in a floating window
end

-- Resize the window if it was opened (adjust these values for meter width/height)
local hwnd = reaper.TrackFX_GetFloatingWindow(track, 0x1000000 + fxIndex)
if hwnd ~= nil then
  reaper.JS_Window_SetPosition(hwnd, 1850, 150, 54, 550) -- Position and size the floating window
end

