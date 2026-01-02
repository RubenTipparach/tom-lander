-- Main entry point with scene manager
local scene_manager = require("scene_manager")
local config = require("config")
local renderer = require("renderer_dda")

-- Frame rate tracking
local frameCount = 0
local frameTimeAccum = 0
local logInterval = 5  -- Log every 1 second

-- Register all scenes
scene_manager.register("menu", require("menu"))
scene_manager.register("flight", require("flight_scene"))
scene_manager.register("ship_viewer", require("ship_viewer"))

function love.load()
    -- Initialize renderer ONCE at startup (calling init twice causes JIT issues)
    renderer.init(config.RENDER_WIDTH, config.RENDER_HEIGHT)

    -- Window mode is set in conf.lua
    -- Start with menu
    scene_manager.switch("menu")
end

function love.update(dt)
    scene_manager.update(dt)

    -- Track frame rate
    frameCount = frameCount + 1
    frameTimeAccum = frameTimeAccum + dt

    if frameTimeAccum >= logInterval then
        local avgFPS = frameCount / frameTimeAccum
        local menu3d = config.MENU_3D_ENABLED and "ON" or "OFF"
        print(string.format("[FPS] Avg: %.1f | Menu3D: %s", avgFPS, menu3d))
        frameCount = 0
        frameTimeAccum = 0
    end
end

function love.draw()
    scene_manager.draw()
end

function love.keypressed(key)
    scene_manager.keypressed(key)
end
