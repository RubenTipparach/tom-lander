-- Minimap Module
-- Handles minimap rendering with terrain, buildings, and player position
-- Ported from Picotron version for Love2D

local Minimap = {}

-- Configuration
Minimap.SIZE = 48  -- 48x48 pixels
Minimap.X = 0      -- Will be set dynamically based on render width
Minimap.Y = 10
Minimap.BORDER = 2

-- Terrain color scheme (RGB 0-255)
-- Heights 1-32+ mapped to colors (darker to lighter)
Minimap.TERRAIN_COLORS = {
    {60, 60, 60},      -- Very low
    {80, 80, 80},      -- Low
    {100, 100, 80},    -- Low-mid
    {80, 120, 60},     -- Mid (grass-like)
    {100, 140, 80},    -- Mid-high
    {120, 120, 100},   -- High (rocky)
    {140, 140, 120},   -- Very high
    {160, 160, 140},   -- Peak
}
Minimap.WATER_COLOR = {30, 50, 100}  -- Dark blue for water

-- Cached minimap terrain data (generated once)
local terrain_cache = nil
local cache_width = 0
local cache_height = 0

-- Generate terrain cache from heightmap
function Minimap.generate_terrain_cache(heightmap)
    if not heightmap then
        return nil
    end

    -- Use heightmap MAP_SIZE
    local map_size = heightmap.MAP_SIZE or 128
    cache_width = map_size
    cache_height = map_size

    -- Create cache as 2D array of colors
    terrain_cache = {}

    for z = 0, map_size - 1 do
        for x = 0, map_size - 1 do
            -- Sample height at this tile
            local world_x, world_z = heightmap.tile_to_world(x, z)
            local height = heightmap.get_height(world_x, world_z)

            -- Map height to color
            local color
            if height == 0 then
                color = Minimap.WATER_COLOR
            else
                -- Heights 0-16 mapped to color indices 1-8
                local color_idx = math.floor(height / 2) + 1
                color_idx = math.max(1, math.min(#Minimap.TERRAIN_COLORS, color_idx))
                color = Minimap.TERRAIN_COLORS[color_idx]
            end

            local idx = z * map_size + x + 1
            terrain_cache[idx] = color
        end
    end

    return terrain_cache
end

-- Set position based on render dimensions
function Minimap.set_position(render_width, render_height)
    Minimap.X = render_width - Minimap.SIZE - 6
    Minimap.Y = 10
end

-- Convert world coordinates to minimap screen coordinates
function Minimap.world_to_minimap(world_x, world_z, heightmap)
    local tile_size = heightmap and heightmap.TILE_SIZE or 4
    local map_size = heightmap and heightmap.MAP_SIZE or 128

    -- Pixels per world unit
    local pixels_per_world_unit = Minimap.SIZE / (map_size * tile_size)

    -- Convert to minimap coordinates (centered)
    local minimap_x = Minimap.X + Minimap.SIZE / 2 + world_x * pixels_per_world_unit
    local minimap_y = Minimap.Y + Minimap.SIZE / 2 + world_z * pixels_per_world_unit

    -- Check bounds
    if minimap_x < Minimap.X or minimap_x > Minimap.X + Minimap.SIZE or
       minimap_y < Minimap.Y or minimap_y > Minimap.Y + Minimap.SIZE then
        return nil, nil
    end

    return minimap_x, minimap_y
end

-- Draw the minimap using the software renderer
function Minimap.draw(renderer, heightmap, ship, landing_pads, cargo_items, mission_target, race_checkpoints, current_checkpoint)
    -- Generate cache on first draw
    if not terrain_cache and heightmap then
        Minimap.generate_terrain_cache(heightmap)
    end

    local tile_size = heightmap and heightmap.TILE_SIZE or 4
    local map_size = heightmap and heightmap.MAP_SIZE or 128
    local pixels_per_world_unit = Minimap.SIZE / (map_size * tile_size)

    -- Draw border (black)
    for y = Minimap.Y - Minimap.BORDER, Minimap.Y + Minimap.SIZE + Minimap.BORDER - 1 do
        for x = Minimap.X - Minimap.BORDER, Minimap.X + Minimap.SIZE + Minimap.BORDER - 1 do
            if x < Minimap.X or x >= Minimap.X + Minimap.SIZE or
               y < Minimap.Y or y >= Minimap.Y + Minimap.SIZE then
                renderer.drawPixel(x, y, 0, 0, 0)
            end
        end
    end

    -- Draw terrain from cache
    if terrain_cache then
        for py = 0, Minimap.SIZE - 1 do
            for px = 0, Minimap.SIZE - 1 do
                -- Sample from cache (scale minimap from cache)
                local cache_x = math.floor(px * cache_width / Minimap.SIZE)
                local cache_z = math.floor(py * cache_height / Minimap.SIZE)
                local cache_idx = cache_z * cache_width + cache_x + 1

                local color = terrain_cache[cache_idx]
                if color then
                    renderer.drawPixel(Minimap.X + px, Minimap.Y + py, color[1], color[2], color[3])
                end
            end
        end
    else
        -- Fallback: solid dark background
        for py = 0, Minimap.SIZE - 1 do
            for px = 0, Minimap.SIZE - 1 do
                renderer.drawPixel(Minimap.X + px, Minimap.Y + py, 20, 30, 50)
            end
        end
    end

    -- Draw landing pads (white squares)
    if landing_pads then
        local pads = landing_pads.get_all and landing_pads.get_all() or landing_pads
        for _, pad in ipairs(pads) do
            local px = Minimap.X + Minimap.SIZE / 2 + pad.x * pixels_per_world_unit
            local py = Minimap.Y + Minimap.SIZE / 2 + pad.z * pixels_per_world_unit

            -- 2x2 white square
            for dy = -1, 0 do
                for dx = -1, 0 do
                    renderer.drawPixel(math.floor(px + dx), math.floor(py + dy), 255, 255, 255)
                end
            end
        end
    end

    -- Draw cargo (blinking orange)
    if cargo_items then
        local blink = (love.timer.getTime() * 2) % 1 < 0.5
        if blink then
            for _, cargo in ipairs(cargo_items) do
                if cargo.state ~= "attached" and cargo.state ~= "delivered" then
                    local cx = Minimap.X + Minimap.SIZE / 2 + cargo.x * pixels_per_world_unit
                    local cy = Minimap.Y + Minimap.SIZE / 2 + cargo.z * pixels_per_world_unit

                    -- 2x2 orange square
                    for dy = -1, 0 do
                        for dx = -1, 0 do
                            renderer.drawPixel(math.floor(cx + dx), math.floor(cy + dy), 255, 140, 0)
                        end
                    end
                end
            end
        end
    end

    -- Draw mission target (blinking green diamond) - skip for race mode (we draw checkpoints instead)
    if mission_target and not race_checkpoints then
        local blink = (love.timer.getTime() * 3) % 1 < 0.7  -- Faster blink, mostly on
        if blink then
            local tx = Minimap.X + Minimap.SIZE / 2 + mission_target.x * pixels_per_world_unit
            local ty = Minimap.Y + Minimap.SIZE / 2 + mission_target.z * pixels_per_world_unit

            -- Diamond shape (4 pixels in cross pattern)
            renderer.drawPixel(math.floor(tx), math.floor(ty - 1), 0, 255, 0)  -- Top
            renderer.drawPixel(math.floor(tx - 1), math.floor(ty), 0, 255, 0)  -- Left
            renderer.drawPixel(math.floor(tx + 1), math.floor(ty), 0, 255, 0)  -- Right
            renderer.drawPixel(math.floor(tx), math.floor(ty + 1), 0, 255, 0)  -- Bottom
            renderer.drawPixel(math.floor(tx), math.floor(ty), 0, 255, 0)      -- Center
        end
    end

    -- Draw race checkpoints
    if race_checkpoints then
        for i, cp in ipairs(race_checkpoints) do
            local cx = Minimap.X + Minimap.SIZE / 2 + cp.x * pixels_per_world_unit
            local cy = Minimap.Y + Minimap.SIZE / 2 + cp.z * pixels_per_world_unit

            -- Color based on checkpoint state
            local r, g, b
            if i == current_checkpoint then
                -- Current checkpoint: blinking yellow
                local blink = (love.timer.getTime() * 4) % 1 < 0.7
                if blink then
                    r, g, b = 255, 200, 0
                else
                    r, g, b = 180, 140, 0
                end
            elseif i < current_checkpoint then
                -- Passed checkpoint: dim green
                r, g, b = 60, 120, 60
            else
                -- Future checkpoint: dim cyan
                r, g, b = 60, 100, 140
            end

            -- Draw checkpoint marker (small cross)
            renderer.drawPixel(math.floor(cx), math.floor(cy), r, g, b)
            renderer.drawPixel(math.floor(cx - 1), math.floor(cy), r, g, b)
            renderer.drawPixel(math.floor(cx + 1), math.floor(cy), r, g, b)
            renderer.drawPixel(math.floor(cx), math.floor(cy - 1), r, g, b)
            renderer.drawPixel(math.floor(cx), math.floor(cy + 1), r, g, b)
        end
    end

    -- Draw player position (yellow dot)
    if ship then
        local player_x = Minimap.X + Minimap.SIZE / 2 + ship.x * pixels_per_world_unit
        local player_y = Minimap.Y + Minimap.SIZE / 2 + ship.z * pixels_per_world_unit

        -- 3x3 yellow dot
        for dy = -1, 1 do
            for dx = -1, 1 do
                -- Skip corners for circular-ish shape
                if not (math.abs(dx) == 1 and math.abs(dy) == 1) then
                    renderer.drawPixel(math.floor(player_x + dx), math.floor(player_y + dy), 255, 255, 0)
                end
            end
        end
    end
end

return Minimap
