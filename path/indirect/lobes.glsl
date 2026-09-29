#ifndef ADV_PATH_INDIRECT_LOBES_GLSL
#define ADV_PATH_INDIRECT_LOBES_GLSL

#include "core/bindings.glsl"
#include "lighting/bsdf.glsl"

#ifndef MCVR_USE_NRD
#    define MCVR_USE_NRD 0
#endif
#ifndef ADV_NRD_MODE
#    define ADV_NRD_MODE 0
#endif

const uint ADV_NRD_MODE_HALF_RATE_CHECKERBOARD = 2u;

const float ADV_INDIRECT_PROBABILISTIC_MAX_ROUGHNESS = 0.35;

struct LobeSurface {
    PathKey key;
    vec3 shadingNormal;
    vec3 albedo;
    vec3 f0;
    vec3 rayDirection;
    float roughness;
    float metallic;
    float opacity;
};

struct LobeSelection {
    uint lobe;
    float probability;
};

bool isLobeSurfaceShadeable(PathKey key);

bool hasIndirectSample(PathKey key) {
    return isLobeSurfaceShadeable(key) && hasPathRayBudget(pathRayBudgetUsed(key));
}

uint indirectPhase() {
    return uint(ADV_INDIRECT_PHASE) & 1u;
}

bool indirectUsesNrdSignals() {
#if MCVR_USE_NRD

    return true;
#else
    return false;
#endif
}

bool indirectUsesHalfRate() {
#if MCVR_USE_NRD
    return uint(ADV_NRD_MODE) == ADV_NRD_MODE_HALF_RATE_CHECKERBOARD && indirectUsesNrdSignals();
#else
    return false;
#endif
}

ivec2 indirectPairOrigin(ivec2 pixel) {
    return ivec2(pixel.x & ~1, pixel.y);
}

ivec2 indirectPairRepresentative(ivec2 pixel, ivec2 extent) {
    ivec2 origin = indirectPairOrigin(pixel);
    int offset = int((indirectPhase() ^ (uint(origin.y) & 1u)) & 1u);
    return ivec2(min(origin.x + offset, extent.x - 1), origin.y);
}

uint lobePhase(uint phase) {
    return phase & 1u;
}

uint lobeCheckerboardForPhase(ivec2 pixel, uint phase) {
    return (uint(pixel.x) ^ uint(pixel.y) ^ lobePhase(phase)) & 1u;
}

bool indirectUsesCloudLobeMixture() {
    return indirectUsesNrdSignals();
}

bool indirectUsesSplitCarrier(PathKey key) {
    uint flags = pathFlags(key);
    return indirectUsesNrdSignals() && isSplitPath(key) && (flags & ADV_PATH_FLAG_FIRST_HIT_CLOUD) == 0u;
}

uint indirectSplitCarrierLobe(ivec2 pixel, PathKey key) {
    uint flags = pathFlags(key);
    if (indirectUsesHalfRate() && (flags & (ADV_PATH_FLAG_FIRST_HIT_WATER | ADV_PATH_FLAG_FIRST_HIT_GLASS)) != 0u) {
        return (flags & ADV_PATH_FLAG_FIRST_INTERFACE_SPECULAR) != 0u ? 1u : 0u;
    }
    return lobeCheckerboardForPhase(pixel, indirectPhase());
}

float indirectSplitBranchWeight(PathKey key) {
    return indirectUsesSplitCarrier(key) && !indirectUsesHalfRate() ? 0.5 : 1.0;
}

bool indirectUsesFullRateLobes(PathKey key) {
    uint flags = pathFlags(key);
    return isLobeSurfaceShadeable(key) && (flags & ADV_PATH_FLAG_CLOUD) != 0u;
}

#ifndef ADV_PATH_RECORD_WRITE
LobeSurface loadLobeSurface(ivec2 packedPixel) {
    LobeSurface surface;
    vec4 albedoRoughness = imageLoad(pathAlbedoRoughnessImage, packedPixel);
    vec4 f0Metallic = imageLoad(pathF0MetallicImage, packedPixel);
    surface.key = loadPathKey(packedPixel);
    vec4 throughputOpacity = loadPathTransport(packedPixel, surface.key);
    vec3 geometryNormal;
    loadPathNormals(packedPixel, surface.shadingNormal, geometryNormal);
    surface.albedo = albedoRoughness.rgb;
    surface.roughness = albedoRoughness.a;
    surface.f0 = f0Metallic.rgb;
    surface.metallic = f0Metallic.a;
    surface.opacity = throughputOpacity.a;
    surface.rayDirection = imageLoad(pathRayDirectionDepthImage, packedPixel).xyz;
    return surface;
}

#endif

LobeSurface makeLobeSurface(ResolvePath path) {
    LobeSurface surface;
    surface.key = path.key;
    surface.shadingNormal = path.shadingNormal;
    surface.albedo = path.albedo;
    surface.f0 = path.f0;
    surface.rayDirection = path.rayDirection;
    surface.roughness = path.roughness;
    surface.metallic = path.metallic;
    surface.opacity = path.opacity;
    return surface;
}

bool supportsStochasticLobes(PathKey key) {
    uint flags = pathFlags(key);
    uint excludedFlags = ADV_PATH_FLAG_SPLIT | ADV_PATH_FLAG_DYNAMIC | ADV_PATH_FLAG_HAND | ADV_PATH_FLAG_CLOUD |
                         ADV_PATH_FLAG_WATER | ADV_PATH_FLAG_NO_REFLECT | ADV_PATH_FLAG_PORTAL |
                         ADV_PATH_FLAG_FIRST_HIT_WATER | ADV_PATH_FLAG_FIRST_HIT_GLASS | ADV_PATH_FLAG_FIRST_HIT_CLOUD |
                         ADV_PATH_FLAG_FIRST_HIT_DYNAMIC | ADV_PATH_FLAG_FIRST_HIT_HAND |
                         ADV_PATH_FLAG_FIRST_INTERFACE_SPECULAR;
    return (flags & ADV_PATH_FLAG_FIRST_HIT_VALID) != 0u && (flags & excludedFlags) == 0u &&
           pathBounceCount(key) == 0u && pathSurfaceMedium(key) == ADV_MEDIUM_SOLID &&
           pathCategory(key) == ADV_HIT_CATEGORY_DEFAULT;
}

bool usesStochasticLobes(LobeSurface surface) {
    uint flags = pathFlags(surface.key);
    if (!isLobeSurfaceShadeable(surface.key) || !isFinite(surface.roughness)) { return false; }
    if (indirectUsesFullRateLobes(surface.key)) { return false; }
    if (indirectUsesCloudLobeMixture() && (flags & ADV_PATH_FLAG_FIRST_HIT_CLOUD) != 0u) { return true; }
    if (indirectUsesSplitCarrier(surface.key)) { return true; }
    if (!supportsStochasticLobes(surface.key) || !isFinite(surface.opacity) || surface.opacity < 1.0 - 1e-6) {
        return false;
    }

    if (indirectUsesHalfRate()) { return true; }
    return surface.roughness <= ADV_INDIRECT_PROBABILISTIC_MAX_ROUGHNESS;
}

float specularLobeProbability(LobeSurface surface) {
    vec3 normal = brdfNormalize(surface.shadingNormal, vec3(0.0, 1.0, 0.0));
    vec3 view = brdfNormalize(-surface.rayDirection, normal);
    vec3 diffuseWeight = diffuseAlbedo(surface.albedo, surface.metallic);
    vec3 viewFresnel = fresnelSchlick(clamp(surface.f0, vec3(0.0), vec3(1.0)), max(dot(view, normal), 0.0));
    float diffuseEnergy = luminance(diffuseWeight);
    float specularEnergy = luminance(viewFresnel);
    float energySum = diffuseEnergy + specularEnergy;
    if (!isFinite(energySum) || energySum <= 1e-8) { return 0.5; }
    if (diffuseEnergy <= 1e-8) { return 1.0; }
    if (specularEnergy <= 1e-8) { return 0.0; }

    float glossyWeight =
        1.0 - smoothstep(0.08, ADV_INDIRECT_PROBABILISTIC_MAX_ROUGHNESS, clamp(surface.roughness, 0.0, 1.0));
    float minimumSpecularProbability = mix(0.10, 0.75, glossyWeight);
    return clamp(specularEnergy / energySum, minimumSpecularProbability, 0.95);
}

LobeSelection selectLobe(ivec2 pixel, LobeSurface surface) {
    LobeSelection selection;
    if (!usesStochasticLobes(surface)) {
        selection.lobe = indirectUsesHalfRate() ? (((uint(pixel.x) >> 1u) ^ uint(pixel.y) ^ indirectPhase()) & 1u) :
                                                  lobeCheckerboardForPhase(pixel, indirectPhase());
        selection.probability = 0.5;
        return selection;
    }
    float specularProbability = specularLobeProbability(surface);
    uint seed = xxhash32(uvec3(uint(pixel.x), uint(pixel.y), worldUBO.seed ^ 0x4c4f4245u));
    selection.lobe = rand(seed) < specularProbability ? 1u : 0u;
    selection.probability = selection.lobe == 1u ? specularProbability : 1.0 - specularProbability;
    return selection;
}

uint selectedLobe(ivec2 pixel, LobeSurface surface) {
    return selectLobe(pixel, surface).lobe;
}

bool indirectRoutesDiffuseToSpecular(ivec2 pixel, PathKey key) {
    bool useSplitCarrier = indirectUsesSplitCarrier(key);
    return useSplitCarrier && indirectSplitCarrierLobe(pixel, key) == 1u;
}

bool indirectRoutesSpecularToDiffuse(ivec2 pixel, PathKey key) {
    return indirectUsesSplitCarrier(key) && indirectSplitCarrierLobe(pixel, key) == 0u;
}

float lobeEstimatorWeight(LobeSelection selection) {
    if (indirectUsesNrdSignals()) { return 1.0; }
    return 1.0 / max(selection.probability, 1e-5);
}

bool isLobeSurfaceShadeable(PathKey key) {
    uint flags = pathFlags(key);
    return isPathValid(key) && !isSkyPath(key) && (flags & ADV_PATH_FLAG_TERMINAL_SURFACE) != 0u &&
           (flags & (ADV_PATH_FLAG_NO_REFLECT | ADV_PATH_FLAG_PORTAL)) == 0u;
}

#endif
