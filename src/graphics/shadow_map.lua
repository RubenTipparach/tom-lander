-- Shadow Map Module
-- Renders shadow casters from light's perspective to create a depth-based shadow map
-- The terrain shader samples this to determine shadowed areas

local config = require("config")
local mat4 = require("graphics.mat4")

local ShadowMap = {}

-- Shadow map configuration
local SHADOW_MAP_SIZE = 512  -- Resolution of shadow map texture
local SHADOW_DISTANCE = 60   -- How far shadows extend from camera
local SHADOW_NEAR = 0.1
local SHADOW_FAR = 100

-- Shadow map resources
local shadowCanvas = nil
local shadowDepthCanvas = nil
local shadowShader = nil

-- Light matrices
local lightViewMatrix = nil
local lightProjMatrix = nil
local lightDir = {-0.866, 0.5, 0.0}  -- Default light direction (60° from east)

-- Shadow caster batches
local casterVertices = {}
local casterCount = 0
local casterMesh = nil

-- Vertex format for shadow casters (just position)
local shadowVertexFormat = {
    {"VertexPosition", "float", 4},
}

-- Initialize shadow map system
function ShadowMap.init()
    -- Create shadow map canvas (stores depth from light's view)
    shadowCanvas = love.graphics.newCanvas(SHADOW_MAP_SIZE, SHADOW_MAP_SIZE, {format = "r16f", readable = true})
    shadowCanvas:setFilter("linear", "linear")  -- Linear filtering for soft shadow edges
    shadowCanvas:setWrap("clamp", "clamp")

    -- Create depth buffer for shadow rendering
    shadowDepthCanvas = love.graphics.newCanvas(SHADOW_MAP_SIZE, SHADOW_MAP_SIZE, {format = "depth24", readable = false})

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

    print("Shadow map initialized: " .. SHADOW_MAP_SIZE .. "x" .. SHADOW_MAP_SIZE)
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

-- Begin shadow map rendering pass
-- Call before adding shadow casters
function ShadowMap.beginPass(camX, camY, camZ)
    if not shadowCanvas or not shadowShader then return false end

    casterCount = 0

    -- Create orthographic projection for directional light
    -- Center the shadow frustum around the camera
    local halfSize = SHADOW_DISTANCE * 0.5
    lightProjMatrix = mat4.orthographic(-halfSize, halfSize, -halfSize, halfSize, SHADOW_NEAR, SHADOW_FAR)

    -- Create view matrix looking along light direction
    -- Position light "behind" the scene (opposite of light direction)
    local lightDist = SHADOW_DISTANCE * 0.5
    local lightPosX = camX - lightDir[1] * lightDist
    local lightPosY = camY - lightDir[2] * lightDist
    local lightPosZ = camZ - lightDir[3] * lightDist

    -- Target is in front of light (along light direction)
    local targetX = camX + lightDir[1] * lightDist
    local targetY = camY + lightDir[2] * lightDist
    local targetZ = camZ + lightDir[3] * lightDist

    -- Look-at matrix: from light position, looking at target
    lightViewMatrix = mat4.lookAt(
        lightPosX, lightPosY, lightPosZ,
        targetX, targetY, targetZ,
        0, 1, 0  -- Up vector
    )

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

-- End shadow map pass and render to shadow texture
function ShadowMap.endPass()
    if casterCount == 0 then
        if not debugPrinted then
            print("ShadowMap: No casters added!")
            debugPrinted = true
        end
        return
    end
    if not shadowCanvas or not shadowShader then return end

    if not debugPrinted then
        print("ShadowMap: Rendering " .. casterCount .. " triangles")
        print("  Light dir: " .. lightDir[1] .. ", " .. lightDir[2] .. ", " .. lightDir[3])
        debugPrinted = true
    end

    -- Save current state
    local prevCanvas = love.graphics.getCanvas()
    local prevShader = love.graphics.getShader()
    local prevDepthMode = love.graphics.getDepthMode()

    -- Set shadow map as render target
    love.graphics.setCanvas({shadowCanvas, depthstencil = shadowDepthCanvas})
    love.graphics.clear(1, 0, 0, 1)  -- Clear to max depth (1.0)
    love.graphics.setDepthMode("lequal", true)

    -- Set shadow shader
    love.graphics.setShader(shadowShader)
    shadowShader:send("lightViewMatrix", lightViewMatrix)
    shadowShader:send("lightProjMatrix", lightProjMatrix)
    shadowShader:send("modelMatrix", {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1})  -- Identity

    -- Update and draw mesh
    local vertCount = casterCount * 3
    casterMesh:setVertices(casterVertices, 1, vertCount)
    casterMesh:setDrawRange(1, vertCount)
    love.graphics.draw(casterMesh)

    -- Restore state
    love.graphics.setShader(prevShader)
    love.graphics.setCanvas(prevCanvas)
    if prevDepthMode then
        love.graphics.setDepthMode("lequal", true)
    end
end

-- Get shadow map texture for terrain shader
function ShadowMap.getTexture()
    return shadowCanvas
end

-- Get light matrices for terrain shader
function ShadowMap.getLightViewMatrix()
    return lightViewMatrix
end

function ShadowMap.getLightProjMatrix()
    return lightProjMatrix
end

-- Get light direction
function ShadowMap.getLightDirection()
    return lightDir[1], lightDir[2], lightDir[3]
end

return ShadowMap
