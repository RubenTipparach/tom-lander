-- Shadow Map Module with Cascaded Shadow Maps (CSM)
-- Uses 2 cascades: near (high detail) and far (wider coverage)
-- The terrain shader samples the appropriate cascade based on distance

local config = require("config")
local mat4 = require("graphics.mat4")

local ShadowMap = {}

-- Shadow map configuration (from config.lua)
local function getConfig()
    return {
        MAP_SIZE = config.SHADOW_MAP_SIZE or 1024,
        DEPTH_RANGE = config.SHADOW_DEPTH_RANGE or 500,
        BIAS = config.SHADOW_BIAS or 0.002,
        CASCADE_ENABLED = config.SHADOW_CASCADE_ENABLED ~= false,
        CASCADE_SPLIT = config.SHADOW_CASCADE_SPLIT or 25,
        NEAR_COVERAGE = config.SHADOW_NEAR_COVERAGE or 40,
        FAR_COVERAGE = config.SHADOW_FAR_COVERAGE or 120,
    }
end
local SHADOW_NEAR = 1

-- Shadow map resources (2 cascades)
local shadowCanvasNear = nil
local shadowCanvasFar = nil
local shadowDepthCanvasNear = nil
local shadowDepthCanvasFar = nil
local shadowShader = nil

-- Light matrices (2 cascades)
local lightViewMatrixNear = nil
local lightProjMatrixNear = nil
local lightViewMatrixFar = nil
local lightProjMatrixFar = nil
local lightDir = {-0.866, 0.5, 0.0}  -- Default light direction (matches config.LIGHT_DIRECTION)

-- Shadow caster batches
local casterVertices = {}
local casterCount = 0
local casterMesh = nil

-- Camera position for cascade selection
local camPosX, camPosY, camPosZ = 0, 0, 0

-- Vertex format for shadow casters (just position)
local shadowVertexFormat = {
    {"VertexPosition", "float", 4},
}

-- Initialize shadow map system
function ShadowMap.init()
    local cfg = getConfig()
    local size = cfg.MAP_SIZE

    -- Create shadow map canvas (single shadow map for simplicity)
    shadowCanvasNear = love.graphics.newCanvas(size, size, {format = "r16f", readable = true})
    shadowCanvasNear:setFilter("linear", "linear")
    shadowCanvasNear:setWrap("clamp", "clamp")
    shadowDepthCanvasNear = love.graphics.newCanvas(size, size, {format = "depth24", readable = false})

    -- Create second canvas (for compatibility, uses same settings)
    shadowCanvasFar = love.graphics.newCanvas(size, size, {format = "r16f", readable = true})
    shadowCanvasFar:setFilter("linear", "linear")
    shadowCanvasFar:setWrap("clamp", "clamp")
    shadowDepthCanvasFar = love.graphics.newCanvas(size, size, {format = "depth24", readable = false})

    -- Load shadow depth shader (renders depth only)
    local shaderCode = [[
        uniform mat4 lightViewMatrix;
        uniform mat4 lightProjMatrix;
        uniform mat4 modelMatrix;

        #ifdef VERTEX
        varying vec4 v_lightClipPos;

        vec4 position(mat4 transformProjection, vec4 vertexPosition) {
            vec4 worldPos = modelMatrix * vertexPosition;
            vec4 lightViewPos = lightViewMatrix * worldPos;
            vec4 lightClipPos = lightProjMatrix * lightViewPos;

            v_lightClipPos = lightClipPos;

            return lightClipPos;
        }
        #endif

        #ifdef PIXEL
        varying vec4 v_lightClipPos;

        vec4 effect(vec4 color, Image tex, vec2 texCoord, vec2 screenCoord) {
            // Output clip space Z as depth (after perspective divide, 0-1 range)
            float depth = (v_lightClipPos.z / v_lightClipPos.w) * 0.5 + 0.5;
            return vec4(depth, 0.0, 0.0, 1.0);
        }
        #endif
    ]]

    local ok, shaderOrErr = pcall(love.graphics.newShader, shaderCode)
    if ok then
        shadowShader = shaderOrErr
        print("Shadow map shader compiled successfully")
    else
        print("Shadow map shader error: " .. tostring(shaderOrErr))
        return false
    end

    -- Create mesh for shadow casters
    casterMesh = love.graphics.newMesh(shadowVertexFormat, 30000, "triangles", "stream")

    print("Shadow Map initialized: " .. size .. "x" .. size)
    print("  Near coverage: " .. cfg.NEAR_COVERAGE .. " units, Far coverage: " .. cfg.FAR_COVERAGE .. " units")
    return true
end

-- Set light direction (normalized)
function ShadowMap.setLightDirection(dx, dy, dz)
    local len = math.sqrt(dx*dx + dy*dy + dz*dz)
    if len > 0.001 then
        lightDir[1] = dx / len
        lightDir[2] = dy / len
        lightDir[3] = dz / len
    end
end

-- Helper to create shadow map matrices for a specific coverage area
local function createShadowMatrices(camX, camY, camZ, coverage)
    local cfg = getConfig()
    local halfSize = coverage
    local depthRange = cfg.DEPTH_RANGE
    local mapSize = cfg.MAP_SIZE

    -- Calculate world units per texel for snapping (prevents shadow swimming)
    local worldUnitsPerTexel = (halfSize * 2) / mapSize

    -- Build light space axes (same as lookAt but we need them separately for snapping)
    -- Forward vector (light looking toward scene)
    local fwdX, fwdY, fwdZ = -lightDir[1], -lightDir[2], -lightDir[3]

    -- Right vector (cross product of forward and world up)
    local upX, upY, upZ = 0, 1, 0
    local rightX = fwdY * upZ - fwdZ * upY
    local rightY = fwdZ * upX - fwdX * upZ
    local rightZ = fwdX * upY - fwdY * upX
    local rightLen = math.sqrt(rightX*rightX + rightY*rightY + rightZ*rightZ)
    if rightLen > 0.001 then
        rightX, rightY, rightZ = rightX/rightLen, rightY/rightLen, rightZ/rightLen
    end

    -- Recalculate up vector (cross product of right and forward)
    local newUpX = rightY * fwdZ - rightZ * fwdY
    local newUpY = rightZ * fwdX - rightX * fwdZ
    local newUpZ = rightX * fwdY - rightY * fwdX

    -- Project camera position onto light space XY plane for snapping
    -- lightSpaceX = dot(camPos, right)
    -- lightSpaceY = dot(camPos, newUp)
    local lightSpaceX = camX * rightX + camY * rightY + camZ * rightZ
    local lightSpaceY = camX * newUpX + camY * newUpY + camZ * newUpZ

    -- Snap to texel grid
    lightSpaceX = math.floor(lightSpaceX / worldUnitsPerTexel) * worldUnitsPerTexel
    lightSpaceY = math.floor(lightSpaceY / worldUnitsPerTexel) * worldUnitsPerTexel

    -- Convert snapped position back to world space
    local snappedX = lightSpaceX * rightX + lightSpaceY * newUpX
    local snappedY = lightSpaceX * rightY + lightSpaceY * newUpY
    local snappedZ = lightSpaceX * rightZ + lightSpaceY * newUpZ

    -- Position light far enough to cover the depth range
    local lightDist = depthRange * 0.5

    -- Position light in direction of lightDir from snapped position
    local lightPosX = snappedX + lightDir[1] * lightDist
    local lightPosY = snappedY + lightDir[2] * lightDist
    local lightPosZ = snappedZ + lightDir[3] * lightDist

    -- Look-at matrix: from light position, looking at snapped target
    local viewMatrix = mat4.lookAt(
        lightPosX, lightPosY, lightPosZ,
        snappedX, snappedY, snappedZ,
        0, 1, 0  -- Up vector
    )

    local projMatrix = mat4.orthographic(-halfSize, halfSize, -halfSize, halfSize, SHADOW_NEAR, depthRange)

    return viewMatrix, projMatrix
end

-- Begin shadow map rendering pass
-- Call before adding shadow casters
function ShadowMap.beginPass(camX, camY, camZ)
    if not shadowCanvasNear or not shadowShader then return false end

    casterCount = 0
    camPosX, camPosY, camPosZ = camX, camY, camZ

    local cfg = getConfig()

    if cfg.CASCADE_ENABLED then
        -- Create separate matrices for near (high detail) and far (wide coverage) cascades
        lightViewMatrixNear, lightProjMatrixNear = createShadowMatrices(camX, camY, camZ, cfg.NEAR_COVERAGE)
        lightViewMatrixFar, lightProjMatrixFar = createShadowMatrices(camX, camY, camZ, cfg.FAR_COVERAGE)
    else
        -- Single shadow map mode - use far coverage for everything
        local viewMatrix, projMatrix = createShadowMatrices(camX, camY, camZ, cfg.FAR_COVERAGE)
        lightViewMatrixNear = viewMatrix
        lightProjMatrixNear = projMatrix
        lightViewMatrixFar = viewMatrix
        lightProjMatrixFar = projMatrix
    end

    return true
end

-- Add a mesh as shadow caster
function ShadowMap.addMeshCaster(meshData, modelMatrix)
    if not meshData or not meshData.triangles then return end

    local vertices = meshData.vertices
    local triangles = meshData.triangles

    for _, tri in ipairs(triangles) do
        local v1 = vertices[tri[1]]
        local v2 = vertices[tri[2]]
        local v3 = vertices[tri[3]]

        -- Transform to world space
        local p1 = mat4.multiplyVec4(modelMatrix, {v1.pos[1], v1.pos[2], v1.pos[3], 1})
        local p2 = mat4.multiplyVec4(modelMatrix, {v2.pos[1], v2.pos[2], v2.pos[3], 1})
        local p3 = mat4.multiplyVec4(modelMatrix, {v3.pos[1], v3.pos[2], v3.pos[3], 1})

        local idx = casterCount * 3
        casterVertices[idx + 1] = {p1[1], p1[2], p1[3], 1.0}
        casterVertices[idx + 2] = {p2[1], p2[2], p2[3], 1.0}
        casterVertices[idx + 3] = {p3[1], p3[2], p3[3], 1.0}
        casterCount = casterCount + 1
    end
end

-- Add a box as shadow caster (for buildings, pads)
function ShadowMap.addBoxCaster(x, y, z, width, height, depth)
    local hw = width * 0.5
    local hd = depth * 0.5

    -- 8 corners of the box
    local corners = {
        {x - hw, y, z - hd},          -- 1: bottom front left
        {x + hw, y, z - hd},          -- 2: bottom front right
        {x + hw, y, z + hd},          -- 3: bottom back right
        {x - hw, y, z + hd},          -- 4: bottom back left
        {x - hw, y + height, z - hd}, -- 5: top front left
        {x + hw, y + height, z - hd}, -- 6: top front right
        {x + hw, y + height, z + hd}, -- 7: top back right
        {x - hw, y + height, z + hd}, -- 8: top back left
    }

    -- 12 triangles (6 faces, 2 triangles each)
    local faces = {
        {1, 2, 6}, {1, 6, 5}, -- front
        {2, 3, 7}, {2, 7, 6}, -- right
        {3, 4, 8}, {3, 8, 7}, -- back
        {4, 1, 5}, {4, 5, 8}, -- left
        {5, 6, 7}, {5, 7, 8}, -- top
        {4, 3, 2}, {4, 2, 1}, -- bottom
    }

    for _, face in ipairs(faces) do
        local idx = casterCount * 3
        casterVertices[idx + 1] = {corners[face[1]][1], corners[face[1]][2], corners[face[1]][3], 1.0}
        casterVertices[idx + 2] = {corners[face[2]][1], corners[face[2]][2], corners[face[2]][3], 1.0}
        casterVertices[idx + 3] = {corners[face[3]][1], corners[face[3]][2], corners[face[3]][3], 1.0}
        casterCount = casterCount + 1
    end
end

-- Add a tree as shadow caster (trunk + foliage)
function ShadowMap.addTreeCaster(x, y, z, radius, height)
    local segments = 6
    local trunkRadius = radius * 0.15
    local trunkHeight = height * 0.3
    local foliageRadius = radius
    local foliageBottom = y + trunkHeight * 0.5
    local foliageTop = y + height

    -- Add trunk as a simple box (thin cylinder approximation)
    for i = 0, segments - 1 do
        local angle1 = (i / segments) * math.pi * 2
        local angle2 = ((i + 1) / segments) * math.pi * 2

        local x1 = x + math.cos(angle1) * trunkRadius
        local z1 = z + math.sin(angle1) * trunkRadius
        local x2 = x + math.cos(angle2) * trunkRadius
        local z2 = z + math.sin(angle2) * trunkRadius

        -- Trunk side quad (2 triangles)
        local idx = casterCount * 3
        casterVertices[idx + 1] = {x1, y, z1, 1.0}
        casterVertices[idx + 2] = {x2, y, z2, 1.0}
        casterVertices[idx + 3] = {x2, foliageBottom, z2, 1.0}
        casterCount = casterCount + 1

        idx = casterCount * 3
        casterVertices[idx + 1] = {x1, y, z1, 1.0}
        casterVertices[idx + 2] = {x2, foliageBottom, z2, 1.0}
        casterVertices[idx + 3] = {x1, foliageBottom, z1, 1.0}
        casterCount = casterCount + 1
    end

    -- Add foliage as a cone
    for i = 0, segments - 1 do
        local angle1 = (i / segments) * math.pi * 2
        local angle2 = ((i + 1) / segments) * math.pi * 2

        local x1 = x + math.cos(angle1) * foliageRadius
        local z1 = z + math.sin(angle1) * foliageRadius
        local x2 = x + math.cos(angle2) * foliageRadius
        local z2 = z + math.sin(angle2) * foliageRadius

        -- Foliage cone side
        local idx = casterCount * 3
        casterVertices[idx + 1] = {x1, foliageBottom, z1, 1.0}
        casterVertices[idx + 2] = {x2, foliageBottom, z2, 1.0}
        casterVertices[idx + 3] = {x, foliageTop, z, 1.0}
        casterCount = casterCount + 1
    end
end

-- Debug flag
local debugPrinted = false

-- Render to a single cascade
local function renderCascade(canvas, depthCanvas, viewMatrix, projMatrix)
    -- Set shadow map as render target
    love.graphics.setCanvas({canvas, depthstencil = depthCanvas})
    love.graphics.clear(1, 0, 0, 1)  -- Clear to max depth (1.0)
    love.graphics.setDepthMode("lequal", true)

    -- Set shadow shader with this cascade's matrices
    love.graphics.setShader(shadowShader)
    shadowShader:send("lightViewMatrix", viewMatrix)
    shadowShader:send("lightProjMatrix", projMatrix)
    shadowShader:send("modelMatrix", {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1})  -- Identity

    -- Draw mesh
    love.graphics.draw(casterMesh)
end

-- End shadow map pass and render to both cascade textures
function ShadowMap.endPass()
    if casterCount == 0 then
        if not debugPrinted then
            print("ShadowMap: No casters added!")
            debugPrinted = true
        end
        return
    end
    if not shadowCanvasNear or not shadowShader then return end

    if not debugPrinted then
        print("ShadowMap: Rendering " .. casterCount .. " triangles to 2 cascades")
        print("  Light dir: " .. lightDir[1] .. ", " .. lightDir[2] .. ", " .. lightDir[3])
        debugPrinted = true
    end

    -- Save current state
    local prevCanvas = love.graphics.getCanvas()
    local prevShader = love.graphics.getShader()
    local prevDepthMode = love.graphics.getDepthMode()

    -- Update mesh vertices once
    local vertCount = casterCount * 3
    casterMesh:setVertices(casterVertices, 1, vertCount)
    casterMesh:setDrawRange(1, vertCount)

    -- Render to near cascade (high detail)
    renderCascade(shadowCanvasNear, shadowDepthCanvasNear, lightViewMatrixNear, lightProjMatrixNear)

    -- Render to far cascade (wide coverage)
    renderCascade(shadowCanvasFar, shadowDepthCanvasFar, lightViewMatrixFar, lightProjMatrixFar)

    -- Restore state
    love.graphics.setShader(prevShader)
    love.graphics.setCanvas(prevCanvas)
    if prevDepthMode then
        love.graphics.setDepthMode("lequal", true)
    end
end

-- Get shadow map textures for terrain shader
function ShadowMap.getTextureNear()
    return shadowCanvasNear
end

function ShadowMap.getTextureFar()
    return shadowCanvasFar
end

-- Legacy single texture getter (returns far cascade for compatibility)
function ShadowMap.getTexture()
    return shadowCanvasFar
end

-- Get light matrices for terrain shader (near cascade)
function ShadowMap.getLightViewMatrixNear()
    return lightViewMatrixNear
end

function ShadowMap.getLightProjMatrixNear()
    return lightProjMatrixNear
end

-- Get light matrices for terrain shader (far cascade)
function ShadowMap.getLightViewMatrixFar()
    return lightViewMatrixFar
end

function ShadowMap.getLightProjMatrixFar()
    return lightProjMatrixFar
end

-- Legacy single matrix getters (return far cascade for compatibility)
function ShadowMap.getLightViewMatrix()
    return lightViewMatrixFar
end

function ShadowMap.getLightProjMatrix()
    return lightProjMatrixFar
end

-- Get cascade split distance (for shader)
function ShadowMap.getCascadeSplitDistance()
    local cfg = getConfig()
    return cfg.CASCADE_SPLIT
end

-- Get light direction
function ShadowMap.getLightDirection()
    return lightDir[1], lightDir[2], lightDir[3]
end

return ShadowMap
