-- Cutscene Module
-- Displays story scenes with images and text
-- Ported from Picotron version for Love2D

local Cutscene = {}

-- Configuration
local TEXT_COLOR = {1, 1, 1}  -- White
local SHADOW_COLOR = {0, 0, 0}  -- Black
local BG_COLOR = {0, 0, 0}  -- Black background
local PROMPT_COLOR = {0.4, 0.8, 0.4}  -- Green
local TEXT_Y_START = 160  -- Y position where text starts (in 480x270 space)
local LINE_HEIGHT = 12  -- Height between lines
local TEXT_SPEED = 0.02  -- Seconds per character
local SPRITE_Y = 10

-- Story scenes (sprite numbers match Picotron)
Cutscene.scenes = {
    {
        sprite = 66,
        text = {
            "Tom Lander, having recently reclaimed his throne,",
            "is now king of the moon."
        }
    },
    {
        sprite = 67,
        text = {
            "Little did he know the Barons placed a sleeper cell",
            "on the Alien planet Gradix. They became mindless",
            "terrorists who blew up cities and government officials",
            "in the name of Tom Lander, framing him for countless",
            "murders."
        }
    },
    {
        sprite = 68,
        text = {
            "The Gradixians got pissed, and invaded the moon.",
            "They showed up with a giant spaceship and blew up",
            "everything. The Moon kingdom evacuated and spread out",
            "across the galaxy. Tom was stripped of his title,",
            "escaped and lived in the outer worlds as an anonymous",
            "blue collar worker. His amazing lander skills landed",
            "him as the Ace Lander Pilot of the Shimigu Mining",
            "industry."
        }
    },
    {
        sprite = 69,
        text = {
            "One day, they received a message from the Gradixians.",
            "They are still pissed at Tom Lander, and demand they",
            "hand him over. The Shimigu board said \"Fuck that!\",",
            "and decided that it was worth defending Tom and his",
            "Lander."
        }
    },
    {
        sprite = 70,
        text = {
            "They have 10 days to prepare before the Gradixians",
            "arrive. Tom must build up his fortress, by doing what",
            "he does best. Pick up valuable resources and land them",
            "in Texius city. The brilliant builders will build up",
            "the fort and fight back the invaders."
        }
    }
}

-- Current state
Cutscene.active = false
Cutscene.current_scene = 1
Cutscene.char_timer = 0
Cutscene.chars_shown = 0
Cutscene.scene_complete = false
Cutscene.skip_used_this_frame = false

-- Cached images
local scene_images = {}
local images_loaded = false

-- Load scene images
local function load_images()
    if images_loaded then return end

    for i, scene in ipairs(Cutscene.scenes) do
        local path = "assets/textures/" .. scene.sprite .. ".png"
        local success, result = pcall(function()
            return love.graphics.newImage(path)
        end)
        if success then
            scene_images[i] = result
            -- Set nearest neighbor filtering for pixel art
            scene_images[i]:setFilter("nearest", "nearest")
        else
            print("Warning: Could not load cutscene image: " .. path)
        end
    end

    images_loaded = true
end

-- Initialize cutscene
function Cutscene.start(scene_num)
    load_images()
    Cutscene.active = true
    Cutscene.current_scene = scene_num or 1
    Cutscene.char_timer = 0
    Cutscene.chars_shown = 0
    Cutscene.scene_complete = false
end

-- Stop cutscene
function Cutscene.stop()
    Cutscene.active = false
end

-- Update cutscene (text reveal animation)
function Cutscene.update(dt)
    if not Cutscene.active then return end

    -- Reset skip flag at start of update
    Cutscene.skip_used_this_frame = false

    local scene = Cutscene.scenes[Cutscene.current_scene]
    if not scene then
        Cutscene.stop()
        return
    end

    -- Calculate total characters in all lines
    local total_chars = 0
    for _, line in ipairs(scene.text) do
        total_chars = total_chars + #line
    end

    -- Reveal characters over time
    if Cutscene.chars_shown < total_chars then
        Cutscene.char_timer = Cutscene.char_timer + dt
        if Cutscene.char_timer >= TEXT_SPEED then
            Cutscene.chars_shown = Cutscene.chars_shown + 1
            Cutscene.char_timer = 0
        end
    else
        Cutscene.scene_complete = true
    end
end

-- Handle key press
function Cutscene.keypressed(key)
    if not Cutscene.active then return false end

    local scene = Cutscene.scenes[Cutscene.current_scene]
    if not scene then return false end

    -- Calculate total characters
    local total_chars = 0
    for _, line in ipairs(scene.text) do
        total_chars = total_chars + #line
    end

    -- Z or Space to skip teletype or advance
    if key == "z" or key == "space" or key == "return" or key == "x" then
        if Cutscene.chars_shown < total_chars then
            -- Show all text immediately
            Cutscene.chars_shown = total_chars
            Cutscene.scene_complete = true
            Cutscene.skip_used_this_frame = true
            return false
        elseif Cutscene.scene_complete and not Cutscene.skip_used_this_frame then
            -- Move to next scene
            Cutscene.current_scene = Cutscene.current_scene + 1
            if Cutscene.current_scene > #Cutscene.scenes then
                -- All scenes complete
                Cutscene.stop()
                return true  -- Signal that cutscene is done
            else
                -- Start next scene
                Cutscene.char_timer = 0
                Cutscene.chars_shown = 0
                Cutscene.scene_complete = false
                return false
            end
        end
    end

    return false
end

-- Draw cutscene
function Cutscene.draw()
    if not Cutscene.active then return end

    local scene = Cutscene.scenes[Cutscene.current_scene]
    if not scene then return end

    -- Black background
    love.graphics.setColor(BG_COLOR)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    -- Get window dimensions for scaling
    local windowW, windowH = love.graphics.getDimensions()
    local scale = math.min(windowW / 480, windowH / 270)
    local offsetX = (windowW - 480 * scale) / 2
    local offsetY = (windowH - 270 * scale) / 2

    -- Draw sprite (centered)
    local img = scene_images[Cutscene.current_scene]
    if img then
        local imgW, imgH = img:getDimensions()
        local spriteX = offsetX + (480 * scale - imgW * scale) / 2
        local spriteY = offsetY + SPRITE_Y * scale

        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(img, spriteX, spriteY, 0, scale, scale)
    end

    -- Draw text with character reveal
    local y = offsetY + TEXT_Y_START * scale
    local chars_remaining = Cutscene.chars_shown

    -- Use default Love2D font
    local font = love.graphics.getFont()

    for _, line in ipairs(scene.text) do
        if chars_remaining <= 0 then break end

        -- Show only the revealed portion of this line
        local chars_to_show = math.min(chars_remaining, #line)
        local line_to_show = string.sub(line, 1, chars_to_show)

        -- Center the text
        local textWidth = font:getWidth(line_to_show)
        local text_x = offsetX + (480 * scale - textWidth) / 2

        -- Shadow
        love.graphics.setColor(SHADOW_COLOR)
        love.graphics.print(line_to_show, text_x + scale, y + scale)

        -- Main text
        love.graphics.setColor(TEXT_COLOR)
        love.graphics.print(line_to_show, text_x, y)

        chars_remaining = chars_remaining - #line
        y = y + LINE_HEIGHT * scale
    end

    -- Show prompt when scene is complete
    if Cutscene.scene_complete then
        local prompt = "PRESS Z TO CONTINUE"
        local prompt_width = font:getWidth(prompt)
        local prompt_x = offsetX + (480 * scale - prompt_width) / 2
        local prompt_y = offsetY + 250 * scale

        -- Blink the prompt
        if math.floor(love.timer.getTime() * 2) % 2 == 0 then
            -- Shadow
            love.graphics.setColor(SHADOW_COLOR)
            love.graphics.print(prompt, prompt_x + scale, prompt_y + scale)
            -- Main text (green)
            love.graphics.setColor(PROMPT_COLOR)
            love.graphics.print(prompt, prompt_x, prompt_y)
        end
    end

    -- Reset color
    love.graphics.setColor(1, 1, 1)
end

-- Check if cutscene is active
function Cutscene.is_active()
    return Cutscene.active
end

-- Get total number of scenes
function Cutscene.get_scene_count()
    return #Cutscene.scenes
end

return Cutscene
