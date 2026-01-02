-- Speed Lines Module
-- 3D particle lines that show motion/speed effect
-- Ported from Picotron version

local Palette = require("palette")

local SpeedLines = {}
SpeedLines.__index = SpeedLines

-- Configuration (matching Picotron, doubled particle count)
local MAX_SPEED_LINES = 80  -- Doubled from 40
local SPEED_LINE_SPAWN_RATE = 0.05
local MIN_SPEED_THRESHOLD = 0.02
local SPAWN_RADIUS = 4  -- Sphere radius around ship
local LINE_LIFETIME = 1.0

-- Depth-based colors using Picotron palette indices
-- Far = 5, mid = 4, near = 6
local COLOR_FAR = Palette.getColor(5)    -- 5f574f - brown/tan (farthest)
local COLOR_MID = Palette.getColor(4)    -- ab5236 - mid
local COLOR_NEAR = Palette.getColor(6)   -- c2c3c7 - light gray (closest)

function SpeedLines.new()
    local self = setmetatable({}, SpeedLines)

    self.lines = {}
    self.spawn_timer = 0

    -- Initialize line pool
    for i = 1, MAX_SPEED_LINES do
        table.insert(self.lines, {
            active = false,
            x = 0, y = 0, z = 0,
            dir_x = 0, dir_y = 0, dir_z = 0,
            length = 0,
            life = 0,
            max_life = LINE_LIFETIME
        })
    end

    return self
end

-- Spawn a speed line particle around the ship
function SpeedLines:spawn(ship_x, ship_y, ship_z, ship_vx, ship_vy, ship_vz)
    -- Calculate ship speed
    local speed = math.sqrt(ship_vx * ship_vx + ship_vy * ship_vy + ship_vz * ship_vz)

    -- Don't spawn if moving too slowly
    if speed < MIN_SPEED_THRESHOLD then
        return false
    end

    -- Find inactive line slot
    for _, line in ipairs(self.lines) do
        if not line.active then
            line.active = true
            line.life = 0
            line.max_life = LINE_LIFETIME

            -- Random spherical position around ship
            local theta = math.random() * math.pi * 2
            local phi = math.random() * math.pi
            local radius = math.random() * SPAWN_RADIUS

            local offset_x = radius * math.sin(phi) * math.cos(theta)
            local offset_y = radius * math.sin(phi) * math.sin(theta)
            local offset_z = radius * math.cos(phi)

            line.x = ship_x + offset_x
            line.y = ship_y + offset_y
            line.z = ship_z + offset_z

            -- Direction from ship velocity (normalized)
            line.dir_x = ship_vx / speed
            line.dir_y = ship_vy / speed
            line.dir_z = ship_vz / speed

            -- Line length based on velocity magnitude
            line.length = math.max(0.1, speed * 2)

            return true
        end
    end

    return false  -- No available slots
end

-- Update all active speed lines
function SpeedLines:update(dt, ship_x, ship_y, ship_z, ship_vx, ship_vy, ship_vz)
    -- Update spawn timer
    self.spawn_timer = self.spawn_timer + dt

    -- Spawn new lines at spawn rate
    while self.spawn_timer >= SPEED_LINE_SPAWN_RATE do
        self.spawn_timer = self.spawn_timer - SPEED_LINE_SPAWN_RATE
        self:spawn(ship_x, ship_y, ship_z, ship_vx, ship_vy, ship_vz)
    end

    -- Update existing lines
    for _, line in ipairs(self.lines) do
        if line.active then
            line.life = line.life + dt

            -- Deactivate when expired
            if line.life >= line.max_life then
                line.active = false
            end
        end
    end
end

-- Draw all active speed lines
function SpeedLines:draw(renderer, camera)
    for _, line in ipairs(self.lines) do
        if line.active then
            local life_progress = line.life / line.max_life

            -- Fade out over lifetime (opacity 1.0 -> 0.0)
            local opacity = 1.0 - life_progress

            -- Skip if too faded (matching Picotron's alpha > 0.3 threshold)
            -- Don't fade colors - just skip drawing when too transparent
            if opacity <= 0.3 then
                goto continue
            end

            -- Calculate line endpoints
            local x1 = line.x
            local y1 = line.y
            local z1 = line.z

            -- End point is in direction of travel, length based on speed
            local x2 = line.x + line.dir_x * line.length
            local y2 = line.y + line.dir_y * line.length
            local z2 = line.z + line.dir_z * line.length

            -- Calculate depth (distance from camera) for color selection
            -- Picotron uses camera-space Z with +5 offset, thresholds at 8 and 15
            local depth = 0
            if camera then
                local dx = line.x - camera.pos.x
                local dy = line.y - camera.pos.y
                local dz = line.z - camera.pos.z
                depth = math.sqrt(dx*dx + dy*dy + dz*dz)
            end

            -- Select color based on depth (matching Picotron thresholds)
            -- Picotron: <8 = near (6), 8-15 = mid (22), >15 = far (5)
            local r, g, b
            if depth > 15 then
                -- Far - darkest
                r, g, b = COLOR_FAR[1], COLOR_FAR[2], COLOR_FAR[3]
            elseif depth > 8 then
                -- Mid
                r, g, b = COLOR_MID[1], COLOR_MID[2], COLOR_MID[3]
            else
                -- Near - lightest
                r, g, b = COLOR_NEAR[1], COLOR_NEAR[2], COLOR_NEAR[3]
            end

            -- Draw 3D line with depth testing (no color fading - matches Picotron)
            renderer.drawLine3D({x1, y1, z1}, {x2, y2, z2}, r, g, b)

            ::continue::
        end
    end
end

-- Get count of active speed lines
function SpeedLines:get_active_count()
    local count = 0
    for _, line in ipairs(self.lines) do
        if line.active then
            count = count + 1
        end
    end
    return count
end

-- Clear all speed lines
function SpeedLines:clear()
    for _, line in ipairs(self.lines) do
        line.active = false
    end
end

return SpeedLines
