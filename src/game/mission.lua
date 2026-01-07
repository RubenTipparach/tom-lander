-- Mission module: Mission scripting and objective tracking
-- Ported from Picotron version

local Cargo = require("cargo")
local Constants = require("constants")
local SaveData = require("save_data")
local config = require("config")

local Mission = {}

-- Reference to LandingPads module (set externally from flight_scene.lua)
Mission.LandingPads = nil

-- MISSION PARAMETERS

-- General mission settings
Mission.LANDING_PAD_RADIUS = 3  -- Landing pad radius in units
Mission.CARGO_DELIVERY_DELAY = 1.0  -- Time to wait on pad before cargo delivery (seconds)

-- Mission 1: Engine Test
Mission.M1_HOVER_DURATION = 5  -- How long to hover in seconds

-- Mission 2: Cargo Delivery
Mission.M2_CARGO_DISTANCE_X = -100  -- Cargo X offset from landing pad
Mission.M2_CARGO_DISTANCE_Z = 20     -- Cargo Z offset from landing pad
Mission.M2_CARGO_COUNT = 1          -- Number of cargo boxes

-- Mission 3: Scientific Mission
Mission.M3_BUILDING_ID = 10         -- Building ID for Command Tower
Mission.M3_LANDING_PAD_ID = 4       -- Landing Pad D
Mission.M3_CARGO_COUNT = 1          -- Number of scientist pods

-- Mission 4: Ocean Rescue
Mission.M4_CARGO_ASEPRITE_X = 105   -- Cargo pickup location
Mission.M4_CARGO_ASEPRITE_Z = 57    -- Cargo pickup location
Mission.M4_LANDING_PAD_ID = 2       -- Landing Pad B
Mission.M4_CARGO_COUNT = 1          -- Number of cargo boxes

-- Mission 5: Secret Weapon
Mission.M5_CARGO_ASEPRITE_X = 54    -- Cargo location
Mission.M5_CARGO_ASEPRITE_Z = 60    -- Cargo location
Mission.M5_LANDING_PAD_ID = 3       -- Landing Pad C
Mission.M5_CARGO_COUNT = 1          -- Number of cargo boxes

-- Mission state
Mission.current_objectives = {}
Mission.cargo_objects = {}
Mission.total_cargo = 0
Mission.collected_cargo = 0
Mission.active = false
Mission.complete_flag = false
Mission.landing_pad_pos = {x = 0, y = 0, z = 0}
Mission.required_landing_pad_id = nil
Mission.current_target = {x = 0, z = 0}  -- Current objective location (for compass)
Mission.show_pause_menu = false
Mission.cargo_just_delivered = false
Mission.type = nil  -- "hover", "cargo", etc.
Mission.hover_timer = 0
Mission.hover_duration = 0
Mission.mission_name = ""
Mission.current_mission_num = nil

-- Initialize a hover mission (take off, hover, land)
function Mission.start_hover_mission(hover_duration, landing_pad_x, landing_pad_z, landing_pad_id)
    Mission.active = true
    Mission.complete_flag = false
    Mission.type = "hover"
    Mission.hover_timer = 0
    Mission.hover_duration = hover_duration
    Mission.show_pause_menu = false

    -- Store landing pad position and ID
    Mission.landing_pad_pos.x = landing_pad_x
    Mission.landing_pad_pos.z = landing_pad_z
    Mission.required_landing_pad_id = landing_pad_id or 1

    -- Set target to landing pad
    Mission.current_target.x = landing_pad_x
    Mission.current_target.z = landing_pad_z

    -- Set objective text
    Mission.current_objectives = {
        "Take off and hover for " .. hover_duration .. " seconds",
        "Then land back on the pad",
        "",
        "[TAB] Menu  [C] Show Controls"
    }
end

-- Initialize a cargo mission
-- cargo_coords: array of {aseprite_x, aseprite_z, world_y (optional)}
function Mission.start_cargo_mission(cargo_coords, landing_pad_x, landing_pad_z, landing_pad_id)
    Mission.active = true
    Mission.complete_flag = false
    Mission.type = "cargo"
    Mission.cargo_objects = {}
    Mission.total_cargo = #cargo_coords
    Mission.collected_cargo = 0
    Mission.show_pause_menu = false

    -- Store landing pad position and ID
    Mission.landing_pad_pos.x = landing_pad_x or 0
    Mission.landing_pad_pos.z = landing_pad_z or 0
    Mission.required_landing_pad_id = landing_pad_id or 1

    -- Create cargo objects at specified coordinates
    local Heightmap = require("heightmap")
    for i, coord in ipairs(cargo_coords) do
        local world_x, world_z = Constants.aseprite_to_world(coord.aseprite_x, coord.aseprite_z)
        -- Determine base_y: use provided world_y or get from heightmap
        local base_y
        if coord.world_y then
            base_y = coord.world_y
        else
            base_y = Heightmap.get_height(world_x, world_z)
        end
        local cargo = Cargo.create({
            x = world_x,
            z = world_z,
            base_y = base_y,
            id = i
        })
        table.insert(Mission.cargo_objects, cargo)
    end

    -- Set initial target to first cargo location
    if Mission.cargo_objects[1] then
        Mission.current_target.x = Mission.cargo_objects[1].x
        Mission.current_target.z = Mission.cargo_objects[1].z
    else
        -- No cargo, point to landing pad
        Mission.current_target.x = landing_pad_x
        Mission.current_target.z = landing_pad_z
    end

    -- Get landing pad name
    local pad_name = Constants.LANDING_PAD_NAMES[landing_pad_id] or "Landing Pad"

    -- Set objective text
    Mission.current_objectives = {
        "Collect cargo and deliver to " .. pad_name,
        "Cargo: 0/" .. Mission.total_cargo,
        "Land with engines off to deliver",
        "[TAB] Menu  [C] Show Controls"
    }
end

-- Update mission state
function Mission.update(dt, ship, current_landing_pad)
    if not Mission.active then return end
    if Mission.complete_flag then return end

    local ship_x = ship.x
    local ship_y = ship.y
    local ship_z = ship.z
    -- Ship is landed if on a landing pad (current_landing_pad is non-nil)
    local ship_landed = current_landing_pad ~= nil
    local engines_off = not ship.thrusting

    -- Handle hover mission
    if Mission.type == "hover" then
        local is_on_pad = current_landing_pad ~= nil

        -- Count hover time only when NOT on the landing pad
        if not is_on_pad then
            Mission.hover_timer = Mission.hover_timer + dt
            local remaining = Mission.hover_duration - Mission.hover_timer
            if remaining > 0 then
                Mission.current_objectives[1] = "Hover for " .. math.floor(remaining + 1) .. " more seconds"
            else
                Mission.current_objectives[1] = "Land back on the pad to complete"
            end
        end

        -- Check if mission complete
        if Mission.hover_timer >= Mission.hover_duration and is_on_pad then
            Mission.complete()
        end
        return
    end

    -- Handle cargo mission
    for _, cargo in ipairs(Mission.cargo_objects) do
        -- Cargo.update takes: cargo, dt, ship_x, ship_y, ship_z, ship_orientation
        Cargo.update(cargo, dt, ship_x, ship_y, ship_z, ship.orientation)

        -- Count attached cargo
        if Cargo.is_attached(cargo) and not cargo.was_attached then
            cargo.was_attached = true
            Mission.collected_cargo = Mission.collected_cargo + 1
            Mission.current_objectives[2] = "Cargo: " .. Mission.collected_cargo .. "/" .. Mission.total_cargo

            -- Switch target to landing pad when cargo is picked up
            local target_pad = Mission.LandingPads.get_pad(Mission.required_landing_pad_id)
            if target_pad then
                Mission.current_target.x = target_pad.x
                Mission.current_target.z = target_pad.z
            end
        end

        -- Check if cargo delivered when landed on correct pad with engines off
        local on_correct_pad = current_landing_pad and current_landing_pad.id == Mission.required_landing_pad_id

        if cargo.state == "attached" and not cargo.was_delivered and ship_landed and engines_off and on_correct_pad then
            if not cargo.delivery_timer then
                cargo.delivery_timer = 0
            end

            cargo.delivery_timer = cargo.delivery_timer + dt

            if cargo.delivery_timer >= Mission.CARGO_DELIVERY_DELAY then
                cargo.state = "delivered"
                cargo.was_delivered = true
                Mission.cargo_just_delivered = true
            end
        else
            cargo.delivery_timer = nil
        end
    end

    -- Check if all cargo delivered
    if Mission.total_cargo > 0 then
        local all_delivered = true
        for _, cargo in ipairs(Mission.cargo_objects) do
            if cargo.state ~= "delivered" then
                all_delivered = false
                break
            end
        end

        if all_delivered and Mission.collected_cargo >= Mission.total_cargo then
            Mission.complete()
        end
    end
end

-- Complete the mission
function Mission.complete()
    Mission.complete_flag = true

    -- Mission-specific completion text
    local completion_text = "All cargo delivered!"
    if Mission.type == "hover" then
        completion_text = "Hover test complete!"
    elseif Mission.current_mission_num == 6 then
        completion_text = "All alien waves destroyed!"
    end

    Mission.current_objectives = {
        "MISSION COMPLETE!",
        completion_text,
        "",
        "[Q] Return to Menu"
    }

    -- Unlock next mission
    if Mission.current_mission_num and Mission.current_mission_num < 6 then
        local next_mission = Mission.current_mission_num + 1
        SaveData.unlock_mission(next_mission)
        print("Mission " .. Mission.current_mission_num .. " complete! Unlocked mission " .. next_mission)
    end
end

-- Reset mission
function Mission.reset()
    Mission.active = false
    Mission.cargo_objects = {}
    Mission.total_cargo = 0
    Mission.collected_cargo = 0
    Mission.current_objectives = {}
    Mission.complete_flag = false
    Mission.type = nil
    Mission.hover_timer = 0
    Mission.hover_duration = 0
    Mission.mission_name = ""
    Mission.cargo_just_delivered = false
    Mission.show_pause_menu = false
    Mission.current_mission_num = nil
end

-- Get mission data for HUD
function Mission.get_hud_data()
    return {
        name = Mission.mission_name,
        objectives = Mission.current_objectives
    }
end

-- Get current target for compass
function Mission.get_target()
    if not Mission.active then return nil end
    return Mission.current_target
end

-- Check if mission is complete
function Mission.is_complete()
    return Mission.complete_flag
end

-- Check if mission is active
function Mission.is_active()
    return Mission.active
end

-- Draw cargo objects
function Mission.draw_cargo(renderer, cam_x, cam_z)
    for _, cargo in ipairs(Mission.cargo_objects) do
        if cargo.state ~= "delivered" then
            Cargo.draw(cargo, renderer, cam_x, cam_z)
        end
    end
end

-- Draw 3D wireframe guide arrow pointing to objective
-- Arrow anchored to camera pivot and points toward target with pulsating effect
function Mission.draw_guide_arrow(renderer, cam_x, cam_y, cam_z)
    if not Mission.active or Mission.complete_flag then return end
    if not Mission.current_target then return end

    local target_x = Mission.current_target.x
    local target_z = Mission.current_target.z

    -- Calculate direction to target from camera pivot
    local dx = target_x - cam_x
    local dz = target_z - cam_z
    local dist = math.sqrt(dx * dx + dz * dz)

    -- Don't draw if very close to target
    if dist < config.GUIDE_ARROW_MIN_TARGET_DIST then return end

    -- Normalize direction (this points FROM camera TO target)
    local dir_x = dx / dist
    local dir_z = dz / dist

    -- Pulsating effect
    local time = love.timer.getTime()
    local pulse_range = config.GUIDE_ARROW_PULSE_MAX - config.GUIDE_ARROW_PULSE_MIN
    local pulse = config.GUIDE_ARROW_PULSE_MIN + pulse_range * (0.5 + 0.5 * math.sin(time * config.GUIDE_ARROW_PULSE_SPEED))

    -- Arrow parameters with pulse
    local arrow_height = cam_y + config.GUIDE_ARROW_Y_OFFSET
    local arrow_length = config.GUIDE_ARROW_LENGTH * pulse
    local arrow_width = config.GUIDE_ARROW_WIDTH * pulse
    local skip_depth = not config.GUIDE_ARROW_DEPTH_TEST

    -- Arrow center position (in front of camera pivot toward target)
    local center_x = cam_x + dir_x * config.GUIDE_ARROW_DISTANCE
    local center_z = cam_z + dir_z * config.GUIDE_ARROW_DISTANCE

    -- Perpendicular direction for arrow width
    local perp_x = -dir_z
    local perp_z = dir_x

    -- Arrow tip (front, pointing toward target)
    local tip_x = center_x + dir_x * arrow_length
    local tip_z = center_z + dir_z * arrow_length

    -- Arrow back (opposite of tip)
    local back_x = center_x - dir_x * (arrow_length * 0.3)
    local back_z = center_z - dir_z * (arrow_length * 0.3)

    -- Wing points (at the back, spread out)
    local wing_left_x = back_x + perp_x * arrow_width
    local wing_left_z = back_z + perp_z * arrow_width
    local wing_right_x = back_x - perp_x * arrow_width
    local wing_right_z = back_z - perp_z * arrow_width

    -- Pulsating color
    local brightness = 0.7 + 0.3 * math.sin(time * config.GUIDE_ARROW_COLOR_SPEED)
    local r = math.floor(config.GUIDE_ARROW_COLOR_R * brightness)
    local g = math.floor(config.GUIDE_ARROW_COLOR_G * brightness)
    local b = math.floor(config.GUIDE_ARROW_COLOR_B * brightness)

    -- Draw chevron/arrow shape (simple triangle pointing toward target)
    -- Tip to left wing
    renderer.drawLine3D(
        {tip_x, arrow_height, tip_z},
        {wing_left_x, arrow_height, wing_left_z},
        r, g, b, skip_depth
    )
    -- Tip to right wing
    renderer.drawLine3D(
        {tip_x, arrow_height, tip_z},
        {wing_right_x, arrow_height, wing_right_z},
        r, g, b, skip_depth
    )
    -- Left wing to back center
    renderer.drawLine3D(
        {wing_left_x, arrow_height, wing_left_z},
        {center_x, arrow_height, center_z},
        r, g, b, skip_depth
    )
    -- Right wing to back center
    renderer.drawLine3D(
        {wing_right_x, arrow_height, wing_right_z},
        {center_x, arrow_height, center_z},
        r, g, b, skip_depth
    )

    -- Draw a second layer slightly above for 3D effect
    local h2 = arrow_height + config.GUIDE_ARROW_HEIGHT
    -- Tip to left wing
    renderer.drawLine3D(
        {tip_x, h2, tip_z},
        {wing_left_x, h2, wing_left_z},
        r, g, b, skip_depth
    )
    -- Tip to right wing
    renderer.drawLine3D(
        {tip_x, h2, tip_z},
        {wing_right_x, h2, wing_right_z},
        r, g, b, skip_depth
    )
    -- Left wing to back center
    renderer.drawLine3D(
        {wing_left_x, h2, wing_left_z},
        {center_x, h2, center_z},
        r, g, b, skip_depth
    )
    -- Right wing to back center
    renderer.drawLine3D(
        {wing_right_x, h2, wing_right_z},
        {center_x, h2, center_z},
        r, g, b, skip_depth
    )

    -- Vertical connectors
    renderer.drawLine3D(
        {tip_x, arrow_height, tip_z},
        {tip_x, h2, tip_z},
        r, g, b, skip_depth
    )
    renderer.drawLine3D(
        {wing_left_x, arrow_height, wing_left_z},
        {wing_left_x, h2, wing_left_z},
        r, g, b, skip_depth
    )
    renderer.drawLine3D(
        {wing_right_x, arrow_height, wing_right_z},
        {wing_right_x, h2, wing_right_z},
        r, g, b, skip_depth
    )
    renderer.drawLine3D(
        {center_x, arrow_height, center_z},
        {center_x, h2, center_z},
        r, g, b, skip_depth
    )
end

return Mission
