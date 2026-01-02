-- Main entry point with scene manager
local scene_manager = require("scene_manager")

-- Frame rate tracking
local frameCount = 0
local frameTimeAccum = 0
local logInterval = 5  -- Log every 5 seconds

-- Register all scenes
scene_manager.register("menu", require("menu"))
scene_manager.register("flight", require("flight_scene"))
scene_manager.register("ship_viewer", require("ship_viewer"))

function love.load()
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
        print(string.format("[FPS] Avg: %.1f (over %.1fs)", avgFPS, frameTimeAccum))
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
