local KEY = "Horizontal_Scroll_50"
local REAPER_INI = reaper.GetResourcePath() .. "/reaper.ini"

local function SetIniValue(key, value)
  local file = io.open(REAPER_INI, "rb")
  if not file then return false end
  local contents = file:read("*all")
  file:close()

  local new_contents, count = contents:gsub(
    "(\n" .. key .. "=)[^\r\n]*",
    function(prefix) return prefix .. value end
  )
  if count == 0 then return false end

  file = io.open(REAPER_INI, "wb")
  if not file then return false end
  file:write(new_contents)
  file:close()
  return true
end

local _, _, _, command_id = reaper.get_action_context()
local new_state = (reaper.GetToggleCommandState(command_id) == 1) and 0 or 1

reaper.SetToggleCommandState(0, command_id, new_state)
SetIniValue(KEY, tostring(new_state))
reaper.RefreshToolbar2(0, command_id)
