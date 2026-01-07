-- Weather System: Rain, wind, and lightning effects
-- Ported from Picotron version

local config = require("config")

local Weather = {}

-- State
Weather.enabled = false
Weather.initialized = false

-- Rain particles
Weather.rain_particles = {}
-- Note: These are read fresh from config in init() to ensure config is loaded
Weather.RAIN_STREAK_SCALE = 2.0
Weather.RAIN_SHIP_MOTION_FACTOR = 100.0  -- Scale ship velocity to match rain fall speed (~50)
Weather.RAIN_WIND_MOTION_FACTOR = 2.0

-- Wind
Weather.wind_vx = 0
Weather.wind_vz = 0
Weather.wind_direction_x = 1
Weather.wind_direction_z = 0
Weather.wind_timer = 0
Weather.wind_change_interval = 15  -- Seconds between wind direction changes

-- Wind strength by altitude
Weather.WIND_LIGHT = 0.03   -- 0-10 units altitude
Weather.WIND_MEDIUM = 0.08  -- 10-20 units altitude
Weather.WIND_HEAVY = 0.15   -- 20+ units altitude

-- Lightning
Weather.lightning_timer = 0
Weather.lightning_interval = 15  -- Seconds between lightning
Weather.lightning_flash_active = false
Weather.lightning_flash_count = 0
Weather.lightning_flash_timer = 0
Weather.LIGHTNING_FLASH_DURATION = 0.1
Weather.LIGHTNING_FLASH_GAP = 0.2
Weather.LIGHTNING_FLASHES_PER_EVENT = 3

-- Fog settings (narrower during weather)
Weather.FOG_START_DISTANCE = 8    -- Where fog begins during weather
Weather.FOG_MAX_DISTANCE = 12     -- Max visibility during weather
Weather.RENDER_DISTANCE = 12      -- Reduced render distance during weather

-- Rain colors (by depth, matching Picotron palette indices 1, 16, 12, 28)
-- Farthest to closest: dark blue -> medium blue -> light blue -> cyan
Weather.RAIN_COLORS = {
    {29, 43, 83},     -- Farthest: dark blue (palette 1)
    {28, 94, 172},    -- Far: medium blue (palette 16)
    {41, 173, 255},   -- Medium: light blue (palette 12)
    {100, 223, 246},  -- Closest: cyan (palette 28)
}

-- Enable/disable weather
function Weather.set_enabled(enabled)
    Weather.enabled = enabled
    if not enabled then
        Weather.initialized = false
        Weather.rain_particles = {}
    end
end

-- Calculate optimal rain count for continuous coverage
-- Returns the number of particles needed for a given density
function Weather.calculate_rain_count()
    local rain_spread = config.WEATHER_RAIN_SPREAD
    local rain_max_y = config.WEATHER_RAIN_MAX_Y
    local rain_despawn_below = config.WEATHER_RAIN_DESPAWN_BELOW
    local rain_fall_speed = math.abs(config.WEATHER_RAIN_FALL_SPEED)

    -- Full vertical range rain must cover
    local rain_full_range = rain_max_y - rain_despawn_below

    -- Horizontal area covered
    local area = rain_spread * rain_spread

    -- Time for a particle to fall through the full range
    local fall_time = rain_full_range / rain_fall_speed

    -- For continuous rain, we want particles evenly distributed
    -- Target: ~1 particle per 10 square units per vertical "layer"
    -- This is a tunable density factor
    local density = 0.1  -- particles per square unit per second of fall time

    local calculated_count = math.floor(area * density * fall_time)

    print(string.format("Weather: Calculated rain count = %d (area=%.0f, fall_time=%.1fs)",
        calculated_count, area, fall_time))

    return calculated_count
end

-- Initialize weather (spawn rain particles)
-- cam_x, cam_y, cam_z: camera position to spawn rain around
function Weather.init(cam_x, cam_y, cam_z)
    if Weather.initialized then return end

    -- Read config values (no defaults - config must define these)
    local rain_count = config.WEATHER_RAIN_COUNT
    local rain_spread = config.WEATHER_RAIN_SPREAD
    local rain_max_y = config.WEATHER_RAIN_MAX_Y
    local rain_despawn_below = config.WEATHER_RAIN_DESPAWN_BELOW

    -- Full vertical range for continuous distribution
    local rain_full_range = rain_max_y - rain_despawn_below

    -- Default camera position if not provided
    cam_x = cam_x or 0
    cam_y = cam_y or 0
    cam_z = cam_z or 0

    Weather.rain_particles = {}

    -- Spawn rain particles distributed around camera position
    -- Distribute across FULL vertical range (not just spawn range) for continuous rain
    for i = 1, rain_count do
        table.insert(Weather.rain_particles, {
            x = cam_x + (math.random() - 0.5) * rain_spread,
            y = cam_y + rain_despawn_below + math.random() * rain_full_range,
            z = cam_z + (math.random() - 0.5) * rain_spread,
        })
    end

    -- Initialize wind
    Weather.wind_timer = 0
    Weather.change_wind_direction()

    -- Initialize lightning
    Weather.lightning_timer = 0
    Weather.lightning_flash_active = false
    Weather.lightning_interval = 10 + math.random() * 10

    Weather.initialized = true
    print("Weather: Initialized with " .. rain_count .. " rain particles (full range: " .. rain_full_range .. " units)")
end

-- Change wind direction randomly
function Weather.change_wind_direction()
    local angle = math.random() * math.pi * 2
    Weather.wind_direction_x = math.cos(angle)
    Weather.wind_direction_z = math.sin(angle)
    Weather.wind_change_interval = 10 + math.random() * 10
    Weather.wind_timer = 0
end

-- Get wind strength based on altitude
function Weather.get_wind_strength(altitude)
    if altitude < 10 then
        return Weather.WIND_LIGHT
    elseif altitude < 20 then
        return Weather.WIND_MEDIUM
    else
        return Weather.WIND_HEAVY
    end
end

-- Apply wind to ship
function Weather.apply_wind(ship, ship_y, is_landed)
    if not Weather.enabled or is_landed then return end

    local strength = Weather.get_wind_strength(ship_y)
    Weather.wind_vx = Weather.wind_direction_x * strength
    Weather.wind_vz = Weather.wind_direction_z * strength

    -- Apply wind velocity to ship
    ship.vx = ship.vx + Weather.wind_vx * 0.016  -- ~60fps
    ship.vz = ship.vz + Weather.wind_vz * 0.016
end

-- Update weather systems
function Weather.update(dt, cam_x, cam_y, cam_z, ship_vx, ship_vy, ship_vz)
    if not Weather.enabled then return end
    if not Weather.initialized then Weather.init(cam_x, cam_y, cam_z) end

    -- Read config values (no defaults)
    local rain_fall_speed = config.WEATHER_RAIN_FALL_SPEED
    local rain_spread = config.WEATHER_RAIN_SPREAD
    local rain_max_y = config.WEATHER_RAIN_MAX_Y
    local rain_despawn_below = config.WEATHER_RAIN_DESPAWN_BELOW

    -- Update wind timer
    Weather.wind_timer = Weather.wind_timer + dt
    if Weather.wind_timer >= Weather.wind_change_interval then
        Weather.change_wind_direction()
    end

    -- Update lightning
    Weather.update_lightning(dt)

    -- Calculate full visible rain range (from max spawn height to despawn depth)
    local rain_full_range = rain_max_y - rain_despawn_below

    -- Update rain particles
    for _, p in ipairs(Weather.rain_particles) do
        -- Apply rain fall speed (in world space, always down)
        p.y = p.y + rain_fall_speed * dt

        -- Apply wind to rain (horizontal drift)
        p.x = p.x + Weather.wind_vx * Weather.RAIN_WIND_MOTION_FACTOR * dt
        p.z = p.z + Weather.wind_vz * Weather.RAIN_WIND_MOTION_FACTOR * dt

        -- Respawn if fallen too far below camera (relative to camera Y)
        -- Spawn at random Y across full range for continuous distribution
        if p.y < cam_y + rain_despawn_below then
            p.x = cam_x + (math.random() - 0.5) * rain_spread
            p.y = cam_y + rain_despawn_below + math.random() * rain_full_range
            p.z = cam_z + (math.random() - 0.5) * rain_spread
        end

        -- Respawn if too far from camera horizontally
        local dx = p.x - cam_x
        local dz = p.z - cam_z
        local dist_sq = dx * dx + dz * dz
        local max_dist_sq = rain_spread * rain_spread
        if dist_sq > max_dist_sq then
            p.x = cam_x + (math.random() - 0.5) * rain_spread
            p.z = cam_z + (math.random() - 0.5) * rain_spread
            p.y = cam_y + rain_despawn_below + math.random() * rain_full_range
        end
    end
end

-- Update lightning
function Weather.update_lightning(dt)
    if Weather.lightning_flash_active then
        Weather.lightning_flash_timer = Weather.lightning_flash_timer + dt

        -- Check if current flash should end
        if Weather.lightning_flash_timer >= Weather.LIGHTNING_FLASH_DURATION + Weather.LIGHTNING_FLASH_GAP then
            Weather.lightning_flash_timer = 0
            Weather.lightning_flash_count = Weather.lightning_flash_count + 1

            if Weather.lightning_flash_count >= Weather.LIGHTNING_FLASHES_PER_EVENT then
                Weather.lightning_flash_active = false
                Weather.lightning_flash_count = 0
                Weather.lightning_interval = 10 + math.random() * 10
            end
        end
    else
        Weather.lightning_timer = Weather.lightning_timer + dt
        if Weather.lightning_timer >= Weather.lightning_interval then
            Weather.lightning_timer = 0
            Weather.lightning_flash_active = true
            Weather.lightning_flash_count = 0
            Weather.lightning_flash_timer = 0
        end
    end
end

-- Check if lightning is currently flashing (for skydome swap)
function Weather.is_lightning_flash()
    if not Weather.lightning_flash_active then return false end
    return Weather.lightning_flash_timer < Weather.LIGHTNING_FLASH_DURATION
end

-- Bayer 4x4 dithering matrix (same as shader)
local BAYER_MATRIX = {
    0/16, 8/16, 2/16, 10/16,
    12/16, 4/16, 14/16, 6/16,
    3/16, 11/16, 1/16, 9/16,
    15/16, 7/16, 13/16, 5/16
}

-- Get Bayer dither threshold for a screen position
local function getBayerThreshold(x, y)
    local bx = math.floor(x) % 4
    local by = math.floor(y) % 4
    return BAYER_MATRIX[by * 4 + bx + 1]
end

-- Draw rain using 3D lines (world space, like speed lines)
-- Point A = current rain position (bottom tip)
-- Point B = where rain was in camera space last frame (based on ship velocity)
-- Uses fog distance for culling and dithering for fade
function Weather.draw_rain(renderer, cam, ship_vx, ship_vy, ship_vz)
    if not Weather.enabled then return end
    if not Weather.initialized then return end

    local cam_x = cam.pos.x
    local cam_y = cam.pos.y
    local cam_z = cam.pos.z

    -- Get fog distances for culling and dithering
    local fog_start = Weather.FOG_START_DISTANCE
    local fog_max = Weather.FOG_MAX_DISTANCE
    local fog_range = fog_max - fog_start

    -- Rain streak length and thickness from config
    local streak_length = config.WEATHER_RAIN_LENGTH
    local streak_thickness = config.WEATHER_RAIN_THICKNESS

    -- Calculate relative velocity: rain velocity - ship velocity
    -- Rain falls in world space, ship/camera moves - the difference creates the streak
    local rain_fall_speed = config.WEATHER_RAIN_FALL_SPEED
    local rain_vx = Weather.wind_vx * Weather.RAIN_WIND_MOTION_FACTOR
    local rain_vy = rain_fall_speed
    local rain_vz = Weather.wind_vz * Weather.RAIN_WIND_MOTION_FACTOR

    -- Relative velocity = rain velocity - camera/ship velocity
    -- Scale ship velocity to match rain velocity magnitude for visible effect
    local ship_scale = Weather.RAIN_SHIP_MOTION_FACTOR
    local rel_vx = rain_vx - (ship_vx * ship_scale)
    local rel_vy = rain_vy - (ship_vy * ship_scale)
    local rel_vz = rain_vz - (ship_vz * ship_scale)

    -- Normalize relative velocity for streak direction
    local rel_speed = math.sqrt(rel_vx * rel_vx + rel_vy * rel_vy + rel_vz * rel_vz)
    if rel_speed < 0.001 then return end

    local dir_x = rel_vx / rel_speed
    local dir_y = rel_vy / rel_speed
    local dir_z = rel_vz / rel_speed

    -- Rain particle index for pseudo-random dithering
    local particle_idx = 0

    for _, p in ipairs(Weather.rain_particles) do
        particle_idx = particle_idx + 1

        -- Calculate distance from camera
        local dx = p.x - cam_x
        local dy = p.y - cam_y
        local dz = p.z - cam_z
        local depth = math.sqrt(dx * dx + dy * dy + dz * dz)

        -- Skip if beyond fog max distance (fully fogged out)
        if depth > fog_max then
            goto continue
        end

        -- Calculate fog factor (0 = no fog, 1 = fully fogged)
        local fog_factor = 0
        if depth > fog_start then
            fog_factor = (depth - fog_start) / fog_range
        end

        -- Dithered fog: skip particle if fog_factor exceeds threshold
        local dither_x = (particle_idx * 7) % 4
        local dither_y = (particle_idx * 13) % 4
        local threshold = BAYER_MATRIX[dither_y * 4 + dither_x + 1]

        if fog_factor > threshold then
            goto continue
        end

        -- Point A: current rain position (bottom tip of streak)
        local x1 = p.x
        local y1 = p.y
        local z1 = p.z

        -- Point B: where rain appeared to be last frame (in camera space)
        -- This is the current position + relative velocity direction * streak length
        local x2 = p.x + dir_x * streak_length
        local y2 = p.y + dir_y * streak_length
        local z2 = p.z + dir_z * streak_length

        -- Choose color based on depth (closer = brighter)
        local depth_idx = math.floor(depth / 4) + 1  -- Tighter depth bands
        depth_idx = math.max(1, math.min(#Weather.RAIN_COLORS, depth_idx))
        local color = Weather.RAIN_COLORS[depth_idx]

        -- Draw 3D line as depth-tested geometry (must be called BEFORE flush3D)
        renderer.drawLine3DDepth({x1, y1, z1}, {x2, y2, z2}, color[1], color[2], color[3], streak_thickness)

        ::continue::
    end
end

-- Get weather fog settings (returns start, max distances)
function Weather.get_fog_settings()
    if Weather.enabled then
        return Weather.FOG_START_DISTANCE, Weather.FOG_MAX_DISTANCE
    else
        return config.FOG_START_DISTANCE, config.FOG_MAX_DISTANCE
    end
end

-- Get weather render distance
function Weather.get_render_distance()
    if Weather.enabled then
        return Weather.RENDER_DISTANCE
    else
        return config.RENDER_DISTANCE
    end
end

-- Check if weather is enabled
function Weather.is_enabled()
    return Weather.enabled
end

-- Draw 3D wireframe wind direction arrow
-- Arrow anchored to camera pivot and points in wind direction
-- Length scales with wind strength
function Weather.draw_wind_arrow(renderer, cam_x, cam_y, cam_z, ship_y)
    if not Weather.enabled then return end

    -- Get current wind strength based on ship altitude
    local strength = Weather.get_wind_strength(ship_y)

    -- Don't draw if no wind
    if strength < 0.001 then return end

    -- Wind direction (already normalized)
    local dir_x = Weather.wind_direction_x
    local dir_z = Weather.wind_direction_z

    -- Pulsating effect
    local time = love.timer.getTime()
    local pulse_range = config.WIND_ARROW_PULSE_MAX - config.WIND_ARROW_PULSE_MIN
    local pulse = config.WIND_ARROW_PULSE_MIN + pulse_range * (0.5 + 0.5 * math.sin(time * config.WIND_ARROW_PULSE_SPEED))

    -- Arrow length scales with wind strength
    local base_length = config.WIND_ARROW_LENGTH_BASE
    local length_scale = config.WIND_ARROW_LENGTH_SCALE
    local arrow_length = (base_length + strength * length_scale) * pulse
    local arrow_width = config.WIND_ARROW_WIDTH * pulse
    local skip_depth = not config.WIND_ARROW_DEPTH_TEST

    -- Arrow height (below the guide arrow)
    local arrow_height = cam_y + config.WIND_ARROW_Y_OFFSET

    -- Arrow center position (in front of camera in wind direction)
    local center_x = cam_x + dir_x * config.WIND_ARROW_DISTANCE
    local center_z = cam_z + dir_z * config.WIND_ARROW_DISTANCE

    -- Perpendicular direction for arrow width
    local perp_x = -dir_z
    local perp_z = dir_x

    -- Arrow tip (front, pointing in wind direction)
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
    local brightness = 0.7 + 0.3 * math.sin(time * config.WIND_ARROW_COLOR_SPEED)
    local r = math.floor(config.WIND_ARROW_COLOR_R * brightness)
    local g = math.floor(config.WIND_ARROW_COLOR_G * brightness)
    local b = math.floor(config.WIND_ARROW_COLOR_B * brightness)

    -- Draw chevron/arrow shape (simple triangle pointing in wind direction)
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
    local h2 = arrow_height + config.WIND_ARROW_HEIGHT
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

-- Draw lightning flash overlay (call after renderer.present())
-- Draws a semi-transparent white rectangle over the entire screen
function Weather.draw_lightning_flash()
    if not Weather.enabled then return end
    if not Weather.is_lightning_flash() then return end

    -- Draw white overlay with some transparency
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    love.graphics.setColor(1, 1, 1, 1)
end

return Weather
