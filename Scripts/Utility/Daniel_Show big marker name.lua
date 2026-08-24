------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------
reaper.set_action_options(1)

local WINDOW_TITLE = "Current Marker / Region"

local WINDOW_WIDTH  = 500
local WINDOW_HEIGHT = 80

-- Distance from a cue position that is considered
-- "at the cue".
--
-- 0.001 = 1 millisecond.
local POSITION_TOLERANCE = 0.001


------------------------------------------------------------
-- CURRENT DISPLAY
------------------------------------------------------------

local display_name = "No Marker / Region"

local last_type = nil
local last_id = nil
local last_position = nil


------------------------------------------------------------
-- GET ALL PROJECT MARKERS AND REGIONS
------------------------------------------------------------

local function get_all_cues()

    local cues = {}

    local _, num_markers, num_regions =
        reaper.CountProjectMarkers(0)

    for i = 0, num_markers + num_regions - 1 do

        local retval,
              is_region,
              position,
              region_end,
              name,
              id =
            reaper.EnumProjectMarkers3(0, i)

        if retval then

            if is_region then

                table.insert(cues, {
                    type = "region",
                    id = id,
                    start_pos = position,
                    end_pos = region_end,
                    name = name
                })

            else

                table.insert(cues, {
                    type = "marker",
                    id = id,
                    start_pos = position,
                    end_pos = nil,
                    name = name
                })

            end
        end
    end

    return cues
end


------------------------------------------------------------
-- FIND MARKER / REGION START AT CURSOR
------------------------------------------------------------

local function find_start_cue(cursor, cues)

    local best_cue = nil
    local best_distance = math.huge

    for _, cue in ipairs(cues) do

        local distance =
            math.abs(cue.start_pos - cursor)

        if distance <= POSITION_TOLERANCE
           and distance < best_distance then

            best_distance = distance
            best_cue = cue
        end
    end

    return best_cue
end


------------------------------------------------------------
-- FIND REGION END AT CURSOR
------------------------------------------------------------

local function find_region_end(cursor, cues)

    local ending_region = nil

    for _, cue in ipairs(cues) do

        if cue.type == "region" then

            local distance =
                math.abs(cue.end_pos - cursor)

            if distance <= POSITION_TOLERANCE then

                -- If multiple regions end at the same point,
                -- prefer the smallest/most deeply nested one.
                --
                -- A smaller region has a later start position.
                if not ending_region
                   or cue.start_pos > ending_region.start_pos then

                    ending_region = cue
                end
            end
        end
    end

    return ending_region
end


------------------------------------------------------------
-- FIND THE SMALLEST REGION CONTAINING CURSOR
--
-- This is used after a nested region ends.
--
-- Example:
--
-- A: 0 ------------------------- 20
-- B:     5 --------------- 15
-- C:         8 ------- 12
--
-- At C's end (12):
--     A and B contain the cursor.
--
-- We choose B because it is the smallest
-- enclosing region.
------------------------------------------------------------

local function find_innermost_region(cursor, cues)

    local best_region = nil

    for _, cue in ipairs(cues) do

        if cue.type == "region" then

            -- The cursor must be INSIDE the region,
            -- not at its end.
            if cursor > cue.start_pos + POSITION_TOLERANCE
               and cursor < cue.end_pos - POSITION_TOLERANCE then

                if not best_region then

                    best_region = cue

                else

                    -- Later start = smaller nested region
                    if cue.start_pos > best_region.start_pos then
                        best_region = cue
                    end

                end
            end
        end
    end

    return best_region
end


------------------------------------------------------------
-- SET DISPLAY FROM CUE
------------------------------------------------------------

local function set_display_from_cue(cue)

    if not cue then
        return
    end

    last_type = cue.type
    last_id = cue.id
    last_position = cue.start_pos

    if cue.name and cue.name ~= "" then

        display_name = cue.name

    else

        if cue.type == "marker" then
            display_name = "(Unnamed Marker)"
        else
            display_name = "(Unnamed Region)"
        end
    end
end


------------------------------------------------------------
-- UPDATE DISPLAY
------------------------------------------------------------

local function update_cue()

    local cursor =
        reaper.GetCursorPosition()

    local cues =
        get_all_cues()


    --------------------------------------------------------
    -- 1. Check for marker or region START
    --
    -- This has priority.
    --------------------------------------------------------

    local start_cue =
        find_start_cue(cursor, cues)

    if start_cue then

        ----------------------------------------------------
        -- If this is a new cue, display it.
        ----------------------------------------------------

        local changed =
            start_cue.type ~= last_type
            or start_cue.id ~= last_id
            or start_cue.start_pos ~= last_position

        if changed then
            set_display_from_cue(start_cue)
        end

        return
    end


    --------------------------------------------------------
    -- 2. Check for a REGION END
    --------------------------------------------------------

    local ending_region =
        find_region_end(cursor, cues)

    if not ending_region then
        return
    end


    --------------------------------------------------------
    -- 3. We reached the end of a region.
    --
    -- Find the smallest region that still contains
    -- the cursor.
    --------------------------------------------------------

    local enclosing_region =
        find_innermost_region(cursor, cues)


    --------------------------------------------------------
    -- 4. If another region contains this position,
    -- display that region.
    --------------------------------------------------------

    if enclosing_region then

        local changed =
            enclosing_region.type ~= last_type
            or enclosing_region.id ~= last_id
            or enclosing_region.start_pos ~= last_position

        if changed then
            set_display_from_cue(enclosing_region)
        end

        return
    end


    --------------------------------------------------------
    -- 5. No enclosing region.
    --
    -- This means we've reached the end of the
    -- outermost region.
    --
    -- DO NOTHING.
    --
    -- The display remains unchanged.
    --------------------------------------------------------

end


------------------------------------------------------------
-- FIND FONT SIZE THAT FITS WINDOW
------------------------------------------------------------

local function get_fitting_font_size(text)

    local low = 10
    local high = 1000
    local best = 10

    while low <= high do

        local mid =
            math.floor((low + high) / 2)

        gfx.setfont(1,"Arial Bold",mid)

        local text_width,
              text_height =
            gfx.measurestr(text)


        local padding_x =
            gfx.w * 0.02

        local padding_y =
            gfx.h * 0.05


        if text_width <= gfx.w - padding_x * 2
           and text_height <= gfx.h - padding_y * 2 then

            best = mid
            low = mid + 1

        else

            high = mid - 1

        end
    end

    return best
end


------------------------------------------------------------
-- DRAW DISPLAY
------------------------------------------------------------

local function draw()

    --------------------------------------------------------
    -- Background
    --------------------------------------------------------

    gfx.set(0,0,0,1)

    gfx.rect(0,0,gfx.w,gfx.h,1)


    --------------------------------------------------------
    -- Calculate maximum font size
    --------------------------------------------------------

    local font_size =
        get_fitting_font_size(display_name)


    gfx.setfont(1,"Arial Bold",font_size)


    --------------------------------------------------------
    -- Measure text
    --------------------------------------------------------

    local text_width,text_height = gfx.measurestr(display_name)


    --------------------------------------------------------
    -- Center text
    --------------------------------------------------------

    local x = (gfx.w - text_width) / 2

    local y = (gfx.h - text_height) / 2


    --------------------------------------------------------
    -- Shadow
    --------------------------------------------------------

    gfx.set(0,0,0,1)

    gfx.x = x + 3
    gfx.y = y + 3

    gfx.drawstr(display_name)


    --------------------------------------------------------
    -- Main text
    --------------------------------------------------------

    gfx.set(0.4314,0.8039,0.5020,1)

    gfx.x = x
    gfx.y = y

    gfx.drawstr(display_name)


    --------------------------------------------------------
    -- Update window
    --------------------------------------------------------

    gfx.update()
end


------------------------------------------------------------
-- MAIN LOOP
------------------------------------------------------------

local function main()

    update_cue()

    draw()


    --------------------------------------------------------
    -- Window / keyboard input
    --------------------------------------------------------

    local char = gfx.getchar()


    --------------------------------------------------------
    -- Close with:
    --   X button
    --   ESC
    --------------------------------------------------------

    if char == -1
       or char == 27 then

        gfx.quit()

        return
    end


    --------------------------------------------------------
    -- Continue
    --------------------------------------------------------

    reaper.defer(main)
end


------------------------------------------------------------
-- CREATE WINDOW
------------------------------------------------------------

gfx.init(WINDOW_TITLE,WINDOW_WIDTH,WINDOW_HEIGHT,0)


------------------------------------------------------------
-- START
------------------------------------------------------------

main()
