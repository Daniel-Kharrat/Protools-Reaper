local KEY = "Floating_Mixer"
local REAPER_INI = reaper.GetResourcePath() .. "/reaper.ini"

-- Sets KEY=value in reaper.ini, in the [toolbar button states] section. If the line isn't
-- there yet, it's added to that section (and the section is added at the end if it's missing).
local function SetIniValue(key, value)
  local file = io.open(REAPER_INI, "rb")
  if not file then return false end
  local contents = file:read("*all")
  file:close()
  value = tostring(value)

  local new_contents, count = contents:gsub(
    "(\n" .. key .. "=)[^\r\n]*",
    function(prefix) return prefix .. value end
  )
  if count == 0 then
    local nl = contents:find("\r\n", 1, true) and "\r\n" or "\n"
    local header = "[toolbar button states]"
    local s = (contents:sub(1, #header) == header) and 1 or contents:find("\n" .. header, 1, true)
    if s then
      local eol = contents:find("\n", s + (s == 1 and 0 or 1), true)
      if not eol then contents = contents .. nl; eol = #contents end   -- header was the last line
      new_contents = contents:sub(1, eol) .. key .. "=" .. value .. nl .. contents:sub(eol + 1)
    else
      if contents ~= "" and not contents:match("\n$") then contents = contents .. nl end
      new_contents = contents .. header .. nl .. key .. "=" .. value .. nl
    end
  end
  if new_contents == contents then return true end

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

--Script: Daniel_Floating Mixer.lua
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS24ce39b36555a74bc155ee3678a8a65a7ba15bd0"), 0)
