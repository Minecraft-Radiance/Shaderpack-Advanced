#version 460
#extension GL_EXT_nonuniform_qualifier : enable
#extension GL_GOOGLE_include_directive : require

#include "common/shared.hpp"

layout(set = 0, binding = 0) uniform sampler2D textures[];

layout(set = 1, binding = 0) uniform WorldUniform {
    WorldUBO worldUBO;
};

layout(location = 0) in vec3 inPos;
layout(location = 1) in uint inNormalOct;
layout(location = 2) in vec2 inTextureUV;
layout(location = 3) in uint inColorRGBA8;
layout(location = 4) in uint inLightUVPacked;
layout(location = 5) in uint inOverlayUVPacked;
layout(location = 6) in uint inGlintUVHalf;
layout(location = 7) in uint inTextureID;
layout(location = 8) in uint inGlintTexture;
layout(location = 9) in vec3 inPostBase;
layout(location = 10) in uint inPackedData;

layout(location = 0) out vec3 outPos;
layout(location = 1) flat out uint outUseNorm;
layout(location = 2) out vec3 outNorm;
layout(location = 3) flat out uint outUseColorLayer;
layout(location = 4) out vec4 outColorLayer;
layout(location = 5) flat out uint outUseTexture;
layout(location = 6) flat out uint outUseOverlay;
layout(location = 7) out vec2 outTextureUV;
layout(location = 8) flat out ivec2 outOverlayUV;
layout(location = 9) flat out uint outUseGlint;
layout(location = 10) flat out uint outTextureID;
layout(location = 11) out vec2 outGlintUV;
layout(location = 12) flat out uint outGlintTexture;
layout(location = 13) flat out uint outUseLight;
layout(location = 14) flat out ivec2 outLightUV;
layout(location = 15) out vec4 lightMapColor;
layout(location = 16) out vec4 overlayColor;
layout(location = 17) flat out uint outPostTextMode;

const uint USE_COLOR_LAYER_BIT = 1u << 0u;
const uint USE_TEXTURE_BIT = 1u << 1u;
const uint USE_OVERLAY_BIT = 1u << 2u;
const uint USE_GLINT_BIT = 1u << 3u;
const uint USE_NORM_BIT = 1u << 4u;
const uint USE_LIGHT_BIT = 1u << 5u;
const uint ALPHA_MODE_SHIFT = 8u;
const uint COORDINATE_SHIFT = 12u;

vec2 pbrOctSignNotZero(vec2 value) {
    return vec2(value.x >= 0.0 ? 1.0 : -1.0, value.y >= 0.0 ? 1.0 : -1.0);
}

vec3 unpackPBRNormal(uint packedNormal) {
    vec2 encoded = unpackSnorm2x16(packedNormal);
    vec3 normal = vec3(encoded, 1.0 - abs(encoded.x) - abs(encoded.y));
    if (normal.z < 0.0) { normal.xy = (vec2(1.0) - abs(normal.yx)) * pbrOctSignNotZero(normal.xy); }
    return normalize(normal);
}

ivec2 unpackPBRU16x2(uint packedValue) {
    return ivec2(int(packedValue & 0xffffu), int((packedValue >> 16u) & 0xffffu));
}

void main() {
    uint inCoordinate = (inPackedData >> COORDINATE_SHIFT) & 0xFu;
    uint inUseNorm = (inPackedData & USE_NORM_BIT) != 0u ? 1u : 0u;
    uint inUseColorLayer = (inPackedData & USE_COLOR_LAYER_BIT) != 0u ? 1u : 0u;
    uint inUseTexture = (inPackedData & USE_TEXTURE_BIT) != 0u ? 1u : 0u;
    uint inUseOverlay = (inPackedData & USE_OVERLAY_BIT) != 0u ? 1u : 0u;
    uint inUseGlint = (inPackedData & USE_GLINT_BIT) != 0u ? 1u : 0u;
    uint inUseLight = (inPackedData & USE_LIGHT_BIT) != 0u ? 1u : 0u;
    vec3 inNorm = unpackPBRNormal(inNormalOct);
    vec4 inColorLayer = unpackUnorm4x8(inColorRGBA8);
    ivec2 inOverlayUV = unpackPBRU16x2(inOverlayUVPacked);
    vec2 inGlintUV = unpackHalf2x16(inGlintUVHalf);
    ivec2 inLightUV = unpackPBRU16x2(inLightUVPacked);

    vec3 worldOrViewPos = inPos + inPostBase;
    if (inCoordinate == 0) {
        worldOrViewPos = worldOrViewPos - vec3(worldUBO.cameraPos.xyz);
    } else if (inCoordinate == 1) {
        worldOrViewPos = mat3(worldUBO.cameraViewMatInv) * worldOrViewPos;
    }

    outPos = worldOrViewPos;
    outUseNorm = inUseNorm;
    if (inCoordinate == 0 || inCoordinate == 2) {
        outNorm = inNorm;
    } else if (inCoordinate == 1) {
        outNorm = normalize(mat3(worldUBO.cameraViewMatInv) * inNorm);
    }
    outUseColorLayer = inUseColorLayer;
    outColorLayer = inColorLayer;
    outUseTexture = inUseTexture;
    outUseOverlay = inUseOverlay;
    outTextureUV = inTextureUV;
    outOverlayUV = inOverlayUV;
    outUseGlint = inUseGlint;
    outTextureID = inTextureID;
    outGlintUV = inGlintUV;
    outGlintTexture = inGlintTexture;
    outUseLight = inUseLight;
    outLightUV = inLightUV;
    outPostTextMode = (inPackedData >> ALPHA_MODE_SHIFT) & 0xFu;

    gl_Position = worldUBO.cameraProjMat * worldUBO.cameraEffectedViewMat * vec4(worldOrViewPos, 1.0);

    if (inUseLight > 0) {
        lightMapColor = texelFetch(textures[nonuniformEXT(worldUBO.lightMapTextureID)], inLightUV / 16, 0);
    } else {
        lightMapColor = vec4(0.0);
    }
    if (inUseOverlay > 0) {
        overlayColor = texelFetch(textures[nonuniformEXT(worldUBO.overlayTextureID)], inOverlayUV, 0);
    } else {
        overlayColor = vec4(0.0);
    }
}
