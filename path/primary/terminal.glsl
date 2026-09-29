#ifndef ADV_PATH_PRIMARY_TERMINAL_GLSL
#define ADV_PATH_PRIMARY_TERMINAL_GLSL

#include "scene/surface.glsl"

const float ADV_PRIMARY_FP16_MAX = 65504.0;

const uint ADV_TERMINAL_FLAG_HAND = 1u << 0u;
const uint ADV_TERMINAL_FLAG_CLOUD = 1u << 1u;
const uint ADV_TERMINAL_FLAG_WATER = 1u << 2u;
const uint ADV_TERMINAL_FLAG_NO_REFLECT = 1u << 3u;
const uint ADV_TERMINAL_FLAG_PORTAL = 1u << 4u;
const uint ADV_TERMINAL_FLAG_PARALLAX = 1u << 5u;
const uint ADV_TERMINAL_FLAG_FRONT_FACE = 1u << 6u;
const uint ADV_TERMINAL_FLAG_PARALLAX_SIDE_WALL = 1u << 7u;
const uint ADV_TERMINAL_FLAG_VALID = 1u << 8u;
const uint ADV_TERMINAL_CATEGORY_SHIFT = 13u;
const uint ADV_TERMINAL_CATEGORY_MASK = 0x7fu;

struct PathTerminal {
    uint metadata;
    uvec3 identity;
    vec3 position;
    vec3 previousPosition;
    bool hasPreviousPosition;
    f16vec3 geometryNormal;
    f16vec3 shadingNormal;
    f16vec3 albedo;
    f16vec3 f0;
    f16vec3 emission;
    float16_t roughness;
    float16_t metallic;
    float16_t opacity;
    vec2 parallaxContinuousUv;
    float parallaxDepth;
    float parallaxMaxDepthWorld;
};

PathTerminal invalidPathTerminal() {
    PathTerminal terminal;
    terminal.metadata = 0u;
    terminal.identity = uvec3(0u);
    terminal.position = vec3(0.0);
    terminal.previousPosition = vec3(0.0);
    terminal.hasPreviousPosition = false;
    terminal.geometryNormal = f16vec3(0.0, 1.0, 0.0);
    terminal.shadingNormal = f16vec3(0.0, 1.0, 0.0);
    terminal.albedo = f16vec3(0.0);
    terminal.f0 = f16vec3(0.0);
    terminal.emission = f16vec3(0.0);
    terminal.roughness = float16_t(1.0);
    terminal.metallic = float16_t(0.0);
    terminal.opacity = float16_t(1.0);
    terminal.parallaxContinuousUv = vec2(0.0);
    terminal.parallaxDepth = 0.0;
    terminal.parallaxMaxDepthWorld = 0.0;
    return terminal;
}

PathTerminal makePathTerminal(Surface surface) {
    PathTerminal terminal = invalidPathTerminal();
    uint flags = (surface.isHand ? ADV_TERMINAL_FLAG_HAND : 0u) | (surface.isCloud ? ADV_TERMINAL_FLAG_CLOUD : 0u) |
                 (surface.isWater ? ADV_TERMINAL_FLAG_WATER : 0u) |
                 (surface.isNonReflective ? ADV_TERMINAL_FLAG_NO_REFLECT : 0u) |
                 (surface.isPortal ? ADV_TERMINAL_FLAG_PORTAL : 0u) |
                 (surface.hasParallax ? ADV_TERMINAL_FLAG_PARALLAX : 0u) |
                 (surface.isFrontFace ? ADV_TERMINAL_FLAG_FRONT_FACE : 0u) |
                 (surface.isParallaxSideWall ? ADV_TERMINAL_FLAG_PARALLAX_SIDE_WALL : 0u) |
                 (surface.isValid ? ADV_TERMINAL_FLAG_VALID : 0u);
    terminal.metadata = flags | ((surface.category & ADV_TERMINAL_CATEGORY_MASK) << ADV_TERMINAL_CATEGORY_SHIFT);
    terminal.identity = uvec3(surface.instanceIndex, surface.geometryBufferIndex, surface.primitiveId);
    terminal.position = surface.position;
    terminal.previousPosition = surface.previousPosition;
    terminal.hasPreviousPosition = surface.hasPreviousPosition;
    vec3 geometryNormal = normalize(surface.geometryNormal, vec3(0.0, 1.0, 0.0));
    vec3 shadingNormal = normalize(surface.shadingNormal, geometryNormal);
    terminal.geometryNormal = f16vec3(clamp(geometryNormal, vec3(-1.0), vec3(1.0)));
    terminal.shadingNormal = f16vec3(clamp(shadingNormal, vec3(-1.0), vec3(1.0)));
    terminal.albedo = f16vec3(isFinite(surface.albedo) ? clamp(surface.albedo, vec3(0.0), vec3(1.0)) : vec3(0.0));
    terminal.f0 = f16vec3(isFinite(surface.f0) ? clamp(surface.f0, vec3(0.0), vec3(1.0)) : vec3(0.0));
    terminal.emission = f16vec3(
        isFinite(surface.emission) ? clamp(surface.emission, vec3(0.0), vec3(ADV_PRIMARY_FP16_MAX)) : vec3(0.0));
    terminal.roughness = float16_t(isFinite(surface.roughness) ? clamp(surface.roughness, 0.0, 1.0) : 1.0);
    terminal.metallic = float16_t(isFinite(surface.metallic) ? clamp(surface.metallic, 0.0, 1.0) : 0.0);
    terminal.opacity = float16_t(isFinite(surface.opacity) ? clamp(surface.opacity, 0.0, 1.0) : 1.0);
    terminal.parallaxContinuousUv = surface.parallaxContinuousUv;
    terminal.parallaxDepth = surface.parallaxDepth;
    terminal.parallaxMaxDepthWorld = surface.parallaxMaxDepthWorld;
    return terminal;
}

bool hasPathTerminalFlag(PathTerminal terminal, uint flag) {
    return (terminal.metadata & flag) != 0u;
}

bool isPathTerminalValid(PathTerminal terminal) {
    return hasPathTerminalFlag(terminal, ADV_TERMINAL_FLAG_VALID);
}

uint pathTerminalCategory(PathTerminal terminal) {
    return (terminal.metadata >> ADV_TERMINAL_CATEGORY_SHIFT) & ADV_TERMINAL_CATEGORY_MASK;
}

#endif
