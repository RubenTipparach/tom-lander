// Retro Flat Shader - For 2D UI elements drawn to the low-res canvas
// No 3D transformation, just nearest-neighbor and optional dithering

#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
    return transform_projection * vertex_position;
}
#endif

#ifdef PIXEL
uniform vec2 u_textureSize;
uniform bool u_ditherEnabled;

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
    vec2 wrappedUV = mod(texture_coords, 1.0);

    // Nearest-neighbor sampling
    vec2 texelCoord = floor(wrappedUV * u_textureSize) / u_textureSize;
    texelCoord += 0.5 / u_textureSize;

    vec4 texColor = Texel(tex, texelCoord);

    // Treat black as transparent (matches software renderer)
    if (texColor.r < 0.01 && texColor.g < 0.01 && texColor.b < 0.01) {
        discard;
    }

    // Apply vertex color modulation
    texColor *= color;

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
