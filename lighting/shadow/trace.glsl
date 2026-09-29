#ifndef ADV_LIGHTING_SHADOW_TRACE_GLSL
#define ADV_LIGHTING_SHADOW_TRACE_GLSL

#include "lighting/shadow/payload.glsl"
#include "lighting/shadow/water.glsl"

#ifndef ADV_SUN_SHADOW_PAYLOAD
#    error ADV_SUN_SHADOW_PAYLOAD must name the raygen shadow payload
#endif
#ifndef ADV_SUN_SHADOW_PAYLOAD_LOCATION
#    error ADV_SUN_SHADOW_PAYLOAD_LOCATION must name its payload location
#endif

struct SunShadowTrace {
    vec3 transmission;
    float blockerHitT;
    uint reachedLight;
    uint dynamicBlocker;
};

bool isSunShadowFinite(vec3 transmission) {
    return !any(isnan(transmission)) && !any(isinf(transmission));
}

vec3 sunShadowSanitizeTransmission(vec3 transmission) {
    if (!isSunShadowFinite(transmission)) { return vec3(0.0); }
    return clamp(transmission, vec3(0.0), vec3(ADV_SHADOW_MAX_TRANSMISSION));
}

void traceSunShadowSegment(vec3 origin,
                           vec3 direction,
                           float maximumDistance,
                           uint flags,
                           uint mask,
                           vec3 initialTransmission,
                           uint rayFlags,
                           uint missIndex) {
    initShadowPayload(ADV_SUN_SHADOW_PAYLOAD, flags);
    ADV_SUN_SHADOW_PAYLOAD.transmission = initialTransmission;
    ADV_SUN_SHADOW_PAYLOAD.blockerHitT = maximumDistance;
    if ((flags & ADV_SHADOW_FLAG_TRANSMISSION_ONLY) != 0u) { rayFlags |= gl_RayFlagsCullOpaqueEXT; }
    traceRayEXT(topLevelAS, rayFlags, mask, 0, 0, missIndex, origin, 0.0, direction, maximumDistance,
                ADV_SUN_SHADOW_PAYLOAD_LOCATION);
}

SunShadowTrace traceSunShadow(vec3 origin,
                              vec3 sampledAirDirection,
                              vec3 underwaterDirection,
                              bool isStartingUnderwater,
                              float maximumDistance,
                              uint shadowFlags,
                              uint shadowMask,
                              uint rayFlags,
                              uint missIndex) {
    SunShadowTrace shadowTrace;
    shadowTrace.transmission = vec3(0.0);
    shadowTrace.blockerHitT = maximumDistance;
    shadowTrace.reachedLight = 0u;
    shadowTrace.dynamicBlocker = 0u;

    if (maximumDistance <= 0.0) {
        shadowTrace.transmission = vec3(1.0);
        shadowTrace.blockerHitT = 0.0;
        shadowTrace.reachedLight = 1u;
        return shadowTrace;
    }

    sampledAirDirection = normalize(sampledAirDirection);
    if (!isStartingUnderwater) {
        traceSunShadowSegment(origin, sampledAirDirection, maximumDistance, shadowFlags, shadowMask & ~BOAT_WATER_MASK,
                              vec3(1.0), rayFlags, missIndex);
        shadowTrace.reachedLight = ADV_SUN_SHADOW_PAYLOAD.reachedLight;
        shadowTrace.blockerHitT = ADV_SUN_SHADOW_PAYLOAD.blockerHitT;
        shadowTrace.dynamicBlocker = hasShadowPayloadDynamicBlocker(ADV_SUN_SHADOW_PAYLOAD) ? 1u : 0u;
        shadowTrace.transmission = shadowTrace.reachedLight != 0u ?
                                       sunShadowSanitizeTransmission(ADV_SUN_SHADOW_PAYLOAD.transmission) :
                                       vec3(0.0);
        return shadowTrace;
    }

    underwaterDirection = normalize(underwaterDirection);
    uint waterProbeMask = shadowMask & (WORLD_MASK | BOAT_WATER_MASK);
    traceSunShadowSegment(origin, underwaterDirection, maximumDistance, shadowFlags | ADV_SHADOW_FLAG_WATER_PROBE,
                          waterProbeMask, vec3(1.0), rayFlags | gl_RayFlagsNoOpaqueEXT, missIndex);
    bool hasWaterSurface = hasShadowPayloadWaterSurface(ADV_SUN_SHADOW_PAYLOAD);
    float waterDistance = ADV_SUN_SHADOW_PAYLOAD.waterSurfaceHitT;
    if (!hasWaterSurface || isnan(waterDistance) || isinf(waterDistance) || waterDistance < 0.0 ||
        waterDistance > maximumDistance) {
        return shadowTrace;
    }

    vec3 waterSurfacePosition = origin + underwaterDirection * waterDistance;
    vec3 transmission =
        sunShadowSanitizeTransmission(waterSunTransmission(waterSurfacePosition, underwaterDirection, waterDistance));
    if (dot(transmission, vec3(1.0)) <= ADV_SHADOW_EARLY_OUT_SUM) {
        shadowTrace.blockerHitT = maximumDistance;
        shadowTrace.dynamicBlocker = 0u;
        return shadowTrace;
    }

    uint blockerMask = shadowMask & ~BOAT_WATER_MASK;
    float waterSegmentHitT = waterDistance;
    if (waterDistance > 1e-6) {
        traceSunShadowSegment(origin, underwaterDirection, waterDistance, shadowFlags, blockerMask, transmission,
                              rayFlags, missIndex);
        waterSegmentHitT = ADV_SUN_SHADOW_PAYLOAD.blockerHitT;
        transmission = sunShadowSanitizeTransmission(ADV_SUN_SHADOW_PAYLOAD.transmission);
        if (ADV_SUN_SHADOW_PAYLOAD.reachedLight == 0u || dot(transmission, vec3(1.0)) <= ADV_SHADOW_EARLY_OUT_SUM) {
            bool hasOpaqueBlocker = !isnan(waterSegmentHitT) && !isinf(waterSegmentHitT) && waterSegmentHitT > 1e-6 &&
                                    waterSegmentHitT < waterDistance - 1e-3;
            shadowTrace.blockerHitT = hasOpaqueBlocker ? waterSegmentHitT : maximumDistance;
            shadowTrace.dynamicBlocker =
                hasOpaqueBlocker && hasShadowPayloadDynamicBlocker(ADV_SUN_SHADOW_PAYLOAD) ? 1u : 0u;
            return shadowTrace;
        }
    }

    uint dynamicBlocker = 0u;
    if (waterDistance > 1e-6 && hasShadowPayloadDynamicBlocker(ADV_SUN_SHADOW_PAYLOAD)) { dynamicBlocker = 1u; }
    float remainingDistance = max(maximumDistance - waterDistance, 0.0);
    if (remainingDistance <= 1e-6) {
        shadowTrace.blockerHitT = maximumDistance;
        shadowTrace.dynamicBlocker = 0u;
        return shadowTrace;
    }
    traceSunShadowSegment(waterSurfacePosition, sampledAirDirection, remainingDistance, shadowFlags, blockerMask,
                          transmission, rayFlags, missIndex);
    shadowTrace.reachedLight = ADV_SUN_SHADOW_PAYLOAD.reachedLight;
    shadowTrace.blockerHitT = waterSegmentHitT + ADV_SUN_SHADOW_PAYLOAD.blockerHitT;
    shadowTrace.dynamicBlocker = dynamicBlocker | (hasShadowPayloadDynamicBlocker(ADV_SUN_SHADOW_PAYLOAD) ? 1u : 0u);
    shadowTrace.transmission =
        shadowTrace.reachedLight != 0u ? sunShadowSanitizeTransmission(ADV_SUN_SHADOW_PAYLOAD.transmission) : vec3(0.0);
    return shadowTrace;
}

#endif
