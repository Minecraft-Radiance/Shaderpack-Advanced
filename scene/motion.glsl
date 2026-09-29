#ifndef ADV_SCENE_MOTION_GLSL
#define ADV_SCENE_MOTION_GLSL

#include "util/vertex.glsl"

layout(set = 1, binding = 3, std430) readonly buffer PreviousIndexBufferAddresses {
    uint64_t addrs[];
}
previousIndexBufferAddresses;

layout(set = 1, binding = 8, std430) readonly buffer PreviousObjectToWorldMatrices {
    mat4 matrices[];
}
previousObjectToWorldMatrices;

layout(std430, buffer_reference, buffer_reference_align = 4) readonly buffer PreviousIndexBuffer {
    uint indices[];
};

bool isPreviousGeometryFinite(vec3 position) {
    return !any(isnan(position)) && !any(isinf(position));
}

bool loadPreviousGeometryWorldPosition(uint geometryBufferIndex,
                                       uint primitiveId,
                                       uint instanceIndex,
                                       vec3 bary,
                                       vec3 currentLocalPosition,
                                       out vec3 previousWorldPosition) {
    vec3 previousLocalPosition = currentLocalPosition;
    bool isVista = instanceIndex >= worldUBO.vistaInstanceOffset &&
                   instanceIndex - worldUBO.vistaInstanceOffset < worldUBO.vistaInstanceCount;
    bool isHistoryValid = isChunkGeometryBufferIndex(geometryBufferIndex) && !isVista;

    if (!isHistoryValid) {
        uint addressIndex = geometryAddressIndex(geometryBufferIndex);
        uint64_t previousIndexAddress = previousIndexBufferAddresses.addrs[addressIndex];
        uint64_t previousPbrAddress = lastPbrBufferAddrs.addrs[addressIndex];
        if (previousIndexAddress != 0ul && previousPbrAddress != 0ul) {
            PreviousIndexBuffer previousIndexBuffer = PreviousIndexBuffer(previousIndexAddress);
            uint indexBase = 3u * primitiveId;
            uint previousI0 = previousIndexBuffer.indices[indexBase];
            uint previousI1 = previousIndexBuffer.indices[indexBase + 1u];
            uint previousI2 = previousIndexBuffer.indices[indexBase + 2u];

            if (!isVista) {
                EntityPBRBuffer previousPbrBuffer = EntityPBRBuffer(previousPbrAddress);
                vec3 previousP0 = previousPbrBuffer.vertices[previousI0].pos;
                vec3 previousP1 = previousPbrBuffer.vertices[previousI1].pos;
                vec3 previousP2 = previousPbrBuffer.vertices[previousI2].pos;
                previousLocalPosition = bary.x * previousP0 + bary.y * previousP1 + bary.z * previousP2;
            }
            isHistoryValid = isPreviousGeometryFinite(previousLocalPosition);
        }
    }

    mat4 previousObjectToWorld = previousObjectToWorldMatrices.matrices[instanceIndex];
    previousWorldPosition = mat3(previousObjectToWorld) * previousLocalPosition + previousObjectToWorld[3].xyz;
    return isHistoryValid && isPreviousGeometryFinite(previousWorldPosition);
}

#endif
