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

    // Apply vertex color RGB (brightness), ignore alpha since it's used for height
    texColor.rgb *= v_color.rgb;

    // Dithered fog effect
    if (u_fogEnabled > 0.5 && v_viewDist > u_fogNear) {
        float fogFactor = clamp((v_viewDist - u_fogNear) / (u_fogFar - u_fogNear), 0.0, 1.0);
        float threshold = getBayerValue(screen_coords);
        if (fogFactor > threshold) {
            texColor.rgb = u_fogColor;
        }
    }

    return texColor;
}
#endif
