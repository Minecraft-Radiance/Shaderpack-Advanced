#ifndef ADV_LIGHTING_RESTIR_HISTORY_GLSL
#define ADV_LIGHTING_RESTIR_HISTORY_GLSL

#include "lighting/restir/reservoir.glsl"

float restirWorldPerPixel(float viewDistance, ivec2 resolution) {
    float fovY = fovYFromProj(worldUBO.cameraProjMat);
    return 2.0 * tan(0.5 * fovY) * max(viewDistance, 1e-3) / float(max(resolution.y, 1));
}

bool selectRestirPreviousActivePixel(vec2 projectedPixel, ivec2 resolution, out ivec2 previousPixel) {
    previousPixel = ivec2(round(projectedPixel));
#if ADV_RESTIR_RESOLUTION_MODE == 1
    return all(greaterThanEqual(previousPixel, ivec2(0))) && all(lessThan(previousPixel, resolution));
#else
    uint previousPhase = restirCheckerboardPhase() ^ 1u;
    if (previousPixel.y < 0 || previousPixel.y >= resolution.y) { return false; }
    if (previousPixel.x >= 0 && previousPixel.x < resolution.x &&
        doesRestirPixelMatchPhase(previousPixel, previousPhase)) {
        return true;
    }

    int preferredDirection = projectedPixel.x >= float(previousPixel.x) ? 1 : -1;
    ivec2 preferredPixel = previousPixel + ivec2(preferredDirection, 0);
    if (preferredPixel.x >= 0 && preferredPixel.x < resolution.x &&
        doesRestirPixelMatchPhase(preferredPixel, previousPhase)) {
        previousPixel = preferredPixel;
        return true;
    }

    ivec2 alternatePixel = previousPixel - ivec2(preferredDirection, 0);
    if (alternatePixel.x >= 0 && alternatePixel.x < resolution.x &&
        doesRestirPixelMatchPhase(alternatePixel, previousPhase)) {
        previousPixel = alternatePixel;
        return true;
    }
    return false;
#endif
}

bool projectRestirPreviousPixel(
    ivec2 pixel, ivec2 resolution, vec3 currentWorldPosition, out ivec2 previousPixel, out float motionLength) {
    previousPixel = pixel;
    motionLength = 0.0;
    vec3 previousRelativePosition = currentWorldPosition - vec3(lastWorldUBO.cameraPos.xyz);
    vec4 previousClip =
        lastWorldUBO.cameraProjMat * lastWorldUBO.cameraEffectedViewMat * vec4(previousRelativePosition, 1.0);
    if (!isFinite(previousClip) || previousClip.w <= 1e-6) { return false; }
    vec2 previousNdc = previousClip.xy / previousClip.w;
    if (any(greaterThan(abs(previousNdc), vec2(1.0)))) { return false; }

    vec2 previousCenter = (previousNdc * 0.5 + 0.5) * vec2(resolution);
    vec2 currentCenter = vec2(pixel) + 0.5 + worldUBO.cameraJitter;
    vec2 motion = previousCenter - currentCenter;
    vec2 jitterCorrection = worldUBO.cameraJitter - lastWorldUBO.cameraJitter;
    vec2 projectedPixel = vec2(pixel) + motion + jitterCorrection;
    motionLength = length(motion + jitterCorrection);
    return selectRestirPreviousActivePixel(projectedPixel, resolution, previousPixel);
}

bool doesRestirHistorySurfaceMatch(
    ivec2 previousPixel, ivec2 resolution, vec3 currentWorldPosition, vec3 currentNormal, float motionLength) {
    bool isCurrentPing = bool(ADV_RESTIR_FRAME_PING_INPUT);
    RestirSurfaceKey previousKey = loadRestirSurfaceKey(previousPixel, !isCurrentPing);
    if (!previousKey.isValid) { return false; }

    vec3 worldDelta = previousKey.worldPosition - currentWorldPosition;
    float motionFactor = clamp(motionLength, 0.0, 2.0);
    float planeTolerance = ADV_RESTIR_TEMPORAL_PLANE_TOLERANCE + motionFactor * ADV_RESTIR_TEMPORAL_PLANE_MOTION_SCALE;
    if (abs(dot(worldDelta, currentNormal)) > planeTolerance) { return false; }
    vec3 tangentDelta = worldDelta - currentNormal * dot(worldDelta, currentNormal);
    float viewDistance = distance(currentWorldPosition, vec3(worldUBO.cameraPos.xyz));
    float worldPerPixel = restirWorldPerPixel(viewDistance, resolution);
    float tangentTolerance =
        max(ADV_RESTIR_TEMPORAL_MIN_TANGENT_TOLERANCE + motionFactor * ADV_RESTIR_TEMPORAL_MIN_TANGENT_MOTION_SCALE,
            worldPerPixel *
                (ADV_RESTIR_TEMPORAL_TANGENT_PIXEL_SCALE + motionFactor * ADV_RESTIR_TEMPORAL_TANGENT_MOTION_SCALE));
    if (dot(tangentDelta, tangentDelta) > tangentTolerance * tangentTolerance ||
        dot(previousKey.normal, currentNormal) <= ADV_RESTIR_TEMPORAL_NORMAL_THRESHOLD) {
        return false;
    }

    return true;
}

bool doesRestirHistoryMatch(ivec2 previousPixel,
                            ivec2 resolution,
                            vec3 currentWorldPosition,
                            vec3 currentNormal,
                            float motionLength,
                            out RestirReservoir previousReservoir) {
    previousReservoir = emptyRestirReservoir();
    if (!doesRestirHistorySurfaceMatch(previousPixel, resolution, currentWorldPosition, currentNormal, motionLength)) {
        return false;
    }
    previousReservoir = loadTemporalRestirReservoir(previousPixel, !bool(ADV_RESTIR_FRAME_PING_INPUT));
    return previousReservoir.isValid;
}

float restirConfidenceCap() {
    return max(float(ADV_RESTIR_TEMPORAL_CONFIDENCE_CAP) * ADV_RESTIR_TEMPORAL_CONFIDENCE_SCALE, 1.0);
}

void ageRestirReservoir(inout RestirReservoir reservoir) {
    float confidence = reservoir.confidence;
    float minimumConfidence = min(confidence, ADV_RESTIR_INACTIVE_MIN_CONFIDENCE);
    reservoir.confidence =
        min(max(confidence * ADV_RESTIR_INACTIVE_CONFIDENCE_DECAY, minimumConfidence), restirConfidenceCap());
}

#endif
