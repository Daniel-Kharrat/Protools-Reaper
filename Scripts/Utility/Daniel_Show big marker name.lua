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

    local markerName = ""

    --------------------------------------------------------
    -- CHECK MARKERS FIRST
    --------------------------------------------------------

    for i = 0, reaper.CountProjectMarkers(0) - 1 do

        local retval, isrgn, markerPos, regionEnd,
              markerNameAtPos, markerIndex =
            reaper.EnumProjectMarkers3(0, i)

        if not isrgn then

            if math.abs(position - markerPos) < 0.0001 then
                markerName = markerNameAtPos or ""
                break
            end

        end
    end

    --------------------------------------------------------
    -- IF NOT ON A MARKER, CHECK REGIONS
    -- If regions overlap, use the smallest/innermost one
    --------------------------------------------------------

    if markerName == "" then

        local smallestRegionLength = math.huge

        for i = 0, reaper.CountProjectMarkers(0) - 1 do

            local retval, isrgn, markerPos, regionEnd,
                  markerNameAtPos, markerIndex =
                reaper.EnumProjectMarkers3(0, i)

            if isrgn then

                if position >= markerPos and position <= regionEnd then

                    local regionLength = regionEnd - markerPos

                    if regionLength < smallestRegionLength then
                        smallestRegionLength = regionLength
                        markerName = markerNameAtPos or ""
                    end

                end
            end
        end
    end

    return markerName
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
            (areaHeight - textHeight) / 2 - (fontSize * 0.04)

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
        --
        -- IMPORTANT:
        -- End() belongs inside the visible block.
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
