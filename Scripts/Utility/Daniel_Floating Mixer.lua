-- === CONFIG ===
local max_dB, min_dB, unity_dB = 12.0, -140.0, 0.0
local unity_pos, taper_below, taper_above = 0.68, 0.25, 0.6
local knob_aspect, hit_margin = 0.5, 0.3
local double_click_threshold = 0.3
local max_name_len = 7 -- truncate length for track names
local side_margin = 20  -- margin on left and right

-- === UTILITY ===
local function slider_to_DVOL(s)
    if s <= 0 then return 0 end
    if s < unity_pos then
        local f = s / unity_pos
        local dB = min_dB + (unity_dB - min_dB)*(f^taper_below)
        return 10^(dB/20)
    else
        local f = (s-unity_pos)/(1-unity_pos)
        local dB = unity_dB + (max_dB-unity_dB)*(f^taper_above)
        return 10^(dB/20)
    end
end

local function DVOL_to_slider(v)
    if v <= 0 then return 0 end
    local dB = 20 * math.log(v, 10)
    if dB <= unity_dB then
        local f = (dB - min_dB) / (unity_dB - min_dB)
        return (f^(1/taper_below)) * unity_pos
    else
        local f = (dB - unity_dB) / (max_dB - unity_dB)
        return unity_pos + (f^(1/taper_above)) * (1 - unity_pos)
    end
end

local function shorten_name(name, max_len)
    if #name > max_len then
        return string.sub(name,1,max_len).."..."
    end
    return name
end

-- === INIT TRACKS ===
local track_count = reaper.CountSelectedTracks(0)
if track_count == 0 then reaper.ShowMessageBox("No tracks selected.","Error",0) return end

local tracks = {}
for i = 0, track_count-1 do
    local track = reaper.GetSelectedTrack(0,i)
    local vol = reaper.GetMediaTrackInfo_Value(track,"D_VOL")
    local _, name = reaper.GetSetMediaTrackInfo_String(track,"P_NAME","",false)
    tracks[i+1] = {
        track=track, slider_value=DVOL_to_slider(vol), last_vol=vol,
        name=name ~= "" and name or "Track "..(i+1),
        mute=reaper.GetMediaTrackInfo_Value(track,"B_MUTE"),
        solo=reaper.GetMediaTrackInfo_Value(track,"I_SOLO"),
        selected=false, index=i+1,
        mute_rect=nil, solo_rect=nil, name_rect=nil
    }
end

gfx.init("Daniel Floating Mixer", track_count*100, 500) -- initial width 800, resizable

-- === STATE ===
local prev_mouse_down=false
local drag_start_y=0
local drag_start_values={}
local click_start_y=0
local is_dragging=false
local drag_threshold=2
local last_selected_index=nil
local temp_drag_selection={}
local last_click_time=0
local last_click_track=nil
local tooltip_text=nil

local function mouse_over_knob(t,mx,my)
    local win_h = gfx.h
    local fader_bottom = win_h - 0.18*win_h
    local fader_top = 0.12*win_h
    local fader_height = fader_bottom - fader_top
    local available_width = gfx.w - 2*side_margin
    local fader_spacing = available_width / track_count
    local x = side_margin + (t.index - 0.5) * fader_spacing
    local knob_w = 0.4 * fader_spacing
    local knob_h = knob_w * knob_aspect
    local knob_y = fader_bottom - t.slider_value * fader_height
    local hit_w = knob_w*(1+hit_margin)
    local hit_h = knob_h*(1+hit_margin)
    return mx>=x-hit_w/2 and mx<=x+hit_w/2 and my>=knob_y-hit_h/2 and my<=knob_y+hit_h/2
end

local function shift_pressed() return gfx.mouse_cap & 8 == 8 end
local function ctrl_pressed() return gfx.mouse_cap & 4 == 4 end

-- === DRAW ===
local function draw_sliders()
    local win_w,win_h = gfx.w,gfx.h
    local top_margin = 0.12*win_h
    local bottom_margin = 0.15*win_h
    local fader_bottom = win_h - bottom_margin
    local fader_top = top_margin
    local fader_height = fader_bottom - fader_top

    gfx.set(0.2,0.2,0.2,1)
    gfx.rect(0,0,win_w,win_h,1)

    local track_font_size = math.floor(0.2*win_w/track_count)
    gfx.setfont(1,"Arial",track_font_size)

    local mx,my = gfx.mouse_x, gfx.mouse_y
    tooltip_text = nil

    local available_width = win_w - 2*side_margin
    local fader_spacing = available_width / track_count

    for _,t in ipairs(tracks) do
        local x = side_margin + (_ - 0.5) * fader_spacing

        -- Track name
        local display_name = shorten_name(t.name, max_name_len)
        gfx.set(1,1,1,1)
        local name_w,name_h = gfx.measurestr(display_name)
        gfx.x = x - name_w/2
        gfx.y = 5
        gfx.printf("%s", display_name)
        t.name_rect = {gfx.x, gfx.y, name_w, name_h}
        if mx >= gfx.x and mx <= gfx.x+name_w and my >= gfx.y and my <= gfx.y+name_h and #t.name>max_name_len then
            tooltip_text = t.name
        end

        -- Fader background
        local fader_w = 0.1*fader_spacing
        gfx.set(0,0,0,0.5)
        gfx.rect(x-fader_w/2,fader_top,fader_w,fader_height,1)
        
        -- --- 0 dB tick ---
        local zero_y = fader_bottom - unity_pos * fader_height
        local tick_w = fader_w * 4
        gfx.set(0.5, 0.5, 0.5, 1)
        gfx.rect(x - tick_w/2, zero_y-1, tick_w, 2, 1)

        -- Knob
        local knob_w = 0.7*fader_spacing
        local knob_h = knob_w*knob_aspect
        local knob_y = fader_bottom - t.slider_value*fader_height
        gfx.set(t.selected and 1 or 0.7, t.selected and 1 or 0.7, t.selected and 1 or 0.7,0.8)
        gfx.rect(x-knob_w/2, knob_y-knob_h/2, knob_w, knob_h,1)
        if t.selected then
            gfx.set(1,1,1,1)
            gfx.rect(x-knob_w/2-2, knob_y-knob_h/2-2, knob_w+4, knob_h+4,0)
        end

        -- dB label
        local db = (t.slider_value<=0) and "-inf" or string.format("%.1f",20*math.log(slider_to_DVOL(t.slider_value),10))
        local db_w,db_h = gfx.measurestr(db)
        gfx.set(0,0,0,0.8)
        gfx.x = x - db_w/2
        gfx.y = knob_y - db_h/2
        gfx.printf("%s", db)

        -- Buttons
        local btn_w = math.min(30,0.4*fader_spacing)
        local btn_h = btn_w
        local btn_y = win_h - bottom_margin + (bottom_margin - btn_h)/2
        local spacing = 0.03*fader_spacing

        -- Mute button
        if t.mute==1 then
            gfx.set(191/255,101/255,34/255,1)
            gfx.rect(x-btn_w-spacing/2,btn_y,btn_w,btn_h,1)
            gfx.set(0,0,0,1)
        else
            gfx.set(0.3,0.3,0.3,1)
            gfx.rect(x-btn_w-spacing/2,btn_y,btn_w,btn_h,1)
            gfx.set(1,1,1,1)
        end
        local m_w,m_h = gfx.measurestr("M")
        gfx.x = x - btn_w - spacing/2 + (btn_w-m_w)/2
        gfx.y = btn_y + (btn_h-m_h)/2
        gfx.printf("M")
        t.mute_rect = {x-btn_w-spacing/2,btn_y,btn_w,btn_h}

        -- Solo button
        if t.solo==1 then
            gfx.set(230/255,216/255,96/255,1)
            gfx.rect(x+spacing/2,btn_y,btn_w,btn_h,1)
            gfx.set(0,0,0,1)
        else
            gfx.set(0.3,0.3,0.3,1)
            gfx.rect(x+spacing/2,btn_y,btn_w,btn_h,1)
            gfx.set(1,1,1,1)
        end
        local s_w,s_h = gfx.measurestr("S")
        gfx.x = x + spacing/2 + (btn_w-s_w)/2
        gfx.y = btn_y + (btn_h-s_h)/2
        gfx.printf("S")
        t.solo_rect = {x+spacing/2,btn_y,btn_w,btn_h}
    end

    -- Tooltip
    if tooltip_text then
        gfx.setfont(1,"Arial",14)
        local tw,th = gfx.measurestr(tooltip_text)
        gfx.set(0,0,0,0.7)
        gfx.rect(mx+10,my+10,tw+6,th+6,1)
        gfx.set(1,1,1,1)
        gfx.x = mx+10
        gfx.y = my+10
        gfx.printf("%s",tooltip_text)
    end
end

-- === MAIN LOOP ===
local function mainloop()
    local mx,my=gfx.mouse_x,gfx.mouse_y
    local lb=gfx.mouse_cap & 1
    local mouse_down=(lb==1)

    -- BUTTON CLICKS
    if mouse_down and not prev_mouse_down then
        for _,t in ipairs(tracks) do
            if t.mute_rect then
                local x,y,w,h = table.unpack(t.mute_rect)
                if mx>=x and mx<=x+w and my>=y and my<=y+h then
                    t.mute = 1-t.mute
                    reaper.SetMediaTrackInfo_Value(t.track,"B_MUTE",t.mute)
                end
            end
            if t.solo_rect then
                local x,y,w,h = table.unpack(t.solo_rect)
                if mx>=x and mx<=x+w and my>=y and my<=y+h then
                    t.solo = 1-t.solo
                    reaper.SetMediaTrackInfo_Value(t.track,"I_SOLO",t.solo)
                end
            end
        end
    end

    -- MOUSE DOWN
    if mouse_down and not prev_mouse_down then
        click_start_y = my
        is_dragging=false
        drag_start_values={}
        temp_drag_selection={}

        local clicked_knob=nil
        for _,t in ipairs(tracks) do if mouse_over_knob(t,mx,my) then clicked_knob=t break end end

        -- DOUBLE CLICK
        local now=reaper.time_precise()
        if clicked_knob and last_click_track==clicked_knob.index and now-last_click_time<double_click_threshold then
            clicked_knob.slider_value=DVOL_to_slider(1.0)
            local vol=slider_to_DVOL(clicked_knob.slider_value)
            reaper.SetMediaTrackInfo_Value(clicked_knob.track,"D_VOL",vol)
            clicked_knob.last_vol=vol
        end
        last_click_time=now
        last_click_track=clicked_knob and clicked_knob.index or nil

        if clicked_knob then
            local any_selected=false
            for _,t in ipairs(tracks) do if t.selected then any_selected=true break end end
            if not any_selected then temp_drag_selection[clicked_knob.index]=true drag_start_values[clicked_knob.index]=clicked_knob.slider_value end
        else
            for _,t in ipairs(tracks) do t.selected=false end
            last_selected_index=nil
        end
    end

    -- START DRAG
    if mouse_down and not is_dragging and math.abs(my-click_start_y)>2 then
        is_dragging=true
        drag_start_y=my
        for _,t in ipairs(tracks) do if t.selected then drag_start_values[t.index]=t.slider_value end end
        for idx,_ in pairs(temp_drag_selection) do drag_start_values[idx]=tracks[idx].slider_value end
    end

    -- DRAGGING
    if mouse_down and is_dragging then
        local win_h=gfx.h
        local fader_bottom=win_h-0.18*win_h
        local fader_top=0.12*win_h
        local fader_height=fader_bottom-fader_top
        local delta=(drag_start_y-my)/fader_height
        for idx,_ in pairs(drag_start_values) do
            local t=tracks[idx]
            local new_val=drag_start_values[idx]+delta
            t.slider_value=math.max(0,math.min(1,new_val))
            local vol=slider_to_DVOL(t.slider_value)
            reaper.SetMediaTrackInfo_Value(t.track,"D_VOL",vol)
            t.last_vol=vol
        end
    end

    -- MOUSE UP: selection logic
    if not mouse_down and prev_mouse_down then
        local clicked_knob=nil
        for _,t in ipairs(tracks) do if mouse_over_knob(t,mx,my) then clicked_knob=t break end end

        if clicked_knob then
            if ctrl_pressed() then
                clicked_knob.selected=not clicked_knob.selected
                last_selected_index=clicked_knob.index
            elseif shift_pressed() and last_selected_index then
                local a,b=math.min(last_selected_index,clicked_knob.index),math.max(last_selected_index,clicked_knob.index)
                for i=a,b do tracks[i].selected=true end
            else
                for _,t in ipairs(tracks) do t.selected=false end
                clicked_knob.selected=true
                last_selected_index=clicked_knob.index
            end
        end
        temp_drag_selection={}
        drag_start_values={}
        is_dragging=false
    end

    -- SYNC EXTERNAL CHANGES
    for _,t in ipairs(tracks) do
        local vol = reaper.GetMediaTrackInfo_Value(t.track,"D_VOL")
        if math.abs(vol-t.last_vol)>1e-7 then
            t.slider_value = DVOL_to_slider(vol)
            t.last_vol = vol
        end
        t.mute = reaper.GetMediaTrackInfo_Value(t.track,"B_MUTE")
        t.solo = reaper.GetMediaTrackInfo_Value(t.track,"I_SOLO")
    end

    prev_mouse_down = mouse_down
    draw_sliders()
    if gfx.getchar()>=0 then reaper.defer(mainloop) end
end

mainloop()

