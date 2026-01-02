-- Heightmap Terrain System
-- Generates terrain geometry from a 128x128 heightmap PNG
-- Adapted from Picotron version for Love2D

local Constants = require("constants")
local Palette = require("palette")

local Heightmap = {}

-- Configuration (matching Picotron exactly)
Heightmap.MAP_SIZE = 128  -- 128x128 heightmap
Heightmap.TILE_SIZE = 4   -- Size of each terrain quad (1 tile = 4 world units)
Heightmap.HEIGHT_SCALE = 1.0  -- How much each palette index raises the terrain (1.0m per index)
Heightmap.MAX_HEIGHT = 32  -- Maximum height value (palette indices 0-31)

-- Cache for height values
local height_cache = {}

-- Heightmap data - loaded from PNG
local heightmap_data = nil
local heightmap_image_data = nil

-- Initialize heightmap by loading from sprite 64
function Heightmap.init()
    local path = "assets/textures/" .. Constants.SPRITE_HEIGHTMAP .. ".png"

    local success, result = pcall(function()
        return love.image.newImageData(path)
    end)

    if success and result then
        heightmap_image_data = result
        print("Heightmap loaded: " .. result:getWidth() .. "x" .. result:getHeight())
    else
        print("Warning: Could not load heightmap from " .. path .. ", using flat terrain")
        heightmap_image_data = nil
    end
end

-- Get raw height value (palette index 0-31) at a pixel coordinate using reverse palette lookup
local function get_pixel_height_index(px, pz)
    if not heightmap_image_data then
        return 0
    end

    -- Clamp to valid range
    px = math.max(0, math.min(Heightmap.MAP_SIZE - 1, math.floor(px)))
    pz = math.max(0, math.min(Heightmap.MAP_SIZE - 1, math.floor(pz)))

    -- Get pixel color (Love2D returns 0.0-1.0, convert to 0-255)
    local r, g, b, a = heightmap_image_data:getPixel(px, pz)
    local r8 = math.floor(r * 255 + 0.5)
    local g8 = math.floor(g * 255 + 0.5)
    local b8 = math.floor(b * 255 + 0.5)

    -- Use Palette module for reverse lookup
    return Palette.getIndex(r8, g8, b8)
end

-- Get height value at a pixel coordinate (scaled for world space)
local function get_pixel_height(px, pz)
    return get_pixel_height_index(px, pz) * Heightmap.HEIGHT_SCALE
end

-- Get height at a specific world position using bilinear interpolation
function Heightmap.get_height(world_x, world_z)
    -- Initialize on first call if needed
    if not heightmap_image_data then
        Heightmap.init()
    end

    if not heightmap_image_data then
        return 0  -- Flat if no heightmap
    end

    -- Convert world coordinates to heightmap coordinates
    local half_world = (Heightmap.MAP_SIZE * Heightmap.TILE_SIZE) / 2
    local map_x_f = (world_x + half_world) / Heightmap.TILE_SIZE
    local map_z_f = (world_z + half_world) / Heightmap.TILE_SIZE

    -- Get the four surrounding heightmap pixels
    local x0 = math.floor(map_x_f)
    local z0 = math.floor(map_z_f)
    local x1 = x0 + 1
    local z1 = z0 + 1

    -- Clamp to map bounds
    if x0 < 0 or x1 >= Heightmap.MAP_SIZE or z0 < 0 or z1 >= Heightmap.MAP_SIZE then
        return 0  -- Outside map bounds = sea level
    end

    -- Get heights at four corners
    local h00 = get_pixel_height(x0, z0)
    local h10 = get_pixel_height(x1, z0)
    local h01 = get_pixel_height(x0, z1)
    local h11 = get_pixel_height(x1, z1)

    -- Calculate interpolation factors (0-1 within the pixel)
    local fx = map_x_f - x0
    local fz = map_z_f - z0

    -- Bilinear interpolation
    local h0 = h00 * (1 - fx) + h10 * fx
    local h1 = h01 * (1 - fx) + h11 * fx
    local height = h0 * (1 - fz) + h1 * fz

    return height
end

-- Generate terrain mesh around camera position
function Heightmap.generate_terrain(cam_x, cam_z, grid_count, render_distance)
    render_distance = render_distance or 20
    if not grid_count then
        grid_count = math.floor(render_distance / Heightmap.TILE_SIZE) * 2
        grid_count = math.min(grid_count, 32)
    end

    local verts = {}
    local faces = {}

    local half_size = grid_count * Heightmap.TILE_SIZE / 2

    -- Snap camera position to grid
    local center_x = math.floor(cam_x / Heightmap.TILE_SIZE) * Heightmap.TILE_SIZE
    local center_z = math.floor(cam_z / Heightmap.TILE_SIZE) * Heightmap.TILE_SIZE

    -- Create vertices for a (grid_count+1) x (grid_count+1) grid
    for gz = 0, grid_count do
        for gx = 0, grid_count do
            local world_x = center_x + gx * Heightmap.TILE_SIZE - half_size
            local world_z = center_z + gz * Heightmap.TILE_SIZE - half_size

            local height = Heightmap.get_height(world_x, world_z)
            table.insert(verts, {pos = {world_x, height, world_z}})
        end
    end

    -- Create faces with appropriate textures based on height
    -- Uses Picotron's palette index thresholds: 0=water, 3+=grass, 10+=rocks
    for gz = 0, grid_count - 1 do
        for gx = 0, grid_count - 1 do
            local v1 = gz * (grid_count + 1) + gx + 1
            local v2 = gz * (grid_count + 1) + gx + 2
            local v3 = (gz + 1) * (grid_count + 1) + gx + 2
            local v4 = (gz + 1) * (grid_count + 1) + gx + 1

            -- Get heights (world space)
            local h1 = verts[v1].pos[2]
            local h2 = verts[v2].pos[2]
            local h3 = verts[v3].pos[2]
            local h4 = verts[v4].pos[2]

            local is_flat = (h1 == h2 and h2 == h3 and h3 == h4)

            -- Get world coordinates for this quad
            local world_x1 = center_x + gx * Heightmap.TILE_SIZE - half_size
            local world_z1 = center_z + gz * Heightmap.TILE_SIZE - half_size
            local world_x2 = world_x1 + Heightmap.TILE_SIZE
            local world_z2 = world_z1 + Heightmap.TILE_SIZE

            -- Convert to tile coordinates
            local tile_x1, tile_z1 = Heightmap.world_to_tile(world_x1, world_z1)
            local tile_x2, tile_z2 = Heightmap.world_to_tile(world_x2, world_z2)

            -- Sample raw height indices (0-31) at all 4 corners
            local height_indices = {}
            if tile_x1 >= 0 and tile_x1 < Heightmap.MAP_SIZE and tile_z1 >= 0 and tile_z1 < Heightmap.MAP_SIZE then
                table.insert(height_indices, get_pixel_height_index(tile_x1, tile_z1))
            end
            if tile_x2 >= 0 and tile_x2 < Heightmap.MAP_SIZE and tile_z1 >= 0 and tile_z1 < Heightmap.MAP_SIZE then
                table.insert(height_indices, get_pixel_height_index(tile_x2, tile_z1))
            end
            if tile_x2 >= 0 and tile_x2 < Heightmap.MAP_SIZE and tile_z2 >= 0 and tile_z2 < Heightmap.MAP_SIZE then
                table.insert(height_indices, get_pixel_height_index(tile_x2, tile_z2))
            end
            if tile_x1 >= 0 and tile_x1 < Heightmap.MAP_SIZE and tile_z2 >= 0 and tile_z2 < Heightmap.MAP_SIZE then
                table.insert(height_indices, get_pixel_height_index(tile_x1, tile_z2))
            end

            -- For slopes, use the LOWEST height index; for flat areas, use the height value
            local height_value = 0
            if #height_indices > 0 then
                if is_flat then
                    height_value = height_indices[1]
                else
                    height_value = height_indices[1]
                    for _, h in ipairs(height_indices) do
                        if h < height_value then
                            height_value = h
                        end
                    end
                end
            end

            -- Choose sprite based on palette index (matching Picotron thresholds)
            local sprite_id
            local is_water = (is_flat and height_value == 0)

            if is_water then
                sprite_id = Constants.SPRITE_WATER
            elseif height_value >= 10 then
                sprite_id = Constants.SPRITE_ROCKS
            elseif height_value >= 3 then
                sprite_id = Constants.SPRITE_GRASS
            else
                sprite_id = Constants.SPRITE_GROUND
            end

            -- Add faces with UV coordinates
            table.insert(faces, {
                indices = {v1, v2, v3},
                sprite = sprite_id,
                uvs = {{0, 0}, {1, 0}, {1, 1}}
            })
            table.insert(faces, {
                indices = {v1, v3, v4},
                sprite = sprite_id,
                uvs = {{0, 0}, {1, 1}, {0, 1}}
            })
        end
    end

    return verts, faces
end

-- Draw terrain using the renderer
function Heightmap.draw(renderer, cam_x, cam_z, grid_count, render_distance)
    local verts, faces = Heightmap.generate_terrain(cam_x, cam_z, grid_count, render_distance)

    -- Animate water: swap between SPRITE_WATER and SPRITE_WATER2 every 0.5 seconds
    local water_frame = math.floor(love.timer.getTime() * 2) % 2
    local water_sprite = water_frame == 0 and Constants.SPRITE_WATER or Constants.SPRITE_WATER2

    for _, face in ipairs(faces) do
        -- Use animated water sprite for water faces
        local sprite_id = face.sprite
        if sprite_id == Constants.SPRITE_WATER or sprite_id == Constants.SPRITE_WATER2 then
            sprite_id = water_sprite
        end

        local texData = Constants.getTextureData(sprite_id)
        if texData then
            local v1 = verts[face.indices[1]]
            local v2 = verts[face.indices[2]]
            local v3 = verts[face.indices[3]]

            -- Calculate fog factor based on tile center distance from camera
            local center_x = (v1.pos[1] + v2.pos[1] + v3.pos[1]) / 3
            local center_z = (v1.pos[3] + v2.pos[3] + v3.pos[3]) / 3
            local dx = center_x - cam_x
            local dz = center_z - cam_z
            local distance = math.sqrt(dx * dx + dz * dz)
            local fogFactor = renderer.calcFogFactor(distance)

            renderer.drawTriangle3D(
                {pos = v1.pos, uv = face.uvs[1]},
                {pos = v2.pos, uv = face.uvs[2]},
                {pos = v3.pos, uv = face.uvs[3]},
                nil,
                texData,
                nil,  -- brightness
                fogFactor
            )
        end
    end
end

-- Convert world coordinates to tile coordinates
function Heightmap.world_to_tile(world_x, world_z)
    local half_world = (Heightmap.MAP_SIZE * Heightmap.TILE_SIZE) / 2
    local tile_x = math.floor((world_x + half_world) / Heightmap.TILE_SIZE)
    local tile_z = math.floor((world_z + half_world) / Heightmap.TILE_SIZE)
    return tile_x, tile_z
end

-- Convert tile coordinates to world coordinates
function Heightmap.tile_to_world(tile_x, tile_z)
    local half_world = (Heightmap.MAP_SIZE * Heightmap.TILE_SIZE) / 2
    local world_x = tile_x * Heightmap.TILE_SIZE - half_world + Heightmap.TILE_SIZE / 2
    local world_z = tile_z * Heightmap.TILE_SIZE - half_world + Heightmap.TILE_SIZE / 2
    return world_x, world_z
end

-- Clear the height cache
function Heightmap.clear_cache()
    height_cache = {}
end

return Heightmap
