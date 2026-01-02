-- Unified camera system for all scenes

local vec3 = require("vec3")
local mat4 = require("mat4")

local camera = {}

function camera.new(x, y, z)
    return {
        pos = vec3.new(x or 0, y or 0, z or 0),
        pitch = 0,  -- X rotation (rx in Picotron)
        yaw = 0,    -- Y rotation (ry in Picotron) - starts at 0 like Picotron
        forward = vec3.new(0, 0, 1),
        right = vec3.new(1, 0, 0),
        up = vec3.new(0, 1, 0)
    }
end

-- Update camera direction vectors based on pitch/yaw
function camera.updateVectors(cam)
    local cy = math.cos(cam.yaw)
    local sy = math.sin(cam.yaw)
    local cp = math.cos(cam.pitch)
    local sp = math.sin(cam.pitch)

    cam.forward = vec3.new(
        sy * cp,
        -sp,
        cy * cp
    )

    local worldUp = vec3.new(0, 1, 0)
    cam.right = vec3.normalize(vec3.cross(cam.forward, worldUp))
    cam.up = vec3.cross(cam.right, cam.forward)
end

-- Build view matrix from camera
-- Optional cam_dist parameter: push the view back by this amount (like Picotron's cam_dist)
-- Picotron transform order (per vertex):
--   1. tx = world_x - camera.x  (subtract camera position)
--   2. tx2 = tx * cos_ry - tz * sin_ry  (rotate by yaw)
--   3. ty2 = ty * cos_rx - tz2 * sin_rx  (rotate by pitch)
--   4. tz3 += cam_dist  (push away from camera)
-- We build the combined matrix by applying operations in order
function camera.getViewMatrix(cam, cam_dist)
    cam_dist = cam_dist or 0

    -- Precompute trig values
    local cos_yaw = math.cos(cam.yaw)
    local sin_yaw = math.sin(cam.yaw)
    local cos_pitch = math.cos(cam.pitch)
    local sin_pitch = math.sin(cam.pitch)

    -- Build combined view matrix manually to match Picotron's exact transformation
    -- This combines: translate(-cam.pos) -> rotateY(yaw) -> rotateX(pitch) -> translate(0,0,cam_dist)

    -- Translation by -camera position
    local tx = -cam.pos.x
    local ty = -cam.pos.y
    local tz = -cam.pos.z

    -- After rotateY: tx' = tx*cos - tz*sin, tz' = tx*sin + tz*cos
    -- After rotateX: ty' = ty*cos - tz'*sin, tz'' = ty*sin + tz'*cos
    -- After translate: tz''' = tz'' + cam_dist

    -- Combined matrix (row-major):
    -- Row 0: [cos_yaw, 0, sin_yaw, tx*cos_yaw + tz*sin_yaw]
    -- Row 1: [sin_yaw*sin_pitch, cos_pitch, -cos_yaw*sin_pitch, tx*sin_yaw*sin_pitch + ty*cos_pitch - tz*cos_yaw*sin_pitch]
    -- Row 2: [-sin_yaw*cos_pitch, sin_pitch, cos_yaw*cos_pitch, -tx*sin_yaw*cos_pitch + ty*sin_pitch + tz*cos_yaw*cos_pitch + cam_dist]
    -- Row 3: [0, 0, 0, 1]

    return {
        cos_yaw, 0, sin_yaw, tx * cos_yaw + tz * sin_yaw,
        sin_yaw * sin_pitch, cos_pitch, -cos_yaw * sin_pitch, tx * sin_yaw * sin_pitch + ty * cos_pitch - tz * cos_yaw * sin_pitch,
        -sin_yaw * cos_pitch, sin_pitch, cos_yaw * cos_pitch, -tx * sin_yaw * cos_pitch + ty * sin_pitch + tz * cos_yaw * cos_pitch + cam_dist,
        0, 0, 0, 1
    }
end

-- Handle camera input (call from love.update)
-- Note: Uses arrow keys for rotation only - WASD reserved for ship controls
function camera.update(cam, dt, moveSpeed, rotSpeed)
    moveSpeed = moveSpeed or 5.0
    rotSpeed = rotSpeed or 2.0

    -- Rotation with arrow keys
    if love.keyboard.isDown("left") then
        cam.yaw = cam.yaw + rotSpeed * dt
        camera.updateVectors(cam)
    end
    if love.keyboard.isDown("right") then
        cam.yaw = cam.yaw - rotSpeed * dt
        camera.updateVectors(cam)
    end
    if love.keyboard.isDown("up") then
        cam.pitch = cam.pitch + rotSpeed * dt
        camera.updateVectors(cam)
    end
    if love.keyboard.isDown("down") then
        cam.pitch = cam.pitch - rotSpeed * dt
        camera.updateVectors(cam)
    end

    -- Movement with I/J/K/L (free camera only, WASD reserved for ship)
    if love.keyboard.isDown("i") then
        cam.pos = vec3.sub(cam.pos, vec3.scale(cam.forward, moveSpeed * dt))
    end
    if love.keyboard.isDown("k") then
        cam.pos = vec3.add(cam.pos, vec3.scale(cam.forward, moveSpeed * dt))
    end
    if love.keyboard.isDown("j") then
        cam.pos = vec3.add(cam.pos, vec3.scale(cam.right, moveSpeed * dt))
    end
    if love.keyboard.isDown("l") then
        cam.pos = vec3.sub(cam.pos, vec3.scale(cam.right, moveSpeed * dt))
    end
    if love.keyboard.isDown("space") then
        cam.pos = vec3.add(cam.pos, vec3.scale(cam.up, moveSpeed * dt))
    end
    if love.keyboard.isDown("lshift") then
        cam.pos = vec3.sub(cam.pos, vec3.scale(cam.up, moveSpeed * dt))
    end
end

return camera
