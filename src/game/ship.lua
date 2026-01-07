-- Ship module: VTOL vehicle with physics
-- Ported from Picotron version for Love2D

local obj_loader = require("obj_loader")
local Constants = require("constants")
local gameConfig = require("config")
local vec3 = require("vec3")
local mat4 = require("mat4")
local quat = require("quat")

local Ship = {}
Ship.__index = Ship

-- Create a new ship instance
function Ship.new(config)
    local self = setmetatable({}, Ship)

    config = config or {}

    -- Position
    self.x = config.spawn_x or 0
    self.y = config.spawn_y or 10
    self.z = config.spawn_z or 0

    -- Orientation as quaternion (no gimbal lock!)
    local spawn_yaw = config.spawn_yaw or 0
    self.orientation = quat.fromAxisAngle(0, 1, 0, spawn_yaw)

    -- Velocity & angular velocity (angular velocity is in local space)
    self.vx = 0
    self.vy = 0
    self.vz = 0
    -- Local-space angular velocities (for quaternion-based rotation)
    self.local_vpitch = 0
    self.local_vyaw = 0
    self.local_vroll = 0

    -- Physics constants (from config.lua)
    self.mass = config.mass or 30
    self.thrust = config.thrust or gameConfig.VTOL_THRUST
    self.gravity = config.gravity or gameConfig.VTOL_GRAVITY
    self.damping = config.damping or gameConfig.VTOL_DAMPING
    self.angular_damping = config.angular_damping or gameConfig.VTOL_ANGULAR_DAMPING

    -- Health and damage
    self.max_health = config.max_health or 100
    self.health = self.max_health
    self.damage_blink_timer = 0  -- Timer for damage blink effect

    -- Mesh data
    self.mesh = nil
    self.flame_mesh = nil
    self.model_scale = 0.15

    -- Thrusters: positions match Picotron exactly
    -- Engine positions are scaled by model_scale
    -- Matching Picotron: Right engine = D key, Left engine = A key
    -- 1=Right(D), 2=Left(A), 3=Front(W), 4=Back(S)
    self.thrusters = {
        {x = 6 * self.model_scale, z = 0, key = "D", active = false},   -- Thruster 1: Right side, key D
        {x = -6 * self.model_scale, z = 0, key = "A", active = false},  -- Thruster 2: Left side, key A
        {x = 0, z = 6 * self.model_scale, key = "W", active = false},   -- Thruster 3: Front, key W
        {x = 0, z = -6 * self.model_scale, key = "S", active = false},  -- Thruster 4: Back, key S
    }

    -- Engine positions for flame rendering (unscaled, in model space)
    self.engine_positions = {
        {x = 6, y = -2, z = 0},   -- Right
        {x = -6, y = -2, z = 0},  -- Left
        {x = 0, y = -2, z = 6},   -- Front
        {x = 0, y = -2, z = -6},  -- Back
    }

    -- Load mesh
    self:load_mesh()

    return self
end

-- Load ship mesh from OBJ file
function Ship:load_mesh()
    local success, result = pcall(function()
        return obj_loader.load("assets/cross_lander.obj")
    end)

    if success and result then
        self.mesh = result
        print("Ship mesh loaded: " .. #result.vertices .. " vertices, " .. #result.triangles .. " triangles")
    else
        print("Warning: Could not load ship mesh, using fallback cube")
        self.mesh = self:create_fallback_mesh()
    end

    local flame_success, flame_result = pcall(function()
        return obj_loader.load("assets/flame.obj")
    end)

    if flame_success and flame_result then
        self.flame_mesh = flame_result
        print("Flame mesh loaded: " .. #flame_result.vertices .. " vertices")
    else
        print("Warning: Could not load flame mesh, using fallback")
        self.flame_mesh = self:create_fallback_flame()
    end
end

-- Create a fallback cube mesh
function Ship:create_fallback_mesh()
    local s = 1.5
    return {
        vertices = {
            {pos = {-s, 0, -s}, uv = {0, 0}},
            {pos = {s, 0, -s}, uv = {1, 0}},
            {pos = {s, 0, s}, uv = {1, 1}},
            {pos = {-s, 0, s}, uv = {0, 1}},
            {pos = {-s, 3, -s}, uv = {0, 0}},
            {pos = {s, 3, -s}, uv = {1, 0}},
            {pos = {s, 3, s}, uv = {1, 1}},
            {pos = {-s, 3, s}, uv = {0, 1}},
        },
        triangles = {
            {1, 2, 3}, {1, 3, 4},
            {5, 7, 6}, {5, 8, 7},
            {1, 5, 6}, {1, 6, 2},
            {3, 7, 8}, {3, 8, 4},
            {4, 8, 5}, {4, 5, 1},
            {2, 6, 7}, {2, 7, 3},
        }
    }
end

-- Create a fallback flame mesh
function Ship:create_fallback_flame()
    local s = 0.5
    return {
        vertices = {
            {pos = {-s, 0, -s}, uv = {0, 0}},
            {pos = {s, 0, -s}, uv = {1, 0}},
            {pos = {s, 0, s}, uv = {1, 1}},
            {pos = {-s, 0, s}, uv = {0, 1}},
            {pos = {-s, 1, -s}, uv = {0, 0}},
            {pos = {s, 1, -s}, uv = {1, 0}},
            {pos = {s, 1, s}, uv = {1, 1}},
            {pos = {-s, 1, s}, uv = {0, 1}},
        },
        triangles = {
            {1, 2, 3}, {1, 3, 4},
            {5, 7, 6}, {5, 8, 7},
            {1, 5, 6}, {1, 6, 2},
            {3, 7, 8}, {3, 8, 4},
            {4, 8, 5}, {4, 5, 1},
            {2, 6, 7}, {2, 7, 3},
        }
    }
end

-- Reset ship to spawn position
function Ship:reset(spawn_x, spawn_y, spawn_z, spawn_yaw)
    self.x = spawn_x or self.x
    self.y = spawn_y or self.y
    self.z = spawn_z or self.z

    -- Reset orientation quaternion
    local yaw = spawn_yaw or 0
    self.orientation = quat.fromAxisAngle(0, 1, 0, yaw)

    -- Reset velocities
    self.vx = 0
    self.vy = 0
    self.vz = 0
    self.local_vpitch = 0
    self.local_vyaw = 0
    self.local_vroll = 0

    self.health = self.max_health
    self.damage_blink_timer = 0
end

-- Update thruster states from keyboard (called from flight_scene)
function Ship:update_thrusters()
    -- Check each key separately (like Picotron)
    local w_pressed = love.keyboard.isDown("w") or love.keyboard.isDown("i")
    local a_pressed = love.keyboard.isDown("a") or love.keyboard.isDown("j")
    local s_pressed = love.keyboard.isDown("s") or love.keyboard.isDown("k")
    local d_pressed = love.keyboard.isDown("d") or love.keyboard.isDown("l")

    -- Arcade mode special keys
    local space_pressed = love.keyboard.isDown("space")
    local n_pressed = love.keyboard.isDown("n")
    local m_pressed = love.keyboard.isDown("m")

    if space_pressed then
        -- Space: fire all thrusters
        self.thrusters[1].active = true
        self.thrusters[2].active = true
        self.thrusters[3].active = true
        self.thrusters[4].active = true
    elseif n_pressed then
        -- N: fire left/right pair (A+D)
        self.thrusters[1].active = true
        self.thrusters[2].active = true
        self.thrusters[3].active = false
        self.thrusters[4].active = false
    elseif m_pressed then
        -- M: fire front/back pair (W+S)
        self.thrusters[1].active = false
        self.thrusters[2].active = false
        self.thrusters[3].active = true
        self.thrusters[4].active = true
    else
        -- Normal WASD/IJKL controls (matching Picotron mapping)
        -- Thruster 1 = Right side (D key), Thruster 2 = Left side (A key)
        self.thrusters[1].active = d_pressed  -- Right thruster (D)
        self.thrusters[2].active = a_pressed  -- Left thruster (A)
        self.thrusters[3].active = w_pressed  -- Front thruster (W)
        self.thrusters[4].active = s_pressed  -- Back thruster (S)
    end
end

-- Update ship physics using quaternions (gimbal-lock free)
-- Uses delta time for frame-rate independent physics
function Ship:update(dt)
    -- Update thruster states
    self:update_thrusters()

    -- Update damage blink timer
    self:update_damage_blink(dt)

    -- Scale factor for 60 FPS equivalence (physics tuned for 60 FPS)
    -- This makes the simulation behave the same regardless of frame rate
    local timeScale = dt * 60

    -- Apply gravity (scaled by dt)
    self.vy = self.vy + self.gravity * timeScale

    -- Apply thrust and torque for each active thruster
    for i, thruster in ipairs(self.thrusters) do
        if thruster.active then
            -- Thrust direction is always upward in local space (0, 1, 0)
            -- Transform by quaternion to get world space thrust
            local tx, ty, tz = quat.rotateVector(self.orientation, 0, 1, 0)

            -- Apply thrust in world space (scaled by dt)
            self.vx = self.vx + tx * self.thrust * timeScale
            self.vy = self.vy + ty * self.thrust * timeScale
            self.vz = self.vz + tz * self.thrust * timeScale

            -- Apply torque as angular velocity in LOCAL space (scaled by dt)
            -- Thruster on front/back (z != 0) creates pitch around local X axis
            -- Thruster on left/right (x != 0) creates roll around local Z axis
            self.local_vpitch = self.local_vpitch + thruster.z * gameConfig.VTOL_TORQUE_PITCH * timeScale
            self.local_vroll = self.local_vroll + (-thruster.x) * gameConfig.VTOL_TORQUE_ROLL * timeScale
        end
    end

    -- Update position (scaled by dt)
    self.x = self.x + self.vx * timeScale
    self.y = self.y + self.vy * timeScale
    self.z = self.z + self.vz * timeScale

    -- Update orientation using LOCAL angular velocities (scaled by dt)
    -- Apply as local rotation: orientation = orientation * localRotation
    local deltaRotation = quat.fromEuler(
        -self.local_vroll * timeScale,
        -self.local_vyaw * timeScale,
        -self.local_vpitch * timeScale
    )
    self.orientation = quat.multiply(self.orientation, deltaRotation)
    self.orientation = quat.normalize(self.orientation)

    -- Apply damping (frame-rate independent using exponential decay)
    -- damping^60 per second -> damping^(60*dt) per frame
    local dampingFactor = math.pow(self.damping, timeScale)
    local angularDampingFactor = math.pow(self.angular_damping, timeScale)

    self.vx = self.vx * dampingFactor
    self.vy = self.vy * dampingFactor
    self.vz = self.vz * dampingFactor
    self.local_vpitch = self.local_vpitch * angularDampingFactor
    self.local_vyaw = self.local_vyaw * angularDampingFactor
    self.local_vroll = self.local_vroll * angularDampingFactor

    -- Height ceiling (like Picotron: 50 world units = 500m)
    local max_height = 50
    if self.y > max_height then
        self.y = max_height
        if self.vy > 0 then
            self.vy = 0
        end
        -- Disable all thrusters above ceiling
        for _, thruster in ipairs(self.thrusters) do
            thruster.active = false
        end
    end
end

-- Auto-level the ship (smoothly returns to upright orientation)
-- Called when shift key is held
function Ship:auto_level(dt)
    -- Frame-rate independent lerp factor (tuned for 60 FPS base)
    local timeScale = dt * 60
    local level_speed = 1.0 - math.pow(0.95, timeScale)

    -- Extract the ship's forward direction from the quaternion
    -- This is more robust than extracting Euler angles when pitch/roll are non-zero
    local rotMatrix = quat.toMatrix(self.orientation)

    -- Forward vector is the third column (Z-axis after rotation)
    -- In our coordinate system: +Z is forward
    local fwd_x = rotMatrix[3]   -- m[1][3]
    local fwd_z = rotMatrix[11]  -- m[3][3]

    -- Calculate yaw from the forward direction projected onto XZ plane
    local yaw = math.atan2(fwd_x, fwd_z)

    -- Create target orientation with same yaw but zero pitch/roll
    local target = quat.fromAxisAngle(0, 1, 0, yaw)

    -- Slerp towards target orientation (frame-rate independent)
    self.orientation = quat.slerp(self.orientation, target, level_speed)
    self.orientation = quat.normalize(self.orientation)

    -- Also dampen angular velocities heavily (frame-rate independent)
    local angularDamping = math.pow(0.8, timeScale)
    self.local_vpitch = self.local_vpitch * angularDamping
    self.local_vroll = self.local_vroll * angularDamping
end

-- Draw ship using the renderer
function Ship:draw(renderer, texData)
    if not self.mesh then return end

    -- Build model matrix using quaternion rotation (no gimbal lock!)
    -- Order: Translation * Rotation * Scale
    local scaleMatrix = mat4.scale(self.model_scale, self.model_scale, self.model_scale)
    local rotationMatrix = quat.toMatrix(self.orientation)
    local modelMatrix = mat4.multiply(rotationMatrix, scaleMatrix)
    modelMatrix = mat4.multiply(mat4.translation(self.x, self.y, self.z), modelMatrix)

    -- Get ship texture (blink red when damage_blink_timer > 0)
    local shipTexData = texData or Constants.getTextureData(Constants.SPRITE_SHIP)
    if self.damage_blink_timer > 0 then
        shipTexData = Constants.getTextureData(Constants.SPRITE_SHIP_DAMAGE) or shipTexData
    end

    -- Use Gouraud or flat shading based on config
    if gameConfig.GOURAUD_SHADING and renderer.drawMeshGouraud then
        renderer.drawMeshGouraud(self.mesh, modelMatrix, shipTexData, mat4)
    elseif renderer.drawMeshFlat then
        renderer.drawMeshFlat(self.mesh, modelMatrix, shipTexData, mat4)
    else
        -- Fallback: draw without lighting
        for _, tri in ipairs(self.mesh.triangles) do
            local v1 = self.mesh.vertices[tri[1]]
            local v2 = self.mesh.vertices[tri[2]]
            local v3 = self.mesh.vertices[tri[3]]

            local p1 = mat4.multiplyVec4(modelMatrix, {v1.pos[1], v1.pos[2], v1.pos[3], 1})
            local p2 = mat4.multiplyVec4(modelMatrix, {v2.pos[1], v2.pos[2], v2.pos[3], 1})
            local p3 = mat4.multiplyVec4(modelMatrix, {v3.pos[1], v3.pos[2], v3.pos[3], 1})

            renderer.drawTriangle3D(
                {pos = {p1[1], p1[2], p1[3]}, uv = v1.uv},
                {pos = {p2[1], p2[2], p2[3]}, uv = v2.uv},
                {pos = {p3[1], p3[2], p3[3]}, uv = v3.uv},
                nil,
                shipTexData
            )
        end
    end

    -- Draw flames for active thrusters
    self:draw_flames(renderer, modelMatrix)
end

-- Draw flames attached to ship (matching Picotron flame animation)
function Ship:draw_flames(renderer, shipModelMatrix)
    local flameTexData = Constants.getTextureData(Constants.SPRITE_FLAME)
    if not flameTexData or not self.flame_mesh then return end

    local flame_time = love.timer.getTime() * 6

    for i, thruster in ipairs(self.thrusters) do
        if thruster.active then
            local engine = self.engine_positions[i]

            -- Flame animation (matching Picotron)
            local base_flicker = math.sin(flame_time + i * 2.5) * 0.03
            local noise = math.sin(flame_time * 3.7 + i * 0.5) * 0.015
            noise = noise + math.sin(flame_time * 7.2 + i * 1.3) * 0.01
            local scale_mod = 1.0 + base_flicker + noise

            -- Build flame matrix: scale flame mesh, translate to engine position, apply ship rotation and translate
            -- This matches Picotron where flames are part of ship mesh and rotated together
            local flameScale = self.model_scale * scale_mod

            -- Start with flame scale
            local flameMatrix = mat4.scale(flameScale, flameScale * 1.2, flameScale)

            -- Translate to engine position in model space (before ship rotation)
            flameMatrix = mat4.multiply(mat4.translation(engine.x * self.model_scale, engine.y * self.model_scale, engine.z * self.model_scale), flameMatrix)

            -- Apply ship rotation using quaternion (no gimbal lock!)
            local rotationMatrix = quat.toMatrix(self.orientation)
            flameMatrix = mat4.multiply(rotationMatrix, flameMatrix)

            -- Finally translate to ship world position
            flameMatrix = mat4.multiply(mat4.translation(self.x, self.y, self.z), flameMatrix)

            for _, tri in ipairs(self.flame_mesh.triangles) do
                local v1 = self.flame_mesh.vertices[tri[1]]
                local v2 = self.flame_mesh.vertices[tri[2]]
                local v3 = self.flame_mesh.vertices[tri[3]]

                local p1 = mat4.multiplyVec4(flameMatrix, {v1.pos[1], v1.pos[2], v1.pos[3], 1})
                local p2 = mat4.multiplyVec4(flameMatrix, {v2.pos[1], v2.pos[2], v2.pos[3], 1})
                local p3 = mat4.multiplyVec4(flameMatrix, {v3.pos[1], v3.pos[2], v3.pos[3], 1})

                -- Flames are emissive (configurable brightness and transparency)
                renderer.drawTriangle3D(
                    {pos = {p1[1], p1[2], p1[3]}, uv = v1.uv},
                    {pos = {p2[1], p2[2], p2[3]}, uv = v2.uv},
                    {pos = {p3[1], p3[2], p3[3]}, uv = v3.uv},
                    nil,
                    flameTexData,
                    gameConfig.FLAME_BRIGHTNESS or 1.0,
                    gameConfig.FLAME_ALPHA or 0.5
                )
            end
        end
    end
end

-- Take damage (triggers temporary blink effect)
function Ship:take_damage(amount)
    self.health = self.health - amount
    if self.health < 0 then
        self.health = 0
    end
    -- Start damage blink timer (0.15 seconds)
    self.damage_blink_timer = 0.15
end

-- Heal the ship
function Ship:heal(amount)
    self.health = self.health + amount
    if self.health > self.max_health then
        self.health = self.max_health
    end
end

-- Update damage blink timer (call this from update)
function Ship:update_damage_blink(dt)
    if self.damage_blink_timer > 0 then
        self.damage_blink_timer = self.damage_blink_timer - dt
        if self.damage_blink_timer < 0 then
            self.damage_blink_timer = 0
        end
    end
end

-- Get position as vec3
function Ship:get_position()
    return vec3.new(self.x, self.y, self.z)
end

-- Check if ship is destroyed
function Ship:is_destroyed()
    return self.health <= 0
end

-- Get rotation matrix from quaternion (for external use)
function Ship:get_rotation_matrix()
    return quat.toMatrix(self.orientation)
end

-- Get model matrix (translation * rotation * scale)
function Ship:get_model_matrix()
    local scaleMatrix = mat4.scale(self.model_scale, self.model_scale, self.model_scale)
    local rotationMatrix = quat.toMatrix(self.orientation)
    local modelMatrix = mat4.multiply(rotationMatrix, scaleMatrix)
    return mat4.multiply(mat4.translation(self.x, self.y, self.z), modelMatrix)
end

return Ship
