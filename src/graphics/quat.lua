-- Quaternion Math Library for gimbal-lock-free rotations

local quat = {}

-- Create a new quaternion (w, x, y, z) - identity by default
function quat.new(w, x, y, z)
    return {w = w or 1, x = x or 0, y = y or 0, z = z or 0}
end

-- Create identity quaternion
function quat.identity()
    return {w = 1, x = 0, y = 0, z = 0}
end

-- Create quaternion from axis-angle
function quat.fromAxisAngle(ax, ay, az, angle)
    local halfAngle = angle * 0.5
    local s = math.sin(halfAngle)
    -- Normalize axis
    local len = math.sqrt(ax*ax + ay*ay + az*az)
    if len > 0.0001 then
        ax, ay, az = ax/len, ay/len, az/len
    end
    return {
        w = math.cos(halfAngle),
        x = ax * s,
        y = ay * s,
        z = az * s
    }
end

-- Create quaternion from Euler angles (yaw, pitch, roll)
-- Matches toEuler extraction: yaw around Z, pitch around Y, roll around X
function quat.fromEuler(yaw, pitch, roll)
    -- Build quaternion from individual axis rotations
    -- Roll around X axis
    local qx = quat.fromAxisAngle(1, 0, 0, roll)
    -- Pitch around Y axis
    local qy = quat.fromAxisAngle(0, 1, 0, pitch)
    -- Yaw around Z axis
    local qz = quat.fromAxisAngle(0, 0, 1, yaw)

    -- Combine: yaw * pitch * roll (matching typical Euler order)
    local result = quat.multiply(qz, qy)
    result = quat.multiply(result, qx)
    return result
end

-- Multiply two quaternions (q1 * q2)
function quat.multiply(q1, q2)
    return {
        w = q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z,
        x = q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y,
        y = q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x,
        z = q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w
    }
end

-- Normalize quaternion
function quat.normalize(q)
    local len = math.sqrt(q.w*q.w + q.x*q.x + q.y*q.y + q.z*q.z)
    if len > 0.0001 then
        return {w = q.w/len, x = q.x/len, y = q.y/len, z = q.z/len}
    end
    return quat.identity()
end

-- Rotate a vector by quaternion
function quat.rotateVector(q, vx, vy, vz)
    -- q * v * q^-1 (optimized)
    local qx, qy, qz, qw = q.x, q.y, q.z, q.w

    -- Calculate cross products
    local uvx = qy * vz - qz * vy
    local uvy = qz * vx - qx * vz
    local uvz = qx * vy - qy * vx

    local uuvx = qy * uvz - qz * uvy
    local uuvy = qz * uvx - qx * uvz
    local uuvz = qx * uvy - qy * uvx

    return
        vx + 2 * (qw * uvx + uuvx),
        vy + 2 * (qw * uvy + uuvy),
        vz + 2 * (qw * uvz + uuvz)
end

-- Convert quaternion to rotation matrix (4x4, row-major)
function quat.toMatrix(q)
    local xx = q.x * q.x
    local xy = q.x * q.y
    local xz = q.x * q.z
    local xw = q.x * q.w
    local yy = q.y * q.y
    local yz = q.y * q.z
    local yw = q.y * q.w
    local zz = q.z * q.z
    local zw = q.z * q.w

    return {
        1 - 2*(yy + zz), 2*(xy - zw), 2*(xz + yw), 0,
        2*(xy + zw), 1 - 2*(xx + zz), 2*(yz - xw), 0,
        2*(xz - yw), 2*(yz + xw), 1 - 2*(xx + yy), 0,
        0, 0, 0, 1
    }
end

-- Convert quaternion to Euler angles (yaw, pitch, roll)
function quat.toEuler(q)
    -- Pitch (x-axis rotation)
    local sinp = 2 * (q.w * q.y - q.z * q.x)
    local pitch
    if math.abs(sinp) >= 1 then
        pitch = (sinp > 0 and 1 or -1) * math.pi / 2  -- Clamp to +/- 90 degrees
    else
        pitch = math.asin(sinp)
    end

    -- Yaw (y-axis rotation)
    local siny_cosp = 2 * (q.w * q.z + q.x * q.y)
    local cosy_cosp = 1 - 2 * (q.y * q.y + q.z * q.z)
    local yaw = math.atan2(siny_cosp, cosy_cosp)

    -- Roll (z-axis rotation)
    local sinr_cosp = 2 * (q.w * q.x + q.y * q.z)
    local cosr_cosp = 1 - 2 * (q.x * q.x + q.y * q.y)
    local roll = math.atan2(sinr_cosp, cosr_cosp)

    return yaw, pitch, roll
end

-- Conjugate (inverse for unit quaternion)
function quat.conjugate(q)
    return {w = q.w, x = -q.x, y = -q.y, z = -q.z}
end

-- Spherical linear interpolation
function quat.slerp(q1, q2, t)
    -- Compute dot product
    local dot = q1.w*q2.w + q1.x*q2.x + q1.y*q2.y + q1.z*q2.z

    -- If negative dot, negate one quaternion to take shorter path
    if dot < 0 then
        q2 = {w = -q2.w, x = -q2.x, y = -q2.y, z = -q2.z}
        dot = -dot
    end

    -- If very close, use linear interpolation
    if dot > 0.9995 then
        return quat.normalize({
            w = q1.w + t * (q2.w - q1.w),
            x = q1.x + t * (q2.x - q1.x),
            y = q1.y + t * (q2.y - q1.y),
            z = q1.z + t * (q2.z - q1.z)
        })
    end

    local theta_0 = math.acos(dot)
    local theta = theta_0 * t
    local sin_theta = math.sin(theta)
    local sin_theta_0 = math.sin(theta_0)

    local s1 = math.cos(theta) - dot * sin_theta / sin_theta_0
    local s2 = sin_theta / sin_theta_0

    return {
        w = s1 * q1.w + s2 * q2.w,
        x = s1 * q1.x + s2 * q2.x,
        y = s1 * q1.y + s2 * q2.y,
        z = s1 * q1.z + s2 * q2.z
    }
end

return quat
