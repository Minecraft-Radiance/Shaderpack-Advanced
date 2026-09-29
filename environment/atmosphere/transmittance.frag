#version 460
#extension GL_GOOGLE_include_directive : require

#include "common/shared.hpp"
#include "environment/atmosphere/medium.glsl"

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 outColor;

bool findAtmosphereSphereIntersection(vec3 rayOrigin, vec3 rayDir, float radius, out float tNear, out float tFar) {
    float rayProjection = dot(rayOrigin, rayDir);
    float sphereOffset = dot(rayOrigin, rayOrigin) - radius * radius;
    float discriminant = rayProjection * rayProjection - sphereOffset;
    if (discriminant < 0.0) return false;
    discriminant = sqrt(discriminant);
    tNear = -rayProjection - discriminant;
    tFar = -rayProjection + discriminant;
    return true;
}

float calculateExponentialDensity(float height, float scaleHeight) {
    return exp(-max(height, 0.0) / scaleHeight);
}

void main() {
    float cosineCoordinate = texCoord.x * 2.0 - 1.0;
    float viewCos = sign(cosineCoordinate) * cosineCoordinate * cosineCoordinate;
    float radius = mix(ADV_ATMOSPHERE_RG, ADV_ATMOSPHERE_RT, texCoord.y * texCoord.y);

    vec3 rayOrigin = vec3(0.0, radius, 0.0);
    float sinTheta = sqrt(max(1.0 - viewCos * viewCos, 0.0));
    vec3 rayDir = normalize(vec3(sinTheta, viewCos, 0.0));

    float nearDistance, farDistance;
    if (!findAtmosphereSphereIntersection(rayOrigin, rayDir, ADV_ATMOSPHERE_RT, nearDistance, farDistance)) {
        outColor = vec4(1.0);
        return;
    }
    nearDistance = max(nearDistance, 0.0);

    const int stepCount = 128;
    float stepLength = (farDistance - nearDistance) / float(stepCount);
    vec3 opticalDepth = vec3(0.0);

    for (int stepIndex = 0; stepIndex < stepCount; stepIndex++) {
        float sampleDistance = nearDistance + (float(stepIndex) + 0.5) * stepLength;
        vec3 samplePos = rayOrigin + rayDir * sampleDistance;
        float sampleRadius = length(samplePos);
        float height = sampleRadius - ADV_ATMOSPHERE_RG;

        float rayleighDensity = calculateExponentialDensity(height, ADV_ATMOSPHERE_HR);
        float mieDensity = calculateExponentialDensity(height, ADV_ATMOSPHERE_HM);

        vec3 sigmaT = atmosphereExtinction(height, ADV_ATMOSPHERE_BETA_R * rayleighDensity,
                                          ADV_ATMOSPHERE_BETA_M * mieDensity);
        opticalDepth += sigmaT * stepLength;
    }

    outColor = vec4(exp(-opticalDepth), 1.0);
}
