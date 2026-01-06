// Retro 3D Shader - Based on g3d's approach
// Uses separate projection, view, and model matrices
// Includes dithered fog effect

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform mat4 modelMatrix;
uniform vec2 u_textureSize;
uniform bool u_ditherEnabled;

// Fog uniforms
uniform float u_fogEnabled;  // 1.0 = enabled, 0.0 = disabled (floats more reliable than bools in LÖVE)
uniform float u_fogNear;
uniform float u_fogFar;
uniform vec3 u_fogColor;

#ifdef VERTEX
varying vec4 worldPosition;
varying vec4 viewPosition;
varying vec4 screenPosition;
varying vec2 v_texCoord;
varying vec4 v_color;
varying float v_viewDist;

vec4 position(mat4 transformProjection, vec4 vertexPosition) {
    // Transform through the pipeline like g3d
    worldPosition = modelMatrix * vertexPosition;
    viewPosition = viewMatrix * worldPosition;
    screenPosition = projectionMatrix * viewPosition;

    // Pass view distance for fog calculation
    v_viewDist = length(viewPosition.xyz);

    // Pass through texture coords and color
    v_texCoord = VaryingTexCoord.xy;
    v_color = VaryingColor;

    // Flip Y for canvas rendering (LÖVE's canvas has inverted Y)
    screenPosition.y *= -1.0;

    return screenPosition;
}
#endif

#ifdef PIXEL
varying vec2 v_texCoord;
varying vec4 v_color;
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

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    // Wrap UVs to 0-1 range (matches software renderer behavior)
    vec2 wrappedUV = mod(v_texCoord, 1.0);

    // Nearest-neighbor sampling
    vec2 texelCoord = floor(wrappedUV * u_textureSize) / u_textureSize;
    texelCoord += 0.5 / u_textureSize;

    vec4 texColor = Texel(tex, texelCoord);

    // Treat black as transparent (matches software renderer)
    if (texColor.r < 0.01 && texColor.g < 0.01 && texColor.b < 0.01) {
        discard;
    }

    // Apply vertex color modulation (includes brightness)
    texColor *= v_color;

    // Dithered fog effect
    // Note: Skydome disables fog on the Lua side, so no distance check needed here
    if (u_fogEnabled > 0.5 && v_viewDist > u_fogNear) {
        float fogFactor = clamp((v_viewDist - u_fogNear) / (u_fogFar - u_fogNear), 0.0, 1.0);

        // Use dithering for fog transition (retro look)
        float threshold = getBayerValue(screen_coords);
        if (fogFactor > threshold) {
            // Replace with fog color
            texColor.rgb = u_fogColor;
        }
    }

    // Dither based on alpha for transparency effects
    if (u_ditherEnabled && texColor.a < 1.0) {
        float threshold = getBayerValue(screen_coords);
        if (texColor.a < threshold) {
            discard;
        }
        texColor.a = 1.0;
    }

    return texColor;
}
#endif
