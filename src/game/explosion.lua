-- Explosion Module
-- Handles impact explosions, death explosions, and damage smoke effects

local Constants = require("constants")
local Billboard = require("billboard")

local Explosion = {}

-- Active explosions list
local explosions = {}
local max_explosions = 50

-- Smoke emitters for damaged ships
local smoke_emitters = {}

-- Initialize/reset explosions
function Explosion.reset()
    explosions = {}
    smoke_emitters = {}
end

-- Spawn a small impact explosion (collision hit)
function Explosion.spawn_impact(x, y, z, scale)
    scale = scale or 1.0

    -- Main explosion billboard with two-phase animation
    -- Phase 1: rapid scale up, Phase 2: slower scale + fade out
    local explosion = Billboard.spawn(x, y, z, scale, 0.8, Constants.SPRITE_EXPLOSION, {
        scale_phase1 = 2.0,       -- Scale up to 2x in phase 1
        scale_phase2 = 2.5,       -- Scale to 2.5x by end
        phase1_ratio = 0.3,       -- 30% of life is rapid expansion
        fade_in_end = 0.1,        -- Quick fade in
        fade_out_start = 0.4,     -- Start fading at 40% through
    })
    if explosion then
        explosion.vy = 0.2  -- Slight upward drift
    end

    -- Add a few small smoke puffs with longer lifetime
    for i = 1, 3 do
        local offset_x = (math.random() - 0.5) * scale
        local offset_y = (math.random() - 0.5) * scale
        local offset_z = (math.random() - 0.5) * scale
        local smoke = Billboard.spawn(
            x + offset_x,
            y + offset_y,
            z + offset_z,
            scale * 0.5,
            1.2,  -- Longer lifetime
            Constants.SPRITE_SMOKE,
            {
                scale_phase1 = 1.8,
                scale_phase2 = 2.5,
                phase1_ratio = 0.4,
                fade_in_end = 0.1,
                fade_out_start = 0.5,
            }
        )
        if smoke then
            smoke.vy = 0.5 + math.random() * 0.3
        end
    end
end

-- Spawn a big death explosion (ship destroyed)
function Explosion.spawn_death(x, y, z, scale)
    scale = scale or 2.0

    -- Central large explosion - BIG and dramatic
    local central = Billboard.spawn(x, y, z, scale * 3.0, 1.5, Constants.SPRITE_EXPLOSION, {
        scale_phase1 = 3.0,       -- Triple size in phase 1
        scale_phase2 = 4.0,       -- Quadruple by end
        phase1_ratio = 0.2,       -- Quick expansion
        fade_in_end = 0.1,        -- Quick fade in
        fade_out_start = 0.3,     -- Start fading early
    })
    if central then
        central.vy = 0.5  -- Slight upward drift
    end

    -- Ring of medium explosions - staggered for dramatic effect
    for i = 1, 10 do
        local angle = (i / 10) * math.pi * 2
        local dist = scale * 1.0
        local delay = i * 0.08  -- Staggered timing

        -- Offset position
        local ex = x + math.sin(angle) * dist
        local ey = y + (math.random() - 0.5) * scale * 0.5
        local ez = z + math.cos(angle) * dist

        -- Medium explosion with animation
        local billboard = Billboard.spawn(ex, ey, ez, scale * 1.5, 1.2 + delay, Constants.SPRITE_EXPLOSION, {
            scale_phase1 = 2.5,
            scale_phase2 = 3.5,
            phase1_ratio = 0.25,
            fade_in_end = 0.1,
            fade_out_start = 0.4,
        })
        if billboard then
            billboard.vx = math.sin(angle) * 3
            billboard.vy = 0.5 + math.random() * 2
            billboard.vz = math.cos(angle) * 3
        end
    end

    -- Secondary wave of smaller explosions
    for i = 1, 6 do
        local angle = math.random() * math.pi * 2
        local dist = scale * 0.5
        local delay = 0.3 + math.random() * 0.4

        local ex = x + math.sin(angle) * dist
        local ey = y + math.random() * scale * 0.3
        local ez = z + math.cos(angle) * dist

        local secondary = Billboard.spawn(ex, ey, ez, scale * 1.0, 0.8 + delay, Constants.SPRITE_EXPLOSION, {
            scale_phase1 = 2.0,
            scale_phase2 = 3.0,
            phase1_ratio = 0.3,
            fade_in_end = 0.1,
            fade_out_start = 0.4,
        })
        if secondary then
            secondary.vy = 1 + math.random()
        end
    end

    -- Lots of smoke puffs - bigger and longer lasting
    for i = 1, 20 do
        local angle = math.random() * math.pi * 2
        local dist = math.random() * scale * 0.8
        local sx = x + math.sin(angle) * dist
        local sy = y + (math.random() - 0.5) * scale * 0.5
        local sz = z + math.cos(angle) * dist

        local smoke = Billboard.spawn(sx, sy, sz, scale * 0.8, 4.0 + math.random() * 2.0, Constants.SPRITE_SMOKE, {
            scale_phase1 = 2.0,
            scale_phase2 = 4.0,
            phase1_ratio = 0.2,
            fade_in_end = 0.1,
            fade_out_start = 0.3,
        })
        if smoke then
            smoke.vx = (math.random() - 0.5) * 4
            smoke.vy = 1.5 + math.random() * 3
            smoke.vz = (math.random() - 0.5) * 4
        end
    end

    -- Small debris particles - faster and more varied
    for i = 1, 25 do
        local angle = math.random() * math.pi * 2
        local pitch = (math.random() - 0.5) * math.pi
        local speed = 4 + math.random() * 8

        local debris = Billboard.spawn(x, y, z, 0.3 + math.random() * 0.2, 1.5 + math.random() * 1.0, Constants.SPRITE_SMOKE, {
            scale_phase1 = 1.2,
            scale_phase2 = 1.8,
            phase1_ratio = 0.4,
            fade_in_end = 0.05,
            fade_out_start = 0.5,
        })
        if debris then
            debris.vx = math.sin(angle) * math.cos(pitch) * speed
            debris.vy = math.sin(pitch) * speed + 3
            debris.vz = math.cos(angle) * math.cos(pitch) * speed
        end
    end
end

-- Spawn enemy explosion (similar to death but can be customized)
function Explosion.spawn_enemy(x, y, z, scale)
    scale = scale or 1.5

    -- Central explosion with two-phase animation
    Billboard.spawn(x, y, z, scale * 1.5, 1.0, Constants.SPRITE_EXPLOSION, {
        scale_phase1 = 2.2,
        scale_phase2 = 2.8,
        phase1_ratio = 0.3,
        fade_in_end = 0.1,
        fade_out_start = 0.45,
    })

    -- Smaller surrounding explosions
    for i = 1, 4 do
        local angle = (i / 4) * math.pi * 2 + math.random() * 0.5
        local dist = scale * 0.5
        local ex = x + math.sin(angle) * dist
        local ey = y + (math.random() - 0.5) * scale * 0.5
        local ez = z + math.cos(angle) * dist

        Billboard.spawn(ex, ey, ez, scale * 0.8, 0.7, Constants.SPRITE_EXPLOSION, {
            scale_phase1 = 1.8,
            scale_phase2 = 2.2,
            phase1_ratio = 0.35,
            fade_in_end = 0.1,
            fade_out_start = 0.5,
        })
    end

    -- Smoke trail with longer lifetime
    for i = 1, 6 do
        local smoke = Billboard.spawn(
            x + (math.random() - 0.5) * scale,
            y + (math.random() - 0.5) * scale,
            z + (math.random() - 0.5) * scale,
            scale * 0.4,
            2.0 + math.random() * 1.0,
            Constants.SPRITE_SMOKE,
            {
                scale_phase1 = 1.5,
                scale_phase2 = 2.5,
                phase1_ratio = 0.4,
                fade_in_end = 0.1,
                fade_out_start = 0.5,
            }
        )
        if smoke then
            smoke.vy = 1 + math.random()
        end
    end
end

-- Register a smoke emitter for a damaged ship
function Explosion.register_damage_smoke(id, get_position_func)
    smoke_emitters[id] = {
        get_position = get_position_func,
        emit_timer = 0,
        emit_rate = 0.1,  -- Seconds between smoke puffs
    }
end

-- Unregister a smoke emitter
function Explosion.unregister_damage_smoke(id)
    smoke_emitters[id] = nil
end

-- Update damage smoke based on hull percentage
function Explosion.update_damage_smoke(id, hull_percent, dt)
    local emitter = smoke_emitters[id]
    if not emitter then return end

    -- No smoke above 50% hull
    if hull_percent > 50 then
        return
    end

    -- Update emit timer
    emitter.emit_timer = emitter.emit_timer + dt

    -- Calculate emit rate based on damage
    -- 50% hull = slow smoke, 0% hull = rapid smoke
    local damage_factor = 1 - (hull_percent / 50)  -- 0 at 50%, 1 at 0%
    local base_rate = 0.3  -- Seconds at 50% damage
    local fast_rate = 0.05  -- Seconds at 0% damage
    local current_rate = base_rate - (base_rate - fast_rate) * damage_factor

    -- Below 25% = more intense smoke
    if hull_percent < 25 then
        current_rate = current_rate * 0.5  -- Double the rate
    end

    -- Emit smoke
    if emitter.emit_timer >= current_rate then
        emitter.emit_timer = 0

        local x, y, z = emitter.get_position()
        if x then
            -- Smoke size based on damage
            local size = 0.3 + damage_factor * 0.4

            -- Random offset from ship center
            local offset_x = (math.random() - 0.5) * 0.5
            local offset_y = (math.random() - 0.5) * 0.3
            local offset_z = (math.random() - 0.5) * 0.5

            -- Double lifetime for damage smoke (3-4 seconds)
            local smoke = Billboard.spawn(
                x + offset_x,
                y + offset_y,
                z + offset_z,
                size,
                3.0 + math.random() * 1.0,
                Constants.SPRITE_SMOKE,
                {
                    scale_phase1 = 1.5,
                    scale_phase2 = 2.5,
                    phase1_ratio = 0.3,
                    fade_in_end = 0.1,
                    fade_out_start = 0.4,
                }
            )

            if smoke then
                smoke.vy = 0.3 + math.random() * 0.3  -- Slow rise
                smoke.vx = (math.random() - 0.5) * 0.2
                smoke.vz = (math.random() - 0.5) * 0.2
            end

            -- Below 25% = occasional small explosion sparks with animation
            if hull_percent < 25 and math.random() < 0.15 then
                Billboard.spawn(
                    x + offset_x,
                    y + offset_y,
                    z + offset_z,
                    0.3,
                    0.5,
                    Constants.SPRITE_EXPLOSION,
                    {
                        scale_phase1 = 1.8,
                        scale_phase2 = 2.2,
                        phase1_ratio = 0.3,
                        fade_in_end = 0.08,
                        fade_out_start = 0.4,
                    }
                )
            end
        end
    end
end

-- Get count of active explosions (for debugging)
function Explosion.get_count()
    return #explosions
end

return Explosion
