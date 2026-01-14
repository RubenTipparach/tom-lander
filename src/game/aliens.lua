-- Aliens module: UFO fighters and mother ship
-- Ported from Picotron version

local quat = require("quat")
local mat4 = require("mat4")
local obj_loader = require("obj_loader")
local Constants = require("constants")
local config = require("config")

local Aliens = {}

-- Alien configuration
Aliens.FIGHTER_HEALTH = 100
Aliens.MOTHER_SHIP_HEALTH = 1000
Aliens.FIGHTER_SPEED = 2.0  -- Units per second
Aliens.FIGHTER_FIRE_RATE = 2  -- Bullets per second
Aliens.FIGHTER_FIRE_ARC = 0.125  -- 45 degrees
Aliens.FIGHTER_FIRE_RANGE = 15  -- Units

-- Fighter AI behavior
Aliens.FIGHTER_ENGAGE_DIST = 10   -- Get close (100 meters)
Aliens.FIGHTER_RETREAT_DIST = 20  -- Retreat distance (200 meters)
Aliens.FIGHTER_ENGAGE_TIME = 10   -- Seconds to circle close
Aliens.FIGHTER_RETREAT_TIME = 15  -- Seconds to stay far
Aliens.FIGHTER_STATE_TIME_VARIANCE = 5  -- +/- seconds randomization
Aliens.FIGHTER_CIRCLE_SPEED = 0.3  -- Rotation speed when circling
Aliens.FIGHTER_CIRCLE_RADIUS = 10  -- Circle radius in units
Aliens.FIGHTER_CIRCLE_HEIGHT_OFFSET = 2  -- Height above player
Aliens.FIGHTER_APPROACH_THRESHOLD = 2  -- Distance threshold
Aliens.FIGHTER_MIN_ALTITUDE = 3  -- Minimum altitude (30 meters - closer to player)
Aliens.FIGHTER_MAX_ALTITUDE = 20  -- Maximum altitude (200 meters)
Aliens.FIGHTER_ALTITUDE_CLIMB_SPEED = 0.5
Aliens.FIGHTER_ALTITUDE_DESCEND_SPEED = -0.2
Aliens.FIGHTER_BANK_MULTIPLIER = 10  -- Banking intensity
Aliens.FIGHTER_MAX_BANK = 0.083  -- Max bank angle (30 degrees)
Aliens.FIGHTER_BANK_DAMPING = 0.9

-- Mother ship behavior
Aliens.MOTHER_SHIP_FIRE_RATE = 1  -- Bullets per second
Aliens.MOTHER_SHIP_FIRE_RANGE = 25
Aliens.MOTHER_SHIP_HOVER_HEIGHT = 10
Aliens.MOTHER_SHIP_MAX_HEIGHT = 30
Aliens.MOTHER_SHIP_DESCEND_SPEED = -0.1

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
        yaw = 0,
        roll = 0,
        prev_yaw = 0,
        health = Aliens.FIGHTER_HEALTH,
        max_health = Aliens.FIGHTER_HEALTH,
        fire_timer = 0,
        target = nil,
        type = "fighter",
        -- AI state
        ai_state = "engage",
        ai_timer = 0,
        ai_duration = Aliens.FIGHTER_ENGAGE_TIME + (math.random() * 2 - 1) * Aliens.FIGHTER_STATE_TIME_VARIANCE,
        circle_angle = math.random()
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
function Aliens.update(dt, player, player_on_pad)
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
            Aliens.update_fighter(fighter, dt, player, player_on_pad)
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

-- Update fighter AI
function Aliens.update_fighter(fighter, dt, player, player_on_pad)
    fighter.ai_timer = fighter.ai_timer + dt

    -- Direction to player
    local dx = player.x - fighter.x
    local dy = player.y - fighter.y
    local dz = player.z - fighter.z
    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

    -- If player is on landing pad, fly away from city center
    if player_on_pad then
        -- Direction away from city center (0,0)
        local to_center_x = -fighter.x
        local to_center_z = -fighter.z
        local center_dist = math.sqrt(to_center_x * to_center_x + to_center_z * to_center_z)

        if center_dist > 0.1 then
            -- Fly away from center at faster speed
            local flee_speed = Aliens.FIGHTER_SPEED * 1.5
            fighter.vx = -(to_center_x / center_dist) * flee_speed
            fighter.vz = -(to_center_z / center_dist) * flee_speed
            -- Maintain altitude
            if fighter.y < Aliens.FIGHTER_MIN_ALTITUDE + 5 then
                fighter.vy = Aliens.FIGHTER_ALTITUDE_CLIMB_SPEED * 2
            else
                fighter.vy = 0
            end
        end

        -- Update position and rotation, skip normal AI
        fighter.x = fighter.x + fighter.vx * dt
        fighter.y = fighter.y + fighter.vy * dt
        fighter.z = fighter.z + fighter.vz * dt

        -- Rotate to face velocity
        fighter.prev_yaw = fighter.yaw
        fighter.yaw = math.atan2(fighter.vx, fighter.vz)
        return  -- Skip normal AI when retreating from safe zone
    end

    if fighter.ai_state == "engage" then
        -- Engage: fly close and circle
        if fighter.ai_timer >= fighter.ai_duration then
            fighter.ai_state = "retreat"
            fighter.ai_timer = 0
            fighter.ai_duration = Aliens.FIGHTER_RETREAT_TIME + (math.random() * 2 - 1) * Aliens.FIGHTER_STATE_TIME_VARIANCE
        end

        local desired_dist = Aliens.FIGHTER_ENGAGE_DIST

        if dist > desired_dist + Aliens.FIGHTER_APPROACH_THRESHOLD then
            -- Move toward player
            local dir_x = dx / dist
            local dir_y = dy / dist
            local dir_z = dz / dist
            fighter.vx = dir_x * Aliens.FIGHTER_SPEED
            fighter.vy = dir_y * Aliens.FIGHTER_SPEED
            fighter.vz = dir_z * Aliens.FIGHTER_SPEED
        else
            -- Circle around player
            fighter.circle_angle = fighter.circle_angle + dt * Aliens.FIGHTER_CIRCLE_SPEED
            local circle_x = player.x + math.cos(fighter.circle_angle * math.pi * 2) * Aliens.FIGHTER_CIRCLE_RADIUS
            local circle_z = player.z + math.sin(fighter.circle_angle * math.pi * 2) * Aliens.FIGHTER_CIRCLE_RADIUS
            local circle_y = player.y + Aliens.FIGHTER_CIRCLE_HEIGHT_OFFSET

            local to_x = circle_x - fighter.x
            local to_y = circle_y - fighter.y
            local to_z = circle_z - fighter.z
            local to_dist = math.sqrt(to_x*to_x + to_y*to_y + to_z*to_z)

            if to_dist > 0.1 then
                fighter.vx = (to_x / to_dist) * Aliens.FIGHTER_SPEED
                fighter.vy = (to_y / to_dist) * Aliens.FIGHTER_SPEED
                fighter.vz = (to_z / to_dist) * Aliens.FIGHTER_SPEED
            end
        end

    elseif fighter.ai_state == "retreat" then
        -- Retreat: fly away
        if fighter.ai_timer >= fighter.ai_duration then
            fighter.ai_state = "engage"
            fighter.ai_timer = 0
            fighter.ai_duration = Aliens.FIGHTER_ENGAGE_TIME + (math.random() * 2 - 1) * Aliens.FIGHTER_STATE_TIME_VARIANCE
        end

        local desired_dist = Aliens.FIGHTER_RETREAT_DIST

        if dist < desired_dist - Aliens.FIGHTER_APPROACH_THRESHOLD then
            -- Move away from player
            local dir_x = -dx / dist
            local dir_y = -dy / dist
            local dir_z = -dz / dist
            fighter.vx = dir_x * Aliens.FIGHTER_SPEED
            fighter.vy = dir_y * Aliens.FIGHTER_SPEED
            fighter.vz = dir_z * Aliens.FIGHTER_SPEED
        else
            -- Hold position
            fighter.vx = 0
            fighter.vy = 0
            fighter.vz = 0
        end
    end

    -- Stay above minimum altitude
    if fighter.y < Aliens.FIGHTER_MIN_ALTITUDE then
        fighter.vy = Aliens.FIGHTER_ALTITUDE_CLIMB_SPEED
    elseif fighter.y > Aliens.FIGHTER_MAX_ALTITUDE then
        fighter.vy = Aliens.FIGHTER_ALTITUDE_DESCEND_SPEED
    end

    -- Update position
    fighter.x = fighter.x + fighter.vx * dt
    fighter.y = fighter.y + fighter.vy * dt
    fighter.z = fighter.z + fighter.vz * dt

    -- Rotate to face velocity
    local new_yaw = math.atan2(fighter.vx, fighter.vz)

    -- Calculate banking
    local yaw_change = new_yaw - fighter.prev_yaw
    while yaw_change > math.pi do yaw_change = yaw_change - math.pi * 2 end
    while yaw_change < -math.pi do yaw_change = yaw_change + math.pi * 2 end

    fighter.roll = -yaw_change * Aliens.FIGHTER_BANK_MULTIPLIER
    fighter.roll = math.max(-Aliens.FIGHTER_MAX_BANK * math.pi * 2, math.min(Aliens.FIGHTER_MAX_BANK * math.pi * 2, fighter.roll))

    if math.abs(yaw_change) < 0.01 then
        fighter.roll = fighter.roll * Aliens.FIGHTER_BANK_DAMPING
    end

    fighter.prev_yaw = fighter.yaw
    fighter.yaw = new_yaw

    -- Shoot at player
    fighter.fire_timer = fighter.fire_timer + dt

    if not player_on_pad and fighter.ai_state == "engage" and dist <= Aliens.FIGHTER_FIRE_RANGE then
        if fighter.fire_timer >= (1 / Aliens.FIGHTER_FIRE_RATE) then
            local to_player_x = dx / dist
            local to_player_y = dy / dist
            local to_player_z = dz / dist

            if Aliens.spawn_bullet then
                Aliens.spawn_bullet(
                    fighter.x, fighter.y, fighter.z,
                    to_player_x, to_player_y, to_player_z,
                    Aliens.FIGHTER_FIRE_RANGE
                )
            end
            fighter.fire_timer = 0
        end
    end
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

    -- Shoot at player
    mother.fire_timer = mother.fire_timer + dt

    local dx = player.x - mother.x
    local dy = player.y - mother.y
    local dz = player.z - mother.z
    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

    if not player_on_pad and dist <= Aliens.MOTHER_SHIP_FIRE_RANGE then
        local to_player_x = dx / dist
        local to_player_y = dy / dist
        local to_player_z = dz / dist

        -- Check if player is below (dot product with down vector)
        local dot = to_player_y * (-1)

        if dot > 0 and mother.fire_timer >= (1 / Aliens.MOTHER_SHIP_FIRE_RATE) then
            if Aliens.spawn_bullet then
                -- Two bullets with spread
                local spread = 0.1
                Aliens.spawn_bullet(
                    mother.x - spread, mother.y, mother.z,
                    to_player_x, to_player_y, to_player_z,
                    Aliens.MOTHER_SHIP_FIRE_RANGE
                )
                Aliens.spawn_bullet(
                    mother.x + spread, mother.y, mother.z,
                    to_player_x, to_player_y, to_player_z,
                    Aliens.MOTHER_SHIP_FIRE_RANGE
                )
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

    -- Draw mother ship
    if Aliens.mother_ship then
        Aliens.draw_alien(renderer, Aliens.mother_ship, Aliens.mother_mesh, mother_tex, 1.0)
    end
end

-- Draw an alien using OBJ mesh (like ship.lua)
function Aliens.draw_alien(renderer, alien, mesh, texData, scale)
    if not mesh or not texData then return end
    if not mesh.triangles or #mesh.triangles == 0 then return end

    -- Build model matrix with yaw and roll (for fighters)
    local yawQ = quat.fromAxisAngle(0, 1, 0, alien.yaw)
    local rollQ = quat.fromAxisAngle(0, 0, 1, alien.roll or 0)
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

-- Draw debug visuals for combat (bounding boxes, velocity lines, target lines)
function Aliens.draw_debug(renderer)
    if not config.COMBAT_DEBUG then return end

    -- Draw debug for all fighters
    for _, fighter in ipairs(Aliens.fighters) do
        Aliens.draw_alien_debug(renderer, fighter, 0.5, 0, 255, 255)  -- Cyan velocity
    end

    -- Draw debug for mother ship
    if Aliens.mother_ship then
        Aliens.draw_alien_debug(renderer, Aliens.mother_ship, 2.0, 255, 0, 255)  -- Magenta velocity
    end
end

-- Draw debug visuals for a single alien
function Aliens.draw_alien_debug(renderer, alien, radius, vel_r, vel_g, vel_b)
    local x, y, z = alien.x, alien.y, alien.z

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

    -- Draw velocity vector (colored line showing movement direction)
    local vel_scale = 2.0  -- Scale velocity for visibility
    local vx, vy, vz = alien.vx * vel_scale, alien.vy * vel_scale, alien.vz * vel_scale
    Aliens.draw_debug_line(renderer, x, y, z, x + vx, y + vy, z + vz, vel_r, vel_g, vel_b)

    -- Draw target line (red line to target)
    if alien.target then
        local tx, ty, tz = alien.target.x, alien.target.y, alien.target.z
        Aliens.draw_debug_line(renderer, x, y, z, tx, ty, tz, 255, 50, 50)
    end
end

-- Draw a debug line using renderer's line drawing
function Aliens.draw_debug_line(renderer, x1, y1, z1, x2, y2, z2, r, g, b)
    -- Use the renderer's built-in line drawing
    renderer.drawLine3D({x1, y1, z1}, {x2, y2, z2}, r or 255, g or 50, b or 50, false)
end

return Aliens
