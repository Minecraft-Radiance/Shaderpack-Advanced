#ifndef ADV_SCENE_PARALLAX_STATE_GLSL
#define ADV_SCENE_PARALLAX_STATE_GLSL

#include "scene/geometry.glsl"
#include "scene/materials/parallax.glsl"
#include "util/ray_cone.glsl"

const uint ADV_PARALLAX_INVALID_INSTANCE_INDEX = 0xffffffffu;
const uint ADV_PARALLAX_HIT_FLAG_FRONT_FACE = 1u << 0u;
const uint ADV_PARALLAX_HIT_FLAG_SIDE_WALL = 1u << 1u;

struct ParallaxState {
    uvec4 hit;
    vec2 continuousUv;
    float depth;
    float maxDepthWorld;
};

ParallaxState invalidParallaxState() {
    ParallaxState parallaxState;
    parallaxState.hit = uvec4(ADV_PARALLAX_INVALID_INSTANCE_INDEX);
    parallaxState.continuousUv = vec2(0.0);
    parallaxState.depth = 0.0;
    parallaxState.maxDepthWorld = 0.0;
    return parallaxState;
}

bool isParallaxStateValid(ParallaxState parallaxState) {
#if ADV_PARALLAX_ENABLED == 0
    return false;
#else
    return parallaxState.hit.x != ADV_PARALLAX_INVALID_INSTANCE_INDEX && isFinite(parallaxState.continuousUv) &&
           isFinite(parallaxState.depth) && parallaxState.depth >= 0.0 && isFinite(parallaxState.maxDepthWorld) &&
           parallaxState.maxDepthWorld > heightMapMinWorldDepth;
#endif
}

bool resolveParallaxStateExit(ParallaxState stored,
                              vec3 surfacePosition,
                              vec3 surfaceNormal,
                              vec3 worldDirection,
                              out vec3 origin,
                              out vec3 normal) {
    origin = surfacePosition;
    normal = normalize(surfaceNormal, vec3(0.0, 1.0, 0.0));
    if (!isParallaxStateValid(stored)) { return true; }

    uint instanceIndex = stored.hit.x;
    uint geometryBufferIndex = stored.hit.y;
    uint primitiveId = stored.hit.z;
    bool isFrontFace = (stored.hit.w & ADV_PARALLAX_HIT_FLAG_FRONT_FACE) != 0u;

    uint i0, i1, i2;
    PositionVertex p0, p1, p2;
    MaterialVertex m0, m1, m2;
    loadTriangle(geometryBufferIndex, primitiveId, i0, i1, i2, p0, p1, p2, m0, m1, m2);
    if (!hasTexture(m0.packedData)) { return true; }
    TextureMapEntry textureMap = mapping.entries[m0.textureID];
    if (textureMap.normal < 0) { return true; }

    AccelerationStructureInstance instance = tlasInstances.instances[instanceIndex];
    vec3 worldP0 = transformPoint(instance, p0.pos);
    vec3 worldP1 = transformPoint(instance, p1.pos);
    vec3 worldP2 = transformPoint(instance, p2.pos);
    vec3 planePosition = worldP0;
    vec2 referenceUv = m0.textureUV;
    vec2 atlasMin = min(m0.textureUV, min(m1.textureUV, m2.textureUV));
    vec2 atlasMax = max(m0.textureUV, max(m1.textureUV, m2.textureUV));

    vec3 localDPdu;
    vec3 localDPdv;
    computedposduDv(p0.pos, p1.pos, p2.pos, m0.textureUV, m1.textureUV, m2.textureUV, localDPdu, localDPdv);
    vec3 dPdu = transformVector(instance, localDPdu);
    vec3 dPdv = transformVector(instance, localDPdv);
    vec3 outwardNormal = normalize(cross(worldP1 - worldP0, worldP2 - worldP0), normal);
    vec3 baseNormal = isFrontFace ? outwardNormal : -outwardNormal;
    if (!isFinite(planePosition) || !isFinite(referenceUv) || !isFinite(dPdu) || !isFinite(dPdv) ||
        !isFinite(baseNormal)) {
        return true;
    }

    vec2 materialUv = wrapUvInRect(stored.continuousUv, atlasMin, atlasMax);
    bool isSideWall = (stored.hit.w & ADV_PARALLAX_HIT_FLAG_SIDE_WALL) != 0u;
    ParallaxSurfaceState surface =
        makeParallaxSurfaceState(materialUv, stored.continuousUv, stored.depth, surfacePosition, normal, isSideWall);
    return resolveParallaxExitOrigin(textureMap.normal, atlasMin, atlasMax, referenceUv, planePosition, dPdu, dPdv,
                                     baseNormal, stored.maxDepthWorld, true, surface, worldDirection,
                                     ADV_PARALLAX_SECONDARY_MAX_STEPS, origin, normal);
}

bool resolvePathParallaxExit(
    ParallaxState parallax, vec3 position, vec3 geometryNormal, vec3 worldDirection, out vec3 origin, out vec3 normal) {
    return resolveParallaxStateExit(parallax, position, geometryNormal, worldDirection, origin, normal);
}

#endif
