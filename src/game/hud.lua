-- HUD Module
-- Displays hull bar, compass, altimeter, control hints, and mission panel
-- Renders directly to software renderer buffer for consistent pixel art look

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

-- Pause menu state
local show_pause_menu = false

-- Renderer reference (set via init)
local renderer = nil

-- Initialize with renderer reference
function HUD.init(r)
    renderer = r
end

-- Set current mission number (affects control hints visibility)
function HUD.set_mission(mission_num)
    current_mission = mission_num
end

-- Toggle control hints
function HUD.toggle_controls()
    show_controls = not show_controls
    return show_controls
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
                      "HULL: " .. math.floor(math.max(0, health)) .. "%",
                      COLOR_BLACK[1], COLOR_BLACK[2], COLOR_BLACK[3], 1, false)
end

-- Draw 3D compass with altitude
function HUD.draw_compass(ship, camera, mission_target)
    -- Black box background for compass and altitude
    local box_width = 100
    local box_height = 22
    local box_x1 = COMPASS_X - box_width / 2 + 20
    local box_x2 = COMPASS_X + box_width / 2 + 20
    local box_y1 = COMPASS_Y - box_height / 2
    local box_y2 = COMPASS_Y + box_height / 2

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
            x = COMPASS_X + x_yaw,
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

    -- Add mission target arrow if provided (orange)
    if mission_target then
        local dx = mission_target.x - ship.x
        local dz = mission_target.z - ship.z

        local mag = math.sqrt(dx*dx + dz*dz)
        if mag > 0.01 then
            local target_point = {x = (-dx / mag) * COMPASS_SIZE, y = 0, z = (-dz / mag) * COMPASS_SIZE}

            -- Transform by camera rotation
            local x_yaw = target_point.x * cos_yaw - target_point.z * sin_yaw
            local z_yaw = target_point.x * sin_yaw + target_point.z * cos_yaw
            local y_pitch = target_point.y * cos_pitch - z_yaw * sin_pitch
            local z_pitch = target_point.y * sin_pitch + z_yaw * cos_pitch

            table.insert(arrows, {
                screen_x = COMPASS_X + x_yaw,
                screen_y = COMPASS_Y + y_pitch,
                color = COLOR_ORANGE,
                z = z_pitch,
                is_target = true
            })
        end
    end

    -- Sort arrows by depth (back to front, furthest first)
    table.sort(arrows, function(a, b) return a.z < b.z end)

    -- Draw arrows in sorted order (back to front)
    for _, arrow in ipairs(arrows) do
        if arrow.is_target then
            -- Draw target arrow (orange)
            renderer.drawLine2D(COMPASS_X, COMPASS_Y, arrow.screen_x, arrow.screen_y,
                               arrow.color[1], arrow.color[2], arrow.color[3])
            renderer.drawCircleFill(arrow.screen_x, arrow.screen_y, 2,
                                    arrow.color[1], arrow.color[2], arrow.color[3])
        else
            -- Draw compass direction arrows
            local p1 = projected_points[arrow.from]
            local p2 = projected_points[arrow.to]
            renderer.drawLine2D(p1.x, p1.y, p2.x, p2.y,
                               arrow.color[1], arrow.color[2], arrow.color[3])
            renderer.drawCircleFill(p2.x, p2.y, 1,
                                    arrow.color[1], arrow.color[2], arrow.color[3])
        end
    end

    -- Center dot (drawn last, always on top)
    renderer.drawCircleFill(COMPASS_X, COMPASS_Y, 2,
                            COLOR_BLACK[1], COLOR_BLACK[2], COLOR_BLACK[3])
    renderer.drawCircle(COMPASS_X, COMPASS_Y, 2,
                        COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3])

    -- Altitude counter (1 world unit = 10 meters)
    local altitude_meters = (ship.y or 0) * 10
    renderer.drawText(COMPASS_X + 20, COMPASS_Y - 3,
                      "ALT: " .. math.floor(altitude_meters) .. "m",
                      COLOR_CYAN[1], COLOR_CYAN[2], COLOR_CYAN[3], 1, true)
end

-- Draw control hints
function HUD.draw_controls(game_mode)
    -- Only show if enabled or in mission 1
    if not show_controls and current_mission ~= 1 then
        return
    end

    local hint_x, hint_y = CONTROL_HINT_X, CONTROL_HINT_Y

    -- Title
    renderer.drawText(hint_x, hint_y, "CONTROLS:",
                      COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3], 1, true)
    hint_y = hint_y + 8

    -- Arcade mode controls (default)
    if game_mode ~= "simulation" then
        renderer.drawText(hint_x, hint_y, "Space: All thrusters",
                          COLOR_GREY[1], COLOR_GREY[2], COLOR_GREY[3], 1, true)
        hint_y = hint_y + 7
        renderer.drawText(hint_x, hint_y, "N:     Left+Right",
                          COLOR_GREY[1], COLOR_GREY[2], COLOR_GREY[3], 1, true)
        hint_y = hint_y + 7
        renderer.drawText(hint_x, hint_y, "M:     Front+Back",
                          COLOR_GREY[1], COLOR_GREY[2], COLOR_GREY[3], 1, true)
        hint_y = hint_y + 7
        renderer.drawText(hint_x, hint_y, "Shift: Auto-level",
                          COLOR_GREY[1], COLOR_GREY[2], COLOR_GREY[3], 1, true)
    else
        renderer.drawText(hint_x, hint_y, "W/A/S/D: Thrusters",
                          COLOR_GREY[1], COLOR_GREY[2], COLOR_GREY[3], 1, true)
        hint_y = hint_y + 7
        renderer.drawText(hint_x, hint_y, "Manual flight!",
                          COLOR_GREY[1], COLOR_GREY[2], COLOR_GREY[3], 1, true)
    end

    hint_y = hint_y + 10

    -- Camera controls
    renderer.drawText(hint_x, hint_y, "CAMERA:",
                      COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3], 1, true)
    hint_y = hint_y + 8
    renderer.drawText(hint_x, hint_y, "Mouse: Drag to rotate",
                      COLOR_GREY[1], COLOR_GREY[2], COLOR_GREY[3], 1, true)
    hint_y = hint_y + 7
    renderer.drawText(hint_x, hint_y, "Arrows: Rotate camera",
                      COLOR_GREY[1], COLOR_GREY[2], COLOR_GREY[3], 1, true)
end

-- Draw mission panel (top-left objectives box)
function HUD.draw_mission_panel(mission)
    -- mission should have: name, objectives (array of strings)
    if not mission then
        -- Draw placeholder when no mission
        mission = {
            name = "FREE FLIGHT",
            objectives = {
                "Explore the terrain",
                "Practice landing on pads",
                "[ESC] Return to menu"
            }
        }
    end

    local objectives = mission.objectives or {}
    local line_height = 8

    -- Calculate box height based on content
    local box_height = 8  -- Top padding
    if mission.name and mission.name ~= "" then
        box_height = box_height + 10  -- Mission name + spacing
    end
    box_height = box_height + #objectives * line_height + 4  -- Objectives + bottom padding

    -- Draw semi-transparent background
    renderer.drawRectFill(MISSION_BOX_X, MISSION_BOX_Y,
                          MISSION_BOX_X + MISSION_BOX_WIDTH, MISSION_BOX_Y + box_height,
                          COLOR_DARK_BLUE[1], COLOR_DARK_BLUE[2], COLOR_DARK_BLUE[3], 200)

    -- Draw border
    renderer.drawRect(MISSION_BOX_X, MISSION_BOX_Y,
                      MISSION_BOX_X + MISSION_BOX_WIDTH, MISSION_BOX_Y + box_height,
                      COLOR_GREY[1], COLOR_GREY[2], COLOR_GREY[3])

    -- Draw mission name header
    local text_y = MISSION_BOX_Y + 4
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
end

-- Draw pause menu (centered overlay)
function HUD.draw_pause_menu()
    if not show_pause_menu then return end

    local screen_w = 480
    local screen_h = 270
    local box_width = 180
    local box_height = 70
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
    local title_x = box_x + (box_width - #title * 5) / 2
    renderer.drawText(title_x, box_y + 10, title,
                      COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3], 1, true)

    -- Options
    local option1 = "[Tab] Resume"
    local option1_x = box_x + (box_width - #option1 * 5) / 2
    renderer.drawText(option1_x, box_y + 30, option1,
                      COLOR_GREY[1], COLOR_GREY[2], COLOR_GREY[3], 1, true)

    local option2 = "[Q] Return to Menu"
    local option2_x = box_x + (box_width - #option2 * 5) / 2
    renderer.drawText(option2_x, box_y + 45, option2,
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

    local text_x = 240 - (#text * 5) / 2  -- Center horizontally
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

-- Main draw function - draws all HUD elements to software renderer
function HUD.draw(ship, camera, opts)
    if not renderer then
        print("HUD: renderer not initialized!")
        return
    end

    opts = opts or {}

    -- Draw mission panel (top-left)
    HUD.draw_mission_panel(opts.mission)

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

    -- Draw pause menu on top of everything
    HUD.draw_pause_menu()
end

-- Handle keypresses
function HUD.keypressed(key)
    if key == "c" then
        return HUD.toggle_controls()
    elseif key == "tab" or key == "escape" then
        return HUD.toggle_pause()
    end
    return nil
end

return HUD
