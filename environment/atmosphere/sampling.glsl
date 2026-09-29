#ifndef ADV_ENVIRONMENT_ATMOSPHERE_SAMPLING_GLSL
#define ADV_ENVIRONMENT_ATMOSPHERE_SAMPLING_GLSL

#include "core/bindings.glsl"
#include "environment/atmosphere/medium.glsl"

layout(set = 5, binding = ADV_ATMOSPHERE_TRANSMITTANCE_BINDING) uniform sampler2D atmosphereTransmittanceTexture;

vec3 sampleAtmosphereLut(float radius, float viewCosine) {
    vec2 halfTexel = 0.5 / vec2(textureSize(atmosphereTransmittanceTexture, 0));
    vec2 uv = clamp(atmosphereTransmittanceUv(radius, viewCosine), halfTexel, 1.0 - halfTexel);
    return textureLod(atmosphereTransmittanceTexture, uv, 0.0).rgb;
}

#endif
