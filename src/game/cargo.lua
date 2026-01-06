-- Cargo module: Pickup objects for missions
-- Adapted from Picotron version for Love2D

local Constants = require("constants")
local obj_loader = require("obj_loader")
local mat4 = require("mat4")
local quat = require("quat")
local config = require("config")

local Cargo = {}

-- Cargo attachment configuration
Cargo.MOUNT_OFFSET_X = 0
Cargo.MOUNT_OFFSET_Y = -0.8
Cargo.MOUNT_OFFSET_Z = 0

-- Cached cargo mesh
local cargo_mesh = nil

-- Get or load the cargo mesh
local function get_cargo_mesh()
    if cargo_mesh then
        return cargo_mesh
    end

    local success, result = pcall(function()
        return obj_loader.load("assets/cargo.obj")
    end)

    if success and result then
        cargo_mesh = result
        print("Cargo mesh loaded")
    else
        -- Fallback cube
        cargo_mesh = {
            vertices = {
                {pos = {-0.5, 0, -0.5}, uv = {0, 0}},
                {pos = {0.5, 0, -0.5}, uv = {1, 0}},
                {pos = {0.5, 0, 0.5}, uv = {1, 1}},
                {pos = {-0.5, 0, 0.5}, uv = {0, 1}},
                {pos = {-0.5, 1, -0.5}, uv = {0, 0}},
                {pos = {0.5, 1, -0.5}, uv = {1, 0}},
                {pos = {0.5, 1, 0.5}, uv = {1, 1}},
                {pos = {-0.5, 1, 0.5}, uv = {0, 1}},
            },
            triangles = {
                {1, 2, 3}, {1, 3, 4},  -- bottom
                {5, 7, 6}, {5, 8, 7},  -- top
                {1, 5, 6}, {1, 6, 2},  -- front
                {3, 7, 8}, {3, 8, 4},  -- back
                {4, 8, 5}, {4, 5, 1},  -- left
                {2, 6, 7}, {2, 7, 3},  -- right
            }
        }
        print("Using fallback cargo mesh")
    end

    return cargo_mesh
end

-- Create a cargo pickup object
-- config: {id, x, z, base_y, scale}
function Cargo.create(config)
    local id = config.id or 1
    local x = config.x or 0
    local z = config.z or 0
    local base_y = config.base_y or 0
    local scale = config.scale or 0.5

    local mesh = get_cargo_mesh()

    -- Scale vertices
    local scaled_vertices = {}
    for _, v in ipairs(mesh.vertices) do
        table.insert(scaled_vertices, {
            pos = {v.pos[1] * scale, v.pos[2] * scale, v.pos[3] * scale},
            uv = v.uv
        })
    end

    return {
        id = id,
        vertices = scaled_vertices,
        triangles = mesh.triangles,
        x = x,
        y = base_y + 0.5,  -- Float above ground
        z = z,
        base_y = base_y + 0.5,
        scale = scale,
        collected = false,
        state = "idle",  -- States: "idle", "tethering", "attached", "delivered"
        hover_distance = 2,
        attach_distance = 0.3,
        tether_speed = 5.0,
        bob_offset = 0,
        attached_to_ship = false,
        mount_offset = {x = Cargo.MOUNT_OFFSET_X, y = Cargo.MOUNT_OFFSET_Y, z = Cargo.MOUNT_OFFSET_Z},
        vy = 0,
        gravity = -9.8,
        pitch = 0,
        yaw = 0,
        roll = 0
    }
end

-- Create cargo using Aseprite coordinates
function Cargo.create_aseprite(config)
    local world_x, world_z = Constants.aseprite_to_world(config.aseprite_x, config.aseprite_z)

    return Cargo.create({
        id = config.id,
        x = world_x,
        z = world_z,
        base_y = config.base_y,
        scale = config.scale
    })
end

-- Update cargo state
-- ship_orientation can be a quaternion table {w, x, y, z} or nil
function Cargo.update(cargo, dt, ship_x, ship_y, ship_z, ship_orientation)
    if cargo.state == "delivered" then return end

    -- Calculate distance to ship
    local dx = ship_x - cargo.x
    local dy = ship_y - cargo.y
    local dz = ship_z - cargo.z
    local dist_3d = math.sqrt(dx*dx + dy*dy + dz*dz)

    if cargo.state == "idle" then
        cargo.bob_offset = 0

        -- Auto-pickup when within range
        if dist_3d < cargo.hover_distance then
            cargo.state = "tethering"
            cargo.vy = 0
        end

    elseif cargo.state == "tethering" then
        if dist_3d > cargo.attach_distance then
            -- Move towards ship
            local dir_x = dx / dist_3d
            local dir_y = dy / dist_3d
            local dir_z = dz / dist_3d

            cargo.x = cargo.x + dir_x * cargo.tether_speed * dt
            cargo.y = cargo.y + dir_y * cargo.tether_speed * dt
            cargo.z = cargo.z + dir_z * cargo.tether_speed * dt
            cargo.bob_offset = 0
        else
            -- Attach to ship
            cargo.state = "attached"
            cargo.attached_to_ship = true
            cargo.collected = true
        end

    elseif cargo.state == "attached" then
        local offset_x = cargo.mount_offset.x
        local offset_y = cargo.mount_offset.y
        local offset_z = cargo.mount_offset.z

        -- Use quaternion to rotate the offset (no gimbal lock!)
        if ship_orientation then
            local rx, ry, rz = quat.rotateVector(ship_orientation, offset_x, offset_y, offset_z)
            cargo.x = ship_x + rx
            cargo.y = ship_y + ry
            cargo.z = ship_z + rz
            -- Store orientation for drawing
            cargo.orientation = ship_orientation
        else
            -- Fallback: no rotation
            cargo.x = ship_x + offset_x
            cargo.y = ship_y + offset_y
            cargo.z = ship_z + offset_z
        end
        cargo.bob_offset = 0
    end
end

-- Draw cargo using the renderer
function Cargo.draw(cargo, renderer, cam_x, cam_z)
    if cargo.state == "delivered" then return end

    -- Distance culling - skip cargo beyond render distance (unless attached)
    if cargo.state ~= "attached" and cam_x and cam_z then
        local dx = cargo.x - cam_x
        local dz = cargo.z - cam_z
        local dist_sq = dx * dx + dz * dz
        if dist_sq > config.RENDER_DISTANCE * config.RENDER_DISTANCE then
            return
        end
    end

    local texData = Constants.getTextureData(Constants.SPRITE_CARGO)
    if not texData then return end

    -- Build model matrix using quaternion if available (no gimbal lock!)
    local modelMatrix
    if cargo.orientation then
        local rotationMatrix = quat.toMatrix(cargo.orientation)
        modelMatrix = mat4.multiply(mat4.translation(cargo.x, cargo.y + cargo.bob_offset, cargo.z), rotationMatrix)
    else
        -- Fallback: identity rotation
        modelMatrix = mat4.translation(cargo.x, cargo.y + cargo.bob_offset, cargo.z)
    end

    for _, tri in ipairs(cargo.triangles) do
        local v1 = cargo.vertices[tri[1]]
        local v2 = cargo.vertices[tri[2]]
        local v3 = cargo.vertices[tri[3]]

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

-- Check if cargo is attached
function Cargo.is_attached(cargo)
    return cargo.state == "attached"
end

-- Check if cargo is tethering
function Cargo.is_tethering(cargo)
    return cargo.state == "tethering"
end

-- Mark cargo as delivered
function Cargo.deliver(cargo)
    cargo.state = "delivered"
    cargo.attached_to_ship = false
end

return Cargo
