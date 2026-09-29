#version 460
#extension GL_GOOGLE_include_directive : require

#include "common/shared.hpp"
#include "core/bindings.glsl"
#include "environment/parameters.glsl"

layout(set = 2, binding = 0) uniform WorldUniform {
    WorldUBO worldUBO;
};

layout(set = 2, binding = 2) uniform SkyUniform {
    SkyUBO skyUBO;
};

#include "environment/celestial.glsl"


layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 outColor;

#ifndef ADV_INDIRECT_SKY_CUBE
#    define ADV_INDIRECT_SKY_CUBE 0
#endif

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

float evaluateRayleighPhase(float cosTheta) {
    return 3.0 / (16.0 * PI) * (1.0 + cosTheta * cosTheta);
}

float evaluateMiePhase(float cosTheta) {
    float mieG = clamp(ADV_ATMOSPHERE_MIE_G, -0.999, 0.999);
    float mieG2 = mieG * mieG;
    float clampedCosTheta = clamp(cosTheta, -1.0, 1.0);
    float mieDenominatorBase = max(1.0 + mieG2 - 2.0 * mieG * clampedCosTheta, 1e-6);
    float mieDenominator = mieDenominatorBase * sqrt(mieDenominatorBase);
    return (1.0 - mieG2) / (4.0 * PI * mieDenominator);
}

vec3 resolveTwilightSky(vec3 solarRadiance, vec3 rayOrigin, vec3 rayDir, vec3 sunDir) {
    float twilightBlend = (1.0 - smoothstep(0.0, 0.342, sunDir.y)) *
                          smoothstep(-0.208, -0.070, sunDir.y);
    if (twilightBlend <= 0.0) { return solarRadiance; }

    float referenceRadius = clamp(length(rayOrigin), ADV_ATMOSPHERE_RG, ADV_ATMOSPHERE_RT);
    float referenceSunElevation = sunDir.y >= 0.0 ? sunDir.y : -0.04 * (1.0 - exp(sunDir.y / 0.04));
    vec3 sunsetTransmittance = sampleAtmosphereLut(referenceRadius, referenceSunElevation) *
                               getCelestialAtmosphereTint(getCelestialSunsetTint(sunDir.y),
                                                         referenceRadius - ADV_ATMOSPHERE_RG);
    vec3 daylightTransmittance = sampleAtmosphereLut(referenceRadius, 0.984807753);
    vec3 twilightColor = pow(max(sunsetTransmittance / max(daylightTransmittance, vec3(1e-4)),
                                 vec3(1e-6)), vec3(0.7)) * ADV_SUN_RADIANCE;
    const vec3 luminanceWeights = vec3(0.2126, 0.7152, 0.0722);
    twilightColor /= max(dot(twilightColor, luminanceWeights), 1e-4);

    float sunward = smoothstep(-0.5, 0.8, dot(rayDir.xz, sunDir.xz));
    float lowSky = 1.0 - smoothstep(0.10, 0.80, max(rayDir.y, 0.0));
    float colorBlend = twilightBlend * (0.12 + 0.68 * lowSky) * mix(0.25, 1.0, sunward);
    vec3 twilightRadiance = twilightColor * dot(solarRadiance, luminanceWeights);
    return mix(solarRadiance, twilightRadiance, colorBlend);
}

vec3 integrateAtmosphereSingleScattering(vec3 rayOrigin, vec3 rayDir, vec3 sunDir) {
    float tAtm0, tAtm1;
    if (!findAtmosphereSphereIntersection(rayOrigin, rayDir, ADV_ATMOSPHERE_RT, tAtm0, tAtm1)) return vec3(0.0);
    tAtm0 = max(tAtm0, 0.0);

    float tG0, tG1;
    if (findAtmosphereSphereIntersection(rayOrigin, rayDir, ADV_ATMOSPHERE_RG, tG0, tG1)) {
        float tHitG = tG0 > 0.0 ? tG0 : tG1;
        if (tHitG > 0.0) tAtm1 = min(tAtm1, tHitG);
    }

    const int stepCount = 32;
    float stepLength = (tAtm1 - tAtm0) / float(stepCount);

    vec3 solarRadiance = vec3(0.0);
    vec3 lunarRadiance = vec3(0.0);
    vec3 viewTransmittance = vec3(1.0);

    float sunCosTheta = dot(sunDir, rayDir);
    float moonCosTheta = -sunCosTheta;
    float sunRayleighPhase = evaluateRayleighPhase(sunCosTheta);
    float sunMiePhase = evaluateMiePhase(sunCosTheta);
    float moonMiePhase = evaluateMiePhase(moonCosTheta);
    vec2 radianceMultipliers = getCelestialRadianceMultipliers(ADV_INDIRECT_SKY_CUBE != 0);
    vec3 surfaceSunsetTint = getCelestialSunsetTint(sunDir.y);
    vec3 upperAtmosphereOpticalDepth = ADV_ATMOSPHERE_BETA_R * ADV_ATMOSPHERE_HR *
                                      (exp(-10000.0 / ADV_ATMOSPHERE_HR) - exp(-40000.0 / ADV_ATMOSPHERE_HR));
    vec3 upperAtmosphereRadiance = ADV_SUN_RADIANCE * getCelestialAtmosphereTint(surfaceSunsetTint, 30000.0) *
                                   radianceMultipliers.x *
                                   sampleAtmosphereLut(ADV_ATMOSPHERE_RG + 30000.0, sunDir.y) *
                                   (vec3(1.0) - exp(-upperAtmosphereOpticalDepth)) / (4.0 * PI);

    for (int stepIndex = 0; stepIndex < stepCount; stepIndex++) {
        float sampleDistance = tAtm0 + (float(stepIndex) + 0.5) * stepLength;
        vec3 samplePos = rayOrigin + rayDir * sampleDistance;

        float radius = length(samplePos);
        float height = radius - ADV_ATMOSPHERE_RG;

        float rayleighDensity = calculateExponentialDensity(height, ADV_ATMOSPHERE_HR);
        float mieDensity = calculateExponentialDensity(height, ADV_ATMOSPHERE_HM);

        vec3 sigmaSR = ADV_ATMOSPHERE_BETA_R * rayleighDensity;
        vec3 sigmaSM = ADV_ATMOSPHERE_BETA_M * mieDensity;
        vec3 sigmaT = atmosphereExtinction(height, sigmaSR, sigmaSM);

        vec3 up = samplePos / radius;
        float sunMuS = dot(up, sunDir);
        float moonMuS = -sunMuS;
        vec3 sunTransmittance = sampleAtmosphereLut(radius, sunMuS);
        vec3 moonTransmittance = sampleAtmosphereLut(radius, moonMuS);

        vec3 sunScattering = sigmaSR * sunRayleighPhase + sigmaSM * sunMiePhase;
        vec3 moonScattering = sigmaSR * sunRayleighPhase + sigmaSM * moonMiePhase;
        vec3 solarIlluminance = ADV_SUN_RADIANCE * getCelestialAtmosphereTint(surfaceSunsetTint, height);
        solarRadiance += viewTransmittance *
                         (sunTransmittance * sunScattering * solarIlluminance * radianceMultipliers.x +
                          (sigmaSR + sigmaSM) * upperAtmosphereRadiance) * stepLength;
        lunarRadiance += viewTransmittance * moonTransmittance * moonScattering * ADV_MOON_RADIANCE *
                         radianceMultipliers.y * stepLength;
        viewTransmittance *= exp(-sigmaT * stepLength);
    }

    return resolveTwilightSky(solarRadiance, rayOrigin, rayDir, sunDir) + lunarRadiance;
}

bool shouldRenderSkyCube() {
    if (skyUBO.cameraSubmersionType == 0 || skyUBO.cameraSubmersionType == 2) { return false; }
    if (skyUBO.hasBlindnessOrDarkness > 0) { return false; }
    return worldUBO.skyType == 1;
}

void main() {
    vec2 cubeUv = texCoord * 2.0 - 1.0;
    vec3 rayDir = normalize(vec3(-cubeUv.x, -cubeUv.y, -1));
    if (FACE == 0) {
        rayDir = normalize(vec3(1, -cubeUv.y, -cubeUv.x));
    } else if (FACE == 1) {
        rayDir = normalize(vec3(-1, -cubeUv.y, cubeUv.x));
    } else if (FACE == 2) {
        rayDir = normalize(vec3(cubeUv.x, 1, cubeUv.y));
    } else if (FACE == 3) {
        rayDir = normalize(vec3(cubeUv.x, -1, -cubeUv.y));
    } else if (FACE == 4) {
        rayDir = normalize(vec3(cubeUv.x, -cubeUv.y, 1));
    }
    if (!shouldRenderSkyCube()) {
        outColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    float blend = smoothstep(-0.05, 0.02, rayDir.y);
    rayDir.y = max(rayDir.y, ADV_ATMOSPHERE_MIN_VIEW_COS);
    rayDir = normalize(mix(vec3(rayDir.x, ADV_ATMOSPHERE_MIN_VIEW_COS, rayDir.z), rayDir, blend));
    float cameraHeight = worldUBO.cameraViewMatInv[3].y;
    vec3 rayOrigin = vec3(0.0, ADV_ATMOSPHERE_RG + cameraHeight + 70.0, 0.0);

    vec3 sunDir = getCelestialSunDirection();
    vec3 scatteredRadiance = integrateAtmosphereSingleScattering(rayOrigin, rayDir, sunDir);
    outColor = vec4(scatteredRadiance, 1.0);
}
