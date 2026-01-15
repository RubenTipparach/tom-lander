-- Flight Scene: Main game scene with terrain, ship, and objects
-- Camera and controls ported from Picotron version

local config = require("config")
local renderer = require("renderer")
local camera_module = require("camera")
local mat4 = require("mat4")
local vec3 = require("vec3")
local quat = require("quat")
local Ship = require("ship")
local ParticleSystem = require("particle_system")
local SpeedLines = require("speed_lines")
local Minimap = require("minimap")
local Constants = require("constants")
local Heightmap = require("heightmap")
local LandingPads = require("landing_pads")
local Building = require("building")
local Cargo = require("cargo")
local Collision = require("collision")
local Trees = require("trees")
local Skydome = require("skydome")
local profile = require("profiler")
local HUD = require("hud")
local Mission = require("mission")
local Missions = require("missions")
local Weather = require("weather")
local Aliens = require("aliens")
local Bullets = require("bullets")
local Turret = require("turret")
local Shadow = require("graphics.shadow")
local ShadowMap = require("graphics.shadow_map")
local Fireworks = require("fireworks")
local Billboard = require("billboard")
local Explosion = require("explosion")
local AudioManager = require("audio_manager")

local flight_scene = {}

-- Scene state
local ship
local cam
local smoke_system
local speed_lines
local softwareImage  -- Only used by software renderer, unused with GPU renderer
local projMatrix
local follow_camera = true

-- Camera mode: "follow" (default if enabled), "free", "focus"
-- If follow mode is disabled, default to "free"
local camera_mode = config.CAMERA_FOLLOW_MODE_ENABLED and "follow" or "free"
local prev_camera_mode = camera_mode  -- Track previous mode for smooth transitions
local camera_mode_names = {"follow", "free", "focus"}

-- Camera settings
-- Note: Picotron runs at 60fps and applies lerp per-frame
local camera_lerp_speed = config.CAMERA_LERP_SPEED
local camera_zoom_speed = config.CAMERA_ZOOM_SPEED
local cam_dist = config.CAMERA_DISTANCE_MIN  -- Will be adjusted based on speed
local cam_rot_speed = config.CAMERA_ROTATION_SPEED
local mouse_sensitivity = config.CAMERA_MOUSE_SENSITIVITY
local last_mouse_x, last_mouse_y = 0, 0
local mouse_camera_enabled = false  -- Toggle with right mouse button

-- World objects
local buildings = {}
local building_configs = {}  -- Store building configs for missions
local cargo_items = {}

-- Game mode and mission
local game_mode = "arcade"  -- "arcade" or "simulation"
local current_mission_num = nil  -- nil = free flight
local current_track_num = nil  -- Track number for racing mode

-- Combat state (Mission 7)
local combat_active = false
local wave_start_delay = 0  -- Delay before starting next wave
local weapons_enabled = true  -- Toggle with T key

-- Race victory state
local race_victory_mode = false
local race_victory_cam_angle = 0  -- Camera orbit angle around ship
local race_victory_ship_pos = {x = 0, y = 0, z = 0}  -- Frozen ship position

-- Mission complete celebration state (non-race missions)
local mission_complete_mode = false
local mission_complete_cam_angle = 0
local mission_complete_ship_pos = {x = 0, y = 0, z = 0}
local mission_complete_timer = 0

-- Ship death state
local ship_death_mode = false
local ship_death_timer = 0
local ship_death_explosion_count = 0
local ship_death_pos = {x = 0, y = 0, z = 0}
local ship_death_landed = false  -- True once ship has hit the ground

-- Ship repair state
local repair_timer = 0
local is_repairing = false

-- Debug timer for camera vectors
local follow_cam_debug_timer = 0
local cam_orientation = nil  -- Camera orientation quaternion for follow mode

-- Fonts
local thrusterFont = nil

function flight_scene.load()
    print("[FLIGHT] Flight scene loaded - camera mode: " .. camera_mode)
    -- Stop menu music when entering flight scene
    AudioManager.stop_music()

    -- Renderer already initialized in main.lua
    -- softwareImage only needed for DDA renderer (GPU renderer handles its own presentation)
    local imageData = renderer.getImageData()
    if imageData then
        softwareImage = love.graphics.newImage(imageData)
        softwareImage:setFilter("nearest", "nearest")  -- Pixel-perfect upscaling
    end

    -- Initialize directional lighting for Gouraud shading
    if renderer.setDirectionalLight then
        local lightDir = config.LIGHT_DIRECTION or {0.5, -0.8, 0.3}
        local intensity = config.LIGHT_INTENSITY or 0.8
        local ambient = config.AMBIENT_LIGHT or 0.3
        renderer.setDirectionalLight(lightDir[1], lightDir[2], lightDir[3], intensity, ambient)
    end

    -- Initialize shadow map system
    if config.SHADOWS_ENABLED then
        ShadowMap.init()
        local lightDir = config.LIGHT_DIRECTION or {-0.866, 0.5, 0.0}
        ShadowMap.setLightDirection(lightDir[1], lightDir[2], lightDir[3])
    end

    -- Create projection matrix
    local aspect = config.RENDER_WIDTH / config.RENDER_HEIGHT
    projMatrix = mat4.perspective(config.FOV, aspect, config.NEAR_PLANE, config.FAR_PLANE)

    -- Initialize heightmap
    Heightmap.init()

    -- Initialize skydome
    Skydome.init()

    -- Generate trees
    Trees.generate(Heightmap)

    -- Clear and create landing pads (matching Picotron exactly)
    -- Picotron aseprite_to_world formula: (aseprite_x - 64) * 4, (aseprite_z - 64) * 4
    LandingPads.clear()

    -- Pad 1: Main spawn pad (Landing Pad A) - direct world coords in Picotron
    local pad1_x, pad1_z = 5, -3
    LandingPads.create_pad({
        id = 1,
        name = Constants.LANDING_PAD_NAMES[1],
        x = pad1_x,
        z = pad1_z,
        base_y = Heightmap.get_height(pad1_x, pad1_z),
        scale = 0.5
    })

    -- Pad 2: Landing Pad B - aseprite coords (25, 36)
    local pad2_x, pad2_z = (25 - 64) * 4, (36 - 64) * 4  -- = -156, -112
    LandingPads.create_pad({
        id = 2,
        name = Constants.LANDING_PAD_NAMES[2],
        x = pad2_x,
        z = pad2_z,
        base_y = Heightmap.get_height(pad2_x, pad2_z),
        scale = 0.5
    })

    -- Pad 3: Landing Pad C - aseprite coords (115, 112)
    local pad3_x, pad3_z = (115 - 64) * 4, (112 - 64) * 4  -- = 204, 192
    LandingPads.create_pad({
        id = 3,
        name = Constants.LANDING_PAD_NAMES[3],
        x = pad3_x,
        z = pad3_z,
        base_y = Heightmap.get_height(pad3_x, pad3_z),
        scale = 0.5
    })

    -- Pad 4: Landing Pad D - aseprite coords (44, 95)
    local pad4_x, pad4_z = (44 - 64) * 4, (95 - 64) * 4  -- = -80, 124
    LandingPads.create_pad({
        id = 4,
        name = Constants.LANDING_PAD_NAMES[4] or "Landing Pad D",
        x = pad4_x,
        z = pad4_z,
        base_y = Heightmap.get_height(pad4_x, pad4_z),
        scale = 0.5
    })

    -- Get spawn position from first landing pad
    local spawn_x, spawn_y, spawn_z, spawn_yaw = LandingPads.get_spawn(1)

    -- Create ship at landing pad
    ship = Ship.new({
        spawn_x = spawn_x or 0,
        spawn_y = spawn_y or 10,
        spawn_z = spawn_z or 0,
        spawn_yaw = spawn_yaw or 0
    })

    -- Register ship for damage smoke effects
    Explosion.register_damage_smoke("player_ship", function()
        return ship.x, ship.y, ship.z
    end)

    -- Create buildings (matching Picotron exactly)
    building_configs = {
        {x = -10, z = 5, width = 1.5, depth = 1.5, height = 8, side_sprite = Constants.SPRITE_BUILDING_SIDE},      -- Tall tower
        {x = -5, z = 4, width = 1.2, depth = 1.2, height = 6, side_sprite = Constants.SPRITE_BUILDING_SIDE_ALT},   -- Medium tower
        {x = 0, z = 5, width = 1.0, depth = 1.0, height = 5, side_sprite = Constants.SPRITE_BUILDING_SIDE},        -- Shorter building
        {x = 6, z = 4, width = 1.3, depth = 1.3, height = 7, side_sprite = Constants.SPRITE_BUILDING_SIDE_ALT},    -- Tall tower
        {x = -8, z = 12, width = 1.8, depth = 1.0, height = 4, side_sprite = Constants.SPRITE_BUILDING_SIDE},      -- Wide building
        {x = -2, z = 12, width = 1.0, depth = 1.8, height = 5, side_sprite = Constants.SPRITE_BUILDING_SIDE_ALT},  -- Long building
        {x = 3, z = 14, width = 1.2, depth = 1.2, height = 9, side_sprite = Constants.SPRITE_BUILDING_SIDE},       -- Tallest skyscraper
        {x = 9, z = 12, width = 1.0, depth = 1.0, height = 3, side_sprite = Constants.SPRITE_BUILDING_SIDE_ALT},   -- Small building
        {x = -6, z = 18, width = 1.5, depth = 1.2, height = 6, side_sprite = Constants.SPRITE_BUILDING_SIDE},      -- Medium building
        {x = 2, z = 20, width = 1.1, depth = 1.4, height = 7, side_sprite = Constants.SPRITE_BUILDING_SIDE_ALT},   -- Tall building (Command Tower for mission 3)
    }
    buildings = Building.create_city(building_configs, Heightmap)

    -- Set up mission system references
    Mission.LandingPads = LandingPads
    Missions.buildings = buildings
    Missions.building_configs = building_configs

    -- Get game mode and mission from menu
    local menu = require("menu")
    game_mode = menu.game_mode or "arcade"
    current_mission_num = menu.selected_mission  -- nil for free flight
    current_track_num = menu.selected_track      -- nil if not racing

    -- Create cargo items (only for free flight mode)
    cargo_items = {}
    if not current_mission_num and not current_track_num then
        -- Free flight mode - spawn a test cargo
        table.insert(cargo_items, Cargo.create({
            id = 1,
            x = 15,
            z = 10,
            base_y = Heightmap.get_height(15, 10),
            scale = 0.5
        }))
    end

    -- Start mission or race if selected
    if current_mission_num then
        Missions.start(current_mission_num, Mission)
        -- Start mission-specific music
        AudioManager.start_level_music(current_mission_num)
    elseif current_track_num then
        Missions.start_race_track(current_track_num, Mission)
        -- Racing mode defaults to focus camera (looks at next checkpoint)
        camera_mode = "focus"
        -- Racing mode uses mission 7 music mapping
        AudioManager.start_level_music(7)
    else
        -- Free flight - no music
    end

    -- Initialize combat systems for Mission 7 (Alien Invasion)
    combat_active = (current_mission_num == 7)
    if combat_active then
        -- Reset combat state
        Aliens.reset()
        Bullets.reset()
        Turret.init()

        -- Set up alien callbacks
        Aliens.spawn_bullet = function(x, y, z, dx, dy, dz, range)
            Bullets.spawn_enemy_bullet(x, y, z, dx, dy, dz, range)
        end
        Aliens.on_fighter_destroyed = function(x, y, z)
            Explosion.spawn_enemy(x, y, z, config.EXPLOSION_ENEMY_SCALE or 1.5)
            AudioManager.play_sfx(3)  -- Explosion sound
        end
        Aliens.on_mothership_destroyed = function(x, y, z)
            -- Big explosion for mothership (larger scale)
            Explosion.spawn_death(x, y, z, (config.EXPLOSION_DEATH_SCALE or 2.5) * 2.0)
            AudioManager.play_sfx(3)  -- Explosion sound
        end

        -- Start first wave with delay
        wave_start_delay = 2.0
    end

    -- Create camera (matching Picotron initial state)
    -- Camera starts at ship position, offset is applied during rendering
    cam = camera_module.new(spawn_x or 0, (spawn_y or 3), (spawn_z or 0) - 8)
    cam.pitch = 0  -- rx in Picotron
    cam.yaw = 0    -- ry in Picotron
    camera_module.updateVectors(cam)

    -- Create smoke particle system
    smoke_system = ParticleSystem.new({
        size = 0.3,
        max_particles = 20,
        lifetime = 0.5,  -- Short lifetime for quick puffs
        sprite_id = Constants.SPRITE_SMOKE,
        use_billboards = true
    })

    -- Create speed lines system
    speed_lines = SpeedLines.new()

    -- Initialize minimap
    Minimap.set_position(config.RENDER_WIDTH, config.RENDER_HEIGHT)

    -- Initialize HUD with renderer reference
    HUD.init(renderer)

    -- Enable fog (using config values matching Picotron, or weather values if enabled)
    local fog_start, fog_max = Weather.get_fog_settings()
    renderer.setFog(true, fog_start, fog_max,
        config.FOG_COLOR[1], config.FOG_COLOR[2], config.FOG_COLOR[3])

    -- Reset renderer state (menu may have changed these)
    renderer.setClearColor(162, 136, 121)

    print("Flight scene loaded")
    print("Controls:")
    print("  W/A/S/D or I/J/K/L - Thrusters")
    print("  Space - All thrusters | N - Side pair | M - Front/Back pair")
    print("  Arrow keys - Rotate camera")
    print("  Tab/Esc - Pause menu")
end

function flight_scene.update(dt)
    profile("update")

    -- Skip updates when paused
    if HUD.is_paused() then
        profile("update")
        return
    end

    -- Check for lap completion - trigger small fireworks
    if Mission.lap_just_completed then
        Mission.lap_just_completed = false
        -- Launch fireworks around the ship
        Fireworks.burst(ship.x, ship.y, ship.z, 3, 0.8)
    end

    -- Check for race completion - trigger big celebration fireworks
    if Mission.race_just_completed then
        Mission.race_just_completed = false
        -- Big fireworks celebration!
        Fireworks.celebrate(ship.x, ship.y, ship.z)
    end

    -- Check if race just completed - enter victory mode
    if Mission.race_complete and not race_victory_mode then
        race_victory_mode = true
        race_victory_cam_angle = cam.yaw  -- Start from current camera angle
        race_victory_ship_pos = {x = ship.x, y = ship.y, z = ship.z}
        -- Zero out ship velocity to freeze it
        ship.vx = 0
        ship.vy = 0
        ship.vz = 0
    end

    -- Check if non-race mission just completed - enter mission complete mode
    if Mission.is_complete() and not race_victory_mode and not mission_complete_mode and Mission.type ~= "race" then
        mission_complete_mode = true
        mission_complete_cam_angle = cam.yaw  -- Start from current camera angle
        mission_complete_ship_pos = {x = ship.x, y = ship.y, z = ship.z}
        mission_complete_timer = 0
        -- Zero out ship velocity to freeze it
        ship.vx = 0
        ship.vy = 0
        ship.vz = 0
        -- Fireworks triggered after delay (in mission_complete_mode block below)
    end

    -- Race victory mode: freeze ship but orbit camera
    if race_victory_mode then
        -- Keep ship frozen at victory position
        ship.x = race_victory_ship_pos.x
        ship.y = race_victory_ship_pos.y
        ship.z = race_victory_ship_pos.z

        -- Keep thrusters active for flame animation (gentle hover effect)
        for _, thruster in ipairs(ship.thrusters) do
            thruster.active = true
        end

        -- Update fireworks during victory celebration
        Fireworks.update(dt)

        -- Launch more fireworks periodically during victory
        if math.random() < dt * 2 then  -- Roughly 2 per second
            local angle = math.random() * math.pi * 2
            local dist = 8 + math.random() * 8
            Fireworks.launch(
                ship.x + math.sin(angle) * dist,
                ship.y - 2,
                ship.z + math.cos(angle) * dist,
                1.2
            )
        end

        -- Orbit camera around ship
        race_victory_cam_angle = race_victory_cam_angle + dt * 0.3  -- Slow rotation
        local orbit_dist = 12  -- Distance from ship
        local orbit_height = 3  -- Height above ship

        -- Calculate camera position on orbit
        cam.pos.x = ship.x + math.sin(race_victory_cam_angle) * orbit_dist
        cam.pos.y = ship.y + orbit_height
        cam.pos.z = ship.z + math.cos(race_victory_cam_angle) * orbit_dist

        -- Point camera at ship
        cam.yaw = race_victory_cam_angle + math.pi  -- Face toward ship center
        cam.pitch = 0.2  -- Slight downward angle
        cam_dist = 0  -- Disable camera distance offset for clean orbit

        camera_module.updateVectors(cam)
        profile("update")
        return
    end

    -- Mission complete mode: freeze ship but orbit camera (non-race missions)
    if mission_complete_mode then
        mission_complete_timer = mission_complete_timer + dt

        -- Keep ship frozen at victory position
        ship.x = mission_complete_ship_pos.x
        ship.y = mission_complete_ship_pos.y
        ship.z = mission_complete_ship_pos.z

        -- Keep thrusters active for flame animation (gentle hover effect)
        for _, thruster in ipairs(ship.thrusters) do
            thruster.active = true
        end

        -- 3-second delay before celebration sequence starts
        local celebration_delay = 3.0
        if mission_complete_timer > celebration_delay then
            -- Update fireworks during victory celebration
            Fireworks.update(dt)

            -- Launch more fireworks periodically during victory
            if math.random() < dt * 2 then  -- Roughly 2 per second
                local angle = math.random() * math.pi * 2
                local dist = 8 + math.random() * 8
                Fireworks.launch(
                    ship.x + math.sin(angle) * dist,
                    ship.y - 2,
                    ship.z + math.cos(angle) * dist,
                    1.2
                )
            end

            -- Orbit camera around ship (only after delay)
            mission_complete_cam_angle = mission_complete_cam_angle + dt * 0.3  -- Slow rotation
            local orbit_dist = 12  -- Distance from ship
            local orbit_height = 3  -- Height above ship

            -- Calculate camera position on orbit
            cam.pos.x = ship.x + math.sin(mission_complete_cam_angle) * orbit_dist
            cam.pos.y = ship.y + orbit_height
            cam.pos.z = ship.z + math.cos(mission_complete_cam_angle) * orbit_dist

            -- Point camera at ship
            cam.yaw = mission_complete_cam_angle + math.pi  -- Face toward ship center
            cam.pitch = 0.2  -- Slight downward angle
            cam_dist = 0  -- Disable camera distance offset for clean orbit
        end

        camera_module.updateVectors(cam)
        profile("update")
        return
    end

    -- Check for ship death FIRST (before physics update)
    if ship:is_destroyed() and not ship_death_mode then
        ship_death_mode = true
        ship_death_timer = 0
        ship_death_explosion_count = 0
        ship_death_pos = {x = ship.x, y = ship.y, z = ship.z}
        ship_death_landed = false

        -- Don't freeze - let it fall! Just stop rotation controls
        ship.local_vpitch = 0
        ship.local_vyaw = 0
        ship.local_vroll = 0

        -- Spawn the big death explosion
        Explosion.spawn_death(ship.x, ship.y, ship.z, config.EXPLOSION_DEATH_SCALE or 2.5)
        AudioManager.play_sfx(3)  -- Explosion sound
        AudioManager.play_death_sound()  -- "You died" voice
        AudioManager.stop_thruster()  -- Stop thruster sound
    end

    -- Handle death sequence - ship falls with gravity until hitting ground
    if ship_death_mode then
        ship_death_timer = ship_death_timer + dt

        -- Stop rotation controls but allow falling
        ship.local_vpitch = 0
        ship.local_vyaw = 0
        ship.local_vroll = 0

        if not ship_death_landed then
            -- Apply gravity
            local gravity = config.GRAVITY or 0.15
            ship.vy = ship.vy - gravity * dt * 60

            -- Apply some air resistance to horizontal movement
            ship.vx = ship.vx * 0.99
            ship.vz = ship.vz * 0.99

            -- Update position
            ship.x = ship.x + ship.vx * dt * 60
            ship.y = ship.y + ship.vy * dt * 60
            ship.z = ship.z + ship.vz * dt * 60

            -- Check for ground collision
            local ground_height = Heightmap.get_height(ship.x, ship.z)
            local ship_ground_offset = config.VTOL_COLLISION_HEIGHT + config.VTOL_COLLISION_OFFSET_Y

            if ship.y < ground_height + ship_ground_offset then
                -- Hit the ground - stop falling
                ship.y = ground_height + ship_ground_offset
                ship.vx = 0
                ship.vy = 0
                ship.vz = 0
                ship_death_landed = true

                -- Spawn crash explosion on impact
                Explosion.spawn_impact(ship.x, ship.y, ship.z, 1.0)
                AudioManager.play_sfx(3)  -- Explosion sound
            end
        end

        -- Spawn additional explosions during death sequence (while falling)
        if ship_death_timer < 2.0 and math.random() < dt * 3 then
            local offset_x = (math.random() - 0.5) * 3
            local offset_y = (math.random() - 0.5) * 2
            local offset_z = (math.random() - 0.5) * 3
            Explosion.spawn_impact(
                ship.x + offset_x,
                ship.y + offset_y,
                ship.z + offset_z,
                0.5 + math.random() * 0.5
            )
        end

        -- Update billboards and particles even during death
        Billboard.update(dt)
        smoke_system:update(dt)

        -- Update damage smoke (shows ship is destroyed)
        Explosion.update_damage_smoke("player_ship", 0, dt)

        -- After death sequence, show death screen (handled in draw)
        -- Player can press R to restart or Q to quit
        profile("update")
        return
    end

    -- Disable ship controls during race countdown
    ship.controls_disabled = Mission.is_race_countdown_active()

    -- Update ship physics (only when alive)
    ship:update(dt)

    -- Update damage smoke based on hull percentage
    local hull_percent = ship:get_hull_percent()
    Explosion.update_damage_smoke("player_ship", hull_percent, dt)

    -- Ground damping constants
    local GROUND_VELOCITY_DAMPING = 0.9  -- Extra damping when grounded

    -- Track highest ground level (terrain or landing pad)
    local ground_height = Heightmap.get_height(ship.x, ship.z)
    local is_grounded = false

    -- Check landing pad surfaces first (they can be higher than terrain)
    for _, pad in ipairs(LandingPads.get_all()) do
        if pad.collision then
            local bounds = pad.collision:get_bounds()

            if Collision.point_in_box(ship.x, ship.z, pad.x, pad.z, bounds.half_width, bounds.half_depth) then
                -- Ship is horizontally over landing pad
                -- Check if ship is within the vertical bounds (side collision)
                if ship.y > bounds.bottom and ship.y < bounds.top then
                    -- Side collision - push out
                    ship.x, ship.z = Collision.push_out_of_box(
                        ship.x, ship.z,
                        pad.x, pad.z,
                        bounds.half_width, bounds.half_depth
                    )
                    ship.vx = ship.vx * 0.5
                    ship.vz = ship.vz * 0.5
                else
                    -- Use pad top as ground height if higher
                    if bounds.top > ground_height then
                        ground_height = bounds.top
                    end
                end
            end
        end
    end

    -- Building collision (matching Picotron)
    local ship_half_width = config.VTOL_COLLISION_WIDTH
    local ship_half_depth = config.VTOL_COLLISION_DEPTH

    for _, building in ipairs(buildings) do
        local half_width = building.width / 2
        local half_depth = building.depth / 2
        local building_height = building.height
        local building_top = building.y + building_height
        local building_bottom = building.y

        -- Check if ship's bounding box overlaps with building
        local ship_half_height = config.VTOL_COLLISION_HEIGHT
        local ship_bottom = ship.y - ship_half_height + config.VTOL_COLLISION_OFFSET_Y
        local ship_top = ship.y + ship_half_height + config.VTOL_COLLISION_OFFSET_Y
        if Collision.box_overlap(ship.x, ship.z, ship_half_width, ship_half_depth,
                                  building.x, building.z, half_width, half_depth) then
            -- Ship is horizontally inside building bounds
            -- Check if ship center is above building top (landing from above)
            -- Use small tolerance to prevent edge-case side collisions when landing
            local roof_tolerance = 0.1
            if ship.y > building_top - roof_tolerance then
                -- Ship is above building - rooftop is a landing surface
                if building_top > ground_height then
                    ground_height = building_top
                end
            elseif ship_bottom < building_top and ship_top > building_bottom then
                -- Side collision: ship is inside building volume - push out
                local old_x, old_z = ship.x, ship.z
                ship.x, ship.z = Collision.push_out_of_box(
                    ship.x, ship.z,
                    building.x, building.z,
                    half_width, half_depth
                )

                -- Calculate bounce direction (away from building)
                local push_dx = ship.x - old_x
                local push_dz = ship.z - old_z
                local push_len = math.sqrt(push_dx * push_dx + push_dz * push_dz)

                -- Damage based on collision speed (configurable multiplier)
                local collision_speed = math.sqrt(ship.vx*ship.vx + ship.vy*ship.vy + ship.vz*ship.vz)
                if collision_speed > 0.05 then
                    local damage = collision_speed * (config.SHIP_COLLISION_DAMAGE_MULTIPLIER or 20)
                    ship:take_damage(damage)
                    -- Spawn impact explosion
                    Explosion.spawn_impact(ship.x, ship.y, ship.z, config.EXPLOSION_IMPACT_SCALE or 0.8)
                    AudioManager.play_sfx(8)  -- Collision sound
                end

                -- Bounce off building - reverse and reduce velocity, add push force
                local bounce_factor = 0.5  -- How much velocity is preserved (reversed)
                local push_force = math.max(collision_speed * 0.3, 0.05)  -- Minimum push to escape

                if push_len > 0.001 then
                    -- Normalize push direction and apply bounce
                    local nx, nz = push_dx / push_len, push_dz / push_len
                    ship.vx = -ship.vx * bounce_factor + nx * push_force
                    ship.vz = -ship.vz * bounce_factor + nz * push_force
                else
                    -- Fallback: just reverse velocity
                    ship.vx = -ship.vx * bounce_factor
                    ship.vz = -ship.vz * bounce_factor
                end
            end
        end
    end

    -- Apply ground collision
    local ship_ground_offset = config.VTOL_COLLISION_HEIGHT + config.VTOL_COLLISION_OFFSET_Y
    local landing_height = ground_height + ship_ground_offset

    if ship.y < landing_height then
        -- Check for water collision (instant death)
        if Heightmap.is_water(ship.x, ship.z) then
            -- Water collision = instant death explosion
            Explosion.spawn_death(ship.x, ship.y, ship.z, config.EXPLOSION_DEATH_SCALE or 2.5)
            AudioManager.play_sfx(3)  -- Explosion sound
            ship.health = 0  -- Kill the ship
        else
            local vertical_speed = math.abs(ship.vy)
            local horizontal_speed = math.sqrt(ship.vx * ship.vx + ship.vz * ship.vz)

            -- Calculate orientation damage multiplier
            -- Ship's local up vector (0, 1, 0) transformed to world space
            -- If ship is upright, world_up_y will be close to 1
            -- If ship is upside down, world_up_y will be close to -1
            -- If ship is on its side, world_up_y will be close to 0
            local _, world_up_y, _ = quat.rotateVector(ship.orientation, 0, 1, 0)

            -- Orientation multiplier based on ship orientation
            -- world_up_y = 1 (upright) -> 1x damage (bottom armor)
            -- world_up_y = 0 (on side) -> side crash multiplier
            -- world_up_y < 0 (upside down) -> top crash multiplier
            local side_mult = config.SHIP_SIDE_CRASH_MULTIPLIER or 5
            local top_mult = config.SHIP_TOP_CRASH_MULTIPLIER or 10
            local orientation_multiplier = 1.0

            if world_up_y < 0 then
                -- Upside down: interpolate from side_mult at 0 to top_mult at -1
                local t = -world_up_y  -- 0 to 1 as we go more upside down
                orientation_multiplier = side_mult + t * (top_mult - side_mult)
            elseif world_up_y < 0.5 then
                -- On side: interpolate from 1x at 0.5 to side_mult at 0
                local t = (0.5 - world_up_y) / 0.5  -- 0 at 0.5, 1 at 0
                orientation_multiplier = 1 + t * (side_mult - 1)
            end

            -- Damage on hard landing (configurable thresholds)
            local hard_landing_threshold = config.SHIP_HARD_LANDING_THRESHOLD or 0.05
            local explosion_threshold = config.SHIP_HARD_LANDING_EXPLOSION_THRESHOLD or 0.1

            -- Vertical impact damage
            if vertical_speed > hard_landing_threshold then
                -- Quadratic damage scaling: harder impacts hurt exponentially more
                local base_damage = vertical_speed * (config.SHIP_COLLISION_DAMAGE_MULTIPLIER or 20)
                local speed_factor = 1 + (vertical_speed * 10)
                local damage = base_damage * speed_factor * orientation_multiplier
                ship:take_damage(damage)
                -- Spawn impact explosion for hard landings
                if vertical_speed > explosion_threshold then
                    local explosion_scale = (config.EXPLOSION_IMPACT_SCALE or 0.8) * math.min(orientation_multiplier, 3)
                    Explosion.spawn_impact(ship.x, ship.y, ship.z, explosion_scale)
                    AudioManager.play_sfx(8)  -- Collision sound
                end
            end

            -- Horizontal ground scraping damage (dragging along ground)
            local scrape_threshold = config.SHIP_GROUND_SCRAPE_THRESHOLD or 0.08
            if horizontal_speed > scrape_threshold then
                local scrape_damage = horizontal_speed * (config.SHIP_COLLISION_DAMAGE_MULTIPLIER or 20) * 0.5
                local speed_factor = 1 + (horizontal_speed * 5)
                ship:take_damage(scrape_damage * speed_factor * orientation_multiplier)
                -- Spawn sparks/small explosion for fast scraping
                if horizontal_speed > scrape_threshold * 2 then
                    Explosion.spawn_impact(ship.x, ship.y, ship.z, 0.4)
                    AudioManager.play_sfx(8)  -- Collision sound
                end
            end
        end

        -- Snap to ground and zero vertical velocity
        ship.y = landing_height
        ship.vy = 0
        is_grounded = true

        -- Extra horizontal damping when grounded to prevent sliding
        ship.vx = ship.vx * GROUND_VELOCITY_DAMPING
        ship.vz = ship.vz * GROUND_VELOCITY_DAMPING
    end

    -- Update cargo (pass quaternion orientation for gimbal-lock-free rotation)
    -- Only update free-flight cargo if no mission is active
    if not Mission.is_active() then
        for _, cargo in ipairs(cargo_items) do
            Cargo.update(cargo, dt, ship.x, ship.y, ship.z, ship.orientation)
        end
    end

    -- Check for landing (returns the pad the ship is currently on, or nil)
    local current_landing_pad = LandingPads.check_landing(ship.x, ship.y, ship.z, ship.vy)

    -- Update mission system
    if Mission.is_active() then
        Mission.update(dt, ship, current_landing_pad)
    end

    -- Free flight cargo delivery
    if not Mission.is_active() and current_landing_pad and cargo_items[1] and Cargo.is_attached(cargo_items[1]) then
        Cargo.deliver(cargo_items[1])
        print("Cargo delivered to " .. current_landing_pad.name .. "!")
    end

    -- Landing pad repair system
    is_repairing = false
    if current_landing_pad and is_grounded then
        -- Calculate total velocity
        local total_velocity = math.sqrt(ship.vx*ship.vx + ship.vy*ship.vy + ship.vz*ship.vz)
        local velocity_threshold = config.SHIP_REPAIR_VELOCITY_THRESHOLD or 0.05

        if total_velocity < velocity_threshold then
            -- Ship is stationary on landing pad
            repair_timer = repair_timer + dt
            local repair_delay = config.SHIP_REPAIR_DELAY or 1.0

            -- Start repairing after delay
            if repair_timer >= repair_delay and ship.health < ship.max_health then
                is_repairing = true
                local repair_rate = config.SHIP_REPAIR_RATE or 20
                local repair_amount = repair_rate * dt
                ship.health = math.min(ship.health + repair_amount, ship.max_health)
            end
        else
            -- Ship is moving, reset repair timer
            repair_timer = 0
        end
    else
        -- Not on landing pad, reset repair timer
        repair_timer = 0
    end

    -- Spawn smoke particles when thrusters are active
    local any_thruster_active = false
    for _, thruster in ipairs(ship.thrusters) do
        if thruster.active then
            any_thruster_active = true
            smoke_system:spawn(
                ship.x + thruster.x,
                ship.y - 0.5,
                ship.z + thruster.z,
                ship.vx * 0.5,
                -0.02,
                ship.vz * 0.5
            )
        end
    end

    -- Manage thruster sound
    if any_thruster_active and not ship_death_mode then
        AudioManager.start_thruster()
    else
        AudioManager.stop_thruster()
    end

    -- Update particles
    smoke_system:update(dt)

    -- Update speed lines (pass ship position and velocity)
    speed_lines:update(dt, ship.x, ship.y, ship.z, ship.vx, ship.vy, ship.vz)

    -- Update weather system (rain particles, wind changes, lightning)
    Weather.update(dt, cam.pos.x, cam.pos.y, cam.pos.z, ship.vx, ship.vy, ship.vz)
    Weather.apply_wind(ship, ship.y, is_grounded)

    -- Update fireworks (for lap completion celebrations)
    Fireworks.update(dt)

    -- Update billboards
    Billboard.update(dt)

    -- Update combat systems (Mission 6)
    if combat_active then
        -- Wave start delay
        if wave_start_delay > 0 then
            wave_start_delay = wave_start_delay - dt
            if wave_start_delay <= 0 then
                -- Start next wave
                local has_more = Aliens.start_next_wave(ship, LandingPads)
                if has_more then
                    print("Wave " .. Aliens.get_wave() .. " starting!")
                end
            end
        end

        -- Check if wave complete and start next (only if not already waiting)
        if Aliens.wave_complete and not Aliens.all_waves_complete() and wave_start_delay <= 0 then
            wave_start_delay = 3.0  -- Delay between waves
            Aliens.wave_complete = false
        end

        -- Check for mission complete
        if Aliens.all_waves_complete() and not Mission.is_complete() then
            Mission.complete()
        end

        -- Update aliens (pass landing pad status for safe zones)
        local player_on_pad = LandingPads.check_landing(ship.x, ship.y, ship.z, ship.vy) ~= nil
        -- Pass world objects for collision detection
        local world_objects = {
            heightmap = Heightmap,
            trees = Trees,
            buildings = buildings
        }
        Aliens.update(dt, ship, player_on_pad, world_objects)

        -- Validate current target (auto-select next if destroyed)
        local enemies = Aliens.get_all()
        local validated_target = HUD.validate_target(enemies)
        -- Sync turret target with HUD target
        Turret.target = validated_target

        -- Update turret (auto-aims at enemies)
        Turret.update(dt, ship, enemies)

        -- Auto-fire turret when target acquired (and weapons enabled)
        if weapons_enabled and Turret.can_fire() and Turret.target then
            local dir_x, dir_y, dir_z = Turret.get_fire_direction(ship)
            if dir_x then
                local turret_x, turret_y, turret_z = Turret.get_position(ship)
                Bullets.spawn_player_bullet(turret_x, turret_y, turret_z, dir_x, dir_y, dir_z)
            end
        end

        -- Update bullets (with world collision)
        Bullets.update(dt, world_objects)

        -- Check player bullet hits on aliens
        for _, fighter in ipairs(Aliens.fighters) do
            local hits = Bullets.check_collision_sphere("enemy", fighter.x, fighter.y, fighter.z, 0.5)
            for _, hit in ipairs(hits) do
                -- Random damage 5-10 per bullet
                local damage = 5 + math.random() * 5
                fighter.health = fighter.health - damage
                -- Spawn small impact explosion at hit location
                Explosion.spawn_impact(hit.x, hit.y, hit.z, 0.4)
            end
        end
        if Aliens.mother_ship then
            local hits = Bullets.check_collision_sphere("enemy", Aliens.mother_ship.x, Aliens.mother_ship.y, Aliens.mother_ship.z, Aliens.MOTHER_SHIP_COLLISION_RADIUS)
            for _, hit in ipairs(hits) do
                -- Random damage 5-10 per bullet
                local damage = 5 + math.random() * 5
                Aliens.mother_ship.health = Aliens.mother_ship.health - damage
                -- Spawn small impact explosion at hit location
                Explosion.spawn_impact(hit.x, hit.y, hit.z, 0.5)
            end
        end

        -- Check enemy bullet hits on player
        local player_hits = Bullets.check_collision_sphere("player", ship.x, ship.y, ship.z, 0.5)
        for _, hit in ipairs(player_hits) do
            ship:take_damage(10)  -- Damage per enemy bullet
        end
    end

    -- Auto-level with shift key
    if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
        ship:auto_level(dt)
    end

    -- Camera rotation (depends on camera mode)
    local timeScale = dt * 60  -- Scale for 60 FPS equivalence

    if camera_mode == "free" then
        -- FREE MODE: Arrow keys and mouse control camera rotation
        if love.keyboard.isDown("left") then
            cam.yaw = cam.yaw - cam_rot_speed * timeScale
        end
        if love.keyboard.isDown("right") then
            cam.yaw = cam.yaw + cam_rot_speed * timeScale
        end
        if love.keyboard.isDown("up") then
            cam.pitch = cam.pitch - cam_rot_speed * 0.6 * timeScale
        end
        if love.keyboard.isDown("down") then
            cam.pitch = cam.pitch + cam_rot_speed * 0.6 * timeScale
        end

        -- Mouse camera control
        local mouse_x, mouse_y = love.mouse.getPosition()
        if love.mouse.isDown(1) or love.mouse.isDown(2) then
            if mouse_camera_enabled then
                local dx = mouse_x - last_mouse_x
                local dy = mouse_y - last_mouse_y
                cam.yaw = cam.yaw + dx * mouse_sensitivity
                cam.pitch = cam.pitch + dy * mouse_sensitivity
                cam.pitch = math.max(-1.5, math.min(1.5, cam.pitch))
            end
            mouse_camera_enabled = true
        else
            mouse_camera_enabled = false
        end
        last_mouse_x, last_mouse_y = mouse_x, mouse_y

        -- Debug print every 5 seconds (if enabled)
        if config.CAMERA_DEBUG then
            follow_cam_debug_timer = follow_cam_debug_timer + dt
            if follow_cam_debug_timer >= 5 then
                follow_cam_debug_timer = 0
                -- Use camera module's forward vector (updated by updateVectors)
                camera_module.updateVectors(cam)
                local horiz_speed = math.sqrt(ship.vx * ship.vx + ship.vz * ship.vz)
                print("=== FREE CAMERA DEBUG ===")
                print(string.format("Ship pos: x=%.1f, y=%.1f, z=%.1f", ship.x, ship.y, ship.z))
                print(string.format("Cam pos:  x=%.1f, y=%.1f, z=%.1f", cam.pos.x, cam.pos.y, cam.pos.z))
                print(string.format("Cam fwd:  x=%.3f, y=%.3f, z=%.3f", cam.forward.x, cam.forward.y, cam.forward.z))
                print(string.format("Ship vel: vx=%.3f, vy=%.3f, vz=%.3f (horiz=%.3f)",
                    ship.vx, ship.vy, ship.vz, horiz_speed))
                print(string.format("Yaw: %.1f deg, Pitch: %.1f deg", math.deg(cam.yaw), math.deg(cam.pitch)))
            end
        end

    elseif camera_mode == "follow" then
        -- FOLLOW MODE: Camera follows behind ship, looking toward it
        -- Per user diagram:
        -- - Camera positioned BEHIND ship (opposite of velocity direction)
        -- - Camera LOOKS TOWARD ship (in velocity direction from camera's perspective)
        --
        -- This section ONLY handles rotation (quaternion).
        -- Position is handled in the later position update section.

        -- Initialize quaternion from current yaw/pitch (on mode switch or first time)
        if not cam_orientation or prev_camera_mode ~= "follow" then
            -- Build quaternion from current camera yaw and pitch for smooth transition
            local yaw_quat = quat.fromAxisAngle(0, 1, 0, cam.yaw)
            local pitch_quat = quat.fromAxisAngle(1, 0, 0, cam.pitch)
            cam_orientation = quat.multiply(yaw_quat, pitch_quat)
        end

        -- Ship horizontal velocity (for yaw direction)
        local horizontal_speed = math.sqrt(ship.vx * ship.vx + ship.vz * ship.vz)

        if horizontal_speed > 0.01 then
            -- Normalized horizontal velocity direction
            local vel_x = ship.vx / horizontal_speed
            local vel_z = ship.vz / horizontal_speed

            -- Target yaw: camera looks OPPOSITE to velocity direction
            -- This way, with cam_dist offset, the ship appears in front of the camera
            local target_yaw = math.atan2(vel_x, -vel_z)

            -- Target pitch: subtle tilt based on vertical movement, but limited
            -- Use full 3D speed for pitch calculation
            local ship_speed = math.sqrt(ship.vx * ship.vx + ship.vy * ship.vy + ship.vz * ship.vz)
            local target_pitch = 0
            if ship_speed > 0.01 then
                -- Pitch based on ratio of vertical to horizontal speed
                -- Positive vy (going up) -> positive pitch (look down at ship)
                -- Negative vy (going down) -> negative pitch (look up at ship)
                local pitch_ratio = ship.vy / ship_speed
                target_pitch = pitch_ratio * 0.4  -- Limit to ~23 degrees max
                target_pitch = math.max(-0.4, math.min(0.4, target_pitch))
            end

            -- Build target quaternion: yaw around Y, then pitch around X
            -- For "yaw then pitch in local frame", we use: yaw * pitch
            local yaw_quat = quat.fromAxisAngle(0, 1, 0, target_yaw)
            local pitch_quat = quat.fromAxisAngle(1, 0, 0, target_pitch)
            local target_quat = quat.multiply(yaw_quat, pitch_quat)

            -- Slerp toward target
            local slerp_speed = 0.08 * timeScale
            cam_orientation = quat.slerp(cam_orientation, target_quat, slerp_speed)
            cam_orientation = quat.normalize(cam_orientation)
        end

        -- Get forward direction from quaternion
        local cam_fwd_x, cam_fwd_y, cam_fwd_z = quat.rotateVector(cam_orientation, 0, 0, 1)

        -- Extract yaw/pitch from forward vector for view matrix
        -- Camera convention: forward = (sin(yaw)*cos(pitch), -sin(pitch), cos(yaw)*cos(pitch))
        cam.yaw = math.atan2(cam_fwd_x, cam_fwd_z)
        cam.pitch = math.asin(math.max(-1, math.min(1, -cam_fwd_y)))

        -- Debug print every 5 seconds (if enabled)
        if config.CAMERA_DEBUG then
            follow_cam_debug_timer = follow_cam_debug_timer + dt
            if follow_cam_debug_timer >= 5 then
                follow_cam_debug_timer = 0
                print("=== FOLLOW CAMERA DEBUG ===")
                print(string.format("Ship pos: x=%.1f, y=%.1f, z=%.1f", ship.x, ship.y, ship.z))
                print(string.format("Cam pos:  x=%.1f, y=%.1f, z=%.1f", cam.pos.x, cam.pos.y, cam.pos.z))
                print(string.format("Cam fwd:  x=%.3f, y=%.3f, z=%.3f", cam_fwd_x, cam_fwd_y, cam_fwd_z))
                print(string.format("Ship vel: vx=%.3f, vy=%.3f, vz=%.3f (horiz=%.3f)",
                    ship.vx, ship.vy, ship.vz, horizontal_speed))
                print(string.format("Yaw: %.1f deg, Pitch: %.1f deg", math.deg(cam.yaw), math.deg(cam.pitch)))
            end
        end

        -- Update mouse position tracking
        last_mouse_x, last_mouse_y = love.mouse.getPosition()

    elseif camera_mode == "focus" then
        -- FOCUS MODE: Camera looks at current target/goal
        local target = HUD.get_target()
        if not target and Mission.is_active() then
            target = Mission.get_target()
        end

        if target then
            -- Calculate direction to target (same convention as guide arrow)
            local dx = target.x - cam.pos.x
            local dz = target.z - cam.pos.z
            local dy = (target.y or ship.y) - cam.pos.y
            local dist_xz = math.sqrt(dx * dx + dz * dz)

            -- Target yaw (horizontal direction) - negate dz for camera convention
            local target_yaw = math.atan2(dx, -dz)
            local yaw_diff = target_yaw - cam.yaw
            while yaw_diff > math.pi do yaw_diff = yaw_diff - math.pi * 2 end
            while yaw_diff < -math.pi do yaw_diff = yaw_diff + math.pi * 2 end
            cam.yaw = cam.yaw + yaw_diff * 0.1 * timeScale

            -- Target pitch (vertical angle)
            local target_pitch = math.atan2(dy, dist_xz)
            target_pitch = math.max(-1.2, math.min(1.2, target_pitch))
            cam.pitch = cam.pitch + (target_pitch - cam.pitch) * 0.1 * timeScale
        else
            -- No target - fall back to follow mode behavior
            local speed_sq = ship.vx * ship.vx + ship.vz * ship.vz

            if speed_sq > 0.001 then
                local speed = math.sqrt(speed_sq)
                local move_dir_x = ship.vx / speed
                local move_dir_z = ship.vz / speed

                -- Camera looks opposite to velocity (same as follow mode)
                local target_yaw = math.atan2(move_dir_x, -move_dir_z)
                local angle_diff = target_yaw - cam.yaw
                while angle_diff > math.pi do angle_diff = angle_diff - math.pi * 2 end
                while angle_diff < -math.pi do angle_diff = angle_diff + math.pi * 2 end

                local turn_speed = 0.08 * timeScale
                if math.abs(angle_diff) > math.pi / 2 then
                    turn_speed = 0.15 * timeScale
                end

                if math.abs(angle_diff) > 0.01 then
                    local rotation = angle_diff > 0 and turn_speed or -turn_speed
                    if math.abs(rotation) > math.abs(angle_diff) then
                        rotation = angle_diff
                    end
                    cam.yaw = cam.yaw + rotation
                end
            end

            -- Gradually return pitch to neutral
            cam.pitch = cam.pitch + (0 - cam.pitch) * 0.02 * timeScale
        end

        -- Update mouse position tracking
        last_mouse_x, last_mouse_y = love.mouse.getPosition()
    end

    -- Camera follows ship with smooth lerp (frame-rate independent)
    -- Pivot point is the ship position
    local pivot_x = ship.x
    local pivot_y = ship.y
    local pivot_z = ship.z

    -- Update camera distance based on ship speed (with smooth lerp)
    local ship_speed = math.sqrt(ship.vx * ship.vx + ship.vy * ship.vy + ship.vz * ship.vz)
    local speed_factor = math.min(ship_speed / config.CAMERA_DISTANCE_SPEED_MAX, 1.0)
    local target_cam_dist = config.CAMERA_DISTANCE_MIN + (config.CAMERA_DISTANCE_MAX - config.CAMERA_DISTANCE_MIN) * speed_factor
    local zoomLerpFactor = 1.0 - math.pow(1.0 - camera_zoom_speed, timeScale)
    cam_dist = cam_dist + (target_cam_dist - cam_dist) * zoomLerpFactor

    -- Camera position: always at the pivot (ship position)
    -- The cam_dist offset is applied in the view matrix, not in world space
    local target_x, target_y, target_z = pivot_x, pivot_y, pivot_z

    -- Frame-rate independent lerp: 1 - (1-speed)^(dt*60)
    local lerpFactor = 1.0 - math.pow(1.0 - camera_lerp_speed, timeScale)

    -- Smoothly move camera toward target
    cam.pos.x = cam.pos.x + (target_x - cam.pos.x) * lerpFactor
    cam.pos.y = cam.pos.y + (target_y - cam.pos.y) * lerpFactor
    cam.pos.z = cam.pos.z + (target_z - cam.pos.z) * lerpFactor

    -- Track previous camera mode for smooth transitions
    prev_camera_mode = camera_mode

    camera_module.updateVectors(cam)
    profile("update")
end

function flight_scene.draw()
    profile("clear")

    -- Update fog based on weather state (narrower visibility during storms)
    local fog_start, fog_max = Weather.get_fog_settings()
    local fog_color = Weather.is_enabled() and config.WEATHER_FOG_COLOR or config.FOG_COLOR
    renderer.setFog(true, fog_start, fog_max, fog_color[1], fog_color[2], fog_color[3])

    -- Set clear color to match fog (darker during weather)
    if Weather.is_enabled() then
        renderer.setClearColor(config.WEATHER_FOG_COLOR[1], config.WEATHER_FOG_COLOR[2], config.WEATHER_FOG_COLOR[3])
    else
        renderer.setClearColor(162, 136, 121)  -- Default clear color
    end

    -- Set clear color and clear buffers
    renderer.clearBuffers()

    -- Build view matrix
    -- cam_dist pushes the view backward in camera's local -Z direction
    local viewMatrix = camera_module.getViewMatrix(cam, cam_dist)
    renderer.setMatrices(projMatrix, viewMatrix, {x = cam.pos.x, y = cam.pos.y, z = cam.pos.z})

    -- Store view matrix for target bracket drawing later
    flight_scene.viewMatrix = viewMatrix
    profile("clear")

    -- Render shadow map BEFORE terrain (terrain shader samples this)
    if config.SHADOWS_ENABLED then
        profile(" shadows")

        -- Begin shadow map pass
        if ShadowMap.beginPass(cam.pos.x, cam.pos.y, cam.pos.z) then
            -- Add ship as shadow caster
            if ship and ship.mesh then
                ShadowMap.addMeshCaster(ship.mesh, ship:get_model_matrix())
            end

            -- Add trees as shadow casters
            -- Tree mesh is ~2.0 units tall with foliage radius ~0.55 units
            local trees = Trees.get_all()
            for _, tree in ipairs(trees) do
                ShadowMap.addTreeCaster(tree.x, tree.y, tree.z, 0.55, 2.0)
            end

            -- Add buildings as shadow casters
            for _, building in ipairs(buildings) do
                local groundY = Heightmap.get_height(building.x, building.z)
                ShadowMap.addBoxCaster(building.x, groundY, building.z,
                    building.width, building.height, building.depth)
            end

            -- Add landing pads as shadow casters
            local pads = LandingPads.get_all()
            for _, pad in ipairs(pads) do
                local groundY = Heightmap.get_height(pad.x, pad.z)
                ShadowMap.addBoxCaster(pad.x, groundY, pad.z,
                    pad.width, pad.height or 0.5, pad.depth)
            end

            -- Render shadow map
            ShadowMap.endPass()

            -- Pass cascaded shadow maps to renderer for terrain shader
            renderer.setShadowMapCascaded(
                ShadowMap.getTextureNear(),
                ShadowMap.getLightViewMatrixNear(),
                ShadowMap.getLightProjMatrixNear(),
                ShadowMap.getTextureFar(),
                ShadowMap.getLightViewMatrixFar(),
                ShadowMap.getLightProjMatrixFar(),
                ShadowMap.getCascadeSplitDistance()
            )
        end

        profile(" shadows")
    end

    -- Draw skydome FIRST (always behind everything, follows camera)
    -- Select sky type based on mission: sunset for Mission 7, overcast for weather, normal otherwise
    profile(" skydome")
    local sky_type = "normal"
    if Mission.current_mission_num == 7 then
        sky_type = "sunset"
    elseif Weather.is_enabled() then
        sky_type = "overcast"
    end
    Skydome.draw(renderer, cam.pos.x, cam.pos.y, cam.pos.z, sky_type)
    profile(" skydome")

    -- Draw terrain (pass camera yaw for frustum culling)
    profile(" terrain")
    Heightmap.draw(renderer, cam.pos.x, cam.pos.z, nil, 80, cam.yaw)
    profile(" terrain")

    -- Draw trees (with distance and frustum culling)
    profile(" trees")
    Trees.draw(renderer, cam.pos.x, cam.pos.y, cam.pos.z, cam.yaw)
    profile(" trees")

    -- Draw buildings
    profile(" buildings")
    for _, building in ipairs(buildings) do
        Building.draw(building, renderer, cam.pos.x, cam.pos.z)
    end
    profile(" buildings")

    -- Draw landing pads
    profile(" pads")
    LandingPads.draw_all(renderer, cam.pos.x, cam.pos.z)
    profile(" pads")

    -- Draw cargo (mission cargo or free-flight cargo)
    profile(" cargo")
    if Mission.is_active() then
        Mission.draw_cargo(renderer, cam.pos.x, cam.pos.z)
    else
        for _, cargo in ipairs(cargo_items) do
            Cargo.draw(cargo, renderer, cam.pos.x, cam.pos.z)
        end
    end
    profile(" cargo")

    -- Draw ship
    profile(" ship")
    ship:draw(renderer)
    profile(" ship")

    -- Draw combat elements (Mission 6)
    if combat_active then
        -- Draw turret on ship
        Turret.draw(renderer, ship)

        -- Draw aliens
        Aliens.draw(renderer)
        Aliens.draw_debug(renderer)

        -- Draw bullets (pass viewMatrix for billboard math)
        Bullets.draw(renderer, viewMatrix, cam)
    end

    -- Draw smoke particles (disabled - billboard rendering needs fixing)
    -- smoke_system:draw(renderer, cam)

    -- Draw billboards (camera-facing smoke/particle quads) - must be before flush3D
    Billboard.draw(renderer, viewMatrix, cam)

    -- Draw rain as depth-tested 3D geometry (MUST be before flush3D for proper occlusion)
    Weather.draw_rain(renderer, cam, ship.vx, ship.vy, ship.vz)

    -- Flush 3D geometry (includes rain, terrain, ship - all depth tested together)
    renderer.flush3D()

    -- Draw 3D guide arrow for missions (anchored to camera pivot, depth tested against geometry)
    if Mission.is_active() then
        -- For combat mode (Mission 7): only draw arrow if there's a selected target
        -- For other missions: draw normal guide arrow
        if combat_active then
            local combat_target = HUD.get_target()
            if combat_target then
                Mission.draw_target_arrow(renderer, cam.pos.x, cam.pos.y, cam.pos.z, combat_target)
            end
            -- No arrow if no target selected in combat mode
        else
            Mission.draw_guide_arrow(renderer, cam.pos.x, cam.pos.y, cam.pos.z)
        end
        -- Draw 3D checkpoint markers for race mode
        Mission.draw_checkpoints(renderer, Heightmap, cam.pos.x, cam.pos.z)
    end

    -- Draw wind direction arrow (blue, length based on wind strength)
    Weather.draw_wind_arrow(renderer, cam.pos.x, cam.pos.y, cam.pos.z, ship.y)

    -- Draw speed lines (depth-tested 3D lines) - disabled during weather (rain acts as speed lines)
    if not Weather.is_enabled() then
        profile(" speedlines")
        speed_lines:draw(renderer, cam)
        profile(" speedlines")
    end

    -- Draw fireworks (celebratory effects for race lap/completion)
    Fireworks.draw(renderer)

    -- Draw minimap (pass mission cargo if active, otherwise free-flight cargo)
    profile(" minimap")
    local minimap_cargo = Mission.is_active() and Mission.cargo_objects or cargo_items
    local minimap_target = Mission.is_active() and Mission.get_target() or nil
    -- Pass race checkpoints if in race mode
    local race_checkpoints = Mission.race_checkpoints
    local current_checkpoint = Mission.race and Mission.race.current_checkpoint or 1
    -- Pass enemies if in combat mode
    local minimap_enemies = combat_active and Aliens.get_all() or nil
    Minimap.draw(renderer, Heightmap, ship, LandingPads, minimap_cargo, minimap_target, race_checkpoints, current_checkpoint, minimap_enemies)
    profile(" minimap")

    -- Draw HUD to software buffer (before blit)
    profile(" hud")
    local mission_data
    if Mission.is_active() then
        mission_data = Mission.get_hud_data()
        -- Update Mission 6 objectives with wave info
        if combat_active and not Mission.is_complete() then
            local wave = Aliens.get_wave()
            local total = Aliens.get_total_waves()
            local enemies = #Aliens.fighters + (Aliens.mother_ship and 1 or 0)
            mission_data.objectives[1] = "Wave " .. wave .. "/" .. total
            mission_data.objectives[2] = "Enemies: " .. enemies
            if wave == total and Aliens.mother_ship then
                mission_data.objectives[3] = "DESTROY THE MOTHER SHIP!"
            else
                mission_data.objectives[3] = ""
            end
        end
    else
        mission_data = {
            name = "FREE FLIGHT",
            objectives = {
                "Explore the terrain",
                "Practice landing on pads",
                "Collect cargo and deliver",
                "[Tab] Pause  [R] Reset"
            }
        }
    end
    HUD.draw(ship, cam, {
        game_mode = game_mode,
        mission = mission_data,
        mission_target = Mission.get_target(),
        current_location = nil,  -- TODO: detect current landing pad/building
        is_repairing = is_repairing,
        race_data = Mission.get_race_data(),  -- Race HUD data (nil if not in race)
        camera_mode = camera_mode  -- Current camera mode (follow/free/focus)
    })

    -- Draw combat HUD (targeting, mothership health bar)
    if combat_active then
        HUD.draw_combat_hud(Aliens.get_all(), Aliens.mother_ship)

        -- Draw target bracket around selected target
        local target = HUD.get_target()
        if target then
            HUD.draw_target_bracket_3d(target, cam, projMatrix, flight_scene.viewMatrix)
        end
    end

    -- Draw death screen overlay if ship is destroyed
    if ship_death_mode and ship_death_timer > 1.5 then
        -- Dark overlay
        renderer.drawRectFill(0, 0, config.RENDER_WIDTH, config.RENDER_HEIGHT, 0, 0, 0, 180)

        -- "SHIP DESTROYED" text
        local title = "SHIP DESTROYED"
        local title_x = config.RENDER_WIDTH / 2 - #title * 4
        local title_y = config.RENDER_HEIGHT / 2 - 30
        renderer.drawText(title_x, title_y, title, 255, 80, 80)

        -- Instructions
        local restart_text = "[R] Restart"
        local quit_text = "[Q] Quit to Menu"
        renderer.drawText(config.RENDER_WIDTH / 2 - #restart_text * 4, config.RENDER_HEIGHT / 2 + 10, restart_text, 255, 255, 255)
        renderer.drawText(config.RENDER_WIDTH / 2 - #quit_text * 4, config.RENDER_HEIGHT / 2 + 25, quit_text, 200, 200, 200)
    end

    -- Draw mission complete celebration panel (non-race missions)
    if mission_complete_mode then
        -- Panel dimensions
        local panel_width = 160
        local panel_height = 80
        local panel_x = (config.RENDER_WIDTH - panel_width) / 2
        local panel_y = (config.RENDER_HEIGHT - panel_height) / 2 - 20

        -- Draw panel background with border
        renderer.drawRectFill(panel_x - 2, panel_y - 2, panel_width + 4, panel_height + 4, 255, 215, 0, 255)  -- Gold border
        renderer.drawRectFill(panel_x, panel_y, panel_width, panel_height, 20, 40, 80, 240)  -- Dark blue background

        -- "MISSION COMPLETE" title
        local title = "MISSION COMPLETE!"
        local title_x = config.RENDER_WIDTH / 2 - #title * 4
        local title_y = panel_y + 12
        renderer.drawText(title_x, title_y, title, 255, 215, 0)  -- Gold text

        -- Mission name
        local mission_name = Mission.mission_name or "Mission"
        local name_x = config.RENDER_WIDTH / 2 - #mission_name * 4
        renderer.drawText(name_x, title_y + 18, mission_name, 255, 255, 255)

        -- Instructions
        local quit_text = "[Q] Return to Menu"
        local restart_text = "[R] Replay Mission"
        renderer.drawText(config.RENDER_WIDTH / 2 - #quit_text * 4, panel_y + panel_height - 28, quit_text, 200, 255, 200)
        renderer.drawText(config.RENDER_WIDTH / 2 - #restart_text * 4, panel_y + panel_height - 14, restart_text, 180, 180, 180)
    end
    profile(" hud")

    profile("present")
    -- Present the rendered frame to screen
    renderer.present()

    -- Draw lightning flash overlay (after present, directly to screen)
    Weather.draw_lightning_flash()
    profile("present")
end

function flight_scene.keypressed(key)
    -- Handle mission complete - Q to return to menu
    if Mission.is_complete() and key == "q" then
        Mission.reset()
        race_victory_mode = false  -- Reset victory mode
        mission_complete_mode = false  -- Reset mission complete mode
        Fireworks.reset()  -- Clear fireworks
        if combat_active then
            Aliens.reset()
            Bullets.reset()
            combat_active = false
        end
        local scene_manager = require("scene_manager")
        scene_manager.switch("menu")
        return
    end

    -- Handle pause menu actions first
    if HUD.is_paused() then
        if key == "q" then
            -- Return to menu from pause
            HUD.close_pause()
            Mission.reset()
            race_victory_mode = false  -- Reset victory mode
            mission_complete_mode = false  -- Reset mission complete mode
            Fireworks.reset()  -- Clear fireworks
            if combat_active then
                Aliens.reset()
                Bullets.reset()
                combat_active = false
            end
            local scene_manager = require("scene_manager")
            scene_manager.switch("menu")
            return
        elseif key == "tab" or key == "escape" then
            -- Resume game
            HUD.toggle_pause()
            return
        elseif key == "c" then
            -- Toggle controls visibility from pause menu
            HUD.toggle_controls()
            return
        end
        return  -- Block other keys while paused
    end

    -- Let HUD handle its keypresses (tab/escape for pause)
    HUD.keypressed(key)

    -- Handle G key to toggle weapons on/off in combat mode
    if key == "g" and combat_active then
        weapons_enabled = not weapons_enabled
        print("[WEAPONS] " .. (weapons_enabled and "ENABLED" or "DISABLED"))
        return
    end

    -- Handle T key for target cycling in combat mode
    if key == "t" and combat_active then
        local enemies = Aliens.get_all()
        local new_target = HUD.cycle_target(enemies)
        if new_target then
            Turret.target = new_target
        end
        return
    end

    -- Handle F key to cycle camera modes (follow -> free -> focus)
    -- If follow mode is disabled, cycle only between free and focus
    if key == "f" then
        if camera_mode == "follow" then
            camera_mode = "free"
            print("[CAMERA] Switched to FREE mode")
        elseif camera_mode == "free" then
            camera_mode = "focus"
            print("[CAMERA] Switched to FOCUS mode")
        else
            -- From focus, go to follow only if enabled, otherwise go to free
            if config.CAMERA_FOLLOW_MODE_ENABLED then
                camera_mode = "follow"
                follow_cam_debug_timer = 4.5  -- Print debug soon after switching
                print("[CAMERA] Switched to FOLLOW mode")
            else
                camera_mode = "free"
                print("[CAMERA] Switched to FREE mode")
            end
        end
        return
    end

    -- Handle Q key in death mode - quit to menu
    if key == "q" and ship_death_mode then
        ship_death_mode = false
        Mission.reset()
        Billboard.reset()
        Fireworks.reset()
        if combat_active then
            Aliens.reset()
            Bullets.reset()
            combat_active = false
        end
        local scene_manager = require("scene_manager")
        scene_manager.switch("menu")
        return
    end

    if key == "r" then
        -- Reset ship to first landing pad
        local spawn_x, spawn_y, spawn_z, spawn_yaw = LandingPads.get_spawn(1)
        ship:reset(spawn_x, spawn_y, spawn_z, spawn_yaw)

        -- Reset camera rotation
        cam.pitch = 0
        cam.yaw = 0

        -- Reset death state
        ship_death_mode = false
        ship_death_timer = 0
        ship_death_landed = false
        repair_timer = 0
        is_repairing = false
        Billboard.reset()

        -- Reset victory mode and fireworks
        race_victory_mode = false
        mission_complete_mode = false
        Fireworks.reset()

        -- Reset mission or race if active
        if Mission.is_active() then
            Mission.reset()
            if current_mission_num then
                Missions.start(current_mission_num, Mission)
                -- Restart mission music
                AudioManager.start_level_music(current_mission_num)

                -- Reset combat for Mission 7
                if current_mission_num == 7 then
                    Aliens.reset()
                    Bullets.reset()
                    Turret.reset()
                    wave_start_delay = 2.0
                end
            elseif current_track_num then
                Missions.start_race_track(current_track_num, Mission)
                -- Restart racing music
                AudioManager.start_level_music(7)
            end
        end

        -- Reset free-flight cargo
        for _, cargo in ipairs(cargo_items) do
            cargo.state = "idle"
            cargo.x = 15
            cargo.z = 10
            cargo.y = Heightmap.get_height(15, 10) + 0.5
            cargo.attached_to_ship = false
            cargo.collected = false
        end
    end

    -- B key - spawn test billboard above ship (free flight only)
    -- if key == "b" and not Mission.is_active() then
    --     Billboard.spawn(ship.x, ship.y + 0.2, ship.z, 0.5, 3.0)
    --     print("Spawned billboard at ship position")
    -- end
end

-- Called when leaving the flight scene
function flight_scene.unload()
    -- Stop all audio when leaving flight scene
    AudioManager.stop_thruster()
    AudioManager.stop_music()
end

return flight_scene
