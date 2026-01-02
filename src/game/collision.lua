-- Collision and Physics Helpers Module
-- Provides AABB collision detection and physics utilities
-- Adapted from Picotron version for Love2D

local Collision = {}

-- Create an AABB (Axis-Aligned Bounding Box) collision object
-- @param x, y, z: center position
-- @param width, height, depth: full dimensions
-- @param y_offset: optional Y offset (default 0)
-- @return collision object with bounds
function Collision.create_box(x, y, z, width, height, depth, y_offset)
    y_offset = y_offset or 0

    local box = {
        x = x,
        y = y,
        z = z,
        width = width,
        height = height,
        depth = depth,
        y_offset = y_offset
    }

    -- Get bounds method
    function box:get_bounds()
        local adjusted_y = self.y + self.y_offset
        return {
            top = adjusted_y + self.height,
            bottom = adjusted_y,
            half_width = self.width / 2,
            half_depth = self.depth / 2
        }
    end

    return box
end

-- Check if a point is inside a box (2D, XZ plane)
function Collision.point_in_box(point_x, point_z, box_x, box_z, half_width, half_depth)
    local dx = point_x - box_x
    local dz = point_z - box_z
    return math.abs(dx) < half_width and math.abs(dz) < half_depth
end

-- Check if a point is inside a 3D box
function Collision.point_in_box_3d(px, py, pz, box_x, box_y, box_z, half_width, half_height, half_depth)
    local dx = px - box_x
    local dy = py - box_y
    local dz = pz - box_z
    return math.abs(dx) < half_width and math.abs(dy) < half_height and math.abs(dz) < half_depth
end

-- Check if two AABBs overlap (2D, XZ plane)
function Collision.box_overlap(box1_x, box1_z, box1_half_w, box1_half_d, box2_x, box2_z, box2_half_w, box2_half_d)
    local dx = math.abs(box1_x - box2_x)
    local dz = math.abs(box1_z - box2_z)
    return dx < (box1_half_w + box2_half_w) and dz < (box1_half_d + box2_half_d)
end

-- Check if two AABBs overlap (3D)
function Collision.box_overlap_3d(b1, b2)
    local dx = math.abs(b1.x - b2.x)
    local dy = math.abs(b1.y - b2.y)
    local dz = math.abs(b1.z - b2.z)

    local sum_half_w = (b1.width + b2.width) / 2
    local sum_half_h = (b1.height + b2.height) / 2
    local sum_half_d = (b1.depth + b2.depth) / 2

    return dx < sum_half_w and dy < sum_half_h and dz < sum_half_d
end

-- Push a point out of a box through the nearest edge
function Collision.push_out_of_box(point_x, point_z, box_x, box_z, half_width, half_depth)
    local dx = point_x - box_x
    local dz = point_z - box_z

    local dist_left = math.abs(dx + half_width)
    local dist_right = math.abs(dx - half_width)
    local dist_front = math.abs(dz + half_depth)
    local dist_back = math.abs(dz - half_depth)

    local min_dist = math.min(dist_left, dist_right, dist_front, dist_back)

    if min_dist == dist_left then
        return box_x - half_width - 0.1, point_z
    elseif min_dist == dist_right then
        return box_x + half_width + 0.1, point_z
    elseif min_dist == dist_front then
        return point_x, box_z - half_depth - 0.1
    else
        return point_x, box_z + half_depth + 0.1
    end
end

-- Calculate bounding box from vertex array
function Collision.calculate_bounds(verts)
    local min_x, max_x = math.huge, -math.huge
    local min_y, max_y = math.huge, -math.huge
    local min_z, max_z = math.huge, -math.huge

    for _, v in ipairs(verts) do
        local x, y, z
        if v.pos then
            x, y, z = v.pos[1], v.pos[2], v.pos[3]
        else
            x, y, z = v.x or v[1], v.y or v[2], v.z or v[3]
        end

        min_x = math.min(min_x, x)
        max_x = math.max(max_x, x)
        min_y = math.min(min_y, y)
        max_y = math.max(max_y, y)
        min_z = math.min(min_z, z)
        max_z = math.max(max_z, z)
    end

    return min_x, max_x, min_y, max_y, min_z, max_z
end

-- Check sphere-box collision
function Collision.sphere_box(sphere_x, sphere_y, sphere_z, radius, box)
    local closest_x = math.max(box.x - box.width/2, math.min(sphere_x, box.x + box.width/2))
    local closest_y = math.max(box.y, math.min(sphere_y, box.y + box.height))
    local closest_z = math.max(box.z - box.depth/2, math.min(sphere_z, box.z + box.depth/2))

    local dx = sphere_x - closest_x
    local dy = sphere_y - closest_y
    local dz = sphere_z - closest_z

    local dist_sq = dx*dx + dy*dy + dz*dz

    return dist_sq < radius * radius
end

-- Get distance between two 3D points
function Collision.distance_3d(x1, y1, z1, x2, y2, z2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dz = z2 - z1
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- Get distance between two 2D points (XZ plane)
function Collision.distance_2d(x1, z1, x2, z2)
    local dx = x2 - x1
    local dz = z2 - z1
    return math.sqrt(dx*dx + dz*dz)
end

return Collision
