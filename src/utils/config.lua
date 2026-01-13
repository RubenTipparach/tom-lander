-- Centralized engine configuration
-- Change resolution here to affect all scenes

local config = {}

-- ===========================================
-- RENDERER SETTINGS
-- ===========================================
config.USE_GPU_RENDERER = true  -- Set to true for GPU shaders, false for software DDA renderer
config.GOURAUD_SHADING = true   -- Set to true for per-vertex lighting (smooth), false for flat shading

-- ===========================================
-- LIGHTING SETTINGS (Gouraud shading)
-- ===========================================
-- Light direction: 60° up from East horizon
-- East = +X, 60° elevation: X = cos(60°) = 0.5, Y = -sin(60°) = -0.866, Z = 0
config.LIGHT_DIRECTION = {-0.866, 0.5, -0.2}  -- Directional light from 60° up, East (normalized automatically)
config.LIGHT_INTENSITY = 1.0               -- Directional light brightness (0-1)
config.AMBIENT_LIGHT = 0.55                -- Ambient light level (0-1)
config.USE_PALETTE_SHADOWS = true          -- Use palette-based shadows instead of RGB darkening
config.DITHER_PALETTE_SHADOWS = true       -- Dither between shadow levels for smooth transitions
config.SHADOW_LEVELS = 8                   -- Number of shadow levels (2-8, more = smoother)
config.SHADOW_BRIGHTNESS_MIN = 0.3         -- Brightness below this uses darkest shadow
config.SHADOW_BRIGHTNESS_MAX = 0.95        -- Brightness above this uses original color
config.SHADOW_DITHER_RANGE = 0.5           -- Range of blend values where dithering occurs (0.0-1.0)
                                           -- 0.0 = hard cutoff (no dither), 1.0 = dither entire transition

-- ===========================================
-- MENU SETTINGS
-- ===========================================
config.MENU_3D_ENABLED = true  -- Set to true to enable 3D menu background (planet, ship, starfield)
config.SET_CLEAR_COLOR = false  -- Set to true to call setClearColor in flight_scene.load() (causes FPS drop)

-- ===========================================
-- DEBUG / DEV SETTINGS
-- ===========================================
config.UNLOCK_ALL_MISSIONS = true  -- Set to true to unlock all missions (dev mode)
config.COMBAT_DEBUG = true         -- Set to true to show combat debug visuals (bounding boxes, velocity, target lines)

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

-- Collision bounds (axis-aligned bounding box half-extents)
config.VTOL_COLLISION_WIDTH = 1.0    -- Half-width (X axis)
config.VTOL_COLLISION_HEIGHT = 0.35   -- Half-height (Y axis)
config.VTOL_COLLISION_DEPTH = 1.0    -- Half-depth (Z axis)
config.VTOL_COLLISION_OFFSET_Y = 0.0 -- Vertical offset of collision box center

-- ===========================================
-- SHIP HEALTH & DAMAGE SETTINGS
-- ===========================================
config.SHIP_MAX_HEALTH = 200                  -- Ship starting/max health
config.SHIP_COLLISION_DAMAGE_MULTIPLIER = 20  -- Damage = collision_speed * this value (was 100)
config.SHIP_HARD_LANDING_THRESHOLD = 0.05     -- Vertical speed above this = hard landing damage
config.SHIP_HARD_LANDING_EXPLOSION_THRESHOLD = 0.05 -- Vertical speed above this = spawn explosion
config.SHIP_GROUND_SCRAPE_THRESHOLD = 0.08    -- Horizontal speed above this = ground scraping damage
config.SHIP_SIDE_CRASH_MULTIPLIER = 5         -- Damage multiplier when crashing on side
config.SHIP_TOP_CRASH_MULTIPLIER = 10         -- Damage multiplier when crashing upside down
config.SHIP_DAMAGE_SMOKE_THRESHOLD = 50       -- Start smoke at this hull % (50 = half health)
config.SHIP_DAMAGE_CRITICAL_THRESHOLD = 25    -- More smoke + sparks below this hull %
config.SHIP_DAMAGE_SMOKE_RATE_NORMAL = 0.3    -- Seconds between smoke puffs at threshold
config.SHIP_DAMAGE_SMOKE_RATE_CRITICAL = 0.05 -- Seconds between smoke at critical

-- Landing pad repair settings
config.SHIP_REPAIR_RATE = 20                  -- Health points repaired per second on landing pad
config.SHIP_REPAIR_DELAY = 1.0                -- Seconds of being stationary before repair starts
config.SHIP_REPAIR_VELOCITY_THRESHOLD = 0.05  -- Max velocity to be considered "stationary"

-- ===========================================
-- EXPLOSION SETTINGS
-- ===========================================
config.EXPLOSION_IMPACT_SCALE = 0.8           -- Scale of impact explosions
config.EXPLOSION_DEATH_SCALE = 2.5            -- Scale of death explosion
config.EXPLOSION_ENEMY_SCALE = 1.5            -- Scale of enemy explosions

-- ===========================================
-- THRUSTER FLAME SETTINGS
-- ===========================================
config.FLAME_BRIGHTNESS = 1.0        -- Flame brightness (1.0 = emissive, no shading)
config.FLAME_ALPHA = 0.5             -- Flame transparency (0-1, 0.5 = 50% transparent)

-- ===========================================
-- CAMERA SETTINGS
-- ===========================================
config.CAMERA_DISTANCE_MIN = -3           -- Min camera distance at low speed (negative = behind ship)
config.CAMERA_DISTANCE_MAX = -8           -- Max camera distance at high speed
config.CAMERA_DISTANCE_SPEED_MAX = 0.3    -- Speed at which camera reaches max distance
config.CAMERA_ZOOM_SPEED = 0.01            -- How fast camera distance adjusts (lerp speed)
config.CAMERA_LERP_SPEED = 0.2            -- How fast camera catches up to ship
config.CAMERA_ROTATION_SPEED = 0.03       -- Camera rotation speed per frame
config.CAMERA_MOUSE_SENSITIVITY = 0.003   -- Mouse sensitivity for camera rotation

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

-- ===========================================
-- SHADOW MAP SETTINGS
-- ===========================================
config.SHADOWS_ENABLED = true                -- Master toggle for shadows
config.SHADOW_DARKNESS = 0.6                 -- Shadow darkness (0 = black, 1 = no change)
config.SHADOW_MAP_SIZE = 1024                -- Shadow map resolution (1024 or 2048)
config.SHADOW_DEPTH_RANGE = 500              -- Depth range for shadow map (how far light can reach)
config.SHADOW_BIAS = 0.0002                   -- Depth bias (smaller = shadows work closer to ground, but may cause acne)

-- Cascade settings (2 cascades: near = high detail, far = wide coverage)
config.SHADOW_CASCADE_ENABLED = true         -- Enable cascaded shadow maps
config.SHADOW_CASCADE_SPLIT = 15             -- Distance where near cascade ends and far begins
config.SHADOW_NEAR_COVERAGE = 20             -- Near cascade coverage (smaller = higher quality close shadows)
config.SHADOW_FAR_COVERAGE = 120             -- Far cascade coverage (larger = shadows visible further)

return config
