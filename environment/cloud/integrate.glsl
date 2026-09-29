#ifndef ADV_ENVIRONMENT_CLOUD_INTEGRATE_GLSL
#define ADV_ENVIRONMENT_CLOUD_INTEGRATE_GLSL

#include "environment/cloud/lighting.glsl"

CloudRadiance integrateCloudSegment(vec3 rayOrigin,
                                    vec3 rayDirection,
                                    vec3 skyBackgroundRadiance,
                                    int viewStepCount,
                                    int lightStepCount,
                                    int ambientStepCount,
                                    bool indirectLighting) {
    CloudRadiance cloudRadiance;
    cloudRadiance.radiance = skyBackgroundRadiance;
    cloudRadiance.transmittance = 1.0;
    cloudRadiance.hitMask = 0.0;

    if (worldUBO.skyType != 1) { return cloudRadiance; }
    if (ADV_CLOUD_MODE != 2u) { return cloudRadiance; }

    float enterDistance, exitDistance;
    if (!intersectCloudLayer(rayOrigin, rayDirection, enterDistance, exitDistance)) { return cloudRadiance; }

    float totalLength = exitDistance - enterDistance;
    if (totalLength <= 1e-3) { return cloudRadiance; }

    vec3 dominantLightDir = cloudLightDirection();
    vec3 primaryLightRadiance = cloudLightRadiance(indirectLighting);
    vec3 surfaceSunsetTint = getCelestialSunsetTint(getCelestialSunDirection().y);
    vec3 horizonBase = sampleCloudHorizonSkyRadiance(rayDirection, indirectLighting);
    vec3 belowHorizonBase = sampleCloudBelowHorizonSkyRadiance(rayDirection, indirectLighting);
    float horizonMatch = cloudHorizonMatch(rayDirection);
    float primaryLightScale = cloudLightScale();
    float directLightInfluence = smoothstep(0.02, 0.35, primaryLightScale);
    float viewToLight = clamp(dot(rayDirection, dominantLightDir), -1.0, 1.0);
    float directionalViewToLight = mix(0.0, viewToLight, directLightInfluence);
    float basePhase = evaluateDualLobePhase(0.5, -0.5, 0.5, -directionalViewToLight);
    vec2 phases = cloudPhaseWeights(basePhase);

    viewStepCount = max(viewStepCount, 1);
    lightStepCount = max(lightStepCount, 1);
    ambientStepCount = max(ambientStepCount, 1);
    int lightTransportReuseSteps = clamp(viewStepCount / 12, 3, 8);
    int ambientTransportReuseSteps = clamp(viewStepCount / 10, 3, 8);
    float stepLength = totalLength / float(viewStepCount);
    float transmittance = 1.0;
    vec3 scattering = vec3(0.0);
    vec3 weightedWorldPos = vec3(0.0);
    float weightedWorldPosWeight = 0.0;
    float sunsetScale = 1.0 + saturateCloudValue(1.0 - dominantLightDir.y * 2.0);
    float cloudShadowSoftness = clamp(ADV_CLOUD_SHADOW_SOFTNESS, 0.0, 1.0);
    vec2 cachedSunTransport = vec2(1.0);
    vec2 cachedAmbientTransport = vec2(1.0);
    vec3 cachedSunAtmosphereTransmittance = vec3(1.0);
    vec3 cachedAmbientIrradiance = sampleCloudAmbientIrradiance(vec3(0.0, 1.0, 0.0), indirectLighting);
    vec3 cachedTopAmbientIrradiance = cachedAmbientIrradiance;
    vec3 cachedGroundBounceBase = cloudGroundBounceBase(vec3(0.0, 1.0, 0.0), indirectLighting);
    int sunTransportCountdown = 0;
    int ambientTransportCountdown = 0;
    float previousDensity = 0.0;
    float previousLayerHeight01 = 0.0;
    bool hasPreviousDensity = false;
    float rainBlend = cloudRainBlend();
    float distanceJitter = sampleCloudStepJitter(17.0);

    for (int stepIndex = 0; stepIndex < viewStepCount; ++stepIndex) {
        float cloudDistance = calculateJitteredCloudDistance(stepIndex, stepLength, distanceJitter, totalLength);
        float sampleDistance = enterDistance + cloudDistance;
        vec3 samplePos = rayOrigin + rayDirection * sampleDistance;

        CloudMacroContext macroContext = sampleCloudMacroContext(samplePos);
        float macroOccupancy = cloudMacroOccupancy(macroContext);
        int skipCount = cloudSkipStepCount(macroOccupancy, cloudRadiance.hitMask < 0.5);
        if (skipCount > 1) {
            stepIndex += min(skipCount - 1, viewStepCount - 1 - stepIndex);
            continue;
        }
        if (macroOccupancy <= 1e-5) { continue; }

        float viewDistance01 = clamp(cloudDistance / max(totalLength, 1e-4), 0.0, 1.0);
        float densityEstimate = estimateCloudMacroDensity(macroContext);
        float densityCullThreshold = mix(0.008, 0.022, viewDistance01);
        if (densityEstimate <= densityCullThreshold) { continue; }

        CloudSampleContext sampleContext = makeCloudViewContext(samplePos, macroContext);
        bool hasPreviousCloudHit = cloudRadiance.hitMask >= 0.5;
        bool shouldSampleDetailNoise = viewDistance01 < 0.42 || !hasPreviousCloudHit;
        float basicNoiseLod = viewDistance01 > 0.60 ? 1.5 : (viewDistance01 > 0.35 ? 1.0 : 0.0);
        float detailNoiseLod = viewDistance01 > 0.42 ? 1.0 : 0.0;
        float density =
            sampleCloudDensityForView(sampleContext, shouldSampleDetailNoise, basicNoiseLod, detailNoiseLod);
        if (density <= 1e-5) { continue; }

        cloudRadiance.hitMask = 1.0;
        weightedWorldPos += samplePos * transmittance;
        weightedWorldPosWeight += transmittance;

        float opticalDepth = density * stepLength;
        float stepTransmittance = max(exp(-opticalDepth), exp(-opticalDepth * 0.25) * 0.70);

        bool shouldRefreshSunTransport = sunTransportCountdown <= 0;
        bool shouldRefreshAmbientTransport = ambientTransportCountdown <= 0;
        if (hasPreviousDensity) {
            float densityDelta = abs(density - previousDensity);
            float layerDelta = abs(sampleContext.layerHeight01 - previousLayerHeight01);
            shouldRefreshSunTransport =
                shouldRefreshSunTransport || densityDelta > 0.10 || layerDelta > 0.14 || sampleContext.coverage < 0.10;
            shouldRefreshAmbientTransport = shouldRefreshAmbientTransport || densityDelta > 0.12 || layerDelta > 0.18;
        }

        vec3 cloudUp = vec3(0.0, 1.0, 0.0);
        float cloudSampleRadius = ADV_ATMOSPHERE_RG + ADV_CLOUD_BOTTOM_HEIGHT;
        if (shouldRefreshSunTransport || shouldRefreshAmbientTransport) {
            vec3 samplePlanetPos = cloudPositionPS(samplePos);
            cloudSampleRadius = clamp(length(samplePlanetPos), ADV_ATMOSPHERE_RG, ADV_ATMOSPHERE_RT);
            cloudUp = normalizeCloudDirectionSafe(samplePlanetPos, vec3(0.0, 1.0, 0.0));
        }

        if (shouldRefreshSunTransport) {
            cachedSunAtmosphereTransmittance =
                sampleCloudAtmosphereTransmittance(cloudSampleRadius, dot(cloudUp, dominantLightDir)) *
                getCelestialAtmosphereTint(surfaceSunsetTint, cloudSampleRadius - ADV_ATMOSPHERE_RG);
            vec3 sunTraceOrigin = samplePos + dominantLightDir * 5.0;
            float sunDistance = cloudSegmentLength(sunTraceOrigin, dominantLightDir);
            cachedSunTransport =
                estimateCloudLightTransport(sunTraceOrigin, dominantLightDir, sunDistance, lightStepCount, 0.175);
            if (cloudShadowSoftness > 1e-4) {
                vec3 shadowTangent =
                    normalizeCloudDirectionSafe(cross(dominantLightDir, vec3(0.0, 1.0, 0.0)), vec3(1.0, 0.0, 0.0));
                vec3 shadowBitangent =
                    normalizeCloudDirectionSafe(cross(dominantLightDir, shadowTangent), vec3(0.0, 0.0, 1.0));
                vec3 shadowOffsetDir =
                    normalizeCloudDirectionSafe(shadowTangent + shadowBitangent * 0.5, shadowTangent);
                float shadowSampleRadius = clamp(sunDistance * 0.04, 40.0, 450.0) * cloudShadowSoftness;
                int offsetStepCount = max(lightStepCount / 2, 1);

                vec3 positiveSunTraceOrigin = sunTraceOrigin + shadowOffsetDir * shadowSampleRadius;
                float positiveSunDistance = cloudSegmentLength(positiveSunTraceOrigin, dominantLightDir);
                vec2 positiveSunTransport =
                    positiveSunDistance <= 1e-3 ?
                        vec2(1.0) :
                        estimateCloudLightTransport(positiveSunTraceOrigin, dominantLightDir, positiveSunDistance,
                                                    offsetStepCount, 0.175);

                vec3 negativeSunTraceOrigin = sunTraceOrigin - shadowOffsetDir * shadowSampleRadius;
                float negativeSunDistance = cloudSegmentLength(negativeSunTraceOrigin, dominantLightDir);
                vec2 negativeSunTransport =
                    negativeSunDistance <= 1e-3 ?
                        vec2(1.0) :
                        estimateCloudLightTransport(negativeSunTraceOrigin, dominantLightDir, negativeSunDistance,
                                                    offsetStepCount, 0.175);

                vec2 filteredSunTransport =
                    cachedSunTransport * 0.50 + (positiveSunTransport + negativeSunTransport) * 0.25;
                cachedSunTransport = mix(cachedSunTransport, filteredSunTransport, cloudShadowSoftness);
            }
            sunTransportCountdown = lightTransportReuseSteps;
        } else {
            sunTransportCountdown -= 1;
        }

        if (shouldRefreshAmbientTransport) {
            cachedAmbientIrradiance = sampleCloudAmbientIrradiance(cloudUp, indirectLighting);
            cachedGroundBounceBase = cloudGroundBounceBase(cloudUp, indirectLighting);
            vec3 ambientTraceOrigin = samplePos + cloudUp * 5.0;
            float ambientDistance = cloudSegmentLength(ambientTraceOrigin, cloudUp);
            cachedAmbientTransport =
                estimateCloudLightTransport(ambientTraceOrigin, cloudUp, ambientDistance, ambientStepCount, 0.50);
            ambientTransportCountdown = ambientTransportReuseSteps;
        } else {
            ambientTransportCountdown -= 1;
        }

        float depthProbability = pow(clamp(density * 8.0, 0.0, 1.0),
                                     remapCloudValueClamped(sampleContext.layerHeight01, 0.3, 0.85, 0.5, 2.0)) +
                                 0.05;
        float verticalProbability = pow(remapCloudValueClamped(sampleContext.layerHeight01, 0.07, 0.22, 0.1, 1.0), 0.8);
        float powderEffect = mix(1.0, cloudPowderEffect(depthProbability, verticalProbability, directionalViewToLight),
                                 clamp(ADV_CLOUD_POWDER_STRENGTH, 0.0, 1.0) * directLightInfluence);

        vec3 groundBounceScatter = applyCloudGroundBounceBase(cachedGroundBounceBase, transmittance, powderEffect);
        vec3 distantAmbient = mix(belowHorizonBase, cachedTopAmbientIrradiance, 0.35);
        vec3 sunlightTerm = cachedSunAtmosphereTransmittance * primaryLightRadiance;
        vec3 sigmaScatter0 = vec3(density);
        vec3 sigmaScatter1 = sigmaScatter0;
        float sigmaE0 = max(density, 1e-5);
        float sigmaE1 = max(sigmaE0 * (0.175 / sunsetScale), 1e-5);

        for (int scatterLobeIndex = 1; scatterLobeIndex >= 0; --scatterLobeIndex) {
            float phaseTerm = scatterLobeIndex == 0 ? phases.x : phases.y;
            float lightVisibility = scatterLobeIndex == 0 ? cachedSunTransport.x : cachedSunTransport.y;
            vec3 incidentLight = lightVisibility * sunlightTerm * phaseTerm * powderEffect;
            if (scatterLobeIndex == 0) {
                incidentLight += cachedAmbientTransport.x * cachedAmbientIrradiance * powderEffect;
                incidentLight += groundBounceScatter;
                incidentLight += distantAmbient * 0.35 * ADV_CLOUD_AMBIENT_STRENGTH;
            }

            if (horizonMatch > 1e-4) {
                float incidentLuminance = cloudLuminance(max(incidentLight, vec3(0.0)));
                float baseLuminance = max(cloudLuminance(max(horizonBase, vec3(0.0))), 1e-4);
                vec3 matchedIncident = max(horizonBase, vec3(0.0)) * (incidentLuminance / baseLuminance);
                float matchStrength = horizonMatch * mix(0.9, 0.30, rainBlend);
                incidentLight = mix(incidentLight, matchedIncident, matchStrength);
            }

            vec3 scatterCoefficients = scatterLobeIndex == 0 ? sigmaScatter0 : sigmaScatter1;
            float extinctionCoefficients = scatterLobeIndex == 0 ? sigmaE0 : sigmaE1;
            vec3 litStep = incidentLight * scatterCoefficients;
            vec3 stepScatter = vec3(transmittance) * (litStep - litStep * stepTransmittance) / extinctionCoefficients;
            scattering += stepScatter;

            if (scatterLobeIndex == 0) { transmittance *= stepTransmittance; }
        }

        if (transmittance <= 1e-3) {
            transmittance = 0.0;
            break;
        }

        previousDensity = density;
        previousLayerHeight01 = sampleContext.layerHeight01;
        hasPreviousDensity = true;
    }

    cloudRadiance.transmittance = transmittance;
    if (weightedWorldPosWeight <= 1e-4) {
        cloudRadiance.radiance = skyBackgroundRadiance * transmittance + scattering;
        float missMix = cloudHorizonMissMix(rayDirection);
        if (missMix > 1e-4) {
            vec3 belowBase = sampleCloudBelowHorizonSkyRadiance(rayDirection, indirectLighting);
            cloudRadiance.radiance = mix(cloudRadiance.radiance, belowBase, missMix);
            cloudRadiance.transmittance = mix(cloudRadiance.transmittance, 1.0, missMix);
        }
        return cloudRadiance;
    }

    vec3 cloudWorldPos = weightedWorldPos / weightedWorldPosWeight;
    float cloudDistance = max(dot(cloudWorldPos - rayOrigin, rayDirection), 0.0);
    CloudAtmosphereSegment airPerspective =
        integrateCloudAtmosphereSegment(rayOrigin, rayDirection, cloudDistance, indirectLighting);
    scattering = scattering * airPerspective.transmittance + airPerspective.scatteredLight * (1.0 - transmittance);

    float fade = cloudHorizonFade(rayDirection, cloudWorldPos, cloudDistance);
    horizonBase = max(skyBackgroundRadiance, horizonBase);
    if (fade > 1e-4) {
        float scatteringLuminance = cloudLuminance(max(scattering, vec3(0.0)));
        float horizonLuminance = max(cloudLuminance(max(horizonBase, vec3(0.0))), 1e-4);
        vec3 horizonTintedScattering = max(horizonBase, vec3(0.0)) * (scatteringLuminance / horizonLuminance);
        scattering = mix(scattering, horizonTintedScattering, fade * mix(0.85, 0.35, rainBlend));
    }
    if (fade > 1e-4) { transmittance = mix(transmittance, 1.0, fade); }
    scattering *= (1.0 - fade);

    cloudRadiance.transmittance = transmittance;
    cloudRadiance.radiance = horizonBase * transmittance + scattering;

    float missMix = cloudHorizonMissMix(rayDirection);
    if (missMix > 1e-4) {
        vec3 belowBase = sampleCloudBelowHorizonSkyRadiance(rayDirection, indirectLighting);
        cloudRadiance.radiance = mix(cloudRadiance.radiance, belowBase, missMix);
        cloudRadiance.transmittance = mix(cloudRadiance.transmittance, 1.0, missMix);
    }

    return cloudRadiance;
}

CloudRadiance integrateCloud(vec3 rayOrigin,
                             vec3 rayDirection,
                             vec3 skyBackgroundRadiance,
                             int viewStepCount,
                             int lightStepCount,
                             int ambientStepCount,
                             bool indirectLighting) {
    return integrateCloudSegment(rayOrigin, rayDirection, skyBackgroundRadiance, viewStepCount, lightStepCount,
                                 ambientStepCount, indirectLighting);
}

#endif
