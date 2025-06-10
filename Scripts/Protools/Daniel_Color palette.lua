reaper.set_action_options(1)

-- ReaImGui Color Palette Script for Reaper (No Text, Square Buttons, Correct Layout)
local reaper = reaper
local imgui = reaper.ImGui_CreateContext("Color Palette")

-- List of predefined colors in RGB format (from hex codes)
local colors = {
    {0x2c, 0x00, 0xfc},   -- #2c00fc
    {0x56, 0x00, 0xfc},   -- #5600fc
    {0x88, 0x00, 0xfc},   -- #8800fc
    {0xbf, 0x00, 0xfc},   -- #bf00fc
    {0xbe, 0x00, 0xc0},   -- #be00c0
    {0xbd, 0x00, 0x88},   -- #bd0088
    {0xbd, 0x00, 0x54},   -- #bd0054
    {0xbc, 0x00, 0x0d},   -- #bc000d
    {0xbd, 0x1e, 0x0d},   -- #bd1e0d
    {0xbd, 0x52, 0x0e},   -- #bd520e
    {0xbe, 0x89, 0x11},   -- #be8911
    {0xc0, 0xc5, 0x14},   -- #c0c514
    {0x89, 0xc5, 0x11},   -- #89c511
    {0x57, 0xc6, 0x10},   -- #57c610
    {0x2e, 0xc6, 0x0f},   -- #2ec60f
    {0x1c, 0xc6, 0x0e},   -- #1cc60e
    {0x1e, 0xc6, 0x54},   -- #1ec654
    {0x20, 0xc4, 0x88},   -- #20c488
    {0x23, 0xc3, 0xc1},   -- #23c3c1
    {0x27, 0xc1, 0xfd},   -- #27c1fd
    {0x21, 0x84, 0xfc},   -- #2184fc
    {0x1c, 0x4a, 0xfc},   -- #1c4afc
    {0x19, 0x00, 0xfc},   -- #1900fc
    {0x1e, 0x00, 0xa3},   -- #1e00a3
    {0x37, 0x00, 0xa3},   -- #3700a3
    {0x55, 0x00, 0xa3},   -- #5500a3
    {0x74, 0x00, 0xa4},   -- #7400a4
    {0x7c, 0x00, 0x89},   -- #7c0089
    {0x7b, 0x00, 0x66},   -- #7b0066
    {0x7a, 0x00, 0x46},   -- #7a0046
    {0x7a, 0x00, 0x0b},   -- #7a000b
    {0x7a, 0x12, 0x0b},   -- #7a120b
    {0x7a, 0x31, 0x0c},   -- #7a310c
    {0x7b, 0x51, 0x0d},   -- #7b510d
    {0x89, 0x80, 0x10},   -- #898010
    {0x66, 0x80, 0x0e},   -- #66800e
    {0x48, 0x80, 0x0d},   -- #48800d
    {0x2d, 0x80, 0x0c},   -- #2d800c
    {0x18, 0x80, 0x0c},   -- #18800c
    {0x15, 0x80, 0x33},   -- #158033
    {0x16, 0x7f, 0x51},   -- #167f51
    {0x1a, 0x8c, 0x7e},   -- #1a8c7e
    {0x1d, 0x8d, 0xa4},   -- #1d8da4
    {0x19, 0x69, 0xa4},   -- #1969a4
    {0x16, 0x46, 0xa3},   -- #1646a3
    {0x14, 0x23, 0xa3},   -- #1423a3
    {0x14, 0x00, 0x5f},   -- #14005f
    {0x21, 0x00, 0x5f},   -- #21005f
    {0x31, 0x00, 0x5f},   -- #31005f
    {0x41, 0x00, 0x5f},   -- #41005f
    {0x4b, 0x00, 0x57},   -- #4b0057
    {0x47, 0x00, 0x42},   -- #470042
    {0x47, 0x00, 0x31},   -- #470031
    {0x47, 0x00, 0x0b},   -- #47000b
    {0x47, 0x0c, 0x0b},   -- #470c0b
    {0x47, 0x1c, 0x0b},   -- #471c0b
    {0x47, 0x2c, 0x0c},   -- #472c0c
    {0x57, 0x4d, 0x0f},   -- #574d0f
    {0x42, 0x4a, 0x0c},   -- #424a0c
    {0x32, 0x4a, 0x0c},   -- #324a0c
    {0x23, 0x4a, 0x0c},   -- #234a0c
    {0x15, 0x4b, 0x0b},   -- #154b0b
    {0x0f, 0x4a, 0x1d},   -- #0f4a1d
    {0x0f, 0x4a, 0x2c},   -- #0f4a2c
    {0x14, 0x59, 0x4c},   -- #14594c
    {0x16, 0x59, 0x5f},   -- #16595f
    {0x14, 0x47, 0x5f},   -- #14475f
    {0x13, 0x35, 0x5f},   -- #13355f
    {0x11, 0x22, 0x5f},   -- #11225f
}

-- Converts RGB to ImGui color format (RGBA)
local function RGBToImGui(r, g, b)
    return (r << 24) + (g << 16) + (b << 8) + 255  -- Add 255 for alpha
end

-- Function to brighten a color slightly
local function brightenColor(r, g, b, increase)
    r = math.min(r + increase, 255)
    g = math.min(g + increase, 255)
    b = math.min(b + increase, 255)
    return r, g, b
end

-- Assigns the selected color to all selected tracks
local function applyColor(r, g, b)
    local color = reaper.ColorToNative(r, g, b) -- Use Reaper's native color format
    local num_tracks = reaper.CountSelectedTracks(0)
    local num_items = reaper.CountSelectedMediaItems(0)
    
    if num_items == 0 then
      for i = 0, num_tracks - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        reaper.SetTrackColor(track, color)
      end
    
    else
      for i = 0, num_items - 1 do
       local item = reaper.GetSelectedMediaItem(0, i)
       reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", color | 0x1000000)
      end
    end

    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
end

-- Main loop to draw the window and handle user interaction
function loop()
    -- Set the window size to 520x102 pixels
    reaper.ImGui_SetNextWindowSize(imgui, 520, 102, reaper.ImGui_Cond_FirstUseEver())
    
    -- Begin the window, store the open state in a variable
    local visible, open = reaper.ImGui_Begin(imgui, "Color Palette", true)
    
    -- Check if the user closes the window
    if not open then
        reaper.ImGui_End(imgui)
        return  -- Exit the loop and stop running
    end
    
    -- Get window dimensions
    local windowWidth = reaper.ImGui_GetWindowWidth(imgui)
    local windowHeight =reaper.ImGui_GetWindowHeight(imgui)
    -- Calculate button size based on the window width
    local padding = reaper.ImGui_GetStyleVar(imgui, reaper.ImGui_StyleVar_ItemSpacing())
    local availableWidth = windowWidth - padding * 1.8  -- Padding between buttons
    local buttonSize = (availableWidth / 23) - 2
    reaper.ImGui_SetWindowSize(imgui, windowWidth, (buttonSize * 3) + padding * 4 + 11, reaper.ImGui_Cond_Always())
    
    if visible then
        for i, color in ipairs(colors) do
            local r, g, b = table.unpack(color)
            -- Set the button color using RGB values converted to ImGui color format
            local buttonColor = RGBToImGui(r, g, b)  -- Convert RGB to ImGui's color format

            -- Create a brighter version of the color for hover effect
            local hoverR, hoverG, hoverB = brightenColor(r, g, b, 15)  -- Brighten by 15 units
            local hoverColor = RGBToImGui(hoverR, hoverG, hoverB)

            -- Push button color and hover color
            reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_Button(), buttonColor)
            reaper.ImGui_PushStyleColor(imgui, reaper.ImGui_Col_ButtonHovered(), hoverColor)  -- Brighter color for hover
            
            -- Create a square clickable color button without text (20x20 pixels)
            if reaper.ImGui_Button(imgui, "##" .. i, buttonSize, buttonSize) then
                applyColor(r, g, b)
            end

            -- Remove active color change behavior (disable active state change)
            reaper.ImGui_PopStyleColor(imgui)  -- Pop the hovered button style
            reaper.ImGui_PopStyleColor(imgui)  -- Pop the regular button style
            
            -- Arrange buttons in rows of 23 per line
            if (i % 23 ~= 0) then
                reaper.ImGui_SameLine(imgui, 0, 2) -- Same line, add small spacing between buttons
            end
        end
        reaper.ImGui_End(imgui)
    end
    reaper.defer(loop)
end

-- Start the loop
loop()
