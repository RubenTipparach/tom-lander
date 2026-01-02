-- Main entry point with scene manager
local scene_manager = require("scene_manager")

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
end

function love.draw()
    scene_manager.draw()
end

function love.keypressed(key)
    scene_manager.keypressed(key)
end
