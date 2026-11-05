-- @description PT Send Core v1.1 - shared REAPER send and session utilities
-- @author antoniondc
-- @version 1.0
local R = reaper
local M = {}
M.NS = 'PT_COPY_TO_SEND_V1'
M.UID_KEY = 'P_EXT:PT_CTS_SEND_UID_V1'
M.LINK_KEY = 'P_EXT:PT_CTS_FMP_V1'
local function valid(tr, proj) return tr and R.ValidatePtr2(proj or 0, tr, 'MediaTrack*') end
M.valid = valid
function M.guid(tr) return R.GetTrackGUID(tr) end
function M.name(tr)
  local _,name=R.GetTrackName(tr)
  if name == '' then name='Track '..tostring(math.floor(R.GetMediaTrackInfo_Value(tr,'IP_TRACKNUMBER'))) end
  return name
end
function M.projects()
  local out,i={},0
  while true do
    local p=R.EnumProjects(i,'')
    if not p then break end
    out[#out+1]=p; i=i+1
  end
  return out
end
function M.getstr(tr,idx,key)
  local ok,val=R.GetSetTrackSendInfo_String(tr,0,idx,key,'',false)
  return ok and val or ''
end
function M.setstr(tr,idx,key,val) return R.GetSetTrackSendInfo_String(tr,0,idx,key,val,true) end
function M.get_destination(tr,idx) return R.GetTrackSendInfo_Value(tr,0,idx,'P_DESTTRACK') end
function M.uid(tr,idx,create)
  local uid=M.getstr(tr,idx,M.UID_KEY)
  if uid=='' and create then
    uid=R.genGuid()
    M.setstr(tr,idx,M.UID_KEY,uid)
  end
  return uid
end
function M.all_sends(project)
  local result, destinations, seen={}, {}, {}
  for i=0,R.CountTracks(project)-1 do
    local src=R.GetTrack(project,i)
    for si=0,R.GetTrackNumSends(src,0)-1 do
      local dest=M.get_destination(src,si)
      if valid(dest,project) then
        local g=M.guid(dest)
        result[#result+1]={src=src,dest=dest,idx=si,dguid=g,sguid=M.guid(src)}
        if not seen[g] then
          seen[g]=true
          destinations[#destinations+1]={track=dest,guid=g,name=M.name(dest),number=math.floor(R.GetMediaTrackInfo_Value(dest,'IP_TRACKNUMBER'))}
        end
      end
    end
  end
  table.sort(destinations,function(a,b)return a.number<b.number end)
  return result,destinations
end
function M.session_read(key) return R.GetExtState(M.NS,key) end
function M.session_write(key,value) R.SetExtState(M.NS,key,tostring(value),false) end
function M.project_id(project)
  -- Each open project tab has a distinct live identity for session UI memory.
  return tostring(project)
end
function M.destination_selection(project)
  local set={}
  local raw=M.session_read('TO_'..M.project_id(project))
  for g in raw:gmatch('[^\n]+') do set[g]=true end
  return set
end
function M.save_destination_selection(project,sel)
  local arr={}
  for k,v in pairs(sel) do if v then arr[#arr+1]=k end end
  table.sort(arr)
  M.session_write('TO_'..M.project_id(project),table.concat(arr,'\n'))
end
function M.has_fmp(project)
  for i=0,R.CountTracks(project)-1 do
    local tr=R.GetTrack(project,i)
    for j=0,R.GetTrackNumSends(tr,0)-1 do
      if M.getstr(tr,j,M.LINK_KEY)=='1' then return true end
    end
  end
  return false
end
return M
