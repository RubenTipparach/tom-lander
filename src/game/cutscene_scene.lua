-- Cutscene Scene wrapper
-- Wraps the Cutscene module for use with scene_manager

local cutscene_scene = {}
local Cutscene = require("cutscene")
local scene_manager = require("scene_manager")

function cutscene_scene.load()
    Cutscene.start(1)
end

function cutscene_scene.update(dt)
    Cutscene.update(dt)
end

function cutscene_scene.draw()
    Cutscene.draw()
end

function cutscene_scene.keypressed(key)
    local finished = Cutscene.keypressed(key)
    if finished then
        -- Cutscene complete, return to menu
        scene_manager.switch("menu")
    end
end

function cutscene_scene.unload()
    Cutscene.stop()
end

return cutscene_scene
