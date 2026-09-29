#ifndef ADV_LIGHTING_EMITTERS_GLSL
#define ADV_LIGHTING_EMITTERS_GLSL

#include "common/shared.hpp"
#include "core/bindings.glsl"

#ifndef ADV_RESTIR_EMISSION_SIZE_XZ
#    define ADV_RESTIR_EMISSION_SIZE_XZ 1
#endif
#ifndef ADV_RESTIR_EMISSION_SIZE_Y
#    define ADV_RESTIR_EMISSION_SIZE_Y 1
#endif
#ifndef ADV_RESTIR_RANGE_XZ
#    define ADV_RESTIR_RANGE_XZ 2
#endif
#ifndef ADV_RESTIR_RANGE_Y
#    define ADV_RESTIR_RANGE_Y 1
#endif

const uint ADV_MAX_PACKED_LIGHTS_PER_CHUNK = 65536u;
const uint ADV_INVALID_LIGHT_SOURCE_INDEX = 0xffffffffu;
const float ADV_UNIT_OPEN_UPPER_BOUND = 0.9999999403953552;
const int ADV_RESTIR_NEIGHBORHOOD_CAPACITY = (2 * ADV_RESTIR_EMISSION_SIZE_XZ + 1) *
                                             (2 * ADV_RESTIR_EMISSION_SIZE_XZ + 1) *
                                             (2 * ADV_RESTIR_EMISSION_SIZE_Y + 1);

struct ChunkLights {
    int chunkOriginX;
    int chunkOriginY;
    int chunkOriginZ;
    uint geometryCount;
    uint lightCount;
    uint64_t lightBufferAddress;
    uint getEntityLightCount;
    uint64_t entityLightBufferAddress;
    uint globalEntityLightCount;
    uint64_t globalEntityLightBufferAddress;
};

struct PackedLight {
    vec4 p0Area;
    vec4 p1;
    vec4 p2;
    vec4 p3;
    vec4 normal;
    vec4 radiance;
    vec4 sourceIdData;
};

layout(std430, set = 1, binding = 9) readonly buffer ChunkLightDataBuffer {
    ChunkLights chunkLights[];
};

layout(std430, buffer_reference, buffer_reference_align = 16) readonly buffer PackedLightBuffer {
    PackedLight lights[];
};

struct ChunkLightNeighborhoodEntry {
    uint chunkIndex;
    float probability;
    float cumulativeProbability;
};

struct ChunkLightNeighborhood {
    uvec4 packedHeader;
    ChunkLightNeighborhoodEntry entries[ADV_RESTIR_NEIGHBORHOOD_CAPACITY];
};

#ifdef ADV_RESTIR_PRECOMPUTE_NEIGHBORHOODS
layout(std430, set = 5, binding = ADV_RESTIR_NEIGHBORHOODS_BINDING) buffer ChunkLightNeighborhoodBuffer {
#else
layout(std430, set = 5, binding = ADV_RESTIR_NEIGHBORHOODS_BINDING) readonly buffer ChunkLightNeighborhoodBuffer {
#endif
    ChunkLightNeighborhood chunkLightNeighborhoods[];
};

int lightFloorModulo(int dividend, int divisor) {
    if (divisor <= 0) { return 0; }
    return dividend - divisor * int(floor(float(dividend) / float(divisor)));
}

ivec3 lightSectionOrigin(ivec3 sectionCoordinate) {
    return sectionCoordinate * 16;
}

bool findChunkIndex(ivec3 sectionCoordinate, WorldUBO world, out int chunkIndex, out ivec3 chunkOrigin) {
    int gridSizeX = world.chunkGridInfo.x;
    int gridSizeY = world.chunkGridInfo.y;
    int gridSizeZ = world.chunkGridInfo.z;
    int bottomSection = world.chunkGridInfo.w;
    chunkIndex = -1;
    chunkOrigin = lightSectionOrigin(sectionCoordinate);
    if (gridSizeX <= 0 || gridSizeY <= 0 || gridSizeZ <= 0) { return false; }

    ivec3 storageSection = world.chunkStorageSectionPos.xyz;
    int viewDistance = (gridSizeX - 1) / 2;
    if (sectionCoordinate.y < bottomSection || sectionCoordinate.y >= bottomSection + gridSizeY ||
        abs(sectionCoordinate.x - storageSection.x) > viewDistance ||
        abs(sectionCoordinate.z - storageSection.z) > viewDistance) {
        return false;
    }

    int gridX = lightFloorModulo(sectionCoordinate.x, gridSizeX);
    int gridY = sectionCoordinate.y - bottomSection;
    int gridZ = lightFloorModulo(sectionCoordinate.z, gridSizeZ);
    chunkIndex = (gridZ * gridSizeY + gridY) * gridSizeX + gridX;
    return true;
}

bool findSectionCoordinate(uint chunkIndex, WorldUBO world, out ivec3 sectionCoordinate, out ivec3 chunkOrigin) {
    int gridSizeX = world.chunkGridInfo.x;
    int gridSizeY = world.chunkGridInfo.y;
    int gridSizeZ = world.chunkGridInfo.z;
    int bottomSection = world.chunkGridInfo.w;
    sectionCoordinate = ivec3(0);
    chunkOrigin = ivec3(0);
    if (gridSizeX <= 0 || gridSizeY <= 0 || gridSizeZ <= 0) { return false; }

    uint sizeX = uint(gridSizeX);
    uint sizeY = uint(gridSizeY);
    uint sizeZ = uint(gridSizeZ);
    uint chunkCount = sizeX * sizeY * sizeZ;
    if (chunkIndex >= chunkCount) { return false; }

    int gridX = int(chunkIndex % sizeX);
    int gridY = int((chunkIndex / sizeX) % sizeY);
    int gridZ = int(chunkIndex / (sizeX * sizeY));
    ivec3 storageSection = world.chunkStorageSectionPos.xyz;
    int viewDistance = (gridSizeX - 1) / 2;
    int baseSectionX = storageSection.x - viewDistance;
    int baseSectionZ = storageSection.z - viewDistance;
    sectionCoordinate = ivec3(baseSectionX + lightFloorModulo(gridX - baseSectionX, gridSizeX), bottomSection + gridY,
                              baseSectionZ + lightFloorModulo(gridZ - baseSectionZ, gridSizeZ));
    chunkOrigin = lightSectionOrigin(sectionCoordinate);
    return true;
}

bool isRestirSectionWithinPlayerRange(ivec3 sectionCoordinate, WorldUBO world) {
    ivec3 delta = sectionCoordinate - world.chunkStorageSectionPos.xyz;
    return abs(delta.x) <= ADV_RESTIR_RANGE_XZ && abs(delta.z) <= ADV_RESTIR_RANGE_XZ &&
           abs(delta.y) <= ADV_RESTIR_RANGE_Y;
}

bool isRestirScenePositionWithinPlayerRange(vec3 scenePosition, WorldUBO world) {
    ivec3 sectionCoordinate = ivec3(floor((scenePosition + vec3(world.cameraPos.xyz)) / 16.0));
    return isRestirSectionWithinPlayerRange(sectionCoordinate, world);
}

bool matchesChunkLights(ChunkLights chunk, ivec3 origin) {
    return chunk.chunkOriginX == origin.x && chunk.chunkOriginY == origin.y && chunk.chunkOriginZ == origin.z;
}

uint getStaticLightCount(ChunkLights chunk) {
    return chunk.lightBufferAddress != 0ul ? min(chunk.lightCount, ADV_MAX_PACKED_LIGHTS_PER_CHUNK) : 0u;
}

uint getEntityLightCount(ChunkLights chunk) {
    uint staticCount = getStaticLightCount(chunk);
    return chunk.entityLightBufferAddress != 0ul ?
               min(chunk.getEntityLightCount, ADV_MAX_PACKED_LIGHTS_PER_CHUNK - staticCount) :
               0u;
}

uint getChunkLightCount(ChunkLights chunk) {
    return getStaticLightCount(chunk) + getEntityLightCount(chunk);
}

bool hasChunkLights(ChunkLights chunk) {
    return getChunkLightCount(chunk) > 0u;
}

bool loadPackedLight(ChunkLights chunk, uint lightIndex, out PackedLight light) {
    uint staticCount = getStaticLightCount(chunk);
    if (lightIndex < staticCount) {
        PackedLightBuffer lightBuffer = PackedLightBuffer(chunk.lightBufferAddress);
        light = lightBuffer.lights[lightIndex];
        return true;
    }

    uint entityIndex = lightIndex - staticCount;
    if (entityIndex >= getEntityLightCount(chunk)) { return false; }
    PackedLightBuffer lightBuffer = PackedLightBuffer(chunk.entityLightBufferAddress);
    light = lightBuffer.lights[entityIndex];
    return true;
}

uvec2 packedLightSourceId(PackedLight light) {
    return uvec2(floatBitsToUint(light.sourceIdData.x), floatBitsToUint(light.sourceIdData.y));
}

uint packedEntityLightChunkIndex(PackedLight light) {
    return floatBitsToUint(light.sourceIdData.z);
}

uint packedEntityLightLocalIndex(PackedLight light) {
    return floatBitsToUint(light.sourceIdData.w);
}

vec3 packedLightRadiance(PackedLight light) {
    return max(light.radiance.rgb, vec3(0.0));
}

uint chunkLightNeighborhoodCount(uint chunkIndex) {
    return min(chunkLightNeighborhoods[chunkIndex].packedHeader.x, uint(ADV_RESTIR_NEIGHBORHOOD_CAPACITY));
}

int sampleChunkLightNeighborhood(uint chunkIndex, float randomSample, out float probability) {
    probability = 0.0;
    uint entryCount = chunkLightNeighborhoodCount(chunkIndex);
    if (entryCount == 0u) { return -1; }

    float xi = clamp(randomSample, 0.0, ADV_UNIT_OPEN_UPPER_BOUND);
    uint lower = 0u;
    uint upper = entryCount;
    while (lower < upper) {
        uint middle = (lower + upper) >> 1u;
        float cumulative = chunkLightNeighborhoods[chunkIndex].entries[middle].cumulativeProbability;
        if (xi <= cumulative) {
            upper = middle;
        } else {
            lower = middle + 1u;
        }
    }

    uint entryIndex = min(lower, entryCount - 1u);
    probability = chunkLightNeighborhoods[chunkIndex].entries[entryIndex].probability;
    return int(entryIndex);
}

#endif
