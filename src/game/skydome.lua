-- Skydome Module
-- Multi-sided dome that follows camera, always draws first (behind everything)
-- Ported from Picotron version with more polygons for smoother appearance

local Constants = require("constants")
local config = require("config")

local Skydome = {}

-- Configuration from config.lua
local SKYBOX_RADIUS = config.SKYBOX_RADIUS or 100
local SKYBOX_HEIGHT = config.SKYBOX_HEIGHT or 60
local NUM_SIDES = config.SKYBOX_SIDES or 16

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
-- Uses dedicated sky shader (no fog) and no depth test
-- sky_type: "normal" (default), "overcast" (weather), "sunset" (mission 7), or "night" (night racing)
function Skydome.draw(renderer, cam_x, cam_y, cam_z, sky_type)
    -- Select sprite based on sky type
    local sprite_id = Constants.SPRITE_SKYBOX  -- default: normal sky
    if sky_type == "overcast" then
        sprite_id = Constants.SPRITE_SKYBOX_OVERCAST
    elseif sky_type == "sunset" then
        sprite_id = Constants.SPRITE_SKYBOX_SUNSET
    elseif sky_type == "night" then
        sprite_id = Constants.SPRITE_SKYBOX_NIGHT
    elseif sky_type == true then
        -- Backwards compatibility: true = overcast
        sprite_id = Constants.SPRITE_SKYBOX_OVERCAST
    end
    local texData = Constants.getTextureData(sprite_id)
    if not texData then return end

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

    -- Flush sky using dedicated sky shader (no fog, no depth test)
    renderer.flushSky()
end

return Skydome
