#version 460
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_buffer_reference2 : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

#include "scene/resources.glsl"

struct RenderIndirectMetadataHeader {
    uint drawCount;
    uint metadataOffsetBytes;
    uint metadataStrideBytes;
    uint commandStrideBytes;
    uint chunkInstanceIndexBase;
    uint chunkGeometryAddressIndexBase;
    uint entityInstanceCount;
    uint entityGeometryCount;
    uint chunkInstanceCount;
    uint chunkGeometrySlotCount;
};

struct RenderIndirectDrawMetadata {
    uint objectType;
    uint objectIndex;
    uint geometryIndex;
    uint instanceIndex;
    uint geometryAddressIndex;
    uint vertexCount;
    uint indexCount;
    uint layerOrder;
    uint renderLayerHashLow;
    uint renderLayerHashHigh;
    uint flags;
    uint reserved;
};

layout(set = 6, binding = 0, std430) readonly buffer HandRasterMetadata {
    RenderIndirectMetadataHeader header;
    RenderIndirectDrawMetadata metadata[];
}
handRasterMetadata;

const uint HAND_DRAW_FLAG = 1u << 1u;

layout(location = 0) out vec3 outRelativePosition;
layout(location = 1) out vec3 outPreviousRelativePosition;
layout(location = 2) out vec3 outBarycentric;
layout(location = 3) flat out uint outTextureId;
layout(location = 4) out vec4 outColorLayer;
layout(location = 5) out vec2 outTextureUv;
layout(location = 6) flat out uint outPackedData;
layout(location = 7) flat out uint outInstanceMask;
layout(location = 8) flat out uint outInstanceIndex;
layout(location = 9) flat out uint outGeometryBufferIndex;
layout(location = 10) flat out uint outPrimitiveId;

vec3 transformPoint(AccelerationStructureInstance instance, vec3 position) {
    return vec3(dot(instance.transform0.xyz, position) + instance.transform0.w,
                dot(instance.transform1.xyz, position) + instance.transform1.w,
                dot(instance.transform2.xyz, position) + instance.transform2.w);
}

void emitInvalidVertex() {
    outRelativePosition = vec3(0.0);
    outPreviousRelativePosition = vec3(0.0);
    outBarycentric = vec3(0.0);
    outTextureId = 0u;
    outColorLayer = vec4(0.0);
    outTextureUv = vec2(0.0);
    outPackedData = 0u;
    outInstanceMask = 0u;
    outInstanceIndex = 0u;
    outGeometryBufferIndex = 0u;
    outPrimitiveId = 0u;
    gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
}

void main() {
    uint drawIndex = gl_BaseInstance;
    if (drawIndex >= handRasterMetadata.header.drawCount) {
        emitInvalidVertex();
        return;
    }

    RenderIndirectDrawMetadata drawMetadata = handRasterMetadata.metadata[drawIndex];
    if (drawMetadata.objectType != 1u || (drawMetadata.flags & HAND_DRAW_FLAG) == 0u ||
        drawMetadata.instanceIndex >= handRasterMetadata.header.entityInstanceCount ||
        drawMetadata.geometryAddressIndex >= handRasterMetadata.header.entityGeometryCount ||
        drawMetadata.vertexCount == 0u || gl_VertexIndex >= drawMetadata.indexCount) {
        emitInvalidVertex();
        return;
    }

    IndexBuffer indexBuffer = IndexBuffer(indexBufferAddrs.addrs[drawMetadata.geometryAddressIndex]);
    uint localVertexIndex = indexBuffer.indices[gl_VertexIndex];
    if (localVertexIndex >= drawMetadata.vertexCount) {
        emitInvalidVertex();
        return;
    }

    PositionVertex positionVertex = loadPositionVertex(drawMetadata.geometryAddressIndex, localVertexIndex);
    MaterialVertex materialVertex = loadMaterialVertex(drawMetadata.geometryAddressIndex, localVertexIndex);
    AccelerationStructureInstance instance = tlasInstances.instances[drawMetadata.instanceIndex];
    vec3 relativePosition = transformPoint(instance, positionVertex.pos);
    uint corner = gl_VertexIndex % 3u;
    vec3 barycentric = corner == 0u ? vec3(1.0, 0.0, 0.0) : corner == 1u ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0);
    vec3 previousRelativePosition;
    if (!loadPreviousGeometryWorldPosition(drawMetadata.geometryAddressIndex, gl_VertexIndex / 3u,
                                           drawMetadata.instanceIndex, barycentric, positionVertex.pos,
                                           previousRelativePosition)) {
        previousRelativePosition = relativePosition + vec3(worldUBO.cameraPos.xyz - lastWorldUBO.cameraPos.xyz);
    }
    outBarycentric = barycentric;
    outRelativePosition = relativePosition;
    outPreviousRelativePosition = previousRelativePosition;
    outTextureId = materialVertex.textureID;
    outColorLayer = materialVertex.colorLayer;
    outTextureUv = materialVertex.textureUV;
    outPackedData = materialVertex.packedData;
    outInstanceMask = loadInstanceMask(drawMetadata.instanceIndex);
    outInstanceIndex = drawMetadata.instanceIndex;
    outGeometryBufferIndex = drawMetadata.geometryAddressIndex;
    outPrimitiveId = gl_VertexIndex / 3u;

    vec4 clipPosition = worldUBO.cameraProjMat * worldUBO.cameraEffectedViewMat * vec4(relativePosition, 1.0);
    vec2 jitterNdc = worldUBO.cameraJitter * (2.0 / vec2(RENDER_WIDTH, RENDER_HEIGHT));
    clipPosition.xy -= jitterNdc * clipPosition.w;
    gl_Position = clipPosition;
}
