#ifndef ADV_LIGHTING_SHADOW_PAYLOAD_GLSL
#define ADV_LIGHTING_SHADOW_PAYLOAD_GLSL

const uint ADV_SHADOW_FLAG_TRANSMISSION_ONLY = 1u << 0u;
const uint ADV_SHADOW_FLAG_WATER_PROBE = 1u << 1u;
const uint ADV_SHADOW_FLAG_WATER_SURFACE_FOUND = 1u << 2u;
const uint ADV_SHADOW_FLAG_DYNAMIC_BLOCKER = 1u << 3u;
const uint ADV_SHADOW_FLAG_DISABLE_PARALLAX = 1u << 7u;

const float ADV_SHADOW_EARLY_OUT_SUM = 0.01;
const float ADV_SHADOW_MAX_TRANSMISSION = 8.0;

struct ShadowPayload {
    vec3 transmission;
    float blockerHitT;
    float waterSurfaceHitT;
    uint flags;
    uint reachedLight;
};

void initShadowPayload(inout ShadowPayload payload, uint flags) {
    payload.transmission = vec3(1.0);
    payload.blockerHitT = 65504.0;
    payload.waterSurfaceHitT = 65504.0;
    payload.flags = flags;
    payload.reachedLight = 0u;
}

bool isShadowPayloadTransmissionOnly(ShadowPayload payload) {
    return (payload.flags & ADV_SHADOW_FLAG_TRANSMISSION_ONLY) != 0u;
}

bool isShadowPayloadWaterProbe(ShadowPayload payload) {
    return (payload.flags & ADV_SHADOW_FLAG_WATER_PROBE) != 0u;
}

bool hasShadowPayloadWaterSurface(ShadowPayload payload) {
    return (payload.flags & ADV_SHADOW_FLAG_WATER_SURFACE_FOUND) != 0u;
}

bool hasShadowPayloadDynamicBlocker(ShadowPayload payload) {
    return (payload.flags & ADV_SHADOW_FLAG_DYNAMIC_BLOCKER) != 0u;
}

bool shouldShadowPayloadDisableParallax(ShadowPayload payload) {
    return (payload.flags & ADV_SHADOW_FLAG_DISABLE_PARALLAX) != 0u;
}

#endif
