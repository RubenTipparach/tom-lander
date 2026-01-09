-- Flight Scene: Main game scene with terrain, ship, and objects
-- Camera and controls ported from Picotron version

local config = require("config")
local renderer = require("renderer")
local camera_module = require("camera")
local mat4 = require("mat4")
local vec3 = require("vec3")
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

local flight_scene = {}

-- Scene state
local ship
local cam
local smoke_system
local speed_lines
local softwareImage  -- Only used by software renderer, unused with GPU renderer
local projMatrix
local follow_camera = true

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

-- Combat state (Mission 6)
local combat_active = false
local wave_start_delay = 0  -- Delay before starting next wave

-- Fonts
local thrusterFont = nil

function flight_scene.load()
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

    -- Create cargo items (only for free flight mode)
    cargo_items = {}
    if not current_mission_num then
        -- Free flight mode - spawn a test cargo
        table.insert(cargo_items, Cargo.create({
            id = 1,
            x = 15,
            z = 10,
            base_y = Heightmap.get_height(15, 10),
            scale = 0.5
        }))
    end

    -- Start mission if selected
    if current_mission_num then
        Missions.start(current_mission_num, Mission)
    end

    -- Initialize combat systems for Mission 6
    combat_active = (current_mission_num == 6)
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
            print("Fighter destroyed at " .. x .. ", " .. y .. ", " .. z)
            -- TODO: Spawn explosion particles
        end
        Aliens.on_mothership_destroyed = function(x, y, z)
            print("MOTHER SHIP DESTROYED!")
            -- TODO: Spawn big explosion
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

    -- Update ship physics
    ship:update(dt)

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
            if ship_bottom < building_top and ship_top > building_bottom then
                -- Side collision: ship is inside building volume - push out
                ship.x, ship.z = Collision.push_out_of_box(
                    ship.x, ship.z,
                    building.x, building.z,
                    half_width, half_depth
                )

                -- Damage based on collision speed
                local collision_speed = math.sqrt(ship.vx*ship.vx + ship.vy*ship.vy + ship.vz*ship.vz)
                if collision_speed > 0.05 then
                    ship:take_damage(collision_speed * 100)
                end

                -- Kill velocity when hitting side
                ship.vx = ship.vx * 0.5
                ship.vz = ship.vz * 0.5
            elseif ship_bottom >= building_top then
                -- Above building - rooftop is a landing surface
                if building_top > ground_height then
                    ground_height = building_top
                end
            end
        end
    end

    -- Apply ground collision
    local ship_ground_offset = config.VTOL_COLLISION_HEIGHT + config.VTOL_COLLISION_OFFSET_Y
    local landing_height = ground_height + ship_ground_offset

    if ship.y < landing_height then
        local impact_speed = math.abs(ship.vy)

        -- Damage on hard landing
        if impact_speed > 0.1 then
            ship:take_damage(impact_speed * 100)
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

    -- Spawn smoke particles when thrusters are active
    for _, thruster in ipairs(ship.thrusters) do
        if thruster.active then
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

    -- Update particles
    smoke_system:update(dt)

    -- Update speed lines (pass ship position and velocity)
    speed_lines:update(dt, ship.x, ship.y, ship.z, ship.vx, ship.vy, ship.vz)

    -- Update weather system (rain particles, wind changes, lightning)
    Weather.update(dt, cam.pos.x, cam.pos.y, cam.pos.z, ship.vx, ship.vy, ship.vz)
    Weather.apply_wind(ship, ship.y, is_grounded)

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

        -- Check if wave complete and start next
        if Aliens.wave_complete and not Aliens.all_waves_complete() then
            wave_start_delay = 3.0  -- Delay between waves
            Aliens.wave_complete = false
        end

        -- Check for mission complete
        if Aliens.all_waves_complete() and not Mission.is_complete() then
            Mission.complete()
        end

        -- Update aliens (pass landing pad status for safe zones)
        local player_on_pad = LandingPads.check_landing(ship.x, ship.y, ship.z, ship.vy) ~= nil
        Aliens.update(dt, ship, player_on_pad)

        -- Update turret (auto-aims at enemies)
        local enemies = Aliens.get_all()
        Turret.update(dt, ship, enemies)

        -- Auto-fire turret when target acquired
        if Turret.can_fire() and Turret.target then
            local dir_x, dir_y, dir_z = Turret.get_fire_direction(ship)
            if dir_x then
                local turret_x, turret_y, turret_z = Turret.get_position(ship)
                Bullets.spawn_player_bullet(turret_x, turret_y, turret_z, dir_x, dir_y, dir_z)
            end
        end

        -- Update bullets
        Bullets.update(dt)

        -- Check player bullet hits on aliens
        for _, fighter in ipairs(Aliens.fighters) do
            local hits = Bullets.check_collision_sphere("enemy", fighter.x, fighter.y, fighter.z, 0.5)
            for _, hit in ipairs(hits) do
                fighter.health = fighter.health - 25  -- Damage per hit
            end
        end
        if Aliens.mother_ship then
            local hits = Bullets.check_collision_sphere("enemy", Aliens.mother_ship.x, Aliens.mother_ship.y, Aliens.mother_ship.z, 2.0)
            for _, hit in ipairs(hits) do
                Aliens.mother_ship.health = Aliens.mother_ship.health - 25
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

    -- Camera rotation with arrow keys (frame-rate independent)
    local timeScale = dt * 60  -- Scale for 60 FPS equivalence
    if love.keyboard.isDown("left") then
        cam.yaw = cam.yaw - cam_rot_speed * timeScale
    end
    if love.keyboard.isDown("right") then
        cam.yaw = cam.yaw + cam_rot_speed * timeScale
    end
    if love.keyboard.isDown("up") then
        cam.pitch = cam.pitch - cam_rot_speed * 0.6 * timeScale  -- Pitch up
    end
    if love.keyboard.isDown("down") then
        cam.pitch = cam.pitch + cam_rot_speed * 0.6 * timeScale  -- Pitch down
    end

    -- Mouse camera control (hold left or right mouse button to rotate)
    local mouse_x, mouse_y = love.mouse.getPosition()
    if love.mouse.isDown(1) or love.mouse.isDown(2) then  -- Left or right mouse button
        if mouse_camera_enabled then
            local dx = mouse_x - last_mouse_x
            local dy = mouse_y - last_mouse_y
            cam.yaw = cam.yaw + dx * mouse_sensitivity
            cam.pitch = cam.pitch + dy * mouse_sensitivity
            -- Clamp pitch to prevent flipping
            cam.pitch = math.max(-1.5, math.min(1.5, cam.pitch))
        end
        mouse_camera_enabled = true
    else
        mouse_camera_enabled = false
    end
    last_mouse_x, last_mouse_y = mouse_x, mouse_y

    -- Camera follows ship with smooth lerp (frame-rate independent)
    -- Target is ship position directly
    local target_x = ship.x
    local target_y = ship.y
    local target_z = ship.z

    -- Update camera distance based on ship speed (with smooth lerp)
    local ship_speed = math.sqrt(ship.vx * ship.vx + ship.vy * ship.vy + ship.vz * ship.vz)
    local speed_factor = math.min(ship_speed / config.CAMERA_DISTANCE_SPEED_MAX, 1.0)
    local target_cam_dist = config.CAMERA_DISTANCE_MIN + (config.CAMERA_DISTANCE_MAX - config.CAMERA_DISTANCE_MIN) * speed_factor
    local zoomLerpFactor = 1.0 - math.pow(1.0 - camera_zoom_speed, timeScale)
    cam_dist = cam_dist + (target_cam_dist - cam_dist) * zoomLerpFactor

    -- Frame-rate independent lerp: 1 - (1-speed)^(dt*60)
    local lerpFactor = 1.0 - math.pow(1.0 - camera_lerp_speed, timeScale)

    -- Smoothly move camera toward target
    cam.pos.x = cam.pos.x + (target_x - cam.pos.x) * lerpFactor
    cam.pos.y = cam.pos.y + (target_y - cam.pos.y) * lerpFactor
    cam.pos.z = cam.pos.z + (target_z - cam.pos.z) * lerpFactor

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

    -- Build view matrix with cam_dist offset (like Picotron)
    local viewMatrix = camera_module.getViewMatrix(cam, cam_dist)
    renderer.setMatrices(projMatrix, viewMatrix, {x = cam.pos.x, y = cam.pos.y, z = cam.pos.z})
    profile("clear")

    -- Draw skydome FIRST (always behind everything, follows camera)
    -- Use overcast sky texture during weather
    profile(" skydome")
    Skydome.draw(renderer, cam.pos.x, cam.pos.y, cam.pos.z, Weather.is_enabled())
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

        -- Draw bullets
        Bullets.draw(renderer)
    end

    -- Draw smoke particles (disabled - billboard rendering needs fixing)
    -- smoke_system:draw(renderer, cam)

    -- Draw rain as depth-tested 3D geometry (MUST be before flush3D for proper occlusion)
    Weather.draw_rain(renderer, cam, ship.vx, ship.vy, ship.vz)

    -- Flush 3D geometry (includes rain, terrain, ship - all depth tested together)
    renderer.flush3D()

    -- Draw 3D guide arrow for missions (anchored to camera pivot, depth tested against geometry)
    if Mission.is_active() then
        Mission.draw_guide_arrow(renderer, cam.pos.x, cam.pos.y, cam.pos.z)
    end

    -- Draw wind direction arrow (blue, length based on wind strength)
    Weather.draw_wind_arrow(renderer, cam.pos.x, cam.pos.y, cam.pos.z, ship.y)

    -- Draw speed lines (depth-tested 3D lines) - disabled during weather (rain acts as speed lines)
    if not Weather.is_enabled() then
        profile(" speedlines")
        speed_lines:draw(renderer, cam)
        profile(" speedlines")
    end

    -- Draw minimap (pass mission cargo if active, otherwise free-flight cargo)
    profile(" minimap")
    local minimap_cargo = Mission.is_active() and Mission.cargo_objects or cargo_items
    local minimap_target = Mission.is_active() and Mission.get_target() or nil
    Minimap.draw(renderer, Heightmap, ship, LandingPads, minimap_cargo, minimap_target)
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
        is_repairing = false  -- TODO: add repair logic
    })
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
        end
        return  -- Block other keys while paused
    end

    -- Let HUD handle its keypresses (tab/escape for pause)
    HUD.keypressed(key)

    if key == "r" then
        -- Reset ship to first landing pad
        local spawn_x, spawn_y, spawn_z, spawn_yaw = LandingPads.get_spawn(1)
        ship:reset(spawn_x, spawn_y, spawn_z, spawn_yaw)

        -- Reset camera rotation
        cam.pitch = 0
        cam.yaw = 0

        -- Reset mission if active
        if Mission.is_active() and current_mission_num then
            Mission.reset()
            Missions.start(current_mission_num, Mission)

            -- Reset combat for Mission 6
            if current_mission_num == 6 then
                Aliens.reset()
                Bullets.reset()
                Turret.reset()
                wave_start_delay = 2.0
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
end

return flight_scene
