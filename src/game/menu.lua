-- Menu module: Main menu with space background and mission selection
-- Ported from Picotron version
local menu = {}
local scene_manager = require("scene_manager")
local config = require("config")
local renderer = require("renderer_dda")
local camera_module = require("camera")
local mat4 = require("mat4")
local quat = require("quat")
local obj_loader = require("obj_loader")
local Constants = require("constants")
local Palette = require("palette")

-- Ship display settings (matching Picotron, Z inverted for Love2D)
local SHIP_X = 0
local SHIP_Y = 1
local SHIP_Z = -9 -- Picotron: 0.5, inverted for Love2D
local SHIP_PITCH = -1.13  -- Picotron 0-1 rotation
local SHIP_YAW = 0.16
local SHIP_ROLL = 0.08
local SHIP_BOB_SPEED_Y = 0.5
local SHIP_BOB_AMOUNT_Y = 0.1
local SHIP_BOB_SPEED_X = 0.2
local SHIP_BOB_AMOUNT_X = 0.01
local SHIP_SCALE = 1

-- Planet settings (matching Picotron, Z inverted for Love2D)
local PLANET_X = 50
local PLANET_Y = 20
local PLANET_Z = -100  -- Picotron: 100, inverted for Love2D
local PLANET_SCALE = 40
local PLANET_PITCH = -0.06
local PLANET_YAW = -0.54
local PLANET_ROLL = 0
local PLANET_ROTATION_SPEED = 0.01

-- Cloud layer settings
local CLOUD_SCALE_OFFSET = 2.5
local CLOUD_ROTATION_SPEED = 0.02

-- Flame/engine settings
local ENGINE_RIGHT = {x = 6, y = -2, z = 0}
local ENGINE_LEFT = {x = -6, y = -2, z = 0}
local ENGINE_FRONT = {x = 0, y = -2, z = 6}
local ENGINE_BACK = {x = 0, y = -2, z = -6}
local FLAME_FLICKER_AMOUNT = 0.1
local FLAME_NOISE_AMOUNT = 0.05
local FLAME_SPEED = 20

-- Starfield settings
local STARFIELD_COUNT = 180  -- Number of stars
local STARFIELD_SPAWN_DIST = 30
local STARFIELD_SPREAD = 20
local STARFIELD_SPEED_MIN = 0.1
local STARFIELD_SPEED_MAX = 0.4
local STARFIELD_LENGTH_MIN = 0.5
local STARFIELD_LENGTH_MAX = 2.5
local STARFIELD_DESPAWN_DIST = 60
local STARFIELD_USE_SHIP_UP = true  -- true = fly opposite ship's up, false = use DIR values below
local STARFIELD_DIR_X = 0  -- Direction stars fly (only used if USE_SHIP_UP = false)
local STARFIELD_DIR_Y = -1  -- -1 = down, 1 = up
local STARFIELD_DIR_Z = 0

-- Menu render distance
local MENU_RENDER_DISTANCE = 2000

-- Menu state
menu.active = true
menu.show_options = false
menu.show_mode_select = false
menu.selected_option = 1
menu.selected_mode = 1  -- 1 = Arcade, 2 = Simulation
menu.pending_mission = nil
menu.options = {}
menu.mission_progress = {}
menu.splash_fade = 0

-- Space background elements
menu.planet = {}
menu.clouds = {}
menu.space_lines = {}
menu.ship_mesh = nil
menu.flame_mesh = nil
menu.ship_model_matrix = nil  -- Stored after draw_ship() for extracting up vector

-- Software rendering
local softwareImage = nil
local projMatrix = nil
local cam = nil

-- Debug camera rotation
local debug_cam_yaw = 0
local debug_cam_pitch = 0

-- Logo image
local logoImage = nil

-- Shader for black transparency
local blackTransparentShader = nil

-- Helper function: Get palette color as Love2D color (0-1)
local function getPaletteColor(index)
    local c = Palette.colors[index] or Palette.colors[7]
    return c[1]/255, c[2]/255, c[3]/255
end

-- Helper function for text with drop shadow
local function print_shadow(text, x, y, color_index, shadow_index)
    shadow_index = shadow_index or 0
    local sr, sg, sb = getPaletteColor(shadow_index)
    local r, g, b = getPaletteColor(color_index)
    love.graphics.setColor(sr, sg, sb)
    love.graphics.print(text, x + 1, y + 1)
    love.graphics.setColor(r, g, b)
    love.graphics.print(text, x, y)
end

-- Convert Picotron rotation (0-1) to radians
local function pico_to_rad(pico_rot)
    return pico_rot * math.pi * 2
end

-- Generate sphere mesh (8 sides, 6 height segments)
-- Uses Picotron's 0-1 rotation system (cos/sin expect 0-1 where 1 = full rotation)
local function generate_sphere(sprite_index)
    local verts = {}
    local faces = {}

    local rings = 6
    local segments = 8

    -- Top vertex (north pole)
    table.insert(verts, {x = 0, y = 1, z = 0})

    -- Middle rings
    for ring = 1, rings - 1 do
        local v = ring / rings  -- Vertical position (0 to 1)
        local angle_v = v * 0.5  -- Picotron: 0.5 = 180 degrees (half turn)
        local y = math.cos(pico_to_rad(angle_v))
        local radius = math.sin(pico_to_rad(angle_v))

        for seg = 0, segments - 1 do
            local angle_h = seg / segments  -- Picotron: 0-1 = full rotation
            local x = math.cos(pico_to_rad(angle_h)) * radius
            local z = math.sin(pico_to_rad(angle_h)) * radius
            table.insert(verts, {x = x, y = y, z = z})
        end
    end

    -- Bottom vertex (south pole)
    table.insert(verts, {x = 0, y = -1, z = 0})

    -- UV scale for texture
    local uv_scale_u = 64
    local uv_scale_v = 32
    local uv_offset = -uv_scale_v

    -- Top cap faces
    for seg = 0, segments - 1 do
        local next_seg = (seg + 1) % segments
        local v1 = 1
        local v2 = 2 + seg
        local v3 = 2 + next_seg

        local u1 = (seg + 0.5) / segments * uv_scale_u
        local u2 = seg / segments * uv_scale_u
        local u3 = (seg + 1) / segments * uv_scale_u
        local v_top = uv_scale_v - uv_offset
        local v_ring1 = uv_scale_v - ((1 / rings) * uv_scale_v + uv_offset)

        table.insert(faces, {
            v1, v3, v2, sprite_index,
            {x = u1, y = v_top}, {x = u3, y = v_ring1}, {x = u2, y = v_ring1}
        })
    end

    -- Middle ring faces
    for ring = 0, rings - 3 do
        local ring_start = 2 + ring * segments
        local next_ring_start = 2 + (ring + 1) * segments

        for seg = 0, segments - 1 do
            local next_seg = (seg + 1) % segments

            local v1 = ring_start + seg
            local v2 = ring_start + next_seg
            local v3 = next_ring_start + next_seg
            local v4 = next_ring_start + seg

            local u1 = seg / segments * uv_scale_u
            local u2 = (seg + 1) / segments * uv_scale_u
            local v1_uv = uv_scale_v - ((ring + 1) / rings * uv_scale_v + uv_offset)
            local v2_uv = uv_scale_v - ((ring + 2) / rings * uv_scale_v + uv_offset)

            table.insert(faces, {
                v1, v2, v3, sprite_index,
                {x = u1, y = v1_uv}, {x = u2, y = v1_uv}, {x = u2, y = v2_uv}
            })
            table.insert(faces, {
                v1, v3, v4, sprite_index,
                {x = u1, y = v1_uv}, {x = u2, y = v2_uv}, {x = u1, y = v2_uv}
            })
        end
    end

    -- Bottom cap faces
    local last_ring_start = 2 + (rings - 2) * segments
    local bottom_vertex = #verts
    for seg = 0, segments - 1 do
        local next_seg = (seg + 1) % segments
        local v1 = last_ring_start + seg
        local v2 = last_ring_start + next_seg
        local v3 = bottom_vertex

        local u1 = seg / segments * uv_scale_u
        local u2 = (seg + 1) / segments * uv_scale_u
        local u_center = (seg + 0.5) / segments * uv_scale_u

        table.insert(faces, {
            v1, v2, v3, sprite_index,
            {x = u1, y = uv_scale_v - (uv_scale_v * (rings - 1) / rings + uv_offset)},
            {x = u2, y = uv_scale_v - (uv_scale_v * (rings - 1) / rings + uv_offset)},
            {x = u_center, y = uv_scale_v - (uv_scale_v + uv_offset)}
        })
    end

    return verts, faces
end

-- Get simulated ship velocity based on ship's up vector
-- Replicate Picotron's get_ship_up_vector() exactly
local function get_ship_velocity()
    -- Picotron uses 0-1 rotations directly with cos/sin (1 = full turn = 2*pi)
    local cos_pitch = math.cos(SHIP_PITCH * 2 * math.pi)
    local sin_pitch = math.sin(SHIP_PITCH * 2 * math.pi)
    local cos_yaw = math.cos(SHIP_YAW * 2 * math.pi)
    local sin_yaw = math.sin(SHIP_YAW * 2 * math.pi)
    local cos_roll = math.cos(SHIP_ROLL * 2 * math.pi)
    local sin_roll = math.sin(SHIP_ROLL * 2 * math.pi)

    -- Start with up vector (0, 1, 0)
    local x, y, z = 0, 1, 0

    -- Apply yaw (Y axis rotation)
    local x_yaw = x * cos_yaw - z * sin_yaw
    local z_yaw = x * sin_yaw + z * cos_yaw

    -- Apply pitch (X axis rotation)
    local y_pitch = y * cos_pitch - z_yaw * sin_pitch
    local z_pitch = y * sin_pitch + z_yaw * cos_pitch

    -- Apply roll (Z axis rotation)
    local x_roll = x_yaw * cos_roll - y_pitch * sin_roll
    local y_roll = x_yaw * sin_roll + y_pitch * cos_roll

    return x_roll, y_roll, z_pitch
end

-- Get starfield direction - stars move DOWN (opposite to ship's up vector)
-- Ship is "flying up", so stars fly past in the down direction
local function get_starfield_direction()
    local up_x, up_y, up_z = get_ship_velocity()
    -- Return down vector (negative of up) - stars move down relative to ship
    return -up_x, -up_y, -up_z
end

-- Add a space line for background motion
function menu.add_space_line()
    local depth_colors = {21, 5, 22}

    -- Stars spawn opposite to where they fly (so they fly toward/past ship)
    local dir_x, dir_y, dir_z = get_starfield_direction()
    local spawn_x, spawn_y, spawn_z = -dir_x, -dir_y, -dir_z
    local spread = math.random() * STARFIELD_SPREAD + 10

    table.insert(menu.space_lines, {
        x = SHIP_X + spawn_x * STARFIELD_SPAWN_DIST + (math.random() - 0.5) * spread,
        y = SHIP_Y + spawn_y * STARFIELD_SPAWN_DIST + (math.random() - 0.5) * spread,
        z = SHIP_Z + spawn_z * STARFIELD_SPAWN_DIST,
        speed = math.random() * (STARFIELD_SPEED_MAX - STARFIELD_SPEED_MIN) + STARFIELD_SPEED_MIN,
        color = depth_colors[math.random(1, 3)],
        length = math.random() * (STARFIELD_LENGTH_MAX - STARFIELD_LENGTH_MIN) + STARFIELD_LENGTH_MIN
    })
end

-- Update menu options based on unlocked missions
function menu.update_options()
    menu.options = {}

    -- Mission 0: Story (always unlocked)
    table.insert(menu.options, {text = "MISSION 0: TOM LANDER", action = "story", locked = false})

    -- Mission 1 (unlocked)
    if menu.mission_progress.mission_1 then
        table.insert(menu.options, {text = "MISSION 1: ENGINE TEST", mission = 1, locked = false})
    else
        table.insert(menu.options, {text = "MISSION 1: [LOCKED]", mission = 1, locked = true})
    end

    -- Mission 2 (locked per user request)
    if menu.mission_progress.mission_2 then
        table.insert(menu.options, {text = "MISSION 2: CARGO DELIVERY", mission = 2, locked = false})
    else
        table.insert(menu.options, {text = "MISSION 2: [LOCKED]", mission = 2, locked = true})
    end

    -- Mission 3 (locked per user request)
    if menu.mission_progress.mission_3 then
        table.insert(menu.options, {text = "MISSION 3: SCIENTIFIC MISSION", mission = 3, locked = false})
    else
        table.insert(menu.options, {text = "MISSION 3: [LOCKED]", mission = 3, locked = true})
    end

    -- Mission 4 (locked per user request)
    if menu.mission_progress.mission_4 then
        table.insert(menu.options, {text = "MISSION 4: OCEAN RESCUE", mission = 4, locked = false})
    else
        table.insert(menu.options, {text = "MISSION 4: [LOCKED]", mission = 4, locked = true})
    end

    -- Mission 5 (locked per user request)
    if menu.mission_progress.mission_5 then
        table.insert(menu.options, {text = "MISSION 5: SECRET WEAPON", mission = 5, locked = false})
    else
        table.insert(menu.options, {text = "MISSION 5: [LOCKED]", mission = 5, locked = true})
    end

    -- Mission 6 (locked per user request)
    if menu.mission_progress.mission_6 then
        table.insert(menu.options, {text = "MISSION 6: ALIEN INVASION", mission = 6, locked = false})
    else
        table.insert(menu.options, {text = "MISSION 6: [LOCKED]", mission = 6, locked = true})
    end

    table.insert(menu.options, {text = "QUIT", action = "quit", locked = false})

    -- Clamp selected option
    if menu.selected_option > #menu.options then
        menu.selected_option = #menu.options
    end

    -- Skip locked options
    while menu.options[menu.selected_option] and menu.options[menu.selected_option].locked do
        menu.selected_option = menu.selected_option + 1
        if menu.selected_option > #menu.options then
            menu.selected_option = 1
        end
    end
end

-- Initialize menu
function menu.load()
    love.window.setTitle("Tom Lander")
    windowWidth, windowHeight = love.graphics.getDimensions()

    menu.active = true
    menu.show_options = false
    menu.show_mode_select = false
    menu.selected_option = 1
    menu.selected_mode = 1
    menu.pending_mission = nil

    -- Initialize mission progress (only missions 0 and 1 unlocked)
    menu.mission_progress = {
        mission_1 = true,   -- Unlocked
        mission_2 = false,  -- Locked
        mission_3 = false,  -- Locked
        mission_4 = false,  -- Locked
        mission_5 = false,  -- Locked
        mission_6 = false   -- Locked
    }

    menu.update_options()

    -- Initialize renderer
    renderer.init(config.RENDER_WIDTH, config.RENDER_HEIGHT)
    softwareImage = love.graphics.newImage(renderer.getImageData())

    -- Create projection matrix
    local aspect = config.RENDER_WIDTH / config.RENDER_HEIGHT
    projMatrix = mat4.perspective(config.FOV, aspect, config.NEAR_PLANE, config.FAR_PLANE)

    -- Create camera
    cam = camera_module.new(0, 0, 0)
    cam.pitch = 0
    cam.yaw = 0
    camera_module.updateVectors(cam)

    -- Disable fog for menu (clear color is passed to clearBuffers() in draw)
    renderer.setFog(false)

    -- Generate planet sphere
    local planet_verts, planet_faces = generate_sphere(Constants.SPRITE_PLANET)
    menu.planet = {
        verts = planet_verts,
        faces = planet_faces,
        x = PLANET_X,
        y = PLANET_Y,
        z = PLANET_Z,
        rotation = 0,
        scale = PLANET_SCALE
    }

    -- Scale planet vertices
    for i, v in ipairs(menu.planet.verts) do
        menu.planet.verts[i] = {
            x = v.x * PLANET_SCALE,
            y = v.y * PLANET_SCALE,
            z = v.z * PLANET_SCALE
        }
    end

    -- Generate cloud sphere
    local cloud_verts, cloud_faces = generate_sphere(Constants.SPRITE_CLOUDS)
    local cloud_scale = PLANET_SCALE + CLOUD_SCALE_OFFSET
    menu.clouds = {
        verts = cloud_verts,
        faces = cloud_faces,
        x = PLANET_X,
        y = PLANET_Y,
        z = PLANET_Z,
        rotation = 0,
        scale = cloud_scale
    }

    -- Scale cloud vertices
    for i, v in ipairs(menu.clouds.verts) do
        menu.clouds.verts[i] = {
            x = v.x * cloud_scale,
            y = v.y * cloud_scale,
            z = v.z * cloud_scale
        }
    end

    -- Initialize space lines
    menu.space_lines = {}
    for i = 1, STARFIELD_COUNT do
        menu.add_space_line()
    end

    -- Load ship mesh
    local success, result = pcall(function()
        return obj_loader.load("assets/cross_lander.obj")
    end)
    if success and result then
        menu.ship_mesh = result
        print("Menu: Ship mesh loaded: " .. #result.vertices .. " vertices")
    else
        print("Menu: Could not load ship mesh: " .. tostring(result))
    end

    -- Load flame mesh
    success, result = pcall(function()
        return obj_loader.load("assets/flame.obj")
    end)
    if success and result then
        menu.flame_mesh = result
        print("Menu: Flame mesh loaded: " .. #result.vertices .. " vertices")
    else
        print("Menu: Could not load flame mesh: " .. tostring(result))
    end

    -- Load logo image (texture 65) with nearest neighbor filtering for pixel art
    logoImage = Constants.getTexture(65)
    if logoImage then
        logoImage:setFilter("nearest", "nearest")
        print("Menu: Logo loaded")
    end

    -- Create shader to make black pixels transparent
    blackTransparentShader = love.graphics.newShader([[
        vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
            vec4 pixel = Texel(tex, texture_coords);
            // If pixel is close to black, make it transparent
            if (pixel.r < 0.1 && pixel.g < 0.1 && pixel.b < 0.1) {
                return vec4(0.0, 0.0, 0.0, 0.0);
            }
            return pixel * color;
        }
    ]])
end

-- Select current menu option
function menu.select_option()
    local option = menu.options[menu.selected_option]

    if option.locked then
        return nil
    end

    if option.mission then
        -- Show mode selection screen
        menu.pending_mission = option.mission
        menu.show_mode_select = true
        menu.show_options = false
        menu.selected_mode = 1
    elseif option.action == "story" then
        -- Start story/mission 0 - go directly to flight for now
        menu.active = false
        scene_manager.switch("flight")
    elseif option.action == "quit" then
        love.event.quit()
    end

    return nil
end

-- Select game mode
function menu.select_mode()
    menu.active = false
    local mode = (menu.selected_mode == 1) and "arcade" or "simulation"
    -- Store selected mission and mode for the flight scene
    menu.selected_mission = menu.pending_mission
    menu.game_mode = mode
    scene_manager.switch("flight")
end

-- Update menu
function menu.update(dt)
    if not menu.active then return end

    -- Debug camera controls (arrow keys)
    -- local cam_speed = 1.0 * dt
    -- if love.keyboard.isDown("left") then
    --     debug_cam_yaw = debug_cam_yaw - cam_speed
    -- end
    -- if love.keyboard.isDown("right") then
    --     debug_cam_yaw = debug_cam_yaw + cam_speed
    -- end
    -- if love.keyboard.isDown("up") then
    --     debug_cam_pitch = debug_cam_pitch - cam_speed
    -- end
    -- if love.keyboard.isDown("down") then
    --     debug_cam_pitch = debug_cam_pitch + cam_speed
    -- end

    -- Rotate planet and clouds
    menu.planet.rotation = menu.planet.rotation + dt * PLANET_ROTATION_SPEED
    menu.clouds.rotation = menu.clouds.rotation + dt * CLOUD_ROTATION_SPEED

    -- Update space lines
    local dir_x, dir_y, dir_z = get_starfield_direction()

    for i = #menu.space_lines, 1, -1 do
        local line = menu.space_lines[i]
        line.x = line.x + dir_x * line.speed
        line.y = line.y + dir_y * line.speed
        line.z = line.z + dir_z * line.speed

        -- Reset line when too far
        local dx = line.x - SHIP_X
        local dy = line.y - SHIP_Y
        local dz = line.z - SHIP_Z
        local dist_sq = dx*dx + dy*dy + dz*dz

        if dist_sq > STARFIELD_DESPAWN_DIST * STARFIELD_DESPAWN_DIST then
            table.remove(menu.space_lines, i)
            menu.add_space_line()
        end
    end
end

-- Handle key press
function menu.keypressed(key)
    if not menu.active then return end

    -- Title screen - press to continue
    if not menu.show_options and not menu.show_mode_select then
        if key == "z" or key == "x" or key == "return" or key == "space" then
            menu.show_options = true
        end
        return
    end

    -- Mode selection screen
    if menu.show_mode_select then
        if key == "up" or key == "down" then
            menu.selected_mode = (menu.selected_mode == 1) and 2 or 1
        elseif key == "z" or key == "x" or key == "return" or key == "space" then
            menu.select_mode()
        elseif key == "tab" or key == "escape" then
            menu.show_mode_select = false
            menu.show_options = true
            menu.pending_mission = nil
        end
        return
    end

    -- Mission selection screen
    if key == "up" then
        menu.selected_option = menu.selected_option - 1
        if menu.selected_option < 1 then
            menu.selected_option = #menu.options
        end
        -- Skip locked options
        while menu.options[menu.selected_option].locked do
            menu.selected_option = menu.selected_option - 1
            if menu.selected_option < 1 then
                menu.selected_option = #menu.options
            end
        end
    elseif key == "down" then
        menu.selected_option = menu.selected_option + 1
        if menu.selected_option > #menu.options then
            menu.selected_option = 1
        end
        -- Skip locked options
        while menu.options[menu.selected_option].locked do
            menu.selected_option = menu.selected_option + 1
            if menu.selected_option > #menu.options then
                menu.selected_option = 1
            end
        end
    elseif key == "z" or key == "x" or key == "return" or key == "space" then
        menu.select_option()
    elseif key == "escape" then
        love.event.quit()
    end
end

-- Draw menu
function menu.draw()
    if not menu.active then return end

    -- Clear to black
    love.graphics.clear(0, 0, 0)

    -- Render 3D background (clear to black)
    renderer.clearBuffersBlack()

    -- Build view matrix with debug rotation
    local viewMatrix = camera_module.getViewMatrix(cam)
    -- Apply debug camera rotation
    local debugRotMatrix = mat4.multiply(mat4.rotationY(debug_cam_yaw), mat4.rotationX(debug_cam_pitch))
    viewMatrix = mat4.multiply(viewMatrix, debugRotMatrix)
    local mvpMatrix = mat4.multiply(projMatrix, viewMatrix)
    renderer.setMatrices(mvpMatrix, {x = cam.pos.x, y = cam.pos.y, z = cam.pos.z})

    -- Draw planet first (smaller sphere, solid)
    local planetTexData = Constants.getTextureData(Constants.SPRITE_PLANET)
    if planetTexData then
        menu.draw_sphere(menu.planet, PLANET_PITCH, PLANET_YAW + menu.planet.rotation, PLANET_ROLL, planetTexData)
    end

    -- Draw clouds on top (larger sphere, black pixels transparent)
    -- Use 50% dither pattern like Picotron
    local cloudTexData = Constants.getTextureData(Constants.SPRITE_CLOUDS)
    if cloudTexData then
        renderer.setDitherPattern(0x5A5A)  -- 50% checkerboard (0b0101101001011010)
        menu.draw_sphere(menu.clouds, PLANET_PITCH, PLANET_YAW + menu.clouds.rotation, PLANET_ROLL, cloudTexData)
        renderer.resetDitherPattern()
    end

    -- Draw ship with thrusters
    menu.draw_ship()

    -- Draw space lines LAST, as background (skipZBuffer = true)
    -- They only draw where nothing else has been drawn (clear pixels)
    local dir_x, dir_y, dir_z = get_starfield_direction()

    for _, space_line in ipairs(menu.space_lines) do
        -- Start point in world space
        local x1 = space_line.x
        local y1 = space_line.y
        local z1 = space_line.z

        -- End point extends in the direction of movement
        local x2 = x1 + dir_x * space_line.length
        local y2 = y1 + dir_y * space_line.length
        local z2 = z1 + dir_z * space_line.length

        local c = Palette.colors[space_line.color] or Palette.colors[7]
        renderer.drawLine3D({x1, y1, z1}, {x2, y2, z2}, c[1], c[2], c[3], true)  -- skipZBuffer = true
    end

    -- Update and display software rendered image
    softwareImage:replacePixels(renderer.getImageData())

    -- Get current window dimensions
    local windowWidth, windowHeight = love.graphics.getDimensions()

    -- Calculate scale maintaining aspect ratio (letterboxing)
    local scaleX = windowWidth / config.RENDER_WIDTH
    local scaleY = windowHeight / config.RENDER_HEIGHT
    local scale = math.min(scaleX, scaleY)

    -- Calculate offset to center the image (letterboxing)
    local offsetX = (windowWidth - config.RENDER_WIDTH * scale) / 2
    local offsetY = (windowHeight - config.RENDER_HEIGHT * scale) / 2

    -- Clear to black for letterboxing
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(softwareImage, offsetX, offsetY, 0, scale, scale)

    -- Draw UI on top (scaled to match render resolution)
    -- All UI code uses config.RENDER_WIDTH/HEIGHT (480x270) as source of truth
    love.graphics.push()
    love.graphics.translate(offsetX, offsetY)
    love.graphics.scale(scale, scale)

    if menu.show_mode_select then
        -- Mode selection screen
        menu.draw_mode_select()
    elseif menu.show_options then
        -- Mission selection screen
        menu.draw_options()
    else
        -- Title screen with logo
        menu.draw_title()
    end

    love.graphics.pop()
end

-- Draw sphere mesh
function menu.draw_sphere(sphere, pitch, yaw, roll, texData)
    -- Build model matrix for the sphere (convert Picotron 0-1 rotations to radians)
    -- For self-rotation: M = T * R (rotate around center, then translate to world position)
    -- In our multiply order: we build right-to-left, so rotation first then translation
    local rotMatrix = mat4.identity()
    rotMatrix = mat4.multiply(mat4.rotationY(pico_to_rad(yaw)), rotMatrix)
    rotMatrix = mat4.multiply(mat4.rotationX(pico_to_rad(pitch)), rotMatrix)
    rotMatrix = mat4.multiply(mat4.rotationZ(pico_to_rad(roll)), rotMatrix)

    local transMatrix = mat4.translation(sphere.x, sphere.y, sphere.z)
    local modelMatrix = mat4.multiply(transMatrix, rotMatrix)

    for _, face in ipairs(sphere.faces) do
        local v1 = sphere.verts[face[1]]
        local v2 = sphere.verts[face[2]]
        local v3 = sphere.verts[face[3]]

        if v1 and v2 and v3 then
            local p1 = mat4.multiplyVec4(modelMatrix, {v1.x, v1.y, v1.z, 1})
            local p2 = mat4.multiplyVec4(modelMatrix, {v2.x, v2.y, v2.z, 1})
            local p3 = mat4.multiplyVec4(modelMatrix, {v3.x, v3.y, v3.z, 1})

            local uv1 = face[5] or {x = 0, y = 0}
            local uv2 = face[6] or {x = 1, y = 0}
            local uv3 = face[7] or {x = 0, y = 1}

            -- Reverse winding order (v1, v3, v2) to match renderer's face culling convention
            renderer.drawTriangle3D(
                {pos = {p1[1], p1[2], p1[3]}, uv = {uv1.x / 64, uv1.y / 32}},
                {pos = {p3[1], p3[2], p3[3]}, uv = {uv3.x / 64, uv3.y / 32}},
                {pos = {p2[1], p2[2], p2[3]}, uv = {uv2.x / 64, uv2.y / 32}},
                nil,
                texData
            )
        end
    end
end

-- Draw ship with animated thrusters
function menu.draw_ship()
    if not menu.ship_mesh then return end

    local time = love.timer.getTime()
    local bob_y = math.sin(time * SHIP_BOB_SPEED_Y) * SHIP_BOB_AMOUNT_Y
    local bob_x = math.sin(time * SHIP_BOB_SPEED_X) * SHIP_BOB_AMOUNT_X

    -- Build model matrix (convert Picotron 0-1 rotations to radians)
    -- In Picotron, SHIP_SCALE is applied directly to vertices, then the mesh is positioned
    local modelMatrix = mat4.identity()
    modelMatrix = mat4.multiply(mat4.scale(SHIP_SCALE, SHIP_SCALE, SHIP_SCALE), modelMatrix)
    modelMatrix = mat4.multiply(mat4.rotationY(pico_to_rad(SHIP_YAW)), modelMatrix)
    modelMatrix = mat4.multiply(mat4.rotationX(pico_to_rad(SHIP_PITCH)), modelMatrix)
    modelMatrix = mat4.multiply(mat4.rotationZ(pico_to_rad(SHIP_ROLL)), modelMatrix)
    modelMatrix = mat4.multiply(mat4.translation(SHIP_X + bob_x, SHIP_Y + bob_y, SHIP_Z), modelMatrix)

    -- Store model matrix for extracting up vector (for starfield direction)
    menu.ship_model_matrix = modelMatrix

    local shipTexData = Constants.getTextureData(Constants.SPRITE_SHIP)

    -- Draw ship mesh
    for _, tri in ipairs(menu.ship_mesh.triangles) do
        local v1 = menu.ship_mesh.vertices[tri[1]]
        local v2 = menu.ship_mesh.vertices[tri[2]]
        local v3 = menu.ship_mesh.vertices[tri[3]]

        local p1 = mat4.multiplyVec4(modelMatrix, {v1.pos[1], v1.pos[2], v1.pos[3], 1})
        local p2 = mat4.multiplyVec4(modelMatrix, {v2.pos[1], v2.pos[2], v2.pos[3], 1})
        local p3 = mat4.multiplyVec4(modelMatrix, {v3.pos[1], v3.pos[2], v3.pos[3], 1})

        renderer.drawTriangle3D(
            {pos = {p1[1], p1[2], p1[3]}, uv = v1.uv},
            {pos = {p2[1], p2[2], p2[3]}, uv = v2.uv},
            {pos = {p3[1], p3[2], p3[3]}, uv = v3.uv},
            nil,
            shipTexData
        )
    end

    -- Draw flames on all 4 engines with 50% dither
    if menu.flame_mesh then
        local flameTexData = Constants.getTextureData(Constants.SPRITE_FLAME)
        local flame_time = time * FLAME_SPEED

        -- Engine positions relative to ship (in ship local space)
        local engine_positions = {ENGINE_RIGHT, ENGINE_LEFT, ENGINE_FRONT, ENGINE_BACK}

        -- Set 50% dither pattern for flames
        renderer.setDitherPattern(0x5A5A)

        for engine_idx, engine in ipairs(engine_positions) do
            -- Flickering scale
            local base_flicker = math.sin(flame_time + engine_idx * 2.5) * FLAME_FLICKER_AMOUNT
            local noise = math.sin(flame_time * 3.7 + engine_idx * 0.5) * FLAME_NOISE_AMOUNT
            local flame_scale = 1.0 + base_flicker + noise

            -- Build flame model matrix (same transform order as ship)
            local flameMatrix = mat4.identity()
            flameMatrix = mat4.multiply(mat4.scale(SHIP_SCALE * flame_scale, SHIP_SCALE * flame_scale, SHIP_SCALE * flame_scale), flameMatrix)
            flameMatrix = mat4.multiply(mat4.translation(engine.x, engine.y, engine.z), flameMatrix)
            flameMatrix = mat4.multiply(mat4.rotationY(pico_to_rad(SHIP_YAW)), flameMatrix)
            flameMatrix = mat4.multiply(mat4.rotationX(pico_to_rad(SHIP_PITCH)), flameMatrix)
            flameMatrix = mat4.multiply(mat4.rotationZ(pico_to_rad(SHIP_ROLL)), flameMatrix)
            flameMatrix = mat4.multiply(mat4.translation(SHIP_X + bob_x, SHIP_Y + bob_y, SHIP_Z), flameMatrix)

            for _, tri in ipairs(menu.flame_mesh.triangles) do
                local v1 = menu.flame_mesh.vertices[tri[1]]
                local v2 = menu.flame_mesh.vertices[tri[2]]
                local v3 = menu.flame_mesh.vertices[tri[3]]

                local p1 = mat4.multiplyVec4(flameMatrix, {v1.pos[1], v1.pos[2], v1.pos[3], 1})
                local p2 = mat4.multiplyVec4(flameMatrix, {v2.pos[1], v2.pos[2], v2.pos[3], 1})
                local p3 = mat4.multiplyVec4(flameMatrix, {v3.pos[1], v3.pos[2], v3.pos[3], 1})

                renderer.drawTriangle3D(
                    {pos = {p1[1], p1[2], p1[3]}, uv = v1.uv},
                    {pos = {p2[1], p2[2], p2[3]}, uv = v2.uv},
                    {pos = {p3[1], p3[2], p3[3]}, uv = v3.uv},
                    nil,
                    flameTexData
                )
            end
        end

        renderer.resetDitherPattern()
    end
end

-- Draw title screen
function menu.draw_title()
    -- Use render resolution as source of truth (480x270)
    local w, h = config.RENDER_WIDTH, config.RENDER_HEIGHT

    -- Draw logo if available (texture 65)
    if logoImage then
        local logo_w, logo_h = logoImage:getDimensions()
        local logo_scale = 1.5
        local scaled_w = logo_w * logo_scale
        local scaled_h = logo_h * logo_scale
        local logo_x = (w - scaled_w) / 2
        local logo_y = (h - scaled_h) / 2 - 20

        -- Use shader to make black transparent
        love.graphics.setShader(blackTransparentShader)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(logoImage, logo_x, logo_y, 0, logo_scale, logo_scale)
        love.graphics.setShader()  -- Reset shader
    else
        -- Fallback text title
        love.graphics.setColor(1, 1, 1)
        love.graphics.setFont(love.graphics.newFont(16))
        love.graphics.printf("THE RETURN OF TOM LANDER", 0, h / 2 - 30, w, "center")
    end

    -- Draw "press Z to start" hint
    love.graphics.setFont(love.graphics.newFont(8))
    local hint = "[Z] to start"
    local hint_y = h * 0.75

    -- Drop shadow
    love.graphics.setColor(0, 0, 0)
    love.graphics.printf(hint, 1, hint_y + 1, w, "center")
    -- Main text (dark blue color 1)
    local r, g, b = getPaletteColor(1)
    love.graphics.setColor(r, g, b)
    love.graphics.printf(hint, 0, hint_y, w, "center")
end

-- Draw mission options screen
function menu.draw_options()
    -- Use render resolution as source of truth (480x270)
    local w, h = config.RENDER_WIDTH, config.RENDER_HEIGHT

    love.graphics.setFont(love.graphics.newFont(8))

    local menu_x = w / 2
    local menu_y = 40

    -- Calculate box dimensions
    local box_padding = 10
    local title = "The Return of Tom Lander"
    local title_width = #title * 5
    local max_option_width = 0
    for i, option in ipairs(menu.options) do
        local option_width = (#option.text + 3) * 5
        if option_width > max_option_width then
            max_option_width = option_width
        end
    end
    local box_width = math.max(title_width, max_option_width) + box_padding * 2 + 20
    local box_height = 20 + #menu.options * 12 + box_padding * 2
    local box_x = menu_x - box_width / 2
    local box_y = menu_y - box_padding

    -- Draw dithered background (semi-transparent dark box)
    love.graphics.setColor(0.1, 0.15, 0.3, 0.7)
    love.graphics.rectangle("fill", box_x, box_y, box_width, box_height)

    -- Draw border
    local r, g, b = getPaletteColor(6)
    love.graphics.setColor(r, g, b)
    love.graphics.rectangle("line", box_x, box_y, box_width, box_height)

    -- Draw title
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(title, box_x, menu_y, box_width, "center")
    menu_y = menu_y + 18

    -- Draw options
    for i, option in ipairs(menu.options) do
        local color_index
        if option.locked then
            color_index = 5  -- Grey for locked
        elseif i == menu.selected_option then
            color_index = 11  -- Cyan for selected
        else
            color_index = 6  -- Light grey for unselected
        end

        local prefix = (i == menu.selected_option) and "> " or "  "
        local r, g, b = getPaletteColor(color_index)
        love.graphics.setColor(r, g, b)
        love.graphics.print(prefix .. option.text, box_x + 10, menu_y + (i - 1) * 12)
    end
end

-- Draw mode selection screen
function menu.draw_mode_select()
    -- Use render resolution as source of truth (480x270)
    local w, h = config.RENDER_WIDTH, config.RENDER_HEIGHT

    love.graphics.setFont(love.graphics.newFont(8))

    local menu_x = w / 2
    local menu_y = 50

    local modes = {
        {name = "ARCADE", desc = "Assisted flight with auto-balance\nand multi-thruster controls"},
        {name = "SIMULATION", desc = "Manual flight with one button\nper thruster - no assists"}
    }

    -- Draw title
    local title = "SELECT MODE"
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(title, 0, menu_y, w, "center")
    menu_y = menu_y + 24

    -- Draw mode options
    for i, mode in ipairs(modes) do
        local color_index = (i == menu.selected_mode) and 11 or 6
        local prefix = (i == menu.selected_mode) and "> " or "  "

        local r, g, b = getPaletteColor(color_index)
        love.graphics.setColor(r, g, b)
        love.graphics.print(prefix .. mode.name, w / 2 - 60, menu_y)
        menu_y = menu_y + 14
    end

    -- Draw description for selected mode
    menu_y = menu_y + 10
    local selected_mode = modes[menu.selected_mode]
    if selected_mode then
        local r, g, b = getPaletteColor(6)
        love.graphics.setColor(r, g, b)
        for line in selected_mode.desc:gmatch("[^\n]+") do
            love.graphics.print("  " .. line, w / 2 - 60, menu_y)
            menu_y = menu_y + 10
        end
    end

    -- Controls hint
    menu_y = h - 40
    local r, g, b = getPaletteColor(6)
    love.graphics.setColor(r, g, b)
    love.graphics.print("[TAB] Back", w / 2 - 60, menu_y)
end

return menu
