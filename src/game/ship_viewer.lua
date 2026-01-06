-- Ship Viewer Scene: Debug scene to verify ship model rendering
local ship_viewer = {}

local config = require("config")
local renderer = require("renderer")
local camera_module = require("camera")
local mat4 = require("mat4")
local obj_loader = require("obj_loader")
local Constants = require("constants")

local shipMesh = nil
local shipRotation = 0
local softwareImage = nil
local projMatrix = nil
local cam = nil
local camDistance = 3
local camHeight = 1

function ship_viewer.load()
    print("=== SHIP VIEWER LOADING ===")

    -- Initialize renderer
    renderer.init(config.RENDER_WIDTH, config.RENDER_HEIGHT)
    -- softwareImage only needed for DDA renderer (GPU renderer handles its own presentation)
    local imageData = renderer.getImageData()
    if imageData then
        softwareImage = love.graphics.newImage(imageData)
    end

    -- Create projection matrix
    local aspect = config.RENDER_WIDTH / config.RENDER_HEIGHT
    projMatrix = mat4.perspective(config.FOV, aspect, config.NEAR_PLANE, config.FAR_PLANE)
    print(string.format("Projection: FOV=%.2f, aspect=%.2f, near=%.2f, far=%.2f",
        config.FOV, aspect, config.NEAR_PLANE, config.FAR_PLANE))

    -- Create camera looking at origin
    cam = camera_module.new(0, camHeight, camDistance)
    cam.pitch = -0.3
    cam.yaw = math.pi
    camera_module.updateVectors(cam)
    print(string.format("Camera: pos=(%.2f, %.2f, %.2f), pitch=%.2f, yaw=%.2f",
        cam.pos.x, cam.pos.y, cam.pos.z, cam.pitch, cam.yaw))

    -- Load ship mesh
    print("Loading ship mesh...")
    local success, result = pcall(function()
        return obj_loader.load("assets/ship_low_poly.obj")
    end)

    if success and result then
        shipMesh = result
        print("Ship mesh loaded: " .. #result.vertices .. " vertices, " .. #result.triangles .. " triangles")

        -- Print first few vertices
        print("First 3 vertices:")
        for i = 1, math.min(3, #result.vertices) do
            local v = result.vertices[i]
            print(string.format("  v%d: pos=(%.2f, %.2f, %.2f), uv=(%.2f, %.2f)",
                i, v.pos[1], v.pos[2], v.pos[3], v.uv[1], v.uv[2]))
        end
    else
        print("ERROR: Could not load ship mesh: " .. tostring(result))
    end

    -- Load texture
    local texData = Constants.getTextureData(Constants.SPRITE_SHIP)
    if texData then
        print(string.format("Ship texture loaded: index=%d, size=%dx%d",
            Constants.SPRITE_SHIP, texData:getWidth(), texData:getHeight()))
    else
        print("ERROR: Ship texture NOT loaded!")
    end

    -- Disable fog
    renderer.setFog(false)

    print("=== SHIP VIEWER READY ===")
    print("Controls: Arrow keys to rotate camera, +/- to zoom, ESC to exit")
end

function ship_viewer.update(dt)
    -- Auto-rotate ship
    shipRotation = shipRotation + dt * 0.5

    -- Camera controls
    if love.keyboard.isDown("left") then
        cam.yaw = cam.yaw + 2 * dt
    end
    if love.keyboard.isDown("right") then
        cam.yaw = cam.yaw - 2 * dt
    end
    if love.keyboard.isDown("up") then
        camHeight = camHeight + 2 * dt
    end
    if love.keyboard.isDown("down") then
        camHeight = camHeight - 2 * dt
    end
    if love.keyboard.isDown("=") or love.keyboard.isDown("+") then
        camDistance = math.max(0.5, camDistance - 2 * dt)
    end
    if love.keyboard.isDown("-") then
        camDistance = camDistance + 2 * dt
    end

    -- Update camera position
    cam.pos.x = math.sin(cam.yaw) * camDistance
    cam.pos.y = camHeight
    cam.pos.z = math.cos(cam.yaw) * camDistance

    -- Look at origin
    local dx = 0 - cam.pos.x
    local dy = 0 - cam.pos.y
    local dz = 0 - cam.pos.z
    local dist_xz = math.sqrt(dx * dx + dz * dz)
    cam.yaw = math.atan2(-dx, -dz)
    cam.pitch = math.atan2(dy, dist_xz)
    camera_module.updateVectors(cam)
end

function ship_viewer.draw()
    if not shipMesh then
        love.graphics.clear(0.2, 0, 0)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("ERROR: Ship mesh not loaded!", 10, 10)
        return
    end

    -- Clear renderer
    renderer.clearBuffers()

    -- Build view matrix
    local viewMatrix = camera_module.getViewMatrix(cam)
    renderer.setMatrices(projMatrix, viewMatrix, {x = cam.pos.x, y = cam.pos.y, z = cam.pos.z})

    -- Build model matrix for ship (NO rotation, just scale to see it clearly)
    local scale = 0.3  -- Larger scale for visibility
    local modelMatrix = mat4.identity()
    modelMatrix = mat4.multiply(mat4.rotationY(shipRotation), modelMatrix)
    modelMatrix = mat4.multiply(mat4.scale(scale, scale, scale), modelMatrix)

    -- Get ship texture
    local shipTexData = Constants.getTextureData(Constants.SPRITE_SHIP)

    -- Draw ship mesh
    local trisDrawn = 0
    for _, tri in ipairs(shipMesh.triangles) do
        local v1 = shipMesh.vertices[tri[1]]
        local v2 = shipMesh.vertices[tri[2]]
        local v3 = shipMesh.vertices[tri[3]]

        -- Transform vertices to world space
        local p1 = mat4.multiplyVec4(modelMatrix, {v1.pos[1], v1.pos[2], v1.pos[3], 1})
        local p2 = mat4.multiplyVec4(modelMatrix, {v2.pos[1], v2.pos[2], v2.pos[3], 1})
        local p3 = mat4.multiplyVec4(modelMatrix, {v3.pos[1], v3.pos[2], v3.pos[3], 1})

        if shipTexData then
            renderer.drawTriangle3D(
                {pos = {p1[1], p1[2], p1[3]}, uv = v1.uv},
                {pos = {p2[1], p2[2], p2[3]}, uv = v2.uv},
                {pos = {p3[1], p3[2], p3[3]}, uv = v3.uv},
                nil,
                shipTexData
            )
        else
            -- Draw white triangles if no texture
            renderer.drawTriangle3D(
                {pos = {p1[1], p1[2], p1[3]}, uv = v1.uv},
                {pos = {p2[1], p2[2], p2[3]}, uv = v2.uv},
                {pos = {p3[1], p3[2], p3[3]}, uv = v3.uv},
                {1, 1, 1},
                nil
            )
        end
        trisDrawn = trisDrawn + 1
    end

    -- Present the rendered frame to screen
    renderer.present()

    -- Draw debug info
    love.graphics.setColor(1, 1, 0)
    love.graphics.print("SHIP VIEWER - Debug Scene", 10, 10)
    love.graphics.print(string.format("Triangles: %d", trisDrawn), 10, 30)
    love.graphics.print(string.format("Camera: (%.1f, %.1f, %.1f)", cam.pos.x, cam.pos.y, cam.pos.z), 10, 50)
    love.graphics.print(string.format("Distance: %.1f, Height: %.1f", camDistance, camHeight), 10, 70)
    love.graphics.print(string.format("Ship rotation: %.2f", shipRotation), 10, 90)
    love.graphics.print("Texture: " .. (shipTexData and "LOADED" or "MISSING"), 10, 110)

    local stats = renderer.getStats()
    love.graphics.print(string.format("Renderer tris: %d", stats.trianglesDrawn), 10, 130)
    love.graphics.print(string.format("FPS: %d", love.timer.getFPS()), 10, 150)

    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.print("Controls: Arrows=rotate/height, +/-=zoom, ESC=menu", 10, config.WINDOW_HEIGHT - 30)
end

function ship_viewer.keypressed(key)
    if key == "escape" then
        local scene_manager = require("scene_manager")
        scene_manager.switch("menu")
    end
end

return ship_viewer
