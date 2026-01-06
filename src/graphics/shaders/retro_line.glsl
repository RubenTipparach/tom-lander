// Retro Line Shader - Pixel-perfect lines with depth and fog
// For starfield and wireframe rendering

#ifdef VERTEX
varying vec4 vColor;
varying float vDepth;
varying float vFogFactor;

uniform mat4 u_mvp;
uniform float u_fogNear;
uniform float u_fogFar;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec4 clipPos = u_mvp * vec4(VertexPosition.xyz, 1.0);

    vDepth = clipPos.w;
    vFogFactor = clamp((vDepth - u_fogNear) / (u_fogFar - u_fogNear), 0.0, 1.0);
    vColor = VertexColor;

    return clipPos;
}
#endif

#ifdef PIXEL
varying vec4 vColor;
varying float vDepth;
varying float vFogFactor;

uniform vec3 u_fogColor;
uniform bool u_fogEnabled;
uniform bool u_ditherEnabled;
uniform bool u_skipDepthFog;  // For starfield (draw behind everything)

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
    vec4 finalColor = vColor;

    // Apply fog with dithering (unless skipDepthFog for starfield)
    if (u_fogEnabled && !u_skipDepthFog && vFogFactor > 0.0) {
        float threshold = getBayerValue(screen_coords);
        if (u_ditherEnabled) {
            if (vFogFactor > threshold) {
                finalColor.rgb = u_fogColor;
            }
        } else {
            finalColor.rgb = mix(finalColor.rgb, u_fogColor, vFogFactor);
        }
    }

    return finalColor;
}
#endif
