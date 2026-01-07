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
-- DEBUG / DEV SETTINGS
-- ===========================================
config.UNLOCK_ALL_MISSIONS = true  -- Set to true to unlock all missions (dev mode)

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

-- ===========================================
-- GUIDE ARROW SETTINGS
-- ===========================================
config.GUIDE_ARROW_LENGTH = 0.5           -- Base arrow length
config.GUIDE_ARROW_WIDTH = 0.3            -- Base arrow width
config.GUIDE_ARROW_HEIGHT = 0.15           -- 3D extrusion height (vertical thickness)
config.GUIDE_ARROW_Y_OFFSET = 0           -- Y offset from camera pivot (positive = up)
config.GUIDE_ARROW_DISTANCE = 2.5         -- Distance from camera pivot to arrow center
config.GUIDE_ARROW_DEPTH_TEST = true      -- Enable depth testing (arrow occluded by terrain/objects)
config.GUIDE_ARROW_MIN_TARGET_DIST = 5    -- Min distance to target before arrow hides
config.GUIDE_ARROW_PULSE_SPEED = 8        -- Pulsating scale speed
config.GUIDE_ARROW_PULSE_MIN = 0.9        -- Min pulse scale
config.GUIDE_ARROW_PULSE_MAX = 1.2        -- Max pulse scale
config.GUIDE_ARROW_COLOR_SPEED = 6        -- Brightness pulsating speed
config.GUIDE_ARROW_COLOR_R = 255          -- Base red color
config.GUIDE_ARROW_COLOR_G = 140          -- Base green color
config.GUIDE_ARROW_COLOR_B = 0            -- Base blue color

-- ===========================================
-- WEATHER SETTINGS (Mission 5)
-- ===========================================
config.WEATHER_RAIN_COUNT = 1000          -- Number of rain particles
config.WEATHER_RAIN_FALL_SPEED = -20      -- Rain fall speed (negative = down)
config.WEATHER_RAIN_SPREAD = 20           -- Horizontal spread of rain around camera
config.WEATHER_RAIN_LENGTH =0.5         -- Rain streak length in world units
config.WEATHER_RAIN_THICKNESS = 0.03     -- Rain streak thickness in world units
config.WEATHER_RAIN_MIN_Y = 50            -- Min spawn height above camera
config.WEATHER_RAIN_MAX_Y = 60            -- Max spawn height above camera
config.WEATHER_RAIN_DESPAWN_BELOW = -50   -- Despawn when this far below camera
config.WEATHER_FOG_START = 20          -- Fog start distance during weather
config.WEATHER_FOG_MAX = 30            -- Max visibility during weather
config.WEATHER_RENDER_DISTANCE = 30       -- Reduced render distance during weather
config.WEATHER_WIND_LIGHT = 0.03          -- Wind strength at low altitude
config.WEATHER_WIND_MEDIUM = 0.08         -- Wind strength at medium altitude
config.WEATHER_WIND_HEAVY = 0.15          -- Wind strength at high altitude
config.WEATHER_LIGHTNING_INTERVAL = 15    -- Average seconds between lightning
config.WEATHER_SKY_SPRITE = 23            -- Cloudy sky sprite ID for weather
config.WEATHER_FOG_COLOR = {162, 136, 131}   -- Fog/clear color during weather

-- ===========================================
-- WIND ARROW SETTINGS (Weather indicator)
-- ===========================================
config.WIND_ARROW_LENGTH_BASE = 0.3          -- Base arrow length (scaled by wind strength)
config.WIND_ARROW_LENGTH_SCALE = 3.0         -- How much wind strength multiplies length
config.WIND_ARROW_WIDTH = 0.2                -- Arrow width
config.WIND_ARROW_HEIGHT = 0.1               -- 3D extrusion height
config.WIND_ARROW_Y_OFFSET = -0.5            -- Y offset from camera pivot (negative = below)
config.WIND_ARROW_DISTANCE = 2.0             -- Distance from camera pivot to arrow center
config.WIND_ARROW_DEPTH_TEST = true          -- Enable depth testing
config.WIND_ARROW_PULSE_SPEED = 6            -- Pulsating scale speed
config.WIND_ARROW_PULSE_MIN = 0.9            -- Min pulse scale
config.WIND_ARROW_PULSE_MAX = 1.1            -- Max pulse scale
config.WIND_ARROW_COLOR_SPEED = 4            -- Brightness pulsating speed
config.WIND_ARROW_COLOR_R = 60               -- Base red color (blue arrow)
config.WIND_ARROW_COLOR_G = 140              -- Base green color
config.WIND_ARROW_COLOR_B = 255              -- Base blue color

return config
