#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require

#include "lighting/shadow/payload.glsl"

layout(location = 0) rayPayloadInEXT ShadowPayload shadowPayload;

void main() {
    if (isShadowPayloadWaterProbe(shadowPayload)) { return; }
    shadowPayload.blockerHitT = min(shadowPayload.blockerHitT, gl_HitTEXT);
    shadowPayload.transmission = vec3(0.0);
}
