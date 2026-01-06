-- GPU-based Renderer using LÖVE shaders
-- GPU-side MVP transformation for maximum performance
-- Features: Dithered fog, nearest-neighbor texturing, pixel-perfect lines

local config = require("config")
local bit = require("bit")

local renderer_gpu = {}

-- Configuration
local RENDER_WIDTH = config.RENDER_WIDTH
local RENDER_HEIGHT = config.RENDER_HEIGHT

-- Render target (low-res canvas for pixel art look)
local canvas = nil
local depthCanvas = nil

-- Shaders
local shader3D = nil
local shaderFlat = nil
local shaderSky = nil  -- Dedicated sky shader (no fog)

-- Current state (separate matrices like g3d)
local currentProjectionMatrix = nil
local currentViewMatrix = nil
local currentModelMatrix = nil  -- Identity by default, set per-object if needed
local currentCamera = nil

-- Clear color (tan/brown sky color)
local clearColor = {162/255, 136/255, 121/255}

-- Fog settings (fog color should match clear color for seamless fade)
local fogEnabled = true
local fogNear = config.FOG_START_DISTANCE or 30
local fogFar = config.FOG_MAX_DISTANCE or 40
local fogColor = {162/255, 136/255, 121/255}  -- Same as clear color

-- Dithering toggle
local ditherEnabled = true

-- Stats for profiler
local stats = {
    trianglesDrawn = 0,
    pixelsDrawn = 0,
    trianglesCulled = 0,
    trianglesClipped = 0,
    timeTransform = 0,
    timeRasterize = 0,
    drawCalls = 0,
    batchCount = 0
}

-- Image cache for ImageData -> Image conversion
local imageCache = setmetatable({}, {__mode = "k"})

-- Deferred batching: collect vertices per texture, draw at present()
local MAX_VERTICES = 60000  -- 20k triangles max
local batchesByTexture = {}  -- {image = {vertices = {}, count = 0}}
local flushed3D = false  -- Track if flush3D was called this frame

-- Vertex format for 3D meshes (world space position as vec4, UV, color)
-- Use standard LÖVE VertexPosition with 4 components for proper 3D
local vertexFormat3D = {
    {"VertexPosition", "float", 4},  -- World space position (x, y, z, 1.0)
    {"VertexTexCoord", "float", 2},
    {"VertexColor", "float", 4},
}

-- Persistent mesh for batched drawing (reused each frame)
local batchMesh = nil

-- Initialize the renderer
function renderer_gpu.init(width, height)
    RENDER_WIDTH = width or RENDER_WIDTH
    RENDER_HEIGHT = height or RENDER_HEIGHT

    -- Create low-res render target
    canvas = love.graphics.newCanvas(RENDER_WIDTH, RENDER_HEIGHT, {format = "rgba8", readable = true})
    canvas:setFilter("nearest", "nearest")

    -- Create depth buffer
    depthCanvas = love.graphics.newCanvas(RENDER_WIDTH, RENDER_HEIGHT, {format = "depth24", readable = false})

    -- Load 3D shader (GPU-side MVP transformation)
    local shaderPath = "src/graphics/shaders/"
    local shader3DCode = love.filesystem.read(shaderPath .. "retro_3d.glsl")
    if shader3DCode then
        local ok, shaderOrErr = pcall(love.graphics.newShader, shader3DCode)
        if ok then
            shader3D = shaderOrErr
            print("3D shader compiled successfully")
        else
            print("3D shader compilation error: " .. tostring(shaderOrErr))
            error("Failed to compile retro_3d.glsl: " .. tostring(shaderOrErr))
        end
    else
        error("Could not load retro_3d.glsl shader")
    end

    -- Load flat shader for 2D/screen-space drawing
    local shaderFlatCode = love.filesystem.read(shaderPath .. "retro_flat.glsl")
    if shaderFlatCode then
        shaderFlat = love.graphics.newShader(shaderFlatCode)
    else
        error("Could not load retro_flat.glsl shader")
    end

    -- Load sky shader (no fog)
    local shaderSkyCode = love.filesystem.read(shaderPath .. "sky.glsl")
    if shaderSkyCode then
        local ok, shaderOrErr = pcall(love.graphics.newShader, shaderSkyCode)
        if ok then
            shaderSky = shaderOrErr
            print("Sky shader compiled successfully")
        else
            print("Sky shader compilation error: " .. tostring(shaderOrErr))
            -- Fall back to 3D shader if sky shader fails
            shaderSky = shader3D
        end
    else
        print("Could not load sky.glsl shader, using 3D shader")
        shaderSky = shader3D
    end

    -- Create persistent mesh for batched drawing
    batchMesh = love.graphics.newMesh(vertexFormat3D, MAX_VERTICES, "triangles", "stream")

    print("GPU Renderer initialized: " .. RENDER_WIDTH .. "x" .. RENDER_HEIGHT .. " (GPU transform)")
end

-- Clear buffers at start of frame
function renderer_gpu.clearBuffers()
    stats.trianglesDrawn = 0
    stats.pixelsDrawn = 0
    stats.trianglesCulled = 0
    stats.trianglesClipped = 0
    stats.timeTransform = 0
    stats.timeRasterize = 0
    stats.drawCalls = 0
    stats.batchCount = 0

    -- Clear batch counts (reuse vertex arrays)
    for _, batch in pairs(batchesByTexture) do
        batch.count = 0
    end
    flushed3D = false  -- Reset flush flag for new frame

    -- Set render target with depth buffer
    love.graphics.setCanvas({canvas, depthstencil = depthCanvas})
    love.graphics.clear(clearColor[1], clearColor[2], clearColor[3], 1, true, 1)
    love.graphics.setDepthMode("lequal", true)
end

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

-- Set clear color (also syncs fog color for seamless fade)
function renderer_gpu.setClearColor(r, g, b)
    clearColor[1] = (r or 162) / 255
    clearColor[2] = (g or 136) / 255
    clearColor[3] = (b or 121) / 255
    -- Sync fog color with clear color
    fogColor[1] = clearColor[1]
    fogColor[2] = clearColor[2]
    fogColor[3] = clearColor[3]
end

-- Toggle dithering
function renderer_gpu.toggleDither()
    ditherEnabled = not ditherEnabled
    return ditherEnabled
end

function renderer_gpu.isDitherEnabled()
    return ditherEnabled
end

-- Set matrices for 3D rendering (separate matrices like g3d)
function renderer_gpu.setMatrices(projMatrix, viewMatrix, cameraPos)
    currentProjectionMatrix = projMatrix
    currentViewMatrix = viewMatrix
    currentCamera = cameraPos
    -- Default model matrix is identity
    currentModelMatrix = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}
end

-- Set model matrix for current object (optional, defaults to identity)
function renderer_gpu.setModelMatrix(modelMatrix)
    currentModelMatrix = modelMatrix
end

-- Get or create batch for a texture
local function getBatch(image)
    local batch = batchesByTexture[image]
    if not batch then
        batch = {vertices = {}, count = 0}
        batchesByTexture[image] = batch
    end
    return batch
end

-- Get or create image from texData
local function getImage(texData)
    local texType = texData:type()
    if texType == "Image" then
        return texData
    elseif texType == "ImageData" then
        local image = imageCache[texData]
        if not image then
            image = love.graphics.newImage(texData)
            image:setFilter("nearest", "nearest")
            imageCache[texData] = image
        end
        return image
    else
        error("Invalid texture data type: " .. tostring(texType))
    end
end

-- Add triangle vertices to batch (world space - GPU will transform)
local function addTriangleToBatch(batch, v1, v2, v3, bright)
    local verts = batch.vertices
    local idx = batch.count * 3

    -- Store world-space positions with w=1.0 for proper matrix math
    -- Format: {x, y, z, w, u, v, r, g, b, a}
    verts[idx + 1] = {v1.pos[1], v1.pos[2], v1.pos[3], 1.0, v1.uv[1], v1.uv[2], 1, 1, 1, bright}
    verts[idx + 2] = {v2.pos[1], v2.pos[2], v2.pos[3], 1.0, v2.uv[1], v2.uv[2], 1, 1, 1, bright}
    verts[idx + 3] = {v3.pos[1], v3.pos[2], v3.pos[3], 1.0, v3.uv[1], v3.uv[2], 1, 1, 1, bright}
    batch.count = batch.count + 1
end

-- Draw a single 3D triangle (adds to batch)
function renderer_gpu.drawTriangle3D(v1, v2, v3, texture, texData, brightness, fogFactor)
    if not currentProjectionMatrix then
        error("Must call renderer_gpu.setMatrices() before drawTriangle3D()")
    end

    local image = getImage(texData)
    local batch = getBatch(image)
    local bright = brightness or 1.0

    addTriangleToBatch(batch, v1, v2, v3, bright)
    stats.trianglesDrawn = stats.trianglesDrawn + 1
end

-- Batch draw triangles (for terrain etc)
function renderer_gpu.drawTriangleBatch(triangles, texData, brightness)
    if not currentProjectionMatrix then
        error("Must call renderer_gpu.setMatrices() before drawTriangleBatch()")
    end
    if #triangles == 0 then return end

    local image = getImage(texData)
    local batch = getBatch(image)
    local bright = brightness or 1.0

    for _, tri in ipairs(triangles) do
        addTriangleToBatch(batch, tri[1], tri[2], tri[3], bright)
        stats.trianglesDrawn = stats.trianglesDrawn + 1
    end
end

-- Draw a 3D line (uses CPU transform since lines are few)
function renderer_gpu.drawLine3D(p0, p1, r, g, b, skipZBuffer)
    if not currentProjectionMatrix then
        error("Must call renderer_gpu.setMatrices() before drawLine3D()")
    end

    -- For lines, compute MVP on CPU (there are few lines)
    local proj = currentProjectionMatrix
    local view = currentViewMatrix
    -- Multiply view * point, then proj * result
    local function transformPoint(p)
        -- Apply view matrix
        local vx = view[1]*p[1] + view[2]*p[2] + view[3]*p[3] + view[4]
        local vy = view[5]*p[1] + view[6]*p[2] + view[7]*p[3] + view[8]
        local vz = view[9]*p[1] + view[10]*p[2] + view[11]*p[3] + view[12]
        local vw = view[13]*p[1] + view[14]*p[2] + view[15]*p[3] + view[16]
        -- Apply projection matrix
        local cx = proj[1]*vx + proj[2]*vy + proj[3]*vz + proj[4]*vw
        local cy = proj[5]*vx + proj[6]*vy + proj[7]*vz + proj[8]*vw
        local cw = proj[13]*vx + proj[14]*vy + proj[15]*vz + proj[16]*vw
        return cx, cy, cw
    end

    local c0x, c0y, c0w = transformPoint(p0)
    local c1x, c1y, c1w = transformPoint(p1)

    if c0w <= 0.1 and c1w <= 0.1 then return end

    local halfW = RENDER_WIDTH * 0.5
    local halfH = RENDER_HEIGHT * 0.5
    local invW0 = 1 / math.max(c0w, 0.1)
    local invW1 = 1 / math.max(c1w, 0.1)

    local s0x = (c0x * invW0 + 1) * halfW
    local s0y = (1 - c0y * invW0) * halfH
    local s1x = (c1x * invW1 + 1) * halfW
    local s1y = (1 - c1y * invW1) * halfH

    -- skipZBuffer=true: draw without depth testing (always behind 3D geometry, for menu background)
    -- skipZBuffer=false: draw with depth testing enabled (for in-game speed lines)
    if skipZBuffer then
        love.graphics.setDepthMode()  -- Disable depth test and write
    else
        -- Keep depth testing enabled - line will be occluded by closer objects
        -- (depth mode should already be "lequal", true from clearBuffers)
    end

    -- Disable line smoothing for crisp pixel-perfect lines (no black outlines)
    love.graphics.setLineStyle("rough")
    love.graphics.setColor(r/255, g/255, b/255, 1)
    love.graphics.line(s0x, s0y, s1x, s1y)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineStyle("smooth")

    if skipZBuffer then
        love.graphics.setDepthMode("lequal", true)  -- Re-enable depth testing
    end
end

-- 2D drawing functions (unchanged)
function renderer_gpu.drawLine2D(x0, y0, x1, y1, r, g, b)
    love.graphics.setDepthMode()
    love.graphics.setColor(r/255, g/255, b/255, 1)
    love.graphics.line(x0, y0, x1, y1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setDepthMode("lequal", true)
end

function renderer_gpu.drawPixel(x, y, r, g, b)
    love.graphics.setDepthMode()
    love.graphics.setColor(r/255, g/255, b/255, 1)
    love.graphics.points(math.floor(x) + 0.5, math.floor(y) + 0.5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setDepthMode("lequal", true)
end

function renderer_gpu.drawRectFill(x1, y1, x2, y2, r, g, b, alpha)
    love.graphics.setDepthMode()
    love.graphics.setColor(r/255, g/255, b/255, (alpha or 255)/255)
    love.graphics.rectangle("fill", x1, y1, x2 - x1, y2 - y1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setDepthMode("lequal", true)
end

function renderer_gpu.drawRect(x1, y1, x2, y2, r, g, b)
    love.graphics.setDepthMode()
    love.graphics.setColor(r/255, g/255, b/255, 1)
    love.graphics.rectangle("line", x1, y1, x2 - x1, y2 - y1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setDepthMode("lequal", true)
end

function renderer_gpu.drawCircleFill(cx, cy, radius, r, g, b)
    love.graphics.setDepthMode()
    love.graphics.setColor(r/255, g/255, b/255, 1)
    love.graphics.circle("fill", cx, cy, radius)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setDepthMode("lequal", true)
end

function renderer_gpu.drawCircle(cx, cy, radius, r, g, b)
    love.graphics.setDepthMode()
    love.graphics.setColor(r/255, g/255, b/255, 1)
    love.graphics.circle("line", cx, cy, radius)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setDepthMode("lequal", true)
end

-- Bitmap font
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
                love.graphics.rectangle("fill", math.floor(x + col * scale), math.floor(y + row * scale), scale, scale)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
    return 5 * scale
end

function renderer_gpu.drawText(x, y, text, r, g, b, scale, shadow)
    love.graphics.setDepthMode()
    scale = scale or 1
    if shadow == nil then shadow = true end
    x = math.floor(x)
    y = math.floor(y)
    if shadow then
        local cursorX = x + scale
        for i = 1, #text do
            cursorX = cursorX + drawCharGPU(text:sub(i,i), cursorX, y + scale, 0, 0, 0, scale)
        end
    end
    local cursorX = x
    for i = 1, #text do
        cursorX = cursorX + drawCharGPU(text:sub(i,i), cursorX, y, r, g, b, scale)
    end
    love.graphics.setDepthMode("lequal", true)
    return cursorX - x
end

function renderer_gpu.getCanvas()
    return canvas
end

-- Flush sky triangles using sky shader (no fog, no depth test)
function renderer_gpu.flushSky()
    -- Disable depth test - sky draws behind everything
    love.graphics.setDepthMode()

    -- Set up sky shader (no fog)
    love.graphics.setShader(shaderSky)

    -- Send matrices to shader
    if currentProjectionMatrix and currentViewMatrix and currentModelMatrix then
        shaderSky:send("projectionMatrix", currentProjectionMatrix)
        shaderSky:send("viewMatrix", currentViewMatrix)
        shaderSky:send("modelMatrix", currentModelMatrix)
    end

    shaderSky:send("isCanvasEnabled", love.graphics.getCanvas() ~= nil)

    -- Draw all batched triangles with sky shader
    for image, batch in pairs(batchesByTexture) do
        if batch.count > 0 then
            local vertCount = batch.count * 3

            batchMesh:setVertices(batch.vertices, 1, vertCount)
            batchMesh:setTexture(image)
            batchMesh:setDrawRange(1, vertCount)

            local texW, texH = image:getDimensions()
            shaderSky:send("u_textureSize", {texW, texH})

            love.graphics.draw(batchMesh)

            stats.drawCalls = stats.drawCalls + 1
        end
    end

    love.graphics.setShader()

    -- Restore depth test for other geometry
    love.graphics.setDepthMode("lequal", true)

    -- Clear batches after drawing sky
    for _, batch in pairs(batchesByTexture) do
        batch.count = 0
    end
end

-- Flush all batched 3D triangles to canvas (without presenting to screen)
-- Call this before drawing 2D UI so UI appears on top
function renderer_gpu.flush3D()
    local t0 = love.timer.getTime()

    -- Set up 3D shader with separate matrices (like g3d)
    love.graphics.setShader(shader3D)

    -- Send matrices to shader (they're already in the correct format)
    if currentProjectionMatrix and currentViewMatrix and currentModelMatrix then
        shader3D:send("projectionMatrix", currentProjectionMatrix)
        shader3D:send("viewMatrix", currentViewMatrix)
        shader3D:send("modelMatrix", currentModelMatrix)
    else
        print("WARNING: Matrices not set!")
    end

    shader3D:send("u_ditherEnabled", ditherEnabled)
    shader3D:send("isCanvasEnabled", love.graphics.getCanvas() ~= nil)

    -- Send fog uniforms
    shader3D:send("u_fogEnabled", fogEnabled and 1.0 or 0.0)
    shader3D:send("u_fogNear", fogNear)
    shader3D:send("u_fogFar", fogFar)
    shader3D:send("u_fogColor", fogColor)

    -- Draw all batched triangles
    for image, batch in pairs(batchesByTexture) do
        if batch.count > 0 then
            local vertCount = batch.count * 3

            -- Update mesh vertices
            batchMesh:setVertices(batch.vertices, 1, vertCount)
            batchMesh:setTexture(image)
            batchMesh:setDrawRange(1, vertCount)

            -- Set texture size for shader
            local texW, texH = image:getDimensions()
            shader3D:send("u_textureSize", {texW, texH})

            -- Draw!
            love.graphics.draw(batchMesh)

            stats.drawCalls = stats.drawCalls + 1
            stats.batchCount = stats.batchCount + 1
        end
    end

    love.graphics.setShader()
    love.graphics.setDepthMode()  -- Disable depth for subsequent 2D drawing
    stats.timeRasterize = stats.timeRasterize + (love.timer.getTime() - t0)
    flushed3D = true
end

-- Present canvas to screen (call after flush3D and any 2D UI drawing)
function renderer_gpu.present()
    -- Flush 3D if not already done
    if not flushed3D then
        renderer_gpu.flush3D()
    end

    -- Present to screen
    love.graphics.setCanvas()
    love.graphics.setDepthMode()
    love.graphics.setColor(1, 1, 1, 1)

    local scaleX = love.graphics.getWidth() / RENDER_WIDTH
    local scaleY = love.graphics.getHeight() / RENDER_HEIGHT
    local scale = math.min(scaleX, scaleY)
    local offsetX = (love.graphics.getWidth() - RENDER_WIDTH * scale) / 2
    local offsetY = (love.graphics.getHeight() - RENDER_HEIGHT * scale) / 2

    love.graphics.draw(canvas, offsetX, offsetY, 0, scale, scale)
end

-- Compatibility functions
function renderer_gpu.getImageData()
    return nil
end

function renderer_gpu.clearTextureCache()
end

function renderer_gpu.calcFogFactor(distance)
    if not fogEnabled or distance <= fogNear then
        return 0
    end
    local factor = (distance - fogNear) / (fogFar - fogNear)
    return math.max(0, math.min(1, factor))
end

return renderer_gpu
