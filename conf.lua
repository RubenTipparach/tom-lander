function love.conf(t)
    t.console = true  -- Enable console output on Windows
    t.window.title = "Chieftan Engine"
    t.window.width = 960
    t.window.height = 540
    t.window.resizable = true

    -- Add src directory to Lua package path
    t.identity = "chieftan-engine"

    -- This runs before love.load, so we set package.path here
    if love.filesystem then
        love.filesystem.setRequirePath("src/?.lua;src/?/init.lua;src/graphics/?.lua;src/game/?.lua;src/utils/?.lua;?.lua;?/init.lua")
    end
end
