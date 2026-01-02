-- Main Menu Scene Selector
local menu = {}
local scene_manager = require("scene_manager")
local config = require("config")
local renderer = require("renderer_dda")
local camera_module = require("camera")
local mat4 = require("mat4")
local obj_loader = require("obj_loader")
local Constants = require("constants")

local menuItems = {
    {title = "Play Game", scene = "flight"},
    {title = "Ship Viewer (Debug)", scene = "ship_viewer"},
}

local selectedIndex = 1
local windowWidth, windowHeight = 960, 540

-- Ship preview
local shipMesh = nil
local shipRotation = 0
local softwareImage = nil
local projMatrix = nil
local cam = nil

function menu.load()
    love.window.setTitle("Tom Lander")
    windowWidth, windowHeight = love.graphics.getDimensions()

    -- Initialize renderer for ship preview
    renderer.init(config.RENDER_WIDTH, config.RENDER_HEIGHT)
    softwareImage = love.graphics.newImage(renderer.getImageData())

    -- Create projection matrix
    local aspect = config.RENDER_WIDTH / config.RENDER_HEIGHT
    projMatrix = mat4.perspective(config.FOV, aspect, config.NEAR_PLANE, config.FAR_PLANE)

    -- Create camera looking at origin - close to see the small ship model
    cam = camera_module.new(0, 0.3, 1.5)
    cam.pitch = -0.15
    cam.yaw = math.pi
    camera_module.updateVectors(cam)

    -- Load ship mesh
    local success, result = pcall(function()
        return obj_loader.load("assets/ship_low_poly.obj")
    end)

    if success and result then
        shipMesh = result
        print("Menu: Ship mesh loaded for preview: " .. #result.vertices .. " vertices, " .. #result.triangles .. " triangles")
    else
        print("Menu: Could not load ship mesh: " .. tostring(result))
    end

    -- Disable fog for menu
    renderer.setFog(false)
end

function menu.update(dt)
    -- Rotate ship preview
    shipRotation = shipRotation + dt * 0.5
end

function menu.draw()
    -- Draw 3D ship preview first
    if shipMesh then
        renderer.clearBuffers()

        -- Build view-projection matrix
        local viewMatrix = camera_module.getViewMatrix(cam)
        local mvpMatrix = mat4.multiply(projMatrix, viewMatrix)
        renderer.setMatrices(mvpMatrix, {x = cam.pos.x, y = cam.pos.y, z = cam.pos.z})

        -- Build model matrix for ship
        local scale = 0.15
        local modelMatrix = mat4.identity()
        modelMatrix = mat4.multiply(mat4.translation(0, 0, 0), modelMatrix)
        modelMatrix = mat4.multiply(mat4.rotationY(shipRotation), modelMatrix)
        modelMatrix = mat4.multiply(mat4.scale(scale, scale, scale), modelMatrix)

        -- Get ship texture
        local shipTexData = Constants.getTextureData(Constants.SPRITE_SHIP)

        -- Draw ship mesh
        if shipTexData then
            for _, tri in ipairs(shipMesh.triangles) do
                local v1 = shipMesh.vertices[tri[1]]
                local v2 = shipMesh.vertices[tri[2]]
                local v3 = shipMesh.vertices[tri[3]]

                -- Transform vertices to world space
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
        else
            -- Draw without texture (white triangles) if texture not found
            print("Warning: Ship texture not found, drawing wireframe")
            for _, tri in ipairs(shipMesh.triangles) do
                local v1 = shipMesh.vertices[tri[1]]
                local v2 = shipMesh.vertices[tri[2]]
                local v3 = shipMesh.vertices[tri[3]]

                local p1 = mat4.multiplyVec4(modelMatrix, {v1.pos[1], v1.pos[2], v1.pos[3], 1})
                local p2 = mat4.multiplyVec4(modelMatrix, {v2.pos[1], v2.pos[2], v2.pos[3], 1})
                local p3 = mat4.multiplyVec4(modelMatrix, {v3.pos[1], v3.pos[2], v3.pos[3], 1})

                renderer.drawTriangle3D(
                    {pos = {p1[1], p1[2], p1[3]}, uv = v1.uv},
                    {pos = {p2[1], p2[2], p2[3]}, uv = v2.uv},
                    {pos = {p3[1], p3[2], p3[3]}, uv = v3.uv},
                    {1, 1, 1},  -- White color
                    nil
                )
            end
        end

        -- Update and draw the software rendered image
        softwareImage:replacePixels(renderer.getImageData())

        local scaleX = windowWidth / config.RENDER_WIDTH
        local scaleY = windowHeight / config.RENDER_HEIGHT
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(softwareImage, 0, 0, 0, scaleX, scaleY)
    else
        love.graphics.clear(0.05, 0.05, 0.08)
    end

    -- Title
    love.graphics.setColor(1, 1, 1)
    local centerY = windowHeight / 2
    love.graphics.printf("TOM LANDER", 0, centerY - 100, windowWidth, "center")
    love.graphics.printf("A Lunar Lander Game", 0, centerY - 70, windowWidth, "center")

    -- Menu items
    local startY = centerY - 20
    local itemHeight = 35

    for i, item in ipairs(menuItems) do
        local y = startY + (i - 1) * itemHeight
        local isSelected = (i == selectedIndex)

        -- Selection indicator
        if isSelected then
            love.graphics.setColor(0.4, 0.6, 1.0)
            love.graphics.print(">", windowWidth / 2 - 80, y, 0, 1.5, 1.5)
        end

        -- Title
        if isSelected then
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(item.title, windowWidth / 2 - 50, y, 0, 1.3, 1.3)
        else
            love.graphics.setColor(0.7, 0.7, 0.7)
            love.graphics.print(item.title, windowWidth / 2 - 50, y)
        end
    end

    -- Controls help
    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.printf("Controls:", 0, windowHeight - 120, windowWidth, "center")
    love.graphics.printf("W/A/S/D - Thrusters  |  Q/E - Yaw  |  R - Reset", 0, windowHeight - 100, windowWidth, "center")
    love.graphics.printf("F - Toggle Camera  |  ESC - Menu", 0, windowHeight - 80, windowWidth, "center")

    -- Instructions at bottom
    love.graphics.setColor(0.6, 0.6, 0.6)
    love.graphics.printf("Enter: Start  |  ESC: Quit", 0, windowHeight - 30, windowWidth, "center")

    -- Debug info
    love.graphics.setColor(1, 1, 0)
    if shipMesh then
        love.graphics.print("Ship mesh: " .. #shipMesh.triangles .. " tris", 10, 10)
    else
        love.graphics.print("Ship mesh: NOT LOADED", 10, 10)
    end
    love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 30)
end

function menu.keypressed(key)
    if key == "up" then
        selectedIndex = selectedIndex - 1
        if selectedIndex < 1 then
            selectedIndex = #menuItems
        end
    elseif key == "down" then
        selectedIndex = selectedIndex + 1
        if selectedIndex > #menuItems then
            selectedIndex = 1
        end
    elseif key == "return" or key == "space" then
        menu.launchScene(selectedIndex)
    elseif key == "escape" then
        love.event.quit()
    end
end

function menu.launchScene(index)
    local item = menuItems[index]
    print("Launching scene: " .. item.title)
    scene_manager.switch(item.scene)
end

return menu
