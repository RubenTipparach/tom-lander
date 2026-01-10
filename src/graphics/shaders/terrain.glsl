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

#ifdef VERTEX
varying vec2 v_texCoord;
varying vec4 v_color;
varying float v_height;      // Raw height value for texture blending
varying float v_viewDist;
varying vec4 v_worldPos;     // World position for shadow map lookup

vec4 position(mat4 transformProjection, vec4 vertexPosition) {
    vec4 worldPosition = modelMatrix * vertexPosition;
    vec4 viewPosition = viewMatrix * worldPosition;
    vec4 screenPosition = projectionMatrix * viewPosition;

    v_worldPos = worldPosition;
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
varying vec4 v_worldPos;

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

        // Apply directional lighting via RGB darkening
        texColor.rgb *= brightness;

        // Apply cascaded shadow darkening
        if (u_shadowMapEnabled > 0.5) {
            float shadowFactor = getShadowFactorCascaded(v_worldPos, v_viewDist);
            if (shadowFactor > 0.5) {
                // In shadow - darken significantly
                texColor.rgb *= 0.4;
            }
        }

        texColor.a = 1.0;  // Terrain is always fully opaque
    }

    return texColor;
}
#endif
