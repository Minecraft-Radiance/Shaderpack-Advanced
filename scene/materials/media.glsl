#ifndef ADV_SCENE_MATERIALS_MEDIA_GLSL
#define ADV_SCENE_MATERIALS_MEDIA_GLSL

#include "common/shared.hpp"

const uint ADV_MEDIUM_WATER = 0u;
const uint ADV_MEDIUM_GLASS = 1u;
const uint ADV_MEDIUM_AIR = 2u;
const uint ADV_MEDIUM_CLOUD = 3u;
const uint ADV_MEDIUM_SOLID = 4u;
const uint ADV_MEDIUM_COUNT = 5u;

const uint ADV_MEDIA_ACTION_STOP = 0x00u;
const uint ADV_MEDIA_ACTION_REFLECT = 0x01u;
const uint ADV_MEDIA_ACTION_REFRACT = 0x02u;
const uint ADV_MEDIA_ACTION_PASS = 0x04u;
const uint ADV_MEDIA_ACTION_INVBLEND = 0x05u;
const uint ADV_MEDIA_ACTION_SPLIT = 0x10u;
const uint ADV_MEDIA_ACTION_BLEND = 0x20u;

const float ADV_AIR_IOR = 1.0;
const float ADV_WATER_IOR = 1.333;
const float ADV_GLASS_IOR = 1.5;
const float ADV_CLOUD_IOR = 1.0;
const float ADV_MAX_MEDIA_EXTINCTION_DISTANCE = 50.0;

#ifndef ADV_WATER_COLOR
#    define ADV_WATER_COLOR vec3(0.0, 0.48, 0.65)
#endif
#ifndef ADV_WATER_ABSORPTION
#    define ADV_WATER_ABSORPTION 0.22
#endif
#ifndef ADV_WATER_EXTINCTION
#    define ADV_WATER_EXTINCTION \
        ((vec3(1.0) - clamp(ADV_WATER_COLOR, vec3(0.0), vec3(1.0))) * max(float(ADV_WATER_ABSORPTION), 0.0))
#endif
#ifndef ADV_AIR_EXTINCTION
#    define ADV_AIR_EXTINCTION vec3(0.0)
#endif
#ifndef ADV_CLOUD_EXTINCTION
#    define ADV_CLOUD_EXTINCTION vec3(0.02)
#endif

struct CheckerAction {
    uint oddAction;
    uint evenAction;
    uint splitAction;
    uint totalReflectionAction;
};

const uint ADV_FIRST_SPLIT_REFLECTION = ADV_MEDIA_ACTION_REFLECT | ADV_MEDIA_ACTION_SPLIT;
const uint ADV_FIRST_SPLIT_REFRACTION = ADV_MEDIA_ACTION_REFRACT | ADV_MEDIA_ACTION_SPLIT;
const uint ADV_FIRST_SPLIT_CLOUD_SURFACE = ADV_MEDIA_ACTION_INVBLEND | ADV_MEDIA_ACTION_SPLIT;
const uint ADV_FIRST_SPLIT_CLOUD_TRANSMISSION = ADV_MEDIA_ACTION_PASS | ADV_MEDIA_ACTION_SPLIT;
const uint ADV_CLOUD_REFRACT = ADV_MEDIA_ACTION_REFRACT | ADV_MEDIA_ACTION_BLEND;
const uint ADV_CLOUD_PASS = ADV_MEDIA_ACTION_PASS | ADV_MEDIA_ACTION_BLEND;
const uint ADV_CLOUD_STOP = ADV_MEDIA_ACTION_STOP | ADV_MEDIA_ACTION_BLEND;

const CheckerAction ADV_CHECKER_ACTION_TABLE[25] = CheckerAction[25](
    CheckerAction(ADV_MEDIA_ACTION_PASS, ADV_MEDIA_ACTION_PASS, ADV_MEDIA_ACTION_PASS, ADV_MEDIA_ACTION_REFLECT),
    CheckerAction(
        ADV_FIRST_SPLIT_REFLECTION, ADV_FIRST_SPLIT_REFRACTION, ADV_MEDIA_ACTION_REFRACT, ADV_MEDIA_ACTION_REFLECT),
    CheckerAction(
        ADV_FIRST_SPLIT_REFLECTION, ADV_FIRST_SPLIT_REFRACTION, ADV_MEDIA_ACTION_REFRACT, ADV_MEDIA_ACTION_REFLECT),
    CheckerAction(ADV_FIRST_SPLIT_CLOUD_SURFACE,
                  ADV_FIRST_SPLIT_CLOUD_TRANSMISSION,
                  ADV_MEDIA_ACTION_STOP,
                  ADV_MEDIA_ACTION_REFLECT),
    CheckerAction(ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP),
    CheckerAction(
        ADV_FIRST_SPLIT_REFLECTION, ADV_FIRST_SPLIT_REFRACTION, ADV_MEDIA_ACTION_REFRACT, ADV_MEDIA_ACTION_REFLECT),
    CheckerAction(ADV_MEDIA_ACTION_PASS, ADV_MEDIA_ACTION_PASS, ADV_MEDIA_ACTION_PASS, ADV_MEDIA_ACTION_REFLECT),
    CheckerAction(
        ADV_FIRST_SPLIT_REFLECTION, ADV_FIRST_SPLIT_REFRACTION, ADV_MEDIA_ACTION_REFRACT, ADV_MEDIA_ACTION_REFLECT),
    CheckerAction(ADV_FIRST_SPLIT_CLOUD_SURFACE,
                  ADV_FIRST_SPLIT_CLOUD_TRANSMISSION,
                  ADV_MEDIA_ACTION_STOP,
                  ADV_MEDIA_ACTION_REFLECT),
    CheckerAction(ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP),
    CheckerAction(
        ADV_FIRST_SPLIT_REFLECTION, ADV_FIRST_SPLIT_REFRACTION, ADV_MEDIA_ACTION_REFRACT, ADV_MEDIA_ACTION_REFLECT),
    CheckerAction(
        ADV_FIRST_SPLIT_REFLECTION, ADV_FIRST_SPLIT_REFRACTION, ADV_MEDIA_ACTION_REFRACT, ADV_MEDIA_ACTION_REFLECT),
    CheckerAction(ADV_MEDIA_ACTION_PASS, ADV_MEDIA_ACTION_PASS, ADV_MEDIA_ACTION_PASS, ADV_MEDIA_ACTION_REFLECT),
    CheckerAction(ADV_FIRST_SPLIT_CLOUD_SURFACE,
                  ADV_FIRST_SPLIT_CLOUD_TRANSMISSION,
                  ADV_MEDIA_ACTION_STOP,
                  ADV_MEDIA_ACTION_REFLECT),
    CheckerAction(ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP),
    CheckerAction(ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_CLOUD_REFRACT, ADV_MEDIA_ACTION_REFLECT),
    CheckerAction(ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_CLOUD_REFRACT, ADV_MEDIA_ACTION_REFLECT),
    CheckerAction(ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_CLOUD_PASS, ADV_MEDIA_ACTION_REFLECT),
    CheckerAction(ADV_MEDIA_ACTION_PASS, ADV_MEDIA_ACTION_PASS, ADV_MEDIA_ACTION_PASS, ADV_MEDIA_ACTION_REFLECT),
    CheckerAction(ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_CLOUD_STOP, ADV_MEDIA_ACTION_STOP),
    CheckerAction(ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP),
    CheckerAction(ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP),
    CheckerAction(ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP),
    CheckerAction(ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP),
    CheckerAction(ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP, ADV_MEDIA_ACTION_STOP));

CheckerAction checkerAction(uint previousMedium, uint nextMedium) {
    uint row = min(previousMedium, ADV_MEDIUM_SOLID);
    uint column = min(nextMedium, ADV_MEDIUM_SOLID);
    return ADV_CHECKER_ACTION_TABLE[row * ADV_MEDIUM_COUNT + column];
}

float mediumIor(uint medium, float glassIor) {
    if (medium == ADV_MEDIUM_WATER) { return ADV_WATER_IOR; }
    if (medium == ADV_MEDIUM_GLASS) { return clamp(glassIor, 1.0001, 3.0); }
    if (medium == ADV_MEDIUM_CLOUD) { return ADV_CLOUD_IOR; }
    return ADV_AIR_IOR;
}

vec3 mediumExtinction(uint medium) {
    if (medium == ADV_MEDIUM_WATER) { return ADV_WATER_EXTINCTION; }
    if (medium == ADV_MEDIUM_CLOUD) { return ADV_CLOUD_EXTINCTION; }
    if (medium == ADV_MEDIUM_AIR) { return ADV_AIR_EXTINCTION; }
    return vec3(0.0);
}

vec3 segmentTransmittance(uint medium, float distance) {
    float d = clamp(distance, 0.0, ADV_MAX_MEDIA_EXTINCTION_DISTANCE);
    return exp(-max(mediumExtinction(medium), vec3(0.0)) * d);
}

float cosCriticalAngle(float sourceIor, float destinationIor) {
    sourceIor = max(sourceIor, 1e-4);
    destinationIor = max(destinationIor, 1e-4);
    if (sourceIor <= destinationIor) { return -1.0; }
    float ratio = clamp(destinationIor / sourceIor, 0.0, 1.0);
    return sqrt(max(1.0 - ratio * ratio, 0.0));
}

float interfaceFresnel(float cosIncident, float sourceIor, float destinationIor) {
    float criticalCos = cosCriticalAngle(sourceIor, destinationIor);
    float adjustedCos = criticalCos < 0.0 ? clamp(cosIncident, 0.0, 1.0) :
                                            clamp((cosIncident - criticalCos) / max(1.0 - criticalCos, 1e-5), 0.0, 1.0);
    float denominator = max(sourceIor + destinationIor, 1e-5);
    float r0 = (destinationIor - sourceIor) / denominator;
    r0 *= r0;
    float oneMinusCos = 1.0 - adjustedCos;
    return clamp(r0 + (1.0 - r0) * oneMinusCos * oneMinusCos * oneMinusCos * oneMinusCos * oneMinusCos, 0.0, 1.0);
}

uint selectAction(CheckerAction actions, bool isEvenField, bool isAlreadySplit, bool hasTotalInternalReflection) {
    if (hasTotalInternalReflection) { return actions.totalReflectionAction; }
    if (isAlreadySplit) { return actions.splitAction; }
    return isEvenField ? actions.evenAction : actions.oddAction;
}

bool isCameraUnderwater(uint cameraSubmersionType) {
    return cameraSubmersionType == 1u;
}

#endif
