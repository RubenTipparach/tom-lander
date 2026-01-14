-- Bullets module: Player and enemy projectiles
-- Ported from Picotron version

local Constants = require("constants")
local AudioManager = require("audio_manager")

local Bullets = {}

-- Bullet configuration
Bullets.MAX_BULLETS = 100  -- Total bullet budget
Bullets.PLAYER_BULLET_SPEED = 20  -- Units per second
Bullets.ENEMY_BULLET_SPEED = 12  -- Units per second
Bullets.BULLET_SIZE = 0.5  -- Billboard size (world units)
Bullets.BULLET_RANGE = 100  -- Max range
Bullets.PLAYER_FIRE_RATE = 4  -- Bullets per second
Bullets.PLAYER_FIRE_COOLDOWN = 1 / Bullets.PLAYER_FIRE_RATE

-- Active bullets
Bullets.bullets = {}
Bullets.player_fire_timer = 0

-- Spawn a bullet (internal function)
function Bullets.spawn(x, y, z, dir_x, dir_y, dir_z, sprite, owner, max_range, speed)
    -- Check bullet budget
    if #Bullets.bullets >= Bullets.MAX_BULLETS then
        return nil
    end

    local bullet = {
        x = x,
        y = y,
        z = z,
        vx = dir_x * speed,
        vy = dir_y * speed,
        vz = dir_z * speed,
        sprite = sprite,
        owner = owner,  -- "player" or "enemy"
        start_x = x,
        start_y = y,
        start_z = z,
        max_range = max_range or Bullets.BULLET_RANGE,
        active = true
    }

    table.insert(Bullets.bullets, bullet)
    return bullet
end

-- Spawn player bullet (with rate limiting, faster speed)
function Bullets.spawn_player_bullet(x, y, z, dir_x, dir_y, dir_z, max_range)
    if Bullets.player_fire_timer > 0 then
        return nil  -- Still on cooldown
    end

    Bullets.player_fire_timer = Bullets.PLAYER_FIRE_COOLDOWN
    AudioManager.play_sfx(0)  -- Shoot sound
    return Bullets.spawn(x, y, z, dir_x, dir_y, dir_z, Constants.SPRITE_BULLET_PLAYER, "player", max_range, Bullets.PLAYER_BULLET_SPEED)
end

-- Spawn enemy bullet (no rate limit, controlled by enemy fire rate, slower speed)
function Bullets.spawn_enemy_bullet(x, y, z, dir_x, dir_y, dir_z, max_range)
    return Bullets.spawn(x, y, z, dir_x, dir_y, dir_z, Constants.SPRITE_BULLET_ENEMY, "enemy", max_range, Bullets.ENEMY_BULLET_SPEED)
end

-- Update all bullets
function Bullets.update(dt)
    -- Update player fire cooldown
    if Bullets.player_fire_timer > 0 then
        Bullets.player_fire_timer = Bullets.player_fire_timer - dt
        if Bullets.player_fire_timer < 0 then
            Bullets.player_fire_timer = 0
        end
    end

    -- Update bullet positions (iterate backwards for safe removal)
    for i = #Bullets.bullets, 1, -1 do
        local bullet = Bullets.bullets[i]

        if bullet.active then
            -- Move bullet
            bullet.x = bullet.x + bullet.vx * dt
            bullet.y = bullet.y + bullet.vy * dt
            bullet.z = bullet.z + bullet.vz * dt

            -- Check range
            local dx = bullet.x - bullet.start_x
            local dy = bullet.y - bullet.start_y
            local dz = bullet.z - bullet.start_z
            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

            if dist > bullet.max_range then
                table.remove(Bullets.bullets, i)
            end
        else
            table.remove(Bullets.bullets, i)
        end
    end
end

-- Draw bullets as camera-facing billboards using proper billboard math
function Bullets.draw(renderer, viewMatrix, cam)
    if #Bullets.bullets == 0 then return end

    -- Extract camera right and up vectors from view matrix
    -- View matrix is row-major in our engine
    local right_x, right_y, right_z
    local up_x, up_y, up_z

    if viewMatrix then
        -- Extract from view matrix (row-major, 1-indexed)
        right_x = viewMatrix[1]
        right_y = viewMatrix[2]
        right_z = viewMatrix[3]

        up_x = viewMatrix[5]
        up_y = viewMatrix[6]
        up_z = viewMatrix[7]
    elseif cam then
        -- Fallback: use camera vectors directly
        right_x = cam.right.x
        right_y = cam.right.y
        right_z = cam.right.z

        up_x = cam.up.x
        up_y = cam.up.y
        up_z = cam.up.z
    else
        -- Default fallback
        right_x, right_y, right_z = 1, 0, 0
        up_x, up_y, up_z = 0, 1, 0
    end

    for _, bullet in ipairs(Bullets.bullets) do
        if bullet.active then
            -- Get texture for bullet sprite
            local texData = Constants.getTextureData(bullet.sprite)
            if texData then
                local half = Bullets.BULLET_SIZE * 0.5
                local x, y, z = bullet.x, bullet.y, bullet.z

                -- Build quad vertices using camera right and up vectors
                local v1 = {
                    pos = {
                        x - right_x * half + up_x * half,
                        y - right_y * half + up_y * half,
                        z - right_z * half + up_z * half
                    },
                    uv = {0, 0}
                }
                local v2 = {
                    pos = {
                        x + right_x * half + up_x * half,
                        y + right_y * half + up_y * half,
                        z + right_z * half + up_z * half
                    },
                    uv = {1, 0}
                }
                local v3 = {
                    pos = {
                        x + right_x * half - up_x * half,
                        y + right_y * half - up_y * half,
                        z + right_z * half - up_z * half
                    },
                    uv = {1, 1}
                }
                local v4 = {
                    pos = {
                        x - right_x * half - up_x * half,
                        y - right_y * half - up_y * half,
                        z - right_z * half - up_z * half
                    },
                    uv = {0, 1}
                }

                -- Draw as two triangles (emissive, full opacity)
                renderer.drawTriangle3D(v1, v2, v3, nil, texData, 1.0, 1.0)
                renderer.drawTriangle3D(v1, v3, v4, nil, texData, 1.0, 1.0)
            end
        end
    end
end

-- Check bullet collision with a bounding box
-- Returns array of bullets that hit, removes them from active list
function Bullets.check_collision(owner_type, bounds)
    local hits = {}

    for i = #Bullets.bullets, 1, -1 do
        local bullet = Bullets.bullets[i]

        -- Only check bullets from the opposite owner
        if bullet.active and bullet.owner ~= owner_type then
            -- AABB collision check
            if bullet.x >= bounds.left and bullet.x <= bounds.right and
               bullet.y >= bounds.bottom and bullet.y <= bounds.top and
               bullet.z >= bounds.back and bullet.z <= bounds.front then
                table.insert(hits, bullet)
                bullet.active = false
                table.remove(Bullets.bullets, i)
            end
        end
    end

    return hits
end

-- Check collision with a sphere (simpler for most entities)
function Bullets.check_collision_sphere(owner_type, x, y, z, radius)
    local hits = {}
    local radius_sq = radius * radius

    for i = #Bullets.bullets, 1, -1 do
        local bullet = Bullets.bullets[i]

        -- Only check bullets from the opposite owner
        if bullet.active and bullet.owner ~= owner_type then
            local dx = bullet.x - x
            local dy = bullet.y - y
            local dz = bullet.z - z
            local dist_sq = dx*dx + dy*dy + dz*dz

            if dist_sq <= radius_sq then
                table.insert(hits, bullet)
                bullet.active = false
                table.remove(Bullets.bullets, i)
            end
        end
    end

    return hits
end

-- Get bullet count for debugging
function Bullets.get_count()
    return #Bullets.bullets
end

-- Reset bullets system
function Bullets.reset()
    Bullets.bullets = {}
    Bullets.player_fire_timer = 0
end

return Bullets
