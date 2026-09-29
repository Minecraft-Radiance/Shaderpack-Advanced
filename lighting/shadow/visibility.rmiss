#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require

#include "lighting/shadow/payload.glsl"

layout(location = 0) rayPayloadInEXT ShadowPayload shadowPayload;

void main() {
    shadowPayload.reachedLight = 1u;
}
