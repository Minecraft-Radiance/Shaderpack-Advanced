#ifndef ADV_ENVIRONMENT_CLOUD_DENSITY_GLSL
#define ADV_ENVIRONMENT_CLOUD_DENSITY_GLSL

#include "environment/cloud/atmosphere.glsl"

CloudSampleContext invalidCloudSampleContext() {
    CloudSampleContext context;
    context.positionKm = vec3(0.0);
    context.windOffset = vec3(0.0);
    context.coverage = 0.0;
    context.gradientShape = 0.0;
    context.layerHeight01 = 0.0;
    context.layerIndex = -1;
    return context;
}

CloudMacroContext invalidCloudMacroContext() {
    CloudMacroContext context;
    context.coverage = 0.0;
    context.gradientShape = 0.0;
    context.layerHeight01 = 0.0;
    context.layerIndex = -1;
    return context;
}

CloudMacroContext buildCloudMacroLayer0Context(vec3 sampleWorldPos, float layerHeight01) {
    CloudMacroContext context = invalidCloudMacroContext();
    vec3 positionMeters = cloudPositionWS(sampleWorldPos);
    vec3 windDirection = cloudWindDirection();
    float time = cloudTime();
    float cloudSpeed = 0.05;
    float overcastBlend = cloudOvercastBlend();
    float clearCoverageDrift = mix(cloudClearCoverageDrift(), 1.0, overcastBlend);
    float clearAmountScale = cloudClearAmountScale();
    float coverageBase = cloudCoverageBase(ADV_CLOUD_COVERAGE * 0.92 * clearCoverageDrift * clearAmountScale,
                                           max(ADV_CLOUD_COVERAGE + 0.12, 0.72));

    positionMeters += windDirection * layerHeight01 * 500.0;
    vec2 stableKmXZ = positionMeters.xz * 0.001;
    vec2 weatherUv = stableKmXZ * ADV_CLOUD_WEATHER_SCALE;
    vec4 weatherValue = textureLod(cloudWeatherTexture, weatherUv, 1.0);
    float weatherCoverage = cloudWeatherSignal(weatherValue.x, 0.72, -0.04, 0.58);

    vec2 animatedWorldXZ = positionMeters.xz + vec2(time * cloudSpeed * 50.0);
    float localCoverage = sampleCloudMacroCoverageNoise(animatedWorldXZ, 0.00000060, vec2(0.50));
    localCoverage = remapCloudValueClamped(localCoverage, 0.34, 0.76, 0.0, 1.0) * mix(0.18, 0.22, overcastBlend);

    float combinedCoverage = max(saturateCloudValue(localCoverage + weatherCoverage), overcastBlend * 0.60);
    context.coverage = saturateCloudValue(coverageBase * combinedCoverage);
    context.gradientShape = remapCloudValueClamped(layerHeight01, 0.10, 0.80, coverageBase * 1.9, 0.2) *
                            remapCloudValueClamped(layerHeight01, 0.00, 0.10, 0.5, 1.0);
    context.layerHeight01 = layerHeight01;
    context.layerIndex = 0;
    return context;
}

CloudMacroContext buildCloudMacroLayer1Context(vec3 sampleWorldPos, float layerHeight01) {
    CloudMacroContext context = invalidCloudMacroContext();
    vec3 positionMeters = cloudPositionWS(sampleWorldPos);
    vec3 windDirection = cloudWindDirection();
    float time = cloudTime();
    float cloudSpeed = 0.05;
    float overcastBlend = cloudOvercastBlend();
    float clearCoverageDrift = mix(cloudClearCoverageDrift(), 1.0, overcastBlend);
    float clearAmountScale = cloudClearAmountScale();
    float coverageBase = cloudCoverageBase(ADV_CLOUD_COVERAGE * 0.60 * clearCoverageDrift * clearAmountScale,
                                           max(ADV_CLOUD_COVERAGE + 0.08, 0.54));

    positionMeters += windDirection * layerHeight01 * 500.0;
    vec2 stableKmXZ = positionMeters.xz * 0.001;
    vec2 weatherKmXZ = stableKmXZ;
    vec2 weatherUv = weatherKmXZ * ADV_CLOUD_WEATHER_SCALE * 0.5 + 0.39;
    weatherUv.y *= 2.0;
    vec4 weatherValue = textureLod(cloudWeatherTexture, weatherUv, 1.0);
    float weatherCoverage = cloudWeatherSignal(weatherValue.x, 0.56, -0.12, 0.34);

    vec2 animatedWorldXZ = positionMeters.xz + vec2(time * cloudSpeed * 50.0 * mix(1.0, 0.10, overcastBlend));
    float localCoverage = sampleCloudMacroCoverageNoise(animatedWorldXZ, 0.00000072, vec2(-0.11, -0.11));
    localCoverage = remapCloudValueClamped(localCoverage, 0.38, 0.78, 0.0, 1.0) * mix(0.24, 0.28, overcastBlend);

    float combinedCoverage = max(saturateCloudValue(localCoverage + weatherCoverage), overcastBlend * 0.36);
    context.coverage = saturateCloudValue(coverageBase * combinedCoverage);
    context.gradientShape = remapCloudValueClamped(layerHeight01, 0.00, 0.01, 0.1, 1.0) *
                            remapCloudValueClamped(layerHeight01, 0.10, 0.80, 0.7, 0.2);
    context.layerHeight01 = layerHeight01;
    context.layerIndex = 1;
    return context;
}

CloudMacroContext buildCloudMacroLayer2Context(vec3 sampleWorldPos, float layerHeight01) {
    CloudMacroContext context = invalidCloudMacroContext();
    vec3 positionMeters = cloudPositionWS(sampleWorldPos);
    vec3 windDirection = cloudWindDirection();
    float time = cloudTime();
    float cloudSpeed = 0.05;
    float overcastBlend = cloudOvercastBlend();
    float clearCoverageDrift = mix(cloudClearCoverageDrift(), 1.0, overcastBlend);
    float clearAmountScale = cloudClearAmountScale();
    float coverageBase =
        cloudCoverageBase(ADV_CLOUD_COVERAGE * 0.46 * clearCoverageDrift * clearAmountScale, ADV_CLOUD_COVERAGE * 0.22);

    positionMeters += windDirection * layerHeight01 * 500.0;
    vec2 stableKmXZ = positionMeters.xz * 0.001;
    vec2 weatherKmXZ = stableKmXZ;
    vec2 weatherUv = weatherKmXZ * ADV_CLOUD_WEATHER_SCALE * 0.6 + 0.739;
    weatherUv.y *= 6.0;
    vec4 weatherValue = textureLod(cloudWeatherTexture, weatherUv, 1.0);
    float weatherCoverage = cloudWeatherSignal(weatherValue.x, 0.35, -0.30, 0.0);

    float localCoverage =
        textureLod(cloudCoverageNoiseTexture, (time * cloudSpeed * 50.0 + positionMeters.xz) * 0.000001 - 0.39, 1.5).x;
    localCoverage = saturateCloudValue(1.0 - pow(localCoverage, 8.0)) * mix(0.26, 0.12, overcastBlend);

    context.coverage = saturateCloudValue(coverageBase * (localCoverage + weatherCoverage));
    context.gradientShape = remapCloudValueClamped(layerHeight01, 0.00, 0.01, 0.1, 1.0) *
                            remapCloudValueClamped(layerHeight01, 0.10, 0.20, 0.8, 0.5);
    context.layerHeight01 = layerHeight01;
    context.layerIndex = 2;
    return context;
}

CloudMacroContext sampleCloudMacroContext(vec3 sampleWorldPos) {
    vec3 planetPos = cloudPositionPS(sampleWorldPos);
    float normalizedHeight = cloudNormalizedHeight(planetPos);
    if (normalizedHeight <= 0.0 || normalizedHeight >= 1.0) { return invalidCloudMacroContext(); }

    if (normalizedHeight < 0.4) {
        float layerHeight01 = normalizedHeight / 0.4;
        return buildCloudMacroLayer0Context(sampleWorldPos, layerHeight01);
    }
    if (normalizedHeight < 0.8) {
        float layerHeight01 = (normalizedHeight - 0.4) / 0.4;
        return buildCloudMacroLayer1Context(sampleWorldPos, layerHeight01);
    }

    float layerHeight01 = (normalizedHeight - 0.8) / 0.2;
    return buildCloudMacroLayer2Context(sampleWorldPos, layerHeight01);
}

float cloudMacroOccupancy(CloudMacroContext context) {
    if (context.layerIndex < 0) { return 0.0; }
    return saturateCloudValue(context.coverage * max(saturateCloudValue(context.gradientShape), 0.35) * 1.25 + 0.002);
}

float estimateCloudMacroDensity(CloudMacroContext context) {
    if (context.layerIndex < 0) { return 0.0; }

    float macroOccupancy = cloudMacroOccupancy(context);
    float layerWeight = 0.0;
    if (context.layerIndex == 0) {
        layerWeight = 0.78;
    } else if (context.layerIndex == 1) {
        layerWeight = 0.46;
    } else {
        layerWeight = 0.24;
    }

    float heightWeight = remapCloudValueClamped(context.layerHeight01, 0.0, 0.18, 0.55, 1.0) *
                         remapCloudValueClamped(context.layerHeight01, 0.78, 1.0, 1.0, 0.65);
    return macroOccupancy * layerWeight * heightWeight;
}

CloudSampleContext buildCloudTransportContext(vec3 sampleWorldPos, CloudMacroContext macroContext) {
    if (macroContext.layerIndex < 0) { return invalidCloudSampleContext(); }

    CloudSampleContext context = invalidCloudSampleContext();
    vec3 windDirection = cloudWindDirection();
    float cloudSpeed = 0.05;
    vec3 positionMeters = cloudPositionWS(sampleWorldPos);
    positionMeters += windDirection * macroContext.layerHeight01 * 500.0;

    context.positionKm = positionMeters * 0.001;
    context.windOffset = (windDirection + vec3(0.0, 0.1, 0.0)) * cloudTime() * cloudSpeed;
    context.coverage = macroContext.coverage;
    context.gradientShape = macroContext.gradientShape;
    context.layerHeight01 = macroContext.layerHeight01;
    context.layerIndex = macroContext.layerIndex;
    return context;
}

CloudSampleContext makeCloudViewContext(vec3 sampleWorldPos, CloudMacroContext macroContext) {
    if (macroContext.layerIndex < 0) { return invalidCloudSampleContext(); }

    CloudSampleContext context = invalidCloudSampleContext();
    vec3 positionMeters = cloudPositionWS(sampleWorldPos);
    vec3 windDirection = cloudWindDirection();
    float time = cloudTime();
    float cloudSpeed = 0.05;

    positionMeters += windDirection * macroContext.layerHeight01 * 500.0;
    context.positionKm = positionMeters * 0.001;

    if (macroContext.layerIndex == 0) {
        vec3 curl =
            texture(cloudCurlNoiseTexture, (time * cloudSpeed * 50.0 + positionMeters.xz) * 0.0000008 + 0.7).xyz;
        context.positionKm += (curl * 2.0 - 1.0) * 2.0;
    } else if (macroContext.layerIndex == 1) {
        vec3 curl = texture(cloudCurlNoiseTexture, (time * cloudSpeed * 50.0 + positionMeters.xz) * 0.000001 - 0.3).xyz;
        context.positionKm += (curl * 2.0 - 1.0) * 5.0;
    } else {
        vec3 curl =
            texture(cloudCurlNoiseTexture, (time * cloudSpeed * 50.0 + positionMeters.xz) * 0.00000125 + 0.7).xyz;
        context.positionKm += (curl * 2.0 - 1.0) * 10.0;
    }

    context.windOffset = (windDirection + vec3(0.0, 0.1, 0.0)) * time * cloudSpeed;
    context.coverage = macroContext.coverage;
    context.gradientShape = macroContext.gradientShape;
    context.layerHeight01 = macroContext.layerHeight01;
    context.layerIndex = macroContext.layerIndex;
    return context;
}

float sampleCloudDensityForView(CloudSampleContext context,
                                bool shouldSampleDetailNoise,
                                float basicNoiseLod,
                                float detailNoiseLod) {
    if (context.layerIndex < 0) { return 0.0; }

    if (context.layerIndex == 0) {
        float densityBase = ADV_CLOUD_DENSITY * mix(1.60, 2.10, cloudOvercastBlend());
        float basicNoise =
            textureLod(cloudShapeNoiseTexture, fract((context.positionKm + context.windOffset) * ADV_CLOUD_BASE_SCALE),
                       basicNoiseLod)
                .r;
        float basicCloudNoise = context.gradientShape * basicNoise;
        float basicCloudWithCoverage =
            context.coverage * remapCloudValueClamped(basicCloudNoise, 1.0 - context.coverage, 1.0, 0.0, 1.0);

        float detailNoiseMixByHeight = 0.10;
        if (shouldSampleDetailNoise) {
            vec3 sampleDetailNoise = context.positionKm - context.windOffset * 0.15;
            float detailNoiseComposite =
                textureLod(cloudDetailNoiseTexture, fract(sampleDetailNoise * ADV_CLOUD_DETAIL_SCALE), detailNoiseLod)
                    .r;
            detailNoiseMixByHeight = 0.2 * mix(detailNoiseComposite, 1.0 - detailNoiseComposite,
                                               saturateCloudValue(context.layerHeight01 * 10.0));
        }

        float densityShape = saturateCloudValue(0.01 + (1.0 - context.layerHeight01) * 0.5) * 0.25 *
                             remapCloudValueClamped(context.layerHeight01, 0.0, 0.3, 0.0, 1.0) *
                             remapCloudValueClamped(context.layerHeight01, 0.7, 1.0, 1.0, 0.0);

        float cloudDensity =
            densityShape * remapCloudValueClamped(basicCloudWithCoverage, detailNoiseMixByHeight, 1.0, 0.0, 1.0);
        cloudDensity =
            pow(cloudDensity, saturateCloudValue(1.0 - context.layerHeight01) * 0.4 + 0.1) * densityBase * 0.1;
        return saturateCloudValue(cloudDensity);
    }

    if (context.layerIndex == 1) {
        float densityBase = ADV_CLOUD_DENSITY * mix(0.26, 0.40, cloudOvercastBlend());
        float basicNoise =
            textureLod(cloudShapeNoiseTexture,
                       fract(2.0 * (context.positionKm + context.windOffset) * ADV_CLOUD_BASE_SCALE), basicNoiseLod)
                .r;
        float basicCloudNoise = context.gradientShape * basicNoise;
        float basicCloudWithCoverage =
            context.coverage * remapCloudValueClamped(basicCloudNoise, 1.0 - context.coverage, 1.0, 0.0, 1.0);

        float detailNoiseMixByHeight = 0.10;
        if (shouldSampleDetailNoise) {
            vec3 sampleDetailNoise = context.positionKm - context.windOffset * 0.15;
            float detailNoiseComposite =
                textureLod(cloudDetailNoiseTexture, fract(2.0 * sampleDetailNoise * ADV_CLOUD_DETAIL_SCALE),
                           detailNoiseLod)
                    .r;
            detailNoiseMixByHeight = 0.2 * mix(detailNoiseComposite, 1.0 - detailNoiseComposite,
                                               saturateCloudValue(context.layerHeight01 * 10.0));
        }

        float densityShape = saturateCloudValue(0.01 + (1.0 - context.layerHeight01) * 0.5) * 0.1 *
                             remapCloudValueClamped(context.layerHeight01, 0.0, 0.3, 0.0, 1.0) *
                             remapCloudValueClamped(context.layerHeight01, 0.7, 1.0, 1.0, 0.0);

        float cloudDensity =
            densityShape * remapCloudValueClamped(basicCloudWithCoverage, detailNoiseMixByHeight, 1.0, 0.0, 1.0);
        cloudDensity =
            pow(cloudDensity, saturateCloudValue(1.0 - context.layerHeight01) * 0.4 + 0.1) * densityBase * 0.1;
        return saturateCloudValue(cloudDensity);
    }

    float densityBase = ADV_CLOUD_DENSITY * mix(0.12, 0.09, cloudOvercastBlend());
    vec3 layer2NoisePosition = 3.0 * (context.positionKm + context.windOffset + 0.39) * ADV_CLOUD_BASE_SCALE;
    float basicNoise = textureLod(cloudShapeNoiseTexture, fract(layer2NoisePosition), basicNoiseLod).r;
    float basicCloudNoise = context.gradientShape * basicNoise;
    float basicCloudWithCoverage =
        context.coverage * remapCloudValueClamped(basicCloudNoise, 1.0 - context.coverage, 1.0, 0.0, 1.0);

    float densityShape = saturateCloudValue(0.01 + (1.0 - context.layerHeight01) * 0.5) * 0.1 *
                         remapCloudValueClamped(context.layerHeight01, 0.0, 0.3, 0.0, 1.0) *
                         remapCloudValueClamped(context.layerHeight01, 0.7, 1.0, 1.0, 0.0);

    return saturateCloudValue(densityShape * basicCloudWithCoverage * densityBase);
}

float sampleCloudDensityForTransport(CloudSampleContext context) {
    return sampleCloudDensityForView(context, false, 1.5, 1.5);
}

int cloudSkipStepCount(float macroOccupancy, bool isBeforeFirstHit) {
    if (macroOccupancy < 0.004) { return isBeforeFirstHit ? 6 : 3; }
    if (macroOccupancy < 0.012) { return isBeforeFirstHit ? 4 : 2; }
    if (macroOccupancy < 0.025) { return 2; }
    return 1;
}

#endif
