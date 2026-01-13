-- Billboard Module
-- Creates camera-facing quads for smoke and particle effects
-- Reference: http://www.opengl-tutorial.org/intermediate-tutorials/billboards-particles/billboards/

local Constants = require("constants")

local Billboard = {}

-- Active billboards list
local billboards = {}
local max_billboards = 100

-- Initialize/reset billboards
function Billboard.reset()
    billboards = {}
end

-- Spawn a new billboard at position
-- Optional params table can include:
--   scale_phase1: scale multiplier at end of phase 1 (default 1.5)
--   scale_phase2: scale multiplier at end of phase 2/death (default 2.0)
--   phase1_ratio: portion of lifetime for phase 1 (default 0.4)
--   fade_in_end: when fade-in completes (0-1, default 0.1 = fade in during first 10%)
--   fade_out_start: when to start fading out (0-1, default 0.6 = start fading at 60% through)
function Billboard.spawn(x, y, z, size, lifetime, sprite_id, params)
    if #billboards >= max_billboards then
        -- Remove oldest billboard
        table.remove(billboards, 1)
    end

    params = params or {}

    local billboard = {
        x = x,
        y = y,
        z = z,
        size = size or 1.0,
        lifetime = lifetime or 2.0,
        max_lifetime = lifetime or 2.0,
        sprite_id = sprite_id or Constants.SPRITE_SMOKE,
        vx = 0,
        vy = 0.5,  -- Slow upward drift
        vz = 0,
        -- Two-phase animation params
        scale_phase1 = params.scale_phase1 or 1.5,   -- Scale at end of phase 1
        scale_phase2 = params.scale_phase2 or 2.0,   -- Scale at death
        phase1_ratio = params.phase1_ratio or 0.4,   -- 40% of life is phase 1
        fade_in_end = params.fade_in_end or 0.15,    -- Fade in during first 15%
        fade_out_start = params.fade_out_start or params.fade_start or 0.6,  -- Start fading out at 60%
        -- Legacy support
        scale_growth = params.scale_growth,          -- If set, use old linear scaling
    }

    table.insert(billboards, billboard)
    return billboard
end

-- Update all billboards
function Billboard.update(dt)
    for i = #billboards, 1, -1 do
        local b = billboards[i]

        -- Update position
        b.x = b.x + b.vx * dt
        b.y = b.y + b.vy * dt
        b.z = b.z + b.vz * dt

        -- Apply some drag
        b.vx = b.vx * 0.98
        b.vy = b.vy * 0.98
        b.vz = b.vz * 0.98

        -- Update lifetime
        b.lifetime = b.lifetime - dt

        -- Remove dead billboards
        if b.lifetime <= 0 then
            table.remove(billboards, i)
        end
    end
end

-- Draw all billboards using proper view matrix extraction
-- For a row-major view matrix, the rows represent camera axes in world space:
-- Row 0: Camera RIGHT vector
-- Row 1: Camera UP vector
-- Row 2: Camera FORWARD vector
function Billboard.draw(renderer, viewMatrix, cam)
    if #billboards == 0 then return end

    -- Extract camera right and up vectors from view matrix
    -- View matrix is row-major in our engine: [row0], [row1], [row2], [row3]
    -- Row 0 (indices 1, 2, 3): camera right in world space
    -- Row 1 (indices 5, 6, 7): camera up in world space
    local right_x, right_y, right_z
    local up_x, up_y, up_z

    if viewMatrix then
        -- Extract from view matrix (row-major, 1-indexed)
        -- Row 0: elements at [1], [2], [3] = camera right
        -- Row 1: elements at [5], [6], [7] = camera up
        right_x = viewMatrix[1]
        right_y = viewMatrix[2]
        right_z = viewMatrix[3]

        up_x = viewMatrix[5]
        up_y = viewMatrix[6]
        up_z = viewMatrix[7]
    elseif cam then
        -- Fallback: use camera vectors directly from cam object
        right_x = cam.right.x
        right_y = cam.right.y
        right_z = cam.right.z

        up_x = cam.up.x
        up_y = cam.up.y
        up_z = cam.up.z
    else
        -- Default fallback
        right_x, right_y, right_z = 1, 0, 0
        up_x, up_y, up_z = 0, 1, 0
    end

    -- Draw each billboard
    for _, b in ipairs(billboards) do
        local life_ratio = b.lifetime / b.max_lifetime
        local progress = 1.0 - life_ratio  -- 0 at birth, 1 at death

        -- Calculate scale using two-phase animation
        local scale
        if b.scale_growth then
            -- Legacy mode: linear scale growth
            scale = b.size * (1.0 + progress * b.scale_growth)
        else
            -- Two-phase animation
            local phase1_end = b.phase1_ratio
            if progress < phase1_end then
                -- Phase 1: rapid scale up from 1.0 to scale_phase1
                local t = progress / phase1_end
                scale = b.size * (1.0 + t * (b.scale_phase1 - 1.0))
            else
                -- Phase 2: slower scale from scale_phase1 to scale_phase2
                local t = (progress - phase1_end) / (1.0 - phase1_end)
                scale = b.size * (b.scale_phase1 + t * (b.scale_phase2 - b.scale_phase1))
            end
        end

        -- Calculate fade (alpha) with fade-in and fade-out
        local fade
        if progress < b.fade_in_end then
            -- Fade in: 0 -> 1 during fade_in period
            fade = progress / b.fade_in_end
        elseif progress < b.fade_out_start then
            -- Full opacity between fade-in and fade-out
            fade = 1.0
        else
            -- Fade out: 1 -> 0 during fade_out period
            fade = 1.0 - (progress - b.fade_out_start) / (1.0 - b.fade_out_start)
        end
        -- Clamp fade to valid range
        fade = math.max(0, math.min(1, fade))

        local half = scale * 0.5

        -- Get texture data
        local texData = Constants.getTextureData(b.sprite_id)
        if texData then
            -- Build quad vertices using camera right and up vectors
            -- Formula: position = center + right * x_offset + up * y_offset
            local v1 = {
                pos = {
                    b.x - right_x * half + up_x * half,
                    b.y - right_y * half + up_y * half,
                    b.z - right_z * half + up_z * half
                },
                uv = {0, 0}
            }
            local v2 = {
                pos = {
                    b.x + right_x * half + up_x * half,
                    b.y + right_y * half + up_y * half,
                    b.z + right_z * half + up_z * half
                },
                uv = {1, 0}
            }
            local v3 = {
                pos = {
                    b.x + right_x * half - up_x * half,
                    b.y + right_y * half - up_y * half,
                    b.z + right_z * half - up_z * half
                },
                uv = {1, 1}
            }
            local v4 = {
                pos = {
                    b.x - right_x * half - up_x * half,
                    b.y - right_y * half - up_y * half,
                    b.z - right_z * half - up_z * half
                },
                uv = {0, 1}
            }

            -- Draw as two triangles with dithered transparency (alpha = fade)
            -- brightness = 1.0 (unlit/emissive), alpha = fade for dithered transparency
            renderer.drawTriangle3D(v1, v2, v3, nil, texData, 1.0, fade)
            renderer.drawTriangle3D(v1, v3, v4, nil, texData, 1.0, fade)
        end
    end
end

-- Get count of active billboards
function Billboard.get_count()
    return #billboards
end

return Billboard
