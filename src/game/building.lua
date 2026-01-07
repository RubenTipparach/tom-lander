-- Building module: Procedural building generation with textured sides and rooftops
-- Adapted from Picotron version for Love2D

local Constants = require("constants")
local mat4 = require("mat4")
local config = require("config")

local Building = {}

-- Generate nine-sliced UVs for a building side
local function generate_nineslice_uvs(width, height, sprite_size)
    local u_min = 0
    local u_max = 1

    -- Vertical tiling to match aspect ratio
    local tiles_v = height / width
    local v_range = tiles_v

    -- Align to TOP
    local v_min = -v_range
    local v_max = 0

    return {
        {u_min, v_min},  -- bottom-left
        {u_max, v_min},  -- bottom-right
        {u_max, v_max},  -- top-right
        {u_min, v_max}   -- top-left
    }
end

-- Create a building object
-- config: {x, z, width, depth, height, base_y, side_sprite, name, id}
function Building.create(config)
    local x = config.x or 0
    local z = config.z or 0
    local width = config.width or 2
    local depth = config.depth or 2
    local height = config.height or 5
    local base_y = config.base_y or 0
    local side_sprite = config.side_sprite or Constants.SPRITE_BUILDING_SIDE
    local name = config.name
    local id = config.id

    -- Create vertices (8 corners of the building)
    local hw = width
    local hd = depth
    local vertices = {
        {pos = {-hw, 0, -hd}, uv = {0, 0}},           -- 1: bottom front-left
        {pos = {hw, 0, -hd}, uv = {1, 0}},            -- 2: bottom front-right
        {pos = {hw, height * 2, -hd}, uv = {1, 1}},   -- 3: top front-right
        {pos = {-hw, height * 2, -hd}, uv = {0, 1}},  -- 4: top front-left
        {pos = {-hw, 0, hd}, uv = {0, 0}},            -- 5: bottom back-left
        {pos = {hw, 0, hd}, uv = {1, 0}},             -- 6: bottom back-right
        {pos = {hw, height * 2, hd}, uv = {1, 1}},    -- 7: top back-right
        {pos = {-hw, height * 2, hd}, uv = {0, 1}},   -- 8: top back-left
    }

    -- Create faces
    local triangles = {}

    -- TOP FACE (rooftop)
    table.insert(triangles, {indices = {4, 3, 7}, sprite = Constants.SPRITE_ROOFTOP, uvs = {{0,0}, {1,0}, {1,1}}})
    table.insert(triangles, {indices = {4, 7, 8}, sprite = Constants.SPRITE_ROOFTOP, uvs = {{0,0}, {1,1}, {0,1}}})

    -- FRONT FACE
    local front_uvs = generate_nineslice_uvs(width * 2, height * 2, 32)
    table.insert(triangles, {indices = {1, 2, 3}, sprite = side_sprite, uvs = {front_uvs[1], front_uvs[2], front_uvs[3]}})
    table.insert(triangles, {indices = {1, 3, 4}, sprite = side_sprite, uvs = {front_uvs[1], front_uvs[3], front_uvs[4]}})

    -- BACK FACE
    local back_uvs = generate_nineslice_uvs(width * 2, height * 2, 32)
    table.insert(triangles, {indices = {6, 5, 8}, sprite = side_sprite, uvs = {back_uvs[1], back_uvs[2], back_uvs[3]}})
    table.insert(triangles, {indices = {6, 8, 7}, sprite = side_sprite, uvs = {back_uvs[1], back_uvs[3], back_uvs[4]}})

    -- LEFT FACE
    local left_uvs = generate_nineslice_uvs(depth * 2, height * 2, 32)
    table.insert(triangles, {indices = {5, 1, 4}, sprite = side_sprite, uvs = {left_uvs[1], left_uvs[2], left_uvs[3]}})
    table.insert(triangles, {indices = {5, 4, 8}, sprite = side_sprite, uvs = {left_uvs[1], left_uvs[3], left_uvs[4]}})

    -- RIGHT FACE
    local right_uvs = generate_nineslice_uvs(depth * 2, height * 2, 32)
    table.insert(triangles, {indices = {2, 6, 7}, sprite = side_sprite, uvs = {right_uvs[1], right_uvs[2], right_uvs[3]}})
    table.insert(triangles, {indices = {2, 7, 3}, sprite = side_sprite, uvs = {right_uvs[1], right_uvs[3], right_uvs[4]}})

    return {
        vertices = vertices,
        triangles = triangles,
        x = x,
        y = base_y,
        z = z,
        width = width * 2,
        height = height * 2,
        depth = depth * 2,
        name = name,
        id = id
    }
end

-- Draw a building using the renderer
function Building.draw(building, renderer, cam_x, cam_z)
    -- Distance culling - skip buildings beyond render distance
    if cam_x and cam_z then
        local dx = building.x - cam_x
        local dz = building.z - cam_z
        local dist_sq = dx * dx + dz * dz
        if dist_sq > config.RENDER_DISTANCE * config.RENDER_DISTANCE then
            return
        end
    end

    -- Build model matrix
    local modelMatrix = mat4.translation(building.x, building.y, building.z)

    for _, tri in ipairs(building.triangles) do
        local texData = Constants.getTextureData(tri.sprite)
        if texData then
            local v1 = building.vertices[tri.indices[1]]
            local v2 = building.vertices[tri.indices[2]]
            local v3 = building.vertices[tri.indices[3]]

            -- Transform vertices
            local p1 = mat4.multiplyVec4(modelMatrix, {v1.pos[1], v1.pos[2], v1.pos[3], 1})
            local p2 = mat4.multiplyVec4(modelMatrix, {v2.pos[1], v2.pos[2], v2.pos[3], 1})
            local p3 = mat4.multiplyVec4(modelMatrix, {v3.pos[1], v3.pos[2], v3.pos[3], 1})

            -- Calculate lighting if enabled
            local brightness = 1.0
            if config.GOURAUD_SHADING and renderer.calculateFaceNormal and renderer.calculateVertexBrightness then
                local nx, ny, nz = renderer.calculateFaceNormal(
                    {p1[1], p1[2], p1[3]},
                    {p2[1], p2[2], p2[3]},
                    {p3[1], p3[2], p3[3]}
                )
                brightness = renderer.calculateVertexBrightness(nx, ny, nz)
            end

            renderer.drawTriangle3D(
                {pos = {p1[1], p1[2], p1[3]}, uv = tri.uvs[1]},
                {pos = {p2[1], p2[2], p2[3]}, uv = tri.uvs[2]},
                {pos = {p3[1], p3[2], p3[3]}, uv = tri.uvs[3]},
                nil,
                texData,
                brightness
            )
        end
    end
end

-- Create multiple buildings from a config array
function Building.create_city(configs, heightmap)
    local buildings = {}
    for i, config in ipairs(configs) do
        config.id = i
        if not config.name and Constants.BUILDING_NAMES[i] then
            config.name = Constants.BUILDING_NAMES[i]
        end

        -- Get terrain height if heightmap provided
        if heightmap and not config.base_y then
            config.base_y = heightmap.get_height(config.x, config.z)
        end

        table.insert(buildings, Building.create(config))
    end
    return buildings
end

return Building
