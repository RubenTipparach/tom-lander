-- Aliens module: UFO fighters and mother ship
-- Ported from Picotron version

local quat = require("quat")
local mat4 = require("mat4")
local obj_loader = require("obj_loader")
local Constants = require("constants")
local config = require("config")
local Collision = require("collision")

local Aliens = {}

-- Alien configuration
Aliens.FIGHTER_HEALTH = 100
Aliens.MOTHER_SHIP_HEALTH = 1000
Aliens.FIGHTER_SPEED = 2.0  -- Units per second
Aliens.FIGHTER_FIRE_RATE = 2  -- Bullets per second
Aliens.FIGHTER_FIRE_ARC = 0.125  -- 45 degrees
Aliens.FIGHTER_FIRE_RANGE = 15  -- Units

-- Fighter AI behavior - forward-only flight model
Aliens.FIGHTER_TURN_SPEED = 2.0      -- Radians per second turn rate
Aliens.FIGHTER_MIN_ALTITUDE = 3      -- Minimum altitude above terrain
Aliens.FIGHTER_MAX_ALTITUDE = 20     -- Maximum altitude
Aliens.FIGHTER_ATTACK_DIST = 15      -- Distance to start attack run
Aliens.FIGHTER_RETREAT_DIST = 30     -- Distance to retreat to after attack
Aliens.FIGHTER_FIRE_CONE = 0.3       -- Cone of fire (radians, ~17 degrees)
Aliens.FIGHTER_BURST_MIN = 5         -- Minimum shots per burst
Aliens.FIGHTER_BURST_MAX = 10        -- Maximum shots per burst
Aliens.FIGHTER_BURST_RATE = 8        -- Shots per second during burst
Aliens.FIGHTER_BURST_COOLDOWN = 3.0  -- Seconds between bursts
Aliens.FIGHTER_BANK_MULTIPLIER = 15  -- Banking intensity based on turn rate
Aliens.FIGHTER_MAX_BANK = 0.5        -- Max bank angle (radians)

-- Mother ship behavior
Aliens.MOTHER_SHIP_FIRE_RATE = 4  -- Bullets per second (increased for bullet hell)
Aliens.MOTHER_SHIP_FIRE_RANGE = 40
Aliens.MOTHER_SHIP_HOVER_HEIGHT = 15
Aliens.MOTHER_SHIP_MAX_HEIGHT = 35
Aliens.MOTHER_SHIP_DESCEND_SPEED = -0.1
Aliens.MOTHER_SHIP_SCALE = 2.0    -- Scale multiplier for mother ship
Aliens.MOTHER_SHIP_COLLISION_RADIUS = 4.0  -- Collision radius for mother ship

-- Wave configuration
Aliens.waves = {
    {count = 2, type = "fighter"},
    {count = 4, type = "fighter"},
    {count = 5, type = "fighter"},
    {count = 1, type = "mother"}
}

-- Active aliens
Aliens.fighters = {}
Aliens.mother_ship = nil
Aliens.current_wave = 0
Aliens.wave_complete = false
Aliens.mother_ship_destroyed = false
Aliens.mother_ship_destroyed_time = nil

-- Callbacks (set from flight_scene)
Aliens.on_fighter_destroyed = nil
Aliens.on_mothership_destroyed = nil
Aliens.spawn_bullet = nil

-- Meshes (loaded from OBJ files)
Aliens.fighter_mesh = nil
Aliens.mother_mesh = nil

-- Load meshes from OBJ files
function Aliens.load_meshes()
    if not Aliens.fighter_mesh then
        -- Load directly (like other modules do) - no pcall so errors are visible
        Aliens.fighter_mesh = obj_loader.load("assets/ufo_fighter.obj")
    end

    if not Aliens.mother_mesh then
        Aliens.mother_mesh = obj_loader.load("assets/ufo_mother.obj")
    end
end

-- Create a UFO fighter
function Aliens.spawn_fighter(x, y, z)
    local fighter = {
        x = x,
        y = y,
        z = z,
        vx = 0,
        vy = 0,
        vz = 0,
        yaw = math.random() * math.pi * 2,  -- Random initial facing
        roll = 0,
        prev_yaw = 0,
        health = Aliens.FIGHTER_HEALTH,
        max_health = Aliens.FIGHTER_HEALTH,
        target = nil,
        type = "fighter",
        -- AI state: "approach" (fly toward player), "attack" (firing burst), "retreat" (fly away)
        ai_state = "approach",
        -- Burst firing state
        burst_shots_remaining = 0,
        burst_timer = 0,
        burst_cooldown = math.random() * 2,  -- Stagger initial attacks
    }
    table.insert(Aliens.fighters, fighter)
    return fighter
end

-- Create mother ship
function Aliens.spawn_mother_ship(x, y, z)
    Aliens.mother_ship = {
        x = x,
        y = y,
        z = z,
        vx = 0,
        vy = 0,
        vz = 0,
        yaw = 0,
        health = Aliens.MOTHER_SHIP_HEALTH,
        max_health = Aliens.MOTHER_SHIP_HEALTH,
        fire_timer = 0,
        fire_angle = 0,
        target = nil,
        type = "mother"
    }
    return Aliens.mother_ship
end

-- Start next wave
function Aliens.start_next_wave(player, landing_pads)
    Aliens.current_wave = Aliens.current_wave + 1
    if Aliens.current_wave > #Aliens.waves then
        return false  -- No more waves
    end

    local wave = Aliens.waves[Aliens.current_wave]
    Aliens.wave_complete = false
    Aliens.wave_spawning = true  -- Flag to prevent immediate wave_complete detection

    if wave.type == "fighter" then
        -- Spawn fighters far from city center (50-80 units out)
        for i = 1, wave.count do
            local angle = (i / wave.count) * math.pi * 2 + math.random() * 0.5
            local distance = 50 + math.random() * 30  -- 50-80 units from center
            local x = math.cos(angle) * distance
            local z = math.sin(angle) * distance
            local y = 8 + math.random() * 5  -- Spawn at altitude 8-13
            local fighter = Aliens.spawn_fighter(x, y, z)
            fighter.target = player
        end
    elseif wave.type == "mother" then
        -- Spawn mother ship far away, high up
        local angle = math.random() * math.pi * 2
        local spawn_x = math.cos(angle) * 100
        local spawn_y = 25 + math.random() * 10
        local spawn_z = math.sin(angle) * 100

        local mother = Aliens.spawn_mother_ship(spawn_x, spawn_y, spawn_z)
        mother.target = player
    end

    return true
end

-- Update all aliens
-- world_objects: {heightmap, trees, buildings} for collision detection
function Aliens.update(dt, player, player_on_pad, world_objects)
    -- Update fighters
    for i = #Aliens.fighters, 1, -1 do
        local fighter = Aliens.fighters[i]

        if fighter.health <= 0 then
            -- Trigger explosion callback
            if Aliens.on_fighter_destroyed then
                Aliens.on_fighter_destroyed(fighter.x, fighter.y, fighter.z)
            end
            table.remove(Aliens.fighters, i)
        else
            Aliens.update_fighter(fighter, dt, player, player_on_pad, world_objects)
        end
    end

    -- Update mother ship
    if Aliens.mother_ship then
        if Aliens.mother_ship.health <= 0 then
            if Aliens.on_mothership_destroyed then
                Aliens.on_mothership_destroyed(Aliens.mother_ship.x, Aliens.mother_ship.y, Aliens.mother_ship.z)
            end
            Aliens.mother_ship_destroyed = true
            Aliens.mother_ship_destroyed_time = love.timer.getTime()
            Aliens.mother_ship = nil
        else
            Aliens.update_mother_ship(Aliens.mother_ship, dt, player, player_on_pad)
        end
    end

    -- Clear spawning flag once we have enemies
    if Aliens.wave_spawning and (#Aliens.fighters > 0 or Aliens.mother_ship) then
        Aliens.wave_spawning = false
    end

    -- Check if wave is complete (only if not in spawning state)
    if not Aliens.wave_spawning and #Aliens.fighters == 0 and not Aliens.mother_ship and Aliens.current_wave > 0 then
        Aliens.wave_complete = true
    end
end

-- Update fighter AI - forward-only flight model with burst firing
-- world_objects: {heightmap, trees, buildings} for collision detection
function Aliens.update_fighter(fighter, dt, player, player_on_pad, world_objects)
    -- Direction and distance to player
    local dx = player.x - fighter.x
    local dy = player.y - fighter.y
    local dz = player.z - fighter.z
    local dist_xz = math.sqrt(dx * dx + dz * dz)
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

    -- Calculate angle to player (horizontal plane)
    local angle_to_player = math.atan2(dx, dz)

    -- Get terrain height for altitude management
    local ground_height = 0
    if world_objects and world_objects.heightmap then
        ground_height = world_objects.heightmap.get_height(fighter.x, fighter.z)
    end
    local min_flight_height = ground_height + Aliens.FIGHTER_MIN_ALTITUDE

    -- If player is on landing pad, fly away
    if player_on_pad then
        fighter.ai_state = "retreat"
        fighter.burst_shots_remaining = 0
    end

    -- Determine target yaw based on AI state
    local target_yaw = fighter.yaw
    local target_altitude = math.max(player.y + 2, min_flight_height)

    if fighter.ai_state == "approach" then
        -- Fly toward player
        target_yaw = angle_to_player
        target_altitude = math.max(player.y + 3, min_flight_height)

        -- Check if close enough and player is in cone of fire
        local yaw_diff = angle_to_player - fighter.yaw
        while yaw_diff > math.pi do yaw_diff = yaw_diff - math.pi * 2 end
        while yaw_diff < -math.pi do yaw_diff = yaw_diff + math.pi * 2 end

        -- If close enough and facing player, start attack
        if dist_xz < Aliens.FIGHTER_ATTACK_DIST and math.abs(yaw_diff) < Aliens.FIGHTER_FIRE_CONE then
            if fighter.burst_cooldown <= 0 then
                -- Start burst
                fighter.ai_state = "attack"
                fighter.burst_shots_remaining = Aliens.FIGHTER_BURST_MIN +
                    math.floor(math.random() * (Aliens.FIGHTER_BURST_MAX - Aliens.FIGHTER_BURST_MIN + 1))
                fighter.burst_timer = 0
            end
        end

        -- Update burst cooldown
        fighter.burst_cooldown = fighter.burst_cooldown - dt

    elseif fighter.ai_state == "attack" then
        -- Keep facing player during attack
        target_yaw = angle_to_player

        -- Fire burst
        fighter.burst_timer = fighter.burst_timer + dt
        local burst_interval = 1.0 / Aliens.FIGHTER_BURST_RATE

        if fighter.burst_timer >= burst_interval and fighter.burst_shots_remaining > 0 then
            -- Check cone of fire
            local yaw_diff = angle_to_player - fighter.yaw
            while yaw_diff > math.pi do yaw_diff = yaw_diff - math.pi * 2 end
            while yaw_diff < -math.pi do yaw_diff = yaw_diff + math.pi * 2 end

            if math.abs(yaw_diff) < Aliens.FIGHTER_FIRE_CONE and not player_on_pad then
                -- Fire at player
                if Aliens.spawn_bullet and dist > 0.1 then
                    local dir_x = dx / dist
                    local dir_y = dy / dist
                    local dir_z = dz / dist
                    Aliens.spawn_bullet(
                        fighter.x, fighter.y, fighter.z,
                        dir_x, dir_y, dir_z,
                        Aliens.FIGHTER_FIRE_RANGE
                    )
                end
            end
            fighter.burst_shots_remaining = fighter.burst_shots_remaining - 1
            fighter.burst_timer = 0
        end

        -- When burst is done, retreat
        if fighter.burst_shots_remaining <= 0 then
            fighter.ai_state = "retreat"
            fighter.burst_cooldown = Aliens.FIGHTER_BURST_COOLDOWN
        end

    elseif fighter.ai_state == "retreat" then
        -- Fly away from player
        target_yaw = angle_to_player + math.pi  -- Opposite direction
        target_altitude = math.max(player.y + 5, min_flight_height + 5)

        -- Once far enough, approach again
        if dist_xz > Aliens.FIGHTER_RETREAT_DIST then
            fighter.ai_state = "approach"
        end

        -- Update burst cooldown while retreating
        fighter.burst_cooldown = fighter.burst_cooldown - dt
    end

    -- Clamp target altitude
    target_altitude = math.min(target_altitude, Aliens.FIGHTER_MAX_ALTITUDE)

    -- Smoothly rotate toward target yaw (forward-only movement)
    local yaw_diff = target_yaw - fighter.yaw
    while yaw_diff > math.pi do yaw_diff = yaw_diff - math.pi * 2 end
    while yaw_diff < -math.pi do yaw_diff = yaw_diff + math.pi * 2 end

    local turn_amount = Aliens.FIGHTER_TURN_SPEED * dt
    if math.abs(yaw_diff) < turn_amount then
        fighter.yaw = target_yaw
    else
        fighter.yaw = fighter.yaw + turn_amount * (yaw_diff > 0 and 1 or -1)
    end

    -- Normalize yaw
    while fighter.yaw > math.pi do fighter.yaw = fighter.yaw - math.pi * 2 end
    while fighter.yaw < -math.pi do fighter.yaw = fighter.yaw + math.pi * 2 end

    -- Calculate banking based on turn rate
    local turn_rate = yaw_diff / dt  -- Approximate turn rate
    local target_roll = -turn_rate * 0.1  -- Bank into turn
    target_roll = math.max(-Aliens.FIGHTER_MAX_BANK, math.min(Aliens.FIGHTER_MAX_BANK, target_roll))
    fighter.roll = fighter.roll + (target_roll - fighter.roll) * 0.1

    -- Move forward in facing direction (forward-only movement)
    local forward_x = math.sin(fighter.yaw)
    local forward_z = math.cos(fighter.yaw)

    fighter.vx = forward_x * Aliens.FIGHTER_SPEED
    fighter.vz = forward_z * Aliens.FIGHTER_SPEED

    -- Vertical movement toward target altitude
    local alt_diff = target_altitude - fighter.y
    fighter.vy = math.max(-1.0, math.min(1.0, alt_diff * 0.5))

    -- Update position
    fighter.x = fighter.x + fighter.vx * dt
    fighter.y = fighter.y + fighter.vy * dt
    fighter.z = fighter.z + fighter.vz * dt

    -- Collision detection with world objects
    if world_objects then
        local fighter_radius = 0.5

        -- Terrain collision
        if world_objects.heightmap then
            local curr_ground = world_objects.heightmap.get_height(fighter.x, fighter.z)
            local min_height = curr_ground + fighter_radius + 0.5
            if fighter.y < min_height then
                fighter.y = min_height
                fighter.vy = 0.5
                fighter.health = fighter.health - 10
            end
        end

        -- Tree collision
        if world_objects.trees then
            local all_trees = world_objects.trees.get_all()
            for _, tree in ipairs(all_trees) do
                local tree_radius = 0.55
                local tree_height = 2.0
                local tdx = fighter.x - tree.x
                local tdz = fighter.z - tree.z
                local tdist = math.sqrt(tdx * tdx + tdz * tdz)
                local combined_radius = fighter_radius + tree_radius

                if tdist < combined_radius and fighter.y < tree.y + tree_height then
                    if tdist > 0.01 then
                        local push_x = tdx / tdist
                        local push_z = tdz / tdist
                        fighter.x = tree.x + push_x * (combined_radius + 0.1)
                        fighter.z = tree.z + push_z * (combined_radius + 0.1)
                        fighter.health = fighter.health - 5
                    end
                end
            end
        end

        -- Building collision
        if world_objects.buildings then
            for _, building in ipairs(world_objects.buildings) do
                local half_width = building.width / 2 + fighter_radius
                local half_depth = building.depth / 2 + fighter_radius
                local building_top = building.y + building.height

                if fighter.x > building.x - half_width and fighter.x < building.x + half_width and
                   fighter.z > building.z - half_depth and fighter.z < building.z + half_depth and
                   fighter.y < building_top then
                    local old_x, old_z = fighter.x, fighter.z
                    fighter.x, fighter.z = Collision.push_out_of_box(
                        fighter.x, fighter.z,
                        building.x, building.z,
                        half_width, half_depth
                    )
                    fighter.health = fighter.health - 15
                end
            end
        end
    end

    -- Store previous yaw for next frame
    fighter.prev_yaw = fighter.yaw
end

-- Update mother ship
function Aliens.update_mother_ship(mother, dt, player, player_on_pad)
    -- Hover above player
    local target_height = player.y + Aliens.MOTHER_SHIP_HOVER_HEIGHT
    if target_height > Aliens.MOTHER_SHIP_MAX_HEIGHT then
        target_height = Aliens.MOTHER_SHIP_MAX_HEIGHT
    end

    if mother.y > target_height then
        mother.vy = Aliens.MOTHER_SHIP_DESCEND_SPEED
        mother.y = mother.y + mother.vy * dt * 60
    else
        mother.vy = 0
    end

    -- Rotate slowly
    mother.yaw = mother.yaw + dt * 0.2

    -- Shoot streams at player
    mother.fire_timer = mother.fire_timer + dt

    local dx = player.x - mother.x
    local dy = player.y - mother.y
    local dz = player.z - mother.z
    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

    if not player_on_pad and dist <= Aliens.MOTHER_SHIP_FIRE_RANGE and dist > 0.1 then
        -- Check if player is below (dot product with down vector)
        local to_player_y = dy / dist
        local dot = to_player_y * (-1)

        if dot > 0 and mother.fire_timer >= (1 / Aliens.MOTHER_SHIP_FIRE_RATE) then
            if Aliens.spawn_bullet then
                -- Direction to player (normalized)
                local dir_x = dx / dist
                local dir_y = dy / dist
                local dir_z = dz / dist

                -- Fire 3 streams aimed at player with slight angular offset
                local num_streams = 3
                local stream_spread = 0.15  -- Angular spread between streams

                for i = 0, num_streams - 1 do
                    -- Calculate perpendicular offset for each stream
                    -- Use cross product with up vector to get perpendicular direction
                    local perp_x = -dir_z
                    local perp_z = dir_x
                    local perp_len = math.sqrt(perp_x * perp_x + perp_z * perp_z)
                    if perp_len > 0.01 then
                        perp_x = perp_x / perp_len
                        perp_z = perp_z / perp_len
                    end

                    -- Offset: -1, 0, +1 for 3 streams
                    local offset = (i - 1) * stream_spread

                    -- Add perpendicular offset to direction
                    local stream_dir_x = dir_x + perp_x * offset
                    local stream_dir_z = dir_z + perp_z * offset
                    local stream_dir_y = dir_y

                    -- Re-normalize
                    local stream_len = math.sqrt(stream_dir_x*stream_dir_x + stream_dir_y*stream_dir_y + stream_dir_z*stream_dir_z)
                    if stream_len > 0.01 then
                        stream_dir_x = stream_dir_x / stream_len
                        stream_dir_y = stream_dir_y / stream_len
                        stream_dir_z = stream_dir_z / stream_len
                    end

                    -- Spawn from slightly offset positions on the ship
                    local spawn_offset = 1.5
                    local spawn_x = mother.x + perp_x * offset * spawn_offset * 5
                    local spawn_z = mother.z + perp_z * offset * spawn_offset * 5

                    Aliens.spawn_bullet(
                        spawn_x, mother.y - 1, spawn_z,
                        stream_dir_x, stream_dir_y, stream_dir_z,
                        Aliens.MOTHER_SHIP_FIRE_RANGE
                    )
                end
            end
            mother.fire_timer = 0
        end
    end
end

-- Get all active aliens
function Aliens.get_all()
    local result = {}
    for _, f in ipairs(Aliens.fighters) do
        table.insert(result, f)
    end
    if Aliens.mother_ship then
        table.insert(result, Aliens.mother_ship)
    end
    return result
end

-- Draw all aliens
function Aliens.draw(renderer)
    -- Load meshes if needed
    Aliens.load_meshes()

    -- Get textures
    local fighter_tex = Constants.getTextureData(Constants.SPRITE_UFO_FIGHTER)
    local mother_tex = Constants.getTextureData(Constants.SPRITE_UFO_MOTHER)

    -- Draw fighters
    for _, fighter in ipairs(Aliens.fighters) do
        Aliens.draw_alien(renderer, fighter, Aliens.fighter_mesh, fighter_tex, 1.0)
    end

    -- Draw mother ship (2x scale)
    if Aliens.mother_ship then
        Aliens.draw_alien(renderer, Aliens.mother_ship, Aliens.mother_mesh, mother_tex, Aliens.MOTHER_SHIP_SCALE)
    end
end

-- Draw an alien using OBJ mesh (like ship.lua)
function Aliens.draw_alien(renderer, alien, mesh, texData, scale)
    if not mesh or not texData then return end
    if not mesh.triangles or #mesh.triangles == 0 then return end

    -- Build model matrix with yaw and roll (for fighters)
    -- Model faces +X by default, so add 90 degree offset to align with +Z (forward)
    -- yaw rotates around Y axis, roll around local forward axis
    local model_yaw_offset = -math.pi / 2  -- Rotate model 90 degrees right to face forward
    local yawQ = quat.fromAxisAngle(0, 1, 0, alien.yaw + model_yaw_offset)
    -- Apply roll in local space: multiply roll FIRST then yaw (right-to-left order)
    local rollQ = quat.fromAxisAngle(0, 0, 1, alien.roll or 0)
    -- This order: first roll (local Z), then yaw (world Y)
    local orientation = quat.multiply(yawQ, rollQ)

    local scaleMatrix = mat4.scale(scale, scale, scale)
    local rotationMatrix = quat.toMatrix(orientation)
    local modelMatrix = mat4.multiply(rotationMatrix, scaleMatrix)
    modelMatrix = mat4.multiply(mat4.translation(alien.x, alien.y, alien.z), modelMatrix)

    -- Use Gouraud or flat shading based on config
    if config.GOURAUD_SHADING and renderer.drawMeshGouraud then
        renderer.drawMeshGouraud(mesh, modelMatrix, texData, mat4)
    elseif renderer.drawMeshFlat then
        renderer.drawMeshFlat(mesh, modelMatrix, texData, mat4)
    else
        -- Fallback: draw without lighting
        for _, tri in ipairs(mesh.triangles) do
            local v1 = mesh.vertices[tri[1]]
            local v2 = mesh.vertices[tri[2]]
            local v3 = mesh.vertices[tri[3]]

            local p1 = mat4.multiplyVec4(modelMatrix, {v1.pos[1], v1.pos[2], v1.pos[3], 1})
            local p2 = mat4.multiplyVec4(modelMatrix, {v2.pos[1], v2.pos[2], v2.pos[3], 1})
            local p3 = mat4.multiplyVec4(modelMatrix, {v3.pos[1], v3.pos[2], v3.pos[3], 1})

            renderer.drawTriangle3D(
                {pos = {p1[1], p1[2], p1[3]}, uv = v1.uv},
                {pos = {p2[1], p2[2], p2[3]}, uv = v2.uv},
                {pos = {p3[1], p3[2], p3[3]}, uv = v3.uv},
                nil,
                texData
            )
        end
    end
end

-- Reset aliens
function Aliens.reset()
    Aliens.fighters = {}
    Aliens.mother_ship = nil
    Aliens.current_wave = 0
    Aliens.wave_complete = false
    Aliens.wave_spawning = false
    Aliens.mother_ship_destroyed = false
    Aliens.mother_ship_destroyed_time = nil
end

-- Get current wave number
function Aliens.get_wave()
    return Aliens.current_wave
end

-- Get total waves
function Aliens.get_total_waves()
    return #Aliens.waves
end

-- Check if all waves complete
function Aliens.all_waves_complete()
    return Aliens.current_wave >= #Aliens.waves and Aliens.wave_complete
end

-- Draw debug visuals for combat
-- Basic (COMBAT_DEBUG): facing direction (red) + velocity (blue) arrows
-- Detailed (COMBAT_DEBUG_DETAILED): adds bounding boxes, axes, target lines
function Aliens.draw_debug(renderer)
    if not config.COMBAT_DEBUG then return end

    -- Draw debug for all fighters
    for _, fighter in ipairs(Aliens.fighters) do
        Aliens.draw_alien_debug(renderer, fighter, 0.5)
    end

    -- Draw debug for mother ship
    if Aliens.mother_ship then
        Aliens.draw_alien_debug(renderer, Aliens.mother_ship, 2.0)
    end
end

-- Draw debug visuals for a single alien
-- Basic (COMBAT_DEBUG): red facing arrow + blue velocity arrow
-- Detailed (COMBAT_DEBUG_DETAILED): bounding boxes, axes, target lines
function Aliens.draw_alien_debug(renderer, alien, radius)
    local x, y, z = alien.x, alien.y, alien.z

    -- BASIC DEBUG: Facing direction (RED) + Velocity (BLUE)
    -- Draw facing direction (RED arrow based on yaw - where model is pointing)
    local facing_length = 3.0
    local facing_x = math.sin(alien.yaw) * facing_length
    local facing_z = math.cos(alien.yaw) * facing_length
    Aliens.draw_debug_line(renderer, x, y, z, x + facing_x, y, z + facing_z, 255, 80, 80)
    -- Draw small arrowhead
    local arrow_size = 0.5
    local arrow_angle = alien.yaw + math.pi * 0.85
    local arrow_x1 = x + facing_x + math.sin(arrow_angle) * arrow_size
    local arrow_z1 = z + facing_z + math.cos(arrow_angle) * arrow_size
    arrow_angle = alien.yaw - math.pi * 0.85
    local arrow_x2 = x + facing_x + math.sin(arrow_angle) * arrow_size
    local arrow_z2 = z + facing_z + math.cos(arrow_angle) * arrow_size
    Aliens.draw_debug_line(renderer, x + facing_x, y, z + facing_z, arrow_x1, y, arrow_z1, 255, 80, 80)
    Aliens.draw_debug_line(renderer, x + facing_x, y, z + facing_z, arrow_x2, y, arrow_z2, 255, 80, 80)

    -- Draw velocity vector (BLUE arrow showing movement direction)
    local vel_scale = 2.0  -- Scale velocity for visibility
    local vx, vy, vz = alien.vx * vel_scale, alien.vy * vel_scale, alien.vz * vel_scale
    Aliens.draw_debug_line(renderer, x, y, z, x + vx, y + vy, z + vz, 80, 150, 255)

    -- DETAILED DEBUG: Only if enabled
    if not config.COMBAT_DEBUG_DETAILED then return end

    -- Draw 3-axis cross at center
    local axis_length = radius * 1.5
    -- X axis (red)
    Aliens.draw_debug_line(renderer, x - axis_length, y, z, x + axis_length, y, z, 255, 0, 0)
    -- Y axis (green)
    Aliens.draw_debug_line(renderer, x, y - axis_length, z, x, y + axis_length, z, 0, 255, 0)
    -- Z axis (blue)
    Aliens.draw_debug_line(renderer, x, y, z - axis_length, x, y, z + axis_length, 0, 100, 255)

    -- Draw bounding box (wireframe) - yellow
    local r = radius
    -- Bottom face edges
    Aliens.draw_debug_line(renderer, x-r, y-r, z-r, x+r, y-r, z-r, 255, 255, 0)
    Aliens.draw_debug_line(renderer, x+r, y-r, z-r, x+r, y-r, z+r, 255, 255, 0)
    Aliens.draw_debug_line(renderer, x+r, y-r, z+r, x-r, y-r, z+r, 255, 255, 0)
    Aliens.draw_debug_line(renderer, x-r, y-r, z+r, x-r, y-r, z-r, 255, 255, 0)
    -- Top face edges
    Aliens.draw_debug_line(renderer, x-r, y+r, z-r, x+r, y+r, z-r, 255, 255, 0)
    Aliens.draw_debug_line(renderer, x+r, y+r, z-r, x+r, y+r, z+r, 255, 255, 0)
    Aliens.draw_debug_line(renderer, x+r, y+r, z+r, x-r, y+r, z+r, 255, 255, 0)
    Aliens.draw_debug_line(renderer, x-r, y+r, z+r, x-r, y+r, z-r, 255, 255, 0)
    -- Vertical edges
    Aliens.draw_debug_line(renderer, x-r, y-r, z-r, x-r, y+r, z-r, 255, 255, 0)
    Aliens.draw_debug_line(renderer, x+r, y-r, z-r, x+r, y+r, z-r, 255, 255, 0)
    Aliens.draw_debug_line(renderer, x+r, y-r, z+r, x+r, y+r, z+r, 255, 255, 0)
    Aliens.draw_debug_line(renderer, x-r, y-r, z+r, x-r, y+r, z+r, 255, 255, 0)

    -- Draw target line (orange line to target)
    if alien.target then
        local tx, ty, tz = alien.target.x, alien.target.y, alien.target.z
        Aliens.draw_debug_line(renderer, x, y, z, tx, ty, tz, 255, 150, 50)
    end
end

-- Draw a debug line using renderer's line drawing
function Aliens.draw_debug_line(renderer, x1, y1, z1, x2, y2, z2, r, g, b)
    -- Use the renderer's built-in line drawing
    renderer.drawLine3D({x1, y1, z1}, {x2, y2, z2}, r or 255, g or 50, b or 50, false)
end

return Aliens
