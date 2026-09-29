#ifndef ADV_PATH_INDIRECT_SPECULAR_GLSL
#define ADV_PATH_INDIRECT_SPECULAR_GLSL

#ifndef ADV_SPECULAR_DISTANCE_FADE_RANGE
#    define ADV_SPECULAR_DISTANCE_FADE_RANGE 16.0
#endif

const float ADV_SPECULAR_RAY_SPREAD_MAX = 0.1;

#define ADV_INDIRECT_SURFACE_MISS_INDEX ADV_PATH_SURFACE_MISS_INDEX
#define ADV_INDIRECT_SHADOW_MISS_INDEX ADV_PATH_SHADOW_MISS_INDEX
#define ADV_INDIRECT_HAS_TRANSMISSION_PAYLOAD 0
#include "path/indirect/trace.glsl"
#undef ADV_INDIRECT_HAS_TRANSMISSION_PAYLOAD
#undef ADV_INDIRECT_SHADOW_MISS_INDEX
#undef ADV_INDIRECT_SURFACE_MISS_INDEX

vec3 specularOffsetOrigin(vec3 position, vec3 normal, vec3 direction) {
    float side = dot(direction, normal) >= 0.0 ? 1.0 : -1.0;
    return position + normal * (side * 0.0002);
}

float specularPrimaryConeSpread(ivec2 flatExtent) {
    return coneSpreadFromFov(fovYFromProj(worldUBO.cameraProjMat), fovXFromProj(worldUBO.cameraProjMat),
                             vec2(flatExtent));
}

float specularRenderDistance(uint flags) {
    return float((flags & ADV_PATH_FLAG_CLOUD) != 0u ?
                     worldUBO.renderDistanceBlocks :
                     max(worldUBO.renderDistanceBlocks, worldUBO.vistaDistanceBlocks));
}

float specularDistanceFade(float totalDistance, uint flags) {
    float fadeEnd = max(specularRenderDistance(flags), 1.0);
    float fadeStart = max(fadeEnd - float(ADV_SPECULAR_DISTANCE_FADE_RANGE), 0.0);
    return smoothstep(fadeStart, fadeEnd, max(totalDistance, 0.0));
}

uint specularSurfaceMask(SpecularPath primary) {
    uint mask = WORLD_MASK | CLOUD_MASK | BOAT_WATER_MASK | FISHING_BOBBER_MASK;
    if ((pathFlags(primary.key) & ADV_PATH_FLAG_HAND) == 0u) { mask |= PLAYER_MASK; }
    return mask;
}

float specularRemainingDistance(float pathLength, uint flags) {
    if (!isFinite(pathLength)) { return 0.0; }
    return max(specularRenderDistance(flags) - max(pathLength, 0.0), 0.0);
}

HitPayload traceSpecularSurface(
    vec3 origin, vec3 direction, float coneWidth, float coneSpread, float maximumDistance, uint mask, uint rayFlags) {
    resetHit(hitPayload, coneWidth, coneSpread, ADV_TRACE_ROLE_SECONDARY_SPECULAR);
    if (maximumDistance <= ADV_INDIRECT_MIN_TRACE_DISTANCE) { return hitPayload; }
    traceRayEXT(topLevelAS, rayFlags, mask, 1, 1, uint(ADV_PATH_SURFACE_MISS_INDEX), origin, 0.0, direction,
                maximumDistance, 0);
    return hitPayload;
}

void clearSpecularOutputs(ivec2 packedPixel) {
    imageStore(specularRadianceImage, packedPixel, vec4(0.0));
    imageStore(specularHitDistanceImage, packedPixel, vec4(0.0));
    imageStore(specularDirectionMomentImage, packedPixel, vec4(0.0));
}

void shadeSpecular(ivec2 packedPixel, ivec2 flatExtent, CheckerCoordinate checker, SpecularPath primary) {
    uint primaryFlags = pathFlags(primary.key);
    if (!isPathValid(primary.key) || isSkyPath(primary.key) || (primaryFlags & ADV_PATH_FLAG_TERMINAL_SURFACE) == 0u ||
        (primaryFlags & (ADV_PATH_FLAG_NO_REFLECT | ADV_PATH_FLAG_PORTAL)) != 0u) {
        clearSpecularOutputs(packedPixel);
        return;
    }

    vec3 shadingNormal = brdfNormalize(primary.shadingNormal, vec3(0.0, 1.0, 0.0));
    vec3 geometryNormal = brdfNormalize(primary.geometryNormal, shadingNormal);
    vec3 viewDirection = brdfNormalize(-primary.rayDirection, shadingNormal);
    vec2 randomSample = blueNoise2(blueNoiseTexture, checker.flatPixel, worldUBO.seed, 2u);
    bool useLobeMixture = usesStochasticLobes(loadLobeSurface(packedPixel));
    SpecularSample sampleValue =
        useLobeMixture ?
            sampleSpecular(viewDirection, shadingNormal, clamp(primary.roughness, 0.0, 1.0), randomSample) :
            sampleSpecularAboveGeometry(viewDirection, shadingNormal, geometryNormal,
                                        clamp(primary.roughness, 0.0, 1.0), randomSample);
    if (useLobeMixture && sampleValue.isValid && dot(sampleValue.direction, geometryNormal) <= 1e-6) {
        sampleValue.isValid = false;
    }
    if (!sampleValue.isValid) {
        clearSpecularOutputs(packedPixel);
        return;
    }
    vec3 sampleTransport = useLobeMixture ? vec3(1.0) : sampleValue.throughput;

    vec3 primaryExitPosition = primary.position;
    vec3 primaryExitNormal = geometryNormal;
    if (pathBounceCount(primary.key) == 0u &&
        !resolvePathParallaxExit(primary.parallax, primary.position, primary.geometryNormal, sampleValue.direction,
                                 primaryExitPosition, primaryExitNormal)) {
        clearSpecularOutputs(packedPixel);
        return;
    }
    vec3 origin = specularOffsetOrigin(primaryExitPosition, primaryExitNormal, sampleValue.direction);
    float primaryConeSpread = specularPrimaryConeSpread(flatExtent);
    float startingConeWidth = max(primary.pathLength, 0.0) * primaryConeSpread;
    float rayConeSpread = ADV_SPECULAR_RAY_SPREAD_MAX * primary.roughness * primary.roughness;
    float maximumDistance = specularRemainingDistance(primary.pathLength, primaryFlags);
    uint rayBudgetUsed = pathRayBudgetUsed(primary.key);
    if (!hasPathRayBudget(rayBudgetUsed)) {
        clearSpecularOutputs(packedPixel);
        return;
    }
    HitPayload hit;
    uint rayFlags = pathNeedsBackFaceCull(primary.key) ? uint(ADV_RAY_FLAGS) | gl_RayFlagsCullBackFacingTrianglesEXT :
                                                         uint(ADV_RAY_FLAGS);
    hit = traceSpecularSurface(origin, sampleValue.direction, startingConeWidth, rayConeSpread, maximumDistance,
                               specularSurfaceMask(primary), rayFlags);
    ++rayBudgetUsed;

    vec3 background = calculateIndirectSkyRadiance(sampleValue.direction);
    if (ADV_CLOUD_INDIRECT_ENABLED != 0 && primary.roughness <= ADV_CLOUD_REFLECTION_MAX_ROUGHNESS) {
        background = shadeIndirectCloud(origin, sampleValue.direction, background);
    }
    vec3 radiance = background;
    float hitDistance = maximumDistance;
    bool isResolved = true;
    if (isHitValid(hit)) {
        hitDistance = hit.hitT;
        radiance = vec3(0.0);
        isResolved = false;
        uint seed = xxhash32(uvec3(uint(checker.flatPixel.x), uint(checker.flatPixel.y), worldUBO.seed ^ 0x9e3779b9u));
        bool captureClouds = ADV_CLOUD_INDIRECT_ENABLED != 0 && primary.roughness <= ADV_CLOUD_REFLECTION_MAX_ROUGHNESS;
        IndirectTraceResult indirect =
            traceIndirectFromHit(hit, origin, sampleValue.direction, primary.medium,
                                 startingConeWidth + hit.hitT * rayConeSpread, rayConeSpread, primary.roughness, false,
                                 sampleTransport, rayBudgetUsed, ADV_SPECULAR_OPAQUE_INDIRECT_RAY_LIMIT, true,
                                 max(maximumDistance - hit.hitT, 0.0), seed, specularSurfaceMask(primary), rayFlags,
                                 ADV_TRACE_ROLE_SECONDARY_SPECULAR, pathNeedsBackFaceCull(primary.key), captureClouds);
        radiance = indirect.radiance;
        isResolved = indirect.isResolved;
        vec3 backgroundContribution = background * sampleTransport * segmentTransmittance(primary.medium, hitDistance);
        radiance =
            mix(radiance, backgroundContribution,
                specularDistanceFade(max(primary.pathLength, 0.0) + hitDistance, primaryFlags));
    } else {
        radiance *= sampleTransport * segmentTransmittance(primary.medium, maximumDistance);
    }

    radiance = sanitizeRadiance(radiance);
    float luminance = min(luminance(radiance), ADV_FP16_MAX);
    imageStore(specularRadianceImage, packedPixel, vec4(radiance, isResolved ? 1.0 : 0.0));
    imageStore(specularHitDistanceImage, packedPixel, vec4(clamp(hitDistance, 0.0, ADV_FP16_MAX)));
    imageStore(specularDirectionMomentImage, packedPixel, vec4(sampleValue.direction * luminance, luminance));
}

#endif
