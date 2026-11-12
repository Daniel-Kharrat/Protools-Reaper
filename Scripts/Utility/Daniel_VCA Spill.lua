-- @description VCA Spill
-- @author Daniel Kharrat
-- @version 1.1
-- @changelog
--   v1.1: Saves your normal mixer view and can restore it (3 views, one button).
--   v1.0: First release.
-- @about
--   One-button VCA spill for the REAPER mixer (like the spill key on a console).
--   Based on the VCA scripts by Airon and NoFish.
--
--   Button off = your normal mixer.
--   - Push: the mixer shows all VCA leaders. The button lights.
--     (If a VCA leader is selected, it spills that leader directly.)
--   - Select a VCA leader and push: the mixer shows that leader and its
--     direct followers only.
--   - Push again: back to all VCA leaders.
--   - In the leaders view, with no VCA leader selected, push: your normal
--     mixer comes back. The button goes off.
--   - Nested VCAs: if a follower is also a leader, select it and push to
--     spill it.
--
--   Only the mixer (MCP) changes. The arrange view (TCP) is not changed.
--   No SWS needed.

local EXT     = "Daniel_VCA Spill"
local K_MODE  = "mode"      -- "" = normal, "leaders", "spill"
local K_LEAD  = "leader"    -- GUID of the spilled leader
local K_SNAP  = "snapshot"  -- saved normal view: GUID=0/1;...

local _, _, section_id, cmd_id = reaper.get_action_context()

local function set_button(on)
  reaper.SetToggleCommandState(section_id, cmd_id, on and 1 or 0)
  reaper.RefreshToolbar2(section_id, cmd_id)
end

local function get(key)
  local _, v = reaper.GetProjExtState(0, EXT, key)
  return v
end

local function set(key, v)
  reaper.SetProjExtState(0, EXT, key, v)
end

-- Leader bits for groups 1-32 and 33-64
local function leader_bits(track)
  local lo = reaper.GetSetTrackGroupMembership(track, "VOLUME_VCA_LEAD", 0, 0)
  local hi = reaper.GetSetTrackGroupMembershipHigh(track, "VOLUME_VCA_LEAD", 0, 0)
  return lo, hi
end

local function is_leader(track)
  local lo, hi = leader_bits(track)
  return lo ~= 0 or hi ~= 0
end

local function any_leader()
  for i = 0, reaper.CountTracks(0) - 1 do
    if is_leader(reaper.GetTrack(0, i)) then return true end
  end
  return false
end

-- Show in the mixer only the tracks for which keep(track) is true
local function show_in_mixer(keep)
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", keep(tr) and 1 or 0)
  end
end

-- Normal view: save and restore -------------------------------------------

local function save_snapshot()
  local parts = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local vis = reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINMIXER")
    parts[#parts + 1] = reaper.GetTrackGUID(tr) .. "=" .. (vis ~= 0 and "1" or "0")
  end
  set(K_SNAP, table.concat(parts, ";"))
end

local function restore_snapshot()
  local saved = {}
  for guid, vis in get(K_SNAP):gmatch("([^;=]+)=([01])") do
    saved[guid] = vis == "1"
  end
  -- Tracks added after the snapshot are shown
  show_in_mixer(function(tr)
    local v = saved[reaper.GetTrackGUID(tr)]
    if v == nil then return true end
    return v
  end)
end

-- Views --------------------------------------------------------------------

local function view_leaders()
  show_in_mixer(is_leader)
  set(K_MODE, "leaders")
  set(K_LEAD, "")
  set_button(true)
  return "VCA Spill: show all VCA leaders"
end

local function view_spill(leader)
  local l_lo, l_hi = leader_bits(leader)
  show_in_mixer(function(tr)
    if tr == leader then return true end
    local f_lo = reaper.GetSetTrackGroupMembership(tr, "VOLUME_VCA_FOLLOW", 0, 0)
    local f_hi = reaper.GetSetTrackGroupMembershipHigh(tr, "VOLUME_VCA_FOLLOW", 0, 0)
    return (f_lo & l_lo) ~= 0 or (f_hi & l_hi) ~= 0
  end)
  set(K_MODE, "spill")
  set(K_LEAD, reaper.GetTrackGUID(leader))
  set_button(true)
  return "VCA Spill: show leader and followers"
end

local function view_normal()
  restore_snapshot()
  set(K_MODE, "")
  set(K_LEAD, "")
  set_button(false)
  return "VCA Spill: restore normal mixer"
end

-- Main ---------------------------------------------------------------------

local mode = get(K_MODE)
local sel  = reaper.GetSelectedTrack(0, 0)
local sel_leader = (sel and is_leader(sel)) and sel or nil

if mode == "" and not any_leader() then
  set_button(false)
  reaper.MB("This project has no VCA leaders.", "VCA Spill", 0)
  return
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local undo_name
if mode == "spill" then
  if sel_leader and reaper.GetTrackGUID(sel_leader) ~= get(K_LEAD) then
    undo_name = view_spill(sel_leader)       -- spill another leader
  else
    undo_name = view_leaders()               -- back to leaders
  end
elseif mode == "leaders" then
  if sel_leader then
    undo_name = view_spill(sel_leader)
  else
    undo_name = view_normal()                -- no leader selected: normal mixer
  end
else
  save_snapshot()                            -- leaving the normal mixer
  if sel_leader then
    undo_name = view_spill(sel_leader)
  else
    undo_name = view_leaders()
  end
end

reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
reaper.CSurf_SetTrackListChange()
reaper.TrackList_UpdateAllExternalSurfaces()
reaper.Undo_EndBlock(undo_name, -1)
