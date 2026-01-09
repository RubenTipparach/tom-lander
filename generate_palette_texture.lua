-- Standalone script to generate palette shadow lookup texture
-- Run with: love . --fused generate_palette_texture.lua
-- Or just: love generate_palette_texture.lua

-- Load palette module
package.path = package.path .. ";src/?.lua;src/game/?.lua"
local Palette = require("palette")

function love.load()
    print("Generating palette shadow lookup texture...")

    local width = 32   -- 32 palette colors
    local height = 8   -- 8 shadow levels

    -- Create ImageData (raw pixel data)
    local imageData = love.image.newImageData(width, height)

    -- Fill with palette shadow colors
    for paletteIndex = 0, 31 do
        for shadowLevel = 0, 7 do
            -- Get the shadow color for this palette index at this level
            local shadowIndex = Palette.getShadowLevel(paletteIndex, shadowLevel)
            local rgb = Palette.getColor(shadowIndex)

            -- Set pixel (x=paletteIndex, y=shadowLevel)
            imageData:setPixel(paletteIndex, shadowLevel, rgb[1]/255, rgb[2]/255, rgb[3]/255, 1.0)

            -- Debug output for first few
            if paletteIndex < 3 and shadowLevel < 3 then
                print(string.format("Palette[%d] Level[%d] -> Shadow[%d] RGB(%d,%d,%d)",
                    paletteIndex, shadowLevel, shadowIndex, rgb[1], rgb[2], rgb[3]))
            end
        end
    end

    -- Save as PNG
    local filename = "assets/palette_shadow_lookup.png"
    imageData:encode("png", filename)
    print("Palette shadow lookup texture saved to " .. filename)
    print("Texture size: " .. width .. "x" .. height .. " pixels")
    print("Each row represents a shadow level (0=brightest, 7=darkest)")
    print("Each column represents a palette color (0-31)")

    love.event.quit()
end

function love.draw()
    love.graphics.print("Generating palette texture...", 10, 10)
end
