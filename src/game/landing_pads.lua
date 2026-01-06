-- Landing Pad System
-- Manages landing pad placement and spawn points
-- Adapted from Picotron version for Love2D

local Constants = require("constants")
local Collision = require("collision")
local obj_loader = require("obj_loader")
local mat4 = require("mat4")
local config = require("config")

local LandingPads = {}

-- List of all landing pads in the world
LandingPads.pads = {}

-- Cached landing pad mesh
local pad_mesh = nil

-- Load or get the landing pad mesh
local function get_pad_mesh()
    if pad_mesh then
        return pad_mesh
    end

    -- Try to load from OBJ
    local success, result = pcall(function()
        return obj_loader.load("assets/landing_pad.obj")
    end)

    if success and result then
        pad_mesh = result
        print("Landing pad mesh loaded")
    else
        -- Fallback: simple flat pad
        pad_mesh = {
            vertices = {
                {pos = {-2, 0, -3}, uv = {0, 0}},
                {pos = {2, 0, -3}, uv = {1, 0}},
                {pos = {2, 0.2, -3}, uv = {1, 0.1}},
                {pos = {-2, 0.2, -3}, uv = {0, 0.1}},
                {pos = {-2, 0, 3}, uv = {0, 1}},
                {pos = {2, 0, 3}, uv = {1, 1}},
                {pos = {2, 0.2, 3}, uv = {1, 0.9}},
                {pos = {-2, 0.2, 3}, uv = {0, 0.9}},
            },
            triangles = {
                -- Top surface
                {4, 3, 7}, {4, 7, 8},
                -- Front
                {1, 2, 3}, {1, 3, 4},
                -- Back
                {6, 5, 8}, {6, 8, 7},
                -- Left
                {5, 1, 4}, {5, 4, 8},
                -- Right
                {2, 6, 7}, {2, 7, 3},
            }
        }
        print("Using fallback landing pad mesh")
    end

    return pad_mesh
end

-- Create a new landing pad
-- config: {id, name, x, z, scale, base_y}
function LandingPads.create_pad(config)
    local id = config.id or (#LandingPads.pads + 1)
    local name = config.name or Constants.LANDING_PAD_NAMES[id] or ("Landing Pad " .. id)
    local x = config.x or 0
    local z = config.z or 0
    local scale = config.scale or 1.0
    local base_y = config.base_y or 0

    local mesh = get_pad_mesh()

    -- Scale mesh vertices and calculate bounds
    local scaled_vertices = {}
    local min_x, max_x = math.huge, -math.huge
    local min_y, max_y = math.huge, -math.huge
    local min_z, max_z = math.huge, -math.huge

    for _, v in ipairs(mesh.vertices) do
        local sx, sy, sz = v.pos[1] * scale, v.pos[2] * scale, v.pos[3] * scale
        table.insert(scaled_vertices, {
            pos = {sx, sy, sz},
            uv = v.uv
        })
        -- Track bounds
        min_x = math.min(min_x, sx)
        max_x = math.max(max_x, sx)
        min_y = math.min(min_y, sy)
        max_y = math.max(max_y, sy)
        min_z = math.min(min_z, sz)
        max_z = math.max(max_z, sz)
    end

    -- Collision dimensions from actual mesh bounds
    -- Height is scaled to 1/4 to match visual landing surface
    local collision_width = max_x - min_x
    local collision_height = (max_y - min_y) * 0.25
    local collision_depth = max_z - min_z

    -- Create collision box centered on pad position
    local collision = Collision.create_box(
        x, base_y, z,
        collision_width, collision_height, collision_depth, 0
    )

    -- Spawn point (above the pad)
    local spawn_y = base_y + collision_height + 0.5

    local pad = {
        id = id,
        name = name,
        x = x,
        y = base_y,
        z = z,
        scale = scale,
        vertices = scaled_vertices,
        triangles = mesh.triangles,
        width = collision_width,
        height = collision_height,
        depth = collision_depth,
        collision = collision,
        spawn = {
            x = x,
            y = spawn_y,
            z = z,
            yaw = 0
        }
    }

    table.insert(LandingPads.pads, pad)
    return pad
end

-- Create a landing pad using Aseprite coordinates
function LandingPads.create_pad_aseprite(config)
    local world_x, world_z = Constants.aseprite_to_world(config.aseprite_x, config.aseprite_z)

    return LandingPads.create_pad({
        id = config.id,
        name = config.name,
        x = world_x,
        z = world_z,
        scale = config.scale,
        base_y = config.base_y
    })
end

-- Get a landing pad by ID
function LandingPads.get_pad(id)
    for _, pad in ipairs(LandingPads.pads) do
        if pad.id == id then
            return pad
        end
    end
    return nil
end

-- Get spawn position for a landing pad
function LandingPads.get_spawn(id)
    local pad = LandingPads.get_pad(id)
    if pad and pad.spawn then
        return pad.spawn.x, pad.spawn.y, pad.spawn.z, pad.spawn.yaw
    end
    return nil
end

-- Clear all landing pads
function LandingPads.clear()
    LandingPads.pads = {}
end

-- Get all landing pads
function LandingPads.get_all()
    return LandingPads.pads
end

-- Draw a landing pad using the renderer
function LandingPads.draw_pad(pad, renderer, cam_x, cam_z)
    -- Distance culling - skip pads beyond render distance
    if cam_x and cam_z then
        local dx = pad.x - cam_x
        local dz = pad.z - cam_z
        local dist_sq = dx * dx + dz * dz
        if dist_sq > config.RENDER_DISTANCE * config.RENDER_DISTANCE then
            return
        end
    end

    local texData = Constants.getTextureData(Constants.SPRITE_LANDING_PAD)
    if not texData then return end

    local modelMatrix = mat4.translation(pad.x, pad.y, pad.z)

    for _, tri in ipairs(pad.triangles) do
        local v1 = pad.vertices[tri[1]]
        local v2 = pad.vertices[tri[2]]
        local v3 = pad.vertices[tri[3]]

        local p1 = mat4.multiplyVec4(modelMatrix, {v1.pos[1], v1.pos[2], v1.pos[3], 1})
        local p2 = mat4.multiplyVec4(modelMatrix, {v2.pos[1], v2.pos[2], v2.pos[3], 1})
        local p3 = mat4.multiplyVec4(modelMatrix, {v3.pos[1], v3.pos[2], v3.pos[3], 1})

        renderer.drawTriangle3D(
            {pos = {p1[1], p1[2], p1[3]}, uv = v1.uv},
            {pos = {p2[1], p2[2], p2[3]}, uv = v2.uv},
            {pos = {p3[1], p3[2], p3[3]}, uv = v3.uv},
            nil,
            texData
        )
    end
end

-- Draw all landing pads
function LandingPads.draw_all(renderer, cam_x, cam_z)
    for _, pad in ipairs(LandingPads.pads) do
        LandingPads.draw_pad(pad, renderer, cam_x, cam_z)
    end
end

-- Check if ship is on a landing pad
function LandingPads.check_landing(ship_x, ship_y, ship_z, ship_vy)
    for _, pad in ipairs(LandingPads.pads) do
        local bounds = pad.collision:get_bounds()

        -- Check XZ bounds
        if Collision.point_in_box(ship_x, ship_z, pad.x, pad.z, bounds.half_width, bounds.half_depth) then
            -- Check Y (ship should be near pad surface and descending slowly)
            local pad_top = bounds.top
            if ship_y >= pad_top and ship_y <= pad_top + 2 and math.abs(ship_vy) < 0.1 then
                return pad
            end
        end
    end
    return nil
end

return LandingPads
