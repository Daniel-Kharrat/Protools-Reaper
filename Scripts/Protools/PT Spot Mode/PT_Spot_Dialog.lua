-- @description PT Spot v11.1 - Spot Dialog / BWF + iXML / multiselecao
-- @author antoniondc
-- @version 1.0

local R = reaper
local PROJECT = 0
local KEY_ORIGINAL = 'P_EXT:PTSPOT_V4_ORIGINAL_SOURCE_SECONDS'
local OLD_ORIGINAL = 'P_EXT:PTSPOT_V2_ORIGINAL_SOURCE_SECONDS'
local KEY_USER = 'P_EXT:PTSPOT_V4_USER_POSITION'
local OLD_USER = 'P_EXT:PTSPOT_V2_USER_SOURCE_SECONDS'
local SCALES = { 'Bars|Beats', 'Min:Secs', 'Timecode', 'Feet+Frames', 'Samples', 'Absolute Frames', 'Seconds' }
local WIN_W, WIN_H = 324, 318
local LEFT_X, LABEL_RIGHT_X, EDIT_X = 10, 149, 155
local RIGHT_PAD = 10
local SCALE_BOX_W = 155
local ARROW_W = 23
local USER_BUTTON_W = 155

if not R.ImGui_CreateContext or not R.ImGui_BeginCombo or
   not R.ImGui_IsItemDeactivatedAfterEdit or not R.ImGui_IsKeyPressed or
   not R.ImGui_CalcTextSize or not R.ImGui_WindowFlags_NoTitleBar or
   not R.ImGui_GetMainViewport or not R.ImGui_SetNextWindowPos or
   (not R.ImGui_Viewport_GetWorkCenter and not R.ImGui_Viewport_GetCenter) then
  R.MB('Instale/atualize o ReaImGui pelo ReaPack.', 'PT Spot', 0)
  return
end
if (R.GetPlayState() & 4) ~= 0 then
  R.MB('Nao use o Spot Mode enquanto estiver gravando.', 'PT Spot', 0)
  return
end

local function valid_item(item)
  return item and R.ValidatePtr2(PROJECT, item, 'MediaItem*')
end
local function get_ext(ptr, is_take, key)
  local fn = is_take and R.GetSetMediaItemTakeInfo_String or R.GetSetMediaItemInfo_String
  local ok, value = fn(ptr, key, '', false)
  return ok and value or ''
end
local function set_ext(ptr, key, value)
  return R.GetSetMediaItemInfo_String(ptr, key, tostring(value), true)
end
local function saved_position(item, key)
  local str = get_ext(item, false, key)
  local val = tonumber(str)
  if val and val == val and val >= 0 and val < math.huge then return val end
  return nil
end
local function validate_position(value)
  return value and value == value and value >= -1e-7 and value < math.huge
end
local function notify(message)
  R.MB(message, 'PT Spot', 0)
end
local function round(n)
  return math.floor(n + 0.5)
end

-- BWF (bext.timeReference) e iXML sao somente leitura; nunca modificamos os WAVs.
local function wave_timecode(path)
  if not path then return nil, 'Ausente' end
  local file = io.open(path, 'rb')
  if not file then return nil, 'Arquivo inacessivel' end
  local header = file:read(12)
  if not header or #header < 12 or
    (header:sub(1,4) ~= 'RIFF' and header:sub(1,4) ~= 'RF64') or
    header:sub(9,12) ~= 'WAVE' then
    file:close()
    return nil, 'Nao WAV/RF64'
  end
  local sr, bwf, ixml, bext_text
  for _ = 1, 768 do
    local block = file:read(8)
    if not block or #block ~= 8 then break end
    local id, sz = block:sub(1,4), string.unpack('<I4', block, 5)
    local at = file:seek()
    if id == 'fmt ' and sz >= 8 then
      local data = file:read(math.min(sz, 40))
      if data and #data >= 8 then sr = string.unpack('<I4', data, 5) end
    elseif id == 'bext' and sz >= 346 then
      file:seek('set', at)
      bext_text = file:read(math.min(sz, 8192))
      file:seek('set', at + 338)
      local data = file:read(8)
      if data and #data == 8 then
        local lo, hi = string.unpack('<I4I4', data)
        bwf = lo + hi * 4294967296
      end
    elseif id == 'iXML' and sz < 2 * 1024 * 1024 then
      ixml = file:read(sz)
    end
    -- Em RF64, o chunk data pode ter tamanho sentinela sem ds64.
    if sz == 0xFFFFFFFF then break end
    if not file:seek('set', at + sz + sz % 2) then break end
  end
  file:close()
  local tc_rate, tc_drop
  local function parse_rate(value)
    if not value then return nil end
    local a, b = value:match('(%d+)%s*/%s*(%d+)')
    if a and b and tonumber(b) ~= 0 then return tonumber(a) / tonumber(b) end
    return tonumber(value:match('(%d+%.?%d*)'))
  end
  if ixml then
    tc_rate = parse_rate(ixml:match('<TIMECODE_RATE>%s*(.-)%s*</TIMECODE_RATE>'))
      or parse_rate(ixml:match('<MASTER_SPEED>%s*(.-)%s*</MASTER_SPEED>'))
    local flag = ixml:match('<TIMECODE_FLAG>%s*(.-)%s*</TIMECODE_FLAG>')
    if flag then
      local normalized=flag:upper():gsub('%s+',''):gsub('[%-_]','')
      if normalized=='NDF' or normalized=='ND' or normalized=='NONDROP' or normalized=='NONDF' then
        tc_drop=false
      elseif normalized=='DF' or normalized=='DROP' or normalized=='DROPFRAME' then
        tc_drop=true
      end
    end
  end
  if not tc_rate and bext_text then
    tc_rate = parse_rate(bext_text:match('zSPEED=(%S+)'))
  end
  if bwf and sr and sr > 0 then return bwf / sr, 'BWF bext', tc_rate, tc_drop end
  if ixml then
    local function xml_num(field)
      return tonumber(ixml:match('<' .. field .. '>%s*(%d+)%s*</' .. field .. '>'))
    end
    local hi = xml_num('TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_HI')
    local lo = xml_num('TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_LO')
    local rate = xml_num('TIMESTAMP_SAMPLE_RATE') or sr
    if hi and lo and rate and rate > 0 then
      return (hi * 4294967296 + lo) / rate, 'iXML timestamp', tc_rate, tc_drop
    end
  end
  return nil, 'Sem BWF/iXML temporal', tc_rate, tc_drop
end

local function source_path(take)
  local src = R.GetMediaItemTake_Source(take)
  if not src then return nil end
  for _=1,12 do
    local parent = R.GetMediaSourceParent(src)
    if not parent then break end
    src = parent
  end
  local path = R.GetMediaSourceFileName(src)
  if not path or path == '' then return nil end
  local f = io.open(path, 'rb')
  if f then f:close(); return path end
  if not path:match('^/') and not path:match('^%a:[/\\]') then
    local projdir = R.GetProjectPath('')
    path = projdir .. '/' .. path
  end
  return path
end

-- O script Open envia GUIDs ao diálogo via ExtState. Assim, um segundo
-- clique atualiza a ÚNICA GUI, sem lançar outra instância em defer.
local BUS = 'PT_SPOT_SINGLETON_V11'
local function project_identity()
  local project = R.EnumProjects(-1, '')
  return project and tostring(project) or ''
end
local function get_guid(item)
  local ok, guid = R.GetSetMediaItemInfo_String(item, 'GUID', '', false)
  return ok and guid or nil
end
local function selected_under_mouse()
  local mx, my = R.GetMousePosition()
  local hovered = R.GetItemFromPoint(mx, my, true)
  local count = R.CountSelectedMediaItems(PROJECT)
  local result = {}
  if valid_item(hovered) and R.IsMediaItemSelected(hovered) and count > 1 then
    for i=0,count-1 do result[#result+1]=R.GetSelectedMediaItem(PROJECT,i) end
  elseif valid_item(hovered) then
    result[1]=hovered
  else
    for i=0,count-1 do result[#result+1]=R.GetSelectedMediaItem(PROJECT,i) end
  end
  if valid_item(hovered) then
    for i,item in ipairs(result) do
      if item==hovered then table.remove(result,i); table.insert(result,1,item); break end
    end
  end
  return result
end
local function unpack_request(payload)
  if not payload or payload=='' then return nil end
  local seq, project, data = payload:match('^([^\n]+)\n([^\n]+)\n(.*)$')
  if not seq or project~=project_identity() then return nil end
  local guids={}
  for guid in data:gmatch('[^\n]+') do
    if not guid:match('^%b{}$') then return nil end
    guids[#guids+1]=guid
  end
  if #guids==0 then return {}, seq, '' end
  local items={}
  -- SWS é opcional: a busca pelo GUID possui fallback nativo.
  local lookup
  if type(R.BR_GetMediaItemByGUID)~='function' then
    lookup={}
    for index=0,R.CountMediaItems(PROJECT)-1 do
      local item=R.GetMediaItem(PROJECT,index)
      local guid=get_guid(item)
      if guid then lookup[guid]=item end
    end
  end
  for _,guid in ipairs(guids) do
    local item=lookup and lookup[guid] or R.BR_GetMediaItemByGUID(PROJECT,guid)
    if not valid_item(item) then return nil end
    items[#items+1]=item
  end
  return items, seq, table.concat(guids, '\n')
end
local project_offset, fps, drop
local function update_project_time_settings()
  project_offset=R.GetProjectTimeOffset(PROJECT,false) or 0
  fps,drop=R.TimeMap_curFrameRate(PROJECT)
  if not fps or fps<=0 then fps=24 end
end
local function make_entries(selection)
  local result={}
  local original_writes=0
  for _,item in ipairs(selection) do
    if not valid_item(item) then return nil,'Item was removed from the project.' end
    local take=R.GetActiveTake(item)
    if not take or R.TakeIsMIDI(take) then
      return nil,'Seleção contém item has no audio take.'
    end
    local position=R.GetMediaItemInfo_Value(item,'D_POSITION')
    local path=source_path(take)
    local timecode,format,source_fps,source_drop=wave_timecode(path)
    local original=tonumber(get_ext(take,true,KEY_ORIGINAL))
    if original==nil then original=tonumber(get_ext(take,true,OLD_ORIGINAL)) end
    if original==nil and timecode~=nil then original=timecode end
    if original~=nil and get_ext(take,true,KEY_ORIGINAL)=='' then
      local ok=R.GetSetMediaItemTakeInfo_String(take,KEY_ORIGINAL,
        string.format('%.12f',original),true)
      if ok then original_writes=original_writes+1 end
    end
    local takeoff=R.GetMediaItemTakeInfo_Value(take,'D_STARTOFFS')
    local user=saved_position(item,KEY_USER)
    if user==nil then
      local legacy=tonumber(get_ext(take,true,OLD_USER))
      if legacy and legacy>=0 then
        user=legacy+takeoff-project_offset
        if user>=0 then
          set_ext(item,KEY_USER,string.format('%.12f',user))
          original_writes=original_writes+1
        else user=nil end
      end
    end
    result[#result+1]={
      item=item,take=take,pos=position,
      len=R.GetMediaItemInfo_Value(item,'D_LENGTH'),
      snap=R.GetMediaItemInfo_Value(item,'D_SNAPOFFSET'),
      source_offset=takeoff,
      original=original,user=user,timecode=timecode,format=format,
      source_fps=source_fps,source_drop=source_drop,
    }
  end
  if #result==0 then return nil,'No audio item found.' end
  if original_writes>0 then R.MarkProjectDirty(PROJECT) end
  return result
end

local request_payload=R.GetExtState(BUS,'request')
local requested, first_seq, signature=unpack_request(request_payload)
local selected=requested or selected_under_mouse()
if #selected==0 then notify('Click an item or select media.'); return end
update_project_time_settings()
local entries, first_error=make_entries(selected)
if not entries then notify(first_error); return end
local anchor=entries[1]
local model_project=project_identity()
local last_request=request_payload
local last_signature=signature or ''
-- Follow the Transport time unit (projtimemode2). If it is set to
-- 'Use ruler time unit', follow the Arrange ruler (projtimemode).
-- SWS reads the current project's unsaved, live configuration.
-- This is NOT PROJECT_TIMEBASE, which controls item/tempo editing.
local PROJECT_CONFIG_MISSING = -999999
local function get_int_project_config(key)
  -- These are project-scoped settings. Do not fall back to the global SWS
  -- reader: its cached/global value can disagree with the active project.
  if not R.SNM_GetIntConfigVarEx then return nil end
  local proj = PROJECT
  if R.EnumProjects then
    local ok, current = pcall(R.EnumProjects, -1, '')
    if ok and current then proj = current end
  end
  local ok, value = pcall(R.SNM_GetIntConfigVarEx,
    proj, key, PROJECT_CONFIG_MISSING)
  if ok and type(value)=='number' and value~=PROJECT_CONFIG_MISSING then
    return value
  end
  return nil
end
-- Transport/ruler values can carry secondary-unit flags in upper bits.
-- Decode the low byte; only -1 means 'Use ruler time unit'.
local function decode_mode(raw, is_transport)
  if type(raw) ~= 'number' then return nil, 'unavailable' end
  raw = math.floor(raw)
  if raw == -1 then
    return nil, 'follow ruler'
  end
  if raw < 0 then return nil, 'negative/unknown' end
  local primary = raw & 0xFF
  if primary <= 11 then return primary, (raw == primary and 'direct' or 'flags') end
  return nil, 'unrecognized: '..tostring(raw)
end
local function mode_to_scale(mode)
  if mode==0 or mode==11 then return 2 end          -- Minutes:Seconds
  if mode==1 or mode==2 or mode==6 or mode==7 or mode==10 then return 1 end -- Bars|Beats, including mixed display
  if mode==3 then return 7 end                     -- Seconds
  if mode==4 then return 5 end                     -- Samples
  if mode==5 then return 3 end                     -- Timecode
  if mode==8 then return 6 end                     -- Absolute Frames
  return nil
end
-- Native ruler-action fallback for installations without SWS.
local function ruler_via_native_actions()
  if not R.GetToggleCommandState then return nil end
  local actions = {
    {40365,0}, {40366,1}, {40367,2}, {40368,3},
    {40369,4}, {40370,5}, {41916,6}, {41918,7}, {41973,8}
  }
  for _, pair in ipairs(actions) do
    local ok, checked = pcall(R.GetToggleCommandState, pair[1])
    if ok and checked==1 then return pair[2] end
  end
  return nil
end
-- Last resort: older heuristic, intentionally LOW confidence.
local function time_scale_fallback()
  local samples = {1.234567,73.245678,1003.567891}
  local candidates = {{4,5},{5,3},{2,1},{1,1},{0,2},{3,2}}
  local winner, best_score=nil,0
  for _, candidate in ipairs(candidates) do
    local score=0
    for _, position in ipairs(samples) do
      local ok_default, default=pcall(R.format_timestr_pos,position,'',-1)
      local ok_explicit, explicit=pcall(R.format_timestr_pos,position,'',candidate[1])
      if ok_default and ok_explicit and
         type(default)=='string' and type(explicit)=='string' and
         default==explicit then score=score+1 end
    end
    if score>best_score then winner,best_score=candidate[2],score end
  end
  if winner and best_score>=2 then return winner end
  return 3
end
local function detect_project_time_scale()
  local transport_raw=get_int_project_config('projtimemode2')
  local transport=decode_mode(transport_raw, true)
  local ui=mode_to_scale(transport)
  if ui then return ui end
  -- Transport is set to 'Use ruler time unit', or SWS could not read it.
  local ruler_raw=get_int_project_config('projtimemode')
  local ruler=decode_mode(ruler_raw, false)
  ui=mode_to_scale(ruler)
  if ui then return ui end
  local fallback_ui=mode_to_scale(ruler_via_native_actions())
  if fallback_ui then return fallback_ui end
  return time_scale_fallback()
end
local scale = detect_project_time_scale()
local manual_scale = false
local preview = anchor.pos
local edited = {}
local focus_next
local pending_row
local open = true
local ctx = R.ImGui_CreateContext('PT Spot v11')
local F_AUTOS = R.ImGui_InputTextFlags_AutoSelectAll()
local F_READ = R.ImGui_InputTextFlags_ReadOnly()
local F_INPUT = F_AUTOS
local offsets = {start=0, sync=anchor.snap, finish=anchor.len}

-- Exclusividade: somente a instância que detém esta chave desenha a janela.
local owner=string.format('%.9f',R.time_precise())..':'..tostring(anchor.item)
R.SetExtState(BUS,'owner',owner,false)
R.SetExtState(BUS,'heartbeat',tostring(R.time_precise()),false)
R.SetExtState(BUS,'shutdown','0',false)
local heartbeat_last=0
local function release_owner()
  if R.GetExtState(BUS,'owner')==owner then
    R.DeleteExtState(BUS,'owner',false)
    R.DeleteExtState(BUS,'heartbeat',false)
  end
end
if R.atexit then R.atexit(release_owner) end

-- Escape is handled by ReaImGui only. No js_ReaScriptAPI used.
-- Outside dialog focus, Escape is not captured (no global keyboard hook).

local function digits(text)
  local parts = {}
  for x in tostring(text):gmatch('%d+') do parts[#parts+1]=x end
  return parts
end
local function specs()
  if scale==1 then return {width={7,2,3},sep={'|','|'}, max={7,2,3}} end
  if scale==2 then return {width={5,2,3},sep={':','.'}, max={5,2,3}} end
  if scale==3 then return {width={2,2,2,2},sep={':',':',drop and ';' or ':'}, max={2,2,2,2}} end
  if scale==4 then return {width={7,2},sep={'+'}, max={7,2}} end
  if scale==7 then return {width={16},sep={},max={16}} end
  return {width={13},sep={},max={13}}
end
local function fmt(sec, is_length, at)
  at = at or 0
  sec = math.max(0,sec)
  if scale==1 then
    local value = is_length and R.format_timestr_len(sec,'',at,2) or R.format_timestr_pos(sec,'',2)
    return (value:gsub('%.','|'))
  elseif scale==2 then
    local n=round(sec*1000)
    return string.format('%d:%02d.%03d',math.floor(n/60000),math.floor(n/1000)%60,n%1000)
  elseif scale==3 then
    return is_length and R.format_timestr_len(sec,'',at,5) or R.format_timestr_pos(sec,'',5)
  elseif scale==4 then
    local frame=round((sec+(is_length and 0 or project_offset))*fps)
    return string.format('%d+%02d',math.floor(frame/16),frame%16)
  elseif scale==6 then
    return tostring(round((sec+(is_length and 0 or project_offset))*fps))
  elseif scale==7 then
    return string.format('%.3f',sec)
  else
    return is_length and R.format_timestr_len(sec,'',at,4) or R.format_timestr_pos(sec,'',4)
  end
end
local function parts_at(sec, is_length, at)
  if scale==7 then return {fmt(sec,is_length,at)} end
  local vals=digits(fmt(sec,is_length,at))
  local s=specs()
  for i=1,#s.width do vals[i] = vals[i] or '0' end
  return vals
end
local function parse_parts(vals)
  if scale==7 then
    local seconds=tonumber(vals[1])
    if not seconds or seconds<0 or seconds==math.huge then return nil,'Seconds invalido' end
    return seconds
  end
  local s=specs()
  local n={}
  for i=1,#s.width do
    if not vals[i] or vals[i]=='' or not vals[i]:match('^%d+$') then return nil,'Campo incompleto' end
    n[i]=tonumber(vals[i])
  end
  if scale==1 then
    if n[1]<1 or n[2]<1 or n[3]>=100 then return nil,'Bars|Beats invalido' end
    return R.parse_timestr_pos(string.format('%d.%d.%02d',n[1],n[2],n[3]),2)
  elseif scale==2 then
    if n[2]>=60 or n[3]>=1000 then return nil,'Min:Secs invalido' end
    return n[1]*60+n[2]+n[3]/1000
  elseif scale==3 then
    if n[2]>=60 or n[3]>=60 or n[4]>=math.ceil(fps-0.001) then
      return nil,'Invalid timecode for the project frame rate'
    end
    if drop and n[3]==0 and n[2]%10~=0 then
      local skipped = math.abs(fps-59.94)<0.1 and 4 or 2
      if n[4]<skipped then return nil,'Frame inexistente (drop-frame)' end
    end
    local tc=string.format('%02d:%02d:%02d%s%02d',n[1],n[2],n[3],drop and ';' or ':',n[4])
    return R.parse_timestr_pos(tc,5)
  elseif scale==4 then
    if n[2]>=16 then return nil,'Feet+Frames: frames devem ser 0-15' end
    return (n[1]*16+n[2])/fps - project_offset
  elseif scale==6 then
    return n[1]/fps - project_offset
  end
  return R.parse_timestr_pos(tostring(n[1]),4)
end
local function refresh_fields(except)
  for key,offset in pairs(offsets) do
    if key~=except then edited[key]=parts_at(preview+offset,false,0) end
  end
end
refresh_fields()

local function refresh_entries()
  for _,e in ipairs(entries) do e.pos = R.GetMediaItemInfo_Value(e.item,'D_POSITION') end
  preview = anchor.pos
  refresh_fields()
end
local session_matches
local function movement(target_positions, label)
  if not session_matches() then notify('Project changed; reopen the Spot Dialog.'); return false end
  if (R.GetPlayState() & 4) ~= 0 then notify('Gravacao em andamento.'); return false end
  for i,e in ipairs(entries) do
    if not valid_item(e.item) or
      (math.floor(R.GetMediaItemInfo_Value(e.item,'C_LOCK')) & 1)~=0 then
      notify('Operation canceled: a locked or deleted item was found. No items were moved.')
      return false
    end
    if not validate_position(target_positions[i]) then
      notify('Operacao cancelada: algum timestamp ficaria antes do zero do projeto.')
      return false
    end
  end
  R.Undo_BeginBlock2(PROJECT)
  local ok = true
  for i,e in ipairs(entries) do
    if not R.SetMediaItemPosition(e.item, math.max(0,target_positions[i]), false) then
      ok=false; break
    end
    R.UpdateItemInProject(e.item)
  end
  if not ok then
    -- Rollback da operacao se houver falha no REAPER.
    for _,e in ipairs(entries) do R.SetMediaItemPosition(e.item,e.pos,false) end
    R.UpdateArrange()
    R.Undo_EndBlock2(PROJECT,'PT Spot - movimento nao realizado',4)
    notify('Falha durante movimentacao. Posicoes anteriores restauradas.')
    return false
  end
  R.UpdateArrange()
  R.Undo_EndBlock2(PROJECT,label,4)
  refresh_entries()
  return true
end
local function move_to_reference(which)
  if which=='timecode' then
    local mismatched={}
    for i,e in ipairs(entries) do
      if e.source_fps and math.abs(e.source_fps-fps)>0.001 then
        mismatched[#mismatched+1]=string.format('Item %d: %.5g FPS',i,e.source_fps)
      end
    end
    if #mismatched>0 then
      local explanation='A taxa de quadros do arquivo difere da sessao (' ..
        string.format('%.5g',fps) .. ' FPS).\n' .. table.concat(mismatched,'\n') ..
        '\nA referencia BWF e por amostras, mas o timecode visual pode nao coincidir.\nContinuar?' 
      if R.MB(explanation,'PT Spot - Timecode FPS',4)~=6 then return end
    end
  end
  local targets={}
  for i,e in ipairs(entries) do
    local time
    if which=='original' then
      if e.original~=nil then time=e.original+e.source_offset-project_offset end
    elseif which=='user' then time=e.user
    else
      if e.timecode~=nil then
        time=e.timecode+e.source_offset-project_offset
      end
    end
    if time==nil then
      notify(string.format('Item %d/%d sem %s. Operacao cancelada para todos.',i,#entries,which))
      return
    end
    targets[i]=time
  end
  movement(targets,'PT Spot - '..which..' ('..#entries..' itens)')
end
local function move_manual(desired)
  if not validate_position(desired) then notify('Posicao manual anterior ao zero do projeto.'); return false end
  local delta=desired-anchor.pos
  local targets={}
  for i,e in ipairs(entries) do targets[i]=e.pos+delta end
  return movement(targets,'PT Spot - posicionar '..#entries..' itens')
end
local function save_user()
  if not session_matches() then notify('Project changed; reopen the Spot Dialog.'); return end
  if (R.GetPlayState() & 4)~=0 then notify('Gravacao em andamento.'); return end
  local overwrite=false
  for _,e in ipairs(entries) do
    if not valid_item(e.item) then notify('Item indisponivel.'); return end
    if e.user~=nil then overwrite=true end
  end
  if overwrite then
    local msg = #entries==1 and 'Substituir o User Timestamp existente?' or
      'Existem User Timestamps salvos nesta selecao. Sobrescrever os valores dos '..#entries..' itens?'
    if R.MB(msg,'PT Spot - User Timestamp',4)~=6 then return end
  end
  local before={}
  R.Undo_BeginBlock2(PROJECT)
  for i,e in ipairs(entries) do
    local pos=R.GetMediaItemInfo_Value(e.item,'D_POSITION')
    before[i]=get_ext(e.item,false,KEY_USER)
    local ok=set_ext(e.item,KEY_USER,string.format('%.12f',pos))
    if not ok then
      for j=1,i do set_ext(entries[j].item,KEY_USER,before[j]) end
      R.Undo_EndBlock2(PROJECT,'PT Spot - sem alteracao de User TS',4)
      notify('Nao foi possivel gravar User TS no projeto.'); return
    end
    e.user=pos
  end
  R.MarkProjectDirty(PROJECT)
  R.Undo_EndBlock2(PROJECT,'PT Spot - Set User Timestamp ('..#entries..' itens)',4)
end

-- Posicoes e larguras consistentes em todas as escalas.
-- Os campos de entrada sao centralizados por FramePadding calculado.
local function text_width(value)
  local w=R.ImGui_CalcTextSize(ctx, tostring(value))
  return w or 0
end
local function right_label(value)
  local width=text_width(value)
  R.ImGui_SetCursorPosX(ctx, math.max(LEFT_X,LABEL_RIGHT_X-width))
  R.ImGui_Text(ctx,value)
  R.ImGui_SameLine(ctx,0,0)
  R.ImGui_SetCursorPosX(ctx,EDIT_X)
end
local function ref_seconds(which)
  local e=anchor
  if which=='original' then
    if e.original~=nil then return e.original+e.source_offset-project_offset end
  elseif which=='user' then
    return e.user
  elseif which=='timecode' then
    if e.timecode~=nil then return e.timecode+e.source_offset-project_offset end
  end
  return nil
end
local function ref_text(which)
  if #entries>1 then return 'Múltiplas seleções' end
  local n=ref_seconds(which)
  if n==nil then return '--' end
  return fmt(n,false,0)
end
local function timestamp_row(value,which)
  right_label(value)
  local label = ref_text(which)
  R.ImGui_Text(ctx,label)
  R.ImGui_SameLine(ctx,0,0)
  -- Os tres botoes terminam exatamente na borda direita do Time Scale.
  R.ImGui_SetCursorPosX(ctx,EDIT_X+SCALE_BOX_W-ARROW_W)
  if R.ImGui_Button(ctx,'^##'..which,ARROW_W,21) then move_to_reference(which) end
end
local function field_width(part)
  if scale==1 then return ({61,24,35})[part] end
  if scale==2 then return ({54,24,35})[part] end
  if scale==3 then return 31 end
  if scale==4 then return ({81,28})[part] end
  return 145
end
local function centered_text_input(id, value, flags, width)
  R.ImGui_SetNextItemWidth(ctx,width)
  local pad
  if scale==5 then pad=4
  else pad=math.max(3, math.floor((width-text_width(value))/2)) end
  if R.ImGui_PushStyleVar and R.ImGui_StyleVar_FramePadding then
    R.ImGui_PushStyleVar(ctx,R.ImGui_StyleVar_FramePadding(),pad,2)
    local changed, result=R.ImGui_InputText(ctx,id,value,flags)
    R.ImGui_PopStyleVar(ctx)
    return changed,result
  end
  return R.ImGui_InputText(ctx,id,value,flags)
end
local function segmented_row(value,name,readonly)
  local spec=specs()
  right_label(value)
  local parts=readonly and parts_at(anchor.len,true,anchor.pos) or edited[name]
  if not parts then return end
  local commit=false
  local deactivated=false
  for p=1,#spec.width do
    if p>1 then
      R.ImGui_SameLine(ctx,0,1)
      R.ImGui_Text(ctx,spec.sep[p-1])
      R.ImGui_SameLine(ctx,0,1)
    end
    if focus_next==name..'_'..p then
      R.ImGui_SetKeyboardFocusHere(ctx)
      focus_next=nil
    end
    local flags=readonly and F_READ or F_INPUT
    local changed,v=centered_text_input('##'..name..'_'..p,parts[p] or '0',flags,field_width(p))
    if not readonly then
      if changed then
        local jump=v:match('[|:+.;]$')~=nil
        v=v:gsub('[^%d]',''):sub(1,spec.max[p])
        parts[p]=v
        edited[name]=parts
        pending_row=name
        if (jump or #v>=spec.max[p]) and p<#spec.width then
          focus_next=name..'_'..(p+1)
        elseif (jump or #v>=spec.max[p]) and p==#spec.width then
          commit=true
        end
      end
      if R.ImGui_IsItemDeactivatedAfterEdit(ctx) then deactivated=true end
    end
    if p<#spec.width then R.ImGui_SameLine(ctx,0,1) end
  end
  if not readonly and pending_row==name and (commit or deactivated) then
    local target,err=parse_parts(parts)
    if target==nil then
      if deactivated then notify(err or 'Valor invalido.') end
    else
      if move_manual(target-offsets[name]) then pending_row=nil end
    end
  end
end
local function centered_title()
  local title='Spot Mode'
  if #entries == 1 then
    local _, item_name = R.GetSetMediaItemTakeInfo_String(anchor.take, 'P_NAME', '', false)
    if not item_name or item_name == '' then
      local source = R.GetMediaItemTake_Source(anchor.take)
      local _, path = R.GetMediaSourceFileName(source, '')
      item_name = path and path:match('([^/\\]+)$') or ''
    end
    if item_name ~= '' then title = 'Spot Mode — '..item_name end
  end
  R.ImGui_SetCursorPosX(ctx,(WIN_W-text_width(title))/2)
  R.ImGui_Text(ctx,title)
end
local combo_open_last_frame = false
local combo_open_this_frame = false
local function combo_scale()
  right_label('Time Scale:')
  -- A escala escolhida sempre aparece, tambem em selecao multipla.
  local shown = SCALES[scale]
  local width = SCALE_BOX_W
  local pad = math.max(3, math.floor((width-20-text_width(shown))/2))
  R.ImGui_SetNextItemWidth(ctx, width)
  local pushed = R.ImGui_PushStyleVar and R.ImGui_PopStyleVar and R.ImGui_StyleVar_FramePadding
  if pushed then R.ImGui_PushStyleVar(ctx, R.ImGui_StyleVar_FramePadding(), pad, 2) end
  local expanded = false
  local ok_combo, combo_err = xpcall(function()
    expanded = R.ImGui_BeginCombo(ctx, '##scale', shown)
    combo_open_this_frame = expanded
    if expanded then
      for i, entry in ipairs(SCALES) do
        if R.ImGui_Selectable(ctx, entry, scale == i) then
          scale = i
          manual_scale = true
          pending_row = nil
          focus_next = nil
          refresh_fields()
        end
      end
    end
  end, debug.traceback)
  -- Sempre equilibrar a pilha de popups/estilos, inclusive em caso de erro.
  if expanded then R.ImGui_EndCombo(ctx) end
  if pushed then R.ImGui_PopStyleVar(ctx) end
  if not ok_combo then error(combo_err, 0) end
end
local function closing_buttons()
  local gap, height = 5, 24
  -- The group begins at the same X as the editor fields, centered INSIDE
  -- the right-hand input column rather than across the entire window.
  local width = SCALE_BOX_W
  local w = math.floor((width-gap)/2)
  local start = EDIT_X + math.floor((width-(2*w+gap))/2)
  R.ImGui_SetCursorPosX(ctx, start)
  -- Center vertically within the footer after the separator.
  if R.ImGui_GetCursorPosY and R.ImGui_SetCursorPosY then
    local current_y=R.ImGui_GetCursorPosY(ctx)
    local footer_bottom=WIN_H-10
    local target_y=current_y+math.max(0,(footer_bottom-current_y-height)/2)
    R.ImGui_SetCursorPosY(ctx,target_y)
  end
  if R.ImGui_Button(ctx, 'Close', w, height) then open=false end
  R.ImGui_SameLine(ctx, 0, gap)
  if R.ImGui_Button(ctx, 'OK', w, height) then open=false end
end
-- ESC: o combo usa a primeira tecla para fechar a lista nativamente.
-- Somente um segundo ESC, sem dropdown aberto, fecha o Spot Dialog.
-- A solicitação de foco dura apenas alguns frames após CLICAR em outro item.
-- SetNextWindowFocus organiza as janelas ImGui, mas por si só não devolve o
-- foco NATIVO do macOS após um clique na timeline do REAPER.
local position_initially = true
local native_focus_pending = true
local native_focus_attempts = 0
local native_focus_limit = 3

-- SWS oferece as rotinas nativas de janela (C++/SWELL, sem JavaScript).
-- Falha segura: na ausência de uma janela identificável não focar a janela
-- principal, outra aplicação, nem qualquer HWND desconhecido.
local function activate_native_window()
  if type(R.BR_Win32_FindWindowEx) ~= 'function' or
     type(R.BR_Win32_SetForegroundWindow) ~= 'function' then
    return false
  end
  local hwnd
  -- ImGui oculta a barra de título, não o título interno da janela.
  for _, candidate in ipairs({'Spot Dialog', 'Spot Dialog##PTSpotV10'}) do
    local ok, found = pcall(R.BR_Win32_FindWindowEx,
      '0', '0', '', candidate, false, true)
    if ok and found and tostring(found) ~= '0' then
      if type(R.BR_Win32_IsWindow) ~= 'function' or
         R.BR_Win32_IsWindow(found) then
        hwnd = found
        break
      end
    end
  end
  if not hwnd then return false end
  local ok, status = pcall(R.BR_Win32_SetForegroundWindow, hwnd)
  if not ok or status == 0 or status == false then return false end
  if type(R.BR_Win32_SetFocus) == 'function' then
    pcall(R.BR_Win32_SetFocus, hwnd)
  end
  return true
end

local function center_first_open()
  if not position_initially then return end
  local viewport = R.ImGui_GetMainViewport(ctx)
  local x, y
  if R.ImGui_Viewport_GetWorkCenter then
    x, y = R.ImGui_Viewport_GetWorkCenter(viewport)
  else
    x, y = R.ImGui_Viewport_GetCenter(viewport)
  end
  R.ImGui_SetNextWindowPos(ctx, x, y, R.ImGui_Cond_Always(), 0.5, 0.5)
  if R.ImGui_SetNextWindowFocus then R.ImGui_SetNextWindowFocus(ctx) end
  position_initially = false
end

local function draw_contents()
  centered_title()
  R.ImGui_Separator(ctx)
  right_label('Current Timecode:')
  local current = R.format_timestr_pos(anchor.pos, '', 5)
  R.ImGui_Text(ctx, current)
  R.ImGui_Separator(ctx)
  -- O Time Scale pertence ao mesmo bloco dos quatro campos de tempo.
  combo_scale()
  segmented_row('Start:', 'start', false)
  segmented_row('Sync Point:', 'sync', false)
  segmented_row('End:', 'finish', false)
  segmented_row('Duration:', 'duration', true)
  R.ImGui_Separator(ctx)
  timestamp_row('Original Time Stamp:', 'original')
  timestamp_row('Timecode:', 'timecode')
  timestamp_row('User Time Stamp:', 'user')
  R.ImGui_SetCursorPosX(ctx,math.floor((WIN_W-USER_BUTTON_W)/2))
  if R.ImGui_Button(ctx, 'Set User Timestamp', USER_BUTTON_W, 22) then save_user() end
  R.ImGui_Separator(ctx)
  closing_buttons()
end

-- Receber nova seleção sem criar outra janela ImGui.
local function receive_selection()
  local payload=R.GetExtState(BUS,'request')
  if payload=='' or payload==last_request then return true end
  last_request=payload
  local targets,seq,new_signature=unpack_request(payload)
  if not targets then
    -- Pode ter mudado o projeto ou o item pode ter sido excluído.
    return false
  end
  if #targets == 0 then
    open = false
    return false
  end
  if new_signature==last_signature then
    -- Até se o mesmo item for clicado, devolver o foco uma única vez.
    native_focus_pending = true
    native_focus_attempts = 0
    return true
  end
  update_project_time_settings()
  local next_entries,error_message=make_entries(targets)
  if not next_entries then
    notify(error_message)
    return false
  end
  entries=next_entries
  anchor=entries[1]
  model_project=project_identity()
  last_signature=new_signature
  scale=detect_project_time_scale()
  manual_scale=false
  preview=anchor.pos
  edited={}
  focus_next=nil
  pending_row=nil
  offsets={start=0,sync=anchor.snap,finish=anchor.len}
  refresh_fields()
  combo_open_last_frame=false
  combo_open_this_frame=false
  -- Preservar a posição da janela na troca. Só centralizar na primeira abertura.
  native_focus_pending=true
  native_focus_attempts=0
  return true
end

session_matches=function()
  return project_identity()==model_project
end

-- Close if the user changes the transport cursor, time selection, or visible Arrange range.
local function capture_context_state()
  local cursor = R.GetCursorPositionEx and R.GetCursorPositionEx(PROJECT) or R.GetCursorPosition()
  local ts_start, ts_end = R.GetSet_LoopTimeRange2(PROJECT, false, false, 0, 0, false)
  local view_start, view_end = R.GetSet_ArrangeView2(PROJECT, false, 0, 0, 0, 0)
  return {cursor=cursor, ts_start=ts_start, ts_end=ts_end,
    view_start=view_start, view_end=view_end}
end
local initial_context_state = capture_context_state()
local function context_changed()
  local current = capture_context_state()
  local previous = initial_context_state
  local eps = 0.00001
  -- While playing or paused, the play cursor moves by itself; do not treat that as a user seek.
  local transport_state = R.GetPlayState()
  local stopped = (transport_state & 1) == 0 and (transport_state & 2) == 0
  if stopped and math.abs(current.cursor-previous.cursor)>eps then return true end
  if math.abs(current.ts_start-previous.ts_start)>eps or
     math.abs(current.ts_end-previous.ts_end)>eps or
     math.abs(current.view_start-previous.view_start)>eps or
     math.abs(current.view_end-previous.view_end)>eps then return true end
  return false
end

local function loop()
  if not open then release_owner(); return end
  if R.GetExtState(BUS,'owner')~=owner or
     R.GetExtState(BUS,'shutdown')=='1' then
    open=false
    release_owner()
    return
  end
  local now=R.time_precise()
  if now-heartbeat_last>=0.1 then
    R.SetExtState(BUS,'heartbeat',tostring(now),false)
    heartbeat_last=now
  end
  if not receive_selection() then
    open=false
    release_owner()
    return
  end
  local detected_scale=not manual_scale and detect_project_time_scale() or nil
  if detected_scale and detected_scale~=scale then
    scale=detected_scale
    refresh_fields()
  end
  if not session_matches() or context_changed() then
    open=false
    release_owner()
    return
  end
  R.ImGui_SetNextWindowSize(ctx, WIN_W, WIN_H, R.ImGui_Cond_Always())
  center_first_open()
  if native_focus_pending and R.ImGui_SetNextWindowFocus then
    R.ImGui_SetNextWindowFocus(ctx)
  end
  local flags = R.ImGui_WindowFlags_NoResize() | R.ImGui_WindowFlags_NoCollapse() |
    R.ImGui_WindowFlags_NoTitleBar() | R.ImGui_WindowFlags_NoSavedSettings() |
    R.ImGui_WindowFlags_NoScrollbar()
  local ok_begin, visible, still_open = pcall(
    R.ImGui_Begin, ctx, 'Spot Dialog##PTSpotV10', true, flags)
  if not ok_begin then
    open = false
    notify('Erro ao iniciar a janela ImGui: ' .. tostring(visible))
    return
  end
  open = still_open
  local pressed_escape = false
  local any_popup_open = false
  local ok_draw, draw_error = true, nil
  if visible then
    combo_open_this_frame = false
    ok_draw, draw_error = xpcall(function()
      draw_contents()
      pressed_escape = R.ImGui_IsKeyPressed(ctx, R.ImGui_Key_Escape(), false)
      if R.ImGui_IsPopupOpen and R.ImGui_PopupFlags_AnyPopup then
        any_popup_open = R.ImGui_IsPopupOpen(
          ctx, '', R.ImGui_PopupFlags_AnyPopup())
      end
    end, debug.traceback)
  end
  -- ImGui_End deve ser chamado mesmo quando Begin retorna visible=false.
  local ok_end, end_error = pcall(R.ImGui_End, ctx)
  if not ok_end or not ok_draw then
    open = false
    local error_text = not ok_draw and draw_error or end_error
    R.ShowConsoleMsg('[PT Spot v11] ' .. tostring(error_text) .. '\n')
    notify('Error drawing the Spot Dialog. See the ReaScript console.')
    return
  end
  if pressed_escape and not combo_open_last_frame and
     not combo_open_this_frame and not any_popup_open then
    open = false
  end
  combo_open_last_frame = combo_open_this_frame
  if open and native_focus_pending then
    native_focus_attempts = native_focus_attempts + 1
    if activate_native_window() or native_focus_attempts >= native_focus_limit then
      native_focus_pending = false
    end
  end
  if open then R.defer(loop) else release_owner() end
end
R.defer(loop)
