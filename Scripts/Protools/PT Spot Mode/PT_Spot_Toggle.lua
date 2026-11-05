-- @description PT Spot v11 - Alternar Spot por clique na mídia
-- @author antoniondc
-- @version 1.0

local R = reaper

-- Mesma seção persistente das versões 6 a 10.2, para permitir desligar
-- uma atribuição existente e recuperar os Mouse Modifiers originais.
local SECTION = 'PT_SPOT_TOGGLE_V6'
local CONTEXTS = { 'MM_CTX_ITEM_CLK', 'MM_CTX_ITEMLOWER_CLK' }
local CLICK_FLAG = 0
local OPTIONS_FLAG = 1024
local OPTIONS_SPOT = '3' -- Não mover cursor (1) nem alterar a seleção (2).

local _, script_path, action_section, action_id = R.get_action_context()
local folder = script_path and script_path:match('^(.*[/\\])')
if not folder then
  R.MB('Não foi possível identificar a pasta do Toggle.', 'PT Spot', 0)
  return
end

local dialog_path = folder .. 'PT_Spot_Open.lua'
local file = io.open(dialog_path, 'rb')
if not file then
  R.MB('PT_Spot_Open.lua precisa estar na mesma pasta do Toggle.', 'PT Spot', 0)
  return
end
file:close()

local function key(context, field)
  if field == 'previous' then return 'previous_' .. context end
  return 'flags_' .. context
end

local function token(value)
  return tostring(value or ''):match('^%s*(%S+)') or ''
end

local function named_id(value)
  local id = token(value)
  if id:match('^RS') then id = '_' .. id end
  return id
end

-- O REAPER pode devolver tanto o _RS... quanto o número do comando,
-- com ou sem o sufixo " c". Comparamos o comando resolvido, não strings.
local function is_spot(value, name, numeric_id)
  local id = named_id(value)
  if id == '' then return false end
  if name ~= '' and id == name then return true end
  if numeric_id and numeric_id > 0 and tonumber(id) == numeric_id then
    return true
  end
  if id:sub(1, 1) == '_' then
    local found = R.NamedCommandLookup(id)
    return found ~= 0 and found == numeric_id
  end
  return false
end

local function read(context)
  return {
    context = context,
    action = R.GetMouseModifier(context, CLICK_FLAG) or '',
    flags = R.GetMouseModifier(context, OPTIONS_FLAG) or '',
  }
end

local function set_action(context, value)
  if value == '' or value == '__DEFAULT__' then
    R.SetMouseModifier(context, CLICK_FLAG, '-1')
  else
    R.SetMouseModifier(context, CLICK_FLAG, value)
  end
end

local function restore(context, action, flags)
  set_action(context, action)
  -- As opções só fazem sentido quando há um comando na atribuição.
  if flags ~= nil and flags ~= '' then
    R.SetMouseModifier(context, OPTIONS_FLAG, flags)
  end
end

local function set_toolbar(enabled)
  if action_id and action_id > 0 then
    R.SetToggleCommandState(action_section, action_id, enabled and 1 or 0)
    R.RefreshToolbar2(action_section, action_id)
  end
end

local function error_dialog(message)
  R.MB(message, 'PT Spot - Mouse Modifiers', 0)
end

local stored_name = named_id(R.GetExtState(SECTION, 'command'))
local stored_id = stored_name ~= '' and R.NamedCommandLookup(stored_name) or 0
local before = {}
for i, context in ipairs(CONTEXTS) do before[i] = read(context) end

-- Se a versão anterior já deixou o clique com Spot, a primeira execução
-- desta versão DESLIGA, sem tentar sobrescrever os backups existentes.
local already_on = false
for _, saved in ipairs(before) do
  if is_spot(saved.action, stored_name, stored_id) then
    already_on = true
    break
  end
end

if already_on then
  local missing = {}
  for _, saved in ipairs(before) do
    if R.GetExtState(SECTION, key(saved.context, 'previous')) == '' then
      missing[#missing + 1] = saved.context
    end
  end
  if #missing > 0 then
    error_dialog('Spot está atribuído, mas não existe cópia de segurança de: '
      .. table.concat(missing, ', ') .. '\n'
      .. 'Restaure essas preferências manualmente antes de desativar.')
    set_toolbar(true)
    R.defer(function() end)
    return
  end

  for _, saved in ipairs(before) do
    local previous = R.GetExtState(SECTION, key(saved.context, 'previous'))
    local previous_flags = R.GetExtState(SECTION, key(saved.context, 'flags'))
    restore(saved.context, previous, previous_flags)
  end

  -- Somente remover os backups depois que ambos foram restaurados.
  local success = true
  for _, saved in ipairs(before) do
    local restored = R.GetMouseModifier(saved.context, CLICK_FLAG) or ''
    local previous = R.GetExtState(SECTION, key(saved.context, 'previous'))
    if previous ~= '' and previous ~= '__DEFAULT__' then
      if token(restored) ~= token(previous) then success = false end
    end
  end
  if not success then
    error_dialog('A restauração dos Mouse Modifiers não foi confirmada. '
      .. 'As cópias continuam salvas; confira Preferences > Mouse Modifiers.')
    set_toolbar(true)
    R.defer(function() end)
    return
  end
  for _, saved in ipairs(before) do
    R.DeleteExtState(SECTION, key(saved.context, 'previous'), true)
    R.DeleteExtState(SECTION, key(saved.context, 'flags'), true)
  end
  R.SetExtState(SECTION, 'state', 'OFF', true)
  -- Fechar a janela ativa ao desligar o modo, sem alterar nenhum timestamp.
  R.SetExtState('PT_SPOT_SINGLETON_V11', 'shutdown', '1', false)
  set_toolbar(false)
  R.defer(function() end)
  return
end

-- Registrar o Dialog na seção principal (0); isto permite associá-lo
-- diretamente aos contextos de clique, sem scripts em execução permanente.
local dialog_command = R.AddRemoveReaScript(true, 0, dialog_path, true)
if not dialog_command or dialog_command <= 0 then
  error_dialog('Não foi possível registrar o PT_Spot_Open.lua na Action List.')
  return
end
local raw = R.ReverseNamedCommandLookup(dialog_command)
local name = named_id(raw)
if name == '' then
  error_dialog('O comando de abertura do Spot não possui identificador válido.')
  return
end

local variants = {
  name .. ' c',
  name,
  tostring(dialog_command) .. ' c',
  tostring(dialog_command),
}

-- Para cada contexto, tentar a forma nominal e, quando necessário,
-- a forma numérica. Não interpretar uma representação diferente como falha.
local function assign(context)
  for _, value in ipairs(variants) do
    R.SetMouseModifier(context, CLICK_FLAG, value)
    local actual = R.GetMouseModifier(context, CLICK_FLAG) or ''
    if is_spot(actual, name, dialog_command) then
      R.SetMouseModifier(context, OPTIONS_FLAG, OPTIONS_SPOT)
      actual = R.GetMouseModifier(context, CLICK_FLAG) or ''
      if is_spot(actual, name, dialog_command) then return true, actual end
    end
  end
  return false, R.GetMouseModifier(context, CLICK_FLAG) or ''
end

-- Gravar as configurações originais ANTES de mudar o mouse.
-- Se o REAPER encerrar entre as atribuições, a próxima execução consegue
-- recuperar as preferências sem depender do estado da toolbar.
for _, saved in ipairs(before) do
  R.SetExtState(SECTION, key(saved.context, 'previous'),
    saved.action == '' and '__DEFAULT__' or saved.action, true)
  R.SetExtState(SECTION, key(saved.context, 'flags'), saved.flags, true)
end
R.SetExtState(SECTION, 'command', name, true)
R.SetExtState(SECTION, 'state', 'PENDING', true)

local successful = true
local reason = ''
for _, saved in ipairs(before) do
  local ok, assigned = assign(saved.context)
  if not ok then
    successful = false
    reason = saved.context .. ' retornou: ' .. tostring(assigned)
    break
  end
end

if not successful then
  -- Transação atômica: uma atribuição parcial não deixa o mouse alterado.
  for _, saved in ipairs(before) do
    restore(saved.context, saved.action, saved.flags)
  end
  local rolled_back = true
  for _, saved in ipairs(before) do
    local current = R.GetMouseModifier(saved.context, CLICK_FLAG) or ''
    if saved.action ~= '' and token(current) ~= token(saved.action) then
      rolled_back = false
    end
  end
  if rolled_back then
    for _, saved in ipairs(before) do
      R.DeleteExtState(SECTION, key(saved.context, 'previous'), true)
      R.DeleteExtState(SECTION, key(saved.context, 'flags'), true)
    end
    R.SetExtState(SECTION, 'state', 'OFF', true)
  end
  set_toolbar(false)
  error_dialog('Não foi possível ativar o clique para Spot.\n' .. reason
    .. '\nAs configurações anteriores foram restauradas.\n'
    .. 'Confirme que o Dialog está registrado na Action List.')
  R.defer(function() end)
  return
end

-- Confirmado: os backups já estão seguros, basta marcar o modo ativo.
R.SetExtState(SECTION, 'state', 'ON', true)
R.SetExtState('PT_SPOT_SINGLETON_V11', 'shutdown', '0', false)
set_toolbar(true)
R.defer(function() end)
