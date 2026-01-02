-- Per-Vertex Lighting System
-- Ported from Picotron lounge lighting system
-- Uses distance and angle-based lighting calculations

local lighting = {}

-- Active lights in the scene
local lights = {}
local ambientLevel = 0.2  -- Default 20% ambient light

-- Add or update a point light
function lighting.addLight(id, x, y, z, radius, brightness)
    lights[id] = {
        pos = {x = x or 0, y = y or 0, z = z or 0},
        radius = radius or 5.0,      -- Distance where light reaches 100%
        brightness = brightness or 1.0  -- Light intensity multiplier
    }
end

-- Remove a light
function lighting.removeLight(id)
    lights[id] = nil
end

-- Set ambient light level (0-1)
function lighting.setAmbient(level)
    ambientLevel = level or 0.2
end

-- Clear all lights
function lighting.clearLights()
    lights = {}
end

-- Calculate brightness for a vertex based on all lights
-- Returns brightness value 0-1
-- @param vx, vy, vz: vertex world position
-- @param nx, ny, nz: vertex normal (normalized)
-- @return brightness (0-1)
function lighting.calculateVertexBrightness(vx, vy, vz, nx, ny, nz)
    local totalBrightness = ambientLevel

    -- Add contribution from each light
    for _, light in pairs(lights) do
        -- Vector from vertex to light
        local dx = light.pos.x - vx
        local dy = light.pos.y - vy
        local dz = light.pos.z - vz
        local dist_sq = dx*dx + dy*dy + dz*dz
        local dist = math.sqrt(dist_sq)

        if dist > 0.01 then
            -- Normalize light direction vector
            local lx, ly, lz = dx / dist, dy / dist, dz / dist

            -- Distance attenuation: 1 - (distance / radius), clamped to 0-1
            local dist_atten = 1.0 - (dist / light.radius)
            dist_atten = math.max(0, math.min(1, dist_atten))

            -- Angle-based lighting: dot product of normal and light direction
            -- Negated because normals point outward
            local dot = -(nx * lx + ny * ly + nz * lz)
            local angle_factor = math.max(0, dot)

            -- Combine: distance dims all faces, angle darkens faces pointing away
            local lightContribution = light.brightness * dist_atten * angle_factor * (1 - ambientLevel)
            totalBrightness = totalBrightness + lightContribution
        end
    end

    -- Clamp to 0-1 range
    return math.max(0, math.min(1, totalBrightness))
end

-- Calculate face normal from three vertices using cross product
-- Returns normalized normal vector
function lighting.calculateFaceNormal(v1, v2, v3)
    -- Two edge vectors
    local e1x = v2[1] - v1[1]
    local e1y = v2[2] - v1[2]
    local e1z = v2[3] - v1[3]

    local e2x = v3[1] - v1[1]
    local e2y = v3[2] - v1[2]
    local e2z = v3[3] - v1[3]

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

-- Draw a mesh with per-vertex lighting
-- @param meshData: mesh data with vertices and triangles
-- @param modelMatrix: model transformation matrix
-- @param texture: texture image
-- @param texData: texture image data
-- @param renderer: renderer module (renderer_dda)
-- @param mat4: mat4 module
-- @param viewMatrix: view matrix
-- @param projectionMatrix: projection matrix
-- @param camPos: camera position
function lighting.drawLitMesh(meshData, modelMatrix, texture, texData, renderer, mat4, viewMatrix, projectionMatrix, camPos)
    -- First pass: calculate face normals
    local faceNormals = {}
    for i, tri in ipairs(meshData.triangles) do
        local v1 = meshData.vertices[tri[1]].pos
        local v2 = meshData.vertices[tri[2]].pos
        local v3 = meshData.vertices[tri[3]].pos

        -- Transform to world space
        local w1 = mat4.multiplyVec4(modelMatrix, {v1[1], v1[2], v1[3], 1})
        local w2 = mat4.multiplyVec4(modelMatrix, {v2[1], v2[2], v2[3], 1})
        local w3 = mat4.multiplyVec4(modelMatrix, {v3[1], v3[2], v3[3], 1})

        -- Calculate face normal
        local nx, ny, nz = lighting.calculateFaceNormal(w1, w2, w3)
        faceNormals[i] = {x = nx, y = ny, z = nz}
    end

    -- Second pass: accumulate normals at vertices (for smooth shading)
    local vertexNormals = {}
    for i = 1, #meshData.vertices do
        vertexNormals[i] = {x = 0, y = 0, z = 0, count = 0}
    end

    for i, tri in ipairs(meshData.triangles) do
        local normal = faceNormals[i]
        for _, vi in ipairs(tri) do
            vertexNormals[vi].x = vertexNormals[vi].x + normal.x
            vertexNormals[vi].y = vertexNormals[vi].y + normal.y
            vertexNormals[vi].z = vertexNormals[vi].z + normal.z
            vertexNormals[vi].count = vertexNormals[vi].count + 1
        end
    end

    -- Third pass: calculate per-vertex brightness
    local vertexBrightness = {}
    for i = 1, #meshData.vertices do
        local v = meshData.vertices[i].pos
        local worldPos = mat4.multiplyVec4(modelMatrix, {v[1], v[2], v[3], 1})

        -- Normalize averaged normal
        local vn = vertexNormals[i]
        local nx, ny, nz = 0, 1, 0  -- Default
        if vn.count > 0 then
            nx, ny, nz = vn.x / vn.count, vn.y / vn.count, vn.z / vn.count
            local len = math.sqrt(nx*nx + ny*ny + nz*nz)
            if len > 0.001 then
                nx, ny, nz = nx / len, ny / len, nz / len
            end
        end

        -- Calculate brightness
        vertexBrightness[i] = lighting.calculateVertexBrightness(
            worldPos[1], worldPos[2], worldPos[3],
            nx, ny, nz
        )
    end

    -- Draw triangles with per-triangle average brightness
    local mvp = mat4.multiply(mat4.multiply(projectionMatrix, viewMatrix), modelMatrix)
    renderer.setMatrices(mvp, camPos)

    for _, tri in ipairs(meshData.triangles) do
        local v1 = meshData.vertices[tri[1]]
        local v2 = meshData.vertices[tri[2]]
        local v3 = meshData.vertices[tri[3]]

        -- Average brightness for the triangle
        local avgBrightness = (vertexBrightness[tri[1]] + vertexBrightness[tri[2]] + vertexBrightness[tri[3]]) / 3

        -- Draw with brightness
        renderer.drawTriangle3D(v1, v2, v3, texture, texData, avgBrightness)
    end
end

return lighting
