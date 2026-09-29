#ifndef ADV_PATH_TYPES_GLSL
#define ADV_PATH_TYPES_GLSL

#include "scene/parallax_state.glsl"

const uint ADV_PATH_FLAG_VALID = 1u << 0u;
const uint ADV_PATH_FLAG_SKY = 1u << 1u;
const uint ADV_PATH_FLAG_SPLIT = 1u << 2u;
const uint ADV_PATH_FLAG_DYNAMIC = 1u << 3u;
const uint ADV_PATH_FLAG_HAND = 1u << 4u;
const uint ADV_PATH_FLAG_CLOUD = 1u << 5u;
const uint ADV_PATH_FLAG_WATER = 1u << 6u;
const uint ADV_PATH_FLAG_NO_REFLECT = 1u << 7u;
const uint ADV_PATH_FLAG_PORTAL = 1u << 8u;
const uint ADV_PATH_FLAG_FIRST_HIT_VALID = 1u << 9u;
const uint ADV_PATH_FLAG_TERMINAL_SURFACE = 1u << 10u;
const uint ADV_PATH_FLAG_FIRST_HIT_WATER = 1u << 11u;
const uint ADV_PATH_FLAG_FIRST_HIT_GLASS = 1u << 12u;
const uint ADV_PATH_FLAG_FIRST_HIT_CLOUD = 1u << 13u;
const uint ADV_PATH_FLAG_FIRST_HIT_DYNAMIC = 1u << 14u;
const uint ADV_PATH_FLAG_FIRST_HIT_HAND = 1u << 15u;
const uint ADV_PATH_FLAG_FIRST_INTERFACE_SPECULAR = 1u << 16u;
const uint ADV_PATH_FLAG_EMISSIVE = 1u << 17u;
const uint ADV_PATH_FLAG_AFTER_TRANSPARENT = 1u << 18u;
const uint ADV_PATH_STATE_TRANSPORT = 1u << 27u;
const uint ADV_PATH_STATE_TRANSPARENT_DISTANCE = 1u << 28u;
const uint ADV_PATH_STATE_PARALLAX = 1u << 29u;
const uint ADV_PATH_STATE_PARALLAX_SIDE_WALL = 1u << 30u;
const uint ADV_PATH_SURFACE_HASH_SHIFT = 19u;
const uint ADV_PATH_SURFACE_HASH_MASK = 0x1fffu;
struct PathKey {
    uint flags;
    uint packed;
};

struct PathRecord {
    PathKey key;
    vec3 position;
    float pathLength;
    vec3 shadingNormal;
    float roughness;
    vec3 geometryNormal;
    vec3 albedo;
    float metallic;
    vec3 f0;
    ParallaxState parallax;
    float opacity;
    vec3 throughput;
    vec3 rayDirection;
    float previousPathDepth;
    float transparentSpecularHitDistance;
};

struct DiffusePath {
    PathKey key;
    vec3 position;
    float pathLength;
    vec3 shadingNormal;
    vec3 geometryNormal;
    uint medium;
    ParallaxState parallax;
};

struct SpecularPath {
    PathKey key;
    vec3 position;
    float pathLength;
    vec3 shadingNormal;
    vec3 geometryNormal;
    vec3 rayDirection;
    float roughness;
    uint medium;
    ParallaxState parallax;
};

struct TransmissionPath {
    PathKey key;
    vec3 position;
    float pathLength;
    vec3 shadingNormal;
    vec3 geometryNormal;
    vec3 albedo;
    vec3 rayDirection;
    float opacity;
    ParallaxState parallax;
};

struct ShadingPath {
    PathKey key;
    vec3 position;
    vec3 shadingNormal;
    vec3 geometryNormal;
    vec3 albedo;
    vec3 f0;
    vec3 throughput;
    vec3 rayDirection;
    float roughness;
    float metallic;
    float opacity;
    ParallaxState parallax;
};

struct ResolvePath {
    PathKey key;
    vec3 position;
    float pathLength;
    vec3 shadingNormal;
    vec3 geometryNormal;
    vec3 albedo;
    vec3 f0;
    vec3 throughput;
    vec3 rayDirection;
    float previousPathDepth;
    float roughness;
    float metallic;
    float opacity;
    float transparentSpecularHitDistance;
};

#endif
