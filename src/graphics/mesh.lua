-- Mesh definitions

local mesh = {}

function mesh.createCube()
    -- Define vertices of a cube
    local vertices = {
        -- Front face
        {pos = {-1, -1, 1}, uv = {0, 1}},
        {pos = {1, -1, 1}, uv = {1, 1}},
        {pos = {1, 1, 1}, uv = {1, 0}},
        {pos = {-1, 1, 1}, uv = {0, 0}},

        -- Back face
        {pos = {1, -1, -1}, uv = {0, 1}},
        {pos = {-1, -1, -1}, uv = {1, 1}},
        {pos = {-1, 1, -1}, uv = {1, 0}},
        {pos = {1, 1, -1}, uv = {0, 0}},

        -- Top face
        {pos = {-1, 1, 1}, uv = {0, 1}},
        {pos = {1, 1, 1}, uv = {1, 1}},
        {pos = {1, 1, -1}, uv = {1, 0}},
        {pos = {-1, 1, -1}, uv = {0, 0}},

        -- Bottom face
        {pos = {-1, -1, -1}, uv = {0, 1}},
        {pos = {1, -1, -1}, uv = {1, 1}},
        {pos = {1, -1, 1}, uv = {1, 0}},
        {pos = {-1, -1, 1}, uv = {0, 0}},

        -- Right face
        {pos = {1, -1, 1}, uv = {0, 1}},
        {pos = {1, -1, -1}, uv = {1, 1}},
        {pos = {1, 1, -1}, uv = {1, 0}},
        {pos = {1, 1, 1}, uv = {0, 0}},

        -- Left face
        {pos = {-1, -1, -1}, uv = {0, 1}},
        {pos = {-1, -1, 1}, uv = {1, 1}},
        {pos = {-1, 1, 1}, uv = {1, 0}},
        {pos = {-1, 1, -1}, uv = {0, 0}}
    }

    -- Define triangles (indices into vertices array) - CCW winding
    local triangles = {
        -- Front face
        {1, 3, 2}, {1, 4, 3},
        -- Back face
        {5, 7, 6}, {5, 8, 7},
        -- Top face
        {9, 11, 10}, {9, 12, 11},
        -- Bottom face
        {13, 15, 14}, {13, 16, 15},
        -- Right face
        {17, 19, 18}, {17, 20, 19},
        -- Left face
        {21, 23, 22}, {21, 24, 23}
    }

    return {
        vertices = vertices,
        triangles = triangles
    }
end

function mesh.createSphere(rings, segments)
    -- Create a low-poly UV sphere
    rings = rings or 8
    segments = segments or 8

    local vertices = {}
    local triangles = {}

    -- Generate vertices
    for ring = 0, rings do
        local theta = ring * math.pi / rings
        local sinTheta = math.sin(theta)
        local cosTheta = math.cos(theta)

        for seg = 0, segments do
            local phi = seg * 2 * math.pi / segments
            local sinPhi = math.sin(phi)
            local cosPhi = math.cos(phi)

            local x = cosPhi * sinTheta
            local y = cosTheta
            local z = sinPhi * sinTheta

            local u = seg / segments
            local v = ring / rings

            table.insert(vertices, {
                pos = {x, y, z},
                uv = {u, v}
            })
        end
    end

    -- Generate triangles
    for ring = 0, rings - 1 do
        for seg = 0, segments - 1 do
            local first = ring * (segments + 1) + seg + 1
            local second = first + segments + 1

            -- Triangle 1
            table.insert(triangles, {first, second, first + 1})
            -- Triangle 2
            table.insert(triangles, {second, second + 1, first + 1})
        end
    end

    return {
        vertices = vertices,
        triangles = triangles
    }
end

function mesh.createPyramid()
    local vertices = {
        -- Base face (facing down)
        {pos = {-0.5, 0, -0.5}, uv = {0, 1}},   -- 1
        {pos = {0.5, 0, 0.5}, uv = {1, 0}},     -- 2
        {pos = {0.5, 0, -0.5}, uv = {1, 1}},    -- 3
        {pos = {-0.5, 0, 0.5}, uv = {0, 0}},    -- 4

        -- Front face
        {pos = {-0.5, 0, -0.5}, uv = {0, 1}},   -- 5
        {pos = {0, 1, 0}, uv = {0.5, 0}},       -- 6
        {pos = {0.5, 0, -0.5}, uv = {1, 1}},    -- 7

        -- Right face
        {pos = {0.5, 0, -0.5}, uv = {0, 1}},    -- 8
        {pos = {0, 1, 0}, uv = {0.5, 0}},       -- 9
        {pos = {0.5, 0, 0.5}, uv = {1, 1}},     -- 10

        -- Back face
        {pos = {0.5, 0, 0.5}, uv = {0, 1}},     -- 11
        {pos = {0, 1, 0}, uv = {0.5, 0}},       -- 12
        {pos = {-0.5, 0, 0.5}, uv = {1, 1}},    -- 13

        -- Left face
        {pos = {-0.5, 0, 0.5}, uv = {0, 1}},    -- 14
        {pos = {0, 1, 0}, uv = {0.5, 0}},       -- 15
        {pos = {-0.5, 0, -0.5}, uv = {1, 1}}    -- 16
    }

    -- Define triangles with CW winding (opposite of cube because pyramid geometry is inverted)
    local triangles = {
        -- Base (two triangles)
        {1, 3, 2}, {1, 2, 4},
        -- Front
        {5, 7, 6},
        -- Right
        {8, 10, 9},
        -- Back
        {11, 13, 12},
        -- Left
        {14, 16, 15}
    }

    return {
        vertices = vertices,
        triangles = triangles
    }
end

return mesh
