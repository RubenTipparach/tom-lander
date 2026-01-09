// Terrain Shader - Height-based texture blending with dithering
// Blends between ground, grass, and rocks based on vertex height

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform mat4 modelMatrix;

// Terrain textures
uniform Image u_texGround;
uniform Image u_texGrass;
uniform Image u_texRocks;
uniform vec2 u_textureSize;

// Height thresholds (palette indices)
uniform float u_groundToGrass;  // Height where ground transitions to grass (default 3)
uniform float u_grassToRocks;   // Height where grass transitions to rocks (default 10)
// Blend ranges (separate for each transition)
uniform float u_groundGrassBlend;  // Ground-to-grass (sand) blend range (default 2.0)
uniform float u_grassRocksBlend;   // Grass-to-rocks blend range (default 4.0)

// Fog uniforms
uniform float u_fogEnabled;
uniform float u_fogNear;
uniform float u_fogFar;
uniform vec3 u_fogColor;

// Palette-based shadow uniforms
uniform float u_usePaletteShadows;
uniform float u_ditherPaletteShadows;
uniform float u_shadowBrightnessMin;
uniform float u_shadowBrightnessMax;
uniform float u_shadowDitherRange;
uniform Image u_paletteShadowLookup;   // 32x8 texture: palette shadows lookup (x=color, y=level)

#ifdef VERTEX
varying vec2 v_texCoord;
varying vec4 v_color;
varying float v_height;      // Raw height value for texture blending
varying float v_viewDist;

vec4 position(mat4 transformProjection, vec4 vertexPosition) {
    vec4 worldPosition = modelMatrix * vertexPosition;
    vec4 viewPosition = viewMatrix * worldPosition;
    vec4 screenPosition = projectionMatrix * viewPosition;

    v_viewDist = length(viewPosition.xyz);
    v_texCoord = VaryingTexCoord.xy;
    v_color = VaryingColor;

    // Height is passed via vertex color alpha channel (scaled 0-1 for 0-32 range)
    v_height = VaryingColor.a * 32.0;

    // Flip Y for canvas rendering (LÖVE's canvas has inverted Y)
    screenPosition.y *= -1.0;

    return screenPosition;
}
#endif

#ifdef PIXEL
varying vec2 v_texCoord;
varying vec4 v_color;
varying float v_height;
varying float v_viewDist;

// Bayer 4x4 dithering matrix
float getBayerValue(vec2 screenPos) {
    int x = int(mod(screenPos.x, 4.0));
    int y = int(mod(screenPos.y, 4.0));
    int idx = y * 4 + x;

    if (idx == 0) return 0.0/16.0;
    if (idx == 1) return 8.0/16.0;
    if (idx == 2) return 2.0/16.0;
    if (idx == 3) return 10.0/16.0;
    if (idx == 4) return 12.0/16.0;
    if (idx == 5) return 4.0/16.0;
    if (idx == 6) return 14.0/16.0;
    if (idx == 7) return 6.0/16.0;
    if (idx == 8) return 3.0/16.0;
    if (idx == 9) return 11.0/16.0;
    if (idx == 10) return 1.0/16.0;
    if (idx == 11) return 9.0/16.0;
    if (idx == 12) return 15.0/16.0;
    if (idx == 13) return 7.0/16.0;
    if (idx == 14) return 13.0/16.0;
    return 5.0/16.0;
}

// Find closest palette index for a given RGB color by searching the lookup texture
int findPaletteIndex(vec3 rgb) {
    int bestIndex = 0;
    float bestDist = 1000000.0;

    // Sample the first row (level 0) of the palette shadow lookup to get all 32 palette colors
    for (int i = 0; i < 32; i++) {
        // Sample palette color from lookup texture (row 0 = original colors)
        vec2 uv = vec2((float(i) + 0.5) / 32.0, 0.5 / 8.0);
        vec3 paletteColor = Texel(u_paletteShadowLookup, uv).rgb;

        vec3 diff = rgb - paletteColor;
        float dist = dot(diff, diff);
        if (dist < bestDist) {
            bestDist = dist;
            bestIndex = i;
        }
    }

    return bestIndex;
}

// Check if palette texture is loaded by sampling a known non-black color
bool isPaletteTextureValid() {
    // Sample palette index 7 (white - should be bright)
    vec2 uv = vec2((7.0 + 0.5) / 32.0, 0.5 / 8.0);
    vec3 white = Texel(u_paletteShadowLookup, uv).rgb;
    // White should have high brightness (>0.8)
    return (white.r + white.g + white.b) > 2.0;
}

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    // Wrap UVs and do nearest-neighbor sampling
    vec2 wrappedUV = mod(v_texCoord, 1.0);
    vec2 texelCoord = floor(wrappedUV * u_textureSize) / u_textureSize;
    texelCoord += 0.5 / u_textureSize;

    // Sample all three terrain textures
    vec4 groundColor = Texel(u_texGround, texelCoord);
    vec4 grassColor = Texel(u_texGrass, texelCoord);
    vec4 rocksColor = Texel(u_texRocks, texelCoord);

    // Get dither threshold for this pixel
    float dither = getBayerValue(screen_coords);

    // Select texture based on height with dithered blending
    vec4 texColor;

    if (v_height >= u_grassToRocks) {
        // Pure rocks
        texColor = rocksColor;
    } else if (v_height >= u_grassToRocks - u_grassRocksBlend) {
        // Grass-to-rocks transition zone
        float blend = (v_height - (u_grassToRocks - u_grassRocksBlend)) / u_grassRocksBlend;
        texColor = (dither < blend) ? rocksColor : grassColor;
    } else if (v_height >= u_groundToGrass) {
        // Pure grass
        texColor = grassColor;
    } else if (v_height >= u_groundToGrass - u_groundGrassBlend) {
        // Ground-to-grass (sand) transition zone
        float blend = (v_height - (u_groundToGrass - u_groundGrassBlend)) / u_groundGrassBlend;
        texColor = (dither < blend) ? grassColor : groundColor;
    } else {
        // Pure ground (sand)
        texColor = groundColor;
    }

    // Treat black as transparent
    if (texColor.r < 0.01 && texColor.g < 0.01 && texColor.b < 0.01) {
        discard;
    }

    // Check for fog FIRST - if fogged, skip all lighting/shadow calculations
    bool isFogged = false;
    if (u_fogEnabled > 0.5 && v_viewDist > u_fogNear) {
        float fogFactor = clamp((v_viewDist - u_fogNear) / (u_fogFar - u_fogNear), 0.0, 1.0);
        float threshold = getBayerValue(screen_coords);
        if (fogFactor > threshold) {
            isFogged = true;
            // Apply fog color immediately
            if (u_usePaletteShadows > 0.5 && isPaletteTextureValid()) {
                int fogPaletteIndex = findPaletteIndex(u_fogColor);
                vec2 fogUV = vec2((float(fogPaletteIndex) + 0.5) / 32.0, 0.5 / 8.0);
                texColor.rgb = Texel(u_paletteShadowLookup, fogUV).rgb;
            } else {
                texColor.rgb = u_fogColor;
            }
            texColor.a = 1.0;
            return texColor;  // Skip all lighting/shadow processing
        }
    }

    // Apply lighting - ALWAYS use palette path to prevent uniform optimization
    {
        float brightness = v_color.r;  // Brightness stored in RGB channels

        // Check for unlit objects (brightness >= 0.999 means no lighting/shadows applied)
        bool isUnlit = (brightness >= 0.999);

        if (!isUnlit) {

        // Palette-based shadow mapping with 8 levels

        // Find closest palette color for the texture color
        int paletteIndex = findPaletteIndex(texColor.rgb);

        // Map brightness to shadow level (0-7)
        // Level 0 = brightest (original color), Level 7 = darkest shadow
        float normalizedBrightness = clamp(
            (brightness - u_shadowBrightnessMin) / (u_shadowBrightnessMax - u_shadowBrightnessMin),
            0.0, 1.0
        );

        // INVERT: High brightness = low level (bright), Low brightness = high level (dark)
        float levelFloat = (1.0 - normalizedBrightness) * 7.0;
        float levelFloored = floor(levelFloat);
        int level0 = int(levelFloored);
        int level1 = level0 + 1;
        if (level1 > 7) level1 = 7;
        float blend = levelFloat - levelFloored;

        // Get colors for the two adjacent levels from the lookup texture
        // UV coordinates: x = (paletteIndex + 0.5) / 32, y = (level + 0.5) / 8
        vec2 uv0 = vec2((float(paletteIndex) + 0.5) / 32.0, (float(level0) + 0.5) / 8.0);
        vec2 uv1 = vec2((float(paletteIndex) + 0.5) / 32.0, (float(level1) + 0.5) / 8.0);

        vec3 color0 = Texel(u_paletteShadowLookup, uv0).rgb;
        vec3 color1 = Texel(u_paletteShadowLookup, uv1).rgb;

        // Debug: Check if palette lookup is working
        // If we get pure black from lookup but we're not sampling black palette
        if (length(color0) < 0.01 && paletteIndex != 0) {
            // Texture not working - use RGB fallback
            texColor.rgb *= v_color.rgb;
            return texColor;
        }

        // Choose between dithered and hard transition
        if (u_ditherPaletteShadows > 0.5 && u_shadowDitherRange > 0.0) {
            // Dithered transition between levels
            float ditherRangeMin = 0.5 - u_shadowDitherRange * 0.5;
            float ditherRangeMax = 0.5 + u_shadowDitherRange * 0.5;

            if (blend < ditherRangeMin) {
                // Below dither range - use color0
                texColor.rgb = color0;
            } else if (blend > ditherRangeMax) {
                // Above dither range - use color1
                texColor.rgb = color1;
            } else {
                // Within dither range - apply dithering
                float normalizedBlend = (blend - ditherRangeMin) / (ditherRangeMax - ditherRangeMin);
                float ditherThreshold = getBayerValue(screen_coords);
                texColor.rgb = (normalizedBlend > ditherThreshold) ? color1 : color0;
            }
        } else {
            // Hard level cutoff (no dithering)
            texColor.rgb = color0;
        }

        // Apply result based on mode
        if (u_usePaletteShadows < 0.5) {
            // Palette shadows disabled - use traditional RGB darkening instead
            texColor.rgb *= v_color.rgb;
        }

        } // End of !isUnlit block

        // NOTE: Terrain doesn't use alpha for transparency
        // v_color.a contains height data, not transparency
        // So we don't touch texColor.a for terrain
        texColor.a = 1.0;  // Terrain is always fully opaque
    }

    // NOTE: Fog is now applied at the beginning of the shader (before lighting/shadows)
    // to ensure fog always overrides terrain colors
    // NOTE: Terrain doesn't use alpha transparency - alpha stores height data

    return texColor;
}
#endif
