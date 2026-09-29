#ifndef ADV_PATH_PRIMARY_GUIDES_GLSL
#define ADV_PATH_PRIMARY_GUIDES_GLSL

#include "path/primary/terminal.glsl"

void storePrimaryTransmissionGuide(ivec2 flatPixel,
                                   vec4 firstInterfaceAlbedoMetallic,
                                   float firstInterfaceOpacity,
                                   bool isFirstInterfaceWater,
                                   uint transmissionMedium,
                                   Surface transmittedSurface) {
    vec3 albedo = transmittedSurface.albedo;
    if (!isFinite(albedo)) { albedo = vec3(0.0); }
    float metallic = isFinite(transmittedSurface.metallic) ? clamp(transmittedSurface.metallic, 0.0, 1.0) : 0.0;
    if (isFirstInterfaceWater) {
        albedo *= segmentTransmittance(transmissionMedium, transmittedSurface.rayDistance);
    } else {
        float opacity = clamp(firstInterfaceOpacity, 0.0, 1.0);
        vec3 interfaceAlbedo = isFinite(firstInterfaceAlbedoMetallic.rgb) ?
                                   clamp(firstInterfaceAlbedoMetallic.rgb, vec3(0.0), vec3(1.0)) :
                                   vec3(0.0);
        float interfaceMetallic =
            isFinite(firstInterfaceAlbedoMetallic.a) ? clamp(firstInterfaceAlbedoMetallic.a, 0.0, 1.0) : 0.0;
        albedo = mix(albedo, interfaceAlbedo, opacity);
        metallic = mix(metallic, interfaceMetallic, opacity);
    }
    imageStore(primaryDiffuseAlbedoImage, flatPixel, vec4(clamp(albedo, vec3(0.0), vec3(1.0)), metallic));
}

void storePrimaryGuides(
    ivec2 flatPixel, vec4 albedoMetallic, vec4 specularAlbedo, vec4 normalRoughness, vec2 motion, float linearDepth) {
    imageStore(primaryDiffuseAlbedoImage, flatPixel,
               vec4(clamp(albedoMetallic.rgb, vec3(0.0), vec3(1.0)), clamp(albedoMetallic.a, 0.0, 1.0)));
    imageStore(primarySpecularAlbedoImage, flatPixel,
               vec4(clamp(specularAlbedo.rgb, vec3(0.0), vec3(1.0)), clamp(specularAlbedo.a, 0.0, 0.5)));
    imageStore(primaryNormalRoughnessImage, flatPixel, normalRoughness);
    imageStore(primaryMotionVectorImage, flatPixel, vec4(motion, 0.0, 0.0));
    imageStore(primaryLinearDepthImage, flatPixel, vec4(linearDepth));
    imageStore(primaryFirstHitDepthImage, flatPixel, vec4(linearDepth));
}

void storePrimarySpecularGuide(ivec2 flatPixel, vec3 specularAlbedo) {
    imageStore(primarySpecularAlbedoImage, flatPixel, vec4(clamp(specularAlbedo, vec3(0.0), vec3(1.0)), 0.0));
}

bool primaryUsesHalfRateIndirect() {
#if MCVR_USE_NRD
    return uint(ADV_NRD_MODE) == 2u;
#else
    return false;
#endif
}

ivec2 primaryIndirectPairOrigin(ivec2 pixel) {
    return ivec2(pixel.x & ~1, pixel.y);
}

ivec2 primaryIndirectPairRepresentative(ivec2 pixel, ivec2 extent) {
    ivec2 origin = primaryIndirectPairOrigin(pixel);
    int offset = int((uint(ADV_INDIRECT_PHASE) ^ (uint(origin.y) & 1u)) & 1u);
    return ivec2(min(origin.x + offset, extent.x - 1), origin.y);
}

bool halfRateSplitActionEvenField(CheckerCoordinate checker, ivec2 extent, bool preferCloudSurface) {
    ivec2 pairOrigin = primaryIndirectPairOrigin(checker.flatPixel);
    if (pairOrigin.x + 1 >= extent.x) { return checker.isEvenField; }
    bool representative = all(equal(checker.flatPixel, primaryIndirectPairRepresentative(pairOrigin, extent)));
    if (preferCloudSurface) { return !representative; }
    uint seed = xxhash32(uvec3(uint(pairOrigin.x >> 1), uint(pairOrigin.y), worldUBO.seed ^ 0x53504c54u));
    bool representativeEvenField = (seed & 1u) == 0u;
    return representative ? representativeEvenField : !representativeEvenField;
}

void storeInvalidPathOutputs(ivec2 packedPixel, ivec2 flatPixel) {
    storePrimaryGuides(flatPixel, vec4(0.0), vec4(0.0), vec4(0.0, 0.0, 0.0, 1.0), vec2(0.0), ADV_PRIMARY_FP16_MAX);
    imageStore(pathBaseEmissionImage, flatPixel, vec4(0.0));
#if MCVR_USE_NRD_SEPARATE_DIRECT
    imageStore(directLightGuideNormalRoughnessImage, flatPixel, vec4(0.0));
    imageStore(directLightGuideMotionDepthImage, flatPixel, vec4(0.0));
#endif
    storePathRecord(packedPixel, invalidPathRecord());
}

#if MCVR_USE_NRD_SEPARATE_DIRECT
void storePrimaryDirectGuide(ivec2 flatPixel,
                             vec3 normal,
                             float roughness,
                             vec2 motion,
                             float depth,
                             float previousDepth,
                             bool isTerminal,
                             bool isValid) {
    if (isValid) {
        imageStore(directLightGuideNormalRoughnessImage, flatPixel,
                   vec4(clamp(normal, vec3(-1.0), vec3(1.0)), clamp(roughness, 0.0, 1.0) + (isTerminal ? 2.0 : 0.0)));
        imageStore(directLightGuideMotionDepthImage, flatPixel,
                   vec4(isFinite(motion) ? motion : vec2(0.0), depth, previousDepth));
    } else {
        imageStore(directLightGuideNormalRoughnessImage, flatPixel, vec4(0.0));
        imageStore(directLightGuideMotionDepthImage, flatPixel, vec4(0.0));
    }
}

bool projectCurrentPosition(vec3 position, vec2 resolution, out vec2 pixel, out float viewDepth) {
    pixel = vec2(0.0);
    viewDepth = ADV_PRIMARY_FP16_MAX;
    vec4 view = worldUBO.cameraEffectedViewMat * vec4(position, 1.0);
    if (!isFinite(view) || view.z >= -1e-6) { return false; }
    viewDepth = -view.z;
    vec4 clip = worldUBO.cameraProjMat * view;
    if (!isFinite(clip) || clip.w <= 1e-8) { return false; }
    pixel = (clip.xy / clip.w * 0.5 + 0.5) * resolution;
    return isFinite(pixel) && isFinite(viewDepth);
}
#endif

#endif
