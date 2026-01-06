-- GPU-based Renderer using LÖVE shaders
-- Replicates the software renderer look with massive performance gains
-- Features: Dithered fog, nearest-neighbor texturing, pixel-perfect lines

local config = require("config")
local mat4 = require("mat4")

local renderer_gpu = {}

-- Configuration
local RENDER_WIDTH = config.RENDER_WIDTH
local RENDER_HEIGHT = config.RENDER_HEIGHT

-- Render target (low-res canvas for pixel art look)
local canvas = nil
local depthCanvas = nil

-- Shaders
local shaderFlat = nil

-- Current state
local currentMVP = nil
local currentCamera = nil

-- Fog settings
local fogEnabled = true
local fogNear = 10.0
local fogFar = 100.0
local fogColor = {0.157, 0.157, 0.235}  -- Normalized RGB

-- Clear color
local clearColor = {162/255, 136/255, 121/255}

-- Dithering toggle
local ditherEnabled = true

-- Stats for profiler compatibility
local stats = {
    trianglesDrawn = 0,
    pixelsDrawn = 0,
    trianglesCulled = 0,
    trianglesClipped = 0,
    timeTransform = 0,
    timeRasterize = 0
}

-- Mesh batching
local meshBatches = {}  -- {texture = mesh}
local currentBatchVertices = {}
local currentBatchTexture = nil

-- Image cache for ImageData -> Image conversion (weak keys so GC can clean up)
local imageCache = setmetatable({}, {__mode = "k"})

-- Initialize the renderer
function renderer_gpu.init(width, height)
    RENDER_WIDTH = width or RENDER_WIDTH
    RENDER_HEIGHT = height or RENDER_HEIGHT

    -- Create low-res render target
    canvas = love.graphics.newCanvas(RENDER_WIDTH, RENDER_HEIGHT, {format = "rgba8", readable = true})
    canvas:setFilter("nearest", "nearest")

    -- Create depth buffer for proper z-ordering
    depthCanvas = love.graphics.newCanvas(RENDER_WIDTH, RENDER_HEIGHT, {format = "depth16", readable = false})

    -- Load flat shader for screen-space triangles
    local shaderPath = "src/graphics/shaders/"
    local shaderFlatCode = love.filesystem.read(shaderPath .. "retro_flat.glsl")
    if shaderFlatCode then
        shaderFlat = love.graphics.newShader(shaderFlatCode)
    else
        error("Could not load retro_flat.glsl shader")
    end

    print("GPU Renderer initialized: " .. RENDER_WIDTH .. "x" .. RENDER_HEIGHT)
end

-- Clear buffers at start of frame
function renderer_gpu.clearBuffers()
    -- Reset stats
    stats.trianglesDrawn = 0
    stats.pixelsDrawn = 0
    stats.trianglesCulled = 0
    stats.trianglesClipped = 0
    stats.timeTransform = 0
    stats.timeRasterize = 0

    -- Clear batch data
    meshBatches = {}
    currentBatchVertices = {}

    -- Set render target with depth buffer
    love.graphics.setCanvas({canvas, depthstencil = depthCanvas})
    love.graphics.clear(clearColor[1], clearColor[2], clearColor[3], 1, true, 1)
    love.graphics.setDepthMode("less", true)
end

-- Get stats for profiler
function renderer_gpu.getStats()
    return stats
end

-- Fog control
function renderer_gpu.setFog(enabled, near, far, r, g, b)
    fogEnabled = enabled
    if near then fogNear = near end
    if far then fogFar = far end
    if r then fogColor[1] = r / 255 end
    if g then fogColor[2] = g / 255 end
    if b then fogColor[3] = b / 255 end
end

function renderer_gpu.getFogEnabled()
    return fogEnabled
end

function renderer_gpu.getFogSettings()
    return fogNear, fogFar
end

-- Set clear color
function renderer_gpu.setClearColor(r, g, b)
    clearColor[1] = (r or 162) / 255
    clearColor[2] = (g or 136) / 255
    clearColor[3] = (b or 121) / 255
end

-- Toggle dithering
function renderer_gpu.toggleDither()
    ditherEnabled = not ditherEnabled
    return ditherEnabled
end

function renderer_gpu.isDitherEnabled()
    return ditherEnabled
end

-- Set matrices for 3D rendering
function renderer_gpu.setMatrices(mvpMatrix, cameraPos)
    currentMVP = mvpMatrix
    currentCamera = cameraPos
end

-- Pre-allocated tables for transformation
local clipPos1 = {0, 0, 0, 0}
local clipPos2 = {0, 0, 0, 0}
local clipPos3 = {0, 0, 0, 0}

-- Transform vertex to clip space, then to screen space
local function transformToScreen(mvp, x, y, z, out)
    -- MVP * vertex (row-major matrix multiplication)
    out[1] = mvp[1] * x + mvp[2] * y + mvp[3] * z + mvp[4]
    out[2] = mvp[5] * x + mvp[6] * y + mvp[7] * z + mvp[8]
    out[3] = mvp[9] * x + mvp[10] * y + mvp[11] * z + mvp[12]
    out[4] = mvp[13] * x + mvp[14] * y + mvp[15] * z + mvp[16]
end

-- Draw a single 3D triangle (immediate mode - less efficient than batching)
function renderer_gpu.drawTriangle3D(v1, v2, v3, texture, texData, brightness, fogFactor)
    if not currentMVP then
        error("Must call renderer_gpu.setMatrices() before drawTriangle3D()")
    end

    local t0 = love.timer.getTime()

    -- Transform vertices to clip space
    transformToScreen(currentMVP, v1.pos[1], v1.pos[2], v1.pos[3], clipPos1)
    transformToScreen(currentMVP, v2.pos[1], v2.pos[2], v2.pos[3], clipPos2)
    transformToScreen(currentMVP, v3.pos[1], v3.pos[2], v3.pos[3], clipPos3)

    -- Near plane clipping (simple reject if all behind)
    local nearPlane = 0.01
    if clipPos1[4] <= nearPlane and clipPos2[4] <= nearPlane and clipPos3[4] <= nearPlane then
        return  -- All vertices behind camera
    end

    -- Perspective divide and screen space conversion
    local halfW = RENDER_WIDTH * 0.5
    local halfH = RENDER_HEIGHT * 0.5

    local invW1 = 1 / clipPos1[4]
    local invW2 = 1 / clipPos2[4]
    local invW3 = 1 / clipPos3[4]

    local s1x = (clipPos1[1] * invW1 + 1) * halfW
    local s1y = (1 - clipPos1[2] * invW1) * halfH
    local s1z = 1 - (clipPos1[3] * invW1 + 1) * 0.5  -- Invert: near=0, far=1

    local s2x = (clipPos2[1] * invW2 + 1) * halfW
    local s2y = (1 - clipPos2[2] * invW2) * halfH
    local s2z = 1 - (clipPos2[3] * invW2 + 1) * 0.5

    local s3x = (clipPos3[1] * invW3 + 1) * halfW
    local s3y = (1 - clipPos3[2] * invW3) * halfH
    local s3z = 1 - (clipPos3[3] * invW3 + 1) * 0.5

    -- Get or create image from texData
    local image
    local texType = texData:type()
    if texType == "Image" then
        image = texData
    elseif texType == "ImageData" then
        image = imageCache[texData]
        if not image then
            image = love.graphics.newImage(texData)
            image:setFilter("nearest", "nearest")
            imageCache[texData] = image
        end
    else
        error("Invalid texture data type: " .. tostring(texType))
    end

    local texW, texH = image:getDimensions()
    local bright = brightness or 1.0

    -- Build vertices for LÖVE mesh in SCREEN SPACE with depth
    -- Format: {x, y, z, u, v, r, g, b, a}
    local vertices = {
        {s1x, s1y, s1z, v1.uv[1], v1.uv[2], 1, 1, 1, bright},
        {s2x, s2y, s2z, v2.uv[1], v2.uv[2], 1, 1, 1, bright},
        {s3x, s3y, s3z, v3.uv[1], v3.uv[2], 1, 1, 1, bright},
    }

    -- Create mesh with 3D position for depth buffer
    local mesh = love.graphics.newMesh({
        {"VertexPosition", "float", 3},
        {"VertexTexCoord", "float", 2},
        {"VertexColor", "float", 4},
    }, vertices, "triangles", "stream")

    mesh:setTexture(image)

    local t1 = love.timer.getTime()
    stats.timeTransform = stats.timeTransform + (t1 - t0)

    -- Use a simpler shader for screen-space triangles
    love.graphics.setShader(shaderFlat)
    shaderFlat:send("u_textureSize", {texW, texH})
    shaderFlat:send("u_ditherEnabled", ditherEnabled)

    -- Draw
    love.graphics.draw(mesh)
    love.graphics.setShader()

    stats.trianglesDrawn = stats.trianglesDrawn + 1
    stats.timeRasterize = stats.timeRasterize + (love.timer.getTime() - t1)
end

-- Batch draw triangles (much more efficient)
function renderer_gpu.drawTriangleBatch(triangles, texData, brightness)
    if not currentMVP then
        error("Must call renderer_gpu.setMatrices() before drawTriangleBatch()")
    end

    if #triangles == 0 then return end

    local t0 = love.timer.getTime()

    -- Get or create image
    local image
    local texType = texData:type()
    if texType == "Image" then
        image = texData
    elseif texType == "ImageData" then
        image = imageCache[texData]
        if not image then
            image = love.graphics.newImage(texData)
            image:setFilter("nearest", "nearest")
            imageCache[texData] = image
        end
    else
        error("Invalid texture data type: " .. tostring(texType))
    end

    local texW, texH = image:getDimensions()
    local bright = brightness or 1.0
    local halfW = RENDER_WIDTH * 0.5
    local halfH = RENDER_HEIGHT * 0.5
    local nearPlane = 0.01
    local mvp = currentMVP

    -- Build all vertices in screen space
    local vertices = {}
    local triCount = 0
    for _, tri in ipairs(triangles) do
        local v1, v2, v3 = tri[1], tri[2], tri[3]
        local b = bright

        -- Transform each vertex to clip space
        local p1x, p1y, p1z = v1.pos[1], v1.pos[2], v1.pos[3]
        local c1x = mvp[1] * p1x + mvp[2] * p1y + mvp[3] * p1z + mvp[4]
        local c1y = mvp[5] * p1x + mvp[6] * p1y + mvp[7] * p1z + mvp[8]
        local c1z = mvp[9] * p1x + mvp[10] * p1y + mvp[11] * p1z + mvp[12]
        local c1w = mvp[13] * p1x + mvp[14] * p1y + mvp[15] * p1z + mvp[16]

        local p2x, p2y, p2z = v2.pos[1], v2.pos[2], v2.pos[3]
        local c2x = mvp[1] * p2x + mvp[2] * p2y + mvp[3] * p2z + mvp[4]
        local c2y = mvp[5] * p2x + mvp[6] * p2y + mvp[7] * p2z + mvp[8]
        local c2z = mvp[9] * p2x + mvp[10] * p2y + mvp[11] * p2z + mvp[12]
        local c2w = mvp[13] * p2x + mvp[14] * p2y + mvp[15] * p2z + mvp[16]

        local p3x, p3y, p3z = v3.pos[1], v3.pos[2], v3.pos[3]
        local c3x = mvp[1] * p3x + mvp[2] * p3y + mvp[3] * p3z + mvp[4]
        local c3y = mvp[5] * p3x + mvp[6] * p3y + mvp[7] * p3z + mvp[8]
        local c3z = mvp[9] * p3x + mvp[10] * p3y + mvp[11] * p3z + mvp[12]
        local c3w = mvp[13] * p3x + mvp[14] * p3y + mvp[15] * p3z + mvp[16]

        -- Skip if all behind near plane
        if c1w > nearPlane or c2w > nearPlane or c3w > nearPlane then
            -- Perspective divide and screen conversion
            local invW1 = 1 / c1w
            local invW2 = 1 / c2w
            local invW3 = 1 / c3w

            local s1x = (c1x * invW1 + 1) * halfW
            local s1y = (1 - c1y * invW1) * halfH
            local s1z = 1 - (c1z * invW1 + 1) * 0.5  -- Invert: near=0, far=1
            local s2x = (c2x * invW2 + 1) * halfW
            local s2y = (1 - c2y * invW2) * halfH
            local s2z = 1 - (c2z * invW2 + 1) * 0.5
            local s3x = (c3x * invW3 + 1) * halfW
            local s3y = (1 - c3y * invW3) * halfH
            local s3z = 1 - (c3z * invW3 + 1) * 0.5

            table.insert(vertices, {s1x, s1y, s1z, v1.uv[1], v1.uv[2], 1, 1, 1, b})
            table.insert(vertices, {s2x, s2y, s2z, v2.uv[1], v2.uv[2], 1, 1, 1, b})
            table.insert(vertices, {s3x, s3y, s3z, v3.uv[1], v3.uv[2], 1, 1, 1, b})
            triCount = triCount + 1
        end
    end

    if #vertices == 0 then return end

    -- Create mesh with 3D position for depth buffer
    local mesh = love.graphics.newMesh({
        {"VertexPosition", "float", 3},
        {"VertexTexCoord", "float", 2},
        {"VertexColor", "float", 4},
    }, vertices, "triangles", "stream")

    mesh:setTexture(image)

    local t1 = love.timer.getTime()
    stats.timeTransform = stats.timeTransform + (t1 - t0)

    -- Use flat shader for screen-space triangles
    love.graphics.setShader(shaderFlat)
    shaderFlat:send("u_textureSize", {texW, texH})
    shaderFlat:send("u_ditherEnabled", ditherEnabled)

    love.graphics.draw(mesh)
    love.graphics.setShader()

    stats.trianglesDrawn = stats.trianglesDrawn + triCount
    stats.timeRasterize = stats.timeRasterize + (love.timer.getTime() - t1)
end

-- Draw a 3D line
function renderer_gpu.drawLine3D(p0, p1, r, g, b, skipZBuffer)
    if not currentMVP then
        error("Must call renderer_gpu.setMatrices() before drawLine3D()")
    end

    local mvp = currentMVP
    local halfW = RENDER_WIDTH * 0.5
    local halfH = RENDER_HEIGHT * 0.5
    local nearPlane = 0.01

    -- Transform both endpoints to clip space
    local c0x = mvp[1] * p0[1] + mvp[2] * p0[2] + mvp[3] * p0[3] + mvp[4]
    local c0y = mvp[5] * p0[1] + mvp[6] * p0[2] + mvp[7] * p0[3] + mvp[8]
    local c0w = mvp[13] * p0[1] + mvp[14] * p0[2] + mvp[15] * p0[3] + mvp[16]

    local c1x = mvp[1] * p1[1] + mvp[2] * p1[2] + mvp[3] * p1[3] + mvp[4]
    local c1y = mvp[5] * p1[1] + mvp[6] * p1[2] + mvp[7] * p1[3] + mvp[8]
    local c1w = mvp[13] * p1[1] + mvp[14] * p1[2] + mvp[15] * p1[3] + mvp[16]

    -- Skip if both points behind near plane
    if c0w <= nearPlane and c1w <= nearPlane then
        return
    end

    -- Perspective divide and screen conversion
    local invW0 = 1 / math.max(c0w, nearPlane)
    local invW1 = 1 / math.max(c1w, nearPlane)

    local s0x = (c0x * invW0 + 1) * halfW
    local s0y = (1 - c0y * invW0) * halfH
    local s1x = (c1x * invW1 + 1) * halfW
    local s1y = (1 - c1y * invW1) * halfH

    -- Draw line in screen space
    love.graphics.setColor(r/255, g/255, b/255, 1)
    love.graphics.line(s0x, s0y, s1x, s1y)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw a 2D line (screen space)
function renderer_gpu.drawLine2D(x0, y0, x1, y1, r, g, b)
    love.graphics.setColor(r/255, g/255, b/255, 1)
    love.graphics.line(x0, y0, x1, y1)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw a pixel
function renderer_gpu.drawPixel(x, y, r, g, b)
    love.graphics.setColor(r/255, g/255, b/255, 1)
    love.graphics.points(math.floor(x) + 0.5, math.floor(y) + 0.5)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw filled rectangle
function renderer_gpu.drawRectFill(x1, y1, x2, y2, r, g, b, alpha)
    love.graphics.setColor(r/255, g/255, b/255, (alpha or 255)/255)
    love.graphics.rectangle("fill", x1, y1, x2 - x1, y2 - y1)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw rectangle outline
function renderer_gpu.drawRect(x1, y1, x2, y2, r, g, b)
    love.graphics.setColor(r/255, g/255, b/255, 1)
    love.graphics.rectangle("line", x1, y1, x2 - x1, y2 - y1)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw filled circle
function renderer_gpu.drawCircleFill(cx, cy, radius, r, g, b)
    love.graphics.setColor(r/255, g/255, b/255, 1)
    love.graphics.circle("fill", cx, cy, radius)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw circle outline
function renderer_gpu.drawCircle(cx, cy, radius, r, g, b)
    love.graphics.setColor(r/255, g/255, b/255, 1)
    love.graphics.circle("line", cx, cy, radius)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Simple 4x5 bitmap font (copied from software renderer)
local font_4x5 = {
    ["0"] = {0xF,0x9,0x9,0x9,0xF}, ["1"] = {0x2,0x6,0x2,0x2,0x7},
    ["2"] = {0xF,0x1,0xF,0x8,0xF}, ["3"] = {0xF,0x1,0xF,0x1,0xF},
    ["4"] = {0x9,0x9,0xF,0x1,0x1}, ["5"] = {0xF,0x8,0xF,0x1,0xF},
    ["6"] = {0xF,0x8,0xF,0x9,0xF}, ["7"] = {0xF,0x1,0x2,0x4,0x4},
    ["8"] = {0xF,0x9,0xF,0x9,0xF}, ["9"] = {0xF,0x9,0xF,0x1,0xF},
    ["A"] = {0x6,0x9,0xF,0x9,0x9}, ["B"] = {0xE,0x9,0xE,0x9,0xE},
    ["C"] = {0x7,0x8,0x8,0x8,0x7}, ["D"] = {0xE,0x9,0x9,0x9,0xE},
    ["E"] = {0xF,0x8,0xE,0x8,0xF}, ["F"] = {0xF,0x8,0xE,0x8,0x8},
    ["G"] = {0x7,0x8,0xB,0x9,0x7}, ["H"] = {0x9,0x9,0xF,0x9,0x9},
    ["I"] = {0x7,0x2,0x2,0x2,0x7}, ["J"] = {0x7,0x2,0x2,0xA,0x4},
    ["K"] = {0x9,0xA,0xC,0xA,0x9}, ["L"] = {0x8,0x8,0x8,0x8,0xF},
    ["M"] = {0x9,0xF,0xF,0x9,0x9}, ["N"] = {0x9,0xD,0xF,0xB,0x9},
    ["O"] = {0x6,0x9,0x9,0x9,0x6}, ["P"] = {0xE,0x9,0xE,0x8,0x8},
    ["Q"] = {0x6,0x9,0x9,0xB,0x7}, ["R"] = {0xE,0x9,0xE,0xA,0x9},
    ["S"] = {0x7,0x8,0x6,0x1,0xE}, ["T"] = {0x7,0x2,0x2,0x2,0x2},
    ["U"] = {0x9,0x9,0x9,0x9,0x6}, ["V"] = {0x9,0x9,0x9,0x6,0x6},
    ["W"] = {0x9,0x9,0xF,0xF,0x9}, ["X"] = {0x9,0x9,0x6,0x9,0x9},
    ["Y"] = {0x5,0x5,0x2,0x2,0x2}, ["Z"] = {0xF,0x1,0x6,0x8,0xF},
    [":"] = {0x0,0x2,0x0,0x2,0x0}, ["."] = {0x0,0x0,0x0,0x0,0x2},
    [","] = {0x0,0x0,0x0,0x2,0x4}, ["-"] = {0x0,0x0,0x7,0x0,0x0},
    ["/"] = {0x1,0x1,0x2,0x4,0x4}, ["%"] = {0x9,0x1,0x2,0x4,0x9},
    ["!"] = {0x2,0x2,0x2,0x0,0x2}, ["?"] = {0x6,0x1,0x2,0x0,0x2},
    ["("] = {0x1,0x2,0x2,0x2,0x1}, [")"] = {0x4,0x2,0x2,0x2,0x4},
    ["["] = {0x3,0x2,0x2,0x2,0x3}, ["]"] = {0x6,0x2,0x2,0x2,0x6},
    [" "] = {0x0,0x0,0x0,0x0,0x0},
    -- Lowercase
    ["a"] = {0x0,0x6,0xB,0x9,0x7}, ["b"] = {0x8,0xE,0x9,0x9,0xE},
    ["c"] = {0x0,0x7,0x8,0x8,0x7}, ["d"] = {0x1,0x7,0x9,0x9,0x7},
    ["e"] = {0x0,0x6,0xF,0x8,0x7}, ["f"] = {0x3,0x4,0xE,0x4,0x4},
    ["g"] = {0x0,0x7,0x9,0x7,0xE}, ["h"] = {0x8,0xE,0x9,0x9,0x9},
    ["i"] = {0x2,0x0,0x2,0x2,0x2}, ["j"] = {0x1,0x0,0x1,0x9,0x6},
    ["k"] = {0x8,0x9,0xE,0x9,0x9}, ["l"] = {0x6,0x2,0x2,0x2,0x7},
    ["m"] = {0x0,0xF,0xF,0x9,0x9}, ["n"] = {0x0,0xE,0x9,0x9,0x9},
    ["o"] = {0x0,0x6,0x9,0x9,0x6}, ["p"] = {0x0,0xE,0x9,0xE,0x8},
    ["q"] = {0x0,0x7,0x9,0x7,0x1}, ["r"] = {0x0,0xB,0xC,0x8,0x8},
    ["s"] = {0x0,0x7,0x4,0x2,0xE}, ["t"] = {0x2,0x7,0x2,0x2,0x1},
    ["u"] = {0x0,0x9,0x9,0x9,0x7}, ["v"] = {0x0,0x9,0x9,0x6,0x6},
    ["w"] = {0x0,0x9,0xF,0xF,0x9}, ["x"] = {0x0,0x9,0x6,0x6,0x9},
    ["y"] = {0x0,0x9,0x7,0x1,0x6}, ["z"] = {0x0,0xF,0x2,0x4,0xF},
}

local function drawCharGPU(char, x, y, r, g, b, scale)
    scale = scale or 1
    local glyph = font_4x5[char]
    if not glyph then return 4 * scale end

    love.graphics.setColor(r/255, g/255, b/255, 1)

    for row = 0, 4 do
        local bits = glyph[row + 1]
        for col = 0, 3 do
            if bit.band(bits, bit.lshift(1, 3 - col)) ~= 0 then
                love.graphics.rectangle("fill",
                    math.floor(x + col * scale),
                    math.floor(y + row * scale),
                    scale, scale)
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
    return 5 * scale
end

-- Draw text with drop shadow
function renderer_gpu.drawText(x, y, text, r, g, b, scale, shadow)
    scale = scale or 1
    if shadow == nil then shadow = true end

    x = math.floor(x)
    y = math.floor(y)

    -- Draw shadow
    if shadow then
        local cursorX = x + scale
        for i = 1, #text do
            cursorX = cursorX + drawCharGPU(text:sub(i,i), cursorX, y + scale, 0, 0, 0, scale)
        end
    end

    -- Draw text
    local cursorX = x
    for i = 1, #text do
        cursorX = cursorX + drawCharGPU(text:sub(i,i), cursorX, y, r, g, b, scale)
    end

    return cursorX - x
end

-- Get the canvas (for final presentation)
function renderer_gpu.getCanvas()
    return canvas
end

-- End frame and present
function renderer_gpu.present()
    love.graphics.setCanvas()
    love.graphics.setDepthMode()
    love.graphics.setShader()

    -- Draw scaled canvas to screen
    love.graphics.setColor(1, 1, 1, 1)
    local scaleX = love.graphics.getWidth() / RENDER_WIDTH
    local scaleY = love.graphics.getHeight() / RENDER_HEIGHT
    local scale = math.min(scaleX, scaleY)

    local offsetX = (love.graphics.getWidth() - RENDER_WIDTH * scale) / 2
    local offsetY = (love.graphics.getHeight() - RENDER_HEIGHT * scale) / 2

    love.graphics.draw(canvas, offsetX, offsetY, 0, scale, scale)
end

-- Compatibility: getImageData returns nil (not supported in GPU mode)
function renderer_gpu.getImageData()
    return nil
end

-- Clear texture cache (no-op for GPU)
function renderer_gpu.clearTextureCache()
    -- GPU manages its own texture cache
end

-- Fog factor calculation (for compatibility)
function renderer_gpu.calcFogFactor(distance)
    if not fogEnabled or distance <= fogNear then
        return 0
    end
    local factor = (distance - fogNear) / (fogFar - fogNear)
    return math.max(0, math.min(1, factor))
end

return renderer_gpu
