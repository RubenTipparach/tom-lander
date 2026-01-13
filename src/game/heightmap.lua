-- Heightmap Terrain System
-- Generates terrain geometry from a 128x128 heightmap PNG
-- Adapted from Picotron version for Love2D

local Constants = require("constants")
local Palette = require("palette")
local config = require("config")

-- Localize math functions
local floor = math.floor
local sqrt = math.sqrt
local min = math.min
local max = math.max

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
    px = max(0, min(Heightmap.MAP_SIZE - 1, floor(px)))
    pz = max(0, min(Heightmap.MAP_SIZE - 1, floor(pz)))

    -- Get pixel color (Love2D returns 0.0-1.0, convert to 0-255)
    local r, g, b, a = heightmap_image_data:getPixel(px, pz)
    local r8 = floor(r * 255 + 0.5)
    local g8 = floor(g * 255 + 0.5)
    local b8 = floor(b * 255 + 0.5)

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
    local x0 = floor(map_x_f)
    local z0 = floor(map_z_f)
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

-- Check if a world position is over water (all surrounding heights are 0)
function Heightmap.is_water(world_x, world_z)
    -- Initialize on first call if needed
    if not heightmap_image_data then
        Heightmap.init()
    end

    if not heightmap_image_data then
        return true  -- No heightmap = water
    end

    -- Convert world coordinates to heightmap coordinates
    local half_world = (Heightmap.MAP_SIZE * Heightmap.TILE_SIZE) / 2
    local map_x_f = (world_x + half_world) / Heightmap.TILE_SIZE
    local map_z_f = (world_z + half_world) / Heightmap.TILE_SIZE

    -- Get the four surrounding heightmap pixels
    local x0 = floor(map_x_f)
    local z0 = floor(map_z_f)
    local x1 = x0 + 1
    local z1 = z0 + 1

    -- Outside map bounds = water
    if x0 < 0 or x1 >= Heightmap.MAP_SIZE or z0 < 0 or z1 >= Heightmap.MAP_SIZE then
        return true
    end

    -- Get height indices at four corners (0 = water level)
    local h00 = get_pixel_height_index(x0, z0)
    local h10 = get_pixel_height_index(x1, z0)
    local h01 = get_pixel_height_index(x0, z1)
    local h11 = get_pixel_height_index(x1, z1)

    -- Water if all four corners are at height 0
    return h00 == 0 and h10 == 0 and h01 == 0 and h11 == 0
end

-- Generate terrain mesh around camera position
-- Returns vertices with per-vertex height index for shader-based texture blending
function Heightmap.generate_terrain(cam_x, cam_z, grid_count, render_distance)
    render_distance = render_distance or 20
    if not grid_count then
        grid_count = floor(render_distance / Heightmap.TILE_SIZE) * 2
        grid_count = min(grid_count, 32)
    end

    local verts = {}
    local faces = {}

    local half_size = grid_count * Heightmap.TILE_SIZE / 2

    -- Snap camera position to grid
    local center_x = floor(cam_x / Heightmap.TILE_SIZE) * Heightmap.TILE_SIZE
    local center_z = floor(cam_z / Heightmap.TILE_SIZE) * Heightmap.TILE_SIZE

    -- Create vertices for a (grid_count+1) x (grid_count+1) grid
    -- Each vertex stores both world position AND raw height index for shader blending
    for gz = 0, grid_count do
        for gx = 0, grid_count do
            local world_x = center_x + gx * Heightmap.TILE_SIZE - half_size
            local world_z = center_z + gz * Heightmap.TILE_SIZE - half_size

            -- Get tile coordinates
            local tile_x, tile_z = Heightmap.world_to_tile(world_x, world_z)

            -- Get raw height index (0-31) for this vertex
            local height_index = 0
            if tile_x >= 0 and tile_x < Heightmap.MAP_SIZE and tile_z >= 0 and tile_z < Heightmap.MAP_SIZE then
                height_index = get_pixel_height_index(tile_x, tile_z)
            end

            local height = height_index * Heightmap.HEIGHT_SCALE
            table.insert(verts, {
                pos = {world_x, height, world_z},
                height_index = height_index  -- Raw palette index for shader
            })
        end
    end

    -- Create faces - now we track per-vertex height indices
    for gz = 0, grid_count - 1 do
        for gx = 0, grid_count - 1 do
            local v1 = gz * (grid_count + 1) + gx + 1
            local v2 = gz * (grid_count + 1) + gx + 2
            local v3 = (gz + 1) * (grid_count + 1) + gx + 2
            local v4 = (gz + 1) * (grid_count + 1) + gx + 1

            -- Get height indices for all 4 corners
            local hi1 = verts[v1].height_index
            local hi2 = verts[v2].height_index
            local hi3 = verts[v3].height_index
            local hi4 = verts[v4].height_index

            -- Check if this is water (all corners at height 0 and flat)
            local is_water = (hi1 == 0 and hi2 == 0 and hi3 == 0 and hi4 == 0)

            -- Add faces with UV coordinates and height indices
            table.insert(faces, {
                indices = {v1, v2, v3},
                height_indices = {hi1, hi2, hi3},
                is_water = is_water,
                uvs = {{0, 0}, {1, 0}, {1, 1}}
            })
            table.insert(faces, {
                indices = {v1, v3, v4},
                height_indices = {hi1, hi3, hi4},
                is_water = is_water,
                uvs = {{0, 0}, {1, 1}, {0, 1}}
            })
        end
    end

    return verts, faces
end

-- Cached terrain data (geometry + textures)
local cached_terrain = nil
local cached_center_x = nil
local cached_center_z = nil
local cached_grid_count = nil
local cached_textures = nil  -- Cached texture data

-- Initialize texture cache
local function init_texture_cache()
    if cached_textures then return end
    cached_textures = {
        water1 = Constants.getTextureData(Constants.SPRITE_WATER),
        water2 = Constants.getTextureData(Constants.SPRITE_WATER2),
        grass = Constants.getTextureData(Constants.SPRITE_GRASS),
        rocks = Constants.getTextureData(Constants.SPRITE_ROCKS),
        ground = Constants.getTextureData(Constants.SPRITE_GROUND),
    }
end

-- Pre-allocated batch array for water (reused each frame to avoid GC)
local batch_water = {}
local terrain_textures_initialized = false

-- Draw terrain using the renderer
-- Land uses terrain shader with height-based texture blending
-- Water uses regular 3D shader with animated textures
function Heightmap.draw(renderer, cam_x, cam_z, grid_count, render_distance, cam_yaw)
    render_distance = render_distance or 20
    if not grid_count then
        grid_count = floor(render_distance / Heightmap.TILE_SIZE) * 2
        grid_count = min(grid_count, 32)  -- Cap at 32x32 grid for performance
    end

    -- Initialize texture cache once
    init_texture_cache()

    -- Initialize terrain textures for shader (once)
    if not terrain_textures_initialized then
        renderer.setTerrainTextures(
            cached_textures.ground,
            cached_textures.grass,
            cached_textures.rocks
        )
        terrain_textures_initialized = true
    end

    -- Snap camera to grid for cache key
    local center_x = floor(cam_x / Heightmap.TILE_SIZE) * Heightmap.TILE_SIZE
    local center_z = floor(cam_z / Heightmap.TILE_SIZE) * Heightmap.TILE_SIZE

    -- Regenerate terrain only if camera moved to a new tile
    if not cached_terrain or cached_center_x ~= center_x or cached_center_z ~= center_z or cached_grid_count ~= grid_count then
        local verts, faces = Heightmap.generate_terrain(cam_x, cam_z, grid_count, render_distance)
        cached_terrain = {verts = verts, faces = faces}
        cached_center_x = center_x
        cached_center_z = center_z
        cached_grid_count = grid_count
    end

    local verts = cached_terrain.verts
    local faces = cached_terrain.faces

    -- Animate water: swap between water1 and water2 every 0.5 seconds
    local water_frame = floor(love.timer.getTime() * 2) % 2
    local tex_water = water_frame == 0 and cached_textures.water1 or cached_textures.water2

    -- Clear water batch (reuse table, just reset count)
    local water_count = 0

    -- Process all faces
    for _, face in ipairs(faces) do
        local v1 = verts[face.indices[1]]
        local v2 = verts[face.indices[2]]
        local v3 = verts[face.indices[3]]

        if face.is_water then
            -- Water uses regular 3D shader batch
            water_count = water_count + 1
            batch_water[water_count] = {
                {pos = v1.pos, uv = face.uvs[1]},
                {pos = v2.pos, uv = face.uvs[2]},
                {pos = v3.pos, uv = face.uvs[3]}
            }
        else
            -- Land uses terrain shader with per-vertex height
            local hi = face.height_indices

            -- Calculate lighting if enabled
            local brightness = 1.0
            if config.GOURAUD_SHADING and renderer.calculateFaceNormal and renderer.calculateVertexBrightness then
                local nx, ny, nz = renderer.calculateFaceNormal(v1.pos, v2.pos, v3.pos)
                brightness = renderer.calculateVertexBrightness(nx, ny, nz)
            end

            renderer.drawTerrainTriangle(
                {pos = v1.pos, uv = face.uvs[1]},
                {pos = v2.pos, uv = face.uvs[2]},
                {pos = v3.pos, uv = face.uvs[3]},
                hi[1], hi[2], hi[3],
                brightness
            )
        end
    end

    -- Trim water batch to actual size
    for i = water_count + 1, #batch_water do batch_water[i] = nil end

    -- Flush terrain first (land), then draw water on top
    renderer.flushTerrain()

    -- Draw water using regular 3D shader
    if water_count > 0 then
        renderer.drawTriangleBatch(batch_water, tex_water, nil)
    end
end

-- Convert world coordinates to tile coordinates
function Heightmap.world_to_tile(world_x, world_z)
    local half_world = (Heightmap.MAP_SIZE * Heightmap.TILE_SIZE) / 2
    local tile_x = floor((world_x + half_world) / Heightmap.TILE_SIZE)
    local tile_z = floor((world_z + half_world) / Heightmap.TILE_SIZE)
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
