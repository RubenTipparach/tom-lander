-- Flight Scene: Main game scene with terrain, ship, and objects
-- Camera and controls ported from Picotron version

local config = require("config")
local renderer = require("renderer")
local camera_module = require("camera")
local mat4 = require("mat4")
local vec3 = require("vec3")
local quat = require("quat")
local Ship = require("game.ship")
local ParticleSystem = require("particle_system")
local SpeedLines = require("game.speed_lines")
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
local controls = require("input.controls")

local flight_scene = {}

-- Consolidate all mutable state into a single table to reduce upvalues
local S = {
    -- Scene objects
    ship = nil,
    cam = nil,
    smoke_system = nil,
    speed_lines = nil,
    softwareImage = nil,
    projMatrix = nil,
    -- Camera state
    camera_mode = config.CAMERA_FOLLOW_MODE_ENABLED and "follow" or "free",
    prev_camera_mode = config.CAMERA_FOLLOW_MODE_ENABLED and "follow" or "free",
    cam_dist = config.CAMERA_DISTANCE_MIN,
    last_mouse_x = 0,
    last_mouse_y = 0,
    mouse_camera_enabled = false,
    follow_cam_debug_timer = 0,
    cam_orientation = nil,
    -- World objects
    buildings = {},
    building_configs = {},
    cargo_items = {},
    -- Game mode and mission
    game_mode = "arcade",
    current_mission_num = nil,
    current_track_num = nil,
    -- Combat state
    combat_active = false,
    wave_start_delay = 0,
    weapons_enabled = true,
    -- Race victory state
    race_victory_mode = false,
    race_victory_cam_angle = 0,
    race_victory_ship_pos = {x = 0, y = 0, z = 0},
    race_victory_timer = 0,
    -- Mission complete state
    mission_complete_mode = false,
    mission_complete_cam_angle = 0,
    mission_complete_ship_pos = {x = 0, y = 0, z = 0},
    mission_complete_timer = 0,
    -- Ship death state
    ship_death_mode = false,
    ship_death_timer = 0,
    ship_death_explosion_count = 0,
    ship_death_pos = {x = 0, y = 0, z = 0},
    ship_death_landed = false,
    -- Altitude warning
    altitude_warning_active = false,
    altitude_warning_timer = 0,
    altitude_limit = nil,
    -- Repair state
    repair_timer = 0,
    is_repairing = false,
}

-- Camera config constants (read-only, kept as locals for performance)
local cam_rot_speed = config.CAMERA_ROTATION_SPEED
local camera_lerp_speed = config.CAMERA_LERP_SPEED
local camera_zoom_speed = config.CAMERA_ZOOM_SPEED
local mouse_sensitivity = config.CAMERA_MOUSE_SENSITIVITY

-- Helper function: Restart from death/failed state
local function do_restart_from_death()
    local spawn_x, spawn_y, spawn_z, spawn_yaw = LandingPads.get_spawn(1)
    S.ship:reset(spawn_x, spawn_y, spawn_z, spawn_yaw)
    S.cam.pitch = 0
    S.cam.yaw = 0
    S.ship_death_mode = false
    S.ship_death_timer = 0
    S.ship_death_landed = false
    S.repair_timer = 0
    S.is_repairing = false
    Billboard.reset()
    S.race_victory_mode = false
    S.race_victory_timer = 0
    S.mission_complete_mode = false
    S.mission_complete_timer = 0
    S.ship.invulnerable = false
    Fireworks.reset()
    if Mission.is_active() then
        Mission.reset()
        if S.current_mission_num then
            Missions.start(S.current_mission_num, Mission)
            HUD.set_mission(S.current_mission_num)
            AudioManager.start_level_music(S.current_mission_num)
            if S.current_mission_num == 7 then
                Aliens.reset()
                Bullets.reset()
                Turret.reset()
                S.wave_start_delay = 2.0
            end
        elseif S.current_track_num then
            Missions.start_race_track(S.current_track_num, Mission)
            AudioManager.start_level_music(7)
        end
    end
end

-- Helper function: Quit to menu from any game state
local function do_quit_to_menu()
    S.ship_death_mode = false
    Mission.reset()
    Billboard.reset()
    S.race_victory_mode = false
    S.race_victory_timer = 0
    S.mission_complete_mode = false
    S.mission_complete_timer = 0
    S.ship.invulnerable = false
    Fireworks.reset()
    if S.combat_active then
        Aliens.reset()
        Bullets.reset()
        S.combat_active = false
    end
    local scene_manager = require("scene_manager")
    scene_manager.switch("menu")
end

function flight_scene.load()
    print("[FLIGHT] Flight scene loaded - camera mode: " .. S.camera_mode)
    -- Stop menu music when entering flight scene
    AudioManager.stop_music()

    -- Renderer already initialized in main.lua
    -- S.softwareImage only needed for DDA renderer (GPU renderer handles its own presentation)
    local imageData = renderer.getImageData()
    if imageData then
        S.softwareImage = love.graphics.newImage(imageData)
        S.softwareImage:setFilter("nearest", "nearest")  -- Pixel-perfect upscaling
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
    S.projMatrix = mat4.perspective(config.FOV, aspect, config.NEAR_PLANE, config.FAR_PLANE)

    -- Get game mode and mission from menu to determine which map to load
    local menu = require("menu")
    local selected_map = menu.selected_map or config.CURRENT_MAP

    -- Initialize heightmap with selected map
    Heightmap.init(selected_map)

    -- Reset minimap cache for new map
    Minimap.reset_cache()

    -- Initialize skydome
    Skydome.init()

    -- Generate trees (only for maps with grass/vegetation)
    local map_config = Heightmap.get_map_config()

    -- Set altitude limit from map config (nil = no limit)
    S.altitude_limit = map_config and map_config.altitude_limit or nil
    S.altitude_warning_active = false
    S.altitude_warning_timer = 0

    if map_config and map_config.has_grass then
        Trees.generate(Heightmap)
    else
        Trees.clear()  -- No trees on desert maps
    end

    -- Clear and create landing pads from map config
    LandingPads.clear()

    if map_config and map_config.landing_pads then
        -- Load landing pads from map configuration
        for _, pad_def in ipairs(map_config.landing_pads) do
            local pad_x, pad_z = Constants.aseprite_to_world(pad_def.x, pad_def.z)
            LandingPads.create_pad({
                id = pad_def.id,
                name = Constants.LANDING_PAD_NAMES[pad_def.id] or ("Landing Pad " .. pad_def.id),
                x = pad_x,
                z = pad_z,
                base_y = Heightmap.get_height(pad_x, pad_z),
                scale = 0.5
            })
        end
    else
        -- Fallback: Create default landing pads for act1 (matching Picotron exactly)
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
    end

    -- Get spawn position from first landing pad
    local spawn_x, spawn_y, spawn_z, spawn_yaw = LandingPads.get_spawn(1)

    -- Create S.ship at landing pad
    S.ship = Ship.new({
        spawn_x = spawn_x or 0,
        spawn_y = spawn_y or 10,
        spawn_z = spawn_z or 0,
        spawn_yaw = spawn_yaw or 0
    })

    -- Register S.ship for damage smoke effects
    Explosion.register_damage_smoke("player_ship", function()
        return S.ship.x, S.ship.y, S.ship.z
    end)

    -- Create S.buildings (matching Picotron exactly)
    S.building_configs = {
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
    S.buildings = Building.create_city(S.building_configs, Heightmap)

    -- Set up mission system references
    Mission.LandingPads = LandingPads
    Missions.buildings = S.buildings
    Missions.building_configs = S.building_configs

    -- Get game mode and mission from menu (menu already required above)
    S.game_mode = menu.game_mode or "arcade"
    S.current_mission_num = menu.selected_mission  -- nil for free flight
    S.current_track_num = menu.selected_track      -- nil if not racing

    -- Create cargo items (only for free flight mode)
    S.cargo_items = {}
    if not S.current_mission_num and not S.current_track_num then
        -- Free flight mode - spawn a test cargo
        table.insert(S.cargo_items, Cargo.create({
            id = 1,
            x = 15,
            z = 10,
            base_y = Heightmap.get_height(15, 10),
            scale = 0.5
        }))
    end

    -- Start mission or race if selected
    if S.current_mission_num then
        Missions.start(S.current_mission_num, Mission)
        HUD.set_mission(S.current_mission_num)
        -- Start mission-specific music
        AudioManager.start_level_music(S.current_mission_num)
    elseif S.current_track_num then
        Missions.start_race_track(S.current_track_num, Mission)
        HUD.set_mission(8)  -- Race missions use mission 8+ settings (hide controls/goals by default)
        -- Racing mode defaults to focus camera (looks at next checkpoint)
        S.camera_mode = "focus"
        -- Racing mode uses mission 7 music mapping
        AudioManager.start_level_music(7)
    else
        -- Free flight - clear all mission/race state first
        Mission.reset()
        -- Then set up free flight mode with countdown
        Mission.active = true  -- Mark as active for countdown to work
        Mission.type = "free_flight"  -- Mark as free flight mode
        Mission.countdown = {
            active = true,
            timer = Mission.COUNTDOWN_DURATION,
        }
    end

    -- Initialize combat systems for Mission 7 (Alien Invasion)
    S.combat_active = (S.current_mission_num == 7)
    if S.combat_active then
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
        S.wave_start_delay = 2.0
    end

    -- Create camera (matching Picotron initial state)
    -- Camera starts at S.ship position, offset is applied during rendering
    S.cam = camera_module.new(spawn_x or 0, (spawn_y or 3), (spawn_z or 0) - 8)
    S.cam.pitch = 0  -- rx in Picotron
    S.cam.yaw = 0    -- ry in Picotron
    camera_module.updateVectors(S.cam)

    -- Create smoke particle system
    S.smoke_system = ParticleSystem.new({
        size = 0.3,
        max_particles = 20,
        lifetime = 0.5,  -- Short lifetime for quick puffs
        sprite_id = Constants.SPRITE_SMOKE,
        use_billboards = true
    })

    -- Create speed lines system
    S.speed_lines = SpeedLines.new()

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

    -- Initialize controls system
    controls.init()

    print("Flight scene loaded")
    print("Controls: Use " .. (controls.has_gamepad() and "gamepad or keyboard" or "keyboard"))
end

function flight_scene.update(dt)
    profile("update")

    -- Check for gamepad pause toggle (Start button)
    -- This needs to happen before the paused check so we can unpause too
    if controls.just_pressed("pause") then
        HUD.toggle_pause()
    end

    -- Check for gamepad goals toggle (D-Pad Up)
    if controls.just_pressed("toggle_goals") then
        HUD.toggle_goal_box()
    end

    -- Check for camera cycle (D-Pad Right or F key)
    if controls.just_pressed("camera_cycle") then
        if S.camera_mode == "follow" then
            S.camera_mode = "free"
            print("[CAMERA] Switched to FREE mode")
        elseif S.camera_mode == "free" then
            S.camera_mode = "focus"
            print("[CAMERA] Switched to FOCUS mode")
        else
            -- From focus, go to follow only if enabled, otherwise go to free
            if config.CAMERA_FOLLOW_MODE_ENABLED then
                S.camera_mode = "follow"
                S.follow_cam_debug_timer = 4.5  -- Print debug soon after switching
                print("[CAMERA] Switched to FOLLOW mode")
            else
                S.camera_mode = "free"
                print("[CAMERA] Switched to FREE mode")
            end
        end
    end

    -- Handle death mode (Y to restart, B to quit) - gamepad support
    if S.ship_death_mode and S.ship_death_timer > 1.5 then
        if controls.just_pressed("restart") then
            do_restart_from_death()
            profile("update")
            return
        end
        if controls.just_pressed("quit_to_menu") then
            do_quit_to_menu()
            profile("update")
            return
        end
    end

    -- Handle race failed (Y to restart, B to quit) - gamepad support
    if Mission.is_race_failed() then
        if controls.just_pressed("restart") then
            flight_scene.load()
            profile("update")
            return
        end
        if controls.just_pressed("quit_to_menu") then
            do_quit_to_menu()
            profile("update")
            return
        end
    end

    -- Handle mission complete (Y to replay, B to quit) - gamepad support
    if S.mission_complete_mode and S.mission_complete_timer > config.VICTORY_DELAY then
        if controls.just_pressed("restart") then
            do_quit_to_menu()  -- Reset state first
            flight_scene.load()
            profile("update")
            return
        end
        if controls.just_pressed("quit_to_menu") then
            do_quit_to_menu()
            profile("update")
            return
        end
    end

    -- Handle pause menu actions
    if HUD.is_paused() then
        -- Check for quit to menu (B button on gamepad)
        if controls.just_pressed("quit_to_menu") then
            HUD.close_pause()
            Mission.reset()
            S.race_victory_mode = false
            S.race_victory_timer = 0
            S.mission_complete_mode = false
            S.mission_complete_timer = 0
            S.ship.invulnerable = false
            Fireworks.reset()
            if S.combat_active then
                Aliens.reset()
                Bullets.reset()
                S.combat_active = false
            end
            local scene_manager = require("scene_manager")
            scene_manager.switch("menu")
        end
        profile("update")
        return
    end

    -- Check for lap completion - trigger small fireworks
    if Mission.lap_just_completed then
        Mission.lap_just_completed = false
        -- Launch fireworks around the S.ship
        Fireworks.burst(S.ship.x, S.ship.y, S.ship.z, 3, 0.8)
    end

    -- Check for race completion - trigger big celebration fireworks
    if Mission.race_just_completed then
        Mission.race_just_completed = false
        -- Big fireworks celebration!
        Fireworks.celebrate(S.ship.x, S.ship.y, S.ship.z)
    end

    -- Check if race just completed - enter victory mode
    if Mission.race_complete and not S.race_victory_mode then
        S.race_victory_mode = true
        S.race_victory_cam_angle = S.cam.yaw  -- Start from current camera angle
        S.race_victory_ship_pos = {x = S.ship.x, y = S.ship.y, z = S.ship.z}
        S.race_victory_timer = 0
        -- Ship becomes invulnerable but gameplay continues for 3 seconds
        S.ship.invulnerable = true
    end

    -- Check if non-race mission just completed - start victory sequence
    if Mission.is_complete() and not S.race_victory_mode and not S.mission_complete_mode and Mission.type ~= "race" then
        S.mission_complete_mode = true
        S.mission_complete_cam_angle = S.cam.yaw  -- Start from current camera angle
        S.mission_complete_ship_pos = {x = S.ship.x, y = S.ship.y, z = S.ship.z}
        S.mission_complete_timer = 0
        -- Ship becomes invulnerable but gameplay continues for 3 seconds
        S.ship.invulnerable = true
    end

    -- Race victory mode: delay then freeze S.ship and orbit camera
    if S.race_victory_mode then
        S.race_victory_timer = S.race_victory_timer + dt

        -- Delay: gameplay continues normally, S.ship just invulnerable
        if S.race_victory_timer <= config.VICTORY_DELAY then
            -- During delay: update saved S.ship position for when we freeze it
            S.race_victory_ship_pos = {x = S.ship.x, y = S.ship.y, z = S.ship.z}
            -- Normal update continues (no early return)
        else
            -- AFTER delay: freeze S.ship and orbit camera
            -- Disable camera distance offset for clean orbit
            S.cam_dist = 0

            -- Freeze S.ship at saved victory position
            S.ship.x = S.race_victory_ship_pos.x
            S.ship.y = S.race_victory_ship_pos.y
            S.ship.z = S.race_victory_ship_pos.z
            S.ship.vx = 0
            S.ship.vy = 0
            S.ship.vz = 0

            -- Keep thrusters active for flame animation
            for _, thruster in ipairs(S.ship.thrusters) do
                thruster.active = true
            end

            -- Update fireworks during victory celebration
            Fireworks.update(dt)

            -- Launch more fireworks periodically during victory
            if math.random() < dt * config.VICTORY_FIREWORK_RATE then
                local angle = math.random() * math.pi * 2
                local dist = 8 + math.random() * 8
                Fireworks.launch(
                    S.ship.x + math.sin(angle) * dist,
                    S.ship.y - 2,
                    S.ship.z + math.cos(angle) * dist,
                    1.2
                )
            end

            -- Orbit camera around S.ship
            S.race_victory_cam_angle = S.race_victory_cam_angle + dt * config.VICTORY_ORBIT_SPEED

            -- Calculate camera position on orbit
            S.cam.pos.x = S.ship.x + math.sin(S.race_victory_cam_angle) * config.VICTORY_ORBIT_DISTANCE
            S.cam.pos.y = S.ship.y + config.VICTORY_ORBIT_HEIGHT
            S.cam.pos.z = S.ship.z + math.cos(S.race_victory_cam_angle) * config.VICTORY_ORBIT_DISTANCE

            -- Point camera at S.ship (use same formula as focus camera)
            local dx = S.ship.x - S.cam.pos.x
            local dz = S.ship.z - S.cam.pos.z
            local dy = S.ship.y - S.cam.pos.y
            local dist_xz = math.sqrt(dx * dx + dz * dz)
            S.cam.yaw = math.atan2(dx, -dz)
            -- Calculate pitch to look at S.ship, clamped to ±90 degrees
            local max_pitch = math.pi / 2 - 0.01
            S.cam.pitch = math.max(-max_pitch, math.min(max_pitch, math.atan2(dy, dist_xz)))

            camera_module.updateVectors(S.cam)
            profile("update")
            return  -- Only return early AFTER the delay
        end
    end

    -- Mission complete mode: delay then freeze S.ship and orbit camera
    if S.mission_complete_mode then
        S.mission_complete_timer = S.mission_complete_timer + dt

        -- Delay: gameplay continues normally, S.ship just invulnerable
        if S.mission_complete_timer <= config.VICTORY_DELAY then
            -- During delay: update saved S.ship position for when we freeze it
            S.mission_complete_ship_pos = {x = S.ship.x, y = S.ship.y, z = S.ship.z}
            -- Normal update continues (no early return)
        else
            -- AFTER delay: freeze S.ship and orbit camera
            -- Disable camera distance offset for clean orbit
            S.cam_dist = 0

            -- Freeze S.ship at saved victory position
            S.ship.x = S.mission_complete_ship_pos.x
            S.ship.y = S.mission_complete_ship_pos.y
            S.ship.z = S.mission_complete_ship_pos.z
            S.ship.vx = 0
            S.ship.vy = 0
            S.ship.vz = 0

            -- Keep thrusters active for flame animation
            for _, thruster in ipairs(S.ship.thrusters) do
                thruster.active = true
            end

            -- Update fireworks during victory celebration
            Fireworks.update(dt)

            -- Launch more fireworks periodically during victory
            if math.random() < dt * config.VICTORY_FIREWORK_RATE then
                local angle = math.random() * math.pi * 2
                local dist = 8 + math.random() * 8
                Fireworks.launch(
                    S.ship.x + math.sin(angle) * dist,
                    S.ship.y - 2,
                    S.ship.z + math.cos(angle) * dist,
                    1.2
                )
            end

            -- Orbit camera around S.ship
            S.mission_complete_cam_angle = S.mission_complete_cam_angle + dt * config.VICTORY_ORBIT_SPEED

            -- Calculate camera position on orbit
            S.cam.pos.x = S.ship.x + math.sin(S.mission_complete_cam_angle) * config.VICTORY_ORBIT_DISTANCE
            S.cam.pos.y = S.ship.y + config.VICTORY_ORBIT_HEIGHT
            S.cam.pos.z = S.ship.z + math.cos(S.mission_complete_cam_angle) * config.VICTORY_ORBIT_DISTANCE

            -- Point camera at S.ship (use same formula as focus camera)
            local dx = S.ship.x - S.cam.pos.x
            local dz = S.ship.z - S.cam.pos.z
            local dy = S.ship.y - S.cam.pos.y
            local dist_xz = math.sqrt(dx * dx + dz * dz)
            S.cam.yaw = math.atan2(dx, -dz)
            -- Calculate pitch to look at S.ship, clamped to ±90 degrees
            local max_pitch = math.pi / 2 - 0.01
            S.cam.pitch = math.max(-max_pitch, math.min(max_pitch, math.atan2(dy, dist_xz)))

            camera_module.updateVectors(S.cam)
            profile("update")
            return  -- Only return early AFTER the delay
        end
    end

    -- Check altitude limit (for maps with altitude restrictions like canyon)
    if S.altitude_limit and not S.ship_death_mode then
        local map_config = Heightmap.get_map_config()
        local warning_time = map_config and map_config.altitude_warning_time or 5

        if S.ship.y > S.altitude_limit then
            -- Over the limit - start or continue countdown
            if not S.altitude_warning_active then
                S.altitude_warning_active = true
                S.altitude_warning_timer = warning_time
            else
                S.altitude_warning_timer = S.altitude_warning_timer - dt
                if S.altitude_warning_timer <= 0 then
                    -- Time's up!
                    if Mission.type == "race" then
                        -- In race mode, fail the race instead of destroying S.ship
                        Mission.fail_race_altitude()
                    else
                        -- Regular mode - destroy the S.ship
                        S.ship.hull_health = 0
                    end
                    S.altitude_warning_active = false
                end
            end
        else
            -- Back under limit - cancel warning
            if S.altitude_warning_active then
                S.altitude_warning_active = false
                S.altitude_warning_timer = 0
            end
        end
    end

    -- Check for S.ship death FIRST (before physics update)
    if S.ship:is_destroyed() and not S.ship_death_mode then
        S.ship_death_mode = true
        S.ship_death_timer = 0
        S.ship_death_explosion_count = 0
        S.ship_death_pos = {x = S.ship.x, y = S.ship.y, z = S.ship.z}
        S.ship_death_landed = false

        -- Don't freeze - let it fall! Just stop rotation controls
        S.ship.local_vpitch = 0
        S.ship.local_vyaw = 0
        S.ship.local_vroll = 0

        -- Spawn the big death explosion
        Explosion.spawn_death(S.ship.x, S.ship.y, S.ship.z, config.EXPLOSION_DEATH_SCALE or 2.5)
        AudioManager.play_sfx(3)  -- Explosion sound
        AudioManager.play_death_sound()  -- "You died" voice
        AudioManager.stop_thruster()  -- Stop thruster sound
    end

    -- Handle death sequence - S.ship falls with gravity until hitting ground
    if S.ship_death_mode then
        S.ship_death_timer = S.ship_death_timer + dt

        -- Stop rotation controls but allow falling
        S.ship.local_vpitch = 0
        S.ship.local_vyaw = 0
        S.ship.local_vroll = 0

        if not S.ship_death_landed then
            -- Apply gravity
            local gravity = config.GRAVITY or 0.15
            S.ship.vy = S.ship.vy - gravity * dt * 60

            -- Apply some air resistance to horizontal movement
            S.ship.vx = S.ship.vx * 0.99
            S.ship.vz = S.ship.vz * 0.99

            -- Update position
            S.ship.x = S.ship.x + S.ship.vx * dt * 60
            S.ship.y = S.ship.y + S.ship.vy * dt * 60
            S.ship.z = S.ship.z + S.ship.vz * dt * 60

            -- Check for ground collision
            local ground_height = Heightmap.get_height(S.ship.x, S.ship.z)
            local ship_ground_offset = config.VTOL_COLLISION_HEIGHT + config.VTOL_COLLISION_OFFSET_Y

            if S.ship.y < ground_height + ship_ground_offset then
                -- Hit the ground - stop falling
                S.ship.y = ground_height + ship_ground_offset
                S.ship.vx = 0
                S.ship.vy = 0
                S.ship.vz = 0
                S.ship_death_landed = true

                -- Spawn crash explosion on impact
                Explosion.spawn_impact(S.ship.x, S.ship.y, S.ship.z, 1.0)
                AudioManager.play_sfx(3)  -- Explosion sound
            end
        end

        -- Spawn additional explosions during death sequence (while falling)
        if S.ship_death_timer < 2.0 and math.random() < dt * 3 then
            local offset_x = (math.random() - 0.5) * 3
            local offset_y = (math.random() - 0.5) * 2
            local offset_z = (math.random() - 0.5) * 3
            Explosion.spawn_impact(
                S.ship.x + offset_x,
                S.ship.y + offset_y,
                S.ship.z + offset_z,
                0.5 + math.random() * 0.5
            )
        end

        -- Update billboards and particles even during death
        Billboard.update(dt)
        S.smoke_system:update(dt)

        -- Update damage smoke (shows S.ship is destroyed)
        Explosion.update_damage_smoke("player_ship", 0, dt)

        -- After death sequence, show death screen (handled in draw)
        -- Player can press R to restart or Q to quit
        profile("update")
        return
    end

    -- Disable S.ship controls during race countdown or when race is failed
    S.ship.controls_disabled = Mission.is_countdown_active() or Mission.is_race_failed()

    -- Update S.ship physics (only when alive)
    S.ship:update(dt)

    -- Update damage smoke based on hull percentage
    local hull_percent = S.ship:get_hull_percent()
    Explosion.update_damage_smoke("player_ship", hull_percent, dt)

    -- Ground damping constants
    local GROUND_VELOCITY_DAMPING = 0.9  -- Extra damping when grounded

    -- Track highest ground level (terrain or landing pad)
    local ground_height = Heightmap.get_height(S.ship.x, S.ship.z)
    local is_grounded = false

    -- Check landing pad surfaces first (they can be higher than terrain)
    for _, pad in ipairs(LandingPads.get_all()) do
        if pad.collision then
            local bounds = pad.collision:get_bounds()

            if Collision.point_in_box(S.ship.x, S.ship.z, pad.x, pad.z, bounds.half_width, bounds.half_depth) then
                -- Ship is horizontally over landing pad
                -- Check if S.ship is within the vertical bounds (side collision)
                if S.ship.y > bounds.bottom and S.ship.y < bounds.top then
                    -- Side collision - push out
                    S.ship.x, S.ship.z = Collision.push_out_of_box(
                        S.ship.x, S.ship.z,
                        pad.x, pad.z,
                        bounds.half_width, bounds.half_depth
                    )
                    S.ship.vx = S.ship.vx * 0.5
                    S.ship.vz = S.ship.vz * 0.5
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

    for _, building in ipairs(S.buildings) do
        local half_width = building.width / 2
        local half_depth = building.depth / 2
        local building_height = building.height
        local building_top = building.y + building_height
        local building_bottom = building.y

        -- Check if S.ship's bounding box overlaps with building
        local ship_half_height = config.VTOL_COLLISION_HEIGHT
        local ship_bottom = S.ship.y - ship_half_height + config.VTOL_COLLISION_OFFSET_Y
        local ship_top = S.ship.y + ship_half_height + config.VTOL_COLLISION_OFFSET_Y
        if Collision.box_overlap(S.ship.x, S.ship.z, ship_half_width, ship_half_depth,
                                  building.x, building.z, half_width, half_depth) then
            -- Ship is horizontally inside building bounds
            -- Check if S.ship center is above building top (landing from above)
            -- Use small tolerance to prevent edge-case side collisions when landing
            local roof_tolerance = 0.1
            if S.ship.y > building_top - roof_tolerance then
                -- Ship is above building - rooftop is a landing surface
                if building_top > ground_height then
                    ground_height = building_top
                end
            elseif ship_bottom < building_top and ship_top > building_bottom then
                -- Side collision: S.ship is inside building volume - push out
                local old_x, old_z = S.ship.x, S.ship.z
                S.ship.x, S.ship.z = Collision.push_out_of_box(
                    S.ship.x, S.ship.z,
                    building.x, building.z,
                    half_width, half_depth
                )

                -- Calculate bounce direction (away from building)
                local push_dx = S.ship.x - old_x
                local push_dz = S.ship.z - old_z
                local push_len = math.sqrt(push_dx * push_dx + push_dz * push_dz)

                -- Damage based on collision speed (configurable multiplier)
                local collision_speed = math.sqrt(S.ship.vx*S.ship.vx + S.ship.vy*S.ship.vy + S.ship.vz*S.ship.vz)
                if collision_speed > 0.05 then
                    local damage = collision_speed * (config.SHIP_COLLISION_DAMAGE_MULTIPLIER or 20)
                    S.ship:take_damage(damage)
                    -- Spawn impact explosion
                    Explosion.spawn_impact(S.ship.x, S.ship.y, S.ship.z, config.EXPLOSION_IMPACT_SCALE or 0.8)
                    AudioManager.play_sfx(8)  -- Collision sound
                end

                -- Bounce off building - reverse and reduce velocity, add push force
                local bounce_factor = 0.5  -- How much velocity is preserved (reversed)
                local push_force = math.max(collision_speed * 0.3, 0.05)  -- Minimum push to escape

                if push_len > 0.001 then
                    -- Normalize push direction and apply bounce
                    local nx, nz = push_dx / push_len, push_dz / push_len
                    S.ship.vx = -S.ship.vx * bounce_factor + nx * push_force
                    S.ship.vz = -S.ship.vz * bounce_factor + nz * push_force
                else
                    -- Fallback: just reverse velocity
                    S.ship.vx = -S.ship.vx * bounce_factor
                    S.ship.vz = -S.ship.vz * bounce_factor
                end
            end
        end
    end

    -- Apply ground collision
    local ship_ground_offset = config.VTOL_COLLISION_HEIGHT + config.VTOL_COLLISION_OFFSET_Y
    local landing_height = ground_height + ship_ground_offset

    if S.ship.y < landing_height then
        -- Check for water collision (instant death) - skip if invulnerable
        if Heightmap.is_water(S.ship.x, S.ship.z) and not S.ship.invulnerable then
            -- Water collision = instant death explosion
            Explosion.spawn_death(S.ship.x, S.ship.y, S.ship.z, config.EXPLOSION_DEATH_SCALE or 2.5)
            AudioManager.play_sfx(3)  -- Explosion sound
            S.ship.health = 0  -- Kill the S.ship
        elseif not Heightmap.is_water(S.ship.x, S.ship.z) then
            local vertical_speed = math.abs(S.ship.vy)
            local horizontal_speed = math.sqrt(S.ship.vx * S.ship.vx + S.ship.vz * S.ship.vz)

            -- Calculate orientation damage multiplier
            -- Ship's local up vector (0, 1, 0) transformed to world space
            -- If S.ship is upright, world_up_y will be close to 1
            -- If S.ship is upside down, world_up_y will be close to -1
            -- If S.ship is on its side, world_up_y will be close to 0
            local _, world_up_y, _ = quat.rotateVector(S.ship.orientation, 0, 1, 0)

            -- Orientation multiplier based on S.ship orientation
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
                S.ship:take_damage(damage)
                -- Spawn impact explosion for hard landings
                if vertical_speed > explosion_threshold then
                    local explosion_scale = (config.EXPLOSION_IMPACT_SCALE or 0.8) * math.min(orientation_multiplier, 3)
                    Explosion.spawn_impact(S.ship.x, S.ship.y, S.ship.z, explosion_scale)
                    AudioManager.play_sfx(8)  -- Collision sound
                end
            end

            -- Horizontal ground scraping damage (dragging along ground)
            local scrape_threshold = config.SHIP_GROUND_SCRAPE_THRESHOLD or 0.08
            if horizontal_speed > scrape_threshold then
                local scrape_damage = horizontal_speed * (config.SHIP_COLLISION_DAMAGE_MULTIPLIER or 20) * 0.5
                local speed_factor = 1 + (horizontal_speed * 5)
                S.ship:take_damage(scrape_damage * speed_factor * orientation_multiplier)
                -- Spawn sparks/small explosion for fast scraping
                if horizontal_speed > scrape_threshold * 2 then
                    Explosion.spawn_impact(S.ship.x, S.ship.y, S.ship.z, 0.4)
                    AudioManager.play_sfx(8)  -- Collision sound
                end
            end
        end

        -- Snap to ground and zero vertical velocity
        S.ship.y = landing_height
        S.ship.vy = 0
        is_grounded = true

        -- Extra horizontal damping when grounded to prevent sliding
        S.ship.vx = S.ship.vx * GROUND_VELOCITY_DAMPING
        S.ship.vz = S.ship.vz * GROUND_VELOCITY_DAMPING
    end

    -- Update cargo (pass quaternion orientation for gimbal-lock-free rotation)
    -- Only update free-flight cargo if in free flight mode
    if Mission.type == "free_flight" then
        for _, cargo in ipairs(S.cargo_items) do
            Cargo.update(cargo, dt, S.ship.x, S.ship.y, S.ship.z, S.ship.orientation)
        end
    end

    -- Check for landing (returns the pad the S.ship is currently on, or nil)
    local current_landing_pad = LandingPads.check_landing(S.ship.x, S.ship.y, S.ship.z, S.ship.vy)

    -- Update mission system
    if Mission.is_active() then
        Mission.update(dt, S.ship, current_landing_pad)
    end

    -- Free flight cargo delivery
    if Mission.type == "free_flight" and current_landing_pad and S.cargo_items[1] and Cargo.is_attached(S.cargo_items[1]) then
        Cargo.deliver(S.cargo_items[1])
        print("Cargo delivered to " .. current_landing_pad.name .. "!")
    end

    -- Landing pad repair system
    S.is_repairing = false
    if current_landing_pad and is_grounded then
        -- Calculate total velocity
        local total_velocity = math.sqrt(S.ship.vx*S.ship.vx + S.ship.vy*S.ship.vy + S.ship.vz*S.ship.vz)
        local velocity_threshold = config.SHIP_REPAIR_VELOCITY_THRESHOLD or 0.05

        if total_velocity < velocity_threshold then
            -- Ship is stationary on landing pad
            S.repair_timer = S.repair_timer + dt
            local repair_delay = config.SHIP_REPAIR_DELAY or 1.0

            -- Start repairing after delay
            if S.repair_timer >= repair_delay and S.ship.health < S.ship.max_health then
                S.is_repairing = true
                local repair_rate = config.SHIP_REPAIR_RATE or 20
                local repair_amount = repair_rate * dt
                S.ship.health = math.min(S.ship.health + repair_amount, S.ship.max_health)
            end
        else
            -- Ship is moving, reset repair timer
            S.repair_timer = 0
        end
    else
        -- Not on landing pad, reset repair timer
        S.repair_timer = 0
    end

    -- Spawn smoke particles when thrusters are active
    local any_thruster_active = false
    for _, thruster in ipairs(S.ship.thrusters) do
        if thruster.active then
            any_thruster_active = true
            S.smoke_system:spawn(
                S.ship.x + thruster.x,
                S.ship.y - 0.5,
                S.ship.z + thruster.z,
                S.ship.vx * 0.5,
                -0.02,
                S.ship.vz * 0.5
            )
        end
    end

    -- Manage thruster sound
    if any_thruster_active and not S.ship_death_mode then
        AudioManager.start_thruster()
    else
        AudioManager.stop_thruster()
    end

    -- Update particles
    S.smoke_system:update(dt)

    -- Update speed lines (pass S.ship position and velocity)
    S.speed_lines:update(dt, S.ship.x, S.ship.y, S.ship.z, S.ship.vx, S.ship.vy, S.ship.vz)

    -- Update weather system (rain particles, wind changes, lightning)
    Weather.update(dt, S.cam.pos.x, S.cam.pos.y, S.cam.pos.z, S.ship.vx, S.ship.vy, S.ship.vz)
    Weather.apply_wind(S.ship, S.ship.y, is_grounded)

    -- Update fireworks (for lap completion celebrations)
    Fireworks.update(dt)

    -- Update billboards
    Billboard.update(dt)

    -- Update combat systems (Mission 6)
    if S.combat_active then
        -- Wave start delay
        if S.wave_start_delay > 0 then
            S.wave_start_delay = S.wave_start_delay - dt
            if S.wave_start_delay <= 0 then
                -- Start next wave
                local has_more = Aliens.start_next_wave(S.ship, LandingPads)
                if has_more then
                    print("Wave " .. Aliens.get_wave() .. " starting!")
                end
            end
        end

        -- Check if wave complete and start next (only if not already waiting)
        if Aliens.wave_complete and not Aliens.all_waves_complete() and S.wave_start_delay <= 0 then
            S.wave_start_delay = 3.0  -- Delay between waves
            Aliens.wave_complete = false
        end

        -- Check for mission complete
        if Aliens.all_waves_complete() and not Mission.is_complete() then
            Mission.complete()
        end

        -- Update aliens (pass landing pad status for safe zones)
        local player_on_pad = LandingPads.check_landing(S.ship.x, S.ship.y, S.ship.z, S.ship.vy) ~= nil
        -- Pass world objects for collision detection
        local world_objects = {
            heightmap = Heightmap,
            trees = Trees,
            buildings = S.buildings
        }
        Aliens.update(dt, S.ship, player_on_pad, world_objects)

        -- Validate current target (auto-select closest if destroyed)
        local enemies = Aliens.get_all()
        local validated_target = HUD.validate_target(enemies, S.ship.x, S.ship.z)
        -- Sync turret target with HUD target
        Turret.target = validated_target

        -- Update turret (auto-aims at enemies)
        Turret.update(dt, S.ship, enemies)

        -- Auto-fire turret when target acquired (and weapons enabled)
        if S.weapons_enabled and Turret.can_fire() and Turret.target then
            local dir_x, dir_y, dir_z = Turret.get_fire_direction(S.ship)
            if dir_x then
                local turret_x, turret_y, turret_z = Turret.get_position(S.ship)
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

        -- Check enemy bullet hits on player (using S.ship's collision box)
        local ship_bounds = {
            left = S.ship.x - config.VTOL_COLLISION_WIDTH,
            right = S.ship.x + config.VTOL_COLLISION_WIDTH,
            bottom = S.ship.y - config.VTOL_COLLISION_HEIGHT + config.VTOL_COLLISION_OFFSET_Y,
            top = S.ship.y + config.VTOL_COLLISION_HEIGHT + config.VTOL_COLLISION_OFFSET_Y,
            back = S.ship.z - config.VTOL_COLLISION_DEPTH,
            front = S.ship.z + config.VTOL_COLLISION_DEPTH,
        }
        local player_hits = Bullets.check_collision("player", ship_bounds)
        for _, hit in ipairs(player_hits) do
            S.ship:take_damage(10)  -- Damage per enemy bullet
            AudioManager.play_sfx(8)  -- Collision/damage sound
        end
    end

    -- Auto-level (analog - LT pressure controls strength)
    local auto_level_power = controls.get_axis("auto_level")
    if auto_level_power > 0 then
        S.ship:auto_level(dt, auto_level_power)
    end

    -- Camera rotation (depends on camera mode)
    local timeScale = dt * 60  -- Scale for 60 FPS equivalence

    if S.camera_mode == "free" then
        -- FREE MODE: Arrow keys/right stick and mouse control camera rotation
        -- Use analog values for proportional camera speed
        local cam_left = controls.get_axis("camera_left")
        local cam_right = controls.get_axis("camera_right")
        local cam_up = controls.get_axis("camera_up")
        local cam_down = controls.get_axis("camera_down")

        if cam_left > 0 then
            S.cam.yaw = S.cam.yaw - cam_rot_speed * cam_left * timeScale
        end
        if cam_right > 0 then
            S.cam.yaw = S.cam.yaw + cam_rot_speed * cam_right * timeScale
        end
        if cam_up > 0 then
            S.cam.pitch = S.cam.pitch - cam_rot_speed * 0.6 * cam_up * timeScale
        end
        if cam_down > 0 then
            S.cam.pitch = S.cam.pitch + cam_rot_speed * 0.6 * cam_down * timeScale
        end

        -- Mouse camera control
        local mouse_x, mouse_y = love.mouse.getPosition()
        if love.mouse.isDown(1) or love.mouse.isDown(2) then
            if S.mouse_camera_enabled then
                local dx = mouse_x - S.last_mouse_x
                local dy = mouse_y - S.last_mouse_y
                S.cam.yaw = S.cam.yaw + dx * mouse_sensitivity
                S.cam.pitch = S.cam.pitch + dy * mouse_sensitivity
                S.cam.pitch = math.max(-1.5, math.min(1.5, S.cam.pitch))
            end
            S.mouse_camera_enabled = true
        else
            S.mouse_camera_enabled = false
        end
        S.last_mouse_x, S.last_mouse_y = mouse_x, mouse_y

        -- Debug print every 5 seconds (if enabled)
        if config.CAMERA_DEBUG then
            S.follow_cam_debug_timer = S.follow_cam_debug_timer + dt
            if S.follow_cam_debug_timer >= 5 then
                S.follow_cam_debug_timer = 0
                -- Use camera module's forward vector (updated by updateVectors)
                camera_module.updateVectors(S.cam)
                local horiz_speed = math.sqrt(S.ship.vx * S.ship.vx + S.ship.vz * S.ship.vz)
                print("=== FREE CAMERA DEBUG ===")
                print(string.format("Ship pos: x=%.1f, y=%.1f, z=%.1f", S.ship.x, S.ship.y, S.ship.z))
                print(string.format("Cam pos:  x=%.1f, y=%.1f, z=%.1f", S.cam.pos.x, S.cam.pos.y, S.cam.pos.z))
                print(string.format("Cam fwd:  x=%.3f, y=%.3f, z=%.3f", S.cam.forward.x, S.cam.forward.y, S.cam.forward.z))
                print(string.format("Ship vel: vx=%.3f, vy=%.3f, vz=%.3f (horiz=%.3f)",
                    S.ship.vx, S.ship.vy, S.ship.vz, horiz_speed))
                print(string.format("Yaw: %.1f deg, Pitch: %.1f deg", math.deg(S.cam.yaw), math.deg(S.cam.pitch)))
            end
        end

    elseif S.camera_mode == "follow" then
        -- FOLLOW MODE: Camera follows behind S.ship, looking toward it
        -- Per user diagram:
        -- - Camera positioned BEHIND S.ship (opposite of velocity direction)
        -- - Camera LOOKS TOWARD S.ship (in velocity direction from camera's perspective)
        --
        -- This section ONLY handles rotation (quaternion).
        -- Position is handled in the later position update section.

        -- Initialize quaternion from current yaw/pitch (on mode switch or first time)
        if not S.cam_orientation or S.prev_camera_mode ~= "follow" then
            -- Build quaternion from current camera yaw and pitch for smooth transition
            local yaw_quat = quat.fromAxisAngle(0, 1, 0, S.cam.yaw)
            local pitch_quat = quat.fromAxisAngle(1, 0, 0, S.cam.pitch)
            S.cam_orientation = quat.multiply(yaw_quat, pitch_quat)
        end

        -- Ship horizontal velocity (for yaw direction)
        local horizontal_speed = math.sqrt(S.ship.vx * S.ship.vx + S.ship.vz * S.ship.vz)

        if horizontal_speed > 0.01 then
            -- Normalized horizontal velocity direction
            local vel_x = S.ship.vx / horizontal_speed
            local vel_z = S.ship.vz / horizontal_speed

            -- Target yaw: camera looks OPPOSITE to velocity direction
            -- This way, with S.cam_dist offset, the S.ship appears in front of the camera
            local target_yaw = math.atan2(vel_x, -vel_z)

            -- Target pitch: subtle tilt based on vertical movement, but limited
            -- Use full 3D speed for pitch calculation
            local ship_speed = math.sqrt(S.ship.vx * S.ship.vx + S.ship.vy * S.ship.vy + S.ship.vz * S.ship.vz)
            local target_pitch = 0
            if ship_speed > 0.01 then
                -- Pitch based on ratio of vertical to horizontal speed
                -- Positive vy (going up) -> positive pitch (look down at S.ship)
                -- Negative vy (going down) -> negative pitch (look up at S.ship)
                local pitch_ratio = S.ship.vy / ship_speed
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
            S.cam_orientation = quat.slerp(S.cam_orientation, target_quat, slerp_speed)
            S.cam_orientation = quat.normalize(S.cam_orientation)
        end

        -- Get forward direction from quaternion
        local cam_fwd_x, cam_fwd_y, cam_fwd_z = quat.rotateVector(S.cam_orientation, 0, 0, 1)

        -- Extract yaw/pitch from forward vector for view matrix
        -- Camera convention: forward = (sin(yaw)*cos(pitch), -sin(pitch), cos(yaw)*cos(pitch))
        S.cam.yaw = math.atan2(cam_fwd_x, cam_fwd_z)
        S.cam.pitch = math.asin(math.max(-1, math.min(1, -cam_fwd_y)))

        -- Debug print every 5 seconds (if enabled)
        if config.CAMERA_DEBUG then
            S.follow_cam_debug_timer = S.follow_cam_debug_timer + dt
            if S.follow_cam_debug_timer >= 5 then
                S.follow_cam_debug_timer = 0
                print("=== FOLLOW CAMERA DEBUG ===")
                print(string.format("Ship pos: x=%.1f, y=%.1f, z=%.1f", S.ship.x, S.ship.y, S.ship.z))
                print(string.format("Cam pos:  x=%.1f, y=%.1f, z=%.1f", S.cam.pos.x, S.cam.pos.y, S.cam.pos.z))
                print(string.format("Cam fwd:  x=%.3f, y=%.3f, z=%.3f", cam_fwd_x, cam_fwd_y, cam_fwd_z))
                print(string.format("Ship vel: vx=%.3f, vy=%.3f, vz=%.3f (horiz=%.3f)",
                    S.ship.vx, S.ship.vy, S.ship.vz, horizontal_speed))
                print(string.format("Yaw: %.1f deg, Pitch: %.1f deg", math.deg(S.cam.yaw), math.deg(S.cam.pitch)))
            end
        end

        -- Update mouse position tracking
        S.last_mouse_x, S.last_mouse_y = love.mouse.getPosition()

    elseif S.camera_mode == "focus" then
        -- FOCUS MODE: Camera looks at current target/goal
        local target = HUD.get_target()
        if not target and Mission.is_active() then
            target = Mission.get_target()
        end

        if target then
            -- Calculate direction to target (same convention as guide arrow)
            local dx = target.x - S.cam.pos.x
            local dz = target.z - S.cam.pos.z
            local dy = (target.y or S.ship.y) - S.cam.pos.y
            local dist_xz = math.sqrt(dx * dx + dz * dz)

            -- Target yaw (horizontal direction) - negate dz for camera convention
            local target_yaw = math.atan2(dx, -dz)
            local yaw_diff = target_yaw - S.cam.yaw
            while yaw_diff > math.pi do yaw_diff = yaw_diff - math.pi * 2 end
            while yaw_diff < -math.pi do yaw_diff = yaw_diff + math.pi * 2 end
            S.cam.yaw = S.cam.yaw + yaw_diff * 0.1 * timeScale

            -- Target pitch (vertical angle) - clamp to ±90 degrees
            local target_pitch = math.atan2(dy, dist_xz)
            local max_pitch = math.pi / 2 - 0.01  -- Just under 90 degrees to avoid gimbal lock
            target_pitch = math.max(-max_pitch, math.min(max_pitch, target_pitch))
            S.cam.pitch = S.cam.pitch + (target_pitch - S.cam.pitch) * 0.1 * timeScale
        else
            -- No target - fall back to follow mode behavior
            local speed_sq = S.ship.vx * S.ship.vx + S.ship.vz * S.ship.vz

            if speed_sq > 0.001 then
                local speed = math.sqrt(speed_sq)
                local move_dir_x = S.ship.vx / speed
                local move_dir_z = S.ship.vz / speed

                -- Camera looks opposite to velocity (same as follow mode)
                local target_yaw = math.atan2(move_dir_x, -move_dir_z)
                local angle_diff = target_yaw - S.cam.yaw
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
                    S.cam.yaw = S.cam.yaw + rotation
                end
            end

            -- Gradually return pitch to neutral
            S.cam.pitch = S.cam.pitch + (0 - S.cam.pitch) * 0.02 * timeScale
        end

        -- Update mouse position tracking
        S.last_mouse_x, S.last_mouse_y = love.mouse.getPosition()
    end

    -- Camera follows S.ship with smooth lerp (frame-rate independent)
    -- Pivot point is the S.ship position
    local pivot_x = S.ship.x
    local pivot_y = S.ship.y
    local pivot_z = S.ship.z

    -- Update camera distance based on S.ship speed (with smooth lerp)
    local ship_speed = math.sqrt(S.ship.vx * S.ship.vx + S.ship.vy * S.ship.vy + S.ship.vz * S.ship.vz)
    local speed_factor = math.min(ship_speed / config.CAMERA_DISTANCE_SPEED_MAX, 1.0)
    local target_cam_dist = config.CAMERA_DISTANCE_MIN + (config.CAMERA_DISTANCE_MAX - config.CAMERA_DISTANCE_MIN) * speed_factor
    local zoomLerpFactor = 1.0 - math.pow(1.0 - camera_zoom_speed, timeScale)
    S.cam_dist = S.cam_dist + (target_cam_dist - S.cam_dist) * zoomLerpFactor

    -- Camera position: always at the pivot (S.ship position)
    -- The S.cam_dist offset is applied in the view matrix, not in world space
    local target_x, target_y, target_z = pivot_x, pivot_y, pivot_z

    -- Frame-rate independent lerp: 1 - (1-speed)^(dt*60)
    local lerpFactor = 1.0 - math.pow(1.0 - camera_lerp_speed, timeScale)

    -- Smoothly move camera toward target
    S.cam.pos.x = S.cam.pos.x + (target_x - S.cam.pos.x) * lerpFactor
    S.cam.pos.y = S.cam.pos.y + (target_y - S.cam.pos.y) * lerpFactor
    S.cam.pos.z = S.cam.pos.z + (target_z - S.cam.pos.z) * lerpFactor

    -- Track previous camera mode for smooth transitions
    S.prev_camera_mode = S.camera_mode

    camera_module.updateVectors(S.cam)
    profile("update")
end

function flight_scene.draw()
    profile("clear")

    -- Update fog based on weather state and night mode
    local fog_start, fog_max = Weather.get_fog_settings()
    local fog_color = config.FOG_COLOR  -- Default fog color

    -- Night mode overrides (check Mission.night_mode flag set by racing tracks 3 and 4)
    if Mission.night_mode then
        fog_color = config.NIGHT_FOG_COLOR or {29, 43, 83}  -- Dark blue fog for night
        fog_start = config.NIGHT_FOG_START or 25
        fog_max = config.NIGHT_FOG_MAX or 45
    elseif Weather.is_enabled() then
        fog_color = config.WEATHER_FOG_COLOR
    end
    renderer.setFog(true, fog_start, fog_max, fog_color[1], fog_color[2], fog_color[3])

    -- Set clear color to match fog
    if Mission.night_mode then
        local night_fog = config.NIGHT_FOG_COLOR or {29, 43, 83}
        renderer.setClearColor(night_fog[1], night_fog[2], night_fog[3])
    elseif Weather.is_enabled() then
        renderer.setClearColor(config.WEATHER_FOG_COLOR[1], config.WEATHER_FOG_COLOR[2], config.WEATHER_FOG_COLOR[3])
    else
        renderer.setClearColor(162, 136, 121)  -- Default clear color
    end

    -- Update lighting for night mode (reduced intensity)
    if renderer.setDirectionalLight then
        local lightDir = config.LIGHT_DIRECTION or {0.5, -0.8, 0.3}
        if Mission.night_mode then
            local intensity = config.NIGHT_LIGHT_INTENSITY or 0.25
            local ambient_ratio = config.NIGHT_AMBIENT_RATIO or 0.5
            local ambient = intensity * ambient_ratio  -- Ambient as percentage of intensity
            renderer.setDirectionalLight(lightDir[1], lightDir[2], lightDir[3], intensity, ambient)
        else
            local intensity = config.LIGHT_INTENSITY or 0.8
            local ambient = config.AMBIENT_LIGHT or 0.3
            renderer.setDirectionalLight(lightDir[1], lightDir[2], lightDir[3], intensity, ambient)
        end
    end

    -- Set clear color and clear buffers
    renderer.clearBuffers()

    -- Build view matrix
    -- S.cam_dist pushes the view backward in camera's local -Z direction
    local viewMatrix = camera_module.getViewMatrix(S.cam, S.cam_dist)
    renderer.setMatrices(S.projMatrix, viewMatrix, {x = S.cam.pos.x, y = S.cam.pos.y, z = S.cam.pos.z})

    -- Store view matrix for target bracket drawing later
    flight_scene.viewMatrix = viewMatrix
    profile("clear")

    -- Render shadow map BEFORE terrain (terrain shader samples this)
    if config.SHADOWS_ENABLED then
        profile(" shadows")

        -- Begin shadow map pass
        if ShadowMap.beginPass(S.cam.pos.x, S.cam.pos.y, S.cam.pos.z) then
            -- Add S.ship as shadow caster
            if S.ship and S.ship.mesh then
                ShadowMap.addMeshCaster(S.ship.mesh, S.ship:get_model_matrix())
            end

            -- Add trees as shadow casters
            -- Tree mesh is ~2.0 units tall with foliage radius ~0.55 units
            local trees = Trees.get_all()
            for _, tree in ipairs(trees) do
                ShadowMap.addTreeCaster(tree.x, tree.y, tree.z, 0.55, 2.0)
            end

            -- Add S.buildings as shadow casters
            for _, building in ipairs(S.buildings) do
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
    -- Select sky type based on mission: night for night racing, sunset for Mission 7, overcast for weather, normal otherwise
    profile(" skydome")
    local sky_type = "normal"
    if Mission.night_mode then
        sky_type = "night"
    elseif Mission.current_mission_num == 7 then
        sky_type = "sunset"
    elseif Weather.is_enabled() then
        sky_type = "overcast"
    end
    Skydome.draw(renderer, S.cam.pos.x, S.cam.pos.y, S.cam.pos.z, sky_type)
    profile(" skydome")

    -- Set up checkpoint point lights for race mode
    renderer.clearPointLights()
    if Mission.type == "race" and Mission.race_checkpoints and Mission.race then
        local checkpoints = Mission.race_checkpoints
        local current_cp = Mission.race.current_checkpoint
        local time = love.timer.getTime()

        -- Checkpoint light config values
        local cp_current_radius = config.CHECKPOINT_LIGHT_CURRENT_RADIUS or 20
        local cp_current_intensity = config.CHECKPOINT_LIGHT_CURRENT_INTENSITY or 0.8
        local cp_current_pulse_min = config.CHECKPOINT_LIGHT_CURRENT_PULSE_MIN or 0.7
        local cp_current_pulse_max = config.CHECKPOINT_LIGHT_CURRENT_PULSE_MAX or 1.0
        local cp_current_pulse_speed = config.CHECKPOINT_LIGHT_CURRENT_PULSE_SPEED or 4
        local cp_current_color = config.CHECKPOINT_LIGHT_CURRENT_COLOR or {1.0, 0.8, 0.2}
        local cp_next_radius = config.CHECKPOINT_LIGHT_NEXT_RADIUS or 15
        local cp_next_intensity = config.CHECKPOINT_LIGHT_NEXT_INTENSITY or 0.3
        local cp_next_color = config.CHECKPOINT_LIGHT_NEXT_COLOR or {0.3, 0.6, 0.8}
        local cp_max_distance = config.CHECKPOINT_LIGHT_MAX_DISTANCE or 100

        for i, cp in ipairs(checkpoints) do
            -- Only add lights for current and next checkpoint
            if i == current_cp or i == current_cp + 1 then
                local dist = math.sqrt((cp.x - S.cam.pos.x)^2 + (cp.z - S.cam.pos.z)^2)
                if dist < cp_max_distance then
                    local ground_y = cp.ground_y or (Heightmap and Heightmap.get_height(cp.x, cp.z)) or 0
                    local light_y = ground_y + (cp.y or 6)

                    -- Current checkpoint: bright pulsing light
                    -- Next checkpoint: dimmer light
                    local intensity, r, g, b, radius
                    if i == current_cp then
                        local pulse_range = cp_current_pulse_max - cp_current_pulse_min
                        local pulse = cp_current_pulse_min + pulse_range * (0.5 + 0.5 * math.sin(time * cp_current_pulse_speed))
                        intensity = cp_current_intensity * pulse
                        r, g, b = cp_current_color[1], cp_current_color[2], cp_current_color[3]
                        radius = cp_current_radius
                    else
                        intensity = cp_next_intensity
                        r, g, b = cp_next_color[1], cp_next_color[2], cp_next_color[3]
                        radius = cp_next_radius
                    end

                    renderer.addPointLight("checkpoint_" .. i, cp.x, light_y, cp.z, radius, intensity, r, g, b)
                end
            end
        end
    end

    -- Add thruster lights in night mode when thrusters are firing
    if Mission.night_mode and S.ship then
        -- Thruster light config values
        local thr_radius = config.THRUSTER_LIGHT_RADIUS or 8
        local thr_intensity = config.THRUSTER_LIGHT_INTENSITY or 0.6
        local thr_flicker_min = config.THRUSTER_LIGHT_FLICKER_MIN or 0.7
        local thr_flicker_max = config.THRUSTER_LIGHT_FLICKER_MAX or 1.0
        local thr_flicker_speed = config.THRUSTER_LIGHT_FLICKER_SPEED or 12
        local thr_color = config.THRUSTER_LIGHT_COLOR or {1.0, 0.6, 0.2}

        for i, thruster in ipairs(S.ship.thrusters) do
            if thruster.active then
                -- Get engine position in model space
                local engine = S.ship.engine_positions[i]
                if engine then
                    -- Transform engine position to world space
                    local engine_world = mat4.multiplyVec4(S.ship:get_model_matrix(), {
                        engine.x * S.ship.model_scale,
                        engine.y * S.ship.model_scale,
                        engine.z * S.ship.model_scale,
                        1
                    })

                    -- Add light for thruster flame with flicker effect
                    local time = love.timer.getTime()
                    local flicker_range = thr_flicker_max - thr_flicker_min
                    local flicker = thr_flicker_min + flicker_range * (0.5 + 0.5 * math.sin(time * thr_flicker_speed + i * 1.5))
                    renderer.addPointLight("thruster_" .. i, engine_world[1], engine_world[2], engine_world[3],
                        thr_radius, thr_intensity * flicker, thr_color[1], thr_color[2], thr_color[3])
                end
            end
        end
    end

    -- Draw terrain (pass camera yaw for frustum culling)
    profile(" terrain")
    Heightmap.draw(renderer, S.cam.pos.x, S.cam.pos.z, nil, 80, S.cam.yaw)
    profile(" terrain")

    -- Draw trees (with distance and frustum culling)
    profile(" trees")
    Trees.draw(renderer, S.cam.pos.x, S.cam.pos.y, S.cam.pos.z, S.cam.yaw)
    profile(" trees")

    -- Draw S.buildings
    profile(" S.buildings")
    for _, building in ipairs(S.buildings) do
        Building.draw(building, renderer, S.cam.pos.x, S.cam.pos.z)
    end
    profile(" S.buildings")

    -- Draw landing pads
    profile(" pads")
    LandingPads.draw_all(renderer, S.cam.pos.x, S.cam.pos.z)
    profile(" pads")

    -- Draw cargo (mission cargo or free-flight cargo)
    profile(" cargo")
    if Mission.is_active() then
        Mission.draw_cargo(renderer, S.cam.pos.x, S.cam.pos.z)
    else
        for _, cargo in ipairs(S.cargo_items) do
            Cargo.draw(cargo, renderer, S.cam.pos.x, S.cam.pos.z)
        end
    end
    profile(" cargo")

    -- Draw S.ship
    profile(" S.ship")
    S.ship:draw(renderer)
    profile(" S.ship")

    -- Draw combat elements (Mission 6)
    if S.combat_active then
        -- Draw turret on S.ship
        Turret.draw(renderer, S.ship)

        -- Draw aliens
        Aliens.draw(renderer)
        Aliens.draw_debug(renderer)

        -- Draw bullets (pass viewMatrix for billboard math)
        Bullets.draw(renderer, viewMatrix, S.cam)
    end

    -- Draw smoke particles (disabled - billboard rendering needs fixing)
    -- S.smoke_system:draw(renderer, S.cam)

    -- Draw billboards (camera-facing smoke/particle quads) - must be before flush3D
    Billboard.draw(renderer, viewMatrix, S.cam)

    -- Draw rain as depth-tested 3D geometry (MUST be before flush3D for proper occlusion)
    Weather.draw_rain(renderer, S.cam, S.ship.vx, S.ship.vy, S.ship.vz)

    -- Flush 3D geometry (includes rain, terrain, S.ship - all depth tested together)
    renderer.flush3D()

    -- Draw 3D guide arrow for missions (anchored to camera pivot, depth tested against geometry)
    -- Skip guide arrow in focus mode (camera already points at target)
    if Mission.is_active() and S.camera_mode ~= "focus" then
        -- For combat mode (Mission 7): only draw arrow if there's a selected target
        -- For other missions: draw normal guide arrow
        if S.combat_active then
            local combat_target = HUD.get_target()
            if combat_target then
                Mission.draw_target_arrow(renderer, S.cam.pos.x, S.cam.pos.y, S.cam.pos.z, combat_target)
            end
            -- No arrow if no target selected in combat mode
        else
            Mission.draw_guide_arrow(renderer, S.cam.pos.x, S.cam.pos.y, S.cam.pos.z)
        end
    end
    -- Draw 3D checkpoint markers for race mode (always show, even in focus mode)
    if Mission.is_active() then
        Mission.draw_checkpoints(renderer, Heightmap, S.cam.pos.x, S.cam.pos.z)
    end

    -- Draw wind direction arrow (blue, length based on wind strength)
    Weather.draw_wind_arrow(renderer, S.cam.pos.x, S.cam.pos.y, S.cam.pos.z, S.ship.y)

    -- Draw speed lines (depth-tested 3D lines) - disabled during weather (rain acts as speed lines)
    if not Weather.is_enabled() then
        profile(" speedlines")
        S.speed_lines:draw(renderer, S.cam)
        profile(" speedlines")
    end

    -- Draw fireworks (celebratory effects for race lap/completion)
    Fireworks.draw(renderer)

    -- Draw minimap (pass mission cargo if active, otherwise free-flight cargo)
    profile(" minimap")
    local minimap_cargo = Mission.is_active() and Mission.cargo_objects or S.cargo_items
    local minimap_target = Mission.is_active() and Mission.get_target() or nil
    -- Pass race checkpoints if in race mode
    local race_checkpoints = Mission.race_checkpoints
    local current_checkpoint = Mission.race and Mission.race.current_checkpoint or 1
    -- Pass enemies if in combat mode
    local minimap_enemies = S.combat_active and Aliens.get_all() or nil
    Minimap.draw(renderer, Heightmap, S.ship, LandingPads, minimap_cargo, minimap_target, race_checkpoints, current_checkpoint, minimap_enemies)
    profile(" minimap")

    -- Draw HUD to software buffer (before blit)
    profile(" hud")
    local mission_data
    if Mission.is_active() then
        mission_data = Mission.get_hud_data()
        -- Update Mission 6 objectives with wave info
        if S.combat_active and not Mission.is_complete() then
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
        -- Build input-aware control hints
        local pause_prompt = controls.get_prompt_bracketed("pause")
        local restart_prompt = controls.get_prompt_bracketed("restart")
        mission_data = {
            name = "FREE FLIGHT",
            objectives = {
                "Explore the terrain",
                "Practice landing on pads",
                "Collect cargo and deliver",
                pause_prompt .. " Pause  " .. restart_prompt .. " Reset"
            }
        }
    end
    HUD.draw(S.ship, S.cam, {
        game_mode = S.game_mode,
        mission = mission_data,
        mission_target = Mission.get_target(),
        current_location = nil,  -- TODO: detect current landing pad/building
        is_repairing = S.is_repairing,
        race_data = Mission.get_race_data(),  -- Race HUD data (nil if not in race)
        countdown_data = Mission.get_countdown_data(),  -- Countdown data for non-race missions
        camera_mode = S.camera_mode,  -- Current camera mode (follow/free/focus)
        victory_mode = S.race_victory_mode or S.mission_complete_mode,  -- Hide WASD during victory
        altitude_warning = S.altitude_warning_active,  -- Altitude limit warning active
        altitude_timer = S.altitude_warning_timer      -- Seconds remaining before explosion
    })

    -- Draw combat HUD (targeting, mothership health bar)
    if S.combat_active then
        HUD.draw_combat_hud(Aliens.get_all(), Aliens.mother_ship)

        -- Draw target bracket around selected target
        local target = HUD.get_target()
        if target then
            HUD.draw_target_bracket_3d(target, S.cam, S.projMatrix, flight_scene.viewMatrix)
        end
    end

    -- Draw death screen overlay if S.ship is destroyed
    if S.ship_death_mode and S.ship_death_timer > 1.5 then
        -- Dark overlay
        renderer.drawRectFill(0, 0, config.RENDER_WIDTH, config.RENDER_HEIGHT, 0, 0, 0, 180)

        -- "SHIP DESTROYED" text
        local title = "SHIP DESTROYED"
        local title_x = (config.RENDER_WIDTH - renderer.getTextWidth(title)) / 2
        local title_y = config.RENDER_HEIGHT / 2 - 30
        renderer.drawText(title_x, title_y, title, 255, 80, 80)

        -- Instructions (input-aware prompts)
        local death_prompts = controls.get_prompts("death_screen")
        local restart_text = death_prompts[1]
        local quit_text = death_prompts[2]
        renderer.drawText((config.RENDER_WIDTH - renderer.getTextWidth(restart_text)) / 2, config.RENDER_HEIGHT / 2 + 10, restart_text, 255, 255, 255)
        renderer.drawText((config.RENDER_WIDTH - renderer.getTextWidth(quit_text)) / 2, config.RENDER_HEIGHT / 2 + 25, quit_text, 200, 200, 200)
    end

    -- Draw mission complete celebration panel (non-race missions)
    if S.mission_complete_mode then
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
        local title_x = (config.RENDER_WIDTH - renderer.getTextWidth(title)) / 2
        local title_y = panel_y + 12
        renderer.drawText(title_x, title_y, title, 255, 215, 0)  -- Gold text

        -- Mission name
        local mission_name = Mission.mission_name or "Mission"
        local name_x = (config.RENDER_WIDTH - renderer.getTextWidth(mission_name)) / 2
        renderer.drawText(name_x, title_y + 18, mission_name, 255, 255, 255)

        -- Instructions (input-aware prompts)
        local complete_prompts = controls.get_prompts("mission_complete")
        local quit_text = complete_prompts[1]
        local restart_text = complete_prompts[2]
        renderer.drawText((config.RENDER_WIDTH - renderer.getTextWidth(quit_text)) / 2, panel_y + panel_height - 28, quit_text, 200, 255, 200)
        renderer.drawText((config.RENDER_WIDTH - renderer.getTextWidth(restart_text)) / 2, panel_y + panel_height - 14, restart_text, 180, 180, 180)
    end

    -- Draw race failed panel (timeout or altitude violation)
    if Mission.is_race_failed() then
        -- Panel dimensions
        local panel_width = 180
        local panel_height = 90
        local panel_x = (config.RENDER_WIDTH - panel_width) / 2
        local panel_y = (config.RENDER_HEIGHT - panel_height) / 2 - 10

        -- Dark overlay
        renderer.drawRectFill(0, 0, config.RENDER_WIDTH, config.RENDER_HEIGHT, 0, 0, 0, 160)

        -- Draw panel background with border
        renderer.drawRectFill(panel_x - 2, panel_y - 2, panel_width + 4, panel_height + 4, 255, 80, 80, 255)  -- Red border
        renderer.drawRectFill(panel_x, panel_y, panel_width, panel_height, 40, 20, 20, 240)  -- Dark red background

        -- Get failure reason from objectives
        local title = "RACE FAILED"
        local reason = ""
        if Mission.current_objectives and Mission.current_objectives[1] then
            if Mission.current_objectives[1] == "TIME'S UP!" then
                title = "TIME'S UP!"
                reason = "You ran out of time"
            elseif Mission.current_objectives[1] == "ALTITUDE VIOLATION!" then
                title = "ALTITUDE VIOLATION!"
                reason = "You exceeded the altitude limit"
            end
        end

        -- Title
        local title_x = (config.RENDER_WIDTH - renderer.getTextWidth(title)) / 2
        local title_y = panel_y + 12
        renderer.drawText(title_x, title_y, title, 255, 100, 100)  -- Red text

        -- Reason
        local reason_x = (config.RENDER_WIDTH - renderer.getTextWidth(reason)) / 2
        renderer.drawText(reason_x, title_y + 16, reason, 255, 200, 200)

        -- Total time
        local time_text = "Total time: " .. string.format("%.1f", Mission.race and Mission.race.total_time or 0) .. "s"
        local time_x = (config.RENDER_WIDTH - renderer.getTextWidth(time_text)) / 2
        renderer.drawText(time_x, title_y + 32, time_text, 200, 200, 200)

        -- Instructions (input-aware prompts)
        local failed_prompts = controls.get_prompts("race_failed")
        local quit_text = failed_prompts[1]
        local restart_text = failed_prompts[2]
        renderer.drawText((config.RENDER_WIDTH - renderer.getTextWidth(quit_text)) / 2, panel_y + panel_height - 28, quit_text, 200, 255, 200)
        renderer.drawText((config.RENDER_WIDTH - renderer.getTextWidth(restart_text)) / 2, panel_y + panel_height - 14, restart_text, 180, 180, 180)
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
    -- Notify controls system of keyboard input
    controls.keypressed(key)

    -- Handle race failure - Q to return to menu, R to restart
    if Mission.is_race_failed() then
        if key == "q" then
            Mission.reset()
            Fireworks.reset()
            local scene_manager = require("scene_manager")
            scene_manager.switch("menu")
            return
        elseif key == "r" then
            -- Restart the same track
            local menu = require("menu")
            local track = menu.selected_track
            flight_scene.load()  -- Reload scene
            return
        end
        return  -- Block other inputs when race is failed
    end

    -- Handle mission complete - Q to return to menu
    if Mission.is_complete() and key == "q" then
        Mission.reset()
        S.race_victory_mode = false  -- Reset victory mode
        S.race_victory_timer = 0
        S.mission_complete_mode = false  -- Reset mission complete mode
        S.mission_complete_timer = 0
        S.ship.invulnerable = false  -- Reset invulnerability
        Fireworks.reset()  -- Clear fireworks
        if S.combat_active then
            Aliens.reset()
            Bullets.reset()
            S.combat_active = false
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
            S.race_victory_mode = false  -- Reset victory mode
            S.race_victory_timer = 0
            S.mission_complete_mode = false  -- Reset mission complete mode
            S.mission_complete_timer = 0
            S.ship.invulnerable = false  -- Reset invulnerability
            Fireworks.reset()  -- Clear fireworks
            if S.combat_active then
                Aliens.reset()
                Bullets.reset()
                S.combat_active = false
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

    -- Let HUD handle its keypresses (C for controls, G for goals, tab/escape for pause)
    local hud_handled = HUD.keypressed(key)
    if hud_handled ~= nil then
        return  -- HUD handled this key
    end

    -- Handle T key for target cycling in combat mode
    if key == "t" and S.combat_active then
        local enemies = Aliens.get_all()
        local new_target = HUD.cycle_target(enemies, S.ship.x, S.ship.z)
        if new_target then
            Turret.target = new_target
        end
        return
    end

    -- Note: F key / D-Pad Right camera cycling is handled in update() via controls.just_pressed("camera_cycle")

    -- Handle Q key in death mode - quit to menu
    if key == "q" and S.ship_death_mode then
        S.ship_death_mode = false
        Mission.reset()
        Billboard.reset()
        Fireworks.reset()
        if S.combat_active then
            Aliens.reset()
            Bullets.reset()
            S.combat_active = false
        end
        local scene_manager = require("scene_manager")
        scene_manager.switch("menu")
        return
    end

    if key == "r" and S.ship_death_mode then
        -- Reset S.ship to first landing pad (only works when dead)
        local spawn_x, spawn_y, spawn_z, spawn_yaw = LandingPads.get_spawn(1)
        S.ship:reset(spawn_x, spawn_y, spawn_z, spawn_yaw)

        -- Reset camera rotation
        S.cam.pitch = 0
        S.cam.yaw = 0

        -- Reset death state
        S.ship_death_mode = false
        S.ship_death_timer = 0
        S.ship_death_landed = false
        S.repair_timer = 0
        S.is_repairing = false
        Billboard.reset()

        -- Reset victory mode and fireworks
        S.race_victory_mode = false
        S.race_victory_timer = 0
        S.mission_complete_mode = false
        S.mission_complete_timer = 0
        S.ship.invulnerable = false  -- Reset invulnerability
        Fireworks.reset()

        -- Reset mission or race if active
        if Mission.is_active() then
            Mission.reset()
            if S.current_mission_num then
                Missions.start(S.current_mission_num, Mission)
                HUD.set_mission(S.current_mission_num)
                -- Restart mission music
                AudioManager.start_level_music(S.current_mission_num)

                -- Reset combat for Mission 7
                if S.current_mission_num == 7 then
                    Aliens.reset()
                    Bullets.reset()
                    Turret.reset()
                    S.wave_start_delay = 2.0
                end
            elseif S.current_track_num then
                Missions.start_race_track(S.current_track_num, Mission)
                -- Restart racing music
                AudioManager.start_level_music(7)
            end
        end

        -- Reset free-flight cargo
        for _, cargo in ipairs(S.cargo_items) do
            cargo.state = "idle"
            cargo.x = 15
            cargo.z = 10
            cargo.y = Heightmap.get_height(15, 10) + 0.5
            cargo.attached_to_ship = false
            cargo.collected = false
        end
    end

    -- B key - spawn test billboard above S.ship (free flight only)
    -- if key == "b" and not Mission.is_active() then
    --     Billboard.spawn(S.ship.x, S.ship.y + 0.2, S.ship.z, 0.5, 3.0)
    --     print("Spawned billboard at S.ship position")
    -- end
end

-- Called when leaving the flight scene
function flight_scene.unload()
    -- Stop all audio when leaving flight scene
    AudioManager.stop_thruster()
    AudioManager.stop_music()
end

return flight_scene
