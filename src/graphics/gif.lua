-- Simple GIF encoder for Love2D
-- Based on LuaGIF by Paul Hicks

local GIF = {}

-- LZW compression for GIF
local function lzw_encode(data, min_code_size)
    local clear_code = 2 ^ min_code_size
    local end_code = clear_code + 1
    local code_size = min_code_size + 1
    local next_code = end_code + 1

    local dictionary = {}
    for i = 0, clear_code - 1 do
        dictionary[string.char(i)] = i
    end

    local output = {}
    local bit_buffer = 0
    local bit_count = 0

    local function write_code(code)
        bit_buffer = bit_buffer + bit.lshift(code, bit_count)
        bit_count = bit_count + code_size

        while bit_count >= 8 do
            table.insert(output, bit.band(bit_buffer, 0xFF))
            bit_buffer = bit.rshift(bit_buffer, 8)
            bit_count = bit_count - 8
        end
    end

    write_code(clear_code)

    local w = ""
    for i = 1, #data do
        local k = string.char(data[i])
        local wk = w .. k

        if dictionary[wk] then
            w = wk
        else
            write_code(dictionary[w])

            if next_code < 4096 then
                dictionary[wk] = next_code
                next_code = next_code + 1

                if next_code > (2 ^ code_size) and code_size < 12 then
                    code_size = code_size + 1
                end
            else
                write_code(clear_code)
                dictionary = {}
                for j = 0, clear_code - 1 do
                    dictionary[string.char(j)] = j
                end
                next_code = end_code + 1
                code_size = min_code_size + 1
            end

            w = k
        end
    end

    if w ~= "" then
        write_code(dictionary[w])
    end

    write_code(end_code)

    if bit_count > 0 then
        table.insert(output, bit.band(bit_buffer, 0xFF))
    end

    return output
end

function GIF.new(width, height, delay)
    local obj = {
        width = width,
        height = height,
        delay = delay or 3, -- delay in 1/100th seconds (3 = ~30fps)
        frames = {}
    }
    setmetatable(obj, {__index = GIF})
    return obj
end

function GIF:addFrame(imageData)
    table.insert(self.frames, imageData)
end

function GIF:save(filename)
    local f = love.filesystem.newFile(filename, "w")
    if not f then
        return false, "Could not create file"
    end

    -- GIF Header
    f:write("GIF89a")

    -- Logical Screen Descriptor
    local function writeWord(value)
        f:write(string.char(bit.band(value, 0xFF), bit.band(bit.rshift(value, 8), 0xFF)))
    end

    writeWord(self.width)
    writeWord(self.height)
    f:write(string.char(0xF7, 0, 0)) -- Global color table flag, 8 bits per color

    -- Global Color Table (256 colors using RGB332 palette)
    -- 3 bits red (8 levels), 3 bits green (8 levels), 2 bits blue (4 levels)
    for i = 0, 255 do
        local r = bit.band(bit.rshift(i, 5), 7) -- 3 bits for red (0-7)
        local g = bit.band(bit.rshift(i, 2), 7) -- 3 bits for green (0-7)
        local b = bit.band(i, 3)                -- 2 bits for blue (0-3)

        -- Scale to 0-255 range properly
        -- For 3-bit color: replicate bits (rrr -> rrr rrr rr)
        -- For 2-bit color: replicate bits (bb -> bb bb bb bb)
        r = bit.bor(bit.lshift(r, 5), bit.bor(bit.lshift(r, 2), bit.rshift(r, 1)))
        g = bit.bor(bit.lshift(g, 5), bit.bor(bit.lshift(g, 2), bit.rshift(g, 1)))
        b = bit.bor(bit.lshift(b, 6), bit.bor(bit.lshift(b, 4), bit.bor(bit.lshift(b, 2), b)))

        f:write(string.char(r, g, b))
    end

    -- Application Extension for looping
    f:write(string.char(0x21, 0xFF, 0x0B))
    f:write("NETSCAPE2.0")
    f:write(string.char(0x03, 0x01))
    writeWord(0) -- Loop forever
    f:write(string.char(0))

    -- Write frames
    for _, imageData in ipairs(self.frames) do
        -- Graphic Control Extension
        -- Packed field: disposal method 2 (restore to background), no transparency
        f:write(string.char(0x21, 0xF9, 0x04, 0x08))
        writeWord(self.delay)
        f:write(string.char(0, 0)) -- Transparent color index (none)

        -- Image Descriptor
        f:write(string.char(0x2C))
        writeWord(0) -- Left
        writeWord(0) -- Top
        writeWord(self.width)
        writeWord(self.height)
        f:write(string.char(0)) -- No local color table

        -- Convert image data to indexed color using RGB332 palette
        local indices = {}
        for y = 0, self.height - 1 do
            for x = 0, self.width - 1 do
                local r, g, b = imageData:getPixel(x, y)

                -- Quantize to RGB332 (3-3-2 bits)
                local ri = math.min(7, math.floor(r * 8)) -- 0-7 (3 bits)
                local gi = math.min(7, math.floor(g * 8)) -- 0-7 (3 bits)
                local bi = math.min(3, math.floor(b * 4)) -- 0-3 (2 bits)

                -- Combine into palette index: rrrgggbb
                local index = bit.bor(bit.lshift(ri, 5), bit.bor(bit.lshift(gi, 2), bi))
                table.insert(indices, index)
            end
        end

        -- LZW Minimum Code Size
        f:write(string.char(8))

        -- LZW compressed data
        local compressed = lzw_encode(indices, 8)

        -- Write data in sub-blocks
        local pos = 1
        while pos <= #compressed do
            local blockSize = math.min(255, #compressed - pos + 1)
            f:write(string.char(blockSize))
            for i = pos, pos + blockSize - 1 do
                f:write(string.char(compressed[i]))
            end
            pos = pos + blockSize
        end

        f:write(string.char(0)) -- Block terminator
    end

    -- Trailer
    f:write(string.char(0x3B))

    f:close()
    return true
end

return GIF
