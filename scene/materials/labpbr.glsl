#ifndef ADV_SCENE_MATERIALS_LABPBR_GLSL
#define ADV_SCENE_MATERIALS_LABPBR_GLSL

#include "util/color_space.glsl"
#include "util/alpha_mode.glsl"
#include "util/labpbr.glsl"
#include "util/sampling_helpers.glsl"

float resolveLabPbrAlbedoAlpha(sampler2D tex, vec2 uv, vec2 atlasUvMin, vec2 atlasUvMax, float filteredAlpha) {
    ivec2 size = textureSize(tex, 0);
    if (size.x <= 0 || size.y <= 0) { return filteredAlpha; }

    vec2 clampedUv = clampAtlasTextureUv(uv, atlasUvMin, atlasUvMax, size);
    ivec2 texel = clamp(ivec2(floor(clampedUv * vec2(size))), ivec2(0), size - ivec2(1));
    float texelAlpha = texelFetch(tex, texel, 0).a;
    return texelAlpha >= 1.0 - (0.5 / 255.0) ? 1.0 : filteredAlpha;
}

vec4 sampleLabPbrAlbedo(sampler2D tex, vec2 uv, vec2 atlasUvMin, vec2 atlasUvMax, float lod, uint alphaMode) {
    vec4 albedo = sampleAtlasTexture(tex, uv, atlasUvMin, atlasUvMax, lod, false);
    albedo.a = resolveLabPbrAlbedoAlpha(tex, uv, atlasUvMin, atlasUvMax, albedo.a);
    return resolveSurfaceTextureColor(albedo, alphaMode);
}

vec4 sampleLabPbrSpecular(sampler2D tex, vec2 uv, vec2 atlasUvMin, vec2 atlasUvMax, float lod, uint samplingMode) {
    return samplePBRSpecularTexture(tex, uv, atlasUvMin, atlasUvMax, lod, samplingMode);
}

#endif
