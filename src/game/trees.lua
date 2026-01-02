-- Trees Module
-- Generates and renders trees using grid-based distribution
-- Ported from Picotron version

local Constants = require("constants")
local obj_loader = require("obj_loader")
local config = require("config")

local Trees = {}

-- Configuration (matching Picotron)
local CELL_SIZE = 20  -- 20m x 20m cells
local MAX_TREES_PER_CELL = 3
local MAP_RANGE = 100  -- Place trees in 200x200m area (-100 to 100)
local TREE_ATTEMPTS = 150  -- Try to place up to 150 trees

-- Tree mesh - loaded from OBJ file
local tree_mesh = nil

-- Seeded random function (deterministic)
local function seeded_random(idx, component, seed)
    local x = math.sin(idx * 12.9898 + component * 78.233 + seed) * 43758.5453
    return x - math.floor(x)
end

-- Tree instances
local trees = {}

-- Load tree mesh from OBJ file
local function load_tree_mesh()
    if tree_mesh then return true end

    local success, result = pcall(function()
        return obj_loader.load("assets/tree.obj")
    end)

    if success and result then
        tree_mesh = result
        print("Loaded tree mesh: " .. #result.vertices .. " vertices, " .. #result.triangles .. " triangles")
        return true
    else
        print("Warning: Could not load tree.obj, trees will not be rendered")
        return false
    end
end

-- Generate trees based on heightmap
function Trees.generate(Heightmap)
    trees = {}
    local tree_grid = {}

    -- Load tree mesh
    load_tree_mesh()

    for tree_idx = 1, TREE_ATTEMPTS do
        local x = (seeded_random(tree_idx, 0, 1234) - 0.5) * MAP_RANGE * 2
        local z = (seeded_random(tree_idx, 1, 1234) - 0.5) * MAP_RANGE * 2

        -- Determine which cell this tree falls into
        local cell_x = math.floor(x / CELL_SIZE)
        local cell_z = math.floor(z / CELL_SIZE)
        local cell_key = cell_x .. "," .. cell_z

        -- Initialize cell counter if needed
        if not tree_grid[cell_key] then
            tree_grid[cell_key] = 0
        end

        -- Only place tree if cell has less than max trees
        if tree_grid[cell_key] < MAX_TREES_PER_CELL then
            -- Get height from heightmap
            local tree_height = Heightmap.get_height(x, z)

            -- Don't place trees on water (height = 0)
            if tree_height > 0 then
                table.insert(trees, {
                    x = x,
                    y = tree_height,
                    z = z
                })
                tree_grid[cell_key] = tree_grid[cell_key] + 1
            end
        end
    end

    print("Generated " .. #trees .. " trees across the map")
    return trees
end

-- Draw all trees with distance culling
function Trees.draw(renderer, cam_x, cam_y, cam_z)
    if not tree_mesh then return end

    local texData = Constants.getTextureData(Constants.SPRITE_TREES)
    if not texData then return end

    local render_dist_sq = config.RENDER_DISTANCE * config.RENDER_DISTANCE

    for _, tree in ipairs(trees) do
        -- Distance culling - skip trees beyond render distance
        local dx = tree.x - cam_x
        local dz = tree.z - cam_z
        local dist_sq = dx * dx + dz * dz

        if dist_sq < render_dist_sq then
            -- Calculate fog factor for entire tree (per-mesh fog)
            local distance = math.sqrt(dist_sq)
            local fogFactor = renderer.calcFogFactor(distance)

            -- Draw each triangle of the tree mesh (OBJ loader format)
            for _, tri in ipairs(tree_mesh.triangles) do
                local v1 = tree_mesh.vertices[tri[1]]
                local v2 = tree_mesh.vertices[tri[2]]
                local v3 = tree_mesh.vertices[tri[3]]

                -- Offset vertices by tree position
                renderer.drawTriangle3D(
                    {pos = {v1.pos[1] + tree.x, v1.pos[2] + tree.y, v1.pos[3] + tree.z}, uv = v1.uv},
                    {pos = {v2.pos[1] + tree.x, v2.pos[2] + tree.y, v2.pos[3] + tree.z}, uv = v2.uv},
                    {pos = {v3.pos[1] + tree.x, v3.pos[2] + tree.y, v3.pos[3] + tree.z}, uv = v3.uv},
                    nil,
                    texData,
                    nil,  -- brightness
                    fogFactor
                )
            end
        end
    end
end

-- Get all trees (for minimap etc.)
function Trees.get_all()
    return trees
end

-- Get tree count
function Trees.get_count()
    return #trees
end

return Trees
