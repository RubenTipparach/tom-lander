-- Picotron Palette Module
-- 32-color palette (indexed 0-31) with reverse lookup for heightmap sampling

local Palette = {}

-- Picotron palette (32 colors, indexed 0-31)
-- Converted from hex to RGB (0-255)
Palette.colors = {
    [0]  = {0x00, 0x00, 0x00},  -- 000000
    [1]  = {0x1d, 0x2b, 0x53},  -- 1d2b53
    [2]  = {0x7e, 0x25, 0x53},  -- 7e2553
    [3]  = {0x00, 0x87, 0x51},  -- 008751
    [4]  = {0xab, 0x52, 0x36},  -- ab5236
    [5]  = {0x5f, 0x57, 0x4f},  -- 5f574f
    [6]  = {0xc2, 0xc3, 0xc7},  -- c2c3c7
    [7]  = {0xff, 0xf1, 0xe8},  -- fff1e8
    [8]  = {0xff, 0x00, 0x4d},  -- ff004d
    [9]  = {0xff, 0xa3, 0x00},  -- ffa300
    [10] = {0xff, 0xec, 0x27},  -- ffec27
    [11] = {0x00, 0xe4, 0x36},  -- 00e436
    [12] = {0x29, 0xad, 0xff},  -- 29adff
    [13] = {0x83, 0x76, 0x9c},  -- 83769c
    [14] = {0xff, 0x77, 0xa8},  -- ff77a8
    [15] = {0xff, 0xcc, 0xaa},  -- ffccaa
    [16] = {0x1c, 0x5e, 0xac},  -- 1c5eac
    [17] = {0x00, 0xa5, 0xa1},  -- 00a5a1
    [18] = {0x75, 0x4e, 0x97},  -- 754e97
    [19] = {0x12, 0x53, 0x59},  -- 125359
    [20] = {0x74, 0x2f, 0x29},  -- 742f29
    [21] = {0x49, 0x2d, 0x38},  -- 492d38
    [22] = {0xa2, 0x88, 0x79},  -- a28879
    [23] = {0xff, 0xac, 0xc5},  -- ffacc5
    [24] = {0xc3, 0x00, 0x4c},  -- c3004c
    [25] = {0xeb, 0x6b, 0x00},  -- eb6b00
    [26] = {0x90, 0xec, 0x42},  -- 90ec42
    [27] = {0x00, 0xb2, 0x51},  -- 00b251
    [28] = {0x64, 0xdf, 0xf6},  -- 64dff6
    [29] = {0xbd, 0x9a, 0xdf},  -- bd9adf
    [30] = {0xe4, 0x0d, 0xab},  -- e40dab
    [31] = {0xff, 0x85, 0x6d},  -- ff856d
}

-- Build reverse lookup table: RGB key -> palette index
Palette.reverse = {}
for index, rgb in pairs(Palette.colors) do
    -- Create a key from RGB values (pack into single integer)
    local key = rgb[1] * 65536 + rgb[2] * 256 + rgb[3]
    Palette.reverse[key] = index
end

-- Get palette index from RGB values (0-255 each)
-- Returns exact match or closest color if no exact match
function Palette.getIndex(r, g, b)
    -- Create key and lookup in reverse palette
    local key = r * 65536 + g * 256 + b
    local index = Palette.reverse[key]

    -- If exact match found, return it
    if index ~= nil then
        return index
    end

    -- Find closest palette color
    local best_index = 0
    local best_dist = math.huge
    for idx, rgb in pairs(Palette.colors) do
        local dr = r - rgb[1]
        local dg = g - rgb[2]
        local db = b - rgb[3]
        local dist = dr*dr + dg*dg + db*db
        if dist < best_dist then
            best_dist = dist
            best_index = idx
        end
    end

    return best_index
end

-- Get RGB values from palette index
function Palette.getColor(index)
    return Palette.colors[index] or Palette.colors[0]
end

return Palette
