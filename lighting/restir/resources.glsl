#ifndef ADV_LIGHTING_RESTIR_RESOURCES_GLSL
#define ADV_LIGHTING_RESTIR_RESOURCES_GLSL

#include "core/checkerboard.glsl"
#include "path/state.glsl"
#include "lighting/bsdf.glsl"
#include "lighting/emitters.glsl"
#include "lighting/restir/stability.glsl"

#ifndef ADV_RESTIR_INITIAL_SAMPLES
#    define ADV_RESTIR_INITIAL_SAMPLES 8
#endif
#ifndef ADV_RESTIR_INITIAL_DISOCCLUSION_SAMPLES
#    define ADV_RESTIR_INITIAL_DISOCCLUSION_SAMPLES 16
#endif
#ifndef ADV_RESTIR_SPATIAL_SAMPLES
#    define ADV_RESTIR_SPATIAL_SAMPLES 2
#endif
#ifndef ADV_RESTIR_SPATIAL_RADIUS
#    define ADV_RESTIR_SPATIAL_RADIUS 24
#endif
#ifndef ADV_RESTIR_SPATIAL_DISOCCLUSION_SAMPLES
#    define ADV_RESTIR_SPATIAL_DISOCCLUSION_SAMPLES 8
#endif
#ifndef ADV_RESTIR_TEMPORAL_CONFIDENCE_CAP
#    define ADV_RESTIR_TEMPORAL_CONFIDENCE_CAP 1.0
#endif
#ifndef ADV_RESTIR_DIRECT_LIGHT_STRENGTH
#    define ADV_RESTIR_DIRECT_LIGHT_STRENGTH 1.0
#endif
#ifndef ADV_RESTIR_FRAME_PING_INPUT
#    define ADV_RESTIR_FRAME_PING_INPUT true
#endif
#ifndef ADV_RESTIR_HISTORY_READY
#    define ADV_RESTIR_HISTORY_READY false
#endif
#ifndef MCVR_USE_DLSSRR
#    define MCVR_USE_DLSSRR 0
#endif

#if MCVR_USE_DLSSRR
#    undef ADV_RESTIR_RESOLUTION_MODE
#    define ADV_RESTIR_RESOLUTION_MODE 1
#elif !defined(ADV_RESTIR_RESOLUTION_MODE)
#    define ADV_RESTIR_RESOLUTION_MODE 0
#endif

const float ADV_RESTIR_TEMPORAL_CONFIDENCE_SCALE = 0.5;
const float ADV_RESTIR_DYNAMIC_PREVIOUS_CARRY_MAX = 2.0;
const float ADV_RESTIR_INACTIVE_CONFIDENCE_DECAY = 0.25;
const float ADV_RESTIR_INACTIVE_MIN_CONFIDENCE = 0.125;
const float ADV_RESTIR_CHECKER_REUSE_CONFIDENCE_CAP = 1.0;
const float ADV_RESTIR_LOW_CONFIDENCE_THRESHOLD = 2.0;
const float ADV_RESTIR_STABLE_CONFIDENCE_RATIO = 0.75;
const float ADV_RESTIR_TEMPORAL_PLANE_TOLERANCE = 0.15;
const float ADV_RESTIR_TEMPORAL_NORMAL_THRESHOLD = 0.8;
const float ADV_RESTIR_TEMPORAL_MIN_TANGENT_TOLERANCE = 0.35;
const float ADV_RESTIR_TEMPORAL_TANGENT_PIXEL_SCALE = 3.0;
const float ADV_RESTIR_TEMPORAL_PLANE_MOTION_SCALE = 0.05;
const float ADV_RESTIR_TEMPORAL_MIN_TANGENT_MOTION_SCALE = 0.25;
const float ADV_RESTIR_TEMPORAL_TANGENT_MOTION_SCALE = 1.5;
const float ADV_RESTIR_SPATIAL_NAIVE_M_THRESHOLD = 2.0;
const float ADV_RESTIR_SPATIAL_BOOST_NAIVE_MERGE_COUNT = 0.5;
const float ADV_RESTIR_SPATIAL_STABLE_MERGE_COUNT = 0.5;
const float ADV_RESTIR_SPATIAL_PLANE_TOLERANCE = 0.10;
const float ADV_RESTIR_SPATIAL_MIN_TANGENT_TOLERANCE = 0.25;
const float ADV_RESTIR_SPATIAL_TANGENT_PIXEL_SCALE = 3.0;
const float ADV_RESTIR_SPATIAL_NORMAL_THRESHOLD = 0.8;
const float ADV_RESTIR_VISIBILITY_DISTANCE_SHRINK = 0.002;

const uint ADV_RESTIR_SOURCE_INDEX_MASK = 0xffffu;
const uint ADV_RESTIR_CONFIDENCE_SHIFT = 16u;
const uint ADV_RESTIR_SAMPLE_U_MASK = 0xffffu;
const uint ADV_RESTIR_SAMPLE_V_MASK = 0x7fffu;
const uint ADV_RESTIR_SAMPLE_V_SHIFT = 16u;
const uint ADV_RESTIR_SAMPLE_TRIANGLE_BIT = 1u << 31u;

layout(set = 5, binding = ADV_RESTIR_RESERVOIR_BINDING, rgba32ui) uniform uimage2DArray restirReservoirImage;
layout(set = 5, binding = ADV_RESTIR_SURFACE_KEY_BINDING, rgba32ui) uniform uimage2DArray restirSurfaceKeyImage;
layout(set = 5, binding = ADV_RESTIR_SPATIAL_BINDING, rgba32ui) uniform uimage2DArray restirSpatialImage;

struct RestirTarget {
    bool isValid;
    bool isSplit;
    bool isSecondary;
    vec3 position;
    ParallaxState parallax;
    vec3 geometryNormal;
    vec3 shadingNormal;
    vec3 viewDirection;
    vec3 albedo;
    vec3 f0;
    vec3 throughput;
    float roughness;
    float metallic;
    float opacity;
};

struct RestirReservoir {
    bool isValid;
    vec3 point;
    vec3 normal;
    vec3 radiance;
    float targetFunction;
    float contributionWeight;
    float confidence;
    uint sampleParam;
    uvec2 sourceId;
    uint sourceLightIndex;
    uint sourceChunkIndex;
};

struct RestirReservoirHeader {
    bool isValid;
    float confidence;
    uvec4 raw;
};

struct RestirCandidate {
    bool isValid;
    vec3 point;
    vec3 normal;
    vec3 radiance;
    float targetFunction;
    float inverseProposalPdf;
    uint sampleParam;
    uvec2 sourceId;
    uint sourceLightIndex;
    uint sourceChunkIndex;
};

struct RestirSurfaceKey {
    bool isValid;
    vec3 worldPosition;
    vec3 normal;
};

struct RestirReservoirMerge {
    bool hasSample;
    RestirReservoir selected;
    float weightSum;
};

#endif
