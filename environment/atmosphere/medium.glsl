#ifndef ADV_ENVIRONMENT_ATMOSPHERE_MEDIUM_GLSL
#define ADV_ENVIRONMENT_ATMOSPHERE_MEDIUM_GLSL

#include "environment/parameters.glsl"

vec2 atmosphereTransmittanceUv(float radius, float viewCosine) {
    float cosine = clamp(viewCosine, -1.0, 1.0);
    float height = clamp((radius - ADV_ATMOSPHERE_RG) / (ADV_ATMOSPHERE_RT - ADV_ATMOSPHERE_RG), 0.0, 1.0);
    return vec2(0.5 + 0.5 * sign(cosine) * sqrt(abs(cosine)), sqrt(height));
}

float atmosphereOzoneDensity(float height) {
    return max(1.0 - abs(height - 25000.0) / 15000.0, 0.0);
}

vec3 atmosphereExtinction(float height, vec3 rayleighScattering, vec3 mieScattering) {
    return rayleighScattering + mieScattering / 0.9 +
           ADV_ATMOSPHERE_OZONE_ABSORPTION * atmosphereOzoneDensity(height);
}

#endif
