#ifndef ADV_OUTPUT_RESOURCES_GLSL
#define ADV_OUTPUT_RESOURCES_GLSL

#include "scene/resources.glsl"
#include "core/checkerboard.glsl"
#include "path/state.glsl"
#include "path/indirect/lobes.glsl"
#include "lighting/bsdf.glsl"
#include "lighting/shadow/water.glsl"
#include "lighting/shadow/payload.glsl"
#include "volume/froxel.glsl"

layout(set = 5, binding = ADV_SKY_RADIANCE_BINDING) uniform samplerCube skyRadianceTexture;
#include "environment/sky.glsl"
#define ADV_CLOUD_JITTER_COORD vec2(gl_GlobalInvocationID.xy)
#include "environment/cloud/shade.glsl"
#undef ADV_CLOUD_JITTER_COORD


layout(set = 5, binding = ADV_SUN_BRDF_DISTANCE_BINDING, rgba16f) readonly uniform image2DArray sunBrdfDistanceImage;
layout(set = 5,
       binding = ADV_TRANSMISSION_RADIANCE_BINDING,
       rgba16f) readonly uniform image2D transmissionRadianceImage;
layout(set = 5,
       binding = ADV_RESTIR_DIFFUSE_RADIANCE_BINDING,
       rgba16f) readonly uniform image2D restirDiffuseRadianceImage;
layout(set = 5,
       binding = ADV_RESTIR_DIFFUSE_DIRECTION_MOMENT_BINDING,
       rgba16f) readonly uniform image2D restirDiffuseDirectionMomentImage;

layout(set = 5, binding = ADV_VOLUME_DIRECT_INTEGRAL_SAMPLED_BINDING) uniform sampler3D volumeDirectIntegralTexture;
layout(set = 5, binding = ADV_VOLUME_INDIRECT_INTEGRAL_SAMPLED_BINDING) uniform sampler3D volumeIndirectIntegralTexture;
layout(set = 5, binding = ADV_VOLUME_TRANSMITTANCE_SAMPLED_BINDING) uniform sampler3D volumeTransmittanceTexture;
layout(set = 5, binding = ADV_VOLUME_FAR_VISIBILITY_SAMPLED_BINDING) uniform sampler2D volumeFarVisibilityTexture;
layout(set = 3, binding = 2, rgba8) uniform image2D outputSpecularAlbedoImage;
layout(set = 3, binding = 3, rgba16f) uniform image2D outputNormalRoughnessImage;
layout(set = 3, binding = 5, r16f) uniform image2D outputLinearDepthImage;
layout(set = 3, binding = 6, r16f) readonly uniform image2D outputFirstHitDepthImage;
layout(set = 3, binding = 7, r16f) uniform image2D outputIndirectSpecularHitDistanceImage;
layout(set = 3, binding = 8, r16f) uniform image2D outputIndirectDiffuseHitDistanceImage;
layout(set = 3, binding = 9, rgba16f) writeonly uniform image2D outputIndirectDiffuseRadianceImage;
layout(set = 3, binding = 10, rgba16f) uniform image2D outputIndirectDiffuseDirectionImage;
layout(set = 3, binding = 11, rgba16f) writeonly uniform image2D outputIndirectSpecularRadianceImage;
layout(set = 3, binding = 12, rgba16f) uniform image2D outputIndirectSpecularDirectionImage;
layout(set = 3, binding = 13, rgba16f) writeonly uniform image2D outputClearImage;
layout(set = 3, binding = 14, rgba16f) writeonly uniform image2D outputRefractionImage;
layout(set = 3, binding = 15, rgba16f) uniform image2D outputBaseEmissionImage;
layout(set = 3, binding = 16, rgba16f) writeonly uniform image2D outputFogImage;
#if MCVR_USE_NRD_SEPARATE_DIRECT
layout(set = 3, binding = 17, rgba16f) writeonly uniform image2D outputDirectDiffuseRadianceImage;
layout(set = 3, binding = 18, rgba16f) writeonly uniform image2D outputDirectSpecularRadianceImage;
layout(set = 3, binding = 19, r16f) uniform image2D directHitDistanceImage;
layout(set = 3, binding = 21, rgba16f) uniform image2D directLightGuideNormalRoughnessImage;
layout(set = 3, binding = 22, rgba16f) uniform image2D directLightGuideMotionDepthImage;
#endif
layout(set = 3, binding = 23, r8ui) writeonly uniform uimage2D outputSegmentationImage;

layout(set = 5,
       binding = ADV_STAR_CLOUD_TRANSMITTANCE_STORAGE_BINDING,
       r16f) writeonly uniform image2D starCloudTransmittanceImage;
#if MCVR_USE_NRD_SEPARATE_DIRECT
#    define ADV_DIRECT_RADIANCE_WRITE 1
#endif
#include "output/signals.glsl"
#include "output/indirect.glsl"

#endif
