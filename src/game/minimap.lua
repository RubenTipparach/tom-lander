-- Minimap Module
-- Handles minimap rendering with terrain, buildings, and player position
-- Supports scrolling viewport for tall maps (like canyon)

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

-- Viewport state (for scrolling on tall maps)
local viewport_center_z = 0  -- Center of viewport in tile coordinates
local viewport_size = 128    -- Viewport size in tiles (square)

-- Generate terrain cache from heightmap
function Minimap.generate_terrain_cache(heightmap)
    if not heightmap then
        return nil
    end

    -- Use heightmap dimensions (supports non-square maps)
    local map_width = heightmap.MAP_WIDTH or heightmap.MAP_SIZE or 128
    local map_height = heightmap.MAP_HEIGHT or heightmap.MAP_SIZE or 128
    cache_width = map_width
    cache_height = map_height

    -- Set viewport size to map width (square viewport)
    viewport_size = map_width
    -- Initialize viewport center to middle of map
    viewport_center_z = map_height / 2

    -- Create cache as 2D array of colors
    terrain_cache = {}

    -- Check if map has water
    local map_config = heightmap.get_map_config and heightmap.get_map_config()
    local has_water = not map_config or map_config.has_water ~= false

    for z = 0, map_height - 1 do
        for x = 0, map_width - 1 do
            -- Sample height at this tile
            local world_x, world_z = heightmap.tile_to_world(x, z)
            local height = heightmap.get_height(world_x, world_z)

            -- Map height to color
            local color
            if height == 0 and has_water then
                color = Minimap.WATER_COLOR
            elseif height == 0 then
                -- No water - use lowest terrain color (sand/ground)
                color = Minimap.TERRAIN_COLORS[1]
            else
                -- Heights 0-16 mapped to color indices 1-8
                local color_idx = math.floor(height / 2) + 1
                color_idx = math.max(1, math.min(#Minimap.TERRAIN_COLORS, color_idx))
                color = Minimap.TERRAIN_COLORS[color_idx]
            end

            local idx = z * map_width + x + 1
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

-- Update viewport to follow ship (for tall maps)
local function update_viewport(ship_z, heightmap)
    if not heightmap then return end

    local map_height = heightmap.MAP_HEIGHT or heightmap.MAP_SIZE or 128
    local tile_size = heightmap.TILE_SIZE or 4

    -- Convert ship world Z to tile coordinate
    local half_world_z = (map_height * tile_size) / 2
    local ship_tile_z = (ship_z + half_world_z) / tile_size

    -- Only scroll if map is taller than viewport
    if map_height > viewport_size then
        -- Clamp viewport center so it stays within map bounds
        local half_viewport = viewport_size / 2
        local min_center = half_viewport
        local max_center = map_height - half_viewport

        -- Smoothly follow ship
        viewport_center_z = math.max(min_center, math.min(max_center, ship_tile_z))
    else
        -- Map fits in viewport, center it
        viewport_center_z = map_height / 2
    end
end

-- Convert world coordinates to minimap screen coordinates (with viewport)
function Minimap.world_to_minimap(world_x, world_z, heightmap)
    local tile_size = heightmap and heightmap.TILE_SIZE or 4
    local map_width = heightmap and heightmap.MAP_WIDTH or heightmap and heightmap.MAP_SIZE or 128
    local map_height = heightmap and heightmap.MAP_HEIGHT or heightmap and heightmap.MAP_SIZE or 128

    -- Convert world to tile coordinates
    local half_world_x = (map_width * tile_size) / 2
    local half_world_z = (map_height * tile_size) / 2
    local tile_x = (world_x + half_world_x) / tile_size
    local tile_z = (world_z + half_world_z) / tile_size

    -- Calculate position relative to viewport
    local viewport_min_z = viewport_center_z - viewport_size / 2
    local rel_x = tile_x
    local rel_z = tile_z - viewport_min_z

    -- Scale to minimap pixels
    local pixels_per_tile = Minimap.SIZE / viewport_size
    local minimap_x = Minimap.X + rel_x * pixels_per_tile
    local minimap_y = Minimap.Y + rel_z * pixels_per_tile

    -- Check bounds
    if minimap_x < Minimap.X or minimap_x > Minimap.X + Minimap.SIZE or
       minimap_y < Minimap.Y or minimap_y > Minimap.Y + Minimap.SIZE then
        return nil, nil
    end

    return minimap_x, minimap_y
end

-- Draw the minimap using the software renderer
function Minimap.draw(renderer, heightmap, ship, landing_pads, cargo_items, mission_target, race_checkpoints, current_checkpoint, enemies)
    -- Generate cache on first draw
    if not terrain_cache and heightmap then
        Minimap.generate_terrain_cache(heightmap)
    end

    -- Update viewport to follow ship
    if ship then
        update_viewport(ship.z, heightmap)
    end

    local tile_size = heightmap and heightmap.TILE_SIZE or 4
    local map_width = heightmap and heightmap.MAP_WIDTH or heightmap and heightmap.MAP_SIZE or 128
    local map_height = heightmap and heightmap.MAP_HEIGHT or heightmap and heightmap.MAP_SIZE or 128

    -- Calculate viewport bounds in tile coordinates
    local viewport_min_z = viewport_center_z - viewport_size / 2
    local viewport_max_z = viewport_center_z + viewport_size / 2

    -- Pixels per tile for this viewport
    local pixels_per_tile = Minimap.SIZE / viewport_size

    -- Draw border (black)
    for y = Minimap.Y - Minimap.BORDER, Minimap.Y + Minimap.SIZE + Minimap.BORDER - 1 do
        for x = Minimap.X - Minimap.BORDER, Minimap.X + Minimap.SIZE + Minimap.BORDER - 1 do
            if x < Minimap.X or x >= Minimap.X + Minimap.SIZE or
               y < Minimap.Y or y >= Minimap.Y + Minimap.SIZE then
                renderer.drawPixel(x, y, 0, 0, 0)
            end
        end
    end

    -- Draw terrain from cache (only visible portion)
    if terrain_cache then
        for py = 0, Minimap.SIZE - 1 do
            for px = 0, Minimap.SIZE - 1 do
                -- Convert minimap pixel to tile coordinate
                local cache_x = math.floor(px * viewport_size / Minimap.SIZE)
                local cache_z = math.floor(py * viewport_size / Minimap.SIZE + viewport_min_z)

                -- Clamp to valid cache range
                cache_x = math.max(0, math.min(cache_width - 1, cache_x))
                cache_z = math.max(0, math.min(cache_height - 1, cache_z))

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

    -- Helper function to convert world to minimap coords (using viewport)
    local function world_to_screen(wx, wz)
        local half_world_x = (map_width * tile_size) / 2
        local half_world_z = (map_height * tile_size) / 2
        local tile_x = (wx + half_world_x) / tile_size
        local tile_z = (wz + half_world_z) / tile_size

        local rel_x = tile_x
        local rel_z = tile_z - viewport_min_z

        local sx = Minimap.X + rel_x * pixels_per_tile
        local sy = Minimap.Y + rel_z * pixels_per_tile

        -- Check bounds
        if sx < Minimap.X or sx > Minimap.X + Minimap.SIZE or
           sy < Minimap.Y or sy > Minimap.Y + Minimap.SIZE then
            return nil, nil
        end

        return sx, sy
    end

    -- Draw landing pads (white squares)
    if landing_pads then
        local pads = landing_pads.get_all and landing_pads.get_all() or landing_pads
        for _, pad in ipairs(pads) do
            local px, py = world_to_screen(pad.x, pad.z)
            if px then
                -- 2x2 white square
                for dy = -1, 0 do
                    for dx = -1, 0 do
                        renderer.drawPixel(math.floor(px + dx), math.floor(py + dy), 255, 255, 255)
                    end
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
                    local cx, cy = world_to_screen(cargo.x, cargo.z)
                    if cx then
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
    end

    -- Draw mission target (blinking green diamond) - skip for race mode (we draw checkpoints instead)
    if mission_target and not race_checkpoints then
        local blink = (love.timer.getTime() * 3) % 1 < 0.7  -- Faster blink, mostly on
        if blink then
            local tx, ty = world_to_screen(mission_target.x, mission_target.z)
            if tx then
                -- Diamond shape (4 pixels in cross pattern)
                renderer.drawPixel(math.floor(tx), math.floor(ty - 1), 0, 255, 0)  -- Top
                renderer.drawPixel(math.floor(tx - 1), math.floor(ty), 0, 255, 0)  -- Left
                renderer.drawPixel(math.floor(tx + 1), math.floor(ty), 0, 255, 0)  -- Right
                renderer.drawPixel(math.floor(tx), math.floor(ty + 1), 0, 255, 0)  -- Bottom
                renderer.drawPixel(math.floor(tx), math.floor(ty), 0, 255, 0)      -- Center
            end
        end
    end

    -- Draw race checkpoints (only current and next to reduce clutter)
    if race_checkpoints then
        for i, cp in ipairs(race_checkpoints) do
            -- Only show current checkpoint and the next one
            if i == current_checkpoint or i == current_checkpoint + 1 then
                local cx, cy = world_to_screen(cp.x, cp.z)
                if cx then
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
                    else
                        -- Next checkpoint: dim cyan
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
        end
    end

    -- Draw enemies (red blinking dots)
    if enemies then
        local blink = (love.timer.getTime() * 3) % 1 < 0.7  -- Fast blink, mostly on
        if blink then
            for _, enemy in ipairs(enemies) do
                local ex, ey = world_to_screen(enemy.x, enemy.z)
                if ex then
                    -- 2x2 red square
                    for dy = -1, 0 do
                        for dx = -1, 0 do
                            renderer.drawPixel(math.floor(ex + dx), math.floor(ey + dy), 255, 50, 50)
                        end
                    end
                end
            end
        end
    end

    -- Draw player position (yellow dot) - always centered if scrolling
    if ship then
        local player_x, player_y = world_to_screen(ship.x, ship.z)
        if player_x then
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
end

-- Reset terrain cache (call when switching maps)
function Minimap.reset_cache()
    terrain_cache = nil
    cache_width = 0
    cache_height = 0
    viewport_center_z = 0
    viewport_size = 128
end

return Minimap
