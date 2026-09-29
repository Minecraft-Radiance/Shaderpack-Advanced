#ifndef ADV_LIGHTING_RESTIR_LIGHT_SAMPLE_GLSL
#define ADV_LIGHTING_RESTIR_LIGHT_SAMPLE_GLSL

#include "lighting/restir/target.glsl"

bool isRestirSourceIdLess(uvec2 a, uvec2 b) {
    return a.y < b.y || (a.y == b.y && a.x < b.x);
}

bool relocateRestirEntityLight(uvec2 sourceId, inout uint lightIndex, inout uint chunkIndex, out PackedLight light) {
    ChunkLights globalMetadata = chunkLights[0];
    uint lightCount = globalMetadata.globalEntityLightCount;
    if (lightCount == 0u || globalMetadata.globalEntityLightBufferAddress == 0ul) { return false; }

    PackedLightBuffer globalLights = PackedLightBuffer(globalMetadata.globalEntityLightBufferAddress);
    uint lower = 0u;
    uint upper = lightCount;
    while (lower < upper) {
        uint middle = (lower + upper) >> 1u;
        uvec2 middleId = packedLightSourceId(globalLights.lights[middle]);
        if (isRestirSourceIdLess(middleId, sourceId)) {
            lower = middle + 1u;
        } else {
            upper = middle;
        }
    }
    if (lower >= lightCount) { return false; }

    PackedLight relocated = globalLights.lights[lower];
    if (any(notEqual(packedLightSourceId(relocated), sourceId))) { return false; }
    uint relocatedChunkIndex = packedEntityLightChunkIndex(relocated);
    uint relocatedEntityIndex = packedEntityLightLocalIndex(relocated);
    ivec3 sectionCoordinate;
    ivec3 chunkOrigin;
    if (!findSectionCoordinate(relocatedChunkIndex, worldUBO, sectionCoordinate, chunkOrigin) ||
        !isRestirSectionWithinPlayerRange(sectionCoordinate, worldUBO)) {
        return false;
    }
    ChunkLights relocatedChunk = chunkLights[relocatedChunkIndex];
    if (!matchesChunkLights(relocatedChunk, chunkOrigin) ||
        relocatedEntityIndex >= getEntityLightCount(relocatedChunk)) {
        return false;
    }

    uint relocatedLightIndex = getStaticLightCount(relocatedChunk) + relocatedEntityIndex;
    PackedLight verified;
    if (!loadPackedLight(relocatedChunk, relocatedLightIndex, verified) ||
        any(notEqual(packedLightSourceId(verified), sourceId))) {
        return false;
    }
    light = verified;
    lightIndex = relocatedLightIndex;
    chunkIndex = relocatedChunkIndex;
    return true;
}

bool loadRestirSourceLight(inout uint lightIndex, inout uint chunkIndex, uvec2 sourceId, out PackedLight light) {
    if (lightIndex == ADV_INVALID_LIGHT_SOURCE_INDEX || chunkIndex == ADV_INVALID_LIGHT_SOURCE_INDEX) {
        return relocateRestirEntityLight(sourceId, lightIndex, chunkIndex, light);
    }
    ivec3 sectionCoordinate;
    ivec3 chunkOrigin;
    if (findSectionCoordinate(chunkIndex, worldUBO, sectionCoordinate, chunkOrigin) &&
        isRestirSectionWithinPlayerRange(sectionCoordinate, worldUBO)) {
        ChunkLights chunk = chunkLights[chunkIndex];
        if (matchesChunkLights(chunk, chunkOrigin) && lightIndex < getChunkLightCount(chunk) &&
            loadPackedLight(chunk, lightIndex, light) && all(equal(packedLightSourceId(light), sourceId))) {
            return true;
        }
    }
    return relocateRestirEntityLight(sourceId, lightIndex, chunkIndex, light);
}

bool isRestirEntitySource(RestirReservoir reservoir) {
    if (!reservoir.isValid || reservoir.sourceLightIndex == ADV_INVALID_LIGHT_SOURCE_INDEX ||
        reservoir.sourceChunkIndex == ADV_INVALID_LIGHT_SOURCE_INDEX) {
        return false;
    }
    ivec3 sectionCoordinate;
    ivec3 chunkOrigin;
    if (!findSectionCoordinate(reservoir.sourceChunkIndex, worldUBO, sectionCoordinate, chunkOrigin)) { return false; }
    ChunkLights chunk = chunkLights[reservoir.sourceChunkIndex];
    if (!matchesChunkLights(chunk, chunkOrigin)) { return false; }
    uint staticLightCount = getStaticLightCount(chunk);
    return reservoir.sourceLightIndex >= staticLightCount && reservoir.sourceLightIndex < getChunkLightCount(chunk);
}

vec3 packedRestirLightRadiance(PackedLight light) {
    return packedLightRadiance(light) * max(light.radiance.a, 0.0);
}

float restirTriangleArea(vec3 a, vec3 b, vec3 c) {
    return 0.5 * length(cross(b - a, c - a));
}

vec3 restirTrianglePoint(vec3 a, vec3 b, vec3 c, vec2 randomSample) {
    float root = sqrt(clamp(randomSample.x, 0.0, 1.0));
    float b0 = 1.0 - root;
    float b1 = randomSample.y * root;
    return a * b0 + b * b1 + c * (1.0 - b0 - b1);
}

bool resolveRestirLightPoint(PackedLight light, uint sampleParam, out vec3 point, out vec3 normal, out float areaPdf) {
    vec3 p0 = light.p0Area.xyz;
    vec3 p1 = light.p1.xyz;
    vec3 p2 = light.p2.xyz;
    vec3 p3 = light.p3.xyz;
    normal = brdfNormalize(light.normal.xyz, vec3(0.0, 1.0, 0.0));
    vec2 randomSample = unpackRestirSampleXi(sampleParam);
    if (all(equal(p2, p3))) {
        float area = max(light.p0Area.w, 0.0);
        if (area <= 1e-8) {
            areaPdf = 0.0;
            point = p0;
            return false;
        }
        point = restirTrianglePoint(p0, p1, p2, randomSample);
        areaPdf = 1.0 / area;
        return true;
    }

    float area0 = restirTriangleArea(p0, p1, p2);
    float area1 = restirTriangleArea(p0, p2, p3);
    float area = max(area0 + area1, light.p0Area.w);
    if (area <= 1e-8) {
        areaPdf = 0.0;
        point = p0;
        return false;
    }
    bool isSecondTriangle = isRestirSecondTriangle(sampleParam) && area1 > 1e-8;
    point = isSecondTriangle ? restirTrianglePoint(p0, p2, p3, randomSample) :
                               restirTrianglePoint(p0, p1, p2, randomSample);
    areaPdf = 1.0 / area;
    return true;
}

bool sampleRestirLightPoint(
    PackedLight light, inout uint seed, out vec3 point, out vec3 normal, out float areaPdf, out uint sampleParam) {
    vec3 p0 = light.p0Area.xyz;
    vec3 p1 = light.p1.xyz;
    vec3 p2 = light.p2.xyz;
    vec3 p3 = light.p3.xyz;
    normal = brdfNormalize(light.normal.xyz, vec3(0.0, 1.0, 0.0));
    if (all(equal(p2, p3))) {
        float area = max(light.p0Area.w, 0.0);
        if (area <= 1e-8) {
            areaPdf = 0.0;
            point = p0;
            return false;
        }
        vec2 randomSample = vec2(rand(seed), rand(seed));
        sampleParam = packRestirSampleParam(false, randomSample);
        point = restirTrianglePoint(p0, p1, p2, randomSample);
        areaPdf = 1.0 / area;
        return true;
    }

    float area0 = restirTriangleArea(p0, p1, p2);
    float area1 = restirTriangleArea(p0, p2, p3);
    float area = max(area0 + area1, light.p0Area.w);
    if (area <= 1e-8) {
        areaPdf = 0.0;
        point = p0;
        return false;
    }
    bool isSecondTriangle = !(area1 <= 1e-8 || rand(seed) * area < area0);
    vec2 randomSample = vec2(rand(seed), rand(seed));
    sampleParam = packRestirSampleParam(isSecondTriangle, randomSample);
    point = isSecondTriangle ? restirTrianglePoint(p0, p2, p3, randomSample) :
                               restirTrianglePoint(p0, p1, p2, randomSample);
    areaPdf = 1.0 / area;
    return true;
}

#endif
