-- Shadow Projection Module
-- Projects object shadows onto terrain using the light direction
-- Shadows are rendered as flattened geometry on the ground

local config = require("config")
local mat4 = require("mat4")

local Shadow = {}

-- Cache light direction (normalized)
local lightDir = {0, -1, 0}  -- Default: straight down

-- Set light direction for shadow projection
function Shadow.setLightDirection(dx, dy, dz)
    -- Normalize and store
    local len = math.sqrt(dx*dx + dy*dy + dz*dz)
    if len > 0.001 then
        lightDir[1] = dx / len
        lightDir[2] = dy / len
        lightDir[3] = dz / len
    end
end

-- Project a single point onto the terrain along light direction
-- Returns projected x, y, z coordinates
function Shadow.projectPoint(x, y, z, Heightmap)
    -- Get ground height at this XZ position
    local groundHeight = Heightmap.get_height(x, z)

    -- If the point is already below ground, no shadow
    if y <= groundHeight then
        return nil
    end

    -- Light direction points TOWARD the light source
    -- For shadow casting, we need to project AWAY from the light (opposite direction)
    -- If lightDir.y > 0, light is above, shadows go in -lightDir direction
    -- We need lightDir.y to be positive (light above horizon) for shadows to work
    if lightDir[2] <= 0.001 then
        return nil  -- Light is at or below horizon, no shadows
    end

    -- Calculate how far we need to go to reach ground height
    -- Starting at y, going down along -lightDir direction
    -- y - t * lightDir[2] = groundHeight
    -- t = (y - groundHeight) / lightDir[2]
    local t = (y - groundHeight) / lightDir[2]

    -- Project along negative light direction (away from light)
    local shadowX = x - lightDir[1] * t
    local shadowZ = z - lightDir[3] * t

    -- Get actual ground height at projected position
    local actualGroundHeight = Heightmap.get_height(shadowX, shadowZ)
    local shadowY = actualGroundHeight + config.SHADOW_OFFSET_Y

    return shadowX, shadowY, shadowZ
end

-- Project a mesh triangle onto terrain
-- Returns three projected vertices or nil if shadow is invalid
function Shadow.projectTriangle(v1, v2, v3, modelMatrix, Heightmap)
    -- Transform vertices to world space
    local p1 = mat4.multiplyVec4(modelMatrix, {v1.pos[1], v1.pos[2], v1.pos[3], 1})
    local p2 = mat4.multiplyVec4(modelMatrix, {v2.pos[1], v2.pos[2], v2.pos[3], 1})
    local p3 = mat4.multiplyVec4(modelMatrix, {v3.pos[1], v3.pos[2], v3.pos[3], 1})

    -- Project each vertex onto terrain
    local sx1, sy1, sz1 = Shadow.projectPoint(p1[1], p1[2], p1[3], Heightmap)
    local sx2, sy2, sz2 = Shadow.projectPoint(p2[1], p2[2], p2[3], Heightmap)
    local sx3, sy3, sz3 = Shadow.projectPoint(p3[1], p3[2], p3[3], Heightmap)

    -- All three points must project successfully
    if not sx1 or not sx2 or not sx3 then
        return nil
    end

    return {sx1, sy1, sz1}, {sx2, sy2, sz2}, {sx3, sy3, sz3}
end

-- Draw shadow for a mesh with the given model matrix
function Shadow.drawMeshShadow(renderer, mesh, modelMatrix, Heightmap, camX, camZ)
    if not mesh or not mesh.triangles then return end
    if not config.SHADOWS_ENABLED then return end

    local vertices = mesh.vertices
    local triangles = mesh.triangles
    local shadowDistSq = config.SHADOW_RENDER_DISTANCE * config.SHADOW_RENDER_DISTANCE

    for _, tri in ipairs(triangles) do
        local v1 = vertices[tri[1]]
        local v2 = vertices[tri[2]]
        local v3 = vertices[tri[3]]

        -- Project triangle
        local s1, s2, s3 = Shadow.projectTriangle(v1, v2, v3, modelMatrix, Heightmap)

        if s1 and s2 and s3 then
            -- Distance cull based on shadow center
            local centerX = (s1[1] + s2[1] + s3[1]) / 3
            local centerZ = (s1[3] + s2[3] + s3[3]) / 3
            local dx = centerX - camX
            local dz = centerZ - camZ

            if dx*dx + dz*dz < shadowDistSq then
                renderer.drawShadowTriangle(s1, s2, s3)
            end
        end
    end
end

-- Draw shadow for a simple bounding box (for buildings)
-- Uses the footprint projected onto terrain
function Shadow.drawBoxShadow(renderer, x, y, z, width, depth, Heightmap, camX, camZ)
    if not config.SHADOWS_ENABLED then return end

    local shadowDistSq = config.SHADOW_RENDER_DISTANCE * config.SHADOW_RENDER_DISTANCE
    local dx = x - camX
    local dz = z - camZ
    if dx*dx + dz*dz > shadowDistSq then return end

    local halfW = width / 2
    local halfD = depth / 2

    -- Get the four corners of the building at its height
    local corners = {
        {x - halfW, y, z - halfD},
        {x + halfW, y, z - halfD},
        {x + halfW, y, z + halfD},
        {x - halfW, y, z + halfD}
    }

    -- Project each corner onto terrain
    local projected = {}
    for i, c in ipairs(corners) do
        local sx, sy, sz = Shadow.projectPoint(c[1], c[2], c[3], Heightmap)
        if not sx then return end  -- Shadow extends beyond valid terrain
        projected[i] = {sx, sy, sz}
    end

    -- Draw two triangles for the shadow quad
    renderer.drawShadowTriangle(projected[1], projected[2], projected[3])
    renderer.drawShadowTriangle(projected[1], projected[3], projected[4])
end

-- Draw shadow for a simple ellipse (for trees - faster than full mesh)
-- x, z: object base position
-- height: object height (for shadow length calculation)
-- radius: horizontal radius of the shadow ellipse
function Shadow.drawEllipseShadow(renderer, x, y, z, radius, Heightmap, camX, camZ)
    if not config.SHADOWS_ENABLED then return end

    local shadowDistSq = config.SHADOW_RENDER_DISTANCE * config.SHADOW_RENDER_DISTANCE
    local dx = x - camX
    local dz = z - camZ
    if dx*dx + dz*dz > shadowDistSq then return end

    -- Get ground height at object position
    local groundY = Heightmap.get_height(x, z) + config.SHADOW_OFFSET_Y

    -- Calculate shadow stretch based on light angle
    -- Shadow extends in the opposite direction of the light
    local shadowLength = radius * 1.5  -- Base shadow length
    local stretchX = -lightDir[1] / math.max(0.1, lightDir[2]) * shadowLength
    local stretchZ = -lightDir[3] / math.max(0.1, lightDir[2]) * shadowLength

    -- Shadow is an ellipse that starts at object base and extends away from light
    -- Center of shadow is offset from object base
    local centerX = x + stretchX * 0.5
    local centerZ = z + stretchZ * 0.5

    -- 4 points around the shadow center
    local north = {centerX, groundY, centerZ - radius}
    local south = {centerX, groundY, centerZ + radius}
    local east = {centerX + radius, groundY, centerZ}
    local west = {centerX - radius, groundY, centerZ}
    local center = {centerX, groundY, centerZ}

    -- Also add far points stretched by light direction
    local farCenter = {x + stretchX, groundY, z + stretchZ}

    -- Draw shadow as elongated shape toward far point
    -- Near half (around object base)
    renderer.drawShadowTriangle({x, groundY, z - radius * 0.7}, {x + radius * 0.7, groundY, z}, {x, groundY, z})
    renderer.drawShadowTriangle({x + radius * 0.7, groundY, z}, {x, groundY, z + radius * 0.7}, {x, groundY, z})
    renderer.drawShadowTriangle({x, groundY, z + radius * 0.7}, {x - radius * 0.7, groundY, z}, {x, groundY, z})
    renderer.drawShadowTriangle({x - radius * 0.7, groundY, z}, {x, groundY, z - radius * 0.7}, {x, groundY, z})

    -- Far stretched part (away from light)
    renderer.drawShadowTriangle({x, groundY, z - radius * 0.5}, farCenter, {x + radius * 0.5, groundY, z})
    renderer.drawShadowTriangle({x + radius * 0.5, groundY, z}, farCenter, {x, groundY, z + radius * 0.5})
    renderer.drawShadowTriangle({x, groundY, z + radius * 0.5}, farCenter, {x - radius * 0.5, groundY, z})
    renderer.drawShadowTriangle({x - radius * 0.5, groundY, z}, farCenter, {x, groundY, z - radius * 0.5})
end

-- Draw a simple ground shadow for a box/building
-- Shadow is the building footprint stretched in light direction
function Shadow.drawBoxShadowSimple(renderer, x, z, width, depth, height, Heightmap, camX, camZ)
    if not config.SHADOWS_ENABLED then return end

    local shadowDistSq = config.SHADOW_RENDER_DISTANCE * config.SHADOW_RENDER_DISTANCE
    local dx = x - camX
    local dz = z - camZ
    if dx*dx + dz*dz > shadowDistSq then return end

    local groundY = Heightmap.get_height(x, z) + config.SHADOW_OFFSET_Y
    local halfW = width / 2
    local halfD = depth / 2

    -- Calculate shadow stretch based on building height and light angle
    local stretchX = -lightDir[1] / math.max(0.1, lightDir[2]) * height * 0.5
    local stretchZ = -lightDir[3] / math.max(0.1, lightDir[2]) * height * 0.5

    -- Near corners (at building base)
    local n1 = {x - halfW, groundY, z - halfD}
    local n2 = {x + halfW, groundY, z - halfD}
    local n3 = {x + halfW, groundY, z + halfD}
    local n4 = {x - halfW, groundY, z + halfD}

    -- Far corners (stretched by light)
    local f1 = {x - halfW + stretchX, groundY, z - halfD + stretchZ}
    local f2 = {x + halfW + stretchX, groundY, z - halfD + stretchZ}
    local f3 = {x + halfW + stretchX, groundY, z + halfD + stretchZ}
    local f4 = {x - halfW + stretchX, groundY, z + halfD + stretchZ}

    -- Draw building footprint shadow
    renderer.drawShadowTriangle(n1, n2, n3)
    renderer.drawShadowTriangle(n1, n3, n4)

    -- Draw stretched shadow sides (connect near to far)
    renderer.drawShadowTriangle(n1, f1, f2)
    renderer.drawShadowTriangle(n1, f2, n2)

    renderer.drawShadowTriangle(n2, f2, f3)
    renderer.drawShadowTriangle(n2, f3, n3)

    renderer.drawShadowTriangle(n3, f3, f4)
    renderer.drawShadowTriangle(n3, f4, n4)

    renderer.drawShadowTriangle(n4, f4, f1)
    renderer.drawShadowTriangle(n4, f1, n1)
end

return Shadow
