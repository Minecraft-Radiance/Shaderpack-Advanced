#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require

#include "lighting/shadow/payload.glsl"

layout(location = 1) rayPayloadInEXT ShadowPayload segmentShadowPayload;

void main() {
    if (isShadowPayloadWaterProbe(segmentShadowPayload)) { return; }
    segmentShadowPayload.blockerHitT = min(segmentShadowPayload.blockerHitT, gl_HitTEXT);
    segmentShadowPayload.transmission = vec3(0.0);
}
