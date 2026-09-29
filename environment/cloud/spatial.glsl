#ifndef ADV_ENVIRONMENT_CLOUD_SPATIAL_GLSL
#define ADV_ENVIRONMENT_CLOUD_SPATIAL_GLSL

#include "environment/cloud/resources.glsl"

float saturateCloudValue(float cloudValue) {
    return clamp(cloudValue, 0.0, 1.0);
}

float remapCloudValueClamped(float cloudValue, float inputMin, float inputMax, float outputMin, float outputMax) {
    float normalizedValue = clamp((cloudValue - inputMin) / max(inputMax - inputMin, 1e-5), 0.0, 1.0);
    return mix(outputMin, outputMax, normalizedValue);
}

vec3 normalizeCloudDirectionSafe(vec3 direction, vec3 fallbackDirection) {
    float lengthSquared = dot(direction, direction);
    if (lengthSquared <= 1e-8 || any(isnan(direction)) || any(isinf(direction))) { return fallbackDirection; }
    return direction * inversesqrt(lengthSquared);
}

float sampleCloudStepJitter(float jitterSalt) {
    ivec2 noiseSize = textureSize(cloudBlueNoiseTexture, 0);
    ivec2 basePixel = ivec2(floor(ADV_CLOUD_JITTER_COORD));
    ivec2 jitterOffset = ivec2(int(jitterSalt * 19.0), int(jitterSalt * 47.0));
    ivec2 noisePixel = (basePixel + jitterOffset) % noiseSize;
    noisePixel = (noisePixel + noiseSize) % noiseSize;

    float blueNoiseTexture = texelFetch(cloudBlueNoiseTexture, noisePixel, 0).r;
    float temporalOffset = 0.0;
#if ADV_CLOUD_BLUE_NOISE_TEMPORAL != 0
    temporalOffset = float(worldUBO.seed & 63u) * 0.61803398875;
#endif
    return fract(blueNoiseTexture + temporalOffset + jitterSalt * 0.071);
}

float calculateJitteredCloudDistance(int stepIndex, float stepLength, float distanceJitter, float maxDistance) {
    float jitterScale = max(ADV_CLOUD_DISTANCE_JITTER_SCALE, 0.0);
    float cloudDistance = (float(stepIndex) + distanceJitter * jitterScale) * stepLength;
    return min(cloudDistance, maxDistance);
}

bool findCloudSphereIntersection(
    vec3 rayOrigin, vec3 rayDirection, float radius, out float nearDistance, out float farDistance) {
    float rayProjection = dot(rayOrigin, rayDirection);
    float sphereOffset = dot(rayOrigin, rayOrigin) - radius * radius;
    float discriminant = rayProjection * rayProjection - sphereOffset;
    if (discriminant < 0.0) { return false; }
    discriminant = sqrt(discriminant);
    nearDistance = -rayProjection - discriminant;
    farDistance = -rayProjection + discriminant;
    return true;
}

vec3 cloudPositionWS(vec3 relativeWorldPosition) {
    return relativeWorldPosition + vec3(worldUBO.cameraPos.xyz);
}

vec3 cloudPositionPS(vec3 relativeWorldPosition) {
    vec3 absoluteWorldPosition = cloudPositionWS(relativeWorldPosition);
    return vec3(absoluteWorldPosition.x, ADV_ATMOSPHERE_RG + absoluteWorldPosition.y, absoluteWorldPosition.z);
}

float cloudBottomRadius() {
    return ADV_ATMOSPHERE_RG + ADV_CLOUD_BOTTOM_HEIGHT;
}

float cloudTopRadius() {
    return ADV_ATMOSPHERE_RG + ADV_CLOUD_TOP_HEIGHT;
}

float cloudNormalizedHeight(vec3 planetPos) {
    float radius = length(planetPos);
    return clamp((radius - cloudBottomRadius()) / max(cloudTopRadius() - cloudBottomRadius(), 1e-3), 0.0, 1.0);
}

float cloudTime() {
    return worldUBO.gameTime * 24000.0 / 200;
}

vec3 cloudWindDirection() {
    return normalizeCloudDirectionSafe(vec3(0.8, 0.0, 0.4), vec3(1.0, 0.0, 0.0));
}

bool intersectCloudLayer(vec3 rayOrigin, vec3 rayDirection, out float enterDistance, out float exitDistance) {
    vec3 originPlanet = cloudPositionPS(rayOrigin);
    float outerNear, outerFar;
    if (!findCloudSphereIntersection(originPlanet, rayDirection, cloudTopRadius(), outerNear, outerFar)) {
        return false;
    }

    enterDistance = max(outerNear, 0.0);
    exitDistance = max(outerFar, 0.0);
    if (exitDistance <= enterDistance) { return false; }

    float innerNear, innerFar;
    if (!findCloudSphereIntersection(originPlanet, rayDirection, cloudBottomRadius(), innerNear, innerFar)) {
        return exitDistance > enterDistance;
    }

    if (innerFar > 0.0) {
        if (innerNear > 0.0) {
            if (enterDistance < innerNear) {
                exitDistance = min(exitDistance, innerNear);
            } else {
                enterDistance = max(enterDistance, innerFar);
            }
        } else {
            enterDistance = max(enterDistance, innerFar);
        }
    }

    float groundNear, groundFar;
    if (findCloudSphereIntersection(originPlanet, rayDirection, ADV_ATMOSPHERE_RG, groundNear, groundFar)) {
        float groundHit = groundNear > 0.0 ? groundNear : groundFar;
        if (groundHit > 0.0) { exitDistance = min(exitDistance, groundHit); }
    }

    return exitDistance > enterDistance;
}

float cloudSegmentLength(vec3 rayOrigin, vec3 rayDirection) {
    float enterDistance, exitDistance;
    if (!intersectCloudLayer(rayOrigin, rayDirection, enterDistance, exitDistance)) { return 0.0; }
    return max(exitDistance - enterDistance, 0.0);
}

bool findCloudSegment(vec3 rayOrigin, vec3 rayDirection, out vec3 segmentOrigin, out float segmentLength) {
    float enterDistance, exitDistance;
    if (!intersectCloudLayer(rayOrigin, rayDirection, enterDistance, exitDistance)) {
        segmentOrigin = rayOrigin;
        segmentLength = 0.0;
        return false;
    }

    segmentOrigin = rayOrigin + rayDirection * enterDistance;
    segmentLength = max(exitDistance - enterDistance, 0.0);
    return segmentLength > 1e-3;
}

vec3 sampleCloudAtmosphereTransmittance(float radius, float viewCosine) {
    return sampleAtmosphereLut(radius, viewCosine);
}

#endif
