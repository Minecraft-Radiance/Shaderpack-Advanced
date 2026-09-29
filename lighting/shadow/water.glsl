#ifndef ADV_LIGHTING_SHADOW_WATER_GLSL
#define ADV_LIGHTING_SHADOW_WATER_GLSL

#include "scene/materials/media.glsl"
#include "scene/materials/water.glsl"

vec3 underwaterDirectionToLight(vec3 airDirectionToLight) {
    float directionLengthSquared = dot(airDirectionToLight, airDirectionToLight);
    if (directionLengthSquared <= 1e-10 || any(isnan(airDirectionToLight)) || any(isinf(airDirectionToLight))) {
        return vec3(0.0, 1.0, 0.0);
    }

    vec3 airDirection = airDirectionToLight * inversesqrt(directionLengthSquared);
    vec3 refractedTowardWater = refract(-airDirection, vec3(0.0, 1.0, 0.0), ADV_AIR_IOR / ADV_WATER_IOR);
    float refractedLengthSquared = dot(refractedTowardWater, refractedTowardWater);
    if (refractedLengthSquared <= 1e-10 || any(isnan(refractedTowardWater)) || any(isinf(refractedTowardWater))) {
        return airDirection;
    }
    return -refractedTowardWater * inversesqrt(refractedLengthSquared);
}

float waterCausticsAdapter(vec3 sceneSurfacePosition, vec3 directionToLight, float waterRayLength) {
    vec2 absoluteWaterPosition = sceneSurfacePosition.xz + vec2(worldUBO.cameraPos.x, worldUBO.cameraPos.z);
    return waterWaveCaustics(absoluteWaterPosition, directionToLight, waterRayLength);
}

vec3 waterSunTransmission(vec3 sceneSurfacePosition, vec3 directionToLight, float waterRayLength) {
    return segmentTransmittance(ADV_MEDIUM_WATER, waterRayLength) *
           waterCausticsAdapter(sceneSurfacePosition, directionToLight, waterRayLength);
}

#endif
