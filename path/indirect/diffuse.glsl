#ifndef ADV_PATH_INDIRECT_DIFFUSE_GLSL
#define ADV_PATH_INDIRECT_DIFFUSE_GLSL

const float ADV_DIFFUSE_RAY_SPREAD = 0.1;

#define ADV_INDIRECT_SURFACE_MISS_INDEX ADV_PATH_SURFACE_MISS_INDEX
#define ADV_INDIRECT_SHADOW_MISS_INDEX ADV_PATH_SHADOW_MISS_INDEX
#define ADV_INDIRECT_HAS_TRANSMISSION_PAYLOAD 1
#define ADV_INDIRECT_APPLY_MEDIUM_TRANSMITTANCE 0
#include "path/indirect/trace.glsl"
#undef ADV_INDIRECT_APPLY_MEDIUM_TRANSMITTANCE
#undef ADV_INDIRECT_HAS_TRANSMISSION_PAYLOAD
#undef ADV_INDIRECT_SHADOW_MISS_INDEX
#undef ADV_INDIRECT_SURFACE_MISS_INDEX

vec3 diffuseOffsetOrigin(vec3 position, vec3 normal, vec3 direction) {
    float side = dot(direction, normal) >= 0.0 ? 1.0 : -1.0;
    return position + normal * (side * 0.0002);
}

float diffusePrimaryConeSpread(ivec2 flatExtent) {
    return coneSpreadFromFov(fovYFromProj(worldUBO.cameraProjMat), fovXFromProj(worldUBO.cameraProjMat),
                             vec2(flatExtent));
}

uint diffuseSurfaceMask(DiffusePath primary) {
    uint mask = WORLD_MASK | FISHING_BOBBER_MASK;
    if ((pathFlags(primary.key) & ADV_PATH_FLAG_HAND) == 0u) { mask |= PLAYER_MASK; }
    return mask;
}

float diffuseRemainingDistance(float pathLength, uint flags) {
    if (!isFinite(pathLength)) { return 0.0; }
    uint distanceBlocks = (flags & ADV_PATH_FLAG_CLOUD) != 0u ?
                              worldUBO.renderDistanceBlocks :
                              max(worldUBO.renderDistanceBlocks, worldUBO.vistaDistanceBlocks);
    return max(float(distanceBlocks) - max(pathLength, 0.0), 0.0);
}

HitPayload traceDiffuseSurface(vec3 origin, vec3 direction, float coneWidth, float maximumDistance, uint mask) {
    resetHit(hitPayload, coneWidth, ADV_DIFFUSE_RAY_SPREAD, ADV_TRACE_ROLE_SECONDARY_DIFFUSE);
    if (maximumDistance <= ADV_INDIRECT_MIN_TRACE_DISTANCE) { return hitPayload; }
    traceRayEXT(topLevelAS, uint(ADV_RAY_FLAGS) | gl_RayFlagsCullBackFacingTrianglesEXT, mask, 1, 1,
                uint(ADV_PATH_SURFACE_MISS_INDEX), origin, 0.0, direction, maximumDistance, 0);
    return hitPayload;
}

void clearDiffuseOutputs(ivec2 packedPixel) {
    imageStore(diffuseRadianceImage, packedPixel, vec4(0.0));
    imageStore(diffuseHitDistanceImage, packedPixel, vec4(0.0));
    imageStore(diffuseDirectionMomentImage, packedPixel, vec4(0.0));
}

void shadeDiffuse(ivec2 packedPixel, ivec2 flatExtent, CheckerCoordinate checker, DiffusePath primary) {
    uint primaryFlags = pathFlags(primary.key);
    if (!isPathValid(primary.key) || isSkyPath(primary.key) || (primaryFlags & ADV_PATH_FLAG_TERMINAL_SURFACE) == 0u ||
        (primaryFlags & (ADV_PATH_FLAG_NO_REFLECT | ADV_PATH_FLAG_PORTAL)) != 0u) {
        clearDiffuseOutputs(packedPixel);
        return;
    }

    vec2 randomSample = blueNoise2(blueNoiseTexture, checker.flatPixel, worldUBO.seed, 0u);
    vec3 direction = sampleCosineHemisphere(randomSample, primary.shadingNormal);
    vec3 geometryNormal = normalize(primary.geometryNormal, vec3(0.0, 1.0, 0.0));
    if (dot(direction, geometryNormal) <= 1e-6) {
        clearDiffuseOutputs(packedPixel);
        return;
    }

    vec3 primaryExitPosition = primary.position;
    vec3 primaryExitNormal = geometryNormal;
    if (pathBounceCount(primary.key) == 0u &&
        !resolvePathParallaxExit(primary.parallax, primary.position, primary.geometryNormal, direction,
                                 primaryExitPosition, primaryExitNormal)) {
        clearDiffuseOutputs(packedPixel);
        return;
    }

    vec3 origin = diffuseOffsetOrigin(primaryExitPosition, primaryExitNormal, direction);
    float primaryConeSpread = diffusePrimaryConeSpread(flatExtent);
    float startingConeWidth = max(primary.pathLength, 0.0) * primaryConeSpread;
    float maximumDistance = diffuseRemainingDistance(primary.pathLength, primaryFlags);
    uint rayBudgetUsed = pathRayBudgetUsed(primary.key);
    if (!hasPathRayBudget(rayBudgetUsed)) {
        clearDiffuseOutputs(packedPixel);
        return;
    }
    HitPayload hit;
    resetHit(hit, startingConeWidth, ADV_DIFFUSE_RAY_SPREAD, ADV_TRACE_ROLE_SECONDARY_DIFFUSE);
    hit = traceDiffuseSurface(origin, direction, startingConeWidth, maximumDistance, diffuseSurfaceMask(primary));
    ++rayBudgetUsed;

    vec3 radiance = vec3(0.0);
    float hitDistance = maximumDistance;
    bool isHighDetail = false;
    bool isResolved = false;
    if (isHitValid(hit)) {
        hitDistance = hit.hitT;
        uint seed = xxhash32(uvec3(uint(checker.flatPixel.x), uint(checker.flatPixel.y), worldUBO.seed ^ 0x6c8e9cf5u));
        IndirectTraceResult indirect = traceIndirectFromHit(
            hit, origin, direction, primary.medium, startingConeWidth + hit.hitT * ADV_DIFFUSE_RAY_SPREAD,
            ADV_DIFFUSE_RAY_SPREAD, 1.0, false, vec3(1.0), rayBudgetUsed, 1u, false,
            max(maximumDistance - hit.hitT, 0.0), seed, diffuseSurfaceMask(primary),
            uint(ADV_RAY_FLAGS) | gl_RayFlagsCullBackFacingTrianglesEXT, ADV_TRACE_ROLE_SECONDARY_DIFFUSE, false, true);
        radiance = indirect.radiance;
        isHighDetail = indirect.usedHighDetail;
        isResolved = indirect.isResolved;
    } else {
        vec3 throughput = indirectPayloadTransmission(hit);
        radiance = throughput * indirectEnvironment(origin, direction, true);
        isResolved = true;
    }

    radiance = sanitizeRadiance(radiance);
    float detailAndValidity = isResolved ? (isHighDetail ? 1.0 : 0.5) : 0.0;
    float luminance = min(luminance(radiance), ADV_FP16_MAX);
    imageStore(diffuseRadianceImage, packedPixel, vec4(radiance, detailAndValidity));
    imageStore(diffuseHitDistanceImage, packedPixel, vec4(clamp(hitDistance, 0.0, ADV_FP16_MAX)));
    imageStore(diffuseDirectionMomentImage, packedPixel, vec4(direction * luminance, luminance));
}

#endif
