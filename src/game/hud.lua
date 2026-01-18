-- HUD Module
-- Displays hull bar, compass, altimeter, control hints, and mission panel
-- Renders directly to software renderer buffer for consistent pixel art look

local quat = require("quat")
local mat4 = require("mat4")
local config = require("config")
local controls = require("input.controls")

local HUD = {}

-- Configuration (positions for 480x270 render resolution)
local HULL_BAR_X = 2
local HULL_BAR_Y = 250
local HULL_BAR_WIDTH = 100
local HULL_BAR_HEIGHT = 10

local COMPASS_X = 230
local COMPASS_Y = 240
local COMPASS_SIZE = 12

local CONTROL_HINT_X = 2
local CONTROL_HINT_Y = 132

-- Mission panel configuration
local MISSION_BOX_X = 5
local MISSION_BOX_Y = 5
local MISSION_BOX_WIDTH = 200

-- Colors from Picotron palette (RGB 0-255)
local COLOR_BLACK = {0x00, 0x00, 0x00}      -- 0: Black
local COLOR_DARK_BLUE = {0x1d, 0x2b, 0x53}  -- 1: Dark blue (UI backgrounds)
local COLOR_DARK_GREY = {0x5f, 0x57, 0x4f}  -- 5: Dark grey
local COLOR_GREY = {0xc2, 0xc3, 0xc7}       -- 6: Light grey
local COLOR_WHITE = {0xff, 0xf1, 0xe8}      -- 7: White/cream
local COLOR_RED = {0xff, 0x00, 0x4d}        -- 8: Red
local COLOR_ORANGE = {0xff, 0xa3, 0x00}     -- 9: Orange
local COLOR_YELLOW = {0xff, 0xec, 0x27}     -- 10: Yellow
local COLOR_GREEN = {0x00, 0xe4, 0x36}      -- 11: Green
local COLOR_CYAN = {0x29, 0xad, 0xff}       -- 12: Cyan/blue

-- Show controls toggle (press C to toggle, always on for mission 1)
local show_controls = true
local current_mission = 1

-- Goal box visibility (press G to toggle, default shown for tutorial missions 1-2)
local show_goal_box = true

-- Pause menu state
local show_pause_menu = false

-- Renderer reference (set via init)
local renderer = nil

-- Initialize with renderer reference
function HUD.init(r)
    renderer = r
end

-- Helper: get text width using renderer
local function getTextWidth(text, scale)
    if renderer and renderer.getTextWidth then
        return renderer.getTextWidth(text, scale or 1)
    end
    -- Fallback: approximate 5 pixels per character at scale 1
    return #text * 5 * (scale or 1)
end

-- Helper: get X position to center text on screen
local function centerTextX(text, scale)
    local width = getTextWidth(text, scale)
    return (config.RENDER_WIDTH - width) / 2
end

-- Set current mission number (affects control hints and goal box visibility)
function HUD.set_mission(mission_num)
    current_mission = mission_num
    -- Default: controls hidden (C to toggle), goals shown (G to toggle)
    show_controls = false
    show_goal_box = true
end

-- Toggle control hints
function HUD.toggle_controls()
    show_controls = not show_controls
    return show_controls
end

-- Toggle goal box visibility
function HUD.toggle_goal_box()
    show_goal_box = not show_goal_box
    return show_goal_box
end

-- Toggle pause menu
function HUD.toggle_pause()
    show_pause_menu = not show_pause_menu
    return show_pause_menu
end

-- Check if paused
function HUD.is_paused()
    return show_pause_menu
end

-- Close pause menu
function HUD.close_pause()
    show_pause_menu = false
end

-- Draw hull/health bar
function HUD.draw_hull_bar(ship)
    local health = ship.health or 100
    local max_health = ship.max_health or 100
    local health_percent = health / max_health

    -- Background (dark)
    renderer.drawRectFill(HULL_BAR_X, HULL_BAR_Y,
                          HULL_BAR_X + HULL_BAR_WIDTH, HULL_BAR_Y + HULL_BAR_HEIGHT,
                          COLOR_DARK_BLUE[1], COLOR_DARK_BLUE[2], COLOR_DARK_BLUE[3])

    -- Health fill (color based on level)
    local health_width = HULL_BAR_WIDTH * math.max(0, health_percent)
    local health_color = COLOR_GREEN
    if health_percent < 0.3 then
        health_color = COLOR_RED
    elseif health_percent < 0.6 then
        health_color = COLOR_ORANGE
    end

    if health_width > 0 then
        renderer.drawRectFill(HULL_BAR_X, HULL_BAR_Y,
                              HULL_BAR_X + health_width, HULL_BAR_Y + HULL_BAR_HEIGHT,
                              health_color[1], health_color[2], health_color[3])
    end

    -- Border
    renderer.drawRect(HULL_BAR_X, HULL_BAR_Y,
                      HULL_BAR_X + HULL_BAR_WIDTH, HULL_BAR_Y + HULL_BAR_HEIGHT,
                      COLOR_DARK_BLUE[1], COLOR_DARK_BLUE[2], COLOR_DARK_BLUE[3])

    -- Health text
    renderer.drawText(HULL_BAR_X + 2, HULL_BAR_Y + 2,
                      "HULL: " .. math.floor(math.max(0, health_percent * 100)) .. "%",
                      COLOR_BLACK[1], COLOR_BLACK[2], COLOR_BLACK[3], 1, false)
end

-- Draw 3D compass with altitude and speed
function HUD.draw_compass(ship, camera, mission_target)
    -- Black box background for compass, altitude, and speed (centered on screen)
    local box_width = 115
    local box_height = 30
    local screen_center = config.RENDER_WIDTH / 2
    local box_x1 = screen_center - box_width / 2
    local box_x2 = screen_center + box_width / 2
    local box_y1 = COMPASS_Y - box_height / 2
    local box_y2 = COMPASS_Y + box_height / 2

    -- Compass dial position (left side of box)
    local compass_x = box_x1 + 25

    renderer.drawRectFill(box_x1, box_y1, box_x2, box_y2,
                          COLOR_BLACK[1], COLOR_BLACK[2], COLOR_BLACK[3])
    renderer.drawRect(box_x1, box_y1, box_x2, box_y2,
                      COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3])

    -- Create 4 arrow tips in world space (forming a 3D cross)
    local points_3d = {
        {x = 0, y = 0, z = COMPASS_SIZE},    -- 1: North tip (red)
        {x = 0, y = 0, z = -COMPASS_SIZE},   -- 2: South tip (grey)
        {x = COMPASS_SIZE, y = 0, z = 0},    -- 3: East tip (grey)
        {x = -COMPASS_SIZE, y = 0, z = 0},   -- 4: West tip (grey)
        {x = 0, y = 0, z = 0},               -- 5: Center
    }

    -- Get camera rotation (pitch and yaw)
    local pitch = camera.pitch or 0
    local yaw = camera.yaw or 0
    local cos_pitch, sin_pitch = math.cos(pitch), math.sin(pitch)
    local cos_yaw, sin_yaw = math.cos(yaw), math.sin(yaw)

    -- Transform points by camera rotation and project to screen
    local projected_points = {}
    for i, p in ipairs(points_3d) do
        -- Rotate by camera yaw (Y axis)
        local x_yaw = p.x * cos_yaw - p.z * sin_yaw
        local z_yaw = p.x * sin_yaw + p.z * cos_yaw

        -- Rotate by camera pitch (X axis)
        local y_pitch = p.y * cos_pitch - z_yaw * sin_pitch
        local z_pitch = p.y * sin_pitch + z_yaw * cos_pitch

        -- Project to screen (orthographic)
        projected_points[i] = {
            x = compass_x + x_yaw,
            y = COMPASS_Y + y_pitch,
            z = z_pitch  -- Store depth for sorting
        }
    end

    -- Create arrows (lines from center to tips)
    local arrows = {
        {from = 5, to = 1, color = COLOR_RED, z = projected_points[1].z},   -- North (red)
        {from = 5, to = 2, color = COLOR_GREY, z = projected_points[2].z},  -- South (grey)
        {from = 5, to = 3, color = COLOR_GREY, z = projected_points[3].z},  -- East (grey)
        {from = 5, to = 4, color = COLOR_GREY, z = projected_points[4].z},  -- West (grey)
    }

    -- Sort arrows by depth (back to front, furthest first)
    table.sort(arrows, function(a, b) return a.z < b.z end)

    -- Draw arrows in sorted order (back to front)
    for _, arrow in ipairs(arrows) do
        -- Draw compass direction arrows
        local p1 = projected_points[arrow.from]
        local p2 = projected_points[arrow.to]
        renderer.drawLine2D(p1.x, p1.y, p2.x, p2.y,
                           arrow.color[1], arrow.color[2], arrow.color[3])
        renderer.drawCircleFill(p2.x, p2.y, 1,
                                arrow.color[1], arrow.color[2], arrow.color[3])
    end

    -- Center dot (drawn last, always on top)
    renderer.drawCircleFill(compass_x, COMPASS_Y, 2,
                            COLOR_BLACK[1], COLOR_BLACK[2], COLOR_BLACK[3])
    renderer.drawCircle(compass_x, COMPASS_Y, 2,
                        COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3])

    -- Altitude counter (1 world unit = 10 meters)
    local altitude_meters = (ship.y or 0) * 10
    renderer.drawText(compass_x + 20, COMPASS_Y - 8,
                      "ALT: " .. math.floor(altitude_meters) .. "m",
                      COLOR_CYAN[1], COLOR_CYAN[2], COLOR_CYAN[3], 1, true)

    -- Speed counter (m/s) - calculate total velocity magnitude
    local vx = ship.vx or 0
    local vy = ship.vy or 0
    local vz = ship.vz or 0
    local speed = math.sqrt(vx*vx + vy*vy + vz*vz) * 100  -- Convert to m/s (1 unit = 100m)
    renderer.drawText(compass_x + 20, COMPASS_Y + 2,
                      "SPD: " .. math.floor(speed) .. "m/s",
                      COLOR_YELLOW[1], COLOR_YELLOW[2], COLOR_YELLOW[3], 1, true)
end

-- Draw control hints
function HUD.draw_controls(game_mode)
    -- Only show controls in tutorial mission (mission 1) or when explicitly toggled
    -- Outside tutorial, controls are hidden by default and shown via pause menu
    if current_mission ~= 1 and not show_controls then
        return
    end

    local hint_x, hint_y = CONTROL_HINT_X, CONTROL_HINT_Y

    -- Get control prompts based on game mode and input device
    local control_prompts
    if game_mode ~= "simulation" then
        control_prompts = controls.get_prompts("arcade_controls")
    else
        control_prompts = controls.get_prompts("simulation_controls")
    end

    -- Draw control prompts
    for i, line in ipairs(control_prompts) do
        local color = (i == 1) and COLOR_WHITE or COLOR_GREY  -- Title in white, rest in grey
        renderer.drawText(hint_x, hint_y, line,
                          color[1], color[2], color[3], 1, true)
        hint_y = hint_y + (i == 1 and 8 or 7)  -- More space after title
    end

    hint_y = hint_y + 3

    -- Camera controls
    local camera_prompts = controls.get_prompts("camera_controls")
    for i, line in ipairs(camera_prompts) do
        local color = (i == 1) and COLOR_WHITE or COLOR_GREY
        renderer.drawText(hint_x, hint_y, line,
                          color[1], color[2], color[3], 1, true)
        hint_y = hint_y + (i == 1 and 8 or 7)
    end
end

-- Draw mission panel (top-left objectives - text only, no box)
function HUD.draw_mission_panel(mission)
    -- Don't draw if goal box is hidden
    if not show_goal_box then return end

    -- mission should have: name, objectives (array of strings)
    if not mission then
        -- Draw placeholder when no mission
        mission = {
            name = "FREE FLIGHT",
            objectives = {
                "Explore the terrain",
                "Practice landing on pads"
            }
        }
    end

    local objectives = mission.objectives or {}
    local line_height = 8
    local text_y = MISSION_BOX_Y + 4

    -- Draw mission name header
    if mission.name and mission.name ~= "" then
        renderer.drawText(MISSION_BOX_X + 4, text_y, mission.name,
                          COLOR_CYAN[1], COLOR_CYAN[2], COLOR_CYAN[3], 1, true)
        text_y = text_y + 10
    end

    -- Draw objectives
    for _, objective in ipairs(objectives) do
        -- Check if this is a special line (key hints are in brackets)
        local is_hint = objective:match("^%[")
        local color = is_hint and COLOR_GREY or COLOR_WHITE

        renderer.drawText(MISSION_BOX_X + 4, text_y, objective,
                          color[1], color[2], color[3], 1, true)
        text_y = text_y + line_height
    end

    -- Draw toggle hint (input-aware)
    text_y = text_y + 4
    local toggle_goals_prompt = controls.get_prompt_bracketed("toggle_goals") .. " Toggle Goals"
    renderer.drawText(MISSION_BOX_X + 4, text_y, toggle_goals_prompt,
                      COLOR_GREY[1], COLOR_GREY[2], COLOR_GREY[3], 1, true)
end

-- Store current mission for pause menu
local pause_menu_mission = nil

function HUD.set_pause_mission(mission)
    pause_menu_mission = mission
end

-- Draw pause menu (centered overlay)
function HUD.draw_pause_menu()
    if not show_pause_menu then return end

    local screen_w = 480
    local screen_h = 270
    local box_width = 200
    local line_height = 12

    -- Calculate height based on mission objectives
    local objectives = (pause_menu_mission and pause_menu_mission.objectives) or {}
    local num_objectives = 0
    for _, obj in ipairs(objectives) do
        if obj and obj ~= "" and not obj:match("^%[") then
            num_objectives = num_objectives + 1
        end
    end

    local box_height = 95 + (num_objectives * line_height)
    local box_x = (screen_w - box_width) / 2
    local box_y = (screen_h - box_height) / 2

    -- Semi-transparent dark overlay
    renderer.drawRectFill(0, 0, screen_w, screen_h,
                          0, 0, 0, 128)

    -- Menu box background
    renderer.drawRectFill(box_x, box_y, box_x + box_width, box_y + box_height,
                          COLOR_DARK_BLUE[1], COLOR_DARK_BLUE[2], COLOR_DARK_BLUE[3], 240)

    -- Menu box border
    renderer.drawRect(box_x, box_y, box_x + box_width, box_y + box_height,
                      COLOR_GREY[1], COLOR_GREY[2], COLOR_GREY[3])

    -- Title
    local title = "PAUSED"
    local title_x = box_x + (box_width - getTextWidth(title)) / 2
    renderer.drawText(title_x, box_y + 10, title,
                      COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3], 1, true)

    local text_y = box_y + 28

    -- Mission name and objectives
    if pause_menu_mission and pause_menu_mission.name then
        local name_x = box_x + (box_width - getTextWidth(pause_menu_mission.name)) / 2
        renderer.drawText(name_x, text_y, pause_menu_mission.name,
                          COLOR_CYAN[1], COLOR_CYAN[2], COLOR_CYAN[3], 1, true)
        text_y = text_y + line_height

        -- Draw objectives (skip empty lines and hint lines)
        for _, obj in ipairs(objectives) do
            if obj and obj ~= "" and not obj:match("^%[") then
                local obj_x = box_x + (box_width - getTextWidth(obj)) / 2
                renderer.drawText(obj_x, text_y, obj,
                                  COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3], 1, true)
                text_y = text_y + line_height
            end
        end
        text_y = text_y + 4
    end

    -- Options (use controls module for input-aware prompts)
    local pause_prompts = controls.get_prompts("pause_menu")
    local option1 = pause_prompts[1] or "[Tab] Resume"
    local option1_x = box_x + (box_width - getTextWidth(option1)) / 2
    renderer.drawText(option1_x, text_y, option1,
                      COLOR_GREY[1], COLOR_GREY[2], COLOR_GREY[3], 1, true)
    text_y = text_y + line_height

    -- Toggle controls text varies based on state
    local toggle_verb = show_controls and "Hide" or "Show"
    local option2 = controls.get_prompt_bracketed("toggle_controls") .. " " .. toggle_verb .. " Controls"
    local option2_x = box_x + (box_width - getTextWidth(option2)) / 2
    renderer.drawText(option2_x, text_y, option2,
                      COLOR_CYAN[1], COLOR_CYAN[2], COLOR_CYAN[3], 1, true)
    text_y = text_y + line_height

    local option3 = pause_prompts[3] or "[Q] Return to Menu"
    local option3_x = box_x + (box_width - getTextWidth(option3)) / 2
    renderer.drawText(option3_x, text_y, option3,
                      COLOR_GREY[1], COLOR_GREY[2], COLOR_GREY[3], 1, true)
end

-- Draw location name (landing pad or building rooftop)
function HUD.draw_location_name(name, location_type)
    if not name then return end

    local text
    if location_type == "pad" then
        text = "At " .. name
    elseif location_type == "building" then
        text = "Rooftop: " .. name
    else
        text = name
    end

    local text_x = centerTextX(text)
    local text_y = 218  -- Above compass

    renderer.drawText(text_x, text_y, text,
                      COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3], 1, true)
end

-- Draw repair indicator
function HUD.draw_repair_indicator(is_repairing)
    if not is_repairing then return end

    -- Flash "REPAIRING" text
    if math.floor(love.timer.getTime() * 2) % 2 == 0 then
        renderer.drawText(HULL_BAR_X + HULL_BAR_WIDTH + 5, HULL_BAR_Y + 1, "REPAIRING",
                          COLOR_GREEN[1], COLOR_GREEN[2], COLOR_GREEN[3], 1, true)
    end
end

-- Draw mission countdown (3-2-1-GO!) for non-race missions
-- Returns true if countdown is being displayed
function HUD.draw_countdown(countdown_data)
    if not countdown_data or not countdown_data.active then
        return false
    end

    local screen_w = config.RENDER_WIDTH or 480
    local screen_h = config.RENDER_HEIGHT or 270

    local countdown_text = ""

    -- Show each number for 1 second:
    -- 4.0-3.0: "3", 3.0-2.0: "2", 2.0-1.0: "1", 1.0-0.0: "GO!"
    if countdown_data.timer > 3.0 then
        countdown_text = "3"
    elseif countdown_data.timer > 2.0 then
        countdown_text = "2"
    elseif countdown_data.timer > 1.0 then
        countdown_text = "1"
    elseif countdown_data.timer > 0 then
        countdown_text = "GO!"
    end

    if countdown_text ~= "" then
        -- Big centered countdown number/text
        local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 10)  -- Fast pulse
        local scale = 3  -- Big text (3x scale)

        -- Calculate position for centered text
        local text_width = getTextWidth(countdown_text, scale)
        local text_x = (screen_w - text_width) / 2
        local text_y = screen_h / 2 - 20

        -- Color: yellow for numbers, green for GO!
        local r, g, b
        if countdown_text == "GO!" then
            r, g, b = 0, math.floor(255 * pulse), 0
        else
            r, g, b = math.floor(255 * pulse), math.floor(255 * pulse), 0
        end

        renderer.drawText(text_x, text_y, countdown_text, r, g, b, scale, true)

        -- "GET READY!" above the number
        local ready_text = "GET READY!"
        local ready_x = centerTextX(ready_text)
        renderer.drawText(ready_x, text_y - 30, ready_text,
                          COLOR_CYAN[1], COLOR_CYAN[2], COLOR_CYAN[3], 1, true)
    end

    return true  -- Countdown is being displayed
end

-- Draw race HUD (timer bar, lap counter) or race complete stats
function HUD.draw_race_hud(race_data)
    if not race_data then return end

    local screen_w = config.RENDER_WIDTH or 480
    local screen_h = config.RENDER_HEIGHT or 270

    -- Race complete: show lap time stats instead of timer
    if race_data.complete then
        HUD.draw_race_complete_stats(race_data, screen_w, screen_h)
        return
    end

    -- Countdown display (3-2-1-GO!)
    if race_data.countdown_active then
        local countdown_text = ""

        -- Show each number for 1 second:
        -- 4.0-3.0: "3", 3.0-2.0: "2", 2.0-1.0: "1", 1.0-0.0: "GO!"
        if race_data.countdown_timer > 3.0 then
            countdown_text = "3"
        elseif race_data.countdown_timer > 2.0 then
            countdown_text = "2"
        elseif race_data.countdown_timer > 1.0 then
            countdown_text = "1"
        elseif race_data.countdown_timer > 0 then
            countdown_text = "GO!"
        end

        if countdown_text ~= "" then
            -- Big centered countdown number/text
            local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 10)  -- Fast pulse
            local scale = 3  -- Big text (3x scale)

            -- Calculate position for centered text
            local text_width = getTextWidth(countdown_text, scale)
            local text_x = (config.RENDER_WIDTH - text_width) / 2
            local text_y = screen_h / 2 - 20

            -- Color: yellow for numbers, green for GO!
            local r, g, b
            if countdown_text == "GO!" then
                r, g, b = 0, math.floor(255 * pulse), 0
            else
                r, g, b = math.floor(255 * pulse), math.floor(255 * pulse), 0
            end

            renderer.drawText(text_x, text_y, countdown_text, r, g, b, scale, true)

            -- "GET READY!" above the number
            local ready_text = "GET READY!"
            local ready_x = centerTextX(ready_text)
            renderer.drawText(ready_x, text_y - 30, ready_text,
                              COLOR_CYAN[1], COLOR_CYAN[2], COLOR_CYAN[3], 1, true)
        end
        return  -- Don't show timer bar during countdown
    end

    -- Timer bar position (top center of screen)
    local bar_width = 180
    local bar_height = 14
    local bar_x = (screen_w - bar_width) / 2
    local bar_y = 8

    -- Calculate timer progress
    local timer_percent = race_data.checkpoint_timer / race_data.checkpoint_max_time
    timer_percent = math.max(0, math.min(1, timer_percent))

    -- Timer bar color (green -> yellow -> red as time runs out)
    local timer_color
    if timer_percent > 0.5 then
        timer_color = COLOR_GREEN
    elseif timer_percent > 0.25 then
        timer_color = COLOR_YELLOW
    else
        timer_color = COLOR_RED
    end

    -- Background
    renderer.drawRectFill(bar_x, bar_y, bar_x + bar_width, bar_y + bar_height,
                          COLOR_DARK_BLUE[1], COLOR_DARK_BLUE[2], COLOR_DARK_BLUE[3])

    -- Timer fill
    local fill_width = bar_width * timer_percent
    if fill_width > 0 then
        renderer.drawRectFill(bar_x, bar_y, bar_x + fill_width, bar_y + bar_height,
                              timer_color[1], timer_color[2], timer_color[3])
    end

    -- Border
    renderer.drawRect(bar_x, bar_y, bar_x + bar_width, bar_y + bar_height,
                      COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3])

    -- Timer text (centered on bar)
    local timer_text = string.format("%.1f", math.max(0, race_data.checkpoint_timer))
    local text_x = bar_x + (bar_width - getTextWidth(timer_text)) / 2
    renderer.drawText(text_x, bar_y + 3, timer_text,
                      COLOR_BLACK[1], COLOR_BLACK[2], COLOR_BLACK[3], 1, false)

    -- Lap counter (left side of timer bar)
    local lap_text = "LAP " .. race_data.current_lap .. "/" .. race_data.total_laps
    renderer.drawText(bar_x - getTextWidth(lap_text) - 8, bar_y + 3, lap_text,
                      COLOR_CYAN[1], COLOR_CYAN[2], COLOR_CYAN[3], 1, true)

    -- Total time (right side of timer bar)
    local total_minutes = math.floor(race_data.total_time / 60)
    local total_seconds = race_data.total_time % 60
    local time_text = string.format("%d:%05.2f", total_minutes, total_seconds)
    renderer.drawText(bar_x + bar_width + 8, bar_y + 3, time_text,
                      COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3], 1, true)

    -- Checkpoint flash effect (below timer bar)
    if race_data.checkpoint_flash and race_data.checkpoint_flash > 0 then
        -- Flash "CHECKPOINT!" text
        local flash_text = "CHECKPOINT!"
        local flash_x = centerTextX(flash_text)
        renderer.drawText(flash_x, bar_y + bar_height + 6, flash_text,
                          COLOR_YELLOW[1], COLOR_YELLOW[2], COLOR_YELLOW[3], 1, true)
    end

    -- Failed state (below timer bar)
    if race_data.failed then
        local fail_text = "TIME'S UP!"
        local fail_x = centerTextX(fail_text)
        -- Flash the text
        if math.floor(love.timer.getTime() * 4) % 2 == 0 then
            renderer.drawText(fail_x, bar_y + bar_height + 6, fail_text,
                              COLOR_RED[1], COLOR_RED[2], COLOR_RED[3], 1, true)
        end
    end
end

-- Draw race complete stats (lap times, best lap, total time)
function HUD.draw_race_complete_stats(race_data, screen_w, screen_h)
    local center_x = screen_w / 2
    local start_y = 50

    -- "RACE COMPLETE!" header with pulsing effect
    local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 4)
    local header_text = "RACE COMPLETE!"
    local header_x = centerTextX(header_text)
    renderer.drawText(header_x, start_y, header_text,
                      math.floor(255 * pulse), math.floor(255 * pulse), 0, 1, true)

    -- Total time
    local total_minutes = math.floor(race_data.total_time / 60)
    local total_seconds = race_data.total_time % 60
    local total_text = "TOTAL: " .. string.format("%d:%05.2f", total_minutes, total_seconds)
    local total_x = centerTextX(total_text)
    renderer.drawText(total_x, start_y + 20, total_text,
                      COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3], 1, true)

    -- Lap times
    local lap_y = start_y + 45
    local lap_times = race_data.lap_times or {}

    for i, lap_time in ipairs(lap_times) do
        local lap_min = math.floor(lap_time / 60)
        local lap_sec = lap_time % 60
        local lap_text = "LAP " .. i .. ": " .. string.format("%d:%05.2f", lap_min, lap_sec)

        -- Highlight best lap in green
        local color = COLOR_GREY
        if i == race_data.best_lap_num then
            color = COLOR_GREEN
            lap_text = lap_text .. " BEST"
        end

        local lap_x = centerTextX(lap_text)
        renderer.drawText(lap_x, lap_y, lap_text,
                          color[1], color[2], color[3], 1, true)
        lap_y = lap_y + 12
    end

    -- "Press to return" at bottom (input-aware)
    local return_text = controls.get_prompt_bracketed("quit_to_menu") .. " RETURN TO MENU"
    local return_x = centerTextX(return_text)
    renderer.drawText(return_x, screen_h - 30, return_text,
                      COLOR_CYAN[1], COLOR_CYAN[2], COLOR_CYAN[3], 1, true)
end

-- Draw thruster indicator
-- Projects thruster positions to screen space and draws key/direction labels on top
function HUD.draw_thruster_indicator(ship)
    if not ship or not ship.thrusters or not ship.engine_positions then return end
    if not renderer.worldToScreen then return end  -- Need projection function
    if not ship.orientation then return end  -- Need ship orientation for rotation
    if ship:is_destroyed() then return end  -- Hide when ship is destroyed

    -- Get thruster labels from controls module (keyboard: WASD, gamepad: arrows)
    -- Thruster mapping: 1=Right(D), 2=Left(A), 3=Front(W), 4=Back(S)
    local thruster_keys = {"D", "A", "W", "S"}  -- Default fallback
    -- Map thruster index to label: 1->D(4), 2->A(2), 3->W(1), 4->S(3)
    for i = 1, 4 do
        local label = controls.get_thruster_label(i)
        if label then
            thruster_keys[i] = label
        end
    end
    local scale = ship.model_scale

    -- Build the same model matrix as Ship:draw uses
    -- Order: Translation * Rotation * Scale (applied right to left to points)
    local rotationMatrix = quat.toMatrix(ship.orientation)
    local modelMatrix = mat4.multiply(rotationMatrix, mat4.scale(scale, scale, scale))
    modelMatrix = mat4.multiply(mat4.translation(ship.x, ship.y, ship.z), modelMatrix)

    local y_offset = config.THRUSTER_LABEL_Y_OFFSET or 2

    for i, engine in ipairs(ship.engine_positions) do
        -- Engine position with Y offset to appear above thruster
        local local_x = engine.x
        local local_y = engine.y + y_offset
        local local_z = engine.z

        -- Transform by model matrix (same as ship vertices)
        local world_pos = mat4.multiplyVec4(modelMatrix, {local_x, local_y, local_z, 1})
        local world_x = world_pos[1]
        local world_y = world_pos[2]
        local world_z = world_pos[3]

        -- Project to screen using full MVP like the shader does
        -- The shader sends identity modelMatrix, so we just need view * proj
        local screen_x, screen_y, visible = renderer.worldToScreen(world_x, world_y, world_z)

        if visible and screen_x and screen_y then
            local thruster = ship.thrusters[i]
            local is_active = thruster and thruster.active
            local key = thruster_keys[i]

            -- Center the letter on the projected position
            local text_x = math.floor(screen_x - 2)
            local text_y = math.floor(screen_y - 3)

            -- Draw drop shadow (black, offset by 1 pixel)
            renderer.drawText(text_x + 1, text_y + 1, key,
                              COLOR_BLACK[1], COLOR_BLACK[2], COLOR_BLACK[3], 1, false)

            -- Determine color: yellow if both RT/Space AND LS/individual active, red if just active, white if inactive
            local text_color = COLOR_WHITE
            if is_active then
                -- Check if both all-thrusters (RT/Space) and individual input are active
                -- When both active, flame_power > power (individual adds 0.2 visual boost)
                local both_active = thruster.flame_power and thruster.power and
                                    thruster.flame_power > thruster.power and thruster.power > 0
                text_color = both_active and COLOR_YELLOW or COLOR_RED
            end
            renderer.drawText(text_x, text_y, key,
                              text_color[1], text_color[2], text_color[3], 1, false)
        end
    end
end

-- Main draw function - draws all HUD elements to software renderer
function HUD.draw(ship, camera, opts)
    if not renderer then
        print("HUD: renderer not initialized!")
        return
    end

    opts = opts or {}

    -- Draw mission panel (top-left) - skip during active race (race HUD replaces it)
    local in_active_race = opts.race_data and not opts.race_data.complete and not opts.race_data.failed
    if not in_active_race then
        HUD.draw_mission_panel(opts.mission)
    end

    -- Draw hull bar
    HUD.draw_hull_bar(ship)

    -- Draw compass with altimeter
    HUD.draw_compass(ship, camera, opts.mission_target)

    -- Draw control hints
    HUD.draw_controls(opts.game_mode)

    -- Draw location name (landing pad or building rooftop)
    if opts.current_location then
        HUD.draw_location_name(opts.current_location.name, opts.current_location.type)
    end

    -- Draw repair indicator
    HUD.draw_repair_indicator(opts.is_repairing)

    -- Draw race HUD (timer bar, lap counter)
    if opts.race_data then
        HUD.draw_race_hud(opts.race_data)
    end

    -- Draw countdown for non-race missions (3-2-1-GO!)
    if opts.countdown_data and not opts.race_data then
        HUD.draw_countdown(opts.countdown_data)
    end

    -- Draw thruster indicator (WASD keys showing which thrusters are firing)
    -- Skip when paused or during victory sequence
    if not show_pause_menu and not opts.victory_mode then
        HUD.draw_thruster_indicator(ship)
    end

    -- Draw camera mode indicator (bottom right, above target hint)
    if opts.camera_mode and not show_pause_menu then
        HUD.draw_camera_mode(opts.camera_mode)
    end

    -- Draw altitude warning (big flashing countdown in center of screen)
    if opts.altitude_warning and opts.altitude_timer then
        HUD.draw_altitude_warning(opts.altitude_timer)
    end

    -- Store mission for pause menu and draw pause menu on top of everything
    pause_menu_mission = opts.mission
    HUD.draw_pause_menu()
end

-- Draw camera mode indicator
function HUD.draw_camera_mode(mode)
    local screen_w = config.RENDER_WIDTH
    local screen_h = config.RENDER_HEIGHT

    -- Use controls module for input-aware prompt
    local mode_text = controls.get_camera_mode_prompt(mode)
    if not mode_text or mode_text == "" then
        mode_text = "[F] CAM: " .. string.upper(mode)
    end
    local text_x = screen_w - getTextWidth(mode_text) - 10
    local text_y = screen_h - 45

    -- Color based on mode
    local color = COLOR_GREY
    if mode == "follow" then
        color = COLOR_GREEN
    elseif mode == "free" then
        color = COLOR_CYAN
    elseif mode == "focus" then
        color = COLOR_YELLOW
    end

    renderer.drawText(text_x, text_y, mode_text, color[1], color[2], color[3], 1, true)
end

-- Draw altitude warning - big flashing countdown when over altitude limit
function HUD.draw_altitude_warning(timer)
    local screen_w = config.RENDER_WIDTH
    local screen_h = config.RENDER_HEIGHT

    -- Get countdown number (ceiling so 4.1 shows as 5)
    local countdown = math.ceil(timer)
    if countdown < 1 then countdown = 1 end

    -- Flash effect - alternate between red and yellow
    local flash = (love.timer.getTime() * 8) % 1 < 0.5
    local color = flash and {255, 50, 50} or {255, 200, 0}

    -- Draw warning text
    local warning_text = "ALTITUDE WARNING"
    local warning_width = getTextWidth(warning_text, 1)
    local warning_x = centerTextX(warning_text, 1)
    local warning_y = screen_h / 2 - 40

    renderer.drawText(warning_x, warning_y, warning_text, color[1], color[2], color[3], 1, true)

    -- Draw big countdown number (scale 3x)
    local num_text = tostring(countdown)
    local num_width = getTextWidth(num_text, 3)
    local num_x = math.floor((screen_w - num_width) / 2)
    local num_y = screen_h / 2 - 10

    renderer.drawText(num_x, num_y, num_text, color[1], color[2], color[3], 3, true)

    -- Draw instruction
    local instruction = "REDUCE ALTITUDE!"
    local inst_x = centerTextX(instruction, 1)
    local inst_y = screen_h / 2 + 30

    renderer.drawText(inst_x, inst_y, instruction, color[1], color[2], color[3], 1, true)
end

-- Targeting system state
local current_target_index = 0
local current_target = nil
local last_target_press_time = 0
local TARGET_CYCLE_WINDOW = 2.0  -- Seconds to cycle to next closest

-- Helper: sort enemies by distance to ship
local function sort_enemies_by_distance(enemies, ship_x, ship_z)
    local sorted = {}
    for i, enemy in ipairs(enemies) do
        local dx = enemy.x - ship_x
        local dz = enemy.z - ship_z
        local dist = math.sqrt(dx * dx + dz * dz)
        table.insert(sorted, {enemy = enemy, dist = dist, original_index = i})
    end
    table.sort(sorted, function(a, b) return a.dist < b.dist end)
    return sorted
end

-- Helper: find closest enemy
local function find_closest_enemy(enemies, ship_x, ship_z)
    if not enemies or #enemies == 0 then return nil end

    local closest = nil
    local closest_dist = math.huge

    for _, enemy in ipairs(enemies) do
        local dx = enemy.x - ship_x
        local dz = enemy.z - ship_z
        local dist = math.sqrt(dx * dx + dz * dz)
        if dist < closest_dist then
            closest_dist = dist
            closest = enemy
        end
    end

    return closest
end

-- Cycle to next target - selects closest first, then cycles by distance
function HUD.cycle_target(enemies, ship_x, ship_z)
    if not enemies or #enemies == 0 then
        current_target_index = 0
        current_target = nil
        return nil
    end

    local current_time = love.timer.getTime()
    local time_since_last = current_time - last_target_press_time
    last_target_press_time = current_time

    -- Sort enemies by distance
    local sorted = sort_enemies_by_distance(enemies, ship_x, ship_z)

    -- If no target or pressed after cycle window, select closest
    if not current_target or time_since_last > TARGET_CYCLE_WINDOW then
        current_target = sorted[1].enemy
        current_target_index = 1
        return current_target
    end

    -- Find current target's position in sorted list
    local current_sorted_index = 1
    for i, entry in ipairs(sorted) do
        if entry.enemy == current_target then
            current_sorted_index = i
            break
        end
    end

    -- Cycle to next closest
    current_sorted_index = current_sorted_index + 1
    if current_sorted_index > #sorted then
        current_sorted_index = 1
    end

    current_target = sorted[current_sorted_index].enemy
    current_target_index = current_sorted_index
    return current_target
end

-- Get current target
function HUD.get_target()
    return current_target
end

-- Set target directly (e.g., from turret auto-acquire)
function HUD.set_target(target)
    current_target = target
end

-- Reset targeting
function HUD.reset_targeting()
    current_target_index = 0
    current_target = nil
end

-- Validate current target against active enemies list
-- If target is no longer in the list, select closest enemy
function HUD.validate_target(enemies, ship_x, ship_z)
    if not current_target then return end

    -- Check if current target is still in the enemies list
    local target_valid = false

    for _, enemy in ipairs(enemies) do
        if enemy == current_target then
            target_valid = true
            break
        end
    end

    if not target_valid then
        -- Target destroyed - select closest enemy
        if #enemies > 0 and ship_x and ship_z then
            current_target = find_closest_enemy(enemies, ship_x, ship_z)
            -- Update index to match
            for i, enemy in ipairs(enemies) do
                if enemy == current_target then
                    current_target_index = i
                    break
                end
            end
        else
            -- No enemies left or no ship position
            current_target_index = 0
            current_target = nil
        end
    end

    return current_target
end

-- Draw target bracket (4 corner brackets around target) in 3D space
-- Called from flight_scene after 3D rendering
function HUD.draw_target_bracket_3d(target, cam, projMatrix, viewMatrix)
    if not target or not renderer then return end

    local target_x = target.x
    local target_y = target.y or 0  -- Center on target
    local target_z = target.z

    -- Transform through view matrix (world to view space)
    local view = mat4.multiplyVec4(viewMatrix, {target_x, target_y, target_z, 1})

    -- Transform through projection matrix (view to clip space)
    local clip = mat4.multiplyVec4(projMatrix, {view[1], view[2], view[3], view[4]})

    -- Behind camera check
    if clip[4] <= 0 then return end

    -- Perspective divide to NDC
    local ndc_x = clip[1] / clip[4]
    local ndc_y = clip[2] / clip[4]

    -- NDC to screen space
    local screen_x = (ndc_x + 1) * 0.5 * config.RENDER_WIDTH
    local screen_y = (1 - ndc_y) * 0.5 * config.RENDER_HEIGHT  -- Flip Y

    -- Calculate bracket size based on distance (smaller when far)
    local dist = math.sqrt(view[1]*view[1] + view[2]*view[2] + view[3]*view[3])
    local base_size = 30
    local bracket_size = math.max(15, math.min(50, base_size * 3 / dist))
    local bracket_length = bracket_size * 0.4
    local half_size = bracket_size

    -- Pulsing effect
    local time = love.timer.getTime()
    local pulse = 0.8 + 0.2 * math.sin(time * 6)
    local g = math.floor(255 * pulse)
    local r = math.floor(100 * pulse)
    local b = math.floor(50 * pulse)

    -- Draw 4 corner brackets (green)
    -- Top-left corner
    renderer.drawLine2D(screen_x - half_size, screen_y - half_size,
                      screen_x - half_size + bracket_length, screen_y - half_size, r, g, b)
    renderer.drawLine2D(screen_x - half_size, screen_y - half_size,
                      screen_x - half_size, screen_y - half_size + bracket_length, r, g, b)

    -- Top-right corner
    renderer.drawLine2D(screen_x + half_size, screen_y - half_size,
                      screen_x + half_size - bracket_length, screen_y - half_size, r, g, b)
    renderer.drawLine2D(screen_x + half_size, screen_y - half_size,
                      screen_x + half_size, screen_y - half_size + bracket_length, r, g, b)

    -- Bottom-left corner
    renderer.drawLine2D(screen_x - half_size, screen_y + half_size,
                      screen_x - half_size + bracket_length, screen_y + half_size, r, g, b)
    renderer.drawLine2D(screen_x - half_size, screen_y + half_size,
                      screen_x - half_size, screen_y + half_size - bracket_length, r, g, b)

    -- Bottom-right corner
    renderer.drawLine2D(screen_x + half_size, screen_y + half_size,
                      screen_x + half_size - bracket_length, screen_y + half_size, r, g, b)
    renderer.drawLine2D(screen_x + half_size, screen_y + half_size,
                      screen_x + half_size, screen_y + half_size - bracket_length, r, g, b)
end

-- Draw combat HUD (target indicator, enemy health bar)
function HUD.draw_combat_hud(enemies, mother_ship)
    local screen_w = config.RENDER_WIDTH
    local screen_h = config.RENDER_HEIGHT

    -- Draw mothership health bar if present
    if mother_ship then
        local bar_width = 200
        local bar_height = 16
        local bar_x = (screen_w - bar_width) / 2
        local bar_y = 30

        local health_percent = mother_ship.health / mother_ship.max_health
        health_percent = math.max(0, math.min(1, health_percent))

        -- Health bar color
        local health_color = COLOR_RED
        if health_percent > 0.5 then
            health_color = COLOR_GREEN
        elseif health_percent > 0.25 then
            health_color = COLOR_ORANGE
        end

        -- Background
        renderer.drawRectFill(bar_x - 2, bar_y - 2, bar_x + bar_width + 2, bar_y + bar_height + 2,
                              COLOR_BLACK[1], COLOR_BLACK[2], COLOR_BLACK[3])

        -- Health fill
        local fill_width = bar_width * health_percent
        if fill_width > 0 then
            renderer.drawRectFill(bar_x, bar_y, bar_x + fill_width, bar_y + bar_height,
                                  health_color[1], health_color[2], health_color[3])
        end

        -- Border
        renderer.drawRect(bar_x, bar_y, bar_x + bar_width, bar_y + bar_height,
                          COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3])

        -- Label
        local label = "MOTHERSHIP"
        local label_x = centerTextX(label)
        renderer.drawText(label_x, bar_y + 3, label,
                          COLOR_BLACK[1], COLOR_BLACK[2], COLOR_BLACK[3], 1, false)
    end

    -- Draw target hint on right side (input-aware)
    local target_prompts = controls.get_prompts("target_cycle")
    local hint_text = target_prompts.keyboard or "[T] Target"
    if controls.is_gamepad() then
        hint_text = target_prompts.gamepad or hint_text
    end
    local hint_x = screen_w - getTextWidth(hint_text) - 10
    local hint_y = screen_h - 30
    renderer.drawText(hint_x, hint_y, hint_text,
                      COLOR_CYAN[1], COLOR_CYAN[2], COLOR_CYAN[3], 1, true)

end

-- Handle keypresses
function HUD.keypressed(key)
    if key == "c" then
        return HUD.toggle_controls()
    elseif key == "g" then
        return HUD.toggle_goal_box()
    elseif key == "tab" or key == "escape" then
        return HUD.toggle_pause()
    end
    return nil
end

return HUD
