#ifndef ADV_ENVIRONMENT_CLOUD_ATMOSPHERE_GLSL
#define ADV_ENVIRONMENT_CLOUD_ATMOSPHERE_GLSL

#include "environment/cloud/weather.glsl"

vec3 cloudSkyRadiance(vec3 sampleDir, bool indirectLighting) {
    float progress = cloudRainBlend();
    vec3 clearSky = indirectLighting ? texture(skyIndirectRadianceTexture, sampleDir).rgb :
                                       texture(skyRadianceTexture, sampleDir).rgb;
    vec3 rainyRadiance = getOvercastSkyRadiance(clearSky);
    return mix(clearSky, rainyRadiance, progress);
}

float cloudSunDirectScale() {
    float horizonDip = sqrt(2.0 * max(ADV_CLOUD_TOP_HEIGHT, 0.0) / ADV_ATMOSPHERE_RG);
    return smoothstep(-horizonDip - ADV_SUN_RADIUS_RADIANS, -horizonDip + ADV_SUN_RADIUS_RADIANS,
                      getCelestialSunDirection().y);
}

float cloudMoonDirectScale() {
    return smoothstep(0.03, 0.14, getCelestialMoonDirection().y);
}

float cloudLightScale() {
    return max(cloudSunDirectScale(), cloudMoonDirectScale());
}

vec3 cloudLightDirection() {
    vec3 sunDir = getCelestialSunDirection();
    vec3 moonDir = getCelestialMoonDirection();
    float sunScale = cloudSunDirectScale();
    float moonScale = cloudMoonDirectScale();
    float strongestDirectScale = max(sunScale, moonScale);
    if (strongestDirectScale <= 1e-4) { return sunDir.y >= 0.0 ? sunDir : moonDir; }
    if (sunScale >= moonScale) { return sunDir; }
    return moonDir;
}

vec3 cloudLightRadiance(bool indirectLighting) {
    float sunScale = cloudSunDirectScale();
    float moonScale = cloudMoonDirectScale();
    float rainAttenuation = mix(1.0, 0.35, cloudRainBlend());
    vec2 multipliers = getCelestialRadianceMultipliers(indirectLighting);
    if (sunScale >= moonScale) {
        return ADV_SUN_RADIANCE * sunScale * rainAttenuation * multipliers.x;
    }
    return ADV_MOON_RADIANCE * moonScale * rainAttenuation * multipliers.y;
}

float calculateAtmosphereExponentialDensity(float height, float scaleHeight) {
    return exp(-max(height, 0.0) / max(scaleHeight, 1e-3));
}

float evaluateRayleighPhase(float cosTheta) {
    return 3.0 / (16.0 * PI) * (1.0 + cosTheta * cosTheta);
}

float evaluateMieHenyeyGreensteinPhase(float cosTheta, float anisotropy) {
    cosTheta = clamp(cosTheta, -1.0, 1.0);
    anisotropy = clamp(anisotropy, -0.999, 0.999);
    float anisotropySquared = anisotropy * anisotropy;
    float phaseDenominator = 1.0 + anisotropySquared - 2.0 * anisotropy * cosTheta;
    return (1.0 - anisotropySquared) / (4.0 * PI * pow(max(phaseDenominator, 1e-6), 1.5));
}

CloudAtmosphereSegment
integrateCloudAtmosphereSegment(vec3 rayOrigin, vec3 rayDirection, float maxDistance, bool indirectLighting) {
    CloudAtmosphereSegment atmosphereSegment;
    atmosphereSegment.scatteredLight = vec3(0.0);
    atmosphereSegment.transmittance = vec3(1.0);

    vec3 originPlanet = cloudPositionPS(rayOrigin);
    float topNear, topFar;
    if (!findCloudSphereIntersection(originPlanet, rayDirection, ADV_ATMOSPHERE_RT, topNear, topFar)) {
        return atmosphereSegment;
    }

    float atmosphereEnterDistance = max(topNear, 0.0);
    float atmosphereExitDistance = max(topFar, 0.0);

    float groundNear, groundFar;
    if (findCloudSphereIntersection(originPlanet, rayDirection, ADV_ATMOSPHERE_RG, groundNear, groundFar)) {
        float groundHit = groundNear > 0.0 ? groundNear : groundFar;
        if (groundHit > 0.0) { atmosphereExitDistance = min(atmosphereExitDistance, groundHit); }
    }

    if (maxDistance > 0.0) { atmosphereExitDistance = min(atmosphereExitDistance, maxDistance); }
    if (atmosphereExitDistance <= atmosphereEnterDistance) { return atmosphereSegment; }

    vec3 lightDirection = cloudLightDirection();
    vec3 lightRadiance = cloudLightRadiance(indirectLighting);
    vec3 surfaceSunsetTint = getCelestialSunsetTint(getCelestialSunDirection().y);
    float cosTheta = dot(lightDirection, rayDirection);
    float rayleighPhase = evaluateRayleighPhase(cosTheta);
    float miePhase = evaluateMieHenyeyGreensteinPhase(cosTheta, ADV_ATMOSPHERE_MIE_G);
    int stepCount = 8;
    float stepLength = (atmosphereExitDistance - atmosphereEnterDistance) / max(float(stepCount), 1.0);

    for (int stepIndex = 0; stepIndex < stepCount; ++stepIndex) {
        float sampleDistance = atmosphereEnterDistance + (float(stepIndex) + 0.5) * stepLength;
        vec3 samplePos = originPlanet + rayDirection * sampleDistance;
        float sampleRadius = length(samplePos);
        float sampleHeight = sampleRadius - ADV_ATMOSPHERE_RG;
        vec3 upDirection = samplePos / max(sampleRadius, 1e-4);
        float sunViewCos = dot(upDirection, lightDirection);

        float densityRayleigh = calculateAtmosphereExponentialDensity(sampleHeight, ADV_ATMOSPHERE_HR);
        float densityMie = calculateAtmosphereExponentialDensity(sampleHeight, ADV_ATMOSPHERE_HM);
        vec3 sigmaSR = ADV_ATMOSPHERE_BETA_R * densityRayleigh;
        vec3 sigmaSM = ADV_ATMOSPHERE_BETA_M * densityMie;
        vec3 sigmaT = atmosphereExtinction(sampleHeight, sigmaSR, sigmaSM);
        vec3 sunTransmittance = sampleCloudAtmosphereTransmittance(sampleRadius, sunViewCos) *
                                getCelestialAtmosphereTint(surfaceSunsetTint, sampleHeight);
        vec3 scattering = sigmaSR * rayleighPhase + sigmaSM * miePhase;

        atmosphereSegment.scatteredLight +=
            atmosphereSegment.transmittance * (sunTransmittance * scattering * lightRadiance) * stepLength;
        atmosphereSegment.transmittance *= exp(-sigmaT * stepLength);
    }

    return atmosphereSegment;
}

float evaluateCloudHenyeyGreensteinPhase(float anisotropy, float cosTheta) {
    float numerator = 1.0 - anisotropy * anisotropy;
    float denominator = 1.0 + anisotropy * anisotropy + 2.0 * anisotropy * cosTheta;
    return numerator / (4.0 * PI * denominator * sqrt(max(denominator, 1e-5)));
}

float evaluateDualLobePhase(float forwardAnisotropy, float backwardAnisotropy, float lobeWeight, float cosTheta) {
    return mix(evaluateCloudHenyeyGreensteinPhase(forwardAnisotropy, cosTheta),
               evaluateCloudHenyeyGreensteinPhase(backwardAnisotropy, cosTheta), lobeWeight);
}

float cloudPowderEffect(float depth, float height, float viewToLight) {
    float viewBlend = -abs(viewToLight) * 0.5 + 0.5;
    viewBlend = viewBlend * viewBlend;
    height = height * (1.0 - viewBlend) + viewBlend;
    return depth * height;
}

#endif
