#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require

#include "lighting/shadow/payload.glsl"

layout(location = 1) rayPayloadInEXT ShadowPayload segmentShadowPayload;

void main() {
    segmentShadowPayload.reachedLight = 1u;
}
