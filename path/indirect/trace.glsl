#ifndef ADV_PATH_INDIRECT_TRACE_GLSL
#define ADV_PATH_INDIRECT_TRACE_GLSL

#ifndef ADV_INDIRECT_SURFACE_MISS_INDEX
#    error "ADV_INDIRECT_SURFACE_MISS_INDEX must be defined"
#endif
#ifndef ADV_INDIRECT_SHADOW_MISS_INDEX
#    error "ADV_INDIRECT_SHADOW_MISS_INDEX must be defined"
#endif
#ifndef ADV_INDIRECT_HAS_TRANSMISSION_PAYLOAD
#    define ADV_INDIRECT_HAS_TRANSMISSION_PAYLOAD 0
#endif
#ifndef ADV_INDIRECT_APPLY_MEDIUM_TRANSMITTANCE
#    define ADV_INDIRECT_APPLY_MEDIUM_TRANSMITTANCE 1
#endif

#include "path/indirect/scattering.glsl"

struct IndirectTraceResult {
    vec3 radiance;
    uint rayBudgetUsed;
    bool isResolved;
    bool usedHighDetail;
};

const float ADV_INDIRECT_RAY_SPREAD_MAX = 0.1;
const float ADV_INDIRECT_MIN_TRACE_DISTANCE = 1e-4;
const uint ADV_SPECULAR_OPAQUE_INDIRECT_RAY_LIMIT = 1u;
const uint ADV_SPECULAR_INTERFACE_INDIRECT_RAY_LIMIT = 2u;
const uint ADV_SPECULAR_COMPLEX_INTERFACE_INDIRECT_RAY_LIMIT = 3u;

IndirectTraceResult emptyIndirectTraceResult(uint rayBudgetUsed) {
    IndirectTraceResult result;
    result.radiance = vec3(0.0);
    result.rayBudgetUsed = rayBudgetUsed;
    result.isResolved = false;
    result.usedHighDetail = false;
    return result;
}

vec3 indirectPayloadTransmission(HitPayload hit) {
#if ADV_INDIRECT_HAS_TRANSMISSION_PAYLOAD != 0
    vec3 transmission = vec3(hit.transmission);
    return isFinite(transmission) ? clamp(transmission, vec3(0.0), vec3(1.0)) : vec3(0.0);
#else
    return vec3(1.0);
#endif
}

vec3 indirectOffsetOrigin(vec3 position, vec3 normal, vec3 direction) {
    float side = dot(direction, normal) >= 0.0 ? 1.0 : -1.0;
    return position + normal * (side * 0.0002);
}

vec3 indirectEnvironment(vec3 origin, vec3 direction, bool captureClouds) {
    vec3 environment = calculateIndirectSkyRadiance(direction);
    if (captureClouds) { environment = shadeIndirectCloud(origin, direction, environment); }
    return sanitizeRadiance(environment);
}

vec3 evaluateIndirectDirectSun(HitGeometry geometry,
                               SurfaceMaterial material,
                               vec3 incomingDirection,
                               uint pathMedium,
                               float maximumDistance,
                               bool cullBackFaces) {
    vec3 surfaceDiffuseAlbedo = diffuseAlbedo(material.albedo, material.metallic);
    if (max(surfaceDiffuseAlbedo.r, max(surfaceDiffuseAlbedo.g, surfaceDiffuseAlbedo.b)) <= 0.0) { return vec3(0.0); }
    vec3 lightDirection;
    vec3 lightRadiance;
    float lightScale;
    getCelestialIndirectLight(lightDirection, lightRadiance, lightScale);
    if (worldUBO.skyType != 1u || lightScale <= 1e-6 || maximumDistance <= ADV_INDIRECT_MIN_TRACE_DISTANCE) {
        return vec3(0.0);
    }

    bool isStartingUnderwater = pathMedium == ADV_MEDIUM_WATER;
    vec3 surfaceLightDirection = isStartingUnderwater ? underwaterDirectionToLight(lightDirection) : lightDirection;
    if (dot(geometry.geometryNormal, surfaceLightDirection) <= 1e-6) { return vec3(0.0); }

    uint shadowMask = WORLD_MASK | CLOUD_MASK | BOAT_WATER_MASK | PLAYER_MASK | FISHING_BOBBER_MASK;
    vec3 absolutePosition = geometry.position + vec3(worldUBO.cameraPos.xyz);
    vec3 shadowOrigin = indirectOffsetOrigin(geometry.position, geometry.geometryNormal, surfaceLightDirection);
    uint sunRayFlags = uint(ADV_RAY_FLAGS);
    if (cullBackFaces && !material.isCloud) { sunRayFlags |= gl_RayFlagsCullBackFacingTrianglesEXT; }
    vec3 viewDirection = brdfNormalize(-incomingDirection, material.shadingNormal);
    DirectBrdf brdf = evaluateDirectBrdf(material.shadingNormal, surfaceLightDirection, viewDirection, material.f0,
                                         material.roughness);
    vec3 unshadowedRadiance = brdf.diffuse * surfaceDiffuseAlbedo * lightRadiance;
    SunShadowTrace shadow =
        traceSunShadow(shadowOrigin, lightDirection, surfaceLightDirection, isStartingUnderwater, maximumDistance,
                       ADV_SHADOW_FLAG_DISABLE_PARALLAX, shadowMask, sunRayFlags, uint(ADV_INDIRECT_SHADOW_MISS_INDEX));
    vec3 transmission = shadow.reachedLight != 0u ? sunShadowSanitizeTransmission(shadow.transmission) : vec3(0.0);
    transmission *= cloudLightVisibility(absolutePosition, lightDirection, max(ADV_CLOUD_LIGHT_STEPS, 1), 0.175);
    if (!isFinite(transmission) || luminance(transmission) <= 0.0) { return vec3(0.0); }

    return sanitizeRadiance(unshadowedRadiance * transmission);
}

vec3 evaluateIndirectLocalRadiance(HitGeometry geometry,
                                   SurfaceMaterial material,
                                   vec3 incomingDirection,
                                   float coneWidthAtHit,
                                   uint pathMedium,
                                   float maximumDistance,
                                   bool cullBackFaces) {
    vec3 emission = max(material.emission, vec3(0.0));
    if (max(emission.r, max(emission.g, emission.b)) > 0.0) {
        float projectedCosine = clamp(abs(dot(incomingDirection, geometry.outwardNormal)), 0.0, 1.0);
        float projectedEmitterArea = geometry.triangleArea * projectedCosine;
        float coneArea = ADV_BRDF_PI * max(coneWidthAtHit * coneWidthAtHit, 1e-12);
        float coverage = clamp(projectedEmitterArea / coneArea, 0.0, 1.0);
        emission *= coverage;
    }
    vec3 radiance = emission * max(float(ADV_INDIRECT_LIGHT_STRENGTH), 0.0);
    radiance +=
        evaluateIndirectDirectSun(geometry, material, incomingDirection, pathMedium, maximumDistance, cullBackFaces);
    return sanitizeRadiance(radiance);
}

HitPayload traceIndirectSegment(vec3 origin,
                                vec3 direction,
                                float coneWidth,
                                float coneSpread,
                                float maximumDistance,
                                uint traceMask,
                                uint rayFlags,
                                uint traceRole) {
    resetHit(hitPayload, coneWidth, coneSpread, traceRole);
    if (!isFinite(maximumDistance) || maximumDistance <= ADV_INDIRECT_MIN_TRACE_DISTANCE) { return hitPayload; }
    traceRayEXT(topLevelAS, rayFlags, traceMask, 1, 1, uint(ADV_INDIRECT_SURFACE_MISS_INDEX), origin, 0.0, direction,
                maximumDistance, 0);
    return hitPayload;
}

bool queryIndirectCache(RadianceCacheHit cacheHit, bool isFrontFace, out RadianceCacheResult cache) {
    cache = invalidRadianceCacheResult();
    cache = queryRadianceCache(cacheHit, isFrontFace);
    return radianceCacheConfidence(cache) >= ADV_CACHE_MIN_CONFIDENCE;
}

IndirectTraceResult traceIndirectFromHit(HitPayload firstHit,
                                         vec3 firstRayOrigin,
                                         vec3 incomingDirection,
                                         uint currentMedium,
                                         float firstConeWidthAtHit,
                                         float firstConeSpread,
                                         float firstSegmentRoughness,
                                         bool isFirstSegmentWeighted,
                                         vec3 initialThroughput,
                                         uint rayBudgetUsed,
                                         uint maximumIndirectRayCount,
                                         bool useAdaptiveSpecularRayLimit,
                                         float initialRemainingDistance,
                                         uint seed,
                                         uint traceMask,
                                         uint rayFlags,
                                         uint traceRole,
                                         bool isAfterTransparent,
                                         bool captureClouds) {
    IndirectTraceResult result = emptyIndirectTraceResult(rayBudgetUsed);
    HitPayload hit = firstHit;
    vec3 rayOrigin = firstRayOrigin;
    vec3 throughput = initialThroughput;
    float coneWidthAtHit = max(firstConeWidthAtHit, 0.0);
    float coneSpread = max(firstConeSpread, 0.0);
    float segmentRoughness = clamp(firstSegmentRoughness, 0.0, 1.0);
    float remainingDistance = isFinite(initialRemainingDistance) ? max(initialRemainingDistance, 0.0) : 0.0;
    uint indirectRayCount = 0u;
    uint indirectRayLimit = maximumIndirectRayCount;
    uint glassExteriorMedium = currentMedium == ADV_MEDIUM_GLASS ? ADV_MEDIUM_AIR : currentMedium;
    bool hasPassedTransparent = isAfterTransparent;

    for (uint depth = 0u; depth <= ADV_PATH_RAY_BUDGET; ++depth) {
        if (!isHitValid(hit) || !isFinite(throughput)) { break; }

        HitGeometry geometry;
        if (!decodeHitGeometry(hit, rayOrigin, incomingDirection, geometry)) { break; }
#if ADV_INDIRECT_APPLY_MEDIUM_TRANSMITTANCE != 0
        if (depth != 0u || !isFirstSegmentWeighted) {
            throughput *= segmentTransmittance(currentMedium, geometry.rayDistance);
        }
#endif
        throughput *= indirectPayloadTransmission(hit);
        if (!isFinite(throughput) || max(throughput.r, max(throughput.g, throughput.b)) <= 1e-6) { break; }

        bool isNonReflective = geometry.category == ADV_HIT_CATEGORY_NO_REFLECT;
        bool isPortal =
            geometry.category == ADV_HIT_CATEGORY_END_PORTAL || geometry.category == ADV_HIT_CATEGORY_END_GATEWAY;
        if (isNonReflective) {
            result.usedHighDetail = true;
            result.isResolved = true;
            break;
        }
        if (isPortal) {
            int iterations = geometry.category == ADV_HIT_CATEGORY_END_GATEWAY ? 15 : 16;
            result.radiance += throughput * computeEndPortalRadiance(geometry.position, iterations);
            result.usedHighDetail = true;
            result.isResolved = true;
            break;
        }

        float surfaceFootprint = cacheFootprint(coneWidthAtHit, geometry, incomingDirection, segmentRoughness);
        RadianceCacheHit cacheHit = makeRadianceCacheHit(geometry, surfaceFootprint);
        bool isCacheableHit = canQueryRadianceCache(cacheHit, 0.0);
        bool isSharcFootprintSufficient = isCacheableHit && isCacheFootprintSufficient(cacheHit);
        if (isCacheableHit) {
            RadianceCacheResult cache;
            if (isSharcFootprintSufficient && queryIndirectCache(cacheHit, geometry.isFrontFace, cache)) {
                result.radiance += throughput * cache.radiance;
                result.isResolved = true;
                break;
            }
        }

        SurfaceMaterial material;
        if (!decodeSurfaceMaterial(hit, geometry, incomingDirection, coneWidthAtHit, material)) { break; }
        if (useAdaptiveSpecularRayLimit && isIndirectInterfaceMaterial(material)) {
            uint interfaceRayLimit = indirectRayCount >= ADV_SPECULAR_INTERFACE_INDIRECT_RAY_LIMIT ?
                                         ADV_SPECULAR_COMPLEX_INTERFACE_INDIRECT_RAY_LIMIT :
                                         ADV_SPECULAR_INTERFACE_INDIRECT_RAY_LIMIT;
            indirectRayLimit = max(indirectRayLimit, interfaceRayLimit);
        }
        result.usedHighDetail = true;
        bool isTransparent = isIndirectInterfaceMaterial(material);
        bool cullBackFaces = hasPassedTransparent || isTransparent;

        bool canContinue = hasPathRayBudget(result.rayBudgetUsed) && indirectRayCount < indirectRayLimit &&
            remainingDistance > ADV_INDIRECT_MIN_TRACE_DISTANCE;
        PathIndirectSample next;
        next.isValid = false;
        vec3 nextOrigin = vec3(0.0);
        if (canContinue) {
            next = sampleIndirectSurface(
                geometry, material, incomingDirection, currentMedium, glassExteriorMedium, seed);
            nextOrigin = indirectOffsetOrigin(geometry.position, geometry.geometryNormal, next.direction);
        }
        uint nextRayFlags = rayFlags & ~gl_RayFlagsCullBackFacingTrianglesEXT;
        if (cullBackFaces && !material.isCloud) { nextRayFlags |= gl_RayFlagsCullBackFacingTrianglesEXT; }

        result.radiance +=
            throughput * evaluateIndirectLocalRadiance(geometry, material, incomingDirection, coneWidthAtHit,
                                                       currentMedium, remainingDistance, cullBackFaces);
        result.isResolved = true;
        if (!canContinue || !next.isValid) { break; }
        throughput *= next.throughput;
        if (!isFinite(throughput) || max(throughput.r, max(throughput.g, throughput.b)) <= 1e-6) { break; }

        currentMedium = next.medium;
        if (isTransparent) { hasPassedTransparent = true; }
        float outgoingConeSpread =
            max(coneSpread, ADV_INDIRECT_RAY_SPREAD_MAX * next.segmentRoughness * next.segmentRoughness);
        HitPayload nextHit = traceIndirectSegment(nextOrigin, next.direction, coneWidthAtHit, outgoingConeSpread,
                                                  remainingDistance, traceMask, nextRayFlags, traceRole);
        ++result.rayBudgetUsed;
        ++indirectRayCount;
        if (!isHitValid(nextHit)) {
#if ADV_INDIRECT_APPLY_MEDIUM_TRANSMITTANCE != 0
            throughput *= segmentTransmittance(currentMedium, remainingDistance);
#endif
            result.radiance += throughput * indirectEnvironment(nextOrigin, next.direction, captureClouds);
            result.isResolved = true;
            break;
        }

        rayOrigin = nextOrigin;
        incomingDirection = next.direction;
        coneWidthAtHit += max(nextHit.hitT, 0.0) * outgoingConeSpread;
        coneSpread = outgoingConeSpread;
        segmentRoughness = next.segmentRoughness;
        remainingDistance = max(remainingDistance - max(nextHit.hitT, 0.0), 0.0);
        hit = nextHit;
    }

    result.radiance = sanitizeRadiance(result.radiance);
    return result;
}

#endif
