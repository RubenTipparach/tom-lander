-- Flight Scene: Main game scene with terrain, ship, and objects
-- Camera and controls ported from Picotron version

local config = require("config")
local renderer = require("renderer_dda")
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

local flight_scene = {}

-- Scene state
local ship
local cam
local smoke_system
local speed_lines
local softwareImage
local projMatrix
local follow_camera = true

-- Camera settings
-- Note: Picotron runs at 60fps and applies lerp per-frame
local camera_lerp_speed = 0.1  -- How fast camera catches up
local cam_dist = -5 -- Positive = camera behind ship (matching Picotron)
local cam_rot_speed = 0.01  -- Camera rotation speed per frame
local mouse_sensitivity = 0.003  -- Mouse sensitivity for camera rotation
local last_mouse_x, last_mouse_y = 0, 0
local mouse_camera_enabled = false  -- Toggle with right mouse button

-- World objects
local buildings = {}
local cargo_items = {}

-- Fonts
local thrusterFont = nil

function flight_scene.load()
    -- Renderer already initialized in main.lua
    softwareImage = love.graphics.newImage(renderer.getImageData())
    softwareImage:setFilter("nearest", "nearest")  -- Pixel-perfect upscaling

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
    buildings = Building.create_city({
        {x = -10, z = 5, width = 1.5, depth = 1.5, height = 8, side_sprite = Constants.SPRITE_BUILDING_SIDE},      -- Tall tower
        {x = -5, z = 4, width = 1.2, depth = 1.2, height = 6, side_sprite = Constants.SPRITE_BUILDING_SIDE_ALT},   -- Medium tower
        {x = 0, z = 5, width = 1.0, depth = 1.0, height = 5, side_sprite = Constants.SPRITE_BUILDING_SIDE},        -- Shorter building
        {x = 6, z = 4, width = 1.3, depth = 1.3, height = 7, side_sprite = Constants.SPRITE_BUILDING_SIDE_ALT},    -- Tall tower
        {x = -8, z = 12, width = 1.8, depth = 1.0, height = 4, side_sprite = Constants.SPRITE_BUILDING_SIDE},      -- Wide building
        {x = -2, z = 12, width = 1.0, depth = 1.8, height = 5, side_sprite = Constants.SPRITE_BUILDING_SIDE_ALT},  -- Long building
        {x = 3, z = 14, width = 1.2, depth = 1.2, height = 9, side_sprite = Constants.SPRITE_BUILDING_SIDE},       -- Tallest skyscraper
        {x = 9, z = 12, width = 1.0, depth = 1.0, height = 3, side_sprite = Constants.SPRITE_BUILDING_SIDE_ALT},   -- Small building
        {x = -6, z = 18, width = 1.5, depth = 1.2, height = 6, side_sprite = Constants.SPRITE_BUILDING_SIDE},      -- Medium building
        {x = 2, z = 20, width = 1.1, depth = 1.4, height = 7, side_sprite = Constants.SPRITE_BUILDING_SIDE_ALT},   -- Tall building
    }, Heightmap)

    -- Create cargo items
    cargo_items = {}
    table.insert(cargo_items, Cargo.create({
        id = 1,
        x = 15,
        z = 10,
        base_y = Heightmap.get_height(15, 10),
        scale = 0.5
    }))

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

    -- Enable fog (using config values matching Picotron)
    renderer.setFog(true, config.FOG_START_DISTANCE, config.RENDER_DISTANCE,
        config.FOG_COLOR[1], config.FOG_COLOR[2], config.FOG_COLOR[3])

    -- Reset renderer state (menu may have changed these)
    renderer.setClearColor(162, 136, 121)

    print("Flight scene loaded")
    print("Controls:")
    print("  W/A/S/D or I/J/K/L - Thrusters")
    print("  Space - All thrusters | N - Side pair | M - Front/Back pair")
    print("  Arrow keys - Rotate camera")
    print("  R - Reset ship")
    print("  Escape - Return to menu")
end

function flight_scene.update(dt)
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
    local ship_half_width = 0.5  -- Ship collision half-width
    local ship_half_depth = 0.5  -- Ship collision half-depth

    for _, building in ipairs(buildings) do
        local half_width = building.width / 2
        local half_depth = building.depth / 2
        local building_height = building.height
        local building_top = building.y + building_height
        local building_bottom = building.y

        -- Check if ship's bounding box overlaps with building
        if Collision.box_overlap(ship.x, ship.z, ship_half_width, ship_half_depth,
                                  building.x, building.z, half_width, half_depth) then
            -- Ship is horizontally inside building bounds
            if ship.y > building_bottom and ship.y < building_top then
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
            elseif ship.y >= building_top then
                -- Above building - rooftop is a landing surface
                if building_top > ground_height then
                    ground_height = building_top
                end
            end
        end
    end

    -- Apply ground collision
    local ship_ground_offset = 0.5
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
    for _, cargo in ipairs(cargo_items) do
        Cargo.update(cargo, dt, ship.x, ship.y, ship.z, ship.orientation)
    end

    -- Check for landing
    local landing_pad = LandingPads.check_landing(ship.x, ship.y, ship.z, ship.vy)
    if landing_pad and Cargo.is_attached(cargo_items[1]) then
        Cargo.deliver(cargo_items[1])
        print("Cargo delivered to " .. landing_pad.name .. "!")
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

    -- Auto-level with shift key
    if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
        ship:auto_level(dt)
    end

    -- Camera rotation with arrow keys
    if love.keyboard.isDown("left") then
        cam.yaw = cam.yaw - cam_rot_speed
    end
    if love.keyboard.isDown("right") then
        cam.yaw = cam.yaw + cam_rot_speed
    end
    if love.keyboard.isDown("up") then
        cam.pitch = cam.pitch - cam_rot_speed * 0.6  -- Pitch up
    end
    if love.keyboard.isDown("down") then
        cam.pitch = cam.pitch + cam_rot_speed * 0.6  -- Pitch down
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

    -- Camera follows ship with smooth lerp (exactly like Picotron)
    -- Target is ship position directly
    local target_x = ship.x
    local target_y = ship.y
    local target_z = ship.z

    -- Smoothly move camera toward target
    cam.pos.x = cam.pos.x + (target_x - cam.pos.x) * camera_lerp_speed
    cam.pos.y = cam.pos.y + (target_y - cam.pos.y) * camera_lerp_speed
    cam.pos.z = cam.pos.z + (target_z - cam.pos.z) * camera_lerp_speed

    camera_module.updateVectors(cam)
end

function flight_scene.draw()
    -- Set clear color and clear buffers
    renderer.clearBuffers()

    -- Build view-projection matrix with cam_dist offset (like Picotron)
    local viewMatrix = camera_module.getViewMatrix(cam, cam_dist)
    local mvpMatrix = mat4.multiply(projMatrix, viewMatrix)
    renderer.setMatrices(mvpMatrix, {x = cam.pos.x, y = cam.pos.y, z = cam.pos.z})

    -- Draw skydome FIRST (always behind everything, follows camera)
    Skydome.draw(renderer, cam.pos.x, cam.pos.y, cam.pos.z)

    -- Draw terrain
    Heightmap.draw(renderer, cam.pos.x, cam.pos.z, nil, 80)

    -- Draw trees (with distance culling)
    Trees.draw(renderer, cam.pos.x, cam.pos.y, cam.pos.z)

    -- Draw buildings
    for _, building in ipairs(buildings) do
        Building.draw(building, renderer, cam.pos.x, cam.pos.z)
    end

    -- Draw landing pads
    LandingPads.draw_all(renderer, cam.pos.x, cam.pos.z)

    -- Draw cargo
    for _, cargo in ipairs(cargo_items) do
        Cargo.draw(cargo, renderer, cam.pos.x, cam.pos.z)
    end

    -- Draw ship
    ship:draw(renderer)

    -- Draw smoke particles (disabled - billboard rendering needs fixing)
    -- smoke_system:draw(renderer, cam)

    -- Draw speed lines (depth-tested 3D lines)
    speed_lines:draw(renderer, cam)

    -- Draw thruster key labels at 3D positions (in software renderer)
    local shipRotationMatrix = ship:get_rotation_matrix()
    local labelMVP = mat4.multiply(projMatrix, viewMatrix)

    for i, thruster in ipairs(ship.thrusters) do
        -- Get engine position from ship (matches where flames are rendered)
        local engine = ship.engine_positions[i]

        -- Build the same transform as the ship model matrix
        local localX = engine.x * ship.model_scale
        local localY = engine.y * ship.model_scale + 1.0  -- Offset 1 unit above flame
        local localZ = engine.z * ship.model_scale

        -- Apply ship rotation using quaternion (no gimbal lock)
        local shipMatrix = mat4.multiply(shipRotationMatrix, mat4.scale(1, 1, 1))
        shipMatrix = mat4.multiply(mat4.translation(ship.x, ship.y, ship.z), shipMatrix)

        -- Transform local position to world space
        local worldPos = mat4.multiplyVec4(shipMatrix, {localX, localY, localZ, 1})

        -- Transform to clip space using MVP
        local clipPos = mat4.multiplyVec4(labelMVP, {worldPos[1], worldPos[2], worldPos[3], 1})

        -- Only draw if in front of camera
        if clipPos[4] > 0.1 then
            -- Perspective divide and screen mapping (same as renderer)
            local sx = (clipPos[1] / clipPos[4] + 1) * config.RENDER_WIDTH * 0.5
            local sy = (1 - clipPos[2] / clipPos[4]) * config.RENDER_HEIGHT * 0.5

            -- Draw big key letter at thruster position with drop shadow
            local r, g, b = 255, 255, 255
            if thruster.active then r, g, b = 255, 0, 0 end
            renderer.drawText(sx - 4, sy - 5, thruster.key, r, g, b, 2, true)
        end
    end

    -- Draw HUD text (in software renderer, before replacePixels)
    renderer.drawText(2, 2, "TOM LANDER", 255, 255, 255, 1, true)
    renderer.drawText(2, 10, string.format("Health: %d%%", ship.health), 255, 255, 255, 1, true)
    renderer.drawText(2, 18, string.format("Altitude: %.1f", ship.y - Heightmap.get_height(ship.x, ship.z)), 255, 255, 255, 1, true)
    renderer.drawText(2, 26, string.format("Velocity: %.2f", math.sqrt(ship.vx^2 + ship.vy^2 + ship.vz^2)), 255, 255, 255, 1, true)

    -- Cargo status
    local cargo_status = "Cargo: "
    if cargo_items[1].state == "idle" then
        cargo_status = cargo_status .. "Available"
    elseif cargo_items[1].state == "tethering" then
        cargo_status = cargo_status .. "Picking up..."
    elseif cargo_items[1].state == "attached" then
        cargo_status = cargo_status .. "Attached"
    elseif cargo_items[1].state == "delivered" then
        cargo_status = cargo_status .. "Delivered!"
    end
    renderer.drawText(2, 34, cargo_status, 255, 255, 255, 1, true)

    -- Thruster indicators
    renderer.drawText(2, 44, "Thrusters:", 255, 255, 255, 1, true)
    local thruster_labels = {"A", "D", "W", "S"}
    local thruster_str = ""
    for i, thruster in ipairs(ship.thrusters) do
        if thruster.active then
            thruster_str = thruster_str .. "[" .. thruster_labels[i] .. "]"
        else
            thruster_str = thruster_str .. " " .. thruster_labels[i] .. " "
        end
    end
    renderer.drawText(2, 52, thruster_str, 255, 255, 255, 1, true)

    -- Controls hint (gray text at bottom)
    renderer.drawText(2, config.RENDER_HEIGHT - 8, "Arrows: Camera | Shift: Level", 160, 160, 160, 1, true)

    -- Stats (top-right, below minimap)
    local stats = renderer.getStats()
    renderer.drawText(config.RENDER_WIDTH - 50, Minimap.Y + Minimap.SIZE + 8, string.format("Tris:%d", stats.trianglesDrawn), 255, 255, 255, 1, true)
    renderer.drawText(config.RENDER_WIDTH - 50, Minimap.Y + Minimap.SIZE + 16, string.format("FPS:%d", love.timer.getFPS()), 255, 255, 255, 1, true)

    -- Draw minimap
    Minimap.draw(renderer, Heightmap, ship, LandingPads, cargo_items)

    -- Update and draw the software rendered image
    softwareImage:replacePixels(renderer.getImageData())

    -- Get actual window size for dynamic scaling
    local windowWidth, windowHeight = love.graphics.getDimensions()

    -- Calculate scale maintaining aspect ratio
    local scaleX = windowWidth / config.RENDER_WIDTH
    local scaleY = windowHeight / config.RENDER_HEIGHT
    local scale = math.min(scaleX, scaleY)

    -- Calculate offset to center the image
    local offsetX = (windowWidth - config.RENDER_WIDTH * scale) / 2
    local offsetY = (windowHeight - config.RENDER_HEIGHT * scale) / 2

    -- Clear to black for letterboxing
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(softwareImage, offsetX, offsetY, 0, scale, scale)
end

function flight_scene.keypressed(key)
    if key == "escape" then
        local scene_manager = require("scene_manager")
        scene_manager.switch("menu")
    elseif key == "q" then
        -- Toggle SET_CLEAR_COLOR for testing
        config.SET_CLEAR_COLOR = not config.SET_CLEAR_COLOR
        print("SET_CLEAR_COLOR: " .. tostring(config.SET_CLEAR_COLOR))
    elseif key == "r" then
        -- Reset ship to first landing pad
        local spawn_x, spawn_y, spawn_z, spawn_yaw = LandingPads.get_spawn(1)
        ship:reset(spawn_x, spawn_y, spawn_z, spawn_yaw)

        -- Reset camera rotation
        cam.pitch = 0
        cam.yaw = 0

        -- Reset cargo
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
