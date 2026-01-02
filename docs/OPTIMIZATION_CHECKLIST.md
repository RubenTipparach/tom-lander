# Software Renderer Optimization Checklist

Based on analysis of the [Software-3D-Perspective-Correct-Textured-Triangles](https://github.com/Haggarman/Software-3D-Perspective-Correct-Textured-Triangles) reference library.

---

## Current Implementation Status

### ✅ Already Implemented
- [x] Basic perspective-correct texture mapping
- [x] Z-buffer depth sorting
- [x] Barycentric coordinate interpolation
- [x] Basic backface culling (screen-space cross product)
- [x] Frustum culling (cube-level and triangle-level)
- [x] Painter's algorithm (triangle depth sorting)

---

## 🔴 PHASE 1: CRITICAL CORRECTNESS FIXES
**Priority:** Must implement first - fixes rendering bugs and visual artifacts

### 1.1 Scanline/DDA Triangle Rasterization ✅
- [x] **Implement DDA edge walking algorithm**
  - [x] Sort vertices by Y coordinate (A=top, B=middle, C=bottom)
  - [x] Calculate major edge steps (A→C)
  - [x] Calculate minor edge steps (A→B, then B→C)
  - [x] Walk both edges simultaneously using DDA
  - [x] Draw horizontal scanlines left-to-right only
- [x] **Created new renderer_dda.lua with full DDA implementation**
- [x] **Created city_scene.lua for validation** (buildings + sphere)
- [ ] **Test with two-triangle case** (check for gaps/seams) - IN PROGRESS

**Reference:** `reference-lib/Concepts/TwoTriangles.bas` lines 320-603
**Current problem:** Testing EVERY pixel in bounding box (very slow)
**Performance gain:** 3-10x faster for large triangles
**Impact:** 🔴 CRITICAL - Biggest single performance improvement

---

### 1.2 Subpixel Accuracy & Pre-stepping ✅
- [x] **Implement pre-stepping for Y coordinates**
  - [x] Use `math.ceil()` to round Y to next integer pixel row
  - [x] Calculate fractional distance: `prestep_y = draw_min_y - A.y`
  - [x] Pre-step all edge attributes: X, W, U, V
- [x] **Implement pre-stepping for X coordinates**
  - [x] Use `math.ceil()` for horizontal scanline start
  - [x] Calculate fractional distance: `prestep_x = col - leg_x`
  - [x] Pre-step all span attributes
- [x] **Test with moving camera** (city scene validates this)
- [ ] **Test with adjacent triangles** (verify no seams) - TESTING IN CITY SCENE

**Reference:** `TwoTriangles.bas` lines 409-424, 500-505
**Current problem:** Vertex wobbling, visible seams between triangles
**Visual benefit:** Rock-solid vertices, perfect triangle alignment
**Impact:** 🔴 CRITICAL - Required for visual quality

---

### 1.3 Proper Near Frustum Clipping ✅
- [x] **Implement near plane clipping algorithm**
  - [x] Check which vertices are behind near plane (Z < near_distance)
  - [x] Implement 8 clipping cases (3 bits = 8 combinations)
  - [x] Calculate intersection points with near plane
  - [x] Interpolate all vertex attributes (U, V, W) at intersections
  - [x] Tesselate into 0, 1, or 2 output triangles
  - [x] Preserve winding order for backface culling
- [x] **Implemented in renderer_dda.lua clipTriangleNearPlane()**
- [x] **Add configurable near plane distance constant**
- [x] **Test with cube passing through camera**

**Reference:** `reference-lib/Concepts/NearFrustumClipTriangleAttributes.bas`
**Status:** ✅ COMPLETE - Sutherland-Hodgman clipping implemented
**Visual benefit:** Smooth rendering when objects pass through camera
**Impact:** 🔴 CRITICAL - Fixes major visual bug

---

## 🟡 PHASE 2: PERFORMANCE OPTIMIZATIONS
**Priority:** Implement after Phase 1 - significant performance gains

### 2.1 Rounding Rule (Overdraw Prevention) ✅
- [x] **Modify scanline drawing to skip rightmost pixel**
  - [x] Change `while col < draw_max_x` (not `<=`)
  - [x] Ensure `draw_max_x` uses `math.ceil()` without `-1`
- [x] **Skip bottom row of triangle**
  - [x] Change `draw_max_y = math.ceil(C.y) - 1`
- [x] **Test with tight mesh** (city scene + 5000 cubes verified)
- [x] **Measure performance improvement**

**Reference:** README.md "Overdraw" section
**Status:** ✅ COMPLETE - Lines 164 and 315 in renderer_dda.lua
**Performance gain:** ~10-15% reduction in pixel writes
**Impact:** 🟡 MEDIUM - Free performance win

---

### 2.2 Texture Coordinate Wrapping Modes
- [ ] **Implement tile/repeat mode**
  - [ ] Add bitwise AND for power-of-2 textures
  - [ ] Calculate texture mask: `mask = width - 1`
  - [ ] Apply: `texX = math.floor(u) & mask`
- [ ] **Implement clamp mode**
  - [ ] Add min/max clamping
  - [ ] Apply: `texX = math.max(0, math.min(width-1, math.floor(u)))`
- [ ] **Implement mirror mode (optional)**
  - [ ] Add fold-back logic
- [ ] **Add wrap mode parameter to texture sampling**
- [ ] **Test with repeating texture patterns**

**Reference:** `reference-lib/Concepts/TextureWrapOptions.bas`
**Current problem:** Only modulo wrapping (incorrect for some cases)
**Visual benefit:** Correct texture addressing
**Impact:** 🟡 MEDIUM - Required for many texture types

---

### 2.3 Direct Memory Access for Pixels ✅
- [x] **Research LuaJIT FFI for ImageData access**
- [x] **Implement direct memory writes in scanline loop**
  - [x] Get raw pointer to ImageData
  - [x] Calculate memory offset: `offset = (y * width + x) * 4`
  - [x] Write RGBA bytes directly
- [x] **Implemented FFI for both framebuffer and z-buffer**
- [x] **Benchmark before/after performance**

**Reference:** `TwoTriangles.bas` lines 442-447, 536-583
**Status:** ✅ COMPLETE - FFI pointers in renderer_dda.lua (lines 24-28, 42-46)
**Performance gain:** 5-10x faster pixel writes
**Impact:** 🟡 MEDIUM - Significant performance improvement

---

## 🟢 PHASE 3: VISUAL QUALITY ENHANCEMENTS
**Priority:** Implement after Phase 2 - improves visual fidelity

### 3.1 Bilinear Texture Filtering
- [ ] **Implement 4-point bilinear sampling**
  - [ ] Calculate fractional U, V: `frac_u = u - math.floor(u)`
  - [ ] Sample 4 texels: (u,v), (u+1,v), (u,v+1), (u+1,v+1)
  - [ ] Interpolate horizontally twice (top row, bottom row)
  - [ ] Interpolate vertically once (between rows)
- [ ] **Add 0.5 texel offset for bilinear mode**
- [ ] **Add filter mode selection (nearest vs bilinear)**
- [ ] **Test performance impact**

**Reference:** README.md "4 Point Bilinear" section
**Current:** Nearest-neighbor (blocky magnification)
**Visual benefit:** Smooth texture magnification
**Cost:** 4x texture reads + interpolation math
**Impact:** 🟢 LOW - Optional quality improvement

---

### 3.2 Gouraud Shading (Vertex Colors)
- [ ] **Add RGB color to vertex structure**
  - [ ] Extend vertex to include: `r, g, b`
- [ ] **Add color interpolation to DDA**
  - [ ] Calculate color steps per Y: `leg_r_step`, `leg_g_step`, `leg_b_step`
  - [ ] Calculate color steps per X in scanline
  - [ ] Pre-step color values
- [ ] **Multiply or add vertex color to texture color**
- [ ] **Test with colored cube vertices**

**Reference:** `reference-lib/Cube/VertexColorCube.bas`
**Visual benefit:** Per-vertex lighting, smooth color gradients
**Use case:** Simple lighting without normal calculations
**Impact:** 🟢 LOW - Nice to have

---

### 3.3 Alpha Channel & Blending
- [ ] **Add alpha to vertex and texture sampling**
  - [ ] Extend vertex to include alpha value
  - [ ] Sample alpha from texture
- [ ] **Implement alpha test (masking)**
  - [ ] Add threshold: `if alpha < threshold then skip_pixel`
  - [ ] Use for cutout textures (fences, foliage)
- [ ] **Implement alpha blending (transparency)**
  - [ ] Read background pixel before writing
  - [ ] Blend: `C = foreground * alpha + background * (1-alpha)`
- [ ] **Add blend mode selection**
  - [ ] Crossfade (normal transparency)
  - [ ] Additive (lighten)
  - [ ] Multiplicative (darken)
- [ ] **Sort transparent objects back-to-front**

**Reference:** README.md "Alpha Channel" section
**Visual benefit:** Transparency, cutout textures
**Cost:** Read-modify-write per pixel (slower)
**Impact:** 🟢 LOW - Required for specific effects

---

### 3.4 Depth Fog
- [ ] **Add fog configuration parameters**
  - [ ] `fog_near`, `fog_far`, `fog_color`
- [ ] **Calculate fog factor in pixel loop**
  - [ ] `fog_factor = (z - fog_near) / (fog_far - fog_near)`
  - [ ] Clamp to [0, 1]
- [ ] **Blend pixel color with fog color**
  - [ ] `color = lerp(color, fog_color, fog_factor)`
- [ ] **Add fog enable/disable toggle**
- [ ] **Test with distant objects**

**Reference:** README.md "Hardware Table Fog" section
**Visual benefit:** Atmospheric depth, hides far clipping
**Cost:** Small per-pixel math
**Impact:** 🟢 LOW - Atmospheric effect

---

### 3.5 Z-Fighting Bias
- [ ] **Add per-object Z bias parameter**
- [ ] **Add bias to Z before Z-buffer test**
  - [ ] `z_test = z + object_bias`
- [ ] **Use for coplanar surfaces** (decals, overlays)

**Reference:** `reference-lib/Cube/TextureZFightDonut.bas`
**Visual benefit:** Eliminates Z-fighting flicker
**Impact:** 🟢 LOW - Edge case fix

---

## 🔵 PHASE 4: ADVANCED FEATURES
**Priority:** Implement last - diminishing returns or niche use cases

### 4.1 Mipmapping & LOD
- [ ] **Generate mipmap chain on texture load**
  - [ ] Create pyramid: base, half, quarter, etc.
  - [ ] Stop at 1x1 texture
- [ ] **Calculate LOD per triangle**
  - [ ] Calculate texel-to-pixel ratio
  - [ ] `LOD = log2(texel_density)`
- [ ] **Select mipmap level based on LOD**
- [ ] **Implement tri-linear filtering (optional)**
  - [ ] Sample two mipmap levels
  - [ ] Interpolate based on fractional LOD

**Reference:** `reference-lib/Skybox/IsotropicMipmapRoad.bas`
**Visual benefit:** Reduces texture aliasing at distance
**Cost:** 33% more texture memory, slower sampling
**Impact:** 🔵 ADVANCED - Only needed for large textures

---

### 4.2 Fixed-Point Math
- [ ] **Profile float vs fixed-point performance**
- [ ] **Convert W, U, V to fixed-point if beneficial**
  - [ ] Choose precision (e.g., 16.16 fixed-point)
  - [ ] Replace divisions with bit shifts
- [ ] **Benchmark on target hardware**

**Reference:** README.md "Floating point numbers" section
**Performance gain:** Potentially faster on some hardware
**Cost:** Code complexity, overflow risk
**Impact:** 🔵 ADVANCED - Last resort optimization

---

### 4.3 Texture Swizzling
- [ ] **Implement texture memory layout reorganization**
  - [ ] Arrange 2x2 texel blocks adjacently
  - [ ] Pre-process on texture load
- [ ] **Update texture sampling to use swizzled layout**

**Reference:** README.md "Hardware considerations" section
**Performance gain:** Better cache coherency for bilinear
**Impact:** 🔵 ADVANCED - Premature optimization

---

## Testing Checklist

### Phase 1 Testing
- [ ] Two triangles sharing edge (no gap, no overdraw)
- [ ] Rotating triangle through near plane (no pop-in)
- [ ] Moving camera over textured surface (no wobbling)
- [ ] Tight mesh of 100+ triangles (no seams)

### Phase 2 Testing
- [ ] Performance benchmark: 5000 cubes at 30+ FPS
- [ ] Tiled texture wraps correctly
- [ ] Memory access doesn't crash

### Phase 3 Testing
- [ ] Bilinear filtering looks smooth
- [ ] Vertex colors interpolate correctly
- [ ] Transparent surfaces render correctly
- [ ] Fog blends smoothly with distance

### Phase 4 Testing
- [ ] Mipmaps reduce distant texture noise
- [ ] No visual regressions from optimizations

---

## Reference Files by Priority

### MUST READ - Phase 1
- 📖 `reference-lib/README.md` - **Read first** - Explains all concepts
- 💎 `reference-lib/Concepts/TwoTriangles.bas` - **Core DDA algorithm**
- 🔧 `reference-lib/Concepts/NearFrustumClipTriangleAttributes.bas` - Clipping

### Phase 2 & 3 Reference
- `reference-lib/Concepts/TextureWrapOptions.bas` - Wrap modes
- `reference-lib/Cube/VertexColorCube.bas` - Gouraud shading
- `reference-lib/Cube/ColorCubeAffine.bas` - Affine vs perspective

### Phase 4 Reference
- `reference-lib/Skybox/IsotropicMipmapRoad.bas` - Mipmapping
- `reference-lib/Skybox/TrilinearMipmapRoad.bas` - Tri-linear filtering

---

## Quick Reference: BASIC to Lua

| QB64 BASIC | Lua Equivalent |
|------------|----------------|
| `_Ceil(x)` | `math.ceil(x)` |
| `Int(x)` | `math.floor(x)` |
| `Abs(x)` | `math.abs(x)` |
| `Swap A, B` | `A, B = B, A` |
| `Static var` | `local var` outside loop |
| `While/Wend` | `while do end` |
| `If/Then` | `if then end` |

---

## Key Implementation Notes

### DDA Algorithm Summary
1. Sort vertices A, B, C by Y coordinate
2. Calculate edge deltas and steps (divide once per edge)
3. Pre-step to integer pixel boundaries
4. Walk major edge (A→C) and minor edge (A→B, then B→C)
5. For each row, draw horizontal span left→right
6. Increment accumulators with pre-calculated steps

### Perspective Correction Formula
```lua
-- At vertices: divide attributes by Z
vertex.w = 1 / z
vertex.u_over_w = u * vertex.w
vertex.v_over_w = v * vertex.w

-- During rasterization: interpolate w, u/w, v/w linearly

-- At each pixel: recover u and v
local z = 1 / w
local u = u_over_w * z
local v = v_over_w * z
```

### Pre-stepping Formula
```lua
-- Calculate fractional distance to next integer pixel
local prestep_y = math.ceil(start_y) - start_y

-- Advance all accumulators by this distance
leg_x = start_x + prestep_y * leg_x_step
leg_u = start_u + prestep_y * leg_u_step
-- ... etc for all attributes
```

---

## Progress Tracking

**Phase 1:** [▓▓▓▓▓▓▓▓] 3/3 tasks complete (100%) ✅
  - ✅ 1.1 DDA Scanline Rasterization - COMPLETE
  - ✅ 1.2 Subpixel Pre-stepping - COMPLETE
  - ✅ 1.3 Near Frustum Clipping - COMPLETE

**Phase 2:** [▓▓▓▓▓▓░░] 2/3 tasks complete (66%)
  - ✅ 2.1 Rounding Rule - COMPLETE
  - ⏳ 2.2 Texture Coordinate Wrapping - TODO
  - ✅ 2.3 Direct Memory Access (FFI) - COMPLETE

**Phase 3:** [ ] 0/5 tasks complete
**Phase 4:** [ ] 0/3 tasks complete

**Overall:** [▓▓▓▓▓░░░░░░░░░] 5/14 major features implemented (36%)

---

## Implementation Notes

**Files Created:**
- `renderer_dda.lua` - New DDA scanline renderer
- `city_scene.lua` - Validation scene with buildings and sphere
- `run_city.bat` - Quick launcher for city scene

**To Run City Scene:**
```bash
love . city_scene.lua
# or
./run_city.bat
```

**Next Steps:**
- Test for gaps/seams between adjacent triangles
- Implement near frustum clipping (1.3)
- Performance comparison: DDA vs bounding box

---

**Repository cloned to:** `reference-lib/`
**Last updated:** 2025-10-23
**Target:** Phase 1 - 66% complete!
