-- @description Open mouse modifiers documentation
-- @author Daniel Kharrat
-- @about
--   Opens the mouse modifiers reference page (Daniel Kharrat's REAPER-Protools
--   Configuration) in the system's default web browser.

local url = "https://daniel-kharrat.github.io/Protools-Reaper/mouse-modifiers.html"

if reaper.CF_ShellExecute then
  reaper.CF_ShellExecute(url)
else
  reaper.MB(
    "This script needs the SWS Extension (specifically CF_ShellExecute) to open your browser.\n\n" ..
    "You can open the page manually instead:\n" .. url,
    "SWS Extension required", 0)
end
