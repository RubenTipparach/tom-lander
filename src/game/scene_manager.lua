-- Simple Scene Manager
local scene_manager = {}

local currentScene = nil
local scenes = {}

-- Register a scene
function scene_manager.register(name, scene)
    scenes[name] = scene
end

-- Switch to a scene
function scene_manager.switch(name)
    if not scenes[name] then
        error("Scene '" .. name .. "' not found")
    end

    currentScene = scenes[name]

    -- Call the scene's load function if it exists
    if currentScene.load then
        currentScene.load()
    end
end

-- Get current scene
function scene_manager.current()
    return currentScene
end

-- Forward love callbacks to current scene
function scene_manager.update(dt)
    if currentScene and currentScene.update then
        currentScene.update(dt)
    end
end

function scene_manager.draw()
    if currentScene and currentScene.draw then
        currentScene.draw()
    end
end

function scene_manager.keypressed(key)
    if currentScene and currentScene.keypressed then
        currentScene.keypressed(key)
    end
end

return scene_manager
