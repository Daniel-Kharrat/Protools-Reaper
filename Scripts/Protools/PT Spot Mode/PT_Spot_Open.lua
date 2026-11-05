-- @description PT Spot v11 - Open / update selection (singleton)
-- @author Antoniondc
-- @version 1.0

local R = reaper
local BUS = 'PT_SPOT_SINGLETON_V11'
local _, source_file = R.get_action_context()
local folder = source_file and source_file:match('^(.*[/\\])')
if not folder then R.MB('Pasta do PT Spot não encontrada.', 'PT Spot', 0); return end
local dialog_path = folder .. 'PT_Spot_Dialog.lua'
local file = io.open(dialog_path, 'rb')
if not file then
  R.MB('PT_Spot_Dialog.lua não encontrado na pasta.', 'PT Spot', 0)
  return
end
file:close()

local function valid_item(item)
  return item and R.ValidatePtr2(0, item, 'MediaItem*')
end
local mx, my = R.GetMousePosition()
local hovered = R.GetItemFromPoint(mx, my, true)
local count = R.CountSelectedMediaItems(0)
local selected = {}
if valid_item(hovered) and R.IsMediaItemSelected(hovered) and count > 1 then
  for i = 0, count-1 do selected[#selected+1] = R.GetSelectedMediaItem(0, i) end
elseif valid_item(hovered) then
  selected[1] = hovered
else
  for i = 0, count-1 do selected[#selected+1] = R.GetSelectedMediaItem(0, i) end
end
-- Envie também a seleção vazia: o diálogo usa isso para se fechar.
if #selected == 0 then
  local project = R.EnumProjects(-1, '')
  if project then
    local now = R.time_precise()
    R.SetExtState(BUS, 'request', string.format('%.9f', now) .. '\n' .. tostring(project) .. '\n', false)
  end
  return
end
if valid_item(hovered) then
  for i, item in ipairs(selected) do
    if item == hovered then
      table.remove(selected, i)
      table.insert(selected, 1, item)
      break
    end
  end
end

local guids = {}
for _, item in ipairs(selected) do
  if not valid_item(item) then return end
  local ok, guid = R.GetSetMediaItemInfo_String(item, 'GUID', '', false)
  if not ok or not guid or not guid:match('^%b{}$') then
    R.MB('Não foi possível identificar o GUID de um item.', 'PT Spot', 0)
    return
  end
  guids[#guids+1] = guid
end

local project = R.EnumProjects(-1, '')
if not project then return end
local now = R.time_precise()
-- O request é escrito de forma atômica em uma única chave. Seu ID muda
-- a cada clique, mesmo quando a seleção não muda.
local payload = string.format('%.9f', now) .. '\n' .. tostring(project)
  .. '\n' .. table.concat(guids, '\n')
R.SetExtState(BUS, 'request', payload, false)

local owner = R.GetExtState(BUS, 'owner')
local heartbeat = tonumber(R.GetExtState(BUS, 'heartbeat'))
if owner ~= '' and heartbeat and now-heartbeat >= -0.5 and now-heartbeat < 3 then
  return -- Uma única instância receberá a nova seleção no próximo defer.
end

-- Impede segundo lançamento enquanto a GUI está iniciando.
R.SetExtState(BUS, 'owner', 'STARTING', false)
R.SetExtState(BUS, 'heartbeat', tostring(now), false)
R.SetExtState(BUS, 'shutdown', '0', false)

local previous = R.GetExtState(BUS, 'dialog_command')
local id = previous ~= '' and R.NamedCommandLookup(previous) or 0
if id == 0 then
  id = R.AddRemoveReaScript(true, 0, dialog_path, true)
  if id and id > 0 then
    local name = R.ReverseNamedCommandLookup(id)
    if name and name ~= '' then
      if name:sub(1,1) ~= '_' then name = '_' .. name end
      R.SetExtState(BUS, 'dialog_command', name, false)
    end
  end
end
if not id or id <= 0 then
  R.DeleteExtState(BUS, 'owner', false)
  R.DeleteExtState(BUS, 'heartbeat', false)
  R.MB('Não foi possível registrar PT_Spot_Dialog.lua.', 'PT Spot', 0)
  return
end
R.Main_OnCommand(id, 0)
