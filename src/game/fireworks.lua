-- Fireworks Module
-- Creates celebratory firework effects for race completions

local Fireworks = {}

-- Firework state
local rockets = {}      -- Rockets launching upward
local sparks = {}       -- Explosion sparks
local max_sparks = 500  -- Maximum sparks allowed

-- Color palettes for fireworks
local COLORS = {
    {255, 100, 100},   -- Red
    {100, 255, 100},   -- Green
    {100, 100, 255},   -- Blue
    {255, 255, 100},   -- Yellow
    {255, 100, 255},   -- Magenta
    {100, 255, 255},   -- Cyan
    {255, 200, 100},   -- Orange
    {255, 255, 255},   -- White
}

-- Initialize/reset fireworks
function Fireworks.reset()
    rockets = {}
    sparks = {}
end

-- Launch a single firework rocket
function Fireworks.launch(x, y, z, power)
    power = power or 1.0

    local rocket = {
        x = x,
        y = y,
        z = z,
        vx = (math.random() - 0.5) * 2 * power,
        vy = 15 + math.random() * 10 * power,  -- Strong upward velocity
        vz = (math.random() - 0.5) * 2 * power,
        life = 0,
        max_life = 0.8 + math.random() * 0.4,  -- Time before explosion
        color = COLORS[math.random(#COLORS)],
        trail = {},  -- Trail positions
        power = power,
    }

    table.insert(rockets, rocket)
end

-- Launch multiple fireworks in a burst pattern
function Fireworks.burst(x, y, z, count, power)
    count = count or 5
    power = power or 1.0

    for i = 1, count do
        local angle = (i / count) * math.pi * 2
        local offset_x = math.sin(angle) * 3
        local offset_z = math.cos(angle) * 3
        Fireworks.launch(x + offset_x, y, z + offset_z, power)
    end
end

-- Launch a big celebration (for race complete)
function Fireworks.celebrate(x, y, z)
    -- Launch many fireworks in waves
    for i = 1, 8 do
        local angle = (i / 8) * math.pi * 2
        local dist = 10 + math.random() * 5
        local fx = x + math.sin(angle) * dist
        local fz = z + math.cos(angle) * dist
        Fireworks.launch(fx, y, fz, 1.5)
    end
end

-- Create explosion sparks when rocket detonates
local function explode(rocket)
    local spark_count = math.floor(30 * rocket.power)
    local color = rocket.color

    for i = 1, spark_count do
        if #sparks < max_sparks then
            -- Random direction on a sphere
            local theta = math.random() * math.pi * 2
            local phi = math.acos(2 * math.random() - 1)
            local speed = 3 + math.random() * 5

            local spark = {
                x = rocket.x,
                y = rocket.y,
                z = rocket.z,
                vx = math.sin(phi) * math.cos(theta) * speed,
                vy = math.sin(phi) * math.sin(theta) * speed,
                vz = math.cos(phi) * speed,
                life = 0,
                max_life = 1.0 + math.random() * 0.5,
                color = {color[1], color[2], color[3]},
                prev_x = rocket.x,
                prev_y = rocket.y,
                prev_z = rocket.z,
            }

            table.insert(sparks, spark)
        end
    end
end

-- Update all fireworks
function Fireworks.update(dt)
    -- Update rockets
    for i = #rockets, 1, -1 do
        local rocket = rockets[i]

        -- Store trail position
        table.insert(rocket.trail, {x = rocket.x, y = rocket.y, z = rocket.z})
        if #rocket.trail > 8 then
            table.remove(rocket.trail, 1)
        end

        -- Update position
        rocket.x = rocket.x + rocket.vx * dt
        rocket.y = rocket.y + rocket.vy * dt
        rocket.z = rocket.z + rocket.vz * dt

        -- Apply gravity (less than normal for dramatic arc)
        rocket.vy = rocket.vy - 15 * dt

        -- Update life
        rocket.life = rocket.life + dt

        -- Explode when reaching peak or max life
        if rocket.life >= rocket.max_life or rocket.vy <= 0 then
            explode(rocket)
            table.remove(rockets, i)
        end
    end

    -- Update sparks
    for i = #sparks, 1, -1 do
        local spark = sparks[i]

        -- Store previous position for trail
        spark.prev_x = spark.x
        spark.prev_y = spark.y
        spark.prev_z = spark.z

        -- Update position
        spark.x = spark.x + spark.vx * dt
        spark.y = spark.y + spark.vy * dt
        spark.z = spark.z + spark.vz * dt

        -- Apply gravity
        spark.vy = spark.vy - 20 * dt

        -- Apply drag
        spark.vx = spark.vx * 0.98
        spark.vy = spark.vy * 0.99
        spark.vz = spark.vz * 0.98

        -- Update life
        spark.life = spark.life + dt

        -- Remove dead sparks
        if spark.life >= spark.max_life then
            table.remove(sparks, i)
        end
    end
end

-- Draw all fireworks
function Fireworks.draw(renderer)
    -- Draw rocket trails
    for _, rocket in ipairs(rockets) do
        local color = rocket.color

        -- Draw trail
        for j = 2, #rocket.trail do
            local alpha = j / #rocket.trail
            local r = math.floor(color[1] * alpha)
            local g = math.floor(color[2] * alpha)
            local b = math.floor(color[3] * alpha)

            renderer.drawLine3D(
                {rocket.trail[j-1].x, rocket.trail[j-1].y, rocket.trail[j-1].z},
                {rocket.trail[j].x, rocket.trail[j].y, rocket.trail[j].z},
                r, g, b, true  -- Skip depth test for visibility
            )
        end

        -- Draw rocket head
        if #rocket.trail > 0 then
            local last = rocket.trail[#rocket.trail]
            renderer.drawLine3D(
                {last.x, last.y, last.z},
                {rocket.x, rocket.y, rocket.z},
                color[1], color[2], color[3], true
            )
        end
    end

    -- Draw sparks as short lines (trails)
    for _, spark in ipairs(sparks) do
        local life_ratio = 1 - (spark.life / spark.max_life)
        local alpha = life_ratio * life_ratio  -- Fade out quadratically

        local r = math.floor(spark.color[1] * alpha)
        local g = math.floor(spark.color[2] * alpha)
        local b = math.floor(spark.color[3] * alpha)

        -- Draw spark as a short trail line
        renderer.drawLine3D(
            {spark.prev_x, spark.prev_y, spark.prev_z},
            {spark.x, spark.y, spark.z},
            r, g, b, true  -- Skip depth test for visibility
        )
    end
end

-- Check if any fireworks are active
function Fireworks.is_active()
    return #rockets > 0 or #sparks > 0
end

-- Get count of active elements (for debugging)
function Fireworks.get_counts()
    return #rockets, #sparks
end

return Fireworks
