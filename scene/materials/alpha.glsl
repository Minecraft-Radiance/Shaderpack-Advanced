#ifndef ADV_SCENE_MATERIALS_ALPHA_GLSL
#define ADV_SCENE_MATERIALS_ALPHA_GLSL

#include "util/alpha_mode.glsl"

const float ADV_ALPHA_BLEND_COVERAGE_THRESHOLD = 0.05;

float alphaCoverageThreshold(uint alphaMode) {
    if (alphaMode == ALPHA_MODE_TRANSPARENT) { return ADV_ALPHA_BLEND_COVERAGE_THRESHOLD; }
    return alphaCutoutThreshold(alphaMode);
}

bool isAlphaCovered(float rawAlpha, uint alphaMode) {
    if (alphaMode == ALPHA_MODE_OPAQUE) { return true; }
    return clamp(rawAlpha, 0.0, 1.0) >= alphaCoverageThreshold(alphaMode);
}

float remapAlphaBlendedOpacity(float alpha) {
    alpha = clamp(alpha, 0.0, 1.0);
    if (alpha >= 0.99) { return alpha; }
    return clamp((alpha - 0.5) * 2.0, 0.0, 1.0);
}

float resolveSurfaceOpacity(float rawAlpha, uint alphaMode) {
    if (alphaMode == ALPHA_MODE_TRANSPARENT) { return remapAlphaBlendedOpacity(clamp(rawAlpha, 0.0, 1.0)); }
    return resolveSurfaceAlpha(rawAlpha, alphaMode);
}

vec3 alphaBlendedTransmission(vec3 tint, float opacity) {
    return clamp(tint, vec3(0.0), vec3(1.0)) * (1.0 - clamp(opacity, 0.0, 1.0));
}

#endif
