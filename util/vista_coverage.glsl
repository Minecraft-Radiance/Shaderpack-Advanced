#ifndef VISTA_COVERAGE_GLSL
#define VISTA_COVERAGE_GLSL

layout(std430, buffer_reference, buffer_reference_align = 4) readonly buffer VistaCoverage {
    uint words[];
};

bool vistaColumnInGrid(WorldUBO world, ivec2 column) {
    ivec2 size = world.chunkGridInfo.xz;
    ivec2 first = world.chunkStorageSectionPos.xz - size / 2;
    return all(greaterThanEqual(column, first)) && all(lessThan(column, first + size));
}

uint vistaColumnFlags(WorldUBO world, VistaCoverage coverage, ivec2 column) {
    ivec3 size = world.chunkGridInfo.xyz;
    ivec2 relative = column - (world.chunkStorageSectionPos.xz - size.xz / 2);
    if (any(greaterThanEqual(uvec2(relative), uvec2(size.xz)))) { return 0u; }
    uint count = uint(size.x * size.z);
    uint offset = (count * uint(size.y) + 31u) / 32u + (count + 31u) / 32u + (count * 4u + 31u) / 32u;
    uint index = uint(relative.y * size.x + relative.x);
    return (coverage.words[offset + index / 4u] >> ((index % 4u) * 8u)) & 63u;
}

bool vistaNearColumnReady(WorldUBO world, VistaCoverage coverage, ivec2 column) {
    return (vistaColumnFlags(world, coverage, column) & 1u) != 0u;
}

bool vistaUsesFallback(WorldUBO world, ivec2 column) {
    uint64_t address = uint64_t(uint(world.vistaCoverage.x)) | (uint64_t(uint(world.vistaCoverage.y)) << 32);
    return address != uint64_t(0) && (vistaColumnFlags(world, VistaCoverage(address), column) & 3u) == 2u;
}

uint vistaColumnBorders(WorldUBO world, VistaCoverage coverage, ivec2 column) {
    return vistaColumnFlags(world, coverage, column) >> 2u;
}

bool vistaHasBorder(WorldUBO world, ivec2 column) {
    uint64_t address = uint64_t(uint(world.vistaCoverage.x)) | (uint64_t(uint(world.vistaCoverage.y)) << 32);
    return address != uint64_t(0) && vistaColumnBorders(world, VistaCoverage(address), column) != 0u;
}

#endif
