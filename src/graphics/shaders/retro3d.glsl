// Retro 3D Shader - Replicates software renderer look
// Features: Dithered fog, nearest-neighbor texturing, optional brightness

// Vertex shader
#ifdef VERTEX
varying vec2 vTexCoord;
varying float vDepth;
varying float vFogFactor;
varying float vBrightness;

uniform mat4 u_mvp;
uniform float u_fogNear;
uniform float u_fogFar;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    // Apply our custom MVP matrix to the vertex position
    // vertex_position contains (x, y, z, 1) from our mesh
    vec4 clipPos = u_mvp * vertex_position;

    // Pass depth for fog calculation (use positive W for distance)
    vDepth = clipPos.w;

    // Calculate fog factor (0 = no fog, 1 = full fog)
    vFogFactor = clamp((vDepth - u_fogNear) / (u_fogFar - u_fogNear), 0.0, 1.0);

    // Pass through texture coordinates
    vTexCoord = VertexTexCoord.xy;

    // Brightness from vertex color alpha
    vBrightness = VertexColor.a;

    // LÖVE2D uses top-left origin with Y pointing down (same as our software renderer)
    // OpenGL NDC has Y pointing up, so we need to flip Y to match LÖVE's convention
    clipPos.y = -clipPos.y;

    return clipPos;
}
#endif

// Fragment shader
#ifdef PIXEL
varying vec2 vTexCoord;
varying float vDepth;
varying float vFogFactor;
varying float vBrightness;

uniform vec2 u_textureSize;
uniform vec3 u_fogColor;
uniform bool u_ditherEnabled;
uniform bool u_fogEnabled;

// Bayer 4x4 dithering matrix (normalized to 0-1)
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
    // Nearest-neighbor sampling
    vec2 texelCoord = floor(vTexCoord * u_textureSize) / u_textureSize;
    texelCoord += 0.5 / u_textureSize;

    vec4 texColor = Texel(tex, texelCoord);

    // Treat black as transparent
    if (texColor.r < 0.01 && texColor.g < 0.01 && texColor.b < 0.01) {
        discard;
    }

    // Apply brightness with dithering
    if (u_ditherEnabled && vBrightness < 1.0) {
        float threshold = getBayerValue(screen_coords);
        if (vBrightness < threshold) {
            discard;
        }
    }

    // Apply fog with dithering
    if (u_fogEnabled && vFogFactor > 0.0) {
        float threshold = getBayerValue(screen_coords);
        if (u_ditherEnabled) {
            if (vFogFactor > threshold) {
                texColor.rgb = u_fogColor;
            }
        } else {
            texColor.rgb = mix(texColor.rgb, u_fogColor, vFogFactor);
        }
    }

    return texColor * color;
}
#endif
