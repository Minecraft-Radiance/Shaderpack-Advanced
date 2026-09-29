#version 460
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_buffer_reference2 : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

#define ADV_SCENE_RESOURCES_NO_PREVIOUS_GEOMETRY
#include "scene/resources.glsl"
#include "scene/materials/alpha.glsl"
#include "path/primary/hit_buffer.glsl"

layout(location = 0) in vec3 relativePosition;
layout(location = 1) in vec3 previousRelativePosition;
layout(location = 2) in vec3 barycentric;
layout(location = 3) flat in uint textureId;
layout(location = 4) in vec4 colorLayer;
layout(location = 5) in vec2 textureUv;
layout(location = 6) flat in uint packedData;
layout(location = 7) flat in uint instanceMask;
layout(location = 8) flat in uint instanceIndex;
layout(location = 9) flat in uint geometryBufferIndex;
layout(location = 10) flat in uint primitiveId;

layout(location = 0) out uvec4 outHandSurface;
layout(location = 1) out uvec4 outHandBaryDepth;
layout(location = 2) out vec2 outHandTemporalMotion;

const float ADV_HAND_MAX_DISTANCE = 10.0;

bool finiteFloat(float value) {
    return !isnan(value) && !isinf(value);
}

bool finiteVec2(vec2 value) {
    return !any(isnan(value)) && !any(isinf(value));
}

bool finiteVec3(vec3 value) {
    return !any(isnan(value)) && !any(isinf(value));
}

vec3 buildHandRasterRay(out vec3 origin) {
    vec2 pixelCenter = gl_FragCoord.xy + worldUBO.cameraJitter;
    vec2 ndc = pixelCenter / vec2(RENDER_WIDTH, RENDER_HEIGHT) * 2.0 - 1.0;
    vec4 viewNear = worldUBO.cameraProjMatInv * vec4(ndc, 0.0, 1.0);
    origin = worldUBO.cameraEffectedViewMatInv[3].xyz;
    vec3 fallback = normalize(-worldUBO.cameraEffectedViewMatInv[2].xyz);
    if (!finiteVec3(fallback) || dot(fallback, fallback) <= 1e-12) { fallback = vec3(0.0, 0.0, -1.0); }
    if (!finiteVec3(viewNear.xyz) || !finiteFloat(viewNear.w) || abs(viewNear.w) <= 1e-8) { return fallback; }
    viewNear /= viewNear.w;
    vec3 direction = vec3(worldUBO.cameraEffectedViewMatInv * vec4(viewNear.xyz, 0.0));
    float lengthSquared = dot(direction, direction);
    if (!finiteVec3(direction) || !finiteFloat(lengthSquared) || lengthSquared <= 1e-12) { return fallback; }
    return direction * inversesqrt(lengthSquared);
}

vec2 buildHandTemporalMotion(vec2 currentPixelCenter) {
    vec4 previousClip =
        lastWorldUBO.cameraProjMat * lastWorldUBO.cameraEffectedViewMat * vec4(previousRelativePosition, 1.0);
    if (!finiteVec3(previousClip.xyz) || !finiteFloat(previousClip.w) || previousClip.w <= 1e-8) { return vec2(0.0); }
    vec2 previousPixel = (previousClip.xy / previousClip.w * 0.5 + 0.5) * vec2(RENDER_WIDTH, RENDER_HEIGHT);
    vec2 motion = previousPixel - currentPixelCenter;
    return finiteVec2(motion) ? motion : vec2(0.0);
}

void main() {
    if (worldUBO.isFirstPerson == 0u || (instanceMask & HAND_MASK) == 0u) { discard; }

    uint alphaMode = getAlphaMode(packedData);
    float rawAlpha = 1.0;
    if (hasTexture(packedData)) {
        rawAlpha *= resolveSurfaceTextureColor(texture(textures[nonuniformEXT(textureId)], textureUv), alphaMode).a;
    }
    if (hasColorLayer(packedData)) { rawAlpha *= colorLayer.a; }
    if (!isAlphaCovered(rawAlpha, alphaMode)) { discard; }

    vec3 normalizedBary = max(barycentric, vec3(0.0));
    float barySum = normalizedBary.x + normalizedBary.y + normalizedBary.z;
    if (!finiteVec3(normalizedBary) || !finiteFloat(barySum) || barySum <= 1e-8) { discard; }
    normalizedBary /= barySum;

    vec3 cameraOrigin;
    vec3 rayDirection = buildHandRasterRay(cameraOrigin);
    float hitT = dot(relativePosition - cameraOrigin, rayDirection);
    float linearDepth = -(worldUBO.cameraEffectedViewMat * vec4(relativePosition, 1.0)).z;
    if (!finiteFloat(hitT) || hitT <= 0.0 || hitT > ADV_HAND_MAX_DISTANCE || !finiteFloat(linearDepth) ||
        linearDepth < 0.0 || !finiteVec3(relativePosition)) {
        discard;
    }

    uint packedInstance = (instanceIndex & ADV_PRIMARY_HIT_INSTANCE_MASK) | ADV_PRIMARY_HIT_HAND_BIT |
                          ((instanceMask & CLOUD_MASK) != 0u ? ADV_PRIMARY_HIT_CLOUD_BIT : 0u) |
                          ((instanceMask & BOAT_WATER_MASK) != 0u ? ADV_PRIMARY_HIT_BOAT_WATER_BIT : 0u) |
                          (gl_FrontFacing ? ADV_PRIMARY_HIT_FRONT_FACE_BIT : 0u) | ADV_PRIMARY_HIT_VALID_BIT;
    outHandSurface = uvec4(packedInstance, geometryBufferIndex, primitiveId, floatBitsToUint(hitT));
    outHandBaryDepth = uvec4(packUnorm2x16(normalizedBary.yz), floatBitsToUint(linearDepth), 0u, 0u);

    vec2 currentPixelCenter = floor(gl_FragCoord.xy) + vec2(0.5) + worldUBO.cameraJitter;
    outHandTemporalMotion = buildHandTemporalMotion(currentPixelCenter);
}
