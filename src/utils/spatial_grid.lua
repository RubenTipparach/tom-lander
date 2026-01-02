-- Simple spatial grid for broad-phase culling
-- Reduces number of frustum culling tests for large scenes

local spatial_grid = {}

function spatial_grid.new(cellSize)
    return {
        cellSize = cellSize or 10,
        cells = {}
    }
end

-- Get cell key for position
local function getCellKey(grid, x, y, z)
    local cx = math.floor(x / grid.cellSize)
    local cy = math.floor(y / grid.cellSize)
    local cz = math.floor(z / grid.cellSize)
    return cx .. "," .. cy .. "," .. cz
end

-- Add object to grid
function spatial_grid.add(grid, object, x, y, z)
    local key = getCellKey(grid, x, y, z)
    if not grid.cells[key] then
        grid.cells[key] = {}
    end
    table.insert(grid.cells[key], object)
end

-- Clear grid
function spatial_grid.clear(grid)
    grid.cells = {}
end

-- Get potentially visible objects based on camera frustum
-- Returns objects in cells that could intersect the view frustum
function spatial_grid.query(grid, camX, camY, camZ, radius)
    local visible = {}
    local checked = {}

    -- Calculate which cells the camera frustum could touch
    local minCellX = math.floor((camX - radius) / grid.cellSize)
    local maxCellX = math.floor((camX + radius) / grid.cellSize)
    local minCellY = math.floor((camY - radius) / grid.cellSize)
    local maxCellY = math.floor((camY + radius) / grid.cellSize)
    local minCellZ = math.floor((camZ - radius) / grid.cellSize)
    local maxCellZ = math.floor((camZ + radius) / grid.cellSize)

    -- Gather all objects in potentially visible cells
    for cx = minCellX, maxCellX do
        for cy = minCellY, maxCellY do
            for cz = minCellZ, maxCellZ do
                local key = cx .. "," .. cy .. "," .. cz
                if grid.cells[key] then
                    for _, obj in ipairs(grid.cells[key]) do
                        if not checked[obj] then
                            table.insert(visible, obj)
                            checked[obj] = true
                        end
                    end
                end
            end
        end
    end

    return visible
end

return spatial_grid
