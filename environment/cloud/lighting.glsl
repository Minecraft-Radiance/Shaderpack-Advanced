#ifndef ADV_ENVIRONMENT_CLOUD_LIGHTING_GLSL
#define ADV_ENVIRONMENT_CLOUD_LIGHTING_GLSL

#include "environment/cloud/density.glsl"

vec2 cloudPhaseWeights(float basePhase) {
    float uniformPhase = 1.0 / (4.0 * PI);
    return vec2(basePhase, mix(uniformPhase, basePhase, 0.5));
}

vec2 estimateCloudLightTransport(
    vec3 rayOrigin, vec3 rayDirection, float maxDistance, int minimumSteps, float multiScatterExtinction) {
    if (maxDistance <= 1e-3 || minimumSteps <= 0) { return vec2(1.0); }

    int sampleCount = clamp((minimumSteps + 1) / 2, 1, 3);
    float stepLength = maxDistance / float(sampleCount);
    float extinctionAcc = 0.0;

    for (int sampleIndex = 0; sampleIndex < 3; ++sampleIndex) {
        if (sampleIndex >= sampleCount) { break; }

        float sampleDistance = (float(sampleIndex) + 0.5) * stepLength;
        vec3 samplePos = rayOrigin + rayDirection * sampleDistance;
        CloudMacroContext macroContext = sampleCloudMacroContext(samplePos);
        float densityEstimate = estimateCloudMacroDensity(macroContext);
        if (densityEstimate <= 1e-5) { continue; }

        CloudSampleContext context = makeCloudViewContext(samplePos, macroContext);
        float density = sampleCloudDensityForTransport(context);
        extinctionAcc += density * stepLength;
    }

    float singleScatter = exp(-extinctionAcc);
    float multiScatter = exp(-extinctionAcc * multiScatterExtinction);
    return vec2(singleScatter, multiScatter);
}

float cloudLightVisibility(vec3 absoluteWorldPos, vec3 lightDirection, int minimumSteps, float multiScatterExtinction) {
    if (ADV_CLOUD_MODE != 2u || ADV_CLOUD_SHADOWS_ENABLED == 0) { return 1.0; }

    float horizonShadowWeight = smoothstep(0.06, 0.24, max(lightDirection.y, 0.0));
    float cloudShadowWeight = horizonShadowWeight * clamp(ADV_CLOUD_SHADOW_STRENGTH, 0.0, 1.0);
    float cloudShadowSoftness = clamp(ADV_CLOUD_SHADOW_SOFTNESS, 0.0, 1.0);
    if (cloudShadowWeight <= 1e-4) { return 1.0; }

    vec3 rayOrigin = absoluteWorldPos - vec3(worldUBO.cameraPos.xyz);
    vec3 traceOrigin = rayOrigin + lightDirection * 5.0;
    vec3 cloudTraceOrigin;
    float lightDistance;
    if (!findCloudSegment(traceOrigin, lightDirection, cloudTraceOrigin, lightDistance)) { return 1.0; }
    traceOrigin = cloudTraceOrigin;

    float cloudLightVisibility = estimateCloudLightTransport(traceOrigin, lightDirection, lightDistance,
                                                             max(minimumSteps, 1), multiScatterExtinction)
                                     .x;
    if (cloudShadowSoftness > 1e-4) {
        vec3 shadowTangent =
            normalizeCloudDirectionSafe(cross(lightDirection, vec3(0.0, 1.0, 0.0)), vec3(1.0, 0.0, 0.0));
        vec3 shadowBitangent = normalizeCloudDirectionSafe(cross(lightDirection, shadowTangent), vec3(0.0, 0.0, 1.0));
        vec3 shadowOffsetDir = normalizeCloudDirectionSafe(shadowTangent + shadowBitangent * 0.5, shadowTangent);
        float shadowSampleRadius = clamp(lightDistance * 0.04, 40.0, 450.0) * cloudShadowSoftness;
        int offsetStepCount = max(minimumSteps / 2, 1);

        vec3 positiveTraceOrigin = traceOrigin + shadowOffsetDir * shadowSampleRadius;
        vec3 positiveCloudTraceOrigin;
        float positiveLightDistance;
        float positiveCloudLightVisibility =
            !findCloudSegment(positiveTraceOrigin, lightDirection, positiveCloudTraceOrigin, positiveLightDistance) ?
                1.0 :
                estimateCloudLightTransport(positiveCloudTraceOrigin, lightDirection, positiveLightDistance,
                                            offsetStepCount, multiScatterExtinction)
                    .x;

        vec3 negativeTraceOrigin = traceOrigin - shadowOffsetDir * shadowSampleRadius;
        vec3 negativeCloudTraceOrigin;
        float negativeLightDistance;
        float negativeCloudLightVisibility =
            !findCloudSegment(negativeTraceOrigin, lightDirection, negativeCloudTraceOrigin, negativeLightDistance) ?
                1.0 :
                estimateCloudLightTransport(negativeCloudTraceOrigin, lightDirection, negativeLightDistance,
                                            offsetStepCount, multiScatterExtinction)
                    .x;

        float filteredCloudLightVisibility =
            cloudLightVisibility * 0.50 + (positiveCloudLightVisibility + negativeCloudLightVisibility) * 0.25;
        cloudLightVisibility = mix(cloudLightVisibility, filteredCloudLightVisibility, cloudShadowSoftness);
    }
    return mix(1.0, cloudLightVisibility, cloudShadowWeight);
}

vec3 sampleCloudHorizonSkyRadiance(vec3 rayDirection, bool indirectLighting);
vec3 sampleCloudBelowHorizonSkyRadiance(vec3 rayDirection, bool indirectLighting);

vec3 applyCloudRainFilter(vec3 clearSky, float darkness, bool indirectLighting) {
    float rainBlend = cloudRainBlend();
    float luminance = dot(max(clearSky, vec3(0.0)), vec3(0.2126, 0.7152, 0.0722));
    vec3 desaturatedSky = mix(clearSky, vec3(luminance), 0.72);
    vec3 rainyBase = getOvercastSkyRadiance(clearSky) * darkness;
    vec3 rainySky = mix(desaturatedSky, rainyBase, 0.85);
    return mix(clearSky, rainySky, rainBlend);
}

vec3 sampleCloudAmbientIrradiance(vec3 up, bool indirectLighting) {
    vec3 horizonX = sampleCloudHorizonSkyRadiance(normalize(vec3(1.0, max(up.y, 0.0), 0.0)), indirectLighting);
    vec3 horizonZ = sampleCloudHorizonSkyRadiance(normalize(vec3(0.0, max(up.y, 0.0), 1.0)), indirectLighting);
    vec3 skyUp = cloudSkyRadiance(up, indirectLighting);
    vec3 ambient = skyUp * 0.55 + 0.225 * (horizonX + horizonZ);
    return ambient * ADV_CLOUD_AMBIENT_STRENGTH;
}

vec3 cloudGroundBounceBase(vec3 up, bool indirectLighting) {
    vec3 lowerHorizon = sampleCloudBelowHorizonSkyRadiance(-up, indirectLighting);
    vec3 horizon = sampleCloudHorizonSkyRadiance(vec3(up.x, 0.02, up.z), indirectLighting);
    vec3 groundBounce = mix(lowerHorizon, horizon, 0.35);
    float lift = 1.0 - dot(cloudLightDirection(), vec3(0.0, 1.0, 0.0));
    lift *= 1.0 + lift;
    return groundBounce * clamp(lift, 0.0, 1.0);
}

vec3 applyCloudGroundBounceBase(vec3 groundBounceBase, float transmittance, float powderEffect) {
    return groundBounceBase * powderEffect * mix(vec3(1.0), vec3(1.35), saturateCloudValue(1.0 - transmittance));
}

float cloudLuminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

vec3 sampleCloudHorizonSkyRadiance(vec3 rayDirection, bool indirectLighting) {
    float blend = smoothstep(-0.05, 0.02, rayDirection.y);
    vec3 clampedDir = rayDirection;
    clampedDir.y = max(clampedDir.y, ADV_ATMOSPHERE_MIN_VIEW_COS);
    clampedDir = normalize(mix(vec3(rayDirection.x, ADV_ATMOSPHERE_MIN_VIEW_COS, rayDirection.z), clampedDir, blend));
    vec3 clearSky = indirectLighting ? texture(skyIndirectRadianceTexture, clampedDir).rgb :
                                       texture(skyRadianceTexture, clampedDir).rgb;
    return applyCloudRainFilter(clearSky, 0.95, indirectLighting);
}

vec3 sampleCloudBelowHorizonSkyRadiance(vec3 rayDirection, bool indirectLighting) {
    const float belowHorizonCos = ADV_ATMOSPHERE_MIN_VIEW_COS - 0.035;
    float blend = smoothstep(-0.06, 0.03, rayDirection.y);
    vec3 biasedDir = rayDirection;
    biasedDir.y = max(biasedDir.y, belowHorizonCos);
    biasedDir = normalize(mix(vec3(rayDirection.x, belowHorizonCos, rayDirection.z), biasedDir, blend));
    vec3 clearSky = indirectLighting ? texture(skyIndirectRadianceTexture, biasedDir).rgb :
                                       texture(skyRadianceTexture, biasedDir).rgb;
    return applyCloudRainFilter(clearSky, 0.70, indirectLighting);
}

float cloudHorizonFade(vec3 rayDirection, vec3 cloudWorldPos, float cloudDistance) {
    vec3 planetPos = cloudPositionPS(cloudWorldPos);
    vec3 up = normalizeCloudDirectionSafe(planetPos, vec3(0.0, 1.0, 0.0));

    float horizonView = 1.0 - smoothstep(0.015, 0.070, dot(rayDirection, up));
    float farFade = smoothstep(24000.0, 90000.0, cloudDistance);

    float height01 = cloudNormalizedHeight(planetPos);
    float heightFade = 1.0 - smoothstep(0.22, 0.65, height01);

    return clamp(horizonView * farFade * heightFade, 0.0, 1.0);
}

float cloudHorizonMatch(vec3 rayDirection) {
    return 1.0 - smoothstep(0.035, 0.16, rayDirection.y);
}

float cloudHorizonMissMix(vec3 rayDirection) {
    return 1.0 - smoothstep(0.0, 0.08, rayDirection.y);
}

#endif
