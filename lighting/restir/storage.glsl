#ifndef ADV_LIGHTING_RESTIR_STORAGE_GLSL
#define ADV_LIGHTING_RESTIR_STORAGE_GLSL

#include "lighting/restir/resources.glsl"

int restirReservoirLayer(bool isPingSet, int layer) {
    return (isPingSet ? 2 : 0) + layer;
}

int restirSurfaceKeyLayer(bool isPingSet) {
    return isPingSet ? 1 : 0;
}

uvec4 loadTemporalRestirLayer(ivec2 pixel, bool isPingSet, int layer) {
    return imageLoad(restirReservoirImage, ivec3(pixel, restirReservoirLayer(isPingSet, layer)));
}

void storeTemporalRestirLayer(ivec2 pixel, bool isPingSet, int layer, uvec4 packedLayer) {
    imageStore(restirReservoirImage, ivec3(pixel, restirReservoirLayer(isPingSet, layer)), packedLayer);
}

uint restirCheckerboardPhase() {
    return uint(ADV_RESTIR_PHASE) & 1u;
}

ivec2 restirCheckerboardDispatchExtent(ivec2 resolution) {
    return ivec2((resolution.x + 1) / 2, resolution.y);
}

ivec2 restirCheckerboardPixelForPhase(ivec2 dispatchPixel, uint phase) {
    uint xParity = (phase ^ (uint(dispatchPixel.y) & 1u)) & 1u;
    return ivec2(dispatchPixel.x * 2 + int(xParity), dispatchPixel.y);
}

ivec2 restirActivePixel(ivec2 dispatchPixel) {
    return restirCheckerboardPixelForPhase(dispatchPixel, restirCheckerboardPhase());
}

ivec2 restirInactivePixel(ivec2 dispatchPixel) {
    return restirCheckerboardPixelForPhase(dispatchPixel, restirCheckerboardPhase() ^ 1u);
}

bool isRestirPixelActive(ivec2 pixel) {
    uint parity = (uint(pixel.x) + uint(pixel.y)) & 1u;
    return parity == restirCheckerboardPhase();
}

bool doesRestirPixelMatchPhase(ivec2 pixel, uint phase) {
    return ((uint(pixel.x) + uint(pixel.y)) & 1u) == (phase & 1u);
}

uvec4 loadSpatialRestirLayer(ivec2 pixel, int layer) {
    return imageLoad(restirSpatialImage, ivec3(pixel, layer));
}

void storeSpatialRestirLayer(ivec2 pixel, int layer, uvec4 packedLayer) {
    imageStore(restirSpatialImage, ivec3(pixel, layer), packedLayer);
}

uvec4 loadRestirSurfaceKeyRaw(ivec2 pixel, bool isPingSet) {
    return imageLoad(restirSurfaceKeyImage, ivec3(pixel, restirSurfaceKeyLayer(isPingSet)));
}

void storeRestirSurfaceKeyRaw(ivec2 pixel, bool isPingSet, uvec4 packedKey) {
    imageStore(restirSurfaceKeyImage, ivec3(pixel, restirSurfaceKeyLayer(isPingSet)), packedKey);
}

#endif
