-- 3D Vector Math Library

local vec3 = {}

function vec3.new(x, y, z)
    return {x = x or 0, y = y or 0, z = z or 0}
end

function vec3.add(a, b)
    return vec3.new(a.x + b.x, a.y + b.y, a.z + b.z)
end

function vec3.sub(a, b)
    return vec3.new(a.x - b.x, a.y - b.y, a.z - b.z)
end

function vec3.scale(v, s)
    return vec3.new(v.x * s, v.y * s, v.z * s)
end

function vec3.dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

function vec3.cross(a, b)
    return vec3.new(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
end

function vec3.length(v)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

function vec3.normalize(v)
    local len = vec3.length(v)
    if len > 0 then
        return vec3.new(v.x / len, v.y / len, v.z / len)
    end
    return vec3.new(0, 0, 0)
end

return vec3
