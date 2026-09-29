#ifndef ADV_PATH_PRIMARY_TRACE_GLSL
#define ADV_PATH_PRIMARY_TRACE_GLSL

#include "scene/hit.glsl"
#include "path/budget.glsl"
#include "scene/materials/media.glsl"
#include "util/ray_cone.glsl"

#ifndef ADV_PRIMARY_MISS_INDEX
#    define ADV_PRIMARY_MISS_INDEX 0
#endif
#ifndef ADV_RAY_FLAGS
#    define ADV_RAY_FLAGS 0x200u
#endif
#ifndef ADV_PRIMARY_MAX_DISTANCE
#    define ADV_PRIMARY_MAX_DISTANCE max(1000.0, float(worldUBO.vistaDistanceBlocks))
#endif

const float ADV_PRIMARY_T_MIN = 0.001;

bool isPrimaryTraceFinite(vec3 vector) {
    return !any(isnan(vector)) && !any(isinf(vector));
}

vec3 primaryTraceNormalize(vec3 vector, vec3 fallback) {
    float lengthSquared = dot(vector, vector);
    if (!isPrimaryTraceFinite(vector) || isnan(lengthSquared) || isinf(lengthSquared) || lengthSquared <= 1e-12) {
        return fallback;
    }
    return vector * inversesqrt(lengthSquared);
}

void buildPrimaryCameraRay(
    ivec2 flatPixel, ivec2 flatExtent, out vec3 origin, out vec3 direction, out float coneSpread) {
    vec2 pixelCenter = vec2(flatPixel) + 0.5 + worldUBO.cameraJitter;
    vec2 ndc = pixelCenter / vec2(flatExtent) * 2.0 - 1.0;
    vec4 viewNear = worldUBO.cameraProjMatInv * vec4(ndc, 0.0, 1.0);
    origin = worldUBO.cameraEffectedViewMatInv[3].xyz;
    vec3 fallback = primaryTraceNormalize(-worldUBO.cameraEffectedViewMatInv[2].xyz, vec3(0.0, 0.0, -1.0));
    if (any(isnan(viewNear)) || any(isinf(viewNear)) || abs(viewNear.w) <= 1e-8) {
        direction = fallback;
    } else {
        viewNear /= viewNear.w;
        direction = primaryTraceNormalize(vec3(worldUBO.cameraEffectedViewMatInv * vec4(viewNear.xyz, 0.0)), fallback);
    }
    coneSpread =
        coneSpreadFromFov(fovYFromProj(worldUBO.cameraProjMat), fovXFromProj(worldUBO.cameraProjMat), vec2(flatExtent));
}

uint primaryMask(bool isFirstSegment, bool includeHand) {
    uint mask = WORLD_MASK | CLOUD_MASK | BOAT_WATER_MASK;
    if (isFirstSegment) { mask |= FISHING_BOBBER_MASK | WEATHER_MASK | PARTICLE_MASK; }
    if (includeHand) { mask |= HAND_MASK; }
    if (worldUBO.isFirstPerson == 0u) { mask |= PLAYER_MASK; }
    return mask;
}

uint cullFlagsForMedium(uint medium) {
    if (medium == ADV_MEDIUM_CLOUD) { return uint(ADV_RAY_FLAGS); }
    return uint(ADV_RAY_FLAGS) | gl_RayFlagsCullBackFacingTrianglesEXT;
}

HitPayload tracePrimaryHit(vec3 origin,
                           vec3 direction,
                           float tMin,
                           float tMax,
                           float coneWidth,
                           float coneSpread,
                           uint role,
                           uint mask,
                           uint rayFlags) {
    resetHit(hitPayload, coneWidth, coneSpread, role);
    traceRayEXT(topLevelAS, rayFlags, mask, 1, 1, uint(ADV_PRIMARY_MISS_INDEX), origin, tMin, direction, tMax, 0);
    return hitPayload;
}

HitPayload findSegmentHitWithTraceLimit(vec3 origin,
                                        vec3 direction,
                                        float coneWidth,
                                        float coneSpread,
                                        uint medium,
                                        bool isFirstSegment,
                                        bool includeHand,
                                        uint traceLimit,
                                        out uint traceCount) {
    float segmentTMin = isFirstSegment ? ADV_PRIMARY_T_MIN : 0.0;
    HitPayload closest;
    resetHit(closest, coneWidth, coneSpread, ADV_TRACE_ROLE_PRIMARY);
    traceCount = 0u;
    if (traceLimit == 0u) { return closest; }

    uint segmentMask = primaryMask(isFirstSegment, includeHand);
    uint segmentRayFlags = isFirstSegment ? uint(ADV_RAY_FLAGS) : cullFlagsForMedium(medium);
    closest = tracePrimaryHit(origin, direction, segmentTMin, float(ADV_PRIMARY_MAX_DISTANCE), coneWidth, coneSpread,
                              ADV_TRACE_ROLE_PRIMARY, segmentMask, segmentRayFlags);
    ++traceCount;

    return closest;
}

HitPayload findBudgetedSegmentHit(vec3 origin,
                                  vec3 direction,
                                  float coneWidth,
                                  float coneSpread,
                                  uint medium,
                                  bool includeHand,
                                  uint reservedRayCount,
                                  inout uint rayBudgetUsed) {
    uint remainingBudget = remainingPathRayBudget(rayBudgetUsed);
    uint traceLimit = remainingBudget > reservedRayCount ? remainingBudget - reservedRayCount : 0u;
    uint traceCount;
    HitPayload hit = findSegmentHitWithTraceLimit(origin, direction, coneWidth, coneSpread, medium, false, includeHand,
                                                  traceLimit, traceCount);
    rayBudgetUsed += traceCount;
    return hit;
}

vec3 offsetRayAlongNormal(vec3 position, vec3 offsetNormal) {
    const float originThreshold = 1.0 / 32.0;
    const float floatScale = 1.0 / 65536.0;
    const float integerScale = 256.0;
    ivec3 integerOffset = ivec3(integerScale * offsetNormal);
    ivec3 positionBits = floatBitsToInt(position);
    ivec3 offsetBits = ivec3(position.x < 0.0 ? -integerOffset.x : integerOffset.x,
                             position.y < 0.0 ? -integerOffset.y : integerOffset.y,
                             position.z < 0.0 ? -integerOffset.z : integerOffset.z);
    vec3 integerPosition = intBitsToFloat(positionBits + offsetBits);
    return vec3(abs(position.x) < originThreshold ? position.x + floatScale * offsetNormal.x : integerPosition.x,
                abs(position.y) < originThreshold ? position.y + floatScale * offsetNormal.y : integerPosition.y,
                abs(position.z) < originThreshold ? position.z + floatScale * offsetNormal.z : integerPosition.z);
}

vec3 offsetRay(vec3 position, vec3 normal, vec3 direction) {
    float side = dot(direction, normal) >= 0.0 ? 1.0 : -1.0;
    return offsetRayAlongNormal(position, normal * side);
}

vec3 offsetParallaxExit(vec3 position, vec3 normal, vec3 direction) {
    float side = dot(direction, normal) >= 0.0 ? 1.0 : -1.0;
    return position + normal * (side * 0.0002);
}

#endif
