-- 4x4 Matrix Math Library

local mat4 = {}

function mat4.identity()
    return {
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    }
end

function mat4.multiply(a, b)
    local result = {}
    for i = 0, 3 do
        for j = 0, 3 do
            local sum = 0
            for k = 0, 3 do
                sum = sum + a[i * 4 + k + 1] * b[k * 4 + j + 1]
            end
            result[i * 4 + j + 1] = sum
        end
    end
    return result
end

function mat4.multiplyVec4(m, v)
    return {
        m[1] * v[1] + m[2] * v[2] + m[3] * v[3] + m[4] * v[4],
        m[5] * v[1] + m[6] * v[2] + m[7] * v[3] + m[8] * v[4],
        m[9] * v[1] + m[10] * v[2] + m[11] * v[3] + m[12] * v[4],
        m[13] * v[1] + m[14] * v[2] + m[15] * v[3] + m[16] * v[4]
    }
end

function mat4.translation(x, y, z)
    return {
        1, 0, 0, x,
        0, 1, 0, y,
        0, 0, 1, z,
        0, 0, 0, 1
    }
end

function mat4.scale(x, y, z)
    return {
        x, 0, 0, 0,
        0, y, 0, 0,
        0, 0, z, 0,
        0, 0, 0, 1
    }
end

function mat4.rotationX(angle)
    local c = math.cos(angle)
    local s = math.sin(angle)
    return {
        1, 0, 0, 0,
        0, c, -s, 0,
        0, s, c, 0,
        0, 0, 0, 1
    }
end

function mat4.rotationY(angle)
    local c = math.cos(angle)
    local s = math.sin(angle)
    return {
        c, 0, s, 0,
        0, 1, 0, 0,
        -s, 0, c, 0,
        0, 0, 0, 1
    }
end

function mat4.rotationZ(angle)
    local c = math.cos(angle)
    local s = math.sin(angle)
    return {
        c, -s, 0, 0,
        s, c, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    }
end

function mat4.perspective(fov, aspect, near, far)
    local f = 1.0 / math.tan(fov / 2.0)  -- fov already in radians
    local rangeInv = 1.0 / (far - near)

    return {
        f / aspect, 0, 0, 0,
        0, f, 0, 0,
        0, 0, -(near + far) * rangeInv, -2 * near * far * rangeInv,
        0, 0, -1, 0
    }
end

return mat4
