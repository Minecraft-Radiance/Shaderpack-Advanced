#ifndef ALPHA_MODE_GLSL
#define ALPHA_MODE_GLSL

#include "text_mode.glsl"

const uint ALPHA_MODE_OPAQUE = 0u;
const uint ALPHA_MODE_CUTOUT = 1u;
const uint ALPHA_MODE_TRANSPARENT = 2u;
const uint ALPHA_MODE_TEXT_RGBA = 3u;
const uint ALPHA_MODE_TEXT_INTENSITY = 4u;
const uint ALPHA_MODE_CUTOUT_TENTH = 5u;
const uint ALPHA_MODE_CUTOUT_EPSILON = 6u;
const uint ALPHA_MODE_TRANSPARENT_CUTOUT = 7u;
const uint ALPHA_MODE_TRANSPARENT_CUTOUT_TENTH = 8u;
const uint ALPHA_MODE_TRANSPARENT_CUTOUT_EPSILON = 9u;

const float CUTOUT_ALPHA_THRESHOLD = 0.5;
const float TEXT_ALPHA_THRESHOLD = 0.1;

bool isTextAlphaMode(uint alphaMode) {
    return alphaMode == ALPHA_MODE_TEXT_RGBA || alphaMode == ALPHA_MODE_TEXT_INTENSITY;
}

bool isAlphaBlendedMode(uint alphaMode) {
    return alphaMode == ALPHA_MODE_TRANSPARENT || alphaMode == ALPHA_MODE_TRANSPARENT_CUTOUT ||
        alphaMode == ALPHA_MODE_TRANSPARENT_CUTOUT_TENTH || alphaMode == ALPHA_MODE_TRANSPARENT_CUTOUT_EPSILON;
}

float alphaCutoutThreshold(uint alphaMode) {
    if (alphaMode == ALPHA_MODE_CUTOUT || alphaMode == ALPHA_MODE_TRANSPARENT_CUTOUT) { return CUTOUT_ALPHA_THRESHOLD; }
    if (alphaMode == ALPHA_MODE_CUTOUT_TENTH || alphaMode == ALPHA_MODE_TRANSPARENT_CUTOUT_TENTH || isTextAlphaMode(alphaMode)) { return TEXT_ALPHA_THRESHOLD; }
    if (alphaMode == ALPHA_MODE_CUTOUT_EPSILON || alphaMode == ALPHA_MODE_TRANSPARENT_CUTOUT_EPSILON) { return 0.01; }
    return 0.0;
}

uint getSurfaceAlphaMode(uint packedData) {
    uint mode = getPostTextMode(packedData);
    if ((packedData & TEXT_MATERIAL_BIT) == 0u) { return mode; }
    if (isTextBackgroundMode(mode)) { return ALPHA_MODE_TRANSPARENT; }
    return isTextIntensityMode(mode) ? ALPHA_MODE_TEXT_INTENSITY : ALPHA_MODE_TEXT_RGBA;
}

vec4 resolveSurfaceTextureColor(vec4 textureColor, uint alphaMode) {
    return alphaMode == ALPHA_MODE_TEXT_INTENSITY ? textureColor.rrrr : textureColor;
}

float resolveSurfaceAlpha(float alpha, uint alphaMode) {
    alpha = clamp(alpha, 0.0, 1.0);

    if (alphaMode == ALPHA_MODE_OPAQUE) { return 1.0; }

    float threshold = alphaCutoutThreshold(alphaMode);
    if (threshold > 0.0) { return alpha >= threshold ? (isAlphaBlendedMode(alphaMode) ? alpha : 1.0) : 0.0; }
    return alpha;
}

#endif
