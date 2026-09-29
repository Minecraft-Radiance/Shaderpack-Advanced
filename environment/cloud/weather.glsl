#ifndef ADV_ENVIRONMENT_CLOUD_WEATHER_GLSL
#define ADV_ENVIRONMENT_CLOUD_WEATHER_GLSL

#include "environment/cloud/spatial.glsl"

float cloudRainBlend() {
    return skyUBO.rainGradient;
}

float cloudOvercastBlend() {
    return smoothstep(0.02, 0.20, cloudRainBlend());
}

float cloudClearAmountScale() {
    if (ADV_CLOUD_CLEAR_AMOUNT == ADV_CLOUD_CLEAR_AMOUNT_FEW) { return 0.82; }
    if (ADV_CLOUD_CLEAR_AMOUNT == ADV_CLOUD_CLEAR_AMOUNT_MANY) { return 1.22; }
    return 1.0;
}

float cloudClearCoverageDrift() {
    float cloudTime = cloudTime();
    float wave = 0.50 * sin(cloudTime * 0.00013) + 0.35 * sin(cloudTime * 0.000057 + 1.7) +
                 0.15 * sin(cloudTime * 0.000031 - 0.8);
    return 1.0 + 0.08 * wave;
}

float sampleCloudMacroCoverageNoise(vec2 animatedWorldXZ, float scale, vec2 offset) {
    return textureLod(cloudCoverageNoiseTexture, animatedWorldXZ * scale + offset, 1.5).x;
}

float cloudCoverageBase(float clearBase, float rainyBase) {
    return saturateCloudValue(mix(clearBase, rainyBase, cloudOvercastBlend()));
}

float cloudWeatherSignal(float weatherValue, float clearScale, float clearBias, float rainyFloor) {
    float clearSignal = saturateCloudValue(weatherValue * clearScale + clearBias);
    return saturateCloudValue(mix(clearSignal, max(clearSignal, rainyFloor), cloudOvercastBlend()));
}

#endif
