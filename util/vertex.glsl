#ifndef VERTEX_GLSL
#define VERTEX_GLSL

#include "common/shared.hpp"
#include "alpha_mode.glsl"

const uint USE_COLOR_LAYER_BIT = 1u << 0u;
const uint USE_TEXTURE_BIT = 1u << 1u;
const uint USE_OVERLAY_BIT = 1u << 2u;
const uint USE_GLINT_BIT = 1u << 3u;
const uint USE_NORM_BIT = 1u << 4u;
const uint USE_LIGHT_BIT = 1u << 5u;
const uint NO_HEIGHT_SURFACE_BIT = 1u << 6u;
const uint ALPHA_MODE_SHIFT = 8u;
const uint COORDINATE_SHIFT = 12u;
const uint ALBEDO_EMISSION_SHIFT = 16u;
const uint CHUNK_GEOMETRY_BUFFER_INDEX_BIT = 0x80000000u;

#ifndef CONST_ONLY
layout(set = 1, binding = 4) readonly buffer PBRBufferAddr {
    uint64_t addrs[];
}
pbrBufferAddrs;

layout(set = 1, binding = 5) readonly buffer LastPBRBufferAddr {
    uint64_t addrs[];
}
lastPbrBufferAddrs;

layout(std430, buffer_reference, buffer_reference_align = 16) readonly buffer EntityPBRBuffer {
    EntityPBRVertex vertices[];
};

layout(std430, buffer_reference, buffer_reference_align = 8) readonly buffer ChunkPBRBuffer {
    ChunkPBRVertex vertices[];
};

layout(std430, buffer_reference, buffer_reference_align = 16) readonly buffer EntityGeometryInstanceBuffer {
    EntityGeometryInstance data;
};

layout(std430, buffer_reference, buffer_reference_align = 16) readonly buffer EntityGeometryHeaderBuffer {
    EntityGeometryHeader data;
};

layout(std430, buffer_reference, buffer_reference_align = 16) readonly buffer EntityProgramVertexBuffer {
    vec4 channels[];
};

uint64_t entityVertexAddress(uint64_t address) {
    if ((address & uint64_t(1)) == uint64_t(0)) { return address; }
    EntityGeometryHeader data = EntityGeometryHeaderBuffer(address & ~uint64_t(1)).data;
    return uint64_t(data.addressLo) | (uint64_t(data.addressHi) << 32);
}

uint getGeometryBufferIndex(uint instanceID, uint geometryID) {
    uint base = blasOffsets.offsets[instanceID];
    return ((base & ~CHUNK_GEOMETRY_BUFFER_INDEX_BIT) + geometryID) | (base & CHUNK_GEOMETRY_BUFFER_INDEX_BIT);
}

uint geometryAddressIndex(uint geometryBufferIndex) {
    return geometryBufferIndex & ~CHUNK_GEOMETRY_BUFFER_INDEX_BIT;
}

bool isChunkGeometryBufferIndex(uint geometryBufferIndex) {
    return (geometryBufferIndex & CHUNK_GEOMETRY_BUFFER_INDEX_BIT) != 0u;
}

uint markChunkGeometryBufferIndex(uint geometryBufferIndex) {
    return geometryBufferIndex | CHUNK_GEOMETRY_BUFFER_INDEX_BIT;
}

bool hasColorLayer(uint packedData) {
    return (packedData & USE_COLOR_LAYER_BIT) != 0u;
}

bool hasTexture(uint packedData) {
    return (packedData & USE_TEXTURE_BIT) != 0u;
}

bool hasWaterMaterial(MaterialVertex vertex) {
    return !hasTexture(vertex.packedData) && (vertex.textureID == 0xfffffffeu ||
        (vertex.textureID & 0xffff0000u) == 0x800c0000u);
}

bool hasVistaMaterial(MaterialVertex vertex) {
    return !hasTexture(vertex.packedData) && (vertex.textureID & 0xfff00000u) == 0x80000000u;
}

bool hasOverlay(uint packedData) {
    return (packedData & USE_OVERLAY_BIT) != 0u;
}

bool hasGlint(uint packedData) {
    return (packedData & USE_GLINT_BIT) != 0u;
}

bool hasNorm(uint packedData) {
    return (packedData & USE_NORM_BIT) != 0u;
}

bool hasLight(uint packedData) {
    return (packedData & USE_LIGHT_BIT) != 0u;
}

bool hasNoHeightSurface(uint packedData) {
    return (packedData & NO_HEIGHT_SURFACE_BIT) != 0u;
}

uint getAlphaMode(uint packedData) {
    return getSurfaceAlphaMode(packedData);
}

uint getCoordinate(uint packedData) {
    return (packedData >> COORDINATE_SHIFT) & 0xFu;
}

uint packEntityPBRData(EntityPBRVertex vertex) {
    return vertex.packedData;
}

uint packChunkPBRData(ChunkPBRVertex vertex) {
    return vertex.packedData & ~(USE_OVERLAY_BIT | USE_GLINT_BIT);
}

vec2 pbrOctSignNotZero(vec2 value) {
    return vec2(value.x >= 0.0 ? 1.0 : -1.0, value.y >= 0.0 ? 1.0 : -1.0);
}

vec3 unpackPBRNormal(uint packedNormal) {
    vec2 encoded = unpackSnorm2x16(packedNormal);
    vec3 normal = vec3(encoded, 1.0 - abs(encoded.x) - abs(encoded.y));
    if (normal.z < 0.0) { normal.xy = (vec2(1.0) - abs(normal.yx)) * pbrOctSignNotZero(normal.xy); }
    return normalize(normal);
}

vec4 unpackPBRColorLayer(uint packedColor) {
    return unpackUnorm4x8(packedColor);
}

ivec2 unpackPBRU16x2(uint packedValue) {
    return ivec2(int(packedValue & 0xffffu), int((packedValue >> 16u) & 0xffffu));
}

float unpackPBRAlbedoEmission(uint packedData) {
    return unpackHalf2x16(packedData >> ALBEDO_EMISSION_SHIFT).x;
}

vec3 chunkPBRPosition(ChunkPBRVertex vertex) {
    return vec3(vertex.posX, vertex.posY, vertex.posZ);
}

PositionVertex makePositionVertex(EntityPBRVertex vertex) {
    PositionVertex outVertex;
    outVertex.pos = vertex.pos;
    outVertex.pad0 = 0u;
    return outVertex;
}

PositionVertex makePositionVertex(ChunkPBRVertex vertex) {
    PositionVertex outVertex;
    outVertex.pos = chunkPBRPosition(vertex);
    outVertex.pad0 = 0u;
    return outVertex;
}

MaterialVertex makeMaterialVertex(EntityPBRVertex vertex) {
    MaterialVertex outVertex;
    outVertex.norm = unpackPBRNormal(vertex.normalOct);
    outVertex.textureID = vertex.textureID;
    outVertex.colorLayer = unpackPBRColorLayer(vertex.colorRGBA8);
    outVertex.textureUV = vertex.textureUV;
    outVertex.overlayUV = unpackPBRU16x2(vertex.overlayUV);
    outVertex.glintUV = unpackHalf2x16(vertex.glintUVHalf);
    outVertex.glintTexture = vertex.glintTexture;
    outVertex.albedoEmission = unpackPBRAlbedoEmission(vertex.packedData);
    outVertex.lightUV = unpackPBRU16x2(vertex.lightUV);
    outVertex.packedData = packEntityPBRData(vertex);
    outVertex.pad0 = 0u;
    return outVertex;
}

MaterialVertex makeMaterialVertex(ChunkPBRVertex vertex) {
    uint packedData = packChunkPBRData(vertex);
    MaterialVertex outVertex;
    outVertex.norm = unpackPBRNormal(vertex.normalOct);
    outVertex.textureID = vertex.textureID;
    outVertex.colorLayer = unpackPBRColorLayer(vertex.colorRGBA8);
    outVertex.textureUV = vertex.textureUV;
    outVertex.overlayUV = ivec2(0);
    outVertex.glintUV = vec2(0.0);
    outVertex.glintTexture = 0u;
    outVertex.albedoEmission = unpackPBRAlbedoEmission(packedData);
    outVertex.lightUV = unpackPBRU16x2(vertex.lightUV);
    outVertex.packedData = packedData;
    outVertex.pad0 = 0u;
    return outVertex;
}

PositionVertex loadPositionVertex(uint geometryBufferIndex, uint vertexIndex) {
    uint addressIndex = geometryAddressIndex(geometryBufferIndex);
    if (isChunkGeometryBufferIndex(geometryBufferIndex)) {
        ChunkPBRBuffer pbrBufferRef = ChunkPBRBuffer(pbrBufferAddrs.addrs[addressIndex]);
        return makePositionVertex(pbrBufferRef.vertices[vertexIndex]);
    }

    EntityPBRBuffer pbrBufferRef = EntityPBRBuffer(entityVertexAddress(pbrBufferAddrs.addrs[addressIndex]));
    return makePositionVertex(pbrBufferRef.vertices[vertexIndex]);
}

vec3 normalizeEntityProgramNormal(EntityGeometryInstance instance, vec3 normal) {
    mat3 toWorld = mat3(instance.normalToWorld[0].xyz, instance.normalToWorld[1].xyz, instance.normalToWorld[2].xyz);
    mat3 toObject = mat3(instance.normalToObject[0].xyz, instance.normalToObject[1].xyz, instance.normalToObject[2].xyz);
    vec3 transformed = toWorld * normal;
    float magnitude = length(transformed);
    return magnitude > 0.0 ? toObject * (transformed / magnitude) : vec3(0.0);
}

float entityProgramAttribute(EntityGeometryInstanceBuffer instance, uint row,
                             vec4 a, vec4 b, vec4 c, vec4 d) {
    uint base = row * 5u;
    return dot(instance.data.attributes[base], a)
        + dot(instance.data.attributes[base + 1u], b)
        + dot(instance.data.attributes[base + 2u], c)
        + dot(instance.data.attributes[base + 3u], d)
        + instance.data.attributes[base + 4u].x;
}

uvec2 loadMaterialFlagsAndTexture(uint geometryBufferIndex, uint vertexIndex) {
    uint addressIndex = geometryAddressIndex(geometryBufferIndex);
    if (isChunkGeometryBufferIndex(geometryBufferIndex)) {
        ChunkPBRBuffer vertices = ChunkPBRBuffer(pbrBufferAddrs.addrs[addressIndex]);
        return uvec2(packChunkPBRData(vertices.vertices[vertexIndex]), vertices.vertices[vertexIndex].textureID);
    }
    EntityPBRBuffer vertices = EntityPBRBuffer(entityVertexAddress(pbrBufferAddrs.addrs[addressIndex]));
    return uvec2(vertices.vertices[vertexIndex].packedData, vertices.vertices[vertexIndex].textureID);
}

MaterialVertex loadMaterialVertex(uint geometryBufferIndex, uint vertexIndex) {
    uint addressIndex = geometryAddressIndex(geometryBufferIndex);
    if (isChunkGeometryBufferIndex(geometryBufferIndex)) {
        ChunkPBRBuffer pbrBufferRef = ChunkPBRBuffer(pbrBufferAddrs.addrs[addressIndex]);
        return makeMaterialVertex(pbrBufferRef.vertices[vertexIndex]);
    }

    EntityPBRBuffer pbrBufferRef = EntityPBRBuffer(entityVertexAddress(pbrBufferAddrs.addrs[addressIndex]));
    MaterialVertex vertex = makeMaterialVertex(pbrBufferRef.vertices[vertexIndex]);
    uint64_t address = pbrBufferAddrs.addrs[addressIndex];
    if ((address & uint64_t(1)) != uint64_t(0)) {
        EntityGeometryInstanceBuffer instance = EntityGeometryInstanceBuffer(address & ~uint64_t(1));
        EntityInstanceMaterial material = EntityGeometryHeaderBuffer(address & ~uint64_t(1)).data.material;
        if ((material.flags & 2u) != 0u) {
            uint64_t rawAddress = uint64_t(instance.data.rawAddressLo) | (uint64_t(instance.data.rawAddressHi) << 32);
            EntityProgramVertexBuffer raw = EntityProgramVertexBuffer(rawAddress);
            vec4 a = raw.channels[vertexIndex * 4u];
            vec4 b = raw.channels[vertexIndex * 4u + 1u];
            vec4 c = raw.channels[vertexIndex * 4u + 2u];
            vec4 d = raw.channels[vertexIndex * 4u + 3u];
            vertex.colorLayer = vec4(entityProgramAttribute(instance, 0u, a, b, c, d),
                entityProgramAttribute(instance, 1u, a, b, c, d),
                entityProgramAttribute(instance, 2u, a, b, c, d),
                entityProgramAttribute(instance, 3u, a, b, c, d));
            vertex.textureUV = vec2(entityProgramAttribute(instance, 4u, a, b, c, d),
                entityProgramAttribute(instance, 5u, a, b, c, d));
            vertex.overlayUV = ivec2(entityProgramAttribute(instance, 6u, a, b, c, d),
                entityProgramAttribute(instance, 7u, a, b, c, d));
            vertex.lightUV = ivec2(vec2(entityProgramAttribute(instance, 8u, a, b, c, d),
                entityProgramAttribute(instance, 9u, a, b, c, d)) * 256.0);
            vertex.norm = normalizeEntityProgramNormal(instance.data,
                vec3(entityProgramAttribute(instance, 10u, a, b, c, d),
                    entityProgramAttribute(instance, 11u, a, b, c, d),
                    entityProgramAttribute(instance, 12u, a, b, c, d)));
            return vertex;
        }
        if ((material.flags & 4u) != 0u) {
            vertex.norm = normalizeEntityProgramNormal(instance.data, vertex.norm);
            return vertex;
        }
        vertex.colorLayer = (material.flags & 1u) != 0u ? material.color : vertex.colorLayer * material.color;
        vertex.textureUV = vertex.textureUV * material.uvTransform.xy + material.uvTransform.zw;
        if (hasLight(vertex.packedData)) { vertex.lightUV = max(vertex.lightUV, unpackPBRU16x2(material.light)); }
        if (hasOverlay(vertex.packedData)) { vertex.overlayUV = unpackPBRU16x2(material.overlay); }
    }
    return vertex;
}

vec3 loadVertexPosition(uint geometryBufferIndex, uint vertexIndex) {
    return loadPositionVertex(geometryBufferIndex, vertexIndex).pos;
}

vec2 loadVertexTextureUV(uint geometryBufferIndex, uint vertexIndex) {
    uint addressIndex = geometryAddressIndex(geometryBufferIndex);
    if (isChunkGeometryBufferIndex(geometryBufferIndex)) {
        ChunkPBRBuffer pbrBufferRef = ChunkPBRBuffer(pbrBufferAddrs.addrs[addressIndex]);
        return pbrBufferRef.vertices[vertexIndex].textureUV;
    }

    return loadMaterialVertex(geometryBufferIndex, vertexIndex).textureUV;
}

void loadTriangleIndices(uint geometryBufferIndex, uint primitiveID, out uint i0, out uint i1, out uint i2) {
    IndexBuffer indexBuffer = IndexBuffer(indexBufferAddrs.addrs[geometryAddressIndex(geometryBufferIndex)]);
    uint indexBaseID = 3u * primitiveID;
    i0 = indexBuffer.indices[indexBaseID];
    i1 = indexBuffer.indices[indexBaseID + 1u];
    i2 = indexBuffer.indices[indexBaseID + 2u];
}

void loadTrianglePositions(uint geometryBufferIndex,
                           uint i0,
                           uint i1,
                           uint i2,
                           out PositionVertex p0,
                           out PositionVertex p1,
                           out PositionVertex p2) {
    p0 = loadPositionVertex(geometryBufferIndex, i0);
    p1 = loadPositionVertex(geometryBufferIndex, i1);
    p2 = loadPositionVertex(geometryBufferIndex, i2);
}

void loadTriangleMaterial(uint geometryBufferIndex,
                          uint i0,
                          uint i1,
                          uint i2,
                          out MaterialVertex m0,
                          out MaterialVertex m1,
                          out MaterialVertex m2) {
    m0 = loadMaterialVertex(geometryBufferIndex, i0);
    m1 = loadMaterialVertex(geometryBufferIndex, i1);
    m2 = loadMaterialVertex(geometryBufferIndex, i2);
}

void loadTriangle(uint geometryBufferIndex,
                  uint primitiveID,
                  out uint i0,
                  out uint i1,
                  out uint i2,
                  out PositionVertex p0,
                  out PositionVertex p1,
                  out PositionVertex p2,
                  out MaterialVertex m0,
                  out MaterialVertex m1,
                  out MaterialVertex m2) {
    loadTriangleIndices(geometryBufferIndex, primitiveID, i0, i1, i2);
    loadTrianglePositions(geometryBufferIndex, i0, i1, i2, p0, p1, p2);
    loadTriangleMaterial(geometryBufferIndex, i0, i1, i2, m0, m1, m2);
}
#endif

#endif
