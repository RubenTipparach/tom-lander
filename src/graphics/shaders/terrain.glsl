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

// Cascaded Shadow map uniforms
uniform float u_shadowMapEnabled;
// Near cascade (high detail, close range)
uniform Image u_shadowMapNear;
uniform mat4 u_lightViewMatrixNear;
uniform mat4 u_lightProjMatrixNear;
// Far cascade (lower detail, wide range)
uniform Image u_shadowMapFar;
uniform mat4 u_lightViewMatrixFar;
uniform mat4 u_lightProjMatrixFar;
// Cascade split distance
uniform float u_cascadeSplit;  // Distance where we switch from near to far cascade
uniform float u_shadowDebug;   // 1.0 = show debug colors (red=shadow, green=lit, yellow=near cascade)

// Legacy uniforms (kept for compatibility, map to far cascade)
uniform Image u_shadowMap;
uniform mat4 u_lightViewMatrix;
uniform mat4 u_lightProjMatrix;
uniform float u_shadowDarkness;

// Palette-based shadow uniforms
uniform float u_usePaletteShadows;  // 1.0 = palette shadows, 0.0 = RGB darkening
uniform float u_ditherPaletteShadows;  // 1.0 = dither, 0.0 = hard levels
uniform float u_shadowBrightnessMin;   // Brightness for darkest shadow
uniform float u_shadowBrightnessMax;   // Brightness for original color
uniform float u_shadowDitherRange;     // Range of blend where dithering occurs (0-1)
uniform Image u_paletteShadowLookup;   // 32x8 texture: palette shadows lookup (x=color, y=level)

// Point lights (max 4)
uniform int u_pointLightCount;
uniform vec3 u_pointLightPos[4];
uniform float u_pointLightRadius[4];
uniform float u_pointLightIntensity[4];
uniform float u_pointLightUseNormals;  // 1.0 = use N·L calculation, 0.0 = omnidirectional

#ifdef VERTEX
varying vec2 v_texCoord;
varying vec4 v_color;
varying float v_height;      // Raw height value for texture blending
varying float v_viewDist;
varying vec4 v_worldPos;     // World position for shadow map lookup
varying vec3 v_worldNormal;  // World-space normal for point light calculations

// Estimate world normal from neighboring height samples
// For terrain, we approximate using the position gradient
vec3 estimateTerrainNormal(vec4 worldPos) {
    // For terrain, assume upward-facing with some tilt based on position
    // This is approximate - actual normal would come from heightmap gradient
    // We use the model matrix to transform a base up vector
    vec3 baseNormal = vec3(0.0, 1.0, 0.0);
    // Transform normal by model matrix (ignoring translation)
    mat3 normalMatrix = mat3(modelMatrix);
    return normalize(normalMatrix * baseNormal);
}

vec4 position(mat4 transformProjection, vec4 vertexPosition) {
    vec4 worldPosition = modelMatrix * vertexPosition;
    vec4 viewPosition = viewMatrix * worldPosition;
    vec4 screenPosition = projectionMatrix * viewPosition;

    v_worldPos = worldPosition;
    v_viewDist = length(viewPosition.xyz);
    v_texCoord = VaryingTexCoord.xy;
    v_color = VaryingColor;

    // Estimate world normal for point light calculations
    v_worldNormal = estimateTerrainNormal(worldPosition);

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
varying vec4 v_worldPos;
varying vec3 v_worldNormal;

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

// Calculate point light contribution at a world position with dithered falloff
// Uses N·L dot product for angle-based lighting when enabled
// Returns additive brightness (0 = no light, 1+ = bright)
float calculatePointLights(vec3 worldPos, vec3 worldNormal, vec2 screenCoords) {
    float totalLight = 0.0;
    float ditherThreshold = getBayerValue(screenCoords);

    for (int i = 0; i < 4; i++) {
        if (i >= u_pointLightCount) break;

        vec3 lightPos = u_pointLightPos[i];
        float radius = u_pointLightRadius[i];
        float intensity = u_pointLightIntensity[i];

        // Distance from point to light
        vec3 toLight = lightPos - worldPos;
        float dist = length(toLight);

        // Dithered falloff within radius
        if (dist < radius) {
            float attenuation = 1.0 - (dist / radius);

            // Apply N·L angle factor if normals are enabled
            float angleFactor = 1.0;
            if (u_pointLightUseNormals > 0.5 && dist > 0.01) {
                vec3 lightDir = toLight / dist;  // Normalized direction to light
                float NdotL = dot(worldNormal, lightDir);
                // Clamp to 0-1 range (surfaces facing away get no light)
                angleFactor = max(0.0, NdotL);
            }

            // Use dithering for smooth falloff at edges
            float finalAttenuation = attenuation * angleFactor;
            if (finalAttenuation > ditherThreshold * 0.3) {
                totalLight += intensity * finalAttenuation;
            }
        }
    }

    return totalLight;
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

// Apply palette-based shadow to a color
// combinedBrightness: 0.0 = darkest, 1.0 = brightest
vec3 applyPaletteShadow(vec3 texColor, float combinedBrightness, vec2 screenCoords) {
    // Find closest palette color for the texture color
    int paletteIndex = findPaletteIndex(texColor);

    // Map brightness to shadow level (0-7)
    // Level 0 = brightest (original color), Level 7 = darkest shadow
    float normalizedBrightness = clamp(
        (combinedBrightness - u_shadowBrightnessMin) / (u_shadowBrightnessMax - u_shadowBrightnessMin),
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
    vec2 uv0 = vec2((float(paletteIndex) + 0.5) / 32.0, (float(level0) + 0.5) / 8.0);
    vec2 uv1 = vec2((float(paletteIndex) + 0.5) / 32.0, (float(level1) + 0.5) / 8.0);

    vec3 color0 = Texel(u_paletteShadowLookup, uv0).rgb;
    vec3 color1 = Texel(u_paletteShadowLookup, uv1).rgb;

    // Choose between dithered and hard transition
    if (u_ditherPaletteShadows > 0.5 && u_shadowDitherRange > 0.0) {
        // Dithered transition between levels
        float ditherRangeMin = 0.5 - u_shadowDitherRange * 0.5;
        float ditherRangeMax = 0.5 + u_shadowDitherRange * 0.5;

        if (blend < ditherRangeMin) {
            return color0;
        } else if (blend > ditherRangeMax) {
            return color1;
        } else {
            // Within dither range - apply dithering
            float normalizedBlend = (blend - ditherRangeMin) / (ditherRangeMax - ditherRangeMin);
            float ditherThreshold = getBayerValue(screenCoords);
            return (normalizedBlend > ditherThreshold) ? color1 : color0;
        }
    } else {
        // Hard level cutoff (no dithering)
        return color0;
    }
}

// Sample shadow from a specific cascade
// Returns 1.0 if in shadow, 0.0 if lit
float sampleShadowCascade(vec4 worldPos, mat4 viewMat, mat4 projMat, Image shadowTex) {
    // Transform world position to light clip space
    vec4 lightViewPos = viewMat * worldPos;
    vec4 lightClipPos = projMat * lightViewPos;

    // Perspective divide
    vec3 lightNDC = lightClipPos.xyz / lightClipPos.w;

    // Convert from NDC (-1 to 1) to texture coordinates (0 to 1)
    vec2 shadowUV = lightNDC.xy * 0.5 + 0.5;

    // Check if outside shadow map bounds
    if (shadowUV.x < 0.0 || shadowUV.x > 1.0 || shadowUV.y < 0.0 || shadowUV.y > 1.0) {
        return 0.0;  // Outside shadow map = not in shadow
    }

    // Sample shadow map depth
    float shadowMapDepth = Texel(shadowTex, shadowUV).r;

    // Calculate current fragment's depth (same formula as shadow shader)
    float currentDepth = lightNDC.z * 0.5 + 0.5;

    // Shadow bias to prevent shadow acne (smaller = shadows work closer to ground)
    float bias = 0.001;

    // If current depth > shadow map depth + bias, we're in shadow
    if (currentDepth > shadowMapDepth + bias) {
        return 1.0;  // In shadow
    }

    return 0.0;  // Lit
}

// Sample cascaded shadow maps - near cascade for close, far cascade for distant
float getShadowFactorCascaded(vec4 worldPos, float viewDist) {
    if (u_shadowMapEnabled < 0.5) return 0.0;

    // Use near cascade for close objects (higher detail)
    if (viewDist < u_cascadeSplit) {
        return sampleShadowCascade(worldPos, u_lightViewMatrixNear, u_lightProjMatrixNear, u_shadowMapNear);
    }
    // Use far cascade for distant objects (wider coverage)
    return sampleShadowCascade(worldPos, u_lightViewMatrixFar, u_lightProjMatrixFar, u_shadowMapFar);
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
    if (u_fogEnabled > 0.5 && v_viewDist > u_fogNear) {
        float fogFactor = clamp((v_viewDist - u_fogNear) / (u_fogFar - u_fogNear), 0.0, 1.0);
        float threshold = getBayerValue(screen_coords);
        if (fogFactor > threshold) {
            // Apply fog color immediately
            texColor.rgb = u_fogColor;
            texColor.a = 1.0;
            return texColor;  // Skip all lighting/shadow processing
        }
    }

    // Apply lighting
    {
        float brightness = v_color.r;  // Brightness stored in RGB channels

        // DEBUG: Visualize cascaded shadow maps - press F4 to toggle
        if (u_shadowDebug > 0.5 && u_shadowMapEnabled > 0.5) {
            bool useNearCascade = (v_viewDist < u_cascadeSplit);

            vec4 lightViewPos;
            vec4 lightClipPos;
            float shadowMapDepth;

            if (useNearCascade) {
                lightViewPos = u_lightViewMatrixNear * v_worldPos;
                lightClipPos = u_lightProjMatrixNear * lightViewPos;
            } else {
                lightViewPos = u_lightViewMatrixFar * v_worldPos;
                lightClipPos = u_lightProjMatrixFar * lightViewPos;
            }

            vec3 lightNDC = lightClipPos.xyz / lightClipPos.w;
            vec2 shadowUV = lightNDC.xy * 0.5 + 0.5;

            if (shadowUV.x < 0.0 || shadowUV.x > 1.0 || shadowUV.y < 0.0 || shadowUV.y > 1.0) {
                return vec4(0.0, 0.0, 1.0, 1.0);  // Blue = outside shadow map
            }

            if (useNearCascade) {
                shadowMapDepth = Texel(u_shadowMapNear, shadowUV).r;
            } else {
                shadowMapDepth = Texel(u_shadowMapFar, shadowUV).r;
            }

            float currentDepth = lightNDC.z * 0.5 + 0.5;

            // Distinct colors: Near=orange/yellow, Far=red/green
            if (currentDepth > shadowMapDepth + 0.001) {
                // SHADOW
                if (useNearCascade) {
                    return vec4(1.0, 0.5, 0.0, 1.0);  // Orange = near cascade shadow
                } else {
                    return vec4(1.0, 0.0, 0.0, 1.0);  // Red = far cascade shadow
                }
            } else {
                // LIT
                if (useNearCascade) {
                    return vec4(1.0, 1.0, 0.0, 1.0);  // Yellow = near cascade lit
                } else {
                    return vec4(0.0, 1.0, 0.0, 1.0);  // Green = far cascade lit
                }
            }
        }

        // Get shadow factor (0 = lit, 1 = in shadow)
        float shadowFactor = 0.0;
        if (u_shadowMapEnabled > 0.5) {
            shadowFactor = getShadowFactorCascaded(v_worldPos, v_viewDist);
        }

        // Combine directional light brightness with shadow
        // Shadow reduces brightness further (multiply by shadow darkness factor)
        float combinedBrightness = brightness;
        if (shadowFactor > 0.5) {
            combinedBrightness *= u_shadowDarkness;  // Darken in shadow
        }

        // Add point light contribution (additive, affects even shadowed areas)
        float pointLightContrib = calculatePointLights(v_worldPos.xyz, normalize(v_worldNormal), screen_coords);
        combinedBrightness = clamp(combinedBrightness + pointLightContrib, 0.0, 1.0);

        // Apply lighting using palette shadows or RGB darkening
        if (u_usePaletteShadows > 0.5 && isPaletteTextureValid()) {
            // Palette-based shadow with dithering
            texColor.rgb = applyPaletteShadow(texColor.rgb, combinedBrightness, screen_coords);
        } else {
            // Fallback: RGB darkening
            texColor.rgb *= combinedBrightness;
        }

        texColor.a = 1.0;  // Terrain is always fully opaque
    }

    return texColor;
}
#endif
