# Picotron to Love2D Conversion Progress

## Overview
Converting Tom Lander from Picotron to Love2D engine.

**Key Advantage:** Love2D already has DDA renderer with depth buffer, so most Picotron graphics code is unnecessary.

---

## Step 1: Lander OBJ + Flight Code
**Status:** :green_circle: Complete

### Completed:
- [x] Copy `ship_low_poly.obj` and `flame.obj` to Love2D assets
- [x] Port ship physics from `src/ship.lua`
  - [x] VTOL thrust mechanics (W/A/S/D thrusters)
  - [x] Rotation controls (Q/E for yaw)
  - [x] Gravity and velocity
  - [x] Damage system
- [x] Port particle system for flames/smoke
- [x] Create flight_scene.lua for testing
- [x] Wire up keyboard controls
- [x] Create constants.lua with sprite indices

### Files Created:
- `src/game/constants.lua` - Sprite indices and texture loading
- `src/game/ship.lua` - Ship module with physics
- `src/game/particle_system.lua` - Particle effects
- `src/game/flight_scene.lua` - Main game scene

---

## Step 2: Map and Objects
**Status:** :green_circle: Complete

### Completed:
- [x] Port heightmap system from `src/heightmap.lua`
- [x] Load terrain using texture index 64 (SPRITE_HEIGHTMAP)
- [x] Copy OBJ models to Love2D:
  - [x] `cargo.obj`
  - [x] `landing_pad.obj`
- [x] Port building system from `src/building.lua`
- [x] Port cargo system from `src/cargo.lua`
- [x] Port landing pads from `src/landing_pads.lua`
- [x] Port collision system from `src/engine/collision.lua`
- [x] Update flight_scene with terrain, buildings, cargo, pads

### Files Created:
- `src/game/heightmap.lua` - Terrain generation from heightmap PNG
- `src/game/collision.lua` - AABB collision detection
- `src/game/building.lua` - Procedural building generation
- `src/game/landing_pads.lua` - Landing pad system with spawn points
- `src/game/cargo.lua` - Cargo pickup/delivery system

---

## Step 3: Menu System
**Status:** :yellow_circle: Basic Implementation

### Completed:
- [x] Basic menu with "Play Game" option
- [x] Scene switching with escape key
- [x] Controls help display

### TODO for Full Implementation:
- [ ] Space background with planet
- [ ] Mission selection screen
- [ ] Mode selection (Arcade/Simulation)
- [ ] Progress saving/loading
- [ ] Cutscene system
- [ ] Death screen

---

## Step 4: Missions System
**Status:** :yellow_circle: Basic Implementation

### Completed:
- [x] Basic cargo delivery working in flight_scene
- [x] Landing pad detection
- [x] Cargo pickup/attach/deliver states

### TODO for Full Implementation:
- [ ] Mission framework with objectives
- [ ] Multiple mission definitions (6 missions)
- [ ] Mission UI (objectives, compass, minimap)
- [ ] Turret and alien AI (Mission 6)
- [ ] Weather system (Mission 5)
- [ ] Audio system

---

## Texture Index Reference
From Picotron constants (maps to `assets/textures/[index].png`):
```
0: SPRITE_CUBE              20: SPRITE_CARGO
1: SPRITE_SPHERE            21: SPRITE_PLANET
3: SPRITE_FLAME             22: SPRITE_CLOUDS
5: SPRITE_SMOKE             64: SPRITE_HEIGHTMAP
6: SPRITE_TREES
8: SPRITE_LANDING_PAD
9: SPRITE_SHIP
10: SPRITE_SHIP_DAMAGE
11: SPRITE_SKYBOX
12-13: SPRITE_WATER variants
14: SPRITE_GROUND (32x32)
15: SPRITE_GRASS (32x32)
16: SPRITE_ROCKS (32x32)
17-19: Building textures
```

---

## Files Removed (Placeholder)
- [x] `src/game/test_cube_scene.lua`
- [x] `src/game/city_scene.lua`
- [x] `src/game/cubes_scene_dda.lua`
- [x] `src/game/fog_scene.lua`
- [x] `src/game/lighting_test_scene.lua`
- [x] `assets/ship_1.obj`
- [x] `assets/ship_1.mtl`
- [x] `assets/Ship_1_finish.png`
- [x] `assets/checkered_placeholder.png`
- [x] `assets/checkered_placeholde2r.png`

---

## Current Project Structure
```
tom-lander-love/
├── main.lua                 # Entry point, scene registration
├── conf.lua                 # Love2D configuration
├── assets/
│   ├── ship_low_poly.obj    # Ship model
│   ├── flame.obj            # Flame model
│   ├── cargo.obj            # Cargo model
│   ├── landing_pad.obj      # Landing pad model
│   └── textures/            # Indexed sprite textures (0.png, 1.png, etc.)
└── src/
    ├── game/
    │   ├── scene_manager.lua
    │   ├── menu.lua
    │   ├── flight_scene.lua  # Main game scene
    │   ├── constants.lua     # Sprite indices, texture loading
    │   ├── ship.lua          # Ship with VTOL physics
    │   ├── particle_system.lua
    │   ├── heightmap.lua     # Terrain generation
    │   ├── collision.lua     # AABB collision
    │   ├── building.lua      # Procedural buildings
    │   ├── landing_pads.lua  # Landing pad system
    │   └── cargo.lua         # Cargo pickup/delivery
    ├── graphics/
    │   ├── renderer_dda.lua  # Software renderer with depth buffer
    │   ├── obj_loader.lua    # OBJ file parser
    │   ├── camera.lua
    │   ├── mat4.lua
    │   ├── vec3.lua
    │   └── mesh.lua
    └── utils/
        ├── config.lua        # Resolution settings
        └── profiler.lua
```

---

## How to Run
```bash
cd tom-lander-love
love .
```

## Controls
- **W/A/S/D** - Thrusters (tilt ship in that direction)
- **Q/E** - Yaw rotation
- **R** - Reset ship to landing pad
- **F** - Toggle follow/free camera
- **Arrow keys** - Free camera rotation
- **Escape** - Return to menu

---

## Notes
- Love2D has proper depth buffer - no need to port Picotron's z-sorting
- DDA renderer already implemented and optimized with FFI
- Sprite indices map to `assets/textures/[index].png` files
- All game modules use Love2D's require() instead of Picotron's include()
