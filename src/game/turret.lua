-- Turret module: Player auto-turret
-- Ported from Picotron version

local quat = require("quat")
local mat4 = require("mat4")
local Constants = require("constants")

local Turret = {}

-- Turret mount configuration
Turret.MOUNT_OFFSET_X = 0     -- X offset from ship center
Turret.MOUNT_OFFSET_Y = 0.3   -- Y offset (positive = above ship)
Turret.MOUNT_OFFSET_Z = 0.0   -- Z offset from ship center

-- Turret configuration
Turret.FIRE_ARC = 0.5         -- 180 degrees (half hemisphere)
Turret.FIRE_RANGE = 20        -- 200 meters (20 units)
Turret.ROTATION_SPEED = 0.1   -- How fast turret rotates to target
Turret.MAX_PITCH = 0.125      -- Max pitch up/down (45 degrees)
Turret.MAX_YAW = 0.25         -- Max yaw left/right from ship forward

-- Turret state
Turret.orientation = nil      -- Current orientation (quaternion)
Turret.target = nil           -- Current target
Turret.can_fire_now = false   -- Whether turret can fire this frame

-- Turret geometry (long thin box)
Turret.verts = nil
Turret.faces = nil

-- Initialize turret geometry
function Turret.init()
    -- Long cube (0.5 units long, thin cross section)
    local length = 0.5
    local width = 0.05
    local height = 0.05

    -- Create vertices for a box pointing in -Z direction (forward)
    Turret.verts = {
        {-width/2, -height/2, -length},  -- 1: bottom back left
        {width/2, -height/2, -length},   -- 2: bottom back right
        {width/2, -height/2, 0},         -- 3: bottom front right
        {-width/2, -height/2, 0},        -- 4: bottom front left
        {-width/2, height/2, -length},   -- 5: top back left
        {width/2, height/2, -length},    -- 6: top back right
        {width/2, height/2, 0},          -- 7: top front right
        {-width/2, height/2, 0}          -- 8: top front left
    }

    -- Faces (triangulated for renderer)
    Turret.faces = {
        -- Bottom
        {1, 2, 3}, {1, 3, 4},
        -- Top
        {5, 7, 6}, {5, 8, 7},
        -- Back
        {1, 5, 6}, {1, 6, 2},
        -- Front
        {3, 7, 8}, {3, 8, 4},
        -- Left
        {4, 8, 5}, {4, 5, 1},
        -- Right
        {2, 6, 7}, {2, 7, 3}
    }

    -- Initialize orientation to identity
    Turret.orientation = quat.identity()
    Turret.can_fire_now = false
end

-- Find best target from list of enemies
function Turret.find_target(ship, enemies)
    local best_target = nil
    local best_score = -999

    for _, enemy in ipairs(enemies) do
        local dx = enemy.x - ship.x
        local dy = enemy.y - ship.y
        local dz = enemy.z - ship.z
        local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

        -- Check if in range
        if dist <= Turret.FIRE_RANGE then
            -- Prioritize closer enemies
            local score = (Turret.FIRE_RANGE - dist) / Turret.FIRE_RANGE
            if score > best_score then
                best_score = score
                best_target = enemy
            end
        end
    end

    return best_target
end

-- Check if target is in upper hemisphere (turret can only aim up)
local function check_firing_constraints(dir_x, dir_y, dir_z)
    -- Dot product with up vector (0, 1, 0)
    -- If positive, target is above ship
    return dir_y > 0
end

-- Create quaternion that looks at a direction
local function look_at(dir_x, dir_y, dir_z)
    -- Normalize direction
    local mag = math.sqrt(dir_x*dir_x + dir_y*dir_y + dir_z*dir_z)
    if mag < 0.0001 then
        return quat.identity()
    end
    dir_x, dir_y, dir_z = dir_x/mag, dir_y/mag, dir_z/mag

    -- Calculate yaw and pitch
    local yaw = math.atan2(dir_x, dir_z)
    local horizontal_dist = math.sqrt(dir_x*dir_x + dir_z*dir_z)
    local pitch = -math.atan2(dir_y, horizontal_dist)

    -- Convert to quaternion (yaw around Y, pitch around X)
    local qy = quat.fromAxisAngle(0, 1, 0, yaw)
    local qx = quat.fromAxisAngle(1, 0, 0, pitch)
    return quat.multiply(qy, qx)
end

-- Update turret (find target and rotate toward it)
function Turret.update(dt, ship, enemies)
    -- Find target
    Turret.target = Turret.find_target(ship, enemies)

    -- Get turret world position
    local turret_x, turret_y, turret_z = Turret.get_position(ship)

    local target_quat
    if Turret.target then
        -- Direction to enemy (normalized)
        local dx = Turret.target.x - ship.x
        local dy = Turret.target.y - ship.y
        local dz = Turret.target.z - ship.z
        local mag = math.sqrt(dx*dx + dy*dy + dz*dz)
        if mag > 0.0001 then
            dx, dy, dz = dx/mag, dy/mag, dz/mag
        end

        -- Check if enemy is in upper hemisphere
        Turret.can_fire_now = check_firing_constraints(dx, dy, dz)

        if Turret.can_fire_now then
            -- Aim at target
            local tdx = Turret.target.x - turret_x
            local tdy = Turret.target.y - turret_y
            local tdz = Turret.target.z - turret_z
            target_quat = look_at(tdx, tdy, tdz)
        else
            -- Enemy below - point turret up
            target_quat = look_at(0, 1, 0)
        end
    else
        -- No target - point turret up
        target_quat = look_at(0, 1, 0)
        Turret.can_fire_now = false
    end

    -- Slerp toward target orientation
    Turret.orientation = quat.slerp(Turret.orientation, target_quat, Turret.ROTATION_SPEED)
    Turret.orientation = quat.normalize(Turret.orientation)
end

-- Check if turret can fire
function Turret.can_fire()
    return Turret.can_fire_now
end

-- Get firing direction (toward target)
function Turret.get_fire_direction(ship)
    if not Turret.target then
        return nil
    end

    local turret_x, turret_y, turret_z = Turret.get_position(ship)

    -- Direction from turret to target
    local dir_x = Turret.target.x - turret_x
    local dir_y = Turret.target.y - turret_y
    local dir_z = Turret.target.z - turret_z

    -- Normalize
    local mag = math.sqrt(dir_x*dir_x + dir_y*dir_y + dir_z*dir_z)
    if mag < 0.0001 then
        return 0, 0, 1  -- Default forward
    end
    return dir_x/mag, dir_y/mag, dir_z/mag
end

-- Get turret position in world space (mounted on ship)
function Turret.get_position(ship)
    local offset_x = Turret.MOUNT_OFFSET_X
    local offset_y = Turret.MOUNT_OFFSET_Y
    local offset_z = Turret.MOUNT_OFFSET_Z

    -- Transform offset by ship orientation
    local offset = {offset_x, offset_y, offset_z, 1}
    local rotMatrix = quat.toMatrix(ship.orientation)
    local transformed = mat4.multiplyVec4(rotMatrix, offset)

    return ship.x + transformed[1], ship.y + transformed[2], ship.z + transformed[3]
end

-- Draw turret
function Turret.draw(renderer, ship)
    if not Turret.verts or not Turret.faces then
        Turret.init()
    end

    local texData = Constants.getTextureData(Constants.SPRITE_TURRET)
    if not texData then return end

    -- Get turret world position
    local turret_x, turret_y, turret_z = Turret.get_position(ship)

    -- Build turret model matrix: translation * rotation
    local rotMatrix = quat.toMatrix(Turret.orientation)
    local transMatrix = mat4.translation(turret_x, turret_y, turret_z)
    local modelMatrix = mat4.multiply(transMatrix, rotMatrix)

    -- Transform and draw each face
    for _, face in ipairs(Turret.faces) do
        local v1 = Turret.verts[face[1]]
        local v2 = Turret.verts[face[2]]
        local v3 = Turret.verts[face[3]]

        -- Transform vertices
        local t1 = mat4.multiplyVec4(modelMatrix, {v1[1], v1[2], v1[3], 1})
        local t2 = mat4.multiplyVec4(modelMatrix, {v2[1], v2[2], v2[3], 1})
        local t3 = mat4.multiplyVec4(modelMatrix, {v3[1], v3[2], v3[3], 1})

        -- Draw triangle
        renderer.drawTriangle3D(
            {pos = {t1[1], t1[2], t1[3]}, uv = {0, 0}},
            {pos = {t2[1], t2[2], t2[3]}, uv = {1, 0}},
            {pos = {t3[1], t3[2], t3[3]}, uv = {1, 1}},
            nil,
            texData
        )
    end
end

-- Reset turret
function Turret.reset()
    Turret.orientation = quat.identity()
    Turret.target = nil
    Turret.can_fire_now = false
end

return Turret
