#ifndef ADV_LIGHTING_CACHE_SHARC_GLSL
#define ADV_LIGHTING_CACHE_SHARC_GLSL

#ifndef USE_SHARC
#    define USE_SHARC 0
#endif
#ifndef SHARC_UPDATE
#    define SHARC_UPDATE 0
#endif
#ifndef SHARC_QUERY
#    define SHARC_QUERY 0
#endif

#if USE_SHARC
#    define SHARC_ENABLE_GLSL 1
#    define SHARC_ENABLE_64_BIT_ATOMICS 1
#    include "extern/sharc/include/SharcGlsl.h"
#    include "extern/sharc/include/SharcCommon.h"

struct SharcConfig {
    uvec2 hashEntriesAddress;
    uvec2 lockAddress;
    uvec2 accumulationAddress;
    uvec2 resolvedAddress;
    vec4 cameraPosition;
    vec4 cameraPositionPrev;
    float sceneScale;
    float radianceScale;
    uint accumulationFrameNum;
    uint staleFrameNumMax;
    uint capacity;
    uint frameIndex;
    uint enableAntiFireflyFilter;
    uint useLockBuffer;
    uint debugMode;
    uint updateDownsampleFactor;
    uint resolveBaseEntry;
    uint resolveEntryCount;
    uint resolveFrameStride;
    uint reserved;
};

layout(set = 4, binding = 0) readonly buffer SharcConfigBuffer {
    SharcConfig sharcConfig;
};

SharcParameters makeSharcParameters() {
    HashMapData hashMapData;
    hashMapData.capacity = sharcConfig.capacity;
    hashMapData.hashEntriesBuffer = RWStructuredBuffer_uint64_t(sharcConfig.hashEntriesAddress);
#    if !HASH_GRID_ENABLE_64_BIT_ATOMICS
    hashMapData.lockBuffer = RWStructuredBuffer_uint(sharcConfig.lockAddress);
#    endif

    HashGridParameters gridParameters;
    gridParameters.cameraPosition = sharcConfig.cameraPosition.xyz;
    gridParameters.logarithmBase = SHARC_GRID_LOGARITHM_BASE;
    gridParameters.sceneScale = sharcConfig.sceneScale;
    gridParameters.levelBias = SHARC_GRID_LEVEL_BIAS;

    SharcParameters sharcParameters;
    sharcParameters.gridParameters = gridParameters;
    sharcParameters.hashMapData = hashMapData;
    sharcParameters.radianceScale = sharcConfig.radianceScale;
    sharcParameters.enableAntiFireflyFilter = sharcConfig.enableAntiFireflyFilter != 0;
    sharcParameters.accumulationBuffer = RWStructuredBuffer_SharcAccumulationData(sharcConfig.accumulationAddress);
    sharcParameters.resolvedBuffer = RWStructuredBuffer_SharcPackedData(sharcConfig.resolvedAddress);
    return sharcParameters;
}

bool isSharcCellSafeForQuery(vec3 positionWorld, float hitDistance, float surfaceFootprint) {
    SharcParameters sharcParameters = makeSharcParameters();
    uint level = HashGridGetLevel(positionWorld, sharcParameters.gridParameters);
    float voxelSize = HashGridGetVoxelSize(level, sharcParameters.gridParameters);
    if (hitDistance < voxelSize) { return false; }
    return max(surfaceFootprint, 0.0) > voxelSize;
}

bool sharcQueryRadiance(
    vec3 positionWorld, vec3 normalWorld, float hitDistance, float surfaceFootprint, out vec3 cachedRadiance) {
    cachedRadiance = vec3(0.0);
    SharcParameters sharcParameters = makeSharcParameters();
    if (!isSharcCellSafeForQuery(positionWorld, hitDistance, surfaceFootprint)) { return false; }

    SharcHitData sharcHitData;
    sharcHitData.positionWorld = positionWorld;
    sharcHitData.normalWorld = normalWorld;
    return SharcGetCachedRadiance(sharcParameters, sharcHitData, cachedRadiance, false);
}
#endif

#endif
