-- @description PT Copy to Send v1.2 - Compact dialog + send tap modes + FMP
-- @author antoniondc
-- @version 1.0
-- @about Requires ReaImGui; place PT_Send_Core.lua and PT_FMP_Engine.lua beside this file.
local R=reaper
if not (R.ImGui_CreateContext and R.ImGui_WindowFlags_NoTitleBar and R.GetSetTrackSendInfo_String) then
  R.MB('Instale/atualize o ReaImGui e o REAPER.','PT Copy to Send',0); return
end
local _,path=R.get_action_context()
local folder=path:match('^(.*[/\\])')
if not folder then R.MB('Script path not available.','PT Copy to Send',0);return end
local function load_core()
  local ok,mod=pcall(dofile,folder..'PT_Send_Core.lua')
  if not ok then R.MB(tostring(mod),'PT Copy to Send',0);return nil end
  return mod
end
local Core=load_core(); if not Core then return end
local NS=Core.NS
local alive=tonumber(Core.session_read('dialog_heartbeat')) or 0
if R.time_precise()-alive<1.5 and R.time_precise()>=alive then
  Core.session_write('dialog_show',1)
  return
end
local token=R.genGuid()
Core.session_write('dialog_owner',token)
Core.session_write('dialog_heartbeat',R.time_precise())
Core.session_write('dialog_show',0)
local ctx=R.ImGui_CreateContext('PT Copy to Send')
-- Compact PT-style layout (change these values to fine-tune the dialog).
-- Dimensions are ReaImGui units, not physical Retina screenshot pixels.
local UI = {
  WIDTH = 318,
  HEIGHT = 320,
  LABEL_X = 14,
  CONTROL_X = 79,
  RIGHT_PADDING = 12,
  BUTTON_WIDTH = 107,
  BUTTON_HEIGHT = 24,
  BUTTON_GAP = 8,
}
local W,H=UI.WIDTH,UI.HEIGHT
local LEFT,EDIT,RIGHT=UI.LABEL_X,UI.CONTROL_X,UI.RIGHT_PADDING
local state={open=true,first=true,proj=nil,changed=-1, sends={}, destinations={}, selected={},
  copy_current=true,automation=false,volume=true,pan=false,mute=false,fmp=false,
  status='',dropdown=false,mode_dropdown=false,focus=false,window_x=nil,window_y=nil,send_mode=-1}
local fields={'copy_current','automation','volume','pan','mute','fmp'}
for _,k in ipairs(fields) do
  local v=Core.session_read('field_'..k)
  if v~='' then state[k]=v=='1' end
end
-- I_SENDMODE values per REAPER ReaScript API. -1 is UI-only: keep each send's mode.
local SEND_MODES={
  {value=-1, label='Keep current', short='Keep current'},
  {value=0, label='Post-Fader (Post-Pan)', short='Post-Fader (Post-Pan)'},
  {value=3, label='Pre-Fader (Post-FX)', short='Pre-Fader (Post-FX)'},
  {value=1, label='Pre-Fader (Pre-FX)', short='Pre-Fader (Pre-FX)'},
  {value=8, label='Pre-Receive (media and monitoring only)', short='Pre-Receive'},
}
local function mode_label(value)
  for _,mode in ipairs(SEND_MODES) do
    if mode.value==value then return mode.short end
  end
  return SEND_MODES[1].short
end
local saved_mode=tonumber(Core.session_read('field_send_mode'))
if saved_mode then
  for _,mode in ipairs(SEND_MODES) do
    if saved_mode==mode.value then state.send_mode=saved_mode;break end
  end
end
local function store()
  for _,k in ipairs(fields) do Core.session_write('field_'..k,state[k] and '1' or '0') end
  Core.session_write('field_send_mode',state.send_mode)
  if state.proj then Core.save_destination_selection(state.proj,state.selected) end
end
local function validate_selected()
  local alive={}
  for _,d in ipairs(state.destinations) do alive[d.guid]=true end
  for key in pairs(state.selected) do if not alive[key] then state.selected[key]=nil end end
end
local function refresh()
  local proj=R.EnumProjects(-1,'')
  if not proj then return end
  if proj~=state.proj then
    if state.proj then Core.save_destination_selection(state.proj,state.selected) end
    state.proj=proj;state.changed=-1
    state.selected=Core.destination_selection(proj)
  end
  local change=R.GetProjectStateChangeCount(proj)
  if change~=state.changed then
    state.sends,state.destinations=Core.all_sends(proj)
    validate_selected()
    state.changed=change
  end
end
local function count_selected_dest()
  local n=0
  for _,d in ipairs(state.destinations) do if state.selected[d.guid] then n=n+1 end end
  return n
end
local function preview()
  local names={}
  for _,d in ipairs(state.destinations) do if state.selected[d.guid] then names[#names+1]=d.name end end
  if #names==0 then return 'Select destinations...'
  elseif #names==#state.destinations then return 'All Sends ('..#names..')'
  elseif #names<=2 then return table.concat(names,', ')
  else return #names..' destinations selected' end
end
local function affected()
  local ops={}
  for _,s in ipairs(state.sends) do
    if R.IsTrackSelected(s.src) and state.selected[s.dguid] then ops[#ops+1]=s end
  end
  return ops
end
local function launch_engine()
  local t=tonumber(Core.session_read('engine_heartbeat')) or 0
  if R.time_precise()-t < 1.5 then return true end
  local engine=folder..'PT_FMP_Engine.lua'
  local f=io.open(engine,'rb')
  if not f then return false,'PT_FMP_Engine.lua not found' end
  f:close()
  local command=R.AddRemoveReaScript(true,0,engine,true)
  if not command or command==0 then return false,'Could not register FMP engine' end
  R.Main_OnCommand(command,0)
  return true
end
local function apply()
  refresh()
  local change_mode=state.send_mode~=-1
  if not (state.copy_current or state.fmp or change_mode) then
    state.status='Select Current Value, FMP or a send mode.';return false
  end
  if state.copy_current and not (state.volume or state.pan or state.mute) and not state.fmp and not change_mode then
    state.status='Select a parameter.';return false
  end
  local ops=affected()
  if #ops==0 then state.status='No existing sends match selected sources/destinations.';return false end
  local linked,skipped,updated,modes_changed,reactivated=0,0,0,0,0
  local snapshot={}
  for _,s in ipairs(ops) do
    snapshot[#snapshot+1]={src=s.src,idx=s.idx,
      vol=R.GetMediaTrackInfo_Value(s.src,'D_VOL'),
      pan=R.GetMediaTrackInfo_Value(s.src,'D_PAN'),
      mute=R.GetMediaTrackInfo_Value(s.src,'B_MUTE'),
      mode=R.GetTrackSendInfo_Value(s.src,0,s.idx,'I_SENDMODE')}
  end
  R.Undo_BeginBlock2(state.proj)
  R.PreventUIRefresh(1)
  local ok,err=xpcall(function()
    for _,s in ipairs(snapshot) do
      local effective_mode=s.mode
      if change_mode then
        effective_mode=state.send_mode
        if s.mode~=effective_mode then
          local changed=R.SetTrackSendInfo_Value(s.src,0,s.idx,'I_SENDMODE',effective_mode)
          if not changed then
            error('Failed to change send mode: '..tostring(s.idx))
          end
          modes_changed=modes_changed+1
        end
      end
      -- A linked Pre-Fader send already holds a copy of the source pan.
      -- When switching it to native Post-Pan, neutralize the additional
      -- send pan; otherwise source pan + send pan may pan the signal twice.
      -- Never reset an unrelated/unlinked send's deliberate pan offset.
      if s.mode~=0 and effective_mode==0 and
         Core.getstr(s.src,s.idx,Core.LINK_KEY)=='1' then
        R.SetTrackSendInfo_Value(s.src,0,s.idx,'D_PAN',0)
      end
      if state.copy_current then
        if state.volume then R.SetTrackSendInfo_Value(s.src,0,s.idx,'D_VOL',s.vol) end
        if state.mute then R.SetTrackSendInfo_Value(s.src,0,s.idx,'B_MUTE',s.mute) end
        if state.pan and not state.fmp then R.SetTrackSendInfo_Value(s.src,0,s.idx,'D_PAN',s.pan) end
        updated=updated+1
      end
      if state.fmp then
        if effective_mode==0 then
          skipped=skipped+1 -- Native post-pan inheritance; do not apply pan again.
        else
          Core.uid(s.src,s.idx,true)
          Core.setstr(s.src,s.idx,Core.LINK_KEY,'1')
          R.SetTrackSendInfo_Value(s.src,0,s.idx,'D_PAN',s.pan)
          linked=linked+1
        end
      elseif effective_mode~=0 and s.mode==0 and Core.getstr(s.src,s.idx,Core.LINK_KEY)=='1' then
        -- Re-enable the service if a previously linked Post-Pan send is now Pre-Fader.
        reactivated=reactivated+1
      end
    end
  end,debug.traceback)
  R.PreventUIRefresh(-1)
  R.Undo_EndBlock2(state.proj,'PT Copy to Send',-1)
  if not ok then state.status='Error: '..tostring(err);return false end
  if linked>0 or reactivated>0 then
    local started,reason=launch_engine()
    if not started then state.status='FMP saved but engine not started: '..tostring(reason);return false end
  end
  R.UpdateArrange()
  state.status=string.format('%d copied; %d modes; %d FMP; %d skipped.',updated,modes_changed,linked,skipped)
  return true
end
-- The dialog owns only its UI. Copy/FMP processing remains unchanged.
local function label(text)
  R.ImGui_SetCursorPosX(ctx,LEFT)
  R.ImGui_Text(ctx,text)
  R.ImGui_SameLine(ctx,0,0)
  R.ImGui_SetCursorPosX(ctx,EDIT)
end
local function check(title,key,section)
  label(section or '')
  local changed,value=R.ImGui_Checkbox(ctx,title..'##'..key,state[key])
  if changed then state[key]=value;store() end
end
local function destination_combo()
  label('To:')
  R.ImGui_SetNextItemWidth(ctx,W-EDIT-RIGHT)
  local opening=R.ImGui_BeginCombo(ctx,'##to',preview())
  state.dropdown=opening
  if opening then
    if R.ImGui_Button(ctx,'All Sends') then
      for _,d in ipairs(state.destinations) do state.selected[d.guid]=true end
      store()
    end
    R.ImGui_SameLine(ctx)
    if R.ImGui_Button(ctx,'Clear') then state.selected={};store() end
    R.ImGui_Separator(ctx)
    for _,d in ipairs(state.destinations) do
      local changed,on=R.ImGui_Checkbox(ctx,
        string.format('%02d  %s##%s',d.number,d.name,d.guid),
        state.selected[d.guid] or false)
      if changed then state.selected[d.guid]=on or nil;store() end
    end
    R.ImGui_EndCombo(ctx)
  end
  R.ImGui_SetCursorPosX(ctx,EDIT)
  R.ImGui_TextDisabled(ctx,'...of all selected tracks')
end
local function send_mode_combo()
  label('Mode:')
  R.ImGui_SetNextItemWidth(ctx,W-EDIT-RIGHT)
  local opening=R.ImGui_BeginCombo(ctx,'##send_mode',mode_label(state.send_mode))
  state.mode_dropdown=opening
  if opening then
    for _,mode in ipairs(SEND_MODES) do
      local is_selected=(state.send_mode==mode.value)
      if R.ImGui_Selectable(ctx,mode.label..'##mode'..tostring(mode.value),is_selected) then
        state.send_mode=mode.value
        store()
      end
      if is_selected and R.ImGui_SetItemDefaultFocus then
        R.ImGui_SetItemDefaultFocus(ctx)
      end
    end
    R.ImGui_EndCombo(ctx)
  end
end
local function draw()
  refresh()
  if state.first then
    local px=tonumber(Core.session_read('window_x'))
    local py=tonumber(Core.session_read('window_y'))
    if px and py then
      R.ImGui_SetNextWindowPos(ctx,px,py,R.ImGui_Cond_Always())
    else
      local viewport=R.ImGui_GetMainViewport(ctx)
      local x,y
      if R.ImGui_Viewport_GetWorkCenter then x,y=R.ImGui_Viewport_GetWorkCenter(viewport)
      else x,y=R.ImGui_Viewport_GetCenter(viewport) end
      R.ImGui_SetNextWindowPos(ctx,x,y,R.ImGui_Cond_Always(),0.5,0.5)
    end
    state.first=false
  end
  R.ImGui_SetNextWindowSize(ctx,W,H,R.ImGui_Cond_Always())
  if state.focus and R.ImGui_SetNextWindowFocus then
    R.ImGui_SetNextWindowFocus(ctx)
    state.focus=false
  end

  -- Match the compact, opaque appearance of a native PT-style dialog.
  local styles=0
  if R.ImGui_PushStyleVar and R.ImGui_StyleVar_WindowPadding and
     R.ImGui_StyleVar_FramePadding and R.ImGui_StyleVar_ItemSpacing then
    R.ImGui_PushStyleVar(ctx,R.ImGui_StyleVar_WindowPadding(),7,7)
    R.ImGui_PushStyleVar(ctx,R.ImGui_StyleVar_FramePadding(),4,2)
    R.ImGui_PushStyleVar(ctx,R.ImGui_StyleVar_ItemSpacing(),6,3)
    styles=3
  end
  local colors=0
  if R.ImGui_PushStyleColor and R.ImGui_Col_WindowBg then
    R.ImGui_PushStyleColor(ctx,R.ImGui_Col_WindowBg(),0x242424FF)
    colors=1
  end

  local flags=R.ImGui_WindowFlags_NoTitleBar()|R.ImGui_WindowFlags_NoResize()|
    R.ImGui_WindowFlags_NoCollapse()|R.ImGui_WindowFlags_NoSavedSettings()
  if R.ImGui_WindowFlags_NoScrollbar then
    flags=flags|R.ImGui_WindowFlags_NoScrollbar()
  end
  local visible,open=R.ImGui_Begin(ctx,'Copy to Send##PTCTS',true,flags)
  if visible then
    if R.ImGui_GetWindowPos then
      state.window_x,state.window_y=R.ImGui_GetWindowPos(ctx)
    end
    local combo_was_open=state.dropdown or state.mode_dropdown
    local tw=R.ImGui_CalcTextSize(ctx,'Copy To Send')
    R.ImGui_SetCursorPosX(ctx,(W-tw)/2)
    R.ImGui_Text(ctx,'Copy To Send')
    R.ImGui_Separator(ctx)

    -- Copy section: two rows, same column as From and To.
    check('Current Value','copy_current','Copy:')
    label('')
    R.ImGui_BeginDisabled(ctx,true)
    R.ImGui_Checkbox(ctx,'Automation',false)
    R.ImGui_EndDisabled(ctx)
    R.ImGui_Separator(ctx)

    -- FMP occupies the fourth row in the From group, replacing PT LFE.
    check('Volume','volume','From:')
    check('Pan','pan')
    check('Mute','mute')
    check('Follow Main Pan (FMP)','fmp')
    R.ImGui_Separator(ctx)

    destination_combo()
    send_mode_combo()

    -- One compact status line instead of the previous multiline notes.
    R.ImGui_SetCursorPosX(ctx,EDIT)
    if state.status~='' then
      R.ImGui_TextWrapped(ctx,state.status)
    else
      R.ImGui_TextDisabled(ctx,string.format('%d destinations  |  %d sends',
        count_selected_dest(),#affected()))
    end

    -- Fixed footer anchored to the bottom, like PT Spot Dialog.
    local footer_separator_y=H-48
    if R.ImGui_GetCursorPosY(ctx)<footer_separator_y then
      R.ImGui_SetCursorPosY(ctx,footer_separator_y)
    end
    R.ImGui_Separator(ctx)
    R.ImGui_SetCursorPosY(ctx,H-36)
    local bw,gap=UI.BUTTON_WIDTH,UI.BUTTON_GAP
    R.ImGui_SetCursorPosX(ctx,(W-2*bw-gap)/2)
    if R.ImGui_Button(ctx,'Cancel',bw,UI.BUTTON_HEIGHT) then state.open=false end
    R.ImGui_SameLine(ctx,0,gap)
    if R.ImGui_Button(ctx,'OK',bw,UI.BUTTON_HEIGHT) and apply() then state.open=false end

    -- As in PT Spot, the first Escape only closes an open combo.
    local escape=R.ImGui_IsKeyPressed(ctx,R.ImGui_Key_Escape(),false)
    if escape then
      local popup=false
      if R.ImGui_IsPopupOpen and R.ImGui_PopupFlags_AnyPopup then
        popup=R.ImGui_IsPopupOpen(ctx,'',R.ImGui_PopupFlags_AnyPopup())
      end
      if not combo_was_open and not state.dropdown and not state.mode_dropdown and not popup then
        state.open=false
      end
    end
    local popup_active=false
    if R.ImGui_IsPopupOpen and R.ImGui_PopupFlags_AnyPopup then
      popup_active=R.ImGui_IsPopupOpen(ctx,'',R.ImGui_PopupFlags_AnyPopup())
    end
    if state.open and R.ImGui_IsKeyPressed(ctx,R.ImGui_Key_Enter(),false)
      and not combo_was_open and not state.dropdown and not state.mode_dropdown and not popup_active then
      if apply() then state.open=false end
    end
  end
  R.ImGui_End(ctx)
  if colors>0 then R.ImGui_PopStyleColor(ctx,colors) end
  if styles>0 then R.ImGui_PopStyleVar(ctx,styles) end
  if not open then state.open=false end
end
local function cleanup()
  store()
  if state.window_x and state.window_y then
    Core.session_write('window_x',state.window_x)
    Core.session_write('window_y',state.window_y)
  end
  if Core.session_read('dialog_owner')==token then
    Core.session_write('dialog_owner','')
    Core.session_write('dialog_heartbeat','0')
  end
end
R.atexit(cleanup)
local function loop()
  if not state.open or Core.session_read('dialog_owner')~=token then return end
  if Core.session_read('dialog_show')=='1' then
    state.focus=true;Core.session_write('dialog_show',0)
  end
  local ok,err=xpcall(draw,debug.traceback)
  if not ok then R.MB(tostring(err),'PT Copy to Send',0);return end
  Core.session_write('dialog_heartbeat',R.time_precise())
  if state.open then R.defer(loop) end
end
loop()
