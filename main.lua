-- Main entry point with scene manager
local scene_manager = require("scene_manager")
local config = require("config")
local renderer = require("renderer_dda")
local profile = require("profiler")

-- Frame rate tracking
local frameCount = 0
local frameTimeAccum = 0
local logInterval = 5  -- Log every 5 seconds

-- Register all scenes
scene_manager.register("menu", require("menu"))
scene_manager.register("flight", require("flight_scene"))
scene_manager.register("ship_viewer", require("ship_viewer"))
scene_manager.register("cutscene", require("cutscene_scene"))

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

    -- Draw profiler overlay (on top of everything)
    profile.draw()
end

function love.keypressed(key)
    -- F3 toggles profiler
    if key == "f3" then
        local enabled = profile.toggle()
        print("Profiler: " .. (enabled and "ON" or "OFF"))
        return
    end

    scene_manager.keypressed(key)
end
