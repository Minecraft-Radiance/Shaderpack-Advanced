#ifndef ADV_CORE_CHECKERBOARD_GLSL
#define ADV_CORE_CHECKERBOARD_GLSL

#include "core/bindings.glsl"

struct CheckerCoordinate {
    ivec2 packedPixel;
    ivec2 flatPixel;
    bool isEvenField;
    bool isValid;
};

int fieldWidth(int flatWidth) {
    return (flatWidth + 1) / 2;
}

ivec2 packedExtent(ivec2 flatExtent) {
    return ivec2(2 * fieldWidth(flatExtent.x), flatExtent.y);
}

uint fieldPhase() {
    return uint(ADV_FIELD_PHASE) & 1u;
}

CheckerCoordinate checkerToFlat(ivec2 packed, ivec2 flatExtent) {
    CheckerCoordinate coordinate;
    coordinate.packedPixel = packed;
    int checkerFieldWidth = fieldWidth(flatExtent.x);
    coordinate.isEvenField = packed.x >= checkerFieldWidth;
    int localX = coordinate.isEvenField ? packed.x - checkerFieldWidth : packed.x;
    int parity = (packed.y + int(fieldPhase())) & 1;
    int flatX = coordinate.isEvenField ? 2 * localX + parity : 2 * localX + 1 - parity;
    coordinate.flatPixel = ivec2(flatX, packed.y);
    coordinate.isValid = all(greaterThanEqual(packed, ivec2(0))) && packed.x < 2 * checkerFieldWidth &&
                         packed.y < flatExtent.y && all(greaterThanEqual(coordinate.flatPixel, ivec2(0))) &&
                         all(lessThan(coordinate.flatPixel, flatExtent));
    return coordinate;
}

CheckerCoordinate flatToChecker(ivec2 flatPixel, ivec2 flatExtent) {
    CheckerCoordinate coordinate;
    int checkerFieldWidth = fieldWidth(flatExtent.x);
    int parity = (flatPixel.y + int(fieldPhase())) & 1;
    coordinate.isEvenField = (flatPixel.x & 1) == parity;
    int localX = flatPixel.x / 2;
    coordinate.packedPixel = ivec2(localX + (coordinate.isEvenField ? checkerFieldWidth : 0), flatPixel.y);
    coordinate.flatPixel = flatPixel;
    coordinate.isValid = all(greaterThanEqual(flatPixel, ivec2(0))) && all(lessThan(flatPixel, flatExtent));
    return coordinate;
}

bool isPackedCoordinateInBounds(ivec2 packed, ivec2 flatExtent) {
    ivec2 packedFieldExtent = packedExtent(flatExtent);
    return all(greaterThanEqual(packed, ivec2(0))) && all(lessThan(packed, packedFieldExtent));
}

#endif
