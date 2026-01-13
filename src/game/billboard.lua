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
function Billboard.spawn(x, y, z, size, lifetime, sprite_id)
    if #billboards >= max_billboards then
        -- Remove oldest billboard
        table.remove(billboards, 1)
    end

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
        scale_growth = 0.5,  -- Grow over lifetime
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
        local fade = life_ratio  -- Fade out as it dies

        -- Scale grows over lifetime
        local scale = b.size * (1.0 + (1.0 - life_ratio) * b.scale_growth)
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
