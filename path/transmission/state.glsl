#ifndef ADV_PATH_TRANSMISSION_STATE_GLSL
#define ADV_PATH_TRANSMISSION_STATE_GLSL

#include "core/bindings.glsl"
#include "path/budget.glsl"
#include "scene/materials/media.glsl"
#include "scene/hit.glsl"
#include "path/primary/hit_buffer.glsl"

#ifdef ADV_TRANSMISSION_STATE_WRITE
#    define ADV_TRANSMISSION_STATE_ACCESS writeonly
#else
#    define ADV_TRANSMISSION_STATE_ACCESS readonly
#endif

layout(set = 5,
       binding = ADV_TRANSMISSION_IDENTITY_BINDING,
       rgba32ui) ADV_TRANSMISSION_STATE_ACCESS uniform uimage2D transmissionIdentityImage;
layout(set = 5,
       binding = ADV_TRANSMISSION_GEOMETRY_BINDING,
       rgba32ui) ADV_TRANSMISSION_STATE_ACCESS uniform uimage2D transmissionGeometryImage;
layout(set = 5,
       binding = ADV_TRANSMISSION_TRANSPORT_BINDING,
       rg32ui) ADV_TRANSMISSION_STATE_ACCESS uniform uimage2D transmissionTransportImage;

#undef ADV_TRANSMISSION_STATE_ACCESS

const uint ADV_TRANSMISSION_STATE_CATEGORY_MASK = 0x07u;
const uint ADV_TRANSMISSION_STATE_FRONT_FACE_BIT = 1u << 3u;
const uint ADV_TRANSMISSION_STATE_INSTANCE_MASK_SHIFT = 4u;
const uint ADV_TRANSMISSION_STATE_INSTANCE_MASK_MASK = 0xffu;
const uint ADV_TRANSMISSION_STATE_MEDIUM_SHIFT = 12u;
const uint ADV_TRANSMISSION_STATE_MEDIUM_MASK = 0x0fu;
const uint ADV_TRANSMISSION_STATE_BUDGET_SHIFT = 16u;
const uint ADV_TRANSMISSION_STATE_BUDGET_MASK = 0x0fu;
const uint ADV_TRANSMISSION_STATE_VALID_BIT = 1u << 31u;
const float ADV_TRANSMISSION_STATE_FP16_MAX = 65504.0;
const float ADV_TRANSMISSION_STATE_UNORM10_MAX = 1023.0;

struct TransmissionState {
    HitPayload hit;
    vec3 rayDirection;
    vec3 transmission;
    float coneWidthAtHit;
    float coneSpread;
    float totalDistance;
    float distanceThroughAir;
    uint currentMedium;
    uint rayBudgetUsed;
    bool isValid;
};

TransmissionState invalidTransmissionState() {
    TransmissionState state;
    resetHit(state.hit, 0.0, 0.0, ADV_TRACE_ROLE_PRIMARY);
    state.rayDirection = vec3(0.0, 0.0, -1.0);
    state.transmission = vec3(0.0);
    state.coneWidthAtHit = 0.0;
    state.coneSpread = 0.0;
    state.totalDistance = 0.0;
    state.distanceThroughAir = 0.0;
    state.currentMedium = ADV_MEDIUM_AIR;
    state.rayBudgetUsed = 0u;
    state.isValid = false;
    return state;
}

bool isRefractionTerminalFinite(float value) {
    return !isnan(value) && !isinf(value);
}

bool isRefractionTerminalFinite(vec3 value) {
    return !any(isnan(value)) && !any(isinf(value));
}

uint packRefractionTerminalHeader(HitPayload hit, uint currentMedium, uint rayBudgetUsed) {
    return (hit.category & ADV_TRANSMISSION_STATE_CATEGORY_MASK) |
           ((hit.isFrontFace != 0u) ? ADV_TRANSMISSION_STATE_FRONT_FACE_BIT : 0u) |
           ((hit.instanceMask & ADV_TRANSMISSION_STATE_INSTANCE_MASK_MASK)
            << ADV_TRANSMISSION_STATE_INSTANCE_MASK_SHIFT) |
           ((currentMedium & ADV_TRANSMISSION_STATE_MEDIUM_MASK) << ADV_TRANSMISSION_STATE_MEDIUM_SHIFT) |
           ((rayBudgetUsed & ADV_TRANSMISSION_STATE_BUDGET_MASK) << ADV_TRANSMISSION_STATE_BUDGET_SHIFT) |
           ADV_TRANSMISSION_STATE_VALID_BIT;
}

uint packRefractionTerminalTransmission(vec3 transmission) {
    uvec3 quantized = uvec3(round(clamp(transmission, vec3(0.0), vec3(1.0)) * ADV_TRANSMISSION_STATE_UNORM10_MAX));
    return quantized.x | (quantized.y << 10u) | (quantized.z << 20u);
}

vec3 unpackRefractionTerminalTransmission(uint packed) {
    uvec3 quantized = uvec3(packed & 0x3ffu, (packed >> 10u) & 0x3ffu, (packed >> 20u) & 0x3ffu);
    return vec3(quantized) / ADV_TRANSMISSION_STATE_UNORM10_MAX;
}

#ifdef ADV_TRANSMISSION_STATE_WRITE
void clearTransmissionState(ivec2 packedPixel) {
    imageStore(transmissionIdentityImage, packedPixel, uvec4(0u));
}

void storeTransmissionState(ivec2 packedPixel,
                            HitPayload hit,
                            vec3 rayDirection,
                            float coneWidthAtHit,
                            float coneSpread,
                            vec3 transmission,
                            float totalDistance,
                            float distanceThroughAir,
                            uint currentMedium,
                            uint rayBudgetUsed) {
    if (!isHitValid(hit) || !isRefractionTerminalFinite(rayDirection) || !isRefractionTerminalFinite(transmission) ||
        !isRefractionTerminalFinite(coneWidthAtHit) || !isRefractionTerminalFinite(coneSpread) ||
        !isRefractionTerminalFinite(totalDistance) || !isRefractionTerminalFinite(distanceThroughAir)) {
        clearTransmissionState(packedPixel);
        return;
    }

    vec3 packedTransmission = clamp(transmission, vec3(0.0), vec3(1.0));
    vec2 packedCone = clamp(vec2(coneWidthAtHit, coneSpread), vec2(0.0), vec2(ADV_TRANSMISSION_STATE_FP16_MAX));
    vec2 packedDistances =
        clamp(vec2(totalDistance, distanceThroughAir), vec2(0.0), vec2(ADV_TRANSMISSION_STATE_FP16_MAX));
    uvec4 identity = uvec4(hit.instanceIndex, hit.geometryBufferIndex, hit.primitiveId,
                           packRefractionTerminalHeader(hit, currentMedium, rayBudgetUsed));
    uvec4 geometry = uvec4(packPrimaryTemporalNormal(rayDirection), packHalf2x16(packedCone),
                           packUnorm2x16(clamp(hit.barycentrics, vec2(0.0), vec2(1.0))), floatBitsToUint(hit.hitT));
    uvec2 transport = uvec2(packRefractionTerminalTransmission(packedTransmission), packHalf2x16(packedDistances));
    imageStore(transmissionGeometryImage, packedPixel, geometry);
    imageStore(transmissionTransportImage, packedPixel, uvec4(transport, 0u, 0u));
    imageStore(transmissionIdentityImage, packedPixel, identity);
}
#else
TransmissionState loadTransmissionState(ivec2 packedPixel) {
    TransmissionState state = invalidTransmissionState();
    uvec4 identity = imageLoad(transmissionIdentityImage, packedPixel);
    uint header = identity.w;
    if ((header & ADV_TRANSMISSION_STATE_VALID_BIT) == 0u) { return state; }

    uvec4 geometry = imageLoad(transmissionGeometryImage, packedPixel);
    uvec2 transport = imageLoad(transmissionTransportImage, packedPixel).xy;
    vec2 cone = unpackHalf2x16(geometry.y);
    vec2 distances = unpackHalf2x16(transport.y);

    resetHit(state.hit, cone.x, 0.0, ADV_TRACE_ROLE_PRIMARY);
    state.hit.hitKind = ADV_HIT_KIND_TRIANGLE;
    state.hit.instanceIndex = identity.x;
    state.hit.geometryBufferIndex = identity.y;
    state.hit.primitiveId = identity.z;
    state.hit.category = header & ADV_TRANSMISSION_STATE_CATEGORY_MASK;
    state.hit.hitT = uintBitsToFloat(geometry.w);
    state.hit.barycentrics = unpackUnorm2x16(geometry.z);
    state.hit.isFrontFace = (header & ADV_TRANSMISSION_STATE_FRONT_FACE_BIT) != 0u ? 1u : 0u;
    state.hit.instanceMask =
        (header >> ADV_TRANSMISSION_STATE_INSTANCE_MASK_SHIFT) & ADV_TRANSMISSION_STATE_INSTANCE_MASK_MASK;
    state.rayDirection = unpackPrimaryTemporalNormal(geometry.x);
    state.transmission = unpackRefractionTerminalTransmission(transport.x);
    state.coneWidthAtHit = cone.x;
    state.coneSpread = cone.y;
    state.totalDistance = distances.x;
    state.distanceThroughAir = distances.y;
    state.currentMedium = (header >> ADV_TRANSMISSION_STATE_MEDIUM_SHIFT) & ADV_TRANSMISSION_STATE_MEDIUM_MASK;
    state.rayBudgetUsed = (header >> ADV_TRANSMISSION_STATE_BUDGET_SHIFT) & ADV_TRANSMISSION_STATE_BUDGET_MASK;
    state.isValid =
        isHitValid(state.hit) && isRefractionTerminalFinite(state.rayDirection) &&
        dot(state.rayDirection, state.rayDirection) > 1e-8 && isRefractionTerminalFinite(state.transmission) &&
        isRefractionTerminalFinite(state.coneWidthAtHit) && isRefractionTerminalFinite(state.coneSpread) &&
        isRefractionTerminalFinite(state.totalDistance) && isRefractionTerminalFinite(state.distanceThroughAir) &&
        state.currentMedium < ADV_MEDIUM_COUNT && state.rayBudgetUsed <= ADV_PATH_RAY_BUDGET;
    return state;
}
#endif

#endif
