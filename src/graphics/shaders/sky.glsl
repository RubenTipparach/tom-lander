// Sky Shader - Simple shader for skydome without fog
// Just renders texture with vertex colors, no fog effects

uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform mat4 modelMatrix;
uniform vec2 u_textureSize;

#ifdef VERTEX
varying vec2 v_texCoord;
varying vec4 v_color;

vec4 position(mat4 transformProjection, vec4 vertexPosition) {
    vec4 worldPosition = modelMatrix * vertexPosition;
    vec4 viewPosition = viewMatrix * worldPosition;
    vec4 screenPosition = projectionMatrix * viewPosition;

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

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    // Wrap UVs to 0-1 range
    vec2 wrappedUV = mod(v_texCoord, 1.0);

    // Nearest-neighbor sampling
    vec2 texelCoord = floor(wrappedUV * u_textureSize) / u_textureSize;
    texelCoord += 0.5 / u_textureSize;

    vec4 texColor = Texel(tex, texelCoord);

    // Treat black as transparent
    if (texColor.r < 0.01 && texColor.g < 0.01 && texColor.b < 0.01) {
        discard;
    }

    // Apply vertex color modulation
    texColor *= v_color;

    // No fog, no dithering - just return the color
    return texColor;
}
#endif
