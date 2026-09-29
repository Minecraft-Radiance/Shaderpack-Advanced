#ifndef ADV_LIGHTING_RESTIR_RESAMPLING_GLSL
#define ADV_LIGHTING_RESTIR_RESAMPLING_GLSL

#include "lighting/restir/history.glsl"

bool findRestirNeighborhood(vec3 scenePosition, out uint chunkIndex) {
    chunkIndex = ADV_INVALID_LIGHT_SOURCE_INDEX;
    ivec3 sectionCoordinate = ivec3(floor((scenePosition + vec3(worldUBO.cameraPos.xyz)) / 16.0));
    if (!isRestirSectionWithinPlayerRange(sectionCoordinate, worldUBO)) { return false; }
    int resolvedIndex;
    ivec3 chunkOrigin;
    if (!findChunkIndex(sectionCoordinate, worldUBO, resolvedIndex, chunkOrigin)) { return false; }
    ChunkLights chunk = chunkLights[resolvedIndex];
    if (!matchesChunkLights(chunk, chunkOrigin)) { return false; }
    chunkIndex = uint(resolvedIndex);
    return chunkLightNeighborhoodCount(chunkIndex) > 0u;
}

RestirCandidate makeRestirCandidate(RestirTarget target, inout uint seed, uint centerChunkIndex) {
    RestirCandidate candidate;
    candidate.isValid = false;
    candidate.point = vec3(0.0);
    candidate.normal = vec3(0.0, 1.0, 0.0);
    candidate.radiance = vec3(0.0);
    candidate.targetFunction = 0.0;
    candidate.inverseProposalPdf = 0.0;
    candidate.sampleParam = 0u;
    candidate.sourceId = uvec2(0u);
    candidate.sourceLightIndex = ADV_INVALID_LIGHT_SOURCE_INDEX;
    candidate.sourceChunkIndex = ADV_INVALID_LIGHT_SOURCE_INDEX;

    float chunkProbability;
    int entryIndex = sampleChunkLightNeighborhood(centerChunkIndex, rand(seed), chunkProbability);
    if (entryIndex < 0 || chunkProbability <= 1e-8) { return candidate; }
    uint sourceChunkIndex = chunkLightNeighborhoods[centerChunkIndex].entries[entryIndex].chunkIndex;
    ivec3 sectionCoordinate;
    ivec3 chunkOrigin;
    if (!findSectionCoordinate(sourceChunkIndex, worldUBO, sectionCoordinate, chunkOrigin)) { return candidate; }
    ChunkLights chunk = chunkLights[sourceChunkIndex];
    if (!matchesChunkLights(chunk, chunkOrigin)) { return candidate; }
    uint lightCount = getChunkLightCount(chunk);
    if (lightCount == 0u) { return candidate; }
    uint lightIndex = min(uint(clamp(rand(seed), 0.0, ADV_UNIT_OPEN_UPPER_BOUND) * float(lightCount)), lightCount - 1u);
    PackedLight light;
    if (!loadPackedLight(chunk, lightIndex, light)) { return candidate; }

    float areaPdf;
    if (!sampleRestirLightPoint(light, seed, candidate.point, candidate.normal, areaPdf, candidate.sampleParam) ||
        areaPdf <= 1e-8) {
        return candidate;
    }
    candidate.radiance = packedRestirLightRadiance(light);
    candidate.targetFunction = evaluateRestirTarget(target, candidate.radiance, candidate.point, candidate.normal);
    float proposalPdf = chunkProbability * (1.0 / float(lightCount)) * areaPdf;
    if (!isBrdfFinite(candidate.targetFunction) || !isBrdfFinite(proposalPdf) || candidate.targetFunction <= 1e-8 ||
        proposalPdf <= 1e-8) {
        return candidate;
    }
    candidate.inverseProposalPdf = 1.0 / proposalPdf;
    if (!isBrdfFinite(candidate.inverseProposalPdf)) { return candidate; }
    candidate.isValid = true;
    candidate.sourceId = packedLightSourceId(light);
    candidate.sourceLightIndex = lightIndex;
    candidate.sourceChunkIndex = sourceChunkIndex;
    return candidate;
}

RestirReservoir
generateInitialRestirReservoir(RestirTarget target, ivec2 pixel, uint baseSeed, uint requestedSampleCount) {
    uint centerChunkIndex;
    if (!target.isValid || !findRestirNeighborhood(target.position, centerChunkIndex)) {
        return emptyRestirReservoir();
    }
    uint sampleCount = max(requestedSampleCount, 1u);
    uint candidateSeed = xxhash32(uvec3(baseSeed ^ 0x9e3779b9u, uint(pixel.x), uint(pixel.y)));
    uint selectionSeed = xxhash32(uvec3(baseSeed ^ 0x6d2b79f5u, uint(pixel.x), uint(pixel.y)));
    RestirCandidate selected;
    selected.isValid = false;
    float weightSum = 0.0;
    for (uint sampleIndex = 0u; sampleIndex < sampleCount; ++sampleIndex) {
        RestirCandidate candidate = makeRestirCandidate(target, candidateSeed, centerChunkIndex);
        if (!candidate.isValid) { continue; }
        float weight = candidate.targetFunction * candidate.inverseProposalPdf;
        float nextWeightSum = weightSum + weight;
        if (!isBrdfFinite(weight) || weight <= 1e-8 || !isBrdfFinite(nextWeightSum)) { continue; }
        weightSum = nextWeightSum;
        if (!selected.isValid || rand(selectionSeed) * weightSum < weight) { selected = candidate; }
    }
    if (!selected.isValid || weightSum <= 1e-8 || selected.targetFunction <= 1e-8) { return emptyRestirReservoir(); }

    RestirReservoir reservoir;
    reservoir.isValid = true;
    reservoir.point = selected.point;
    reservoir.normal = selected.normal;
    reservoir.radiance = selected.radiance;
    reservoir.targetFunction = selected.targetFunction;
    reservoir.contributionWeight = weightSum / (float(sampleCount) * selected.targetFunction);
    reservoir.confidence = 1.0;
    reservoir.sampleParam = selected.sampleParam;
    reservoir.sourceId = selected.sourceId;
    reservoir.sourceLightIndex = selected.sourceLightIndex;
    reservoir.sourceChunkIndex = selected.sourceChunkIndex;
    return isBrdfFinite(reservoir.contributionWeight) && reservoir.contributionWeight > 1e-8 ? reservoir :
                                                                                               emptyRestirReservoir();
}

RestirReservoirMerge makeRestirReservoirMerge() {
    RestirReservoirMerge merge;
    merge.hasSample = false;
    merge.weightSum = 0.0;
    merge.selected = emptyRestirReservoir();
    return merge;
}

void mergeRestirReservoir(inout RestirReservoirMerge merge,
                          RestirReservoir reservoir,
                          float targetFunction,
                          float mergeCount,
                          inout uint seed) {
    if (!reservoir.isValid || !isBrdfFinite(targetFunction) || !isBrdfFinite(mergeCount) ||
        !isBrdfFinite(reservoir.contributionWeight) || targetFunction <= 1e-8 || mergeCount <= 1e-8 ||
        reservoir.contributionWeight <= 1e-8) {
        return;
    }
    float weight = mergeCount * targetFunction * reservoir.contributionWeight;
    float nextWeightSum = merge.weightSum + weight;
    if (!isBrdfFinite(weight) || weight <= 1e-8 || !isBrdfFinite(nextWeightSum)) { return; }
    merge.weightSum = nextWeightSum;
    if (!merge.hasSample || rand(seed) * merge.weightSum < weight) {
        merge.selected = reservoir;
        merge.selected.targetFunction = targetFunction;
        merge.hasSample = true;
    }
}

RestirReservoir
finishRestirReservoirMerge(RestirReservoirMerge merge, float normalizationCount, float outputConfidence) {
    if (!merge.hasSample || !isBrdfFinite(merge.weightSum) || !isBrdfFinite(normalizationCount) ||
        !isBrdfFinite(outputConfidence) || !isBrdfFinite(merge.selected.targetFunction) || merge.weightSum <= 1e-8 ||
        normalizationCount <= 1e-8 || merge.selected.targetFunction <= 1e-8) {
        return emptyRestirReservoir();
    }
    RestirReservoir reservoir = merge.selected;
    reservoir.isValid = true;
    reservoir.confidence = max(outputConfidence, 0.0);
    reservoir.contributionWeight = merge.weightSum / (normalizationCount * reservoir.targetFunction);
    return isBrdfFinite(reservoir.contributionWeight) && reservoir.contributionWeight > 1e-8 ? reservoir :
                                                                                               emptyRestirReservoir();
}

bool buildRestirShadowRay(RestirTarget target,
                          vec3 lightPoint,
                          vec3 lightNormal,
                          out vec3 origin,
                          out vec3 direction,
                          out float maximumDistance) {
    vec3 lightScenePosition = lightPoint - vec3(worldUBO.cameraPos.xyz);
    vec3 lightVector = lightScenePosition - target.position;
    float distanceSquared = dot(lightVector, lightVector);
    if (!target.isValid || !isBrdfFinite(distanceSquared) || distanceSquared <= 1e-8) { return false; }
    direction = lightVector * inversesqrt(distanceSquared);
    if (!isBrdfFinite(direction) || dot(direction, target.geometryNormal) <= 0.0 ||
        dot(lightNormal, -direction) <= 1e-6) {
        return false;
    }
    vec3 exitPosition = target.position;
    vec3 exitNormal = target.geometryNormal;
    if (!target.isSecondary) {
        if (!resolveParallaxStateExit(target.parallax, target.position, target.geometryNormal, direction, exitPosition,
                                      exitNormal)) {
            return false;
        }
    }
    vec3 biasNormal = dot(direction, exitNormal) >= 0.0 ? exitNormal : -exitNormal;
    origin = exitPosition + biasNormal * 0.0002;
    lightVector = lightScenePosition - origin;
    float distance = length(lightVector);
    if (!isBrdfFinite(distance) || distance <= 1e-8) { return false; }
    direction = lightVector / distance;
    if (dot(lightNormal, -direction) <= 1e-6) { return false; }
    maximumDistance = max(distance - ADV_RESTIR_VISIBILITY_DISTANCE_SHRINK, 0.0001);
    return isBrdfFinite(origin) && isBrdfFinite(direction) && maximumDistance > 0.0;
}

#endif
