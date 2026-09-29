#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference2 : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require
#extension GL_EXT_shader_explicit_arithmetic_types_float16 : require
#extension GL_EXT_shader_16bit_storage : enable

#define ADV_SCENE_RESOURCES_NO_PREVIOUS_GEOMETRY
#include "scene/resources.glsl"
#include "scene/hit.glsl"

#ifndef ADV_PATH_HIT_CATEGORY
#    define ADV_PATH_HIT_CATEGORY ADV_HIT_CATEGORY_DEFAULT
#endif

layout(location = 0) rayPayloadInEXT HitPayload hitPayload;
hitAttributeEXT vec2 pathHitAttributes;

void main() {
    uint instanceIndex = gl_InstanceCustomIndexEXT;
    hitPayload.hitKind = ADV_HIT_KIND_TRIANGLE;
    hitPayload.instanceIndex = instanceIndex;
    hitPayload.geometryBufferIndex = getGeometryBufferIndex(instanceIndex, gl_GeometryIndexEXT);
    hitPayload.primitiveId = gl_PrimitiveID;
    hitPayload.category = uint(ADV_PATH_HIT_CATEGORY);
    hitPayload.hitT = gl_HitTEXT;
    hitPayload.barycentrics = pathHitAttributes;
    hitPayload.isFrontFace = gl_HitKindEXT == gl_HitKindFrontFacingTriangleEXT ? 1u : 0u;
    hitPayload.instanceMask = loadInstanceMask(instanceIndex);
}
