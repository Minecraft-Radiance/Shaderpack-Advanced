#ifndef MCVR_NRD_RESOLVE_MATERIAL_GLSL
#define MCVR_NRD_RESOLVE_MATERIAL_GLSL

const float ILLUMINATION_HISTORY_FLAG = 8.0;

bool usesDiffuseIlluminationHistory(vec4 packedNormalRoughness, vec4 albedoMetallic, float transmissionCarrier) {
    return round(packedNormalRoughness.a * 3.0) == 0.0 &&
           abs(packedNormalRoughness.z * 2.0 - 1.0) >= 0.12 &&
           albedoMetallic.a < 0.5 && transmissionCarrier <= 0.5;
}

#endif
