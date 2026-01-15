-- Cutscene Scene wrapper
-- Wraps the Cutscene module for use with scene_manager

local cutscene_scene = {}
local Cutscene = require("cutscene")
local scene_manager = require("scene_manager")
local AudioManager = require("audio_manager")

function cutscene_scene.load()
    -- Stop menu music and play intro music
    AudioManager.stop_music()
    AudioManager.play_music("intro", AudioManager.music_volume)
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
