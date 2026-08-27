reaper.set_action_options(1)

------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------

local reaper = reaper
local imgui = reaper.ImGui_CreateContext("Current Marker")

local font = reaper.ImGui_CreateFont("Arial", reaper.ImGui_FontFlags_Bold())
reaper.ImGui_Attach(imgui, font)

local INITIAL_WIDTH  = 500
local INITIAL_HEIGHT = 100

------------------------------------------------------------
-- GET CURRENT MARKER / REGION NAME
------------------------------------------------------------

local function getCurrentMarkerName()

    local position = reaper.GetCursorPosition()

    local markers = {}
    local regions = {}

    --------------------------------------------------------
    -- COLLECT MARKERS AND REGIONS
    --------------------------------------------------------

    for i = 0, reaper.CountProjectMarkers(0) - 1 do

        local retval, isrgn, markerPos, regionEnd,
              markerNameAtPos, markerIndex =
            reaper.EnumProjectMarkers3(0, i)

        if isrgn then

            regions[#regions + 1] = {
                startPos = markerPos,
                endPos   = regionEnd,
                name     = markerNameAtPos or ""
            }

        else

            markers[#markers + 1] = {
                pos  = markerPos,
                name = markerNameAtPos or ""
            }

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
    --------------------------------------------------------

    if currentRegion then
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
