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
config.COMBAT_DEBUG = false         -- Set to true to show basic combat debug (facing + velocity arrows)
config.COMBAT_DEBUG_DETAILED = false  -- Set to true to show detailed debug (bounding boxes, axes, target lines)
config.CAMERA_DEBUG = false        -- Set to true to print camera debug info every 5 seconds

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
-- NIGHT MODE SETTINGS (Racing)
-- ===========================================
config.NIGHT_FOG_COLOR = {29, 43, 83}     -- #1d2b53 - Dark blue fog for night
config.NIGHT_LIGHT_INTENSITY = 0.4        -- Overall brightness for night mode (0-1)
config.NIGHT_AMBIENT_RATIO = 0.9          -- Ambient as percentage of intensity (0-1)
config.NIGHT_FOG_START = 25               -- Fog starts closer at night
config.NIGHT_FOG_MAX = 45                 -- Max fog distance at night

-- ===========================================
-- CHECKPOINT POINT LIGHT SETTINGS
-- ===========================================
config.CHECKPOINT_LIGHT_CURRENT_RADIUS = 20       -- Light radius for current checkpoint
config.CHECKPOINT_LIGHT_CURRENT_INTENSITY = 0.8   -- Base intensity (pulsates)
config.CHECKPOINT_LIGHT_CURRENT_PULSE_MIN = 0.7   -- Pulse minimum multiplier
config.CHECKPOINT_LIGHT_CURRENT_PULSE_MAX = 1.0   -- Pulse maximum multiplier
config.CHECKPOINT_LIGHT_CURRENT_PULSE_SPEED = 4   -- Pulse speed (cycles per second)
config.CHECKPOINT_LIGHT_CURRENT_COLOR = {1.0, 0.8, 0.2}  -- Yellow/orange
config.CHECKPOINT_LIGHT_NEXT_RADIUS = 15          -- Light radius for next checkpoint
config.CHECKPOINT_LIGHT_NEXT_INTENSITY = 0.3      -- Intensity for next checkpoint
config.CHECKPOINT_LIGHT_NEXT_COLOR = {0.3, 0.6, 0.8}     -- Cyan
config.CHECKPOINT_LIGHT_MAX_DISTANCE = 100        -- Max distance to add light
config.CHECKPOINT_LIGHT_USE_NORMALS = true        -- Use surface normals for lighting angle

-- ===========================================
-- THRUSTER POINT LIGHT SETTINGS
-- ===========================================
config.THRUSTER_LIGHT_RADIUS = 8                  -- Light radius
config.THRUSTER_LIGHT_INTENSITY = 0.6             -- Base intensity
config.THRUSTER_LIGHT_FLICKER_MIN = 0.7           -- Flicker minimum multiplier
config.THRUSTER_LIGHT_FLICKER_MAX = 1.0           -- Flicker maximum multiplier
config.THRUSTER_LIGHT_FLICKER_SPEED = 12          -- Flicker speed (Hz)
config.THRUSTER_LIGHT_COLOR = {1.0, 0.6, 0.2}     -- Orange/yellow flame color
config.THRUSTER_LIGHT_USE_NORMALS = true          -- Use surface normals for lighting angle

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
-- BULLET SETTINGS
-- ===========================================
config.BULLET_MAX_COUNT = 100                 -- Total bullet budget
config.BULLET_PLAYER_SPEED = 22               -- Player bullet speed (units per second)
config.BULLET_ENEMY_SPEED = 18                -- Enemy bullet speed (units per second)
config.BULLET_SIZE = 0.5                      -- Billboard size (world units)
config.BULLET_PLAYER_RANGE = 100              -- Player bullet max travel distance
config.BULLET_ENEMY_RANGE = 50                -- Enemy bullet max travel distance
config.BULLET_PLAYER_FIRE_RATE = 4            -- Player bullets per second

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
config.CAMERA_FOLLOW_MODE_ENABLED = false -- Set to true to enable follow camera mode (currently disabled)
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

-- ===========================================
-- FIREWORKS SETTINGS
-- ===========================================
config.FIREWORK_MAX_SPARKS = 500             -- Maximum sparks allowed
config.FIREWORK_ROCKET_VELOCITY = 15         -- Base upward velocity
config.FIREWORK_ROCKET_VELOCITY_VAR = 10     -- Velocity variation
config.FIREWORK_ROCKET_LIFETIME = 0.8        -- Base time before explosion
config.FIREWORK_ROCKET_LIFETIME_VAR = 0.4    -- Lifetime variation
config.FIREWORK_SPARK_COUNT = 30             -- Sparks per explosion
config.FIREWORK_SPARK_SPEED = 8              -- Spark explosion speed
config.FIREWORK_SPARK_LIFETIME = 1.0         -- Spark lifetime
config.FIREWORK_SPARK_LIFETIME_VAR = 0.5     -- Spark lifetime variation
config.FIREWORK_GRAVITY = 15                 -- Gravity affecting sparks

-- Firework color palette (RGB values 0-255)
config.FIREWORK_COLORS = {
    {255, 100, 100},   -- Red
    {100, 255, 100},   -- Green
    {100, 100, 255},   -- Blue
    {255, 255, 100},   -- Yellow
    {255, 100, 255},   -- Magenta
    {100, 255, 255},   -- Cyan
    {255, 200, 100},   -- Orange
    {255, 255, 255},   -- White
}

-- ===========================================
-- VICTORY CAMERA SETTINGS
-- ===========================================
config.VICTORY_DELAY = 3.0                   -- Seconds before camera orbit starts
config.VICTORY_ORBIT_DISTANCE = 12           -- Camera distance from ship
config.VICTORY_ORBIT_HEIGHT = 1              -- Camera height above ship
config.VICTORY_ORBIT_SPEED = 0.3             -- Camera rotation speed (radians per second)
config.VICTORY_FIREWORK_RATE = 2             -- Fireworks launched per second during celebration

-- ===========================================
-- MAP CONFIGURATIONS
-- ===========================================
-- Map definitions: each map has size, image path, terrain rules, spawn point
config.MAPS = {
    -- Act 1: Original island map (128x128)
    act1 = {
        name = "Island",
        image = "assets/textures/64.png",       -- Heightmap image path
        width = 128,                             -- Map width in tiles
        height = 128,                            -- Map height in tiles
        has_water = true,                        -- Water at height 0
        has_grass = true,                        -- Use grass texture
        spawn_aseprite = {64, 64},               -- Player spawn in aseprite coords
        landing_pads = nil,                      -- Use hardcoded pads (legacy, matching Picotron)
        edge_walls = nil,                        -- No edge walls
    },
    -- Act 2: Desert canyon map (128x256)
    act2 = {
        name = "Desert Canyon",
        image = "assets/map_act_2.png",          -- Heightmap image path
        width = 128,                             -- Map width in tiles
        height = 256,                            -- Map height in tiles (tall map)
        has_water = false,                       -- No water - all sand
        has_grass = false,                       -- No grass - use sand
        spawn_aseprite = {41, 264},              -- Player spawn in aseprite coords
        landing_pads = {                         -- Landing pad positions (aseprite coords)
            {x = 41, z = 264, id = 1},
        },
        edge_walls = {                           -- Wall extrusion on edges
            east = {height = 25},                -- East edge wall (height in heightmap units)
            west = {height = 25},                -- West edge wall
        },
        altitude_limit = 30,                     -- Max altitude in world units (300m displayed)
        altitude_warning_time = 10,              -- Seconds before ship explodes when over limit
    },
}

-- Current active map (can be changed at runtime)
config.CURRENT_MAP = "act1"

return config
