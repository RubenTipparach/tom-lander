-- Centralized engine configuration
-- Change resolution here to affect all scenes

local config = {}

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

config.RENDER_DISTANCE = 40          -- Max render distance (cull beyond this) - 20 * 4 = 80
config.FOG_START_DISTANCE = 20       -- Distance where fog begins - 15 * 4 = 60
config.FOG_COLOR = {40, 40, 60}      -- Fog color (dark blue-gray)

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
