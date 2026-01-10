-- GPU-based Renderer using LÖVE shaders
-- GPU-side MVP transformation for maximum performance
-- Features: Dithered fog, nearest-neighbor texturing, pixel-perfect lines

local config = require("config")
local fonts = require("fonts")
local Palette = require("game.palette")

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
local shaderTerrain = nil  -- Terrain shader with height-based texture blending
local shaderShadow = nil  -- Shadow shader with dithered transparency

-- Terrain textures for shader
local terrainTextures = {
    ground = nil,
    grass = nil,
    rocks = nil
}

-- Terrain batch (separate from regular batches)
local terrainBatch = {vertices = {}, count = 0}

-- Shadow batch (projected ground shadows) - DEPRECATED, kept for compatibility
local shadowBatch = {vertices = {}, count = 0}

-- Cascaded Shadow map state (new shadow system with 2 cascades)
-- Near cascade (high detail, close range)
local shadowMapTextureNear = nil
local shadowMapLightViewMatrixNear = nil
local shadowMapLightProjMatrixNear = nil
-- Far cascade (lower detail, wide range)
local shadowMapTextureFar = nil
local shadowMapLightViewMatrixFar = nil
local shadowMapLightProjMatrixFar = nil
-- Cascade settings
local shadowCascadeSplit = 25  -- Distance where we switch from near to far cascade
local shadowMapEnabled = false
local shadowDebugEnabled = false  -- F4 toggle for debug visualization
-- Legacy single-texture references (kept for compatibility)
local shadowMapTexture = nil
local shadowMapLightViewMatrix = nil
local shadowMapLightProjMatrix = nil

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

-- Palette shadow lookup texture (32x8: 32 colors × 8 shadow levels)
local paletteShadowTexture = nil

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

-- Create palette shadow lookup texture
-- Returns a 32x8 texture where each pixel (x,y) contains the RGB color
-- for palette index x at shadow level y
local function createPaletteShadowTexture()
    print("Creating palette shadow lookup texture...")
    local width = 32   -- 32 palette colors
    local height = 8   -- 8 shadow levels

    -- Try to load from file first
    local filename = "assets/palette_shadow_lookup.png"
    if love.filesystem.getInfo(filename) then
        print("Loading palette shadow lookup from " .. filename)
        local texture = love.graphics.newImage(filename)
        texture:setFilter("nearest", "nearest")
        texture:setWrap("clamp", "clamp")
        return texture
    end

    -- Generate if not found
    print("Generating palette shadow lookup texture...")
    local imageData = love.image.newImageData(width, height)

    -- Fill with palette shadow colors
    for paletteIndex = 0, 31 do
        for shadowLevel = 0, 7 do
            -- Get the shadow color for this palette index at this level
            local shadowIndex = Palette.getShadowLevel(paletteIndex, shadowLevel)
            local rgb = Palette.getColor(shadowIndex)

            -- Set pixel (x=paletteIndex, y=shadowLevel)
            imageData:setPixel(paletteIndex, shadowLevel, rgb[1]/255, rgb[2]/255, rgb[3]/255, 1.0)
        end
    end

    -- Try to save as PNG for debugging (in save directory)
    local saveOk, saveErr = pcall(function()
        imageData:encode("png", filename)
    end)
    if saveOk then
        print("Palette shadow lookup texture saved to " .. filename)
    else
        print("Note: Could not save to " .. filename .. " - " .. tostring(saveErr))
    end

    -- Create texture from ImageData
    local texture = love.graphics.newImage(imageData)
    texture:setFilter("nearest", "nearest")  -- No interpolation for lookup table
    texture:setWrap("clamp", "clamp")       -- Clamp to edges

    print("Palette shadow lookup texture created: " .. width .. "x" .. height)
    return texture
end

-- Initialize the renderer
function renderer_gpu.init(width, height)
    RENDER_WIDTH = width or RENDER_WIDTH
    RENDER_HEIGHT = height or RENDER_HEIGHT

    -- Create low-res render target
    canvas = love.graphics.newCanvas(RENDER_WIDTH, RENDER_HEIGHT, {format = "rgba8", readable = true})
    canvas:setFilter("nearest", "nearest")

    -- Create depth buffer
    depthCanvas = love.graphics.newCanvas(RENDER_WIDTH, RENDER_HEIGHT, {format = "depth24", readable = false})

    -- Create palette shadow lookup texture
    paletteShadowTexture = createPaletteShadowTexture()

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

    -- Load terrain shader (height-based texture blending)
    local shaderTerrainCode = love.filesystem.read(shaderPath .. "terrain.glsl")
    if shaderTerrainCode then
        local ok, shaderOrErr = pcall(love.graphics.newShader, shaderTerrainCode)
        if ok then
            shaderTerrain = shaderOrErr
            print("Terrain shader compiled successfully")
        else
            print("Terrain shader compilation error: " .. tostring(shaderOrErr))
            -- Fall back to 3D shader if terrain shader fails
            shaderTerrain = shader3D
        end
    else
        print("Could not load terrain.glsl shader, using 3D shader")
        shaderTerrain = shader3D
    end

    -- Load shadow shader (dithered ground shadows)
    local shaderShadowCode = love.filesystem.read(shaderPath .. "shadow.glsl")
    if shaderShadowCode then
        local ok, shaderOrErr = pcall(love.graphics.newShader, shaderShadowCode)
        if ok then
            shaderShadow = shaderOrErr
            print("Shadow shader compiled successfully")
        else
            print("Shadow shader compilation error: " .. tostring(shaderOrErr))
            -- Shadows will be disabled if shader fails
            shaderShadow = nil
        end
    else
        print("Could not load shadow.glsl shader, shadows disabled")
        shaderShadow = nil
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
    terrainBatch.count = 0  -- Clear terrain batch
    shadowBatch.count = 0   -- Clear shadow batch
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
local function addTriangleToBatch(batch, v1, v2, v3, bright, alpha)
    local verts = batch.vertices
    local idx = batch.count * 3
    local a = alpha or 1.0

    -- Store world-space positions with w=1.0 for proper matrix math
    -- Format: {x, y, z, w, u, v, r, g, b, a}
    -- Brightness goes in RGB, alpha for transparency
    verts[idx + 1] = {v1.pos[1], v1.pos[2], v1.pos[3], 1.0, v1.uv[1], v1.uv[2], bright, bright, bright, a}
    verts[idx + 2] = {v2.pos[1], v2.pos[2], v2.pos[3], 1.0, v2.uv[1], v2.uv[2], bright, bright, bright, a}
    verts[idx + 3] = {v3.pos[1], v3.pos[2], v3.pos[3], 1.0, v3.uv[1], v3.uv[2], bright, bright, bright, a}
    batch.count = batch.count + 1
end

-- Add triangle with per-vertex brightness (Gouraud shading)
local function addTriangleToBatchGouraud(batch, v1, v2, v3, b1, b2, b3)
    local verts = batch.vertices
    local idx = batch.count * 3

    -- Store world-space positions with per-vertex brightness
    -- Format: {x, y, z, w, u, v, r, g, b, a}
    verts[idx + 1] = {v1.pos[1], v1.pos[2], v1.pos[3], 1.0, v1.uv[1], v1.uv[2], b1, b1, b1, 1.0}
    verts[idx + 2] = {v2.pos[1], v2.pos[2], v2.pos[3], 1.0, v2.uv[1], v2.uv[2], b2, b2, b2, 1.0}
    verts[idx + 3] = {v3.pos[1], v3.pos[2], v3.pos[3], 1.0, v3.uv[1], v3.uv[2], b3, b3, b3, 1.0}
    batch.count = batch.count + 1
end

-- Draw a single 3D triangle (adds to batch)
-- brightness: lighting intensity (0-1), default 1.0
-- alpha: transparency (0-1), default 1.0 (opaque)
function renderer_gpu.drawTriangle3D(v1, v2, v3, texture, texData, brightness, alpha)
    if not currentProjectionMatrix then
        error("Must call renderer_gpu.setMatrices() before drawTriangle3D()")
    end

    local image = getImage(texData)
    local batch = getBatch(image)
    local bright = brightness or 1.0

    addTriangleToBatch(batch, v1, v2, v3, bright, alpha)
    stats.trianglesDrawn = stats.trianglesDrawn + 1
end

-- Draw a single 3D triangle with per-vertex brightness (Gouraud shading)
-- b1, b2, b3 are brightness values for each vertex (0-1)
function renderer_gpu.drawTriangle3DGouraud(v1, v2, v3, texData, b1, b2, b3)
    if not currentProjectionMatrix then
        error("Must call renderer_gpu.setMatrices() before drawTriangle3DGouraud()")
    end

    local image = getImage(texData)
    local batch = getBatch(image)

    addTriangleToBatchGouraud(batch, v1, v2, v3, b1, b2, b3)
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

-- White 1x1 texture for solid color geometry
local whiteTexData = nil
local whiteImage = nil

local function getWhiteTexture()
    if not whiteTexData then
        whiteTexData = love.image.newImageData(1, 1)
        whiteTexData:setPixel(0, 0, 1, 1, 1, 1)
        whiteImage = love.graphics.newImage(whiteTexData)
        whiteImage:setFilter("nearest", "nearest")
    end
    return whiteTexData, whiteImage
end

-- Add a colored triangle to the batch (for solid color geometry like rain)
local function addColoredTriangleToBatch(batch, p1, p2, p3, r, g, b)
    local verts = batch.vertices
    local idx = batch.count * 3

    -- Normalize color to 0-1 range
    local nr, ng, nb = r/255, g/255, b/255

    -- Format: {x, y, z, w, u, v, r, g, b, a}
    verts[idx + 1] = {p1[1], p1[2], p1[3], 1.0, 0.5, 0.5, nr, ng, nb, 1.0}
    verts[idx + 2] = {p2[1], p2[2], p2[3], 1.0, 0.5, 0.5, nr, ng, nb, 1.0}
    verts[idx + 3] = {p3[1], p3[2], p3[3], 1.0, 0.5, 0.5, nr, ng, nb, 1.0}
    batch.count = batch.count + 1
end

-- Draw a 3D line as a thin quad (depth tested, goes through normal 3D pipeline)
-- This draws BEFORE flush3D, so it will be properly occluded by geometry
function renderer_gpu.drawLine3DDepth(p0, p1, r, g, b, thickness)
    if not currentProjectionMatrix then
        error("Must call renderer_gpu.setMatrices() before drawLine3DDepth()")
    end

    thickness = thickness or 0.02  -- Default thin line

    -- Get the white texture for solid color
    local texData, image = getWhiteTexture()

    -- Get or create batch for white texture
    if not batchesByTexture[image] then
        batchesByTexture[image] = {vertices = {}, count = 0}
    end
    local batch = batchesByTexture[image]

    -- Calculate perpendicular vector for line thickness
    -- Use camera position to make the quad face the camera (billboard-ish)
    local dx = p1[1] - p0[1]
    local dy = p1[2] - p0[2]
    local dz = p1[3] - p0[3]

    -- Get vector from camera to line midpoint
    local midX = (p0[1] + p1[1]) * 0.5
    local midY = (p0[2] + p1[2]) * 0.5
    local midZ = (p0[3] + p1[3]) * 0.5

    local camX = currentCamera and currentCamera.x or 0
    local camY = currentCamera and currentCamera.y or 0
    local camZ = currentCamera and currentCamera.z or 0

    local toCamera = {midX - camX, midY - camY, midZ - camZ}

    -- Cross product of line direction and camera direction gives perpendicular
    local perpX = dy * toCamera[3] - dz * toCamera[2]
    local perpY = dz * toCamera[1] - dx * toCamera[3]
    local perpZ = dx * toCamera[2] - dy * toCamera[1]

    -- Normalize and scale by thickness
    local perpLen = math.sqrt(perpX * perpX + perpY * perpY + perpZ * perpZ)
    if perpLen < 0.0001 then
        -- Line points directly at camera, use arbitrary perpendicular
        perpX, perpY, perpZ = thickness, 0, 0
    else
        local scale = thickness / perpLen
        perpX, perpY, perpZ = perpX * scale, perpY * scale, perpZ * scale
    end

    -- Create quad vertices (two triangles)
    local v0 = {p0[1] - perpX, p0[2] - perpY, p0[3] - perpZ}
    local v1 = {p0[1] + perpX, p0[2] + perpY, p0[3] + perpZ}
    local v2 = {p1[1] + perpX, p1[2] + perpY, p1[3] + perpZ}
    local v3 = {p1[1] - perpX, p1[2] - perpY, p1[3] - perpZ}

    -- Add two triangles for the quad
    addColoredTriangleToBatch(batch, v0, v1, v2, r, g, b)
    addColoredTriangleToBatch(batch, v0, v2, v3, r, g, b)
    stats.trianglesDrawn = stats.trianglesDrawn + 2
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

-- Text queue for deferred rendering (drawn after canvas scaling for crisp text)
local textQueue = {}

-- Queue text for deferred rendering
function renderer_gpu.drawText(x, y, text, r, g, b, scale, shadow)
    scale = scale or 1
    if shadow == nil then shadow = true end

    table.insert(textQueue, {
        x = math.floor(x),
        y = math.floor(y),
        text = text,
        r = r,
        g = g,
        b = b,
        scale = scale,
        shadow = shadow
    })

    -- Return approximate width (based on render resolution font)
    local font = fonts.get(8 * scale)
    return font:getWidth(text)
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

    -- Send fog uniforms (with pcall to skip if optimized out)
    pcall(function() shader3D:send("u_fogEnabled", fogEnabled and 1.0 or 0.0) end)
    pcall(function() shader3D:send("u_fogNear", fogNear) end)
    pcall(function() shader3D:send("u_fogFar", fogFar) end)
    pcall(function() shader3D:send("u_fogColor", fogColor) end)

    -- Send palette-based shadow uniforms (if enabled)
    if config.USE_PALETTE_SHADOWS then
        renderer_gpu.sendPaletteUniforms(shader3D)
        pcall(function() shader3D:send("u_ditherPaletteShadows", config.DITHER_PALETTE_SHADOWS and 1.0 or 0.0) end)
        pcall(function() shader3D:send("u_shadowBrightnessMin", config.SHADOW_BRIGHTNESS_MIN or 0.3) end)
        pcall(function() shader3D:send("u_shadowBrightnessMax", config.SHADOW_BRIGHTNESS_MAX or 0.95) end)
        pcall(function() shader3D:send("u_shadowDitherRange", config.SHADOW_DITHER_RANGE or 0.5) end)
    end
    pcall(function() shader3D:send("u_usePaletteShadows", config.USE_PALETTE_SHADOWS and 1.0 or 0.0) end)

    -- Enable backface culling (use "front" because shader Y-flip reverses winding order)
    love.graphics.setMeshCullMode("front")

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

    love.graphics.setMeshCullMode("none")  -- Disable culling for 2D
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

    -- Draw queued text at screen resolution (crisp, not scaled with canvas)
    local prevFont = love.graphics.getFont()
    for _, t in ipairs(textQueue) do
        -- Scale font size to match screen scale (font scale * canvas scale)
        local fontSize = math.max(8, math.floor(8 * t.scale * scale))
        local font = fonts.get(fontSize)
        love.graphics.setFont(font)

        -- Convert render coords to screen coords
        local screenX = offsetX + t.x * scale
        local screenY = offsetY + t.y * scale

        if t.shadow then
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.print(t.text, screenX + scale, screenY + scale)
        end

        love.graphics.setColor(t.r/255, t.g/255, t.b/255, 1)
        love.graphics.print(t.text, screenX, screenY)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(prevFont)

    -- Clear text queue for next frame
    textQueue = {}
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

-- Set terrain textures for shader-based blending
function renderer_gpu.setTerrainTextures(groundTex, grassTex, rocksTex)
    terrainTextures.ground = getImage(groundTex)
    terrainTextures.grass = getImage(grassTex)
    terrainTextures.rocks = getImage(rocksTex)
end

-- Add a terrain triangle with per-vertex height data
-- Height is passed via vertex color alpha (scaled to 0-1 for 0-32 range)
function renderer_gpu.drawTerrainTriangle(v1, v2, v3, h1, h2, h3, brightness)
    if not currentProjectionMatrix then
        error("Must call renderer_gpu.setMatrices() before drawTerrainTriangle()")
    end

    local verts = terrainBatch.vertices
    local idx = terrainBatch.count * 3
    local bright = brightness or 1.0

    -- Height is stored in alpha channel, scaled from 0-32 to 0-1
    local a1 = h1 / 32.0
    local a2 = h2 / 32.0
    local a3 = h3 / 32.0

    -- Format: {x, y, z, w, u, v, r, g, b, a}
    verts[idx + 1] = {v1.pos[1], v1.pos[2], v1.pos[3], 1.0, v1.uv[1], v1.uv[2], bright, bright, bright, a1}
    verts[idx + 2] = {v2.pos[1], v2.pos[2], v2.pos[3], 1.0, v2.uv[1], v2.uv[2], bright, bright, bright, a2}
    verts[idx + 3] = {v3.pos[1], v3.pos[2], v3.pos[3], 1.0, v3.uv[1], v3.uv[2], bright, bright, bright, a3}
    terrainBatch.count = terrainBatch.count + 1
    stats.trianglesDrawn = stats.trianglesDrawn + 1
end

-- Flush terrain triangles using terrain shader with multi-texture blending
function renderer_gpu.flushTerrain()
    if terrainBatch.count == 0 then return end
    if not terrainTextures.ground or not terrainTextures.grass or not terrainTextures.rocks then
        print("Warning: Terrain textures not set, skipping terrain flush")
        return
    end

    -- Set up terrain shader
    love.graphics.setShader(shaderTerrain)

    -- Send matrices to shader
    if currentProjectionMatrix and currentViewMatrix and currentModelMatrix then
        shaderTerrain:send("projectionMatrix", currentProjectionMatrix)
        shaderTerrain:send("viewMatrix", currentViewMatrix)
        shaderTerrain:send("modelMatrix", currentModelMatrix)
    end

    -- Send terrain textures
    shaderTerrain:send("u_texGround", terrainTextures.ground)
    shaderTerrain:send("u_texGrass", terrainTextures.grass)
    shaderTerrain:send("u_texRocks", terrainTextures.rocks)

    -- Texture size (assuming all terrain textures are same size)
    local texW, texH = terrainTextures.ground:getDimensions()
    shaderTerrain:send("u_textureSize", {texW, texH})

    -- Height thresholds from config
    shaderTerrain:send("u_groundToGrass", config.TERRAIN_GROUND_TO_GRASS or 3.0)
    shaderTerrain:send("u_grassToRocks", config.TERRAIN_GRASS_TO_ROCKS or 10.0)
    shaderTerrain:send("u_groundGrassBlend", config.TERRAIN_GROUND_GRASS_BLEND or 2.0)
    shaderTerrain:send("u_grassRocksBlend", config.TERRAIN_GRASS_ROCKS_BLEND or 4.0)

    -- Fog settings
    shaderTerrain:send("u_fogEnabled", fogEnabled and 1.0 or 0.0)
    shaderTerrain:send("u_fogNear", fogNear)
    shaderTerrain:send("u_fogFar", fogFar)
    shaderTerrain:send("u_fogColor", fogColor)

    -- Palette shadow uniforms
    shaderTerrain:send("u_usePaletteShadows", config.USE_PALETTE_SHADOWS and 1.0 or 0.0)
    shaderTerrain:send("u_ditherPaletteShadows", config.DITHER_PALETTE_SHADOWS and 1.0 or 0.0)
    shaderTerrain:send("u_shadowBrightnessMin", config.SHADOW_BRIGHTNESS_MIN or 0.3)
    shaderTerrain:send("u_shadowBrightnessMax", config.SHADOW_BRIGHTNESS_MAX or 0.95)
    shaderTerrain:send("u_shadowDitherRange", config.SHADOW_DITHER_RANGE or 0.5)
    if paletteShadowTexture then
        shaderTerrain:send("u_paletteShadowLookup", paletteShadowTexture)
    end

    -- Send shadow map uniforms
    renderer_gpu.sendShadowMapUniforms(shaderTerrain)

    -- Enable backface culling for terrain (use "front" because shader Y-flip reverses winding order)
    love.graphics.setMeshCullMode("front")

    -- Draw terrain batch
    local vertCount = terrainBatch.count * 3
    batchMesh:setVertices(terrainBatch.vertices, 1, vertCount)
    batchMesh:setTexture(terrainTextures.ground)  -- Base texture for mesh, shader will sample all 3
    batchMesh:setDrawRange(1, vertCount)

    love.graphics.draw(batchMesh)

    stats.drawCalls = stats.drawCalls + 1
    stats.batchCount = stats.batchCount + 1

    love.graphics.setMeshCullMode("none")
    love.graphics.setShader()

    -- Clear terrain batch for next frame
    terrainBatch.count = 0
end

-- Add a shadow triangle to the shadow batch
-- v1, v2, v3 are {x, y, z} world positions
function renderer_gpu.drawShadowTriangle(v1, v2, v3)
    if not shaderShadow then return end  -- Shadows disabled if shader failed to load

    local verts = shadowBatch.vertices
    local idx = shadowBatch.count * 3

    -- Shadow vertices: position only, no UV needed (solid color shader)
    -- Format: {x, y, z, w, u, v, r, g, b, a}
    verts[idx + 1] = {v1[1], v1[2], v1[3], 1.0, 0, 0, 1, 1, 1, 1}
    verts[idx + 2] = {v2[1], v2[2], v2[3], 1.0, 0, 0, 1, 1, 1, 1}
    verts[idx + 3] = {v3[1], v3[2], v3[3], 1.0, 0, 0, 1, 1, 1, 1}
    shadowBatch.count = shadowBatch.count + 1
end

-- Flush all shadow triangles to the canvas
-- Call AFTER flushTerrain but BEFORE drawing objects
-- Uses stencil buffer to prevent shadow stacking (overlapping shadows merge instead of darken)
function renderer_gpu.flushShadows()
    if shadowBatch.count == 0 then
        return
    end
    if not shaderShadow then
        return
    end

    -- Set up shadow shader
    love.graphics.setShader(shaderShadow)

    -- Send matrices to shader
    if currentProjectionMatrix and currentViewMatrix then
        shaderShadow:send("projectionMatrix", currentProjectionMatrix)
        shaderShadow:send("viewMatrix", currentViewMatrix)
        shaderShadow:send("modelMatrix", {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1})  -- Identity
    end

    -- Send shadow uniforms
    -- SHADOW_DARKNESS: 0.0 = completely black, 1.0 = no change
    -- A value like 0.5 means the surface will be darkened to 50% brightness
    local shadowDarkness = config.SHADOW_DARKNESS or 0.5
    shaderShadow:send("u_shadowDarkness", shadowDarkness)

    -- Send fog uniforms (shadows fade with fog)
    shaderShadow:send("u_fogEnabled", fogEnabled and 1.0 or 0.0)
    shaderShadow:send("u_fogNear", fogNear)
    shaderShadow:send("u_fogFar", fogFar)

    -- Depth test ON but depth write OFF (shadows appear on terrain, don't occlude objects)
    love.graphics.setDepthMode("lequal", false)

    -- Disable backface culling for shadows (projected geometry can have flipped winding)
    love.graphics.setMeshCullMode("none")

    -- Use multiplicative blending to darken the surface underneath
    -- This preserves the surface color while making it darker
    love.graphics.setBlendMode("multiply", "premultiplied")

    -- Prepare the mesh for drawing
    local vertCount = shadowBatch.count * 3
    batchMesh:setVertices(shadowBatch.vertices, 1, vertCount)
    batchMesh:setTexture(nil)  -- No texture needed
    batchMesh:setDrawRange(1, vertCount)

    -- Draw shadows (simple approach without stencil for now)
    -- Note: overlapping shadows will stack/darken more
    love.graphics.draw(batchMesh)

    stats.drawCalls = stats.drawCalls + 1

    -- Restore normal blend mode, depth write for subsequent geometry
    love.graphics.setBlendMode("alpha")
    love.graphics.setDepthMode("lequal", true)
    love.graphics.setShader()

    -- Clear shadow batch
    shadowBatch.count = 0
end

-- Set cascaded shadow map data from ShadowMap module
function renderer_gpu.setShadowMapCascaded(nearTexture, nearViewMatrix, nearProjMatrix,
                                           farTexture, farViewMatrix, farProjMatrix, cascadeSplit)
    shadowMapTextureNear = nearTexture
    shadowMapLightViewMatrixNear = nearViewMatrix
    shadowMapLightProjMatrixNear = nearProjMatrix
    shadowMapTextureFar = farTexture
    shadowMapLightViewMatrixFar = farViewMatrix
    shadowMapLightProjMatrixFar = farProjMatrix
    shadowCascadeSplit = cascadeSplit or 25
    shadowMapEnabled = (nearTexture ~= nil and farTexture ~= nil)
    -- Legacy compatibility
    shadowMapTexture = farTexture
    shadowMapLightViewMatrix = farViewMatrix
    shadowMapLightProjMatrix = farProjMatrix
end

-- Legacy single shadow map setter (for compatibility)
function renderer_gpu.setShadowMap(texture, lightViewMatrix, lightProjMatrix)
    shadowMapTexture = texture
    shadowMapLightViewMatrix = lightViewMatrix
    shadowMapLightProjMatrix = lightProjMatrix
    -- Also set as far cascade for cascaded system
    shadowMapTextureFar = texture
    shadowMapLightViewMatrixFar = lightViewMatrix
    shadowMapLightProjMatrixFar = lightProjMatrix
    shadowMapEnabled = (texture ~= nil)
end

-- Clear shadow map (disable shadows)
function renderer_gpu.clearShadowMap()
    shadowMapTextureNear = nil
    shadowMapLightViewMatrixNear = nil
    shadowMapLightProjMatrixNear = nil
    shadowMapTextureFar = nil
    shadowMapLightViewMatrixFar = nil
    shadowMapLightProjMatrixFar = nil
    shadowMapTexture = nil
    shadowMapLightViewMatrix = nil
    shadowMapLightProjMatrix = nil
    shadowMapEnabled = false
end

-- Toggle shadow debug visualization (F4)
function renderer_gpu.toggleShadowDebug()
    shadowDebugEnabled = not shadowDebugEnabled
    return shadowDebugEnabled
end

-- Get shadow debug state
function renderer_gpu.isShadowDebugEnabled()
    return shadowDebugEnabled
end

-- Debug flag for shadow map
local shadowMapDebugPrinted = false

-- Send cascaded shadow map uniforms to a shader
function renderer_gpu.sendShadowMapUniforms(shader)
    if not shader then return end

    pcall(function()
        shader:send("u_shadowMapEnabled", shadowMapEnabled and 1.0 or 0.0)
    end)

    -- Always send debug flag
    pcall(function()
        shader:send("u_shadowDebug", shadowDebugEnabled and 1.0 or 0.0)
    end)

    -- Send cascade split distance
    pcall(function()
        shader:send("u_cascadeSplit", shadowCascadeSplit)
    end)

    if shadowMapEnabled then
        if not shadowMapDebugPrinted then
            print("Renderer: Sending cascaded shadow map uniforms")
            if shadowMapTextureNear then
                print("  Near cascade: " .. shadowMapTextureNear:getWidth() .. "x" .. shadowMapTextureNear:getHeight())
            end
            if shadowMapTextureFar then
                print("  Far cascade: " .. shadowMapTextureFar:getWidth() .. "x" .. shadowMapTextureFar:getHeight())
            end
            print("  Cascade split: " .. shadowCascadeSplit .. " units")
            shadowMapDebugPrinted = true
        end

        -- Near cascade uniforms
        if shadowMapTextureNear then
            pcall(function()
                shader:send("u_shadowMapNear", shadowMapTextureNear)
            end)
            pcall(function()
                shader:send("u_lightViewMatrixNear", shadowMapLightViewMatrixNear)
            end)
            pcall(function()
                shader:send("u_lightProjMatrixNear", shadowMapLightProjMatrixNear)
            end)
        end

        -- Far cascade uniforms
        if shadowMapTextureFar then
            pcall(function()
                shader:send("u_shadowMapFar", shadowMapTextureFar)
            end)
            pcall(function()
                shader:send("u_lightViewMatrixFar", shadowMapLightViewMatrixFar)
            end)
            pcall(function()
                shader:send("u_lightProjMatrixFar", shadowMapLightProjMatrixFar)
            end)
        end

        -- Legacy uniforms (for compatibility with non-cascaded shaders)
        if shadowMapTexture then
            pcall(function()
                shader:send("u_shadowMap", shadowMapTexture)
            end)
            pcall(function()
                shader:send("u_lightViewMatrix", shadowMapLightViewMatrix)
            end)
            pcall(function()
                shader:send("u_lightProjMatrix", shadowMapLightProjMatrix)
            end)
        end

        pcall(function()
            shader:send("u_shadowDarkness", config.SHADOW_DARKNESS or 0.5)
        end)
    end
end

-- Project a 3D world position to 2D screen coordinates
-- Matches exactly what the GPU shader does
-- Returns screen_x, screen_y, is_visible (behind camera check)
function renderer_gpu.worldToScreen(world_x, world_y, world_z)
    if not currentProjectionMatrix or not currentViewMatrix then
        return nil, nil, false
    end

    -- Step 1: viewPosition = viewMatrix * worldPosition
    -- mat4.multiplyVec4 does: result[row] = sum(m[row*4+col] * v[col])
    local view = currentViewMatrix
    local vx = view[1]*world_x + view[2]*world_y + view[3]*world_z + view[4]
    local vy = view[5]*world_x + view[6]*world_y + view[7]*world_z + view[8]
    local vz = view[9]*world_x + view[10]*world_y + view[11]*world_z + view[12]
    local vw = view[13]*world_x + view[14]*world_y + view[15]*world_z + view[16]

    -- Behind camera check (negative Z is in front in view space for right-handed coords)
    if vz >= 0 then
        return nil, nil, false
    end

    -- Step 2: screenPosition = projectionMatrix * viewPosition
    local proj = currentProjectionMatrix
    local sx = proj[1]*vx + proj[2]*vy + proj[3]*vz + proj[4]*vw
    local sy = proj[5]*vx + proj[6]*vy + proj[7]*vz + proj[8]*vw
    local sz = proj[9]*vx + proj[10]*vy + proj[11]*vz + proj[12]*vw
    local sw = proj[13]*vx + proj[14]*vy + proj[15]*vz + proj[16]*vw

    -- Step 3: Y flip (baked into projection matrix for canvas rendering)
    sy = -sy

    -- Step 4: Perspective divide (GPU does this automatically)
    if math.abs(sw) < 0.001 then
        return nil, nil, false
    end
    local ndc_x = sx / sw
    local ndc_y = sy / sw

    -- Step 5: Viewport transform (GPU does this: screen = (ndc + 1) * 0.5 * size)
    local screen_x = (ndc_x + 1) * 0.5 * RENDER_WIDTH
    local screen_y = (ndc_y + 1) * 0.5 * RENDER_HEIGHT

    return screen_x, screen_y, true
end

-- Draw a camera-facing billboard (quad that always faces camera)
-- Uses the main 3D batch so it's depth tested with other geometry
function renderer_gpu.drawBillboard(x, y, z, size, texData)
    if not currentViewMatrix then return end

    local half = size * 0.5

    -- Extract camera right and up vectors from view matrix
    -- View matrix is rotation + translation, so first 3 columns are the rotated axes
    -- For a proper billboard, we use the inverse (transpose of rotation part)
    local right_x = currentViewMatrix[1]
    local right_y = currentViewMatrix[5]
    local right_z = currentViewMatrix[9]

    local up_x = currentViewMatrix[2]
    local up_y = currentViewMatrix[6]
    local up_z = currentViewMatrix[10]

    -- Build quad vertices (camera-facing)
    -- Bottom-left, bottom-right, top-right, top-left
    local v1 = {
        pos = {x - right_x * half - up_x * half, y - right_y * half - up_y * half, z - right_z * half - up_z * half},
        uv = {0, 1}
    }
    local v2 = {
        pos = {x + right_x * half - up_x * half, y + right_y * half - up_y * half, z + right_z * half - up_z * half},
        uv = {1, 1}
    }
    local v3 = {
        pos = {x + right_x * half + up_x * half, y + right_y * half + up_y * half, z + right_z * half + up_z * half},
        uv = {1, 0}
    }
    local v4 = {
        pos = {x - right_x * half + up_x * half, y - right_y * half + up_y * half, z - right_z * half + up_z * half},
        uv = {0, 0}
    }

    -- Draw as two triangles
    renderer_gpu.drawTriangle3D(v1, v2, v3, nil, texData)
    renderer_gpu.drawTriangle3D(v1, v3, v4, nil, texData)
end

-- ===========================================
-- GOURAUD SHADING / DIRECTIONAL LIGHTING
-- ===========================================

-- Normalized light direction (computed once when set)
local lightDir = {0, -1, 0}  -- Default: straight down
local lightIntensity = 0.8
local ambientLight = 0.3

-- Set directional light parameters
function renderer_gpu.setDirectionalLight(dx, dy, dz, intensity, ambient)
    -- Normalize light direction
    local len = math.sqrt(dx*dx + dy*dy + dz*dz)
    if len > 0.001 then
        lightDir[1] = dx / len
        lightDir[2] = dy / len
        lightDir[3] = dz / len
    end
    lightIntensity = intensity or 0.8
    ambientLight = ambient or 0.3
end

-- Get current light settings
function renderer_gpu.getLightSettings()
    return lightDir, lightIntensity, ambientLight
end

-- Calculate vertex brightness from normal using directional light (Gouraud shading)
-- Normal should be normalized and in world space
function renderer_gpu.calculateVertexBrightness(nx, ny, nz)
    -- Lambertian diffuse: dot(normal, -lightDir) clamped to 0
    -- We negate lightDir because we want the direction TO the light
    local dot = -(nx * lightDir[1] + ny * lightDir[2] + nz * lightDir[3])
    local diffuse = math.max(0, dot) * lightIntensity

    -- Combine ambient + diffuse, clamp to 0-1
    return math.min(1.0, ambientLight + diffuse)
end

-- Calculate face normal from three world-space vertex positions
-- Returns normalized normal vector (nx, ny, nz)
function renderer_gpu.calculateFaceNormal(p1, p2, p3)
    -- Two edge vectors
    local e1x = p2[1] - p1[1]
    local e1y = p2[2] - p1[2]
    local e1z = p2[3] - p1[3]

    local e2x = p3[1] - p1[1]
    local e2y = p3[2] - p1[2]
    local e2z = p3[3] - p1[3]

    -- Cross product: e1 × e2
    local nx = e1y * e2z - e1z * e2y
    local ny = e1z * e2x - e1x * e2z
    local nz = e1x * e2y - e1y * e2x

    -- Normalize
    local len = math.sqrt(nx*nx + ny*ny + nz*nz)
    if len > 0.0001 then
        return nx / len, ny / len, nz / len
    end

    return 0, 1, 0  -- Default upward normal
end

-- Cache for palette uniforms
local paletteUniformsCache = nil

-- Send palette and shadow map data to shader
local paletteSent = false
function renderer_gpu.sendPaletteUniforms(shader)
    -- Simply send the palette shadow lookup texture to the shader
    if paletteShadowTexture then
        local ok, err = pcall(function()
            -- Send texture to shader
            shader:send("u_paletteShadowLookup", paletteShadowTexture)
        end)
        if not ok then
            print("ERROR: Could not send palette shadow lookup texture: " .. tostring(err))
            -- Fallback: disable palette shadows
            config.USE_PALETTE_SHADOWS = false
        elseif not paletteSent then
            print("Palette shadow lookup texture sent to shader successfully")
            print("  Texture dimensions: " .. paletteShadowTexture:getWidth() .. "x" .. paletteShadowTexture:getHeight())
            print("  Format: " .. paletteShadowTexture:getFormat())
            paletteSent = true
        end
    else
        print("WARNING: paletteShadowTexture is nil, cannot send to shader")
        config.USE_PALETTE_SHADOWS = false
    end
end

-- Draw a mesh with Gouraud shading (per-vertex lighting)
-- meshData: {vertices = {{pos={x,y,z}, uv={u,v}}, ...}, triangles = {{v1,v2,v3}, ...}}
-- modelMatrix: 4x4 transformation matrix
-- texData: texture ImageData
-- mat4: mat4 module for matrix operations
function renderer_gpu.drawMeshGouraud(meshData, modelMatrix, texData, mat4)
    if not meshData or not meshData.triangles or #meshData.triangles == 0 then return end
    if not texData then return end

    local vertices = meshData.vertices
    local triangles = meshData.triangles

    -- First pass: calculate face normals and accumulate at vertices
    local vertexNormals = {}
    for i = 1, #vertices do
        vertexNormals[i] = {x = 0, y = 0, z = 0, count = 0}
    end

    -- Transform vertices to world space and calculate face normals
    local worldPositions = {}
    for i, v in ipairs(vertices) do
        local wp = mat4.multiplyVec4(modelMatrix, {v.pos[1], v.pos[2], v.pos[3], 1})
        worldPositions[i] = {wp[1], wp[2], wp[3]}
    end

    -- Calculate face normals and accumulate at vertices
    for _, tri in ipairs(triangles) do
        local p1 = worldPositions[tri[1]]
        local p2 = worldPositions[tri[2]]
        local p3 = worldPositions[tri[3]]

        local nx, ny, nz = renderer_gpu.calculateFaceNormal(p1, p2, p3)

        -- Accumulate normal at each vertex
        for j = 1, 3 do
            local vi = tri[j]
            vertexNormals[vi].x = vertexNormals[vi].x + nx
            vertexNormals[vi].y = vertexNormals[vi].y + ny
            vertexNormals[vi].z = vertexNormals[vi].z + nz
            vertexNormals[vi].count = vertexNormals[vi].count + 1
        end
    end

    -- Second pass: calculate per-vertex brightness
    local vertexBrightness = {}
    for i = 1, #vertices do
        local vn = vertexNormals[i]
        local nx, ny, nz = 0, 1, 0  -- Default up

        if vn.count > 0 then
            -- Average the accumulated normals
            nx = vn.x / vn.count
            ny = vn.y / vn.count
            nz = vn.z / vn.count

            -- Normalize
            local len = math.sqrt(nx*nx + ny*ny + nz*nz)
            if len > 0.001 then
                nx, ny, nz = nx / len, ny / len, nz / len
            end
        end

        vertexBrightness[i] = renderer_gpu.calculateVertexBrightness(nx, ny, nz)
    end

    -- Third pass: draw triangles with per-vertex brightness
    local image = getImage(texData)
    local batch = getBatch(image)

    for _, tri in ipairs(triangles) do
        local v1 = vertices[tri[1]]
        local v2 = vertices[tri[2]]
        local v3 = vertices[tri[3]]

        local b1 = vertexBrightness[tri[1]]
        local b2 = vertexBrightness[tri[2]]
        local b3 = vertexBrightness[tri[3]]

        -- Create vertices with world-space positions
        local wv1 = {pos = worldPositions[tri[1]], uv = v1.uv}
        local wv2 = {pos = worldPositions[tri[2]], uv = v2.uv}
        local wv3 = {pos = worldPositions[tri[3]], uv = v3.uv}

        addTriangleToBatchGouraud(batch, wv1, wv2, wv3, b1, b2, b3)
        stats.trianglesDrawn = stats.trianglesDrawn + 1
    end
end

-- Draw a mesh with flat shading (per-face lighting, no interpolation)
-- Same interface as drawMeshGouraud for easy switching
function renderer_gpu.drawMeshFlat(meshData, modelMatrix, texData, mat4)
    if not meshData or not meshData.triangles or #meshData.triangles == 0 then return end
    if not texData then return end

    local vertices = meshData.vertices
    local triangles = meshData.triangles

    -- Transform vertices to world space
    local worldPositions = {}
    for i, v in ipairs(vertices) do
        local wp = mat4.multiplyVec4(modelMatrix, {v.pos[1], v.pos[2], v.pos[3], 1})
        worldPositions[i] = {wp[1], wp[2], wp[3]}
    end

    local image = getImage(texData)
    local batch = getBatch(image)

    -- Draw each triangle with flat shading (single brightness per face)
    for _, tri in ipairs(triangles) do
        local p1 = worldPositions[tri[1]]
        local p2 = worldPositions[tri[2]]
        local p3 = worldPositions[tri[3]]

        -- Calculate face normal
        local nx, ny, nz = renderer_gpu.calculateFaceNormal(p1, p2, p3)

        -- Calculate brightness for the whole face
        local brightness = renderer_gpu.calculateVertexBrightness(nx, ny, nz)

        local v1 = vertices[tri[1]]
        local v2 = vertices[tri[2]]
        local v3 = vertices[tri[3]]

        -- Create vertices with world-space positions
        local wv1 = {pos = p1, uv = v1.uv}
        local wv2 = {pos = p2, uv = v2.uv}
        local wv3 = {pos = p3, uv = v3.uv}

        addTriangleToBatch(batch, wv1, wv2, wv3, brightness)
        stats.trianglesDrawn = stats.trianglesDrawn + 1
    end
end

return renderer_gpu
