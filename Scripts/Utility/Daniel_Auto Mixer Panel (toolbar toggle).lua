-- @description Daniel_Auto Mixer Panel (toolbar toggle)
-- @author Daniel Kharrat
-- @version 1.1
-- @changelog
--   Same toolbar sync as the other Daniel toggle scripts: launches the panel by
--   its command ID and decides on/off from whether the panel is really running.
-- @about
--   Toolbar button for the Auto Mixer panel. Click to open, click again to
--   close. The panel itself keeps this button lit while it's open, however it
--   was started or closed.

local KEY = "Auto_Mixer_Panel"
local SECTION = "toolbar button states"
-- Script: Daniel_Auto Mixer Panel.lua
local MAIN_SCRIPT = "_RS091ceb4b08e5cda888e096fc0c3054bd03cd907b"

-- writes KEY=value in reaper.ini under [toolbar button states] (adds the line if missing)
local function SetIniValue(key, value)
  local path = reaper.get_ini_file()
  local f = io.open(path, "rb")
  if not f then return end
  local d = f:read("a")
  f:close()
  local nl = d:find("\r\n", 1, true) and "\r\n" or "\n"
  local nd, n = d:gsub("(\n" .. key .. "=)[^\r\n]*", function(p) return p .. value end)
  if n == 0 then
    nd, n = d:gsub("(%[" .. SECTION .. "%][^\r\n]*\r?\n)", function(h) return h .. key .. "=" .. value .. nl end, 1)
  end
  if n == 0 then
    nd = d .. ((d:sub(-1) == "\n") and "" or nl) .. "[" .. SECTION .. "]" .. nl .. key .. "=" .. value .. nl
  end
  if nd == d then return end
  f = io.open(path, "wb")
  if f then f:write(nd) f:close() end
end

local main_id = reaper.NamedCommandLookup(MAIN_SCRIPT)
if not main_id or main_id == 0 then
  reaper.MB("Can't find \"Daniel_Auto Mixer Panel.lua\" in the action list.\nLoad it there first.", "Auto Mixer", 0)
  return
end

local _, _, section_id, command_id = reaper.get_action_context()

-- on/off follows whether the panel is actually running, so the button can never get out of step
local running = reaper.GetToggleCommandState(main_id) == 1
local new_state = running and 0 or 1

SetIniValue(KEY, tostring(new_state))
reaper.SetToggleCommandState(section_id, command_id, new_state)
reaper.RefreshToolbar2(section_id, command_id)

-- starts the panel, or closes it if it's running (the panel uses set_action_options(1))
reaper.Main_OnCommand(main_id, 0)

