-- Skydome Module
-- Multi-sided dome that follows camera, always draws first (behind everything)
-- Ported from Picotron version with more polygons for smoother appearance

local Constants = require("constants")

local Skydome = {}

-- Configuration (more polygons than Picotron's 6 sides)
local SKYBOX_RADIUS = 100
local SKYBOX_HEIGHT = 60
local NUM_SIDES = 16  -- Smoother dome (Picotron used 6, Mission 6 used 16)

-- Pre-computed vertices and faces
local skybox_verts = {}
local skybox_faces = {}

-- Initialize the dome geometry
function Skydome.init()
    skybox_verts = {}
    skybox_faces = {}

    -- Bottom ring (NUM_SIDES vertices at y=0)
    for i = 0, NUM_SIDES - 1 do
        local angle = (i / NUM_SIDES) * math.pi * 2
        table.insert(skybox_verts, {
            math.cos(angle) * SKYBOX_RADIUS,
            0,
            math.sin(angle) * SKYBOX_RADIUS
        })
    end

    -- Top vertex (center of dome)
    table.insert(skybox_verts, {0, SKYBOX_HEIGHT, 0})

    -- Create NUM_SIDES triangular faces
    local top = NUM_SIDES + 1  -- Index of top vertex
    for i = 0, NUM_SIDES - 1 do
        local b1 = i + 1                      -- Bottom ring vertex
        local b2 = (i + 1) % NUM_SIDES + 1    -- Next bottom vertex (wrap around)

        -- Triangle from bottom edge to top
        -- UVs wrap the texture around the full circle (normalized 0-1)
        local u_start = i / NUM_SIDES
        local u_end = (i + 1) / NUM_SIDES

        -- Winding order reversed so triangles face INWARD (we're inside the dome)
        table.insert(skybox_faces, {
            indices = {b2, b1, top},
            uvs = {
                {u_end, 1},             -- bottom right
                {u_start, 1},           -- bottom left
                {(u_start + u_end) / 2, 0}  -- top center
            }
        })
    end

    print("Skydome initialized with " .. #skybox_verts .. " vertices, " .. #skybox_faces .. " faces")
end

-- Draw skydome centered at camera position
-- IMPORTANT: This should be called FIRST before other geometry
-- Fog is temporarily disabled so skydome doesn't get dithered
function Skydome.draw(renderer, cam_x, cam_y, cam_z)
    local texData = Constants.getTextureData(Constants.SPRITE_SKYBOX)
    if not texData then return end

    -- Temporarily disable fog for skydome (no dithering on sky)
    local fogWasEnabled = renderer.getFogEnabled()
    if fogWasEnabled then
        renderer.setFog(false)
    end

    -- Draw each face of the skydome, offset to camera position
    for _, face in ipairs(skybox_faces) do
        local v1 = skybox_verts[face.indices[1]]
        local v2 = skybox_verts[face.indices[2]]
        local v3 = skybox_verts[face.indices[3]]

        -- Offset vertices by camera position (skydome follows camera)
        -- The skydome stays fixed relative to camera, creating infinite distance illusion
        renderer.drawTriangle3D(
            {pos = {v1[1] + cam_x, v1[2] + cam_y, v1[3] + cam_z}, uv = face.uvs[1]},
            {pos = {v2[1] + cam_x, v2[2] + cam_y, v2[3] + cam_z}, uv = face.uvs[2]},
            {pos = {v3[1] + cam_x, v3[2] + cam_y, v3[3] + cam_z}, uv = face.uvs[3]},
            nil,
            texData
        )
    end

    -- Restore fog state
    if fogWasEnabled then
        renderer.setFog(true)
    end
end

return Skydome
