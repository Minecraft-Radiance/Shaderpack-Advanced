#ifndef COLOR_SPACE_GLSL
#define COLOR_SPACE_GLSL

float roundToFloat16(float value) {
    value = isnan(value) || isinf(value) ? 0.0 : clamp(value, -65504.0, 65504.0);
    uint bits = floatBitsToUint(value), sign = (bits >> 16) & 0x8000u;
    int exponent = int((bits >> 23) & 255u) - 112;
    uint mantissa = bits & 0x7fffffu;
    if (exponent <= 0) {
        if (exponent < -10) return unpackHalf2x16(sign).x;
        mantissa = (mantissa | 0x800000u) >> uint(1 - exponent);
        if ((mantissa & 0x1000u) != 0u) mantissa += 0x2000u;
        return unpackHalf2x16(sign | (mantissa >> 13)).x;
    }
    if ((mantissa & 0x1000u) != 0u) {
        mantissa += 0x2000u;
        if ((mantissa & 0x800000u) != 0u) {
            mantissa = 0u;
            ++exponent;
        }
    }
    return unpackHalf2x16(sign | (uint(exponent) << 10) | (mantissa >> 13)).x;
}

vec3 roundToFloat16(vec3 value) {
    return vec3(roundToFloat16(value.x), roundToFloat16(value.y), roundToFloat16(value.z));
}

vec3 srgbToLinear(vec3 srgbColor) {
    vec3 low = srgbColor / 12.92;
    vec3 high = pow((srgbColor + 0.055) / 1.055, vec3(2.4));
    bvec3 useLow = lessThanEqual(srgbColor, vec3(0.04045));
    return mix(high, low, useLow);
}

vec4 srgbToLinear(vec4 srgbColor) {
    return vec4(srgbToLinear(srgbColor.rgb), srgbColor.a);
}

vec4 applySrgbToLinear(vec4 sampledColor, bool isSRGB) {
    if (isSRGB) { return srgbToLinear(sampledColor); }
    return sampledColor;
}

vec4 sampleTexture(sampler2D tex, vec2 uv, bool isSRGB) {
    return applySrgbToLinear(texture(tex, uv), isSRGB);
}

vec4 sampleTexture(sampler2D tex, vec2 uv, float lod, bool isSRGB) {
    return applySrgbToLinear(textureLod(tex, uv, lod), isSRGB);
}

vec4 sampleTexture(sampler2D tex, ivec2 coord, int lod, bool isSRGB) {
    return applySrgbToLinear(texelFetch(tex, coord, lod), isSRGB);
}

vec2 clampAtlasTextureUv(vec2 uv, vec2 atlasUvMin, vec2 atlasUvMax, ivec2 size) {
    vec2 minUv = min(atlasUvMin, atlasUvMax);
    vec2 maxUv = max(atlasUvMin, atlasUvMax);
    vec2 halfTexel = 0.5 / vec2(max(size, ivec2(1)));
    minUv += halfTexel;
    maxUv -= halfTexel;
    maxUv = max(maxUv, minUv);
    return clamp(uv, minUv, maxUv);
}

vec4 sampleAtlasTexture(sampler2D tex, vec2 uv, vec2 atlasUvMin, vec2 atlasUvMax, float lod, bool isSRGB) {
    int levelCount = max(textureQueryLevels(tex), 1);
    ivec2 baseSize = textureSize(tex, 0);
    if (baseSize.x <= 0 || baseSize.y <= 0) { return vec4(0.0); }

    vec2 minUv = min(atlasUvMin, atlasUvMax);
    vec2 maxUv = max(atlasUvMin, atlasUvMax);
    vec2 atlasPixels = max((maxUv - minUv) * vec2(baseSize), vec2(1.0));
    float maxSafeLod = floor(log2(max(min(atlasPixels.x, atlasPixels.y), 1.0)));
    float clampedLod = clamp(max(lod, 0.0), 0.0, min(float(levelCount - 1), maxSafeLod));
    return applySrgbToLinear(textureLod(tex, clampAtlasTextureUv(uv, minUv, maxUv, baseSize), clampedLod), isSRGB);
}

vec4 sampleTexture(samplerCube tex, vec3 dir, bool isSRGB) {
    return applySrgbToLinear(texture(tex, dir), isSRGB);
}

#endif
