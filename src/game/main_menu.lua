-- Chieftan Engine - Main Entry Point with Menu
local menu = require("menu")

function love.load()
    menu.load()
end

function love.update(dt)
    menu.update(dt)
end

function love.draw()
    menu.draw()
end

function love.keypressed(key)
    menu.keypressed(key)
end
