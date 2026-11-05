-- @description PT FMP Engine v1.1 (managed by PT Copy to Send)
-- @author antoniondc
-- @version 1.0
-- @about One low-overhead deferred service for existing FMP send links.
local R=reaper
local _,file=R.get_action_context()
local folder=file:match('^(.*[/\\])')
local Core=dofile(folder..'PT_Send_Core.lua')
local NS=Core.NS
local now=R.time_precise()
local stamp=tonumber(Core.session_read('engine_heartbeat')) or 0
if now-stamp<1.5 and now>=stamp then return end
local token=R.genGuid()
Core.session_write('engine_owner',token)
Core.session_write('engine_heartbeat',now)
------------------------------------------------------------
-- PERFORMANCE SETTINGS - EDIT HERE
------------------------------------------------------------
-- FMP_UPDATE_HZ: maximum synchronization passes per second.
-- Lower = less CPU work, but slower control response.
-- Suggested: 10 (light), 20 (default), 30 (responsive).
-- This does NOT change thread/OS scheduling priority.
local FMP_UPDATE_HZ = 20

-- How often the engine looks for newly added/removed FMP links.
local FMP_RESCAN_SECONDS = 1.0

-- Avoid tiny redundant parameter writes.
local FMP_PAN_EPSILON = 0.000001

local RATE = 1 / math.max(1, FMP_UPDATE_HZ)
local RESCAN = math.max(0.2, FMP_RESCAN_SECONDS)
local EPS = FMP_PAN_EPSILON
local last_scan=-1
local last_sync=-1
local cached={}
local links=0
local function scan()
  local arr={}
  for _,proj in ipairs(Core.projects()) do
    for i=0,R.CountTracks(proj)-1 do
      local src=R.GetTrack(proj,i)
      for si=0,R.GetTrackNumSends(src,0)-1 do
        if Core.getstr(src,si,Core.LINK_KEY)=='1' then
          local mode=R.GetTrackSendInfo_Value(src,0,si,'I_SENDMODE')
          local dst=Core.get_destination(src,si)
          -- Post-pan receives main pan already; avoid double-panning.
          if Core.valid(dst,proj) and mode~=0 then
            arr[#arr+1]={project=proj,source=src,idx=si,uid=Core.uid(src,si,false)}
          end
        end
      end
    end
  end
  cached=arr; links=#arr
  Core.session_write('engine_links',links)
end
local function sync()
  local dirty=false
  for _,v in ipairs(cached) do
    if Core.valid(v.source,v.project) and Core.getstr(v.source,v.idx,Core.UID_KEY)==v.uid then
      local mode=R.GetTrackSendInfo_Value(v.source,0,v.idx,'I_SENDMODE')
      if mode~=0 and Core.getstr(v.source,v.idx,Core.LINK_KEY)=='1' then
        -- Read current evaluated track pan where available, fall back to base pan.
        local pan=R.GetMediaTrackInfo_Value(v.source,'D_PAN')
        local existing=R.GetTrackSendInfo_Value(v.source,0,v.idx,'D_PAN')
        -- Never compete with touch/write/latch send automation.
        local sm=R.GetTrackSendInfo_Value(v.source,0,v.idx,'I_AUTOMODE')
        if sm~=2 and sm~=3 and sm~=4 and sm~=5 and math.abs(existing-pan)>EPS then
          R.SetTrackSendInfo_Value(v.source,0,v.idx,'D_PAN',pan)
          dirty=true
        end
      end
    end
  end
  if dirty then R.UpdateArrange() end
end
local function cleanup()
  if Core.session_read('engine_owner')==token then
    Core.session_write('engine_owner','')
    Core.session_write('engine_heartbeat','0')
    Core.session_write('engine_links','0')
  end
end
R.atexit(cleanup)
local function loop()
  if Core.session_read('engine_owner')~=token then return end
  local t=R.time_precise()
  if t-last_scan>=RESCAN then
    scan(); last_scan=t
    if links==0 then return end
  end
  if t-last_sync>=RATE then sync(); last_sync=t end
  Core.session_write('engine_heartbeat',t)
  R.defer(loop)
end
loop()
