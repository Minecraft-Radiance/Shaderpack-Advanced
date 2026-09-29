#ifndef ADV_SCENE_CAMERA_GLSL
#define ADV_SCENE_CAMERA_GLSL

#include "core/math.glsl"

void buildVirtualCameraRay(ivec2 flatPixel,
                           ivec2 flatExtent,
                           mat4 projectionInverse,
                           mat4 viewInverse,
                           vec2 jitter,
                           out vec3 origin,
                           out vec3 direction) {
    vec2 pixelCenter = vec2(flatPixel) + 0.5 + jitter;
    vec2 ndc = pixelCenter / vec2(flatExtent) * 2.0 - 1.0;
    vec4 viewNear = projectionInverse * vec4(ndc, 0.0, 1.0);
    origin = viewInverse[3].xyz;
    vec3 fallback = normalize(-viewInverse[2].xyz, vec3(0.0, 0.0, -1.0));
    if (!isFinite(viewNear) || abs(viewNear.w) <= 1e-8) {
        direction = fallback;
        return;
    }
    viewNear /= viewNear.w;
    direction = normalize(vec3(viewInverse * vec4(viewNear.xyz, 0.0)), fallback);
}

bool projectPreviousPosition(
    vec3 previousPosition, vec2 currentPixelCenter, vec2 resolution, out vec2 motion, out float reprojectedPathLength) {
    motion = vec2(0.0);
    reprojectedPathLength = 0.0;
    vec4 previousView = lastWorldUBO.cameraEffectedViewMat * vec4(previousPosition, 1.0);
    if (!isFinite(previousView) || previousView.z >= -1e-6) { return false; }
    reprojectedPathLength = -previousView.z;
    vec4 previousClip = lastWorldUBO.cameraProjMat * previousView;
    if (!isFinite(previousClip) || previousClip.w <= 1e-8) { return false; }
    vec2 previousNdc = previousClip.xy / previousClip.w;
    vec2 previousPixel = (previousNdc * 0.5 + 0.5) * resolution;
    motion = previousPixel - currentPixelCenter;
    return isFinite(motion) && isFinite(reprojectedPathLength);
}

bool projectEnvironmentDirection(vec3 direction, vec2 currentPixelCenter, vec2 resolution, out vec2 motion) {
    motion = vec2(0.0);
    vec4 previousView = lastWorldUBO.cameraEffectedViewMat * vec4(direction, 0.0);
    vec4 previousClip = lastWorldUBO.cameraProjMat * previousView;
    if (!isFinite(previousClip) || previousClip.w <= 1e-8) { return false; }
    vec2 previousNdc = previousClip.xy / previousClip.w;
    vec2 previousPixel = (previousNdc * 0.5 + 0.5) * resolution;
    motion = previousPixel - currentPixelCenter;
    return isFinite(motion);
}

#endif
