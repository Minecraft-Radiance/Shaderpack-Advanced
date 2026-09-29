#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_shader_explicit_arithmetic_types_float16 : require
#extension GL_EXT_shader_16bit_storage : enable

#include "scene/hit.glsl"

layout(location = 0) rayPayloadInEXT HitPayload hitPayload;

void main() {
    hitPayload.hitKind = ADV_HIT_KIND_NONE;
    hitPayload.hitT = 0.0;
}
