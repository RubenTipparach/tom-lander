-- Fonts Module
-- Centralized font management for the game

local fonts = {}

-- Cache for loaded fonts at different sizes
local fontCache = {}

-- Default font path
local FONT_PATH = "assets/fonts/perfect_dos_vga_437/Perfect DOS VGA 437.ttf"

-- Get a font at the specified size (cached)
function fonts.get(size)
    size = size or 16
    if not fontCache[size] then
        fontCache[size] = love.graphics.newFont(FONT_PATH, size)
        fontCache[size]:setFilter("nearest", "nearest")  -- Pixel-perfect rendering
    end
    return fontCache[size]
end

-- Preload common font sizes
function fonts.preload()
    fonts.get(8)   -- Small (HUD labels)
    fonts.get(16)  -- Medium (menus, cutscenes)
    fonts.get(32)  -- Large (titles)
end

return fonts
