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

-- Multi-level shadow mapping - 8 levels from brightest to darkest
-- Each color has a progression of darker shades
-- Level 0 = original color, Level 7 = darkest shadow
Palette.shadowLevels = {
    -- Black (0) - stays black at all levels
    [0] = {0, 0, 0, 0, 0, 0, 0, 0},
    -- Dark blue (1) - to black
    [1] = {1, 1, 1, 0, 0, 0, 0, 0},
    -- Dark purple (2) - through darker purple to black
    [2] = {2, 2, 21, 21, 1, 0, 0, 0},
    -- Dark green (3) - through dark teal to black
    [3] = {3, 3, 19, 19, 1, 1, 0, 0},
    -- Brown (4) - through dark brown to black
    [4] = {4, 4, 20, 20, 21, 1, 0, 0},
    -- Dark gray (5) - through darker purple to black
    [5] = {5, 5, 21, 21, 1, 0, 0, 0},
    -- Light gray (6) - through mid gray, dark gray to black
    [6] = {6, 13, 13, 5, 5, 21, 1, 0},
    -- White (7) - through light gray, mid gray, dark to black
    [7] = {7, 6, 6, 13, 5, 5, 1, 0},
    -- Red (8) - through dark red, dark purple to black
    [8] = {8, 8, 24, 24, 2, 21, 1, 0},
    -- Orange (9) - through dark orange, brown to black
    [9] = {9, 9, 25, 25, 4, 20, 21, 0},
    -- Yellow (10) - through orange, dark orange, brown to black
    [10] = {10, 10, 9, 25, 4, 20, 1, 0},
    -- Green (11) - through dark green, dark teal to black
    [11] = {11, 11, 27, 27, 3, 19, 1, 0},
    -- Blue (12) - through dark blue to black
    [12] = {12, 12, 16, 16, 1, 1, 0, 0},
    -- Mid gray (13) - through dark gray, darker purple to black
    [13] = {13, 13, 5, 5, 21, 1, 0, 0},
    -- Pink (14) - through red, dark red to black
    [14] = {14, 14, 8, 8, 24, 2, 1, 0},
    -- Peach (15) - through brown, dark brown to black
    [15] = {15, 15, 4, 4, 20, 21, 1, 0},
    -- Mid blue (16) - through dark blue to black
    [16] = {16, 16, 1, 1, 0, 0, 0, 0},
    -- Teal (17) - through dark teal, dark blue to black
    [17] = {17, 17, 19, 19, 1, 1, 0, 0},
    -- Purple (18) - through dark purple to black
    [18] = {18, 18, 2, 2, 21, 1, 0, 0},
    -- Dark teal (19) - through dark blue to black
    [19] = {19, 19, 1, 1, 0, 0, 0, 0},
    -- Dark brown (20) - through darker purple to black
    [20] = {20, 20, 21, 21, 1, 0, 0, 0},
    -- Darker purple (21) - to black
    [21] = {21, 21, 1, 0, 0, 0, 0, 0},
    -- Tan (22) - through dark gray to black
    [22] = {22, 22, 5, 5, 21, 1, 0, 0},
    -- Light pink (23) - through pink, red to black
    [23] = {23, 23, 14, 14, 8, 24, 2, 0},
    -- Dark red (24) - through dark purple to black
    [24] = {24, 24, 2, 2, 21, 1, 0, 0},
    -- Dark orange (25) - through brown to black
    [25] = {25, 25, 4, 4, 20, 21, 1, 0},
    -- Light green (26) - through green, dark green to black
    [26] = {26, 26, 11, 11, 27, 3, 19, 0},
    -- Dark green (27) - through darker green, dark teal to black
    [27] = {27, 27, 3, 3, 19, 1, 0, 0},
    -- Light blue (28) - through blue, dark blue to black
    [28] = {28, 28, 12, 12, 16, 1, 0, 0},
    -- Light purple (29) - through mid gray to black
    [29] = {29, 29, 13, 13, 5, 21, 1, 0},
    -- Magenta (30) - through dark red, dark purple to black
    [30] = {30, 30, 24, 24, 2, 21, 1, 0},
    -- Light orange (31) - through red, dark red to black
    [31] = {31, 31, 8, 8, 24, 2, 1, 0},
}

-- Get shadow color index at a specific level (0-7)
function Palette.getShadowLevel(paletteIndex, level)
    level = math.max(0, math.min(7, math.floor(level)))
    local levels = Palette.shadowLevels[paletteIndex]
    if not levels then return 0 end
    return levels[level + 1] or 0  -- +1 because Lua tables are 1-indexed
end

-- Legacy function for single-level shadows (uses level 4, mid-darkness)
function Palette.getShadowIndex(index)
    return Palette.getShadowLevel(index, 4)
end

-- Get shadow RGB color for a given palette index and level
function Palette.getShadowColor(index, level)
    local shadowIndex = Palette.getShadowLevel(index, level or 4)
    return Palette.getColor(shadowIndex)
end

return Palette
