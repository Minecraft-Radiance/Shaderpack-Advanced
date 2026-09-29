#ifndef ADV_PATH_PRIMARY_HIT_BUFFER_GLSL
#define ADV_PATH_PRIMARY_HIT_BUFFER_GLSL

#include "core/bindings.glsl"
#include "scene/hit.glsl"

const uint ADV_PRIMARY_HIT_INSTANCE_MASK = 0x00ffffffu;
const uint ADV_PRIMARY_HIT_CATEGORY_MASK = 0x3u;
const uint ADV_PRIMARY_HIT_CATEGORY_SHIFT = 24u;
const uint ADV_PRIMARY_HIT_HAND_BIT = 0x04000000u;
const uint ADV_PRIMARY_HIT_CLOUD_BIT = 0x08000000u;
const uint ADV_PRIMARY_HIT_BOAT_WATER_BIT = 0x10000000u;
const uint ADV_PRIMARY_HIT_TRACE_USED_BIT = 0x20000000u;
const uint ADV_PRIMARY_HIT_FRONT_FACE_BIT = 0x40000000u;
const uint ADV_PRIMARY_HIT_VALID_BIT = 0x80000000u;
const float ADV_PRIMARY_TEMPORAL_INVALID_DEPTH = 65504.0;

#ifdef ADV_PRIMARY_HIT_WRITE
#    define ADV_PRIMARY_HIT_IDENTITY_ACCESS writeonly
#    define ADV_PRIMARY_HIT_AUX_ACCESS writeonly
#elif defined(ADV_PRIMARY_HIT_IDENTITY_READ_WRITE)
#    define ADV_PRIMARY_HIT_IDENTITY_ACCESS
#    define ADV_PRIMARY_HIT_AUX_ACCESS readonly
#else
#    define ADV_PRIMARY_HIT_IDENTITY_ACCESS readonly
#    define ADV_PRIMARY_HIT_AUX_ACCESS readonly
#endif

layout(set = 5,
       binding = ADV_PRIMARY_HIT_IDENTITY_BINDING,
       rgba32ui) ADV_PRIMARY_HIT_IDENTITY_ACCESS uniform uimage2D primaryHitIdentityImage;
layout(set = 5,
       binding = ADV_PRIMARY_HIT_BARY_DEPTH_BINDING,
       rg32ui) ADV_PRIMARY_HIT_AUX_ACCESS uniform uimage2D primaryHitBaryDepthImage;
layout(set = 5,
       binding = ADV_PRIMARY_MOTION_BINDING,
       rg32f) ADV_PRIMARY_HIT_AUX_ACCESS uniform image2D primaryMotionImage;

#undef ADV_PRIMARY_HIT_IDENTITY_ACCESS
#undef ADV_PRIMARY_HIT_AUX_ACCESS

bool isPrimaryHitFinite(float scalar) {
    return !isnan(scalar) && !isinf(scalar);
}

bool isPrimaryHitFinite(vec2 vector) {
    return !any(isnan(vector)) && !any(isinf(vector));
}

bool isPrimaryHitFinite(vec3 vector) {
    return !any(isnan(vector)) && !any(isinf(vector));
}

vec2 primaryHitSignNotZero(vec2 vector) {
    return vec2(vector.x >= 0.0 ? 1.0 : -1.0, vector.y >= 0.0 ? 1.0 : -1.0);
}

uint packPrimaryTemporalNormal(vec3 normal) {
    float lengthSquared = dot(normal, normal);
    if (!isPrimaryHitFinite(normal) || !isPrimaryHitFinite(lengthSquared) || lengthSquared <= 1e-12) { return 0u; }
    vec3 normalizedNormal = normal * inversesqrt(lengthSquared);
    normalizedNormal /= max(abs(normalizedNormal.x) + abs(normalizedNormal.y) + abs(normalizedNormal.z), 1e-8);
    vec2 encoded = normalizedNormal.xy;
    if (normalizedNormal.z < 0.0) { encoded = (vec2(1.0) - abs(encoded.yx)) * primaryHitSignNotZero(encoded); }
    return packSnorm2x16(encoded);
}

vec3 unpackPrimaryTemporalNormal(uint packedNormal) {
    vec2 encoded = unpackSnorm2x16(packedNormal);
    vec3 normal = vec3(encoded, 1.0 - abs(encoded.x) - abs(encoded.y));
    if (normal.z < 0.0) { normal.xy = (vec2(1.0) - abs(normal.yx)) * primaryHitSignNotZero(normal.xy); }
    float lengthSquared = dot(normal, normal);
    return isPrimaryHitFinite(normal) && isPrimaryHitFinite(lengthSquared) && lengthSquared > 1e-12 ?
               normal * inversesqrt(lengthSquared) :
               vec3(0.0);
}

bool isPrimaryHitIdentityValid(uvec4 identity) {
    float hitT = uintBitsToFloat(identity.w);
    return (identity.x & ADV_PRIMARY_HIT_VALID_BIT) != 0u && hitT > 0.0 && isPrimaryHitFinite(hitT);
}

uvec4 invalidPrimaryHitIdentity() {
    return uvec4(0u);
}

bool normalizePrimaryHitBarycentrics(vec2 hitBarycentrics, out vec2 normalizedBarycentrics) {
    normalizedBarycentrics = vec2(0.0);
    vec3 bary = vec3(1.0 - hitBarycentrics.x - hitBarycentrics.y, hitBarycentrics);
    if (!isPrimaryHitFinite(bary) || any(lessThan(bary, vec3(-0.02))) || any(greaterThan(bary, vec3(1.02)))) {
        return false;
    }
    bary = max(bary, vec3(0.0));
    float sum = bary.x + bary.y + bary.z;
    if (!isPrimaryHitFinite(sum) || sum <= 1e-8) { return false; }
    normalizedBarycentrics = (bary / sum).yz;
    return true;
}

uvec4 packPrimaryHitIdentity(HitPayload hit) {
    if (!isHitValid(hit) || hit.instanceIndex > ADV_PRIMARY_HIT_INSTANCE_MASK ||
        hit.category > ADV_PRIMARY_HIT_CATEGORY_MASK) {
        return invalidPrimaryHitIdentity();
    }
    uint packedInstance = (hit.instanceIndex & ADV_PRIMARY_HIT_INSTANCE_MASK) |
                          ((hit.category & ADV_PRIMARY_HIT_CATEGORY_MASK) << ADV_PRIMARY_HIT_CATEGORY_SHIFT) |
                          ((hit.instanceMask & HAND_MASK) != 0u ? ADV_PRIMARY_HIT_HAND_BIT : 0u) |
                          ((hit.instanceMask & CLOUD_MASK) != 0u ? ADV_PRIMARY_HIT_CLOUD_BIT : 0u) |
                          ((hit.instanceMask & BOAT_WATER_MASK) != 0u ? ADV_PRIMARY_HIT_BOAT_WATER_BIT : 0u) |
                          (hit.isFrontFace != 0u ? ADV_PRIMARY_HIT_FRONT_FACE_BIT : 0u) | ADV_PRIMARY_HIT_VALID_BIT;
    return uvec4(packedInstance, hit.geometryBufferIndex, hit.primitiveId, floatBitsToUint(hit.hitT));
}

#ifdef ADV_PRIMARY_HIT_WRITE
void storePrimaryHit(ivec2 packedPixel, HitPayload hit, float temporalDepth, vec2 temporalMotion, uint rayBudgetUsed) {
    uvec4 identity = packPrimaryHitIdentity(hit);
    bool isValid = isPrimaryHitIdentityValid(identity);
    vec2 barycentrics = vec2(0.0);
    isValid = isValid && normalizePrimaryHitBarycentrics(hit.barycentrics, barycentrics);
    if (!isValid) { identity = invalidPrimaryHitIdentity(); }
    float depth = isValid && isPrimaryHitFinite(temporalDepth) && temporalDepth >= 0.0 ?
                      temporalDepth :
                      ADV_PRIMARY_TEMPORAL_INVALID_DEPTH;
    vec2 motion = isValid && isPrimaryHitFinite(temporalMotion) ? temporalMotion : vec2(0.0);
    identity.x |= rayBudgetUsed != 0u ? ADV_PRIMARY_HIT_TRACE_USED_BIT : 0u;
    imageStore(primaryHitIdentityImage, packedPixel, identity);
    imageStore(primaryHitBaryDepthImage, packedPixel,
               uvec4(isValid ? packUnorm2x16(barycentrics) : 0u, floatBitsToUint(depth), rayBudgetUsed, 0u));
    if (isValid && (!isChunkGeometryBufferIndex(hit.geometryBufferIndex) || (hit.instanceMask & HAND_MASK) != 0u)) {
        imageStore(primaryMotionImage, packedPixel, vec4(motion, 0.0, 0.0));
    }
}
#else
uvec4 loadPrimaryHitIdentity(ivec2 packedPixel) {
    return imageLoad(primaryHitIdentityImage, packedPixel);
}

#    ifdef ADV_PRIMARY_HIT_IDENTITY_READ_WRITE
void storePrimaryHitIdentity(ivec2 packedPixel, uvec4 identity) {
    imageStore(primaryHitIdentityImage, packedPixel, identity);
}
#    endif

vec2 loadPrimaryTemporalMotion(ivec2 packedPixel) {
    return imageLoad(primaryMotionImage, packedPixel).xy;
}

bool loadPrimaryHit(ivec2 packedPixel,
                    float coneSpread,
                    out HitPayload hit,
                    out bool hasStoredIdentity,
                    out uint rayBudgetUsed,
                    out float temporalDepth) {
    resetHit(hit, 0.0, coneSpread, ADV_TRACE_ROLE_PRIMARY);
    uvec4 baryDepthBudget = imageLoad(primaryHitBaryDepthImage, packedPixel);
    temporalDepth = uintBitsToFloat(baryDepthBudget.y);
    uvec4 identity = loadPrimaryHitIdentity(packedPixel);
    rayBudgetUsed = (identity.x & ADV_PRIMARY_HIT_TRACE_USED_BIT) != 0u ? 1u : 0u;
    hasStoredIdentity = isPrimaryHitIdentityValid(identity);
    if (!hasStoredIdentity) { return false; }
    vec2 barycentrics;
    if (!normalizePrimaryHitBarycentrics(unpackUnorm2x16(baryDepthBudget.x), barycentrics)) { return false; }

    hit.hitKind = ADV_HIT_KIND_TRIANGLE;
    hit.instanceIndex = identity.x & ADV_PRIMARY_HIT_INSTANCE_MASK;
    hit.geometryBufferIndex = identity.y;
    hit.primitiveId = identity.z;
    hit.category = (identity.x >> ADV_PRIMARY_HIT_CATEGORY_SHIFT) & ADV_PRIMARY_HIT_CATEGORY_MASK;
    hit.hitT = uintBitsToFloat(identity.w);
    hit.barycentrics = barycentrics;
    hit.isFrontFace = (identity.x & ADV_PRIMARY_HIT_FRONT_FACE_BIT) != 0u ? 1u : 0u;
    hit.instanceMask = ((identity.x & ADV_PRIMARY_HIT_HAND_BIT) != 0u ? HAND_MASK : 0u) |
                       ((identity.x & ADV_PRIMARY_HIT_CLOUD_BIT) != 0u ? CLOUD_MASK : 0u) |
                       ((identity.x & ADV_PRIMARY_HIT_BOAT_WATER_BIT) != 0u ? BOAT_WATER_MASK : 0u);
    return true;
}
#endif

#endif
