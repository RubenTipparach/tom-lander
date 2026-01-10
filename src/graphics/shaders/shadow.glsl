// Shadow Shader - Renders projected ground shadows
// Uses multiplicative blending to darken the surface underneath
// This preserves the surface color while making it darker (palette-friendly)

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform mat4 modelMatrix;
uniform float u_shadowDarkness;   // How dark the shadow is (0 = black, 1 = no change)

// Fog uniforms (shadows fade with distance too)
uniform float u_fogEnabled;
uniform float u_fogNear;
uniform float u_fogFar;

#ifdef VERTEX
varying float v_viewDist;

vec4 position(mat4 transformProjection, vec4 vertexPosition) {
    // Transform through the pipeline
    vec4 worldPosition = modelMatrix * vertexPosition;
    vec4 viewPosition = viewMatrix * worldPosition;
    vec4 screenPosition = projectionMatrix * viewPosition;

    // Pass view distance for fog-based shadow fade
    v_viewDist = length(viewPosition.xyz);

    // Flip Y for canvas rendering (LOVE's canvas has inverted Y)
    screenPosition.y *= -1.0;

    return screenPosition;
}
#endif

#ifdef PIXEL
varying float v_viewDist;

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    // Calculate shadow darkness (fade toward 1.0 as we approach fog)
    float darkness = u_shadowDarkness;

    if (u_fogEnabled > 0.5 && v_viewDist > u_fogNear) {
        // Fade shadow out as it enters fog zone (lerp toward 1.0 = no darkening)
        float fogFactor = clamp((v_viewDist - u_fogNear) / (u_fogFar - u_fogNear), 0.0, 1.0);
        darkness = mix(darkness, 1.0, fogFactor);
    }

    // Output a darkening color for multiplicative blending
    // When blended with multiply mode, this darkens the underlying surface
    // darkness = 0.0 would be black, 1.0 = no change
    return vec4(darkness, darkness, darkness, 1.0);
}
#endif
