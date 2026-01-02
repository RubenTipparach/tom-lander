# Menu System Documentation

## Overview

The Chieftan Engine now includes a graphical scene selection menu that allows you to easily switch between different rendering demos and compare performance.

## Launching the Menu

### Windows
```bash
run_menu.bat
```

### Command Line
```bash
love . main_menu.lua
```

## Menu Features

### Visual Design
- **Clean UI** - Dark theme with highlighted selection
- **Scene descriptions** - Clear explanation of each option
- **Performance indicators** - ⚡ NEW tags for DDA renderer scenes
- **Keyboard navigation** - Simple arrow key controls

### Available Scenes

#### 1. 5000 Cubes (DDA Renderer) ⚡ NEW
- **File:** `cubes_scene_dda.lua`
- **Description:** Fast DDA scanline renderer
- **Features:**
  - 5000 rotating cubes
  - New DDA scanline rasterization
  - 2-3x faster than old renderer
  - Perspective-correct texturing
  - Subpixel pre-stepping
- **Performance:** ~30-60 FPS (vs 15-20 FPS old)

#### 2. City Scene (DDA Renderer) ⚡ NEW
- **File:** `city_scene.lua`
- **Description:** Buildings, sphere, and ground
- **Features:**
  - Grid of 20+ buildings (varying heights)
  - Animated low-poly sphere (orbits scene)
  - Textured ground plane
  - Two alternating textures
  - ~300-400 triangles per frame
- **Performance:** ~60+ FPS

#### 3. 5000 Cubes (Old Renderer)
- **File:** `main.lua`
- **Description:** Original bounding-box + barycentric
- **Purpose:** Performance comparison
- **Features:**
  - Same 5000 cubes as #1
  - Old rendering algorithm
  - Slower but functional
- **Performance:** ~15-20 FPS
- **Note:** Kept intact for comparison!

#### 4. Software Demo (Simple)
- **File:** `main_software.lua`
- **Description:** Simple software renderer demo
- **Purpose:** Educational reference
- **Features:**
  - Basic software rendering
  - Simple scene

## Menu Navigation

### Controls
- **↑ Up Arrow** - Move selection up
- **↓ Down Arrow** - Move selection down
- **Enter** - Launch selected scene
- **Space** - Launch selected scene (alternative)
- **ESC** - Quit application

### Keyboard Shortcuts
None currently - navigate with arrows and Enter

## Returning to Menu

From any scene, press **ESC** to return to the menu.

**Exception:** The "5000 Cubes (Old Renderer)" scene will quit the application when ESC is pressed (due to how it was originally designed). To compare, launch it last or restart the menu after.

## Scene Controls (Universal)

Once in a scene, use these controls:

### Camera Movement
- **W** - Move forward
- **S** - Move backward
- **A** - Strafe left
- **D** - Strafe right
- **Space** - Move up (some scenes)
- **Left Shift** - Move down (some scenes)

### Camera Rotation
- **← Left Arrow** - Rotate left
- **→ Right Arrow** - Rotate right
- **↑ Up Arrow** - Look up
- **↓ Down Arrow** - Look down

### Exit
- **ESC** - Return to menu (or quit)

## Technical Implementation

### How It Works

The menu system works by:

1. **Loading menu.lua** - Defines all available scenes
2. **Displaying scene list** - Shows titles, descriptions, files
3. **User selects scene** - Arrow keys + Enter
4. **Dynamic module loading** - Requires the selected scene file
5. **Callback replacement** - Replaces love.load, love.update, love.draw, love.keypressed
6. **Scene runs** - Selected scene takes over
7. **ESC to return** - Reloads menu and resets callbacks

### Code Structure

```lua
-- main_menu.lua (entry point)
local menu = require("menu")
function love.load() menu.load() end
function love.update(dt) menu.update(dt) end
function love.draw() menu.draw() end
function love.keypressed(key) menu.keypressed(key) end

-- menu.lua (scene manager)
local menuItems = {
    {title, description, file, module},
    -- ... more scenes
}

function menu.launchScene(index)
    -- Clear old modules
    -- Load new scene
    -- Replace callbacks
end

function menu.returnToMenu()
    -- Clear scene modules
    -- Reset to menu callbacks
end
```

## Adding New Scenes

To add a new scene to the menu:

1. Create your scene file (e.g., `my_scene.lua`)
2. Export functions as a table:
   ```lua
   return {
       load = love.load,
       update = love.update,
       draw = love.draw,
       keypressed = love.keypressed
   }
   ```

3. Add to `menu.lua` in the `menuItems` array:
   ```lua
   {
       title = "My New Scene",
       description = "Description of what it does",
       file = "my_scene.lua",
       module = nil
   }
   ```

4. Add handler in `menu.launchScene()`:
   ```lua
   elseif item.file == "my_scene.lua" then
       local scene = require("my_scene")
       love.load = scene.load
       love.update = scene.update
       love.draw = scene.draw
       love.keypressed = function(key)
           if key == "escape" then
               menu.returnToMenu()
           else
               if scene.keypressed then scene.keypressed(key) end
           end
       end
       love.load()
   ```

## Performance Comparison

Use the menu to easily compare performance:

### Test 1: DDA vs Old Renderer
1. Launch "5000 Cubes (DDA Renderer)" ⚡
2. Note FPS (usually 30-60)
3. Press ESC to return to menu
4. Launch "5000 Cubes (Old Renderer)"
5. Note FPS (usually 15-20)
6. **Result:** ~2-3x speedup with DDA!

### Test 2: Visual Quality
1. Launch City Scene
2. Move camera through buildings
3. Look for:
   - Solid vertices (no wobbling)
   - No seams between triangles
   - Proper perspective on textures
   - Smooth rotation

## Troubleshooting

### Menu Won't Launch
- **Check:** Is LÖVE installed? `love --version`
- **Check:** Are you in the right directory?
- **Try:** `love . main_menu.lua` from command line

### Scene Won't Load
- **Check:** Is the scene file present?
- **Check:** Console output for Lua errors
- **Try:** Launch scene directly: `love . scene_name.lua`

### Can't Return to Menu
- **Reason:** "5000 Cubes (Old Renderer)" quits on ESC
- **Solution:** Restart menu after testing old renderer

### Performance Issues
- **Lower resolution:** Edit RENDER_WIDTH/HEIGHT in scene files
- **Reduce cubes:** Change NUM_CUBES in cubes_scene_dda.lua
- **Check CPU usage:** Software rendering is CPU-intensive

## Files Reference

### Menu System Files
- `main_menu.lua` - Entry point (starts menu)
- `menu.lua` - Menu logic and scene management
- `run_menu.bat` - Windows launcher

### Scene Files
- `cubes_scene_dda.lua` - 5000 cubes with DDA renderer
- `city_scene.lua` - City scene with DDA renderer
- `main.lua` - Original cubes (old renderer)
- `main_software.lua` - Simple software demo

### Renderer Files
- `renderer_dda.lua` - New DDA scanline renderer
- `renderer.lua` - Original renderer (preserved)

## Future Enhancements

Potential menu improvements:

- [ ] Performance stats in menu (last FPS, triangle count)
- [ ] Scene thumbnails/screenshots
- [ ] Settings menu (resolution, cube count, etc.)
- [ ] Keyboard shortcuts (1-4 to launch scenes)
- [ ] Mouse support (click to select)
- [ ] Scene history (recently played)
- [ ] Comparison mode (split screen?)

## Conclusion

The menu system makes it easy to:
- ✅ Test different rendering techniques
- ✅ Compare performance side-by-side
- ✅ Switch between scenes without restarting
- ✅ Keep old code preserved for reference
- ✅ Add new scenes easily

Use it to explore the engine and see the DDA renderer improvements in action!

---

**Created:** 2025-10-23
**Version:** 1.0
**Status:** Fully functional
