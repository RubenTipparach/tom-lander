-- Particle System Module
-- Handles creation, updating, and rendering of 3D particles
-- Adapted from Picotron version for Love2D

local Constants = require("constants")
local mat4 = require("mat4")

local ParticleSystem = {}
ParticleSystem.__index = ParticleSystem

-- Create a new particle system
function ParticleSystem.new(config)
    local self = setmetatable({}, ParticleSystem)

    config = config or {}

    -- Configuration
    self.particle_size = config.size or 0.16
    self.max_particles = config.max_particles or 4
    self.particle_lifetime = config.lifetime or 2.0
    self.spawn_rate = config.spawn_rate or 0.3
    self.sprite_id = config.sprite_id or Constants.SPRITE_SMOKE
    self.scale_growth = config.scale_growth or 1.5  -- How much to grow over lifetime

    -- State
    self.particles = {}
    self.spawn_timer = 0

    -- Billboard mode: use camera-facing quads
    self.use_billboards = config.use_billboards ~= false

    -- Initialize particle pool
    for i = 1, self.max_particles do
        table.insert(self.particles, {
            active = false,
            life = 0,
            x = 0, y = 0, z = 0,
            vx = 0, vy = 0, vz = 0,
            rot_x = 0, rot_y = 0, rot_z = 0,
            vrot_x = 0, vrot_y = 0, vrot_z = 0
        })
    end

    return self
end

-- Spawn a new particle at a given position with initial velocity
function ParticleSystem:spawn(x, y, z, vx, vy, vz, config)
    config = config or {}

    -- Find inactive particle slot
    for _, particle in ipairs(self.particles) do
        if not particle.active then
            particle.active = true
            particle.life = 0
            particle.x = x
            particle.y = y
            particle.z = z

            -- Set velocity (inherit + random offset)
            local random_vx = config.random_vx or ((math.random() * 2 - 1) * 0.02)
            local random_vy = config.random_vy or (math.random() * 0.03 + 0.01)
            local random_vz = config.random_vz or ((math.random() * 2 - 1) * 0.02)

            particle.vx = (vx or 0) + random_vx
            particle.vy = (vy or 0) + random_vy
            particle.vz = (vz or 0) + random_vz

            -- No rotation for smoke
            particle.rot_x = 0
            particle.rot_y = 0
            particle.rot_z = 0
            particle.vrot_x = 0
            particle.vrot_y = 0
            particle.vrot_z = 0

            return true
        end
    end

    return false  -- No available slots
end

-- Update all active particles
function ParticleSystem:update(dt)
    for _, particle in ipairs(self.particles) do
        if particle.active then
            particle.life = particle.life + dt

            -- Update position
            particle.x = particle.x + particle.vx
            particle.y = particle.y + particle.vy
            particle.z = particle.z + particle.vz

            -- Apply drag
            particle.vx = particle.vx * 0.98
            particle.vy = particle.vy * 0.98
            particle.vz = particle.vz * 0.98

            -- Deactivate particle when it expires
            if particle.life >= self.particle_lifetime then
                particle.active = false
            end
        end
    end
end

-- Draw all active particles using the renderer
function ParticleSystem:draw(renderer, camera)
    local texData = Constants.getTextureData(self.sprite_id)
    if not texData then return end

    for _, particle in ipairs(self.particles) do
        if particle.active then
            local life_progress = particle.life / self.particle_lifetime

            -- Scale grows over lifetime
            local scale = (1.0 + life_progress * self.scale_growth) * self.particle_size

            -- Opacity grows from 25% to 100% over lifetime (for dithering)
            local opacity = 0.25 + (life_progress * 0.75)

            if opacity > 0 and self.use_billboards and camera then
                -- BILLBOARD MODE: Create camera-facing quad
                local half_size = scale

                -- Camera forward vector (matching Picotron: rx=pitch, ry=yaw)
                -- Picotron uses sin/cos directly (0-1 range), Love2D uses radians
                local forward_x = math.sin(camera.yaw) * math.cos(camera.pitch)
                local forward_y = math.sin(camera.pitch)  -- Match Picotron's sign
                local forward_z = math.cos(camera.yaw) * math.cos(camera.pitch)

                -- Camera right vector (perpendicular to forward, in XZ plane)
                local right_x = math.cos(camera.yaw)
                local right_y = 0
                local right_z = -math.sin(camera.yaw)

                -- Camera up vector (cross product of forward and right, inverted - matching Picotron)
                local up_x = -(forward_y * right_z - forward_z * right_y)
                local up_y = -(forward_z * right_x - forward_x * right_z)
                local up_z = -(forward_x * right_y - forward_y * right_x)

                -- Build quad vertices
                local v1 = {
                    pos = {
                        particle.x - right_x * half_size + up_x * half_size,
                        particle.y - right_y * half_size + up_y * half_size,
                        particle.z - right_z * half_size + up_z * half_size
                    },
                    uv = {0, 0}
                }
                local v2 = {
                    pos = {
                        particle.x + right_x * half_size + up_x * half_size,
                        particle.y + right_y * half_size + up_y * half_size,
                        particle.z + right_z * half_size + up_z * half_size
                    },
                    uv = {1, 0}
                }
                local v3 = {
                    pos = {
                        particle.x + right_x * half_size - up_x * half_size,
                        particle.y + right_y * half_size - up_y * half_size,
                        particle.z + right_z * half_size - up_z * half_size
                    },
                    uv = {1, 1}
                }
                local v4 = {
                    pos = {
                        particle.x - right_x * half_size - up_x * half_size,
                        particle.y - right_y * half_size - up_y * half_size,
                        particle.z - right_z * half_size - up_z * half_size
                    },
                    uv = {0, 1}
                }

                -- Draw two triangles forming a quad
                renderer.drawTriangle3D(v1, v2, v3, nil, texData)
                renderer.drawTriangle3D(v1, v3, v4, nil, texData)
            end
        end
    end
end

-- Get count of active particles
function ParticleSystem:get_active_count()
    local count = 0
    for _, particle in ipairs(self.particles) do
        if particle.active then
            count = count + 1
        end
    end
    return count
end

-- Clear all particles
function ParticleSystem:clear()
    for _, particle in ipairs(self.particles) do
        particle.active = false
    end
end

return ParticleSystem
