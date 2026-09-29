#ifndef ADV_LIGHTING_CACHE_QUERY_GLSL
#define ADV_LIGHTING_CACHE_QUERY_GLSL

#ifndef USE_SHARC
#    define USE_SHARC 0
#endif
#ifndef SHARC_QUERY
#    define SHARC_QUERY 0
#endif
#include "scene/hit.glsl"
#include "lighting/cache/sharc.glsl"

const float ADV_CACHE_MIN_CONFIDENCE = 0.5;

struct RadianceCacheHit {
    vec3 position;
    vec3 outwardNormal;
    float distance;
    float surfaceFootprint;
    uint category;
    uint instanceMask;
};

struct RadianceCacheResult {
    vec3 radiance;
    float confidence;
    bool isValid;
};

RadianceCacheResult invalidRadianceCacheResult() {
    RadianceCacheResult query;
    query.radiance = vec3(0.0);
    query.confidence = 0.0;
    query.isValid = false;
    return query;
}

bool isCacheFinite(vec3 vector) {
    return !any(isnan(vector)) && !any(isinf(vector));
}

vec3 normalizeCacheDirection(vec3 direction) {
    float lengthSquared = dot(direction, direction);
    if (!isCacheFinite(direction) || isnan(lengthSquared) || isinf(lengthSquared) || lengthSquared <= 1e-12) {
        return vec3(0.0, 1.0, 0.0);
    }
    return direction * inversesqrt(lengthSquared);
}

bool isCacheCategorySupported(uint category) {
    return category == ADV_HIT_CATEGORY_DEFAULT;
}

bool isCacheInstanceSupported(uint instanceMask) {
    return (instanceMask & WORLD_MASK) != 0u && (instanceMask & (PLAYER_MASK | HAND_MASK | WEATHER_MASK |
                                                                 PARTICLE_MASK | CLOUD_MASK | BOAT_WATER_MASK)) == 0u;
}

bool canQueryRadianceCache(RadianceCacheHit hit, float thresholdDistance) {
    if (!isCacheCategorySupported(hit.category) || !isCacheFinite(hit.position) || !isCacheFinite(hit.outwardNormal) ||
        isnan(hit.distance) || isinf(hit.distance) || hit.distance <= max(thresholdDistance, 0.0)) {
        return false;
    }

    return isCacheInstanceSupported(hit.instanceMask);
}

bool isCacheFootprintSufficient(RadianceCacheHit hit) {
#if USE_SHARC && SHARC_QUERY
    return isSharcCellSafeForQuery(hit.position + vec3(worldUBO.cameraPos.xyz), hit.distance,
                                   max(hit.surfaceFootprint, 0.0));
#else
    return false;
#endif
}

float radianceCacheConfidence(RadianceCacheResult query) {
    return query.isValid ? clamp(query.confidence, 0.0, 1.0) : 0.0;
}

RadianceCacheResult queryRadianceCache(RadianceCacheHit hit, bool isFrontSide) {
    RadianceCacheResult query = invalidRadianceCacheResult();
    if (!isCacheCategorySupported(hit.category) || !isCacheInstanceSupported(hit.instanceMask) ||
        !isCacheFinite(hit.position) || !isCacheFinite(hit.outwardNormal) || isnan(hit.distance) ||
        isinf(hit.distance) || hit.distance <= 0.0) {
        return query;
    }

#if USE_SHARC && SHARC_QUERY
    vec3 queryNormal = normalizeCacheDirection(isFrontSide ? hit.outwardNormal : -hit.outwardNormal);
    vec3 cachedRadiance = vec3(0.0);
    bool isValid = sharcQueryRadiance(hit.position + vec3(worldUBO.cameraPos.xyz), queryNormal, hit.distance,
                                      max(hit.surfaceFootprint, 0.0), cachedRadiance);
    if (isValid && isCacheFinite(cachedRadiance)) {
        query.radiance = max(cachedRadiance, vec3(0.0));
        query.confidence = 1.0;
        query.isValid = true;
    }
#endif
    return query;
}

#endif
