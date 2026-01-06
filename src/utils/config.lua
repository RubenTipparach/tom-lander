-- Centralized engine configuration
-- Change resolution here to affect all scenes

local config = {}

-- ===========================================
-- RENDERER SETTINGS
-- ===========================================
config.USE_GPU_RENDERER = true  -- Set to true for GPU shaders, false for software DDA renderer

-- ===========================================
-- MENU SETTINGS
-- ===========================================
config.MENU_3D_ENABLED = true  -- Set to true to enable 3D menu background (planet, ship, starfield)
config.SET_CLEAR_COLOR = false  -- Set to true to call setClearColor in flight_scene.load() (causes FPS drop)

-- ===========================================
-- RENDER SETTINGS
-- ===========================================

-- Render resolution (software renderer resolution)
config.RENDER_WIDTH = 480
config.RENDER_HEIGHT = 270

-- Window resolution (actual window size)
config.WINDOW_WIDTH = 960
config.WINDOW_HEIGHT = 540

-- Renderer settings
config.NEAR_PLANE = 0.1
config.FAR_PLANE = 500.0
config.FOV = math.pi / 3  -- 60 degrees

-- ===========================================
-- FOG AND RENDER DISTANCE (matching Picotron)
-- ===========================================
-- Picotron: RENDER_DISTANCE = 20, FOG_START_DISTANCE = 15
-- In Picotron units (1 unit = 10m), so we multiply by 10 for Love2D world units
-- But our heightmap uses TILE_SIZE = 4 world units per tile
-- Picotron uses 128x128 tiles at 4 units per tile = 512 world unit map

config.RENDER_DISTANCE = 50          -- Max render distance (cull beyond this)
config.FOG_START_DISTANCE = 30       -- Distance where fog begins
config.FOG_MAX_DISTANCE = 50         -- Distance where fog is 100% (should match RENDER_DISTANCE)
config.FOG_COLOR = {40, 40, 60}      -- Fog color (dark blue-gray, unused - renderer syncs with clear color)

-- ===========================================
-- SKYDOME SETTINGS
-- ===========================================
config.SKYBOX_RADIUS = 30           -- Distance of skydome from camera
config.SKYBOX_HEIGHT = 60            -- Height of dome apex
config.SKYBOX_SIDES = 16             -- Number of polygon sides (more = smoother)

-- ===========================================
-- TERRAIN TEXTURE SETTINGS
-- ===========================================
-- Height thresholds (palette index 0-31)
config.TERRAIN_GROUND_TO_GRASS = 3   -- Height where ground transitions to grass
config.TERRAIN_GRASS_TO_ROCKS = 10   -- Height where grass transitions to rocks
-- Blend ranges (height units for dithered transition zone)
config.TERRAIN_GROUND_GRASS_BLEND = 2.0  -- Ground-to-grass (sand) transition range
config.TERRAIN_GRASS_ROCKS_BLEND = 4.0   -- Grass-to-rocks transition range

-- ===========================================
-- HUD SETTINGS
-- ===========================================
config.THRUSTER_LABEL_Y_OFFSET = 4   -- Y offset for WASD thruster labels above engines

-- ===========================================
-- SHIP PHYSICS CONSTANTS
-- ===========================================

config.VTOL_THRUST = 0.0035          -- Thrust force per thruster
config.VTOL_TORQUE_PITCH = 0.002    -- Torque around X axis (pitch)
config.VTOL_TORQUE_ROLL = 0.002     -- Torque around Z axis (roll)
config.VTOL_GRAVITY = -0.005         -- Gravity force
config.VTOL_DAMPING = 0.95           -- Linear velocity damping
config.VTOL_ANGULAR_DAMPING = 0.95   -- Angular velocity damping

return config
