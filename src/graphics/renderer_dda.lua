-- DDA Scanline Software Renderer with LuaJIT FFI optimization
-- Based on reference-lib/Concepts/TwoTriangles.bas

local config = require("config")
local ffi = require("ffi")
local bit = require("bit")
local mat4 = require("mat4")
local renderer_dda = {}

-- Localize frequently used functions for LuaJIT optimization
local band = bit.band
local bor = bit.bor
local floor = math.floor

-- Performance counters
local stats = {
    trianglesDrawn = 0,
    pixelsDrawn = 0,
    trianglesCulled = 0,
    trianglesClipped = 0,
    -- Timing breakdown (in ms, accumulated per frame)
    timeTransform = 0,
    timeRasterize = 0
}

-- High-resolution timer
local getTime = love.timer.getTime

local RENDER_WIDTH = config.RENDER_WIDTH
local RENDER_HEIGHT = config.RENDER_HEIGHT

-- Buffers
local softwareImageData
local softwareZBuffer
local textureData

-- FFI pointers for direct memory access
local framebufferPtr = nil
local zbufferPtr = nil
local texturePtr = nil
local texWidth = 0
local texHeight = 0

-- Texture pointer cache to avoid repeated ffi.cast calls (JIT killer)
local texturePtrCache = setmetatable({}, {__mode = "k"})  -- Weak keys for GC

-- Cached matrices for drawTriangle3D
local currentMVP = nil
local currentCamera = nil

-- Fog settings
local fogEnabled = false
local fogNear = 10.0
local fogFar = 100.0
local fogColor = {0, 0, 0}  -- RGB 0-255 (unused, kept for compatibility)

-- Clear/background color - fog dithers to this color
local clearColor = {162, 136, 121}  -- #a28879 - matches framebuffer clear

-- Dithering toggle (for testing performance impact)
local ditherEnabled = true

-- Bayer 4x4 dithering matrix for fog transitions
local bayerMatrix = {
    { 0,  8,  2, 10},
    {12,  4, 14,  6},
    { 3, 11,  1,  9},
    {15,  7, 13,  5}
}

-- Track if renderer has been initialized
local isInitialized = false

function renderer_dda.init(width, height)
    -- Prevent double initialization (causes JIT issues)
    if isInitialized then
        print("DDA Renderer already initialized, skipping")
        return
    end

    RENDER_WIDTH = width
    RENDER_HEIGHT = height

    -- Initialize software rendering resources
    softwareImageData = love.image.newImageData(RENDER_WIDTH, RENDER_HEIGHT)

    -- Get FFI pointer to framebuffer (RGBA8 format, 4 bytes per pixel)
    framebufferPtr = ffi.cast("uint8_t*", softwareImageData:getFFIPointer())

    -- Allocate z-buffer using FFI for faster access
    zbufferPtr = ffi.new("float[?]", RENDER_WIDTH * RENDER_HEIGHT)
    for i = 0, RENDER_WIDTH * RENDER_HEIGHT - 1 do
        zbufferPtr[i] = math.huge
    end

    isInitialized = true
    print("DDA Renderer initialized (FFI): " .. RENDER_WIDTH .. "x" .. RENDER_HEIGHT)
end

function renderer_dda.clearBuffers()
    -- Auto-initialize if not initialized
    if not zbufferPtr then
        renderer_dda.init(RENDER_WIDTH, RENDER_HEIGHT)
    end

    -- Reset stats
    stats.trianglesDrawn = 0
    stats.pixelsDrawn = 0
    stats.trianglesCulled = 0
    stats.trianglesClipped = 0
    stats.timeTransform = 0
    stats.timeRasterize = 0

    -- Clear z-buffer using FFI (optimized with ffi.fill)
    ffi.fill(zbufferPtr, RENDER_WIDTH * RENDER_HEIGHT * ffi.sizeof("float"), 0x7F)  -- Max float pattern

    -- Clear framebuffer to background/clear color (RGBA format)
    for i = 0, RENDER_WIDTH * RENDER_HEIGHT - 1 do
        local idx = i * 4
        framebufferPtr[idx] = clearColor[1]      -- R
        framebufferPtr[idx + 1] = clearColor[2]  -- G
        framebufferPtr[idx + 2] = clearColor[3]  -- B
        framebufferPtr[idx + 3] = 255            -- A
    end
end

function renderer_dda.getStats()
    return stats
end

-- Fog control functions
function renderer_dda.setFog(enabled, near, far, r, g, b)
    fogEnabled = enabled
    if near then fogNear = near end
    if far then fogFar = far end
    if r then fogColor[1] = r end
    if g then fogColor[2] = g end
    if b then fogColor[3] = b end
end

function renderer_dda.getFogEnabled()
    return fogEnabled
end

-- Set the clear/background color (fog dithers to this color)
function renderer_dda.setClearColor(r, g, b)
    clearColor[1] = r or 162
    clearColor[2] = g or 136
    clearColor[3] = b or 121
end

-- Calculate fog factor from distance (for per-triangle fog)
-- Returns 0-1 value (0 = no fog, 1 = full fog)
function renderer_dda.calcFogFactor(distance)
    if not fogEnabled or distance <= fogNear then
        return 0
    end
    local factor = (distance - fogNear) / (fogFar - fogNear)
    return math.max(0, math.min(1, factor))
end

-- Get fog settings for external distance calculations
function renderer_dda.getFogSettings()
    return fogNear, fogFar
end

-- Toggle dithering on/off (for testing performance impact)
function renderer_dda.toggleDither()
    ditherEnabled = not ditherEnabled
    return ditherEnabled
end

-- Check if dithering is enabled
function renderer_dda.isDitherEnabled()
    return ditherEnabled
end

-- Set pixel with Z-buffer test (FFI optimized)
local function setPixel(x, y, z, r, g, b)
    if x < 0 or x >= RENDER_WIDTH or y < 0 or y >= RENDER_HEIGHT then
        return
    end

    local xi = math.floor(x)
    local yi = math.floor(y)
    local index = yi * RENDER_WIDTH + xi

    if z < zbufferPtr[index] then
        zbufferPtr[index] = z

        -- Write pixel directly to framebuffer (RGBA8)
        local pixelIndex = index * 4
        framebufferPtr[pixelIndex] = r * 255
        framebufferPtr[pixelIndex + 1] = g * 255
        framebufferPtr[pixelIndex + 2] = b * 255
        framebufferPtr[pixelIndex + 3] = 255
    end
end

-- DDA Triangle Rasterization with perspective-correct texture mapping
-- vertex format: {x, y, w, u, v, z}
-- where w = 1/z, u and v are pre-divided by w
-- fogFactor: 0 = no fog, 1 = full fog (optional, nil = use per-pixel depth fog)
function renderer_dda.drawTriangle(vA, vB, vC, texture, texData, brightness, fogFactor)
    -- print("  [DDA] drawTriangle called")

    -- Backface culling (cull clockwise/back-facing triangles)
    local edge1x = vB[1] - vA[1]
    local edge1y = vB[2] - vA[2]
    local edge2x = vC[1] - vA[1]
    local edge2y = vC[2] - vA[2]
    local cross = edge1x * edge2y - edge1y * edge2x

    if cross <= 0 then
        stats.trianglesCulled = stats.trianglesCulled + 1
        return  -- Back-facing, skip rendering
    end

    stats.trianglesDrawn = stats.trianglesDrawn + 1

    -- Get texture dimensions and FFI pointer
    local texWidth, texHeight

    -- Handle both Image and ImageData
    if texData then
        -- ImageData was provided
        texWidth = texData:getWidth()
        texHeight = texData:getHeight()

        -- Get FFI pointer from cache or create new one (avoid repeated ffi.cast - JIT killer)
        texturePtr = texturePtrCache[texData]
        if not texturePtr then
            texturePtr = ffi.cast("uint8_t*", texData:getFFIPointer())
            texturePtrCache[texData] = texturePtr
        end
    elseif texture then
        -- Only Image provided, try to get its data
        texWidth = texture:getWidth()
        texHeight = texture:getHeight()
        -- Cache: use the global textureData if available
        texData = textureData
        if not texData then
            error("renderer_dda.drawTriangle requires ImageData - pass it as 4th parameter")
        end
        -- Get FFI pointer from cache or create new one
        texturePtr = texturePtrCache[texData]
        if not texturePtr then
            texturePtr = ffi.cast("uint8_t*", texData:getFFIPointer())
            texturePtrCache[texData] = texturePtr
        end
    else
        error("No texture provided to drawTriangle")
    end

    -- Sort vertices by Y (A=top, B=middle, C=bottom)
    if vB[2] < vA[2] then vA, vB = vB, vA end
    if vC[2] < vA[2] then vA, vC = vC, vA end
    if vC[2] < vB[2] then vB, vC = vC, vB end

    -- Clipping bounds
    local clip_min_y = 0
    local clip_max_y = RENDER_HEIGHT - 1
    local clip_min_x = 0
    local clip_max_x = RENDER_WIDTH

    -- Integer window clipping
    local draw_min_y = math.ceil(vA[2])
    if draw_min_y < clip_min_y then draw_min_y = clip_min_y end

    local draw_max_y = math.ceil(vC[2]) - 1
    if draw_max_y > clip_max_y then draw_max_y = clip_max_y end

    if draw_max_y - draw_min_y < 0 then return end

    -- Calculate deltas for major edge (A to C)
    local delta2_x = vC[1] - vA[1]
    local delta2_y = vC[2] - vA[2]
    local delta2_w = vC[3] - vA[3]
    local delta2_u = vC[4] - vA[4]
    local delta2_v = vC[5] - vA[5]
    local delta2_z = vC[6] - vA[6]

    -- Avoid divide by zero
    if delta2_y < (1 / 256) then return end

    -- Calculate steps for major edge (A to C)
    local legx2_step = delta2_x / delta2_y
    local legw2_step = delta2_w / delta2_y
    local legu2_step = delta2_u / delta2_y
    local legv2_step = delta2_v / delta2_y
    local legz2_step = delta2_z / delta2_y

    -- Calculate deltas for minor edge (A to B initially)
    local delta1_x = vB[1] - vA[1]
    local delta1_y = vB[2] - vA[2]
    local delta1_w = vB[3] - vA[3]
    local delta1_u = vB[4] - vA[4]
    local delta1_v = vB[5] - vA[5]
    local delta1_z = vB[6] - vA[6]

    -- Calculate middle Y where we switch from A-B to B-C
    local draw_middle_y = math.ceil(vB[2])
    if draw_middle_y < clip_min_y then draw_middle_y = clip_min_y end

    -- Calculate steps for minor edge (A to B)
    local legx1_step = 0
    local legw1_step = 0
    local legu1_step = 0
    local legv1_step = 0
    local legz1_step = 0

    if delta1_y > (1 / 256) then
        legx1_step = delta1_x / delta1_y
        legw1_step = delta1_w / delta1_y
        legu1_step = delta1_u / delta1_y
        legv1_step = delta1_v / delta1_y
        legz1_step = delta1_z / delta1_y
    end

    -- Pre-step Y to integer pixel boundary
    local prestep_y1 = draw_min_y - vA[2]

    -- Initialize edge accumulators with pre-stepping
    local leg_x1 = vA[1] + prestep_y1 * legx1_step
    local leg_w1 = vA[3] + prestep_y1 * legw1_step
    local leg_u1 = vA[4] + prestep_y1 * legu1_step
    local leg_v1 = vA[5] + prestep_y1 * legv1_step
    local leg_z1 = vA[6] + prestep_y1 * legz1_step

    local leg_x2 = vA[1] + prestep_y1 * legx2_step
    local leg_w2 = vA[3] + prestep_y1 * legw2_step
    local leg_u2 = vA[4] + prestep_y1 * legu2_step
    local leg_v2 = vA[5] + prestep_y1 * legv2_step
    local leg_z2 = vA[6] + prestep_y1 * legz2_step

    -- Row loop from top to bottom
    local row = draw_min_y
    while row <= draw_max_y do
        -- Declare locals at top of loop to avoid goto scope issues
        local delta_x

        -- Check if we've reached the knee (B vertex)
        if row == draw_middle_y then
            -- Recalculate minor edge from B to C
            delta1_x = vC[1] - vB[1]
            delta1_y = vC[2] - vB[2]
            delta1_w = vC[3] - vB[3]
            delta1_u = vC[4] - vB[4]
            delta1_v = vC[5] - vB[5]
            delta1_z = vC[6] - vB[6]

            if math.abs(delta1_y) < 0.001 then
                goto continue_row
            end

            legx1_step = delta1_x / delta1_y
            legw1_step = delta1_w / delta1_y
            legu1_step = delta1_u / delta1_y
            legv1_step = delta1_v / delta1_y
            legz1_step = delta1_z / delta1_y

            -- Pre-step from B
            local prestep_y2 = draw_middle_y - vB[2]
            leg_x1 = vB[1] + prestep_y2 * legx1_step
            leg_w1 = vB[3] + prestep_y2 * legw1_step
            leg_u1 = vB[4] + prestep_y2 * legu1_step
            leg_v1 = vB[5] + prestep_y2 * legv1_step
            leg_z1 = vB[6] + prestep_y2 * legz1_step
        end

        -- Horizontal scanline
        delta_x = math.abs(leg_x2 - leg_x1)

        if delta_x >= (1 / 2048) then
            local tex_w_step, tex_u_step, tex_v_step, tex_z_step
            local tex_w, tex_u, tex_v, tex_z
            local col, draw_max_x

            -- Determine which edge is left and which is right
            if leg_x1 < leg_x2 then
                -- leg 1 is on the left
                tex_w_step = (leg_w2 - leg_w1) / delta_x
                tex_u_step = (leg_u2 - leg_u1) / delta_x
                tex_v_step = (leg_v2 - leg_v1) / delta_x
                tex_z_step = (leg_z2 - leg_z1) / delta_x

                col = math.ceil(leg_x1)
                if col < clip_min_x then col = clip_min_x end

                -- Pre-step X
                local prestep_x = col - leg_x1
                tex_w = leg_w1 + prestep_x * tex_w_step
                tex_u = leg_u1 + prestep_x * tex_u_step
                tex_v = leg_v1 + prestep_x * tex_v_step
                tex_z = leg_z1 + prestep_x * tex_z_step

                draw_max_x = math.ceil(leg_x2)
                if draw_max_x > clip_max_x then draw_max_x = clip_max_x end
            else
                -- leg 2 is on the left
                tex_w_step = (leg_w1 - leg_w2) / delta_x
                tex_u_step = (leg_u1 - leg_u2) / delta_x
                tex_v_step = (leg_v1 - leg_v2) / delta_x
                tex_z_step = (leg_z1 - leg_z2) / delta_x

                col = math.ceil(leg_x2)
                if col < clip_min_x then col = clip_min_x end

                -- Pre-step X
                local prestep_x = col - leg_x2
                tex_w = leg_w2 + prestep_x * tex_w_step
                tex_u = leg_u2 + prestep_x * tex_u_step
                tex_v = leg_v2 + prestep_x * tex_v_step
                tex_z = leg_z2 + prestep_x * tex_z_step

                draw_max_x = math.ceil(leg_x1)
                if draw_max_x > clip_max_x then draw_max_x = clip_max_x end
            end

            -- Draw horizontal span (FFI optimized)
            -- Pre-calculate constant values outside loop
            local texWidthMask = texWidth - 1
            local texHeightMask = texHeight - 1

            -- Perspective-correct every 8 pixels (balance of quality vs speed)
            local PERSP_STEP = 8
            local pixel_count = 0
            local u_linear, v_linear
            local u_linear_step, v_linear_step
            local next_persp_col = col

            -- Cache fog state for this scanline (avoid per-pixel checks)
            local applyFog = fogEnabled and fogFactor and fogFactor > 0
            local fogR, fogG, fogB = clearColor[1], clearColor[2], clearColor[3]

            -- Pre-calculate row offset for index calculation
            local rowOffset = row * RENDER_WIDTH

            while col < draw_max_x do
                -- Index calculation (bounds already guaranteed by clipping)
                local index = rowOffset + col

                -- Early-Z rejection: test depth before expensive perspective divide
                if tex_z < zbufferPtr[index] then
                    zbufferPtr[index] = tex_z

                    -- Perspective-correct calculation every Nth pixel
                    local u, v
                    if col >= next_persp_col then
                        -- Calculate perspective-correct UV at this anchor point
                        local z_recip = 1 / tex_w
                        local u_correct = tex_u * z_recip
                        local v_correct = tex_v * z_recip

                        -- Calculate next anchor point
                        local next_col = col + PERSP_STEP
                        if next_col > draw_max_x then next_col = draw_max_x end
                        local span_len = next_col - col

                        if span_len > 1 then
                            -- Calculate UV at next anchor point
                            local next_tex_w = tex_w + tex_w_step * span_len
                            local next_tex_u = tex_u + tex_u_step * span_len
                            local next_tex_v = tex_v + tex_v_step * span_len
                            local next_z_recip = 1 / next_tex_w
                            local next_u_correct = next_tex_u * next_z_recip
                            local next_v_correct = next_tex_v * next_z_recip

                            -- Linear interpolation step between anchor points
                            u_linear_step = (next_u_correct - u_correct) / span_len
                            v_linear_step = (next_v_correct - v_correct) / span_len
                        else
                            u_linear_step = 0
                            v_linear_step = 0
                        end

                        u_linear = u_correct
                        v_linear = v_correct
                        next_persp_col = next_col
                        pixel_count = 0
                    end

                    -- Use linearly interpolated UV
                    u = u_linear + u_linear_step * pixel_count
                    v = v_linear + v_linear_step * pixel_count
                    pixel_count = pixel_count + 1

                    -- Texture sampling with proper wrapping
                    -- Note: must use floor() not bor() since UV can be negative
                    local texX = band(floor(u), texWidthMask)
                    local texY = band(floor(v), texHeightMask)

                    -- Sample texture using FFI (RGBA format)
                    local texIndex = (texY * texWidth + texX) * 4
                    local r = texturePtr[texIndex]
                    local g = texturePtr[texIndex + 1]
                    local b = texturePtr[texIndex + 2]

                    -- Treat black pixels as transparent (skip rendering)
                    if r == 0 and g == 0 and b == 0 then
                        goto continue_pixel
                    end

                    -- Apply brightness modulation with dithering if provided
                    if brightness then
                        local bayerIdx = band(row, 3) * 4 + band(col, 3) + 1
                        local threshold = bayerMatrix[band(row, 3) + 1][band(col, 3) + 1] * 0.0625

                        if brightness < threshold then
                            goto continue_pixel
                        end
                    end

                    -- Apply fog with dithering (pre-checked at scanline level)
                    if applyFog then
                        local threshold = bayerMatrix[band(row, 3) + 1][band(col, 3) + 1] * 0.0625
                        if fogFactor > threshold then
                            r, g, b = fogR, fogG, fogB
                        end
                    end

                    -- Write to framebuffer
                    local pixelIndex = index * 4
                    framebufferPtr[pixelIndex] = r
                    framebufferPtr[pixelIndex + 1] = g
                    framebufferPtr[pixelIndex + 2] = b
                    framebufferPtr[pixelIndex + 3] = 255
                end

                ::continue_pixel::

                -- Advance accumulators
                tex_w = tex_w + tex_w_step
                tex_u = tex_u + tex_u_step
                tex_v = tex_v + tex_v_step
                tex_z = tex_z + tex_z_step
                col = col + 1
            end
        end

        ::continue_row::

        -- Step to next row
        leg_x1 = leg_x1 + legx1_step
        leg_w1 = leg_w1 + legw1_step
        leg_u1 = leg_u1 + legu1_step
        leg_v1 = leg_v1 + legv1_step
        leg_z1 = leg_z1 + legz1_step

        leg_x2 = leg_x2 + legx2_step
        leg_w2 = leg_w2 + legw2_step
        leg_u2 = leg_u2 + legu2_step
        leg_v2 = leg_v2 + legv2_step
        leg_z2 = leg_z2 + legz2_step

        row = row + 1
    end
end

function renderer_dda.getImageData()
    return softwareImageData
end

-- Clear texture pointer cache (call when switching scenes to avoid stale pointers)
function renderer_dda.clearTextureCache()
    texturePtrCache = setmetatable({}, {__mode = "k"})
end

-- Set matrices for 3D rendering
function renderer_dda.setMatrices(mvpMatrix, cameraPos)
    currentMVP = mvpMatrix
    currentCamera = cameraPos
end

-- Linearly interpolate between two vertices at the near plane
local function lerpVertexAtNearPlane(pIn, pOut, vIn, vOut, nearPlane)
    -- Find t where w = nearPlane: pIn[4] + t * (pOut[4] - pIn[4]) = nearPlane
    local t = (nearPlane - pIn[4]) / (pOut[4] - pIn[4])

    -- Lerp clip space position
    local pClip = {
        pIn[1] + t * (pOut[1] - pIn[1]),
        pIn[2] + t * (pOut[2] - pIn[2]),
        pIn[3] + t * (pOut[3] - pIn[3]),
        nearPlane  -- Exactly on the near plane
    }

    -- Lerp UV coordinates
    local vClip = {
        pos = {
            vIn.pos[1] + t * (vOut.pos[1] - vIn.pos[1]),
            vIn.pos[2] + t * (vOut.pos[2] - vIn.pos[2]),
            vIn.pos[3] + t * (vOut.pos[3] - vIn.pos[3])
        },
        uv = {
            vIn.uv[1] + t * (vOut.uv[1] - vIn.uv[1]),
            vIn.uv[2] + t * (vOut.uv[2] - vIn.uv[2])
        }
    }

    return pClip, vClip
end

-- Clips a triangle against the near plane, generating 1 or 2 new triangles
local function clipTriangleNearPlane(p1, p2, p3, v1, v2, v3, n1, n2, n3, nearPlane)
    local clippedTris = {}

    -- Count vertices behind plane
    local behindCount = (n1 and 1 or 0) + (n2 and 1 or 0) + (n3 and 1 or 0)

    if behindCount == 1 then
        -- One vertex behind - split into 2 triangles
        if n1 then
            -- p1 is behind, p2 and p3 are in front
            local pA, vA = lerpVertexAtNearPlane(p2, p1, v2, v1, nearPlane)
            local pB, vB = lerpVertexAtNearPlane(p3, p1, v3, v1, nearPlane)
            table.insert(clippedTris, {p2, p3, pA, v2, v3, vA})
            table.insert(clippedTris, {p3, pB, pA, v3, vB, vA})
        elseif n2 then
            -- p2 is behind, p1 and p3 are in front
            local pA, vA = lerpVertexAtNearPlane(p1, p2, v1, v2, nearPlane)
            local pB, vB = lerpVertexAtNearPlane(p3, p2, v3, v2, nearPlane)
            table.insert(clippedTris, {p1, pA, p3, v1, vA, v3})
            table.insert(clippedTris, {pA, pB, p3, vA, vB, v3})
        else -- n3
            -- p3 is behind, p1 and p2 are in front
            local pA, vA = lerpVertexAtNearPlane(p1, p3, v1, v3, nearPlane)
            local pB, vB = lerpVertexAtNearPlane(p2, p3, v2, v3, nearPlane)
            table.insert(clippedTris, {p1, p2, pA, v1, v2, vA})
            table.insert(clippedTris, {p2, pB, pA, v2, vB, vA})
        end
    elseif behindCount == 2 then
        -- Two vertices behind - create 1 smaller triangle
        if not n1 then
            -- p1 is in front, p2 and p3 are behind
            local pA, vA = lerpVertexAtNearPlane(p1, p2, v1, v2, nearPlane)
            local pB, vB = lerpVertexAtNearPlane(p1, p3, v1, v3, nearPlane)
            table.insert(clippedTris, {p1, pA, pB, v1, vA, vB})
        elseif not n2 then
            -- p2 is in front, p1 and p3 are behind
            local pA, vA = lerpVertexAtNearPlane(p2, p1, v2, v1, nearPlane)
            local pB, vB = lerpVertexAtNearPlane(p2, p3, v2, v3, nearPlane)
            table.insert(clippedTris, {p2, pB, pA, v2, vB, vA})
        else -- not n3
            -- p3 is in front, p1 and p2 are behind
            local pA, vA = lerpVertexAtNearPlane(p3, p1, v3, v1, nearPlane)
            local pB, vB = lerpVertexAtNearPlane(p3, p2, v3, v2, nearPlane)
            table.insert(clippedTris, {p3, pA, pB, v3, vA, vB})
        end
    end

    return clippedTris
end

-- Draw a triangle that's already in clip space (used after clipping)
local function drawClippedTriangle(p1, p2, p3, v1, v2, v3, texture, texData, brightness, fogFactor)
    -- Project to screen space
    local s1x = (p1[1] / p1[4] + 1) * RENDER_WIDTH * 0.5
    local s1y = (1 - p1[2] / p1[4]) * RENDER_HEIGHT * 0.5
    local s2x = (p2[1] / p2[4] + 1) * RENDER_WIDTH * 0.5
    local s2y = (1 - p2[2] / p2[4]) * RENDER_HEIGHT * 0.5
    local s3x = (p3[1] / p3[4] + 1) * RENDER_WIDTH * 0.5
    local s3y = (1 - p3[2] / p3[4]) * RENDER_HEIGHT * 0.5

    -- Perspective-correct attributes
    local w1 = 1 / p1[4]
    local w2 = 1 / p2[4]
    local w3 = 1 / p3[4]

    -- Get texture dimensions
    local texW = texData:getWidth()
    local texH = texData:getHeight()

    local vA = {
        s1x, s1y,
        w1,
        v1.uv[1] * texW * w1, v1.uv[2] * texH * w1,
        p1[3] / p1[4]
    }
    local vB = {
        s2x, s2y,
        w2,
        v2.uv[1] * texW * w2, v2.uv[2] * texH * w2,
        p2[3] / p2[4]
    }
    local vC = {
        s3x, s3y,
        w3,
        v3.uv[1] * texW * w3, v3.uv[2] * texH * w3,
        p3[3] / p3[4]
    }

    renderer_dda.drawTriangle(vA, vB, vC, texture, texData, brightness, fogFactor)
end

-- Pre-allocated buffers for single triangle drawing (drawTriangle3D)
local singleP1 = {0, 0, 0, 0}
local singleP2 = {0, 0, 0, 0}
local singleP3 = {0, 0, 0, 0}
local singleVA = {0, 0, 0, 0, 0, 0}
local singleVB = {0, 0, 0, 0, 0, 0}
local singleVC = {0, 0, 0, 0, 0, 0}

-- Inline MVP transform for single triangles (avoids function call overhead)
local function transformVertex(mvp, x, y, z, out)
    out[1] = mvp[1] * x + mvp[2] * y + mvp[3] * z + mvp[4]
    out[2] = mvp[5] * x + mvp[6] * y + mvp[7] * z + mvp[8]
    out[3] = mvp[9] * x + mvp[10] * y + mvp[11] * z + mvp[12]
    out[4] = mvp[13] * x + mvp[14] * y + mvp[15] * z + mvp[16]
end

-- Draw a triangle in 3D world space
-- v1, v2, v3 are tables with {pos = {x,y,z}, uv = {u,v}, brightness = 0-1 (optional)}
-- brightness is optional per-vertex lighting multiplier
-- fogFactor: optional 0-1 value for per-triangle fog (nil = use per-pixel depth fog)
function renderer_dda.drawTriangle3D(v1, v2, v3, texture, texData, brightness, fogFactor)
    local t0 = getTime()

    if not currentMVP then
        error("Must call renderer_dda.setMatrices() before drawTriangle3D()")
    end

    local mvp = currentMVP
    local nearPlane = 0.01
    local halfW = RENDER_WIDTH * 0.5
    local halfH = RENDER_HEIGHT * 0.5

    -- Transform to clip space using pre-allocated tables (zero allocation)
    local p1x, p1y, p1z = v1.pos[1], v1.pos[2], v1.pos[3]
    local p2x, p2y, p2z = v2.pos[1], v2.pos[2], v2.pos[3]
    local p3x, p3y, p3z = v3.pos[1], v3.pos[2], v3.pos[3]

    transformVertex(mvp, p1x, p1y, p1z, singleP1)
    transformVertex(mvp, p2x, p2y, p2z, singleP2)
    transformVertex(mvp, p3x, p3y, p3z, singleP3)

    -- Near plane clipping
    local w1, w2, w3 = singleP1[4], singleP2[4], singleP3[4]
    local n1 = w1 <= nearPlane
    local n2 = w2 <= nearPlane
    local n3 = w3 <= nearPlane

    -- All vertices behind - cull entire triangle
    if n1 and n2 and n3 then
        return
    end

    -- Handle clipping case (rare - fall back to allocation path)
    if n1 or n2 or n3 then
        -- Need to create tables for clipping (unavoidable for edge cases)
        local p1 = {singleP1[1], singleP1[2], singleP1[3], singleP1[4]}
        local p2 = {singleP2[1], singleP2[2], singleP2[3], singleP2[4]}
        local p3 = {singleP3[1], singleP3[2], singleP3[3], singleP3[4]}
        local clippedTriangles = clipTriangleNearPlane(p1, p2, p3, v1, v2, v3, n1, n2, n3, nearPlane)
        for _, tri in ipairs(clippedTriangles) do
            drawClippedTriangle(tri[1], tri[2], tri[3], tri[4], tri[5], tri[6], texture, texData, brightness, fogFactor)
        end
        return
    end

    -- Project to screen space (inline, no allocations)
    local invW1 = 1 / w1
    local invW2 = 1 / w2
    local invW3 = 1 / w3

    local s1x = (singleP1[1] * invW1 + 1) * halfW
    local s1y = (1 - singleP1[2] * invW1) * halfH
    local s2x = (singleP2[1] * invW2 + 1) * halfW
    local s2y = (1 - singleP2[2] * invW2) * halfH
    local s3x = (singleP3[1] * invW3 + 1) * halfW
    local s3y = (1 - singleP3[2] * invW3) * halfH

    -- Get texture dimensions
    local texW = texData:getWidth()
    local texH = texData:getHeight()

    -- Build screen-space vertices using pre-allocated tables
    singleVA[1] = s1x
    singleVA[2] = s1y
    singleVA[3] = invW1
    singleVA[4] = v1.uv[1] * texW * invW1
    singleVA[5] = v1.uv[2] * texH * invW1
    singleVA[6] = singleP1[3] * invW1

    singleVB[1] = s2x
    singleVB[2] = s2y
    singleVB[3] = invW2
    singleVB[4] = v2.uv[1] * texW * invW2
    singleVB[5] = v2.uv[2] * texH * invW2
    singleVB[6] = singleP2[3] * invW2

    singleVC[1] = s3x
    singleVC[2] = s3y
    singleVC[3] = invW3
    singleVC[4] = v3.uv[1] * texW * invW3
    singleVC[5] = v3.uv[2] * texH * invW3
    singleVC[6] = singleP3[3] * invW3

    local t1 = getTime()
    stats.timeTransform = stats.timeTransform + (t1 - t0)

    renderer_dda.drawTriangle(singleVA, singleVB, singleVC, texture, texData, brightness, fogFactor)

    stats.timeRasterize = stats.timeRasterize + (getTime() - t1)
end

-- Pre-allocated buffers for batch drawing (avoid per-triangle allocations)
local batchP1 = {0, 0, 0, 0}
local batchP2 = {0, 0, 0, 0}
local batchP3 = {0, 0, 0, 0}
local batchVA = {0, 0, 0, 0, 0, 0}
local batchVB = {0, 0, 0, 0, 0, 0}
local batchVC = {0, 0, 0, 0, 0, 0}

-- Draw multiple triangles with the same texture (optimized for terrain/batches)
-- triangles: array of {v1, v2, v3, fogFactor} where v1/v2/v3 are {pos={x,y,z}, uv={u,v}}
-- This avoids per-triangle table allocations and function call overhead
function renderer_dda.drawTriangleBatch(triangles, texData, brightness)
    if not currentMVP then
        error("Must call renderer_dda.setMatrices() before drawTriangleBatch()")
    end

    local t0 = getTime()
    local mvp = currentMVP
    local nearPlane = 0.01
    local halfW = RENDER_WIDTH * 0.5
    local halfH = RENDER_HEIGHT * 0.5

    -- Cache texture dimensions once for entire batch
    local texW = texData:getWidth()
    local texH = texData:getHeight()

    for i = 1, #triangles do
        local tri = triangles[i]
        local v1, v2, v3, fogFactor = tri[1], tri[2], tri[3], tri[4]

        -- Inline transform to clip space (reuse pre-allocated tables)
        local p1x, p1y, p1z = v1.pos[1], v1.pos[2], v1.pos[3]
        local p2x, p2y, p2z = v2.pos[1], v2.pos[2], v2.pos[3]
        local p3x, p3y, p3z = v3.pos[1], v3.pos[2], v3.pos[3]

        transformVertex(mvp, p1x, p1y, p1z, batchP1)
        transformVertex(mvp, p2x, p2y, p2z, batchP2)
        transformVertex(mvp, p3x, p3y, p3z, batchP3)

        -- Near plane culling
        local w1, w2, w3 = batchP1[4], batchP2[4], batchP3[4]
        local n1 = w1 <= nearPlane
        local n2 = w2 <= nearPlane
        local n3 = w3 <= nearPlane

        -- All behind - skip
        if n1 and n2 and n3 then
            goto continue_batch
        end

        -- Partial clipping - fall back to regular path (rare for terrain)
        if n1 or n2 or n3 then
            -- Use regular drawTriangle3D for clipped triangles
            renderer_dda.drawTriangle3D(v1, v2, v3, nil, texData, brightness, fogFactor)
            goto continue_batch
        end

        -- Project to screen space (inline)
        local invW1 = 1 / w1
        local invW2 = 1 / w2
        local invW3 = 1 / w3

        local s1x = (batchP1[1] * invW1 + 1) * halfW
        local s1y = (1 - batchP1[2] * invW1) * halfH
        local s2x = (batchP2[1] * invW2 + 1) * halfW
        local s2y = (1 - batchP2[2] * invW2) * halfH
        local s3x = (batchP3[1] * invW3 + 1) * halfW
        local s3y = (1 - batchP3[2] * invW3) * halfH

        -- Build screen-space vertices (reuse pre-allocated tables)
        batchVA[1] = s1x
        batchVA[2] = s1y
        batchVA[3] = invW1
        batchVA[4] = v1.uv[1] * texW * invW1
        batchVA[5] = v1.uv[2] * texH * invW1
        batchVA[6] = batchP1[3] * invW1

        batchVB[1] = s2x
        batchVB[2] = s2y
        batchVB[3] = invW2
        batchVB[4] = v2.uv[1] * texW * invW2
        batchVB[5] = v2.uv[2] * texH * invW2
        batchVB[6] = batchP2[3] * invW2

        batchVC[1] = s3x
        batchVC[2] = s3y
        batchVC[3] = invW3
        batchVC[4] = v3.uv[1] * texW * invW3
        batchVC[5] = v3.uv[2] * texH * invW3
        batchVC[6] = batchP3[3] * invW3

        -- Rasterize
        renderer_dda.drawTriangle(batchVA, batchVB, batchVC, nil, texData, brightness, fogFactor)

        ::continue_batch::
    end

    local t1 = getTime()
    stats.timeTransform = stats.timeTransform + (t1 - t0)
end

-- Draw a 3D line in world space with depth testing
-- p0, p1 are {x, y, z} world positions
-- r, g, b are 0-255
-- skipZBuffer: if true, draws behind everything (for starfield background)
-- Uses the current MVP matrix set by setMatrices()
function renderer_dda.drawLine3D(p0, p1, r, g, b, skipZBuffer)
    if not currentMVP then
        error("Must call renderer_dda.setMatrices() before drawLine3D()")
    end

    -- Transform to clip space
    local c0 = mat4.multiplyVec4(currentMVP, {p0[1], p0[2], p0[3], 1})
    local c1 = mat4.multiplyVec4(currentMVP, {p1[1], p1[2], p1[3], 1})

    -- Near plane clipping
    local nearPlane = 0.01
    local behind0 = c0[4] <= nearPlane
    local behind1 = c1[4] <= nearPlane

    -- Both behind near plane - cull
    if behind0 and behind1 then
        return
    end

    -- Clip line to near plane if needed
    if behind0 then
        -- p0 is behind, interpolate to near plane
        local t = (nearPlane - c0[4]) / (c1[4] - c0[4])
        c0 = {
            c0[1] + t * (c1[1] - c0[1]),
            c0[2] + t * (c1[2] - c0[2]),
            c0[3] + t * (c1[3] - c0[3]),
            nearPlane
        }
    elseif behind1 then
        -- p1 is behind, interpolate to near plane
        local t = (nearPlane - c1[4]) / (c0[4] - c1[4])
        c1 = {
            c1[1] + t * (c0[1] - c1[1]),
            c1[2] + t * (c0[2] - c1[2]),
            c1[3] + t * (c0[3] - c1[3]),
            nearPlane
        }
    end

    -- Project to screen space
    local x0 = math.floor((c0[1] / c0[4] + 1) * RENDER_WIDTH * 0.5)
    local y0 = math.floor((1 - c0[2] / c0[4]) * RENDER_HEIGHT * 0.5)
    local z0 = c0[3] / c0[4]  -- Normalized depth for z-buffer

    local x1 = math.floor((c1[1] / c1[4] + 1) * RENDER_WIDTH * 0.5)
    local y1 = math.floor((1 - c1[2] / c1[4]) * RENDER_HEIGHT * 0.5)
    local z1 = c1[3] / c1[4]

    -- Bresenham's line algorithm with depth testing
    local dx = math.abs(x1 - x0)
    local dy = math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx - dy

    -- Calculate total steps for depth interpolation
    local steps = math.max(dx, dy)
    if steps == 0 then steps = 1 end
    local zStep = (z1 - z0) / steps
    local currentZ = z0
    local stepCount = 0

    while true do
        -- Draw pixel if in bounds and passes depth test
        if x0 >= 0 and x0 < RENDER_WIDTH and y0 >= 0 and y0 < RENDER_HEIGHT then
            local index = y0 * RENDER_WIDTH + x0

            if skipZBuffer then
                -- Draw only where z-buffer is at max (nothing rendered yet)
                -- This makes lines appear behind everything
                if zbufferPtr[index] >= 1.0 then
                    local pixelIndex = index * 4
                    framebufferPtr[pixelIndex] = r
                    framebufferPtr[pixelIndex + 1] = g
                    framebufferPtr[pixelIndex + 2] = b
                    framebufferPtr[pixelIndex + 3] = 255
                end
            else
                -- Normal depth test
                if currentZ < zbufferPtr[index] then
                    zbufferPtr[index] = currentZ

                    local pixelIndex = index * 4
                    framebufferPtr[pixelIndex] = r
                    framebufferPtr[pixelIndex + 1] = g
                    framebufferPtr[pixelIndex + 2] = b
                    framebufferPtr[pixelIndex + 3] = 255
                end
            end
        end

        if x0 == x1 and y0 == y1 then break end

        local e2 = 2 * err
        if e2 > -dy then
            err = err - dy
            x0 = x0 + sx
        end
        if e2 < dx then
            err = err + dx
            y0 = y0 + sy
        end

        stepCount = stepCount + 1
        currentZ = z0 + zStep * stepCount
    end
end

-- Draw a 2D line in screen space using Bresenham's algorithm
-- x0, y0, x1, y1 are in render resolution coordinates
-- r, g, b are 0-255
function renderer_dda.drawLine2D(x0, y0, x1, y1, r, g, b)
    x0 = math.floor(x0)
    y0 = math.floor(y0)
    x1 = math.floor(x1)
    y1 = math.floor(y1)

    local dx = math.abs(x1 - x0)
    local dy = math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx - dy

    while true do
        -- Draw pixel if in bounds
        if x0 >= 0 and x0 < RENDER_WIDTH and y0 >= 0 and y0 < RENDER_HEIGHT then
            local index = y0 * RENDER_WIDTH + x0
            local pixelIndex = index * 4
            framebufferPtr[pixelIndex] = r
            framebufferPtr[pixelIndex + 1] = g
            framebufferPtr[pixelIndex + 2] = b
            framebufferPtr[pixelIndex + 3] = 255
        end

        if x0 == x1 and y0 == y1 then break end

        local e2 = 2 * err
        if e2 > -dy then
            err = err - dy
            x0 = x0 + sx
        end
        if e2 < dx then
            err = err + dx
            y0 = y0 + sy
        end
    end
end

-- Simple 4x5 bitmap font for basic characters
-- Each character is defined as a 4-wide, 5-tall bitmap (stored as 5 rows of 4 bits)
local font_4x5 = {
    -- Numbers 0-9
    ["0"] = {0xF,0x9,0x9,0x9,0xF},
    ["1"] = {0x2,0x6,0x2,0x2,0x7},
    ["2"] = {0xF,0x1,0xF,0x8,0xF},
    ["3"] = {0xF,0x1,0xF,0x1,0xF},
    ["4"] = {0x9,0x9,0xF,0x1,0x1},
    ["5"] = {0xF,0x8,0xF,0x1,0xF},
    ["6"] = {0xF,0x8,0xF,0x9,0xF},
    ["7"] = {0xF,0x1,0x2,0x4,0x4},
    ["8"] = {0xF,0x9,0xF,0x9,0xF},
    ["9"] = {0xF,0x9,0xF,0x1,0xF},
    -- Letters A-Z
    ["A"] = {0x6,0x9,0xF,0x9,0x9},
    ["B"] = {0xE,0x9,0xE,0x9,0xE},
    ["C"] = {0x7,0x8,0x8,0x8,0x7},
    ["D"] = {0xE,0x9,0x9,0x9,0xE},
    ["E"] = {0xF,0x8,0xE,0x8,0xF},
    ["F"] = {0xF,0x8,0xE,0x8,0x8},
    ["G"] = {0x7,0x8,0xB,0x9,0x7},
    ["H"] = {0x9,0x9,0xF,0x9,0x9},
    ["I"] = {0x7,0x2,0x2,0x2,0x7},
    ["J"] = {0x7,0x2,0x2,0xA,0x4},
    ["K"] = {0x9,0xA,0xC,0xA,0x9},
    ["L"] = {0x8,0x8,0x8,0x8,0xF},
    ["M"] = {0x9,0xF,0xF,0x9,0x9},
    ["N"] = {0x9,0xD,0xF,0xB,0x9},
    ["O"] = {0x6,0x9,0x9,0x9,0x6},
    ["P"] = {0xE,0x9,0xE,0x8,0x8},
    ["Q"] = {0x6,0x9,0x9,0xB,0x7},
    ["R"] = {0xE,0x9,0xE,0xA,0x9},
    ["S"] = {0x7,0x8,0x6,0x1,0xE},
    ["T"] = {0x7,0x2,0x2,0x2,0x2},
    ["U"] = {0x9,0x9,0x9,0x9,0x6},
    ["V"] = {0x9,0x9,0x9,0x6,0x6},
    ["W"] = {0x9,0x9,0xF,0xF,0x9},
    ["X"] = {0x9,0x9,0x6,0x9,0x9},
    ["Y"] = {0x5,0x5,0x2,0x2,0x2},
    ["Z"] = {0xF,0x1,0x6,0x8,0xF},
    -- Punctuation and symbols
    [":"] = {0x0,0x2,0x0,0x2,0x0},
    ["."] = {0x0,0x0,0x0,0x0,0x2},
    [","] = {0x0,0x0,0x0,0x2,0x4},
    ["-"] = {0x0,0x0,0x7,0x0,0x0},
    ["/"] = {0x1,0x1,0x2,0x4,0x4},
    ["%"] = {0x9,0x1,0x2,0x4,0x9},
    ["!"] = {0x2,0x2,0x2,0x0,0x2},
    ["?"] = {0x6,0x1,0x2,0x0,0x2},
    ["("] = {0x1,0x2,0x2,0x2,0x1},
    [")"] = {0x4,0x2,0x2,0x2,0x4},
    ["["] = {0x3,0x2,0x2,0x2,0x3},
    ["]"] = {0x6,0x2,0x2,0x2,0x6},
    [" "] = {0x0,0x0,0x0,0x0,0x0},
    -- Lowercase (map to uppercase-like glyphs, slightly smaller feel)
    ["a"] = {0x0,0x6,0xB,0x9,0x7},
    ["b"] = {0x8,0xE,0x9,0x9,0xE},
    ["c"] = {0x0,0x7,0x8,0x8,0x7},
    ["d"] = {0x1,0x7,0x9,0x9,0x7},
    ["e"] = {0x0,0x6,0xF,0x8,0x7},
    ["f"] = {0x3,0x4,0xE,0x4,0x4},
    ["g"] = {0x0,0x7,0x9,0x7,0xE},
    ["h"] = {0x8,0xE,0x9,0x9,0x9},
    ["i"] = {0x2,0x0,0x2,0x2,0x2},
    ["j"] = {0x1,0x0,0x1,0x9,0x6},
    ["k"] = {0x8,0x9,0xE,0x9,0x9},
    ["l"] = {0x6,0x2,0x2,0x2,0x7},
    ["m"] = {0x0,0xF,0xF,0x9,0x9},
    ["n"] = {0x0,0xE,0x9,0x9,0x9},
    ["o"] = {0x0,0x6,0x9,0x9,0x6},
    ["p"] = {0x0,0xE,0x9,0xE,0x8},
    ["q"] = {0x0,0x7,0x9,0x7,0x1},
    ["r"] = {0x0,0xB,0xC,0x8,0x8},
    ["s"] = {0x0,0x7,0x4,0x2,0xE},
    ["t"] = {0x2,0x7,0x2,0x2,0x1},
    ["u"] = {0x0,0x9,0x9,0x9,0x7},
    ["v"] = {0x0,0x9,0x9,0x6,0x6},
    ["w"] = {0x0,0x9,0xF,0xF,0x9},
    ["x"] = {0x0,0x9,0x6,0x6,0x9},
    ["y"] = {0x0,0x9,0x7,0x1,0x6},
    ["z"] = {0x0,0xF,0x2,0x4,0xF},
}

-- Draw a single pixel (public function for minimap, etc.)
function renderer_dda.drawPixel(x, y, r, g, b)
    if x >= 0 and x < RENDER_WIDTH and y >= 0 and y < RENDER_HEIGHT then
        local index = math.floor(y) * RENDER_WIDTH + math.floor(x)
        local pixelIndex = index * 4
        framebufferPtr[pixelIndex] = r
        framebufferPtr[pixelIndex + 1] = g
        framebufferPtr[pixelIndex + 2] = b
        framebufferPtr[pixelIndex + 3] = 255
    end
end

-- Draw a filled rectangle
function renderer_dda.drawRectFill(x1, y1, x2, y2, r, g, b, alpha)
    x1 = math.floor(x1)
    y1 = math.floor(y1)
    x2 = math.floor(x2)
    y2 = math.floor(y2)

    -- Clamp to screen bounds
    if x1 < 0 then x1 = 0 end
    if y1 < 0 then y1 = 0 end
    if x2 >= RENDER_WIDTH then x2 = RENDER_WIDTH - 1 end
    if y2 >= RENDER_HEIGHT then y2 = RENDER_HEIGHT - 1 end

    if x1 > x2 or y1 > y2 then return end

    -- Alpha blending support (0-255)
    alpha = alpha or 255
    local useBlend = alpha < 255
    local invAlpha = 255 - alpha

    for y = y1, y2 do
        local rowBase = y * RENDER_WIDTH * 4
        for x = x1, x2 do
            local pixelIndex = rowBase + x * 4
            if useBlend then
                -- Alpha blend with existing pixel
                local oldR = framebufferPtr[pixelIndex]
                local oldG = framebufferPtr[pixelIndex + 1]
                local oldB = framebufferPtr[pixelIndex + 2]
                framebufferPtr[pixelIndex] = math.floor((r * alpha + oldR * invAlpha) / 255)
                framebufferPtr[pixelIndex + 1] = math.floor((g * alpha + oldG * invAlpha) / 255)
                framebufferPtr[pixelIndex + 2] = math.floor((b * alpha + oldB * invAlpha) / 255)
            else
                framebufferPtr[pixelIndex] = r
                framebufferPtr[pixelIndex + 1] = g
                framebufferPtr[pixelIndex + 2] = b
            end
            framebufferPtr[pixelIndex + 3] = 255
        end
    end
end

-- Draw a rectangle outline
function renderer_dda.drawRect(x1, y1, x2, y2, r, g, b)
    x1 = math.floor(x1)
    y1 = math.floor(y1)
    x2 = math.floor(x2)
    y2 = math.floor(y2)

    -- Draw top and bottom edges
    for x = x1, x2 do
        renderer_dda.drawPixel(x, y1, r, g, b)
        renderer_dda.drawPixel(x, y2, r, g, b)
    end
    -- Draw left and right edges
    for y = y1, y2 do
        renderer_dda.drawPixel(x1, y, r, g, b)
        renderer_dda.drawPixel(x2, y, r, g, b)
    end
end

-- Draw a filled circle
function renderer_dda.drawCircleFill(cx, cy, radius, r, g, b)
    cx = math.floor(cx)
    cy = math.floor(cy)
    radius = math.floor(radius)

    for y = -radius, radius do
        for x = -radius, radius do
            if x*x + y*y <= radius*radius then
                renderer_dda.drawPixel(cx + x, cy + y, r, g, b)
            end
        end
    end
end

-- Draw a circle outline
function renderer_dda.drawCircle(cx, cy, radius, r, g, b)
    cx = math.floor(cx)
    cy = math.floor(cy)
    radius = math.floor(radius)

    -- Midpoint circle algorithm
    local x = radius
    local y = 0
    local err = 0

    while x >= y do
        renderer_dda.drawPixel(cx + x, cy + y, r, g, b)
        renderer_dda.drawPixel(cx + y, cy + x, r, g, b)
        renderer_dda.drawPixel(cx - y, cy + x, r, g, b)
        renderer_dda.drawPixel(cx - x, cy + y, r, g, b)
        renderer_dda.drawPixel(cx - x, cy - y, r, g, b)
        renderer_dda.drawPixel(cx - y, cy - x, r, g, b)
        renderer_dda.drawPixel(cx + y, cy - x, r, g, b)
        renderer_dda.drawPixel(cx + x, cy - y, r, g, b)

        y = y + 1
        if err <= 0 then
            err = err + 2*y + 1
        end
        if err > 0 then
            x = x - 1
            err = err - 2*x + 1
        end
    end
end

-- Draw a single pixel (helper for text)
local function drawPixelDirect(x, y, r, g, b)
    if x >= 0 and x < RENDER_WIDTH and y >= 0 and y < RENDER_HEIGHT then
        local index = y * RENDER_WIDTH + x
        local pixelIndex = index * 4
        framebufferPtr[pixelIndex] = r
        framebufferPtr[pixelIndex + 1] = g
        framebufferPtr[pixelIndex + 2] = b
        framebufferPtr[pixelIndex + 3] = 255
    end
end

-- Draw a single character at position (x, y) with color (r, g, b)
-- Returns the width of the character drawn
local function drawChar(char, x, y, r, g, b, scale)
    scale = scale or 1
    local glyph = font_4x5[char]
    if not glyph then return 4 * scale end  -- Space for unknown chars

    for row = 0, 4 do
        local bits = glyph[row + 1]
        for col = 0, 3 do
            if bit.band(bits, bit.lshift(1, 3 - col)) ~= 0 then
                -- Draw scaled pixel
                for sy = 0, scale - 1 do
                    for sx = 0, scale - 1 do
                        drawPixelDirect(
                            math.floor(x + col * scale + sx),
                            math.floor(y + row * scale + sy),
                            r, g, b
                        )
                    end
                end
            end
        end
    end

    return 5 * scale  -- Character width + 1 pixel spacing
end

-- Draw text with drop shadow
-- x, y: position in render coordinates
-- text: string to draw
-- r, g, b: text color (0-255)
-- scale: pixel scale (default 1)
-- shadow: draw drop shadow (default true)
function renderer_dda.drawText(x, y, text, r, g, b, scale, shadow)
    scale = scale or 1
    if shadow == nil then shadow = true end

    x = math.floor(x)
    y = math.floor(y)

    -- Draw shadow first (offset by 1 pixel)
    if shadow then
        local shadowX = x + scale
        local shadowY = y + scale
        local cursorX = shadowX
        for i = 1, #text do
            local char = text:sub(i, i)
            cursorX = cursorX + drawChar(char, cursorX, shadowY, 0, 0, 0, scale)
        end
    end

    -- Draw main text
    local cursorX = x
    for i = 1, #text do
        local char = text:sub(i, i)
        cursorX = cursorX + drawChar(char, cursorX, y, r, g, b, scale)
    end

    return cursorX - x  -- Return total width
end

-- Cached software image for presentation
local softwareImage = nil

-- Present the rendered frame to screen (matches GPU renderer API)
function renderer_dda.present()
    -- Create software image on first use
    if not softwareImage then
        softwareImage = love.graphics.newImage(softwareImageData)
        softwareImage:setFilter("nearest", "nearest")
    end

    -- Update the image with current framebuffer data
    softwareImage:replacePixels(softwareImageData)

    -- Calculate scaling to fit window while maintaining aspect ratio
    local windowW = love.graphics.getWidth()
    local windowH = love.graphics.getHeight()
    local scaleX = windowW / RENDER_WIDTH
    local scaleY = windowH / RENDER_HEIGHT
    local scale = math.min(scaleX, scaleY)

    -- Center the image
    local offsetX = (windowW - RENDER_WIDTH * scale) / 2
    local offsetY = (windowH - RENDER_HEIGHT * scale) / 2

    -- Clear and draw
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(softwareImage, offsetX, offsetY, 0, scale, scale)
end

return renderer_dda
