-- Daniel_Show big marker name.lua
-- Version: 1.5
-- Author: Daniel Kharrat
-- Shows the current marker / region name in a big window.
-- Changelog:
--   1.5  Right-click menu with Close.
--        Window comes back after a REAPER restart if it was open
--        (toolbar toggle script + global startup action).

local reaper = reaper

------------------------------------------------------------
-- TOOLBAR SYNC
--
-- The toolbar button runs the separate "(toolbar toggle)"
-- script. This script keeps that button (and its own toggle
-- state) matching whether the window is really open, and
-- keeps the Show_Big_Marker_Name flag in reaper.ini for the
-- startup action.
------------------------------------------------------------

local _, _, sec_id, cmd_id = reaper.get_action_context()

local closed_by_user = false   -- set by "Close" in the right-click menu

do
local TOGGLE_KEY = 'Show_Big_Marker_Name'   -- the key in reaper.ini that the startup action reads
local EXT = 'Daniel_ShowBigMarkerName'
-- the toolbar button's script: Daniel_Show big marker name (toolbar toggle).lua
local TOGGLE_BUTTON = '_RS6c0d512c6aebb1207367e64782697d63455f6ef1'
local function toggle_button_id()
  local id = reaper.NamedCommandLookup(TOGGLE_BUTTON)
  if id and id ~= 0 then return id end
end
local function set_visual_state(on)
  local v = on and 1 or 0
  reaper.SetToggleCommandState(sec_id, cmd_id, v); reaper.RefreshToolbar2(sec_id, cmd_id)
  local tid = toggle_button_id()
  if tid then reaper.SetToggleCommandState(0, tid, v); reaper.RefreshToolbar2(0, tid) end
end
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
local function write_ini_flag(on) SetIniValue(TOGGLE_KEY, on and 1 or 0) end
-- Running the action while the window is open turns it off. REAPER stops the running script and, with
-- set_action_options(1 + 2), starts it again right away; the stopped one left the time it stopped, so
-- this new start knows it's a "turn off": it writes 0 and doesn't open. (REAPER quitting stops the
-- script without starting it again, so the flag stays 1 and the window comes back at the next startup.)
local stopped_at = tonumber(reaper.GetExtState(EXT, 'stopped_at'))
reaper.DeleteExtState(EXT, 'stopped_at', false)
if stopped_at and reaper.time_precise() - stopped_at < 1 then
  set_visual_state(false)
  write_ini_flag(false)
  return
end
set_visual_state(true)
write_ini_flag(true)
reaper.atexit(function()
  set_visual_state(false)
  if closed_by_user then
    write_ini_flag(false)                        -- closed from the menu: stays closed
  else                                           -- stopped by running it again (or REAPER quitting)
    reaper.SetExtState(EXT, 'stopped_at', tostring(reaper.time_precise()), false)
  end
end)
end
-- launching the script again while it runs closes it (a toggle), without REAPER's dialog:
-- 1 = stop the running one, 2 = then start this one (which sees it was a "turn off", above)
if reaper.set_action_options then reaper.set_action_options(1 | 2) end

------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------
local imgui = reaper.ImGui_CreateContext("Current Marker")

local font = reaper.ImGui_CreateFont("Arial", reaper.ImGui_FontFlags_Bold())
reaper.ImGui_Attach(imgui, font)

local INITIAL_WIDTH  = 500
local INITIAL_HEIGHT = 150

local MAIN_HWND = reaper.GetMainHwnd()
local HAS_JS    = reaper.APIExists("JS_Window_SetFocus")

if not HAS_JS then
    reaper.ShowConsoleMsg(
        "Current Marker: js_ReaScriptAPI not found.\n" ..
        "Install it via ReaPack so focus can return to REAPER after clicking.\n"
    )
end

local function returnFocusToReaper()
    if not HAS_JS then return end

    -- Prefer the arrange view so shortcuts behave as if you clicked the timeline
    local arrange = reaper.JS_Window_FindChildByID(MAIN_HWND, 1000)
    reaper.JS_Window_SetFocus(arrange or MAIN_HWND)
end

------------------------------------------------------------
-- GET CURRENT MARKER / REGION NAME
------------------------------------------------------------

local function getCurrentMarkerName()

    --------------------------------------------------------
    -- POSITION TO FOLLOW
    --
    -- While playing or recording, follow the playhead,
    -- so the name changes as soon as it passes a marker.
    -- When stopped, follow the edit cursor as before.
    --
    -- Play state bits: 1 = playing, 2 = paused, 4 = recording
    --------------------------------------------------------

    local playState = reaper.GetPlayState()
    local position
    local followingPlayhead =
        playState & 1 == 1 or playState & 4 == 4

    if followingPlayhead then
        position = reaper.GetPlayPosition()
    else
        position = reaper.GetCursorPosition()
    end

    local markers = {}
    local regions = {}

    --------------------------------------------------------
    -- COLLECT MARKERS AND REGIONS
    --
    -- Unnamed markers and regions (e.g. red editing
    -- markers) are INVISIBLE: they are never collected,
    -- so the display keeps showing whatever came before
    -- them. Names that are only spaces count as unnamed.
    --------------------------------------------------------

    for i = 0, reaper.CountProjectMarkers(0) - 1 do

        local retval, isrgn, markerPos, regionEnd,
              markerNameAtPos, markerIndex =
            reaper.EnumProjectMarkers3(0, i)

        local hasName =
            markerNameAtPos and markerNameAtPos:match("%S")

        if hasName then

            if isrgn then

                regions[#regions + 1] = {
                    startPos = markerPos,
                    endPos   = regionEnd,
                    name     = markerNameAtPos
                }

            else

                markers[#markers + 1] = {
                    pos  = markerPos,
                    name = markerNameAtPos
                }

            end

        end
    end

    --------------------------------------------------------
    -- 1. EXACT MARKER
    --
    -- Marker always wins when we are exactly on it,
    -- including when it is inside a region.
    --------------------------------------------------------

    for i = 1, #markers do

        if math.abs(position - markers[i].pos) < 0.0001 then
            return markers[i].name
        end

    end

    --------------------------------------------------------
    -- 2. CURRENT REGION
    --
    -- If inside overlapping regions, use the smallest one.
    --------------------------------------------------------

    local currentRegion = nil
    local smallestLength = math.huge

    for i = 1, #regions do

        local region = regions[i]

        if position >= region.startPos
           and position <= region.endPos then

            local length = region.endPos - region.startPos

            if length < smallestLength then
                smallestLength = length
                currentRegion = region
            end

        end
    end

    --------------------------------------------------------
    -- If inside a region, region wins.
    --
    -- Exception while playing/recording: once the playhead
    -- has passed a marker inside this region, that marker
    -- takes over (the playhead is never EXACTLY on a
    -- marker, so rule 1 can't catch it).
    --------------------------------------------------------

    if currentRegion then

        if followingPlayhead then

            local passedMarker = nil

            for i = 1, #markers do

                local marker = markers[i]

                if marker.pos >= currentRegion.startPos
                   and marker.pos <= position then

                    if not passedMarker
                       or marker.pos > passedMarker.pos then

                        passedMarker = marker

                    end
                end
            end

            if passedMarker then
                return passedMarker.name
            end

        end

        return currentRegion.name
    end

    --------------------------------------------------------
    -- 3. FIND THE MOST RECENT REGION THAT ENDED
    --    BEFORE THE CURSOR
    --------------------------------------------------------

    local lastRegion = nil

    for i = 1, #regions do

        local region = regions[i]

        if region.endPos < position then

            if not lastRegion
               or region.endPos > lastRegion.endPos then

                lastRegion = region

            end
        end
    end

    --------------------------------------------------------
    -- 4. FIND THE MOST RECENT MARKER BEFORE THE CURSOR
    --------------------------------------------------------

    local lastMarker = nil

    for i = 1, #markers do

        local marker = markers[i]

        if marker.pos < position then

            if not lastMarker
               or marker.pos > lastMarker.pos then

                lastMarker = marker

            end
        end
    end

    --------------------------------------------------------
    -- 5. IF THERE IS A MARKER AFTER THE LAST REGION,
    --    THAT MARKER IS THE CURRENT STATE.
    --
    -- Example:
    --
    -- Region A [ Marker B ] ---- Marker C ---->
    --
    -- After Marker C:
    --     Marker C
    --
    -- NOT Marker B.
    --------------------------------------------------------

    if lastMarker then

        if not lastRegion
           or lastMarker.pos > lastRegion.endPos then

            return lastMarker.name
        end
    end

    --------------------------------------------------------
    -- 6. WE ARE AFTER A REGION, AND THERE HAS NOT BEEN
    --    A NEW MARKER SINCE THAT REGION ENDED.
    --
    -- Look for the LAST marker that was INSIDE that region.
    --------------------------------------------------------

    if lastRegion then

        local lastMarkerInsideRegion = nil

        for i = 1, #markers do

            local marker = markers[i]

            if marker.pos >= lastRegion.startPos
               and marker.pos <= lastRegion.endPos then

                if not lastMarkerInsideRegion
                   or marker.pos > lastMarkerInsideRegion.pos then

                    lastMarkerInsideRegion = marker

                end
            end
        end

        ----------------------------------------------------
        -- If the region contained a marker, keep displaying
        -- that marker after leaving the region.
        ----------------------------------------------------

        if lastMarkerInsideRegion then
            return lastMarkerInsideRegion.name
        end

        ----------------------------------------------------
        -- Otherwise keep displaying the region name.
        ----------------------------------------------------

        return lastRegion.name
    end

    --------------------------------------------------------
    -- 7. NO REGION HAS BEEN PASSED.
    --
    -- A standalone marker persists until another marker
    -- or a region is encountered.
    --------------------------------------------------------

    if lastMarker then
        return lastMarker.name
    end

    --------------------------------------------------------
    -- NOTHING YET
    --------------------------------------------------------

    return ""
end
------------------------------------------------------------
-- MAIN LOOP
------------------------------------------------------------

local function loop()

    --------------------------------------------------------
    -- INITIAL WINDOW SIZE
    --------------------------------------------------------
    
    local viewport = reaper.ImGui_GetMainViewport(imgui)
    local cx, cy = reaper.ImGui_Viewport_GetCenter(viewport)
    
    reaper.ImGui_SetNextWindowPos(
        imgui,
        cx, cy,
        reaper.ImGui_Cond_FirstUseEver(),
        0.5, 0.5   -- pivot: center the window on that point
    )
    
    reaper.ImGui_SetNextWindowSize(
        imgui,
        INITIAL_WIDTH,
        INITIAL_HEIGHT,
        reaper.ImGui_Cond_FirstUseEver()
    )

    --------------------------------------------------------
    -- REMOVE WINDOW PADDING
    --------------------------------------------------------

    reaper.ImGui_PushStyleVar(
        imgui,
        reaper.ImGui_StyleVar_WindowPadding(),
        0,
        0
    )

    --------------------------------------------------------
    -- WINDOW
    --------------------------------------------------------

    reaper.ImGui_PushStyleColor(
        imgui,
        reaper.ImGui_Col_WindowBg(),
        0x000000FF
    )

    local visible, open =
        reaper.ImGui_Begin(
            imgui,
            "Current Marker",
            true,
            reaper.ImGui_WindowFlags_NoTitleBar() |
            reaper.ImGui_WindowFlags_NoFocusOnAppearing()
        )

    --------------------------------------------------------
    -- CONTENT
    --------------------------------------------------------

    if visible then

        ----------------------------------------------------
        -- GET CURRENT MARKER / REGION
        ----------------------------------------------------

        local TEXT = getCurrentMarkerName()

        if TEXT == "" then
            TEXT = "no marker"
        end

        ----------------------------------------------------
        -- CONTENT AREA
        ----------------------------------------------------

        local areaX, areaY =
            reaper.ImGui_GetCursorScreenPos(imgui)

        local areaWidth, areaHeight =
            reaper.ImGui_GetContentRegionAvail(imgui)

        ----------------------------------------------------
        -- CALCULATE TEXT SIZE
        ----------------------------------------------------

        local baseFontSize =
            reaper.ImGui_GetFontSize(imgui)

        reaper.ImGui_PushFont(
            imgui,
            font,
            baseFontSize
        )

        local baseTextWidth, baseTextHeight =
            reaper.ImGui_CalcTextSize(
                imgui,
                TEXT
            )

        reaper.ImGui_PopFont(imgui)

        ----------------------------------------------------
        -- CALCULATE MAXIMUM FONT SIZE
        ----------------------------------------------------

        local fontSize = baseFontSize

        if baseTextWidth > 0 and baseTextHeight > 0 then

            local sizeFromWidth =
                baseFontSize *
                (areaWidth / baseTextWidth)

            local sizeFromHeight =
                baseFontSize *
                (areaHeight / baseTextHeight)

            fontSize =
                math.min(
                    sizeFromWidth,
                    sizeFromHeight
                )

        end

        ----------------------------------------------------
        -- MEASURE FINAL TEXT
        ----------------------------------------------------

        reaper.ImGui_PushFont(
            imgui,
            font,
            fontSize
        )

        local textWidth, textHeight =
            reaper.ImGui_CalcTextSize(
                imgui,
                TEXT
            )

        reaper.ImGui_PopFont(imgui)

        ----------------------------------------------------
        -- CENTER TEXT
        ----------------------------------------------------

        local x =
            areaX +
            (areaWidth - textWidth) / 2

        local y =
            areaY +
            (areaHeight - textHeight) / 2 -
            (fontSize * 0.04)

        ----------------------------------------------------
        -- DRAW TEXT
        ----------------------------------------------------

        local drawList =
            reaper.ImGui_GetWindowDrawList(imgui)

        reaper.ImGui_DrawList_AddTextEx(
            drawList,
            font,
            fontSize,
            x,
            y,
            0x6ECD80FF,
            TEXT
        )

        ----------------------------------------------------
        -- RIGHT-CLICK MENU: CLOSE
        --
        -- The window has no title bar (no X), so close it
        -- from here. Same as the X on the other windows:
        -- it stays closed at the next REAPER start.
        ----------------------------------------------------

        reaper.ImGui_PushStyleVar(imgui, reaper.ImGui_StyleVar_WindowPadding(), 6, 6)
        reaper.ImGui_PushStyleVar(imgui, reaper.ImGui_StyleVar_PopupRounding(), 6)
        reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_PopupBg(),       0x222228FF)
        reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_Border(),        0x2E2E36FF)
        reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_Text(),          0xEDEDF2FF)
        reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_HeaderHovered(), 0x5B9BF055)

        if reaper.ImGui_BeginPopupContextWindow(imgui) then
            if reaper.ImGui_MenuItem(imgui, "Close") then
                closed_by_user = true
                open = false
            end
            reaper.ImGui_EndPopup(imgui)
        end

        reaper.ImGui_PopStyleColor(imgui, 4)
        reaper.ImGui_PopStyleVar(imgui, 2)

        ----------------------------------------------------
        -- RETURN FOCUS TO REAPER AFTER A CLICK
        -- (not while the right-click menu is open)
        ----------------------------------------------------

        local menuOpen = reaper.ImGui_IsPopupOpen(
            imgui, "",
            reaper.ImGui_PopupFlags_AnyPopupId()
        )

        if not menuOpen and reaper.ImGui_IsWindowFocused(
               imgui,
               reaper.ImGui_FocusedFlags_RootAndChildWindows()
           ) then

            if reaper.ImGui_IsMouseReleased(imgui, 0)    -- left
            or reaper.ImGui_IsMouseReleased(imgui, 1)    -- right
            or reaper.ImGui_IsMouseReleased(imgui, 2) then -- middle
                returnFocusToReaper()
            end

        end
        
        ----------------------------------------------------
        -- END WINDOW
        ----------------------------------------------------

        reaper.ImGui_End(imgui)

    end

    reaper.ImGui_PopStyleColor(imgui)

    --------------------------------------------------------
    -- RESTORE STYLE
    --------------------------------------------------------

    reaper.ImGui_PopStyleVar(imgui)

    --------------------------------------------------------
    -- CONTINUE
    --------------------------------------------------------

    if open then
        reaper.defer(loop)
    end
end

------------------------------------------------------------
-- START
------------------------------------------------------------

loop()
