#ifndef ADV_LIGHTING_RESTIR_RESERVOIR_GLSL
#define ADV_LIGHTING_RESTIR_RESERVOIR_GLSL

#include "lighting/restir/light_sample.glsl"

RestirReservoir emptyRestirReservoir() {
    RestirReservoir reservoir;
    reservoir.isValid = false;
    reservoir.point = vec3(0.0);
    reservoir.normal = vec3(0.0, 1.0, 0.0);
    reservoir.radiance = vec3(0.0);
    reservoir.targetFunction = 0.0;
    reservoir.contributionWeight = 0.0;
    reservoir.confidence = 0.0;
    reservoir.sampleParam = 0u;
    reservoir.sourceId = uvec2(0u);
    reservoir.sourceLightIndex = ADV_INVALID_LIGHT_SOURCE_INDEX;
    reservoir.sourceChunkIndex = ADV_INVALID_LIGHT_SOURCE_INDEX;
    return reservoir;
}

bool packRestirReservoir(RestirReservoir reservoir, out uvec4 header, out uvec4 body) {
    header = uvec4(0u);
    body = uvec4(0u);
    bool isPackable = reservoir.sourceLightIndex <= ADV_RESTIR_SOURCE_INDEX_MASK &&
                      reservoir.sourceChunkIndex != ADV_INVALID_LIGHT_SOURCE_INDEX;
    uint packedConfidence = packRestirConfidence(reservoir.confidence);
    if (!reservoir.isValid || !isPackable || !isBrdfFinite(reservoir.targetFunction) ||
        !isBrdfFinite(reservoir.contributionWeight) || packedConfidence == 0u) {
        return false;
    }
    header = uvec4(reservoir.sourceId, (packedConfidence << ADV_RESTIR_CONFIDENCE_SHIFT) | reservoir.sourceLightIndex,
                   reservoir.sourceChunkIndex);
    body = uvec4(reservoir.sampleParam, floatBitsToUint(max(reservoir.targetFunction, 0.0)),
                 floatBitsToUint(max(reservoir.contributionWeight, 0.0)), 0u);
    return true;
}

RestirReservoirHeader decodeRestirReservoirHeader(uvec4 raw) {
    float packedConfidence = unpackRestirConfidence(raw.z);
    RestirReservoirHeader header;
    header.isValid =
        isBrdfFinite(packedConfidence) && packedConfidence > 0.0 && raw.w != ADV_INVALID_LIGHT_SOURCE_INDEX;
    header.confidence = header.isValid ? packedConfidence : 0.0;
    header.raw = raw;
    return header;
}

RestirReservoir decodeRestirReservoirBody(uvec4 body, RestirReservoirHeader header) {
    if (!header.isValid) { return emptyRestirReservoir(); }
    RestirReservoir reservoir = emptyRestirReservoir();
    reservoir.isValid = true;
    reservoir.targetFunction = max(uintBitsToFloat(body.y), 0.0);
    reservoir.contributionWeight = max(uintBitsToFloat(body.z), 0.0);
    reservoir.confidence = header.confidence;
    reservoir.sampleParam = body.x;
    reservoir.sourceId = header.raw.xy;
    reservoir.sourceLightIndex = unpackRestirLightIndex(header.raw.z);
    reservoir.sourceChunkIndex = header.raw.w;

    PackedLight sourceLight;
    if (!loadRestirSourceLight(reservoir.sourceLightIndex, reservoir.sourceChunkIndex, reservoir.sourceId,
                               sourceLight)) {
        return emptyRestirReservoir();
    }
    float areaPdf;
    if (!resolveRestirLightPoint(sourceLight, reservoir.sampleParam, reservoir.point, reservoir.normal, areaPdf) ||
        areaPdf <= 1e-8) {
        return emptyRestirReservoir();
    }
    reservoir.radiance = packedRestirLightRadiance(sourceLight);
    reservoir.isValid = isBrdfFinite(reservoir.point) && isBrdfFinite(reservoir.normal) &&
                        isBrdfFinite(reservoir.radiance) && isBrdfFinite(reservoir.targetFunction) &&
                        isBrdfFinite(reservoir.contributionWeight) && reservoir.targetFunction > 1e-8 &&
                        reservoir.contributionWeight > 1e-8;
    return reservoir.isValid ? reservoir : emptyRestirReservoir();
}

void storeTemporalRestirReservoir(ivec2 pixel, bool isPingSet, RestirReservoir reservoir) {
    uvec4 header;
    uvec4 body;
    packRestirReservoir(reservoir, header, body);
    storeTemporalRestirLayer(pixel, isPingSet, 0, header);
    storeTemporalRestirLayer(pixel, isPingSet, 1, body);
}

RestirReservoirHeader loadTemporalRestirReservoirHeader(ivec2 pixel, bool isPingSet) {
    return decodeRestirReservoirHeader(loadTemporalRestirLayer(pixel, isPingSet, 0));
}

RestirReservoir loadTemporalRestirReservoirBody(ivec2 pixel, bool isPingSet, RestirReservoirHeader header) {
    return decodeRestirReservoirBody(loadTemporalRestirLayer(pixel, isPingSet, 1), header);
}

RestirReservoir loadTemporalRestirReservoir(ivec2 pixel, bool isPingSet) {
    RestirReservoirHeader header = loadTemporalRestirReservoirHeader(pixel, isPingSet);
    return loadTemporalRestirReservoirBody(pixel, isPingSet, header);
}

void storeSpatialRestirReservoir(ivec2 pixel, RestirReservoir reservoir) {
    uvec4 header;
    uvec4 body;
    packRestirReservoir(reservoir, header, body);
    storeSpatialRestirLayer(pixel, 0, header);
    storeSpatialRestirLayer(pixel, 1, body);
}

RestirReservoirHeader loadSpatialRestirReservoirHeader(ivec2 pixel) {
    return decodeRestirReservoirHeader(loadSpatialRestirLayer(pixel, 0));
}

RestirReservoir loadSpatialRestirReservoir(ivec2 pixel) {
    RestirReservoirHeader header = loadSpatialRestirReservoirHeader(pixel);
    return decodeRestirReservoirBody(loadSpatialRestirLayer(pixel, 1), header);
}

void storeRestirSurfaceKey(ivec2 pixel, bool isPingSet, vec3 worldPosition, vec3 normal) {
    storeRestirSurfaceKeyRaw(pixel, isPingSet,
                             uvec4(floatBitsToUint(worldPosition), packRestirNormal(normal) ^ 0x80000000u));
}

void clearRestirSurfaceKey(ivec2 pixel, bool isPingSet) {
    storeRestirSurfaceKeyRaw(pixel, isPingSet, uvec4(0u));
}

RestirSurfaceKey loadRestirSurfaceKey(ivec2 pixel, bool isPingSet) {
    uvec4 raw = loadRestirSurfaceKeyRaw(pixel, isPingSet);
    RestirSurfaceKey key;
    key.isValid = any(notEqual(raw, uvec4(0u)));
    key.worldPosition = uintBitsToFloat(raw.xyz);
    key.normal = decodeRestirOctNormal(raw.w ^ 0x80000000u);
    if (!isBrdfFinite(key.worldPosition) || !isBrdfFinite(key.normal)) { key.isValid = false; }
    return key;
}

#endif
