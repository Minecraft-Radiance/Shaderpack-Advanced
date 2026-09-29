#ifndef ADV_ENVIRONMENT_CELESTIAL_GLSL
#define ADV_ENVIRONMENT_CELESTIAL_GLSL

#include "environment/parameters.glsl"
#include "environment/atmosphere/sampling.glsl"

#include "common/shared.hpp"
#include "util/random.glsl"

const float ADV_SUN_RADIUS_RADIANS = 0.004675 * 4.0;
const float ADV_SUN_DISK_TAN_HALF_ANGLE = tan(ADV_SUN_RADIUS_RADIANS);

vec3 normalizeCelestialDirection(vec3 direction, vec3 fallback) {
    float lengthSquared = dot(direction, direction);
    if (lengthSquared <= 1e-8 || any(isnan(direction)) || any(isinf(direction))) { return fallback; }
    return direction * inversesqrt(lengthSquared);
}

vec3 applyCelestialSouthOffset(vec3 direction) {
    const float southOffsetSinAngle = 0.17364817766693033;
    const float southOffsetCosAngle = 0.984807753012208;
    vec3 rotatedDirection = vec3(direction.x, direction.y * southOffsetCosAngle - direction.z * southOffsetSinAngle,
                                 direction.y * southOffsetSinAngle + direction.z * southOffsetCosAngle);
    return normalizeCelestialDirection(rotatedDirection, vec3(0.0, 1.0, 0.0));
}

vec3 getCelestialSunDirection() {
    return applyCelestialSouthOffset(normalizeCelestialDirection(skyUBO.sunDirection, vec3(0.0, 1.0, 0.0)));
}

vec3 getCelestialMoonDirection() {
    return -getCelestialSunDirection();
}

float getCelestialSunlightScale(float sunElevation) {
    float elevation = clamp(sunElevation, 0.0, 1.0);
    float horizontalIrradiance = elevation * elevation;
    const float morningIrradiance = 0.20;
    const float middayHeadroom = 0.05;
    if (horizontalIrradiance <= morningIrradiance) { return elevation; }
    float excessIrradiance = horizontalIrradiance - morningIrradiance;
    float compressedIrradiance = morningIrradiance +
                                excessIrradiance / (1.0 + excessIrradiance / middayHeadroom);
    return compressedIrradiance / elevation;
}

vec3 getCelestialSunsetTint(float sunElevation) {
    if (sunElevation <= 0.0 || sunElevation >= 0.65) { return vec3(1.0); }
    float earlyWarmth = 1.0 - smoothstep(0.35, 0.65, sunElevation);
    float colorElevation = sunElevation / (1.0 + 5.0 * sunElevation * earlyWarmth);
    float radius = ADV_ATMOSPHERE_RG + 100.0;
    vec3 originalTransmittance = sampleAtmosphereLut(radius, sunElevation);
    vec3 warmTransmittance = sampleAtmosphereLut(radius, colorElevation);
    const vec3 luminanceWeights = vec3(0.2126, 0.7152, 0.0722);
    float luminanceScale = dot(originalTransmittance, luminanceWeights) /
                           max(dot(warmTransmittance, luminanceWeights), 1e-5);
    return warmTransmittance * luminanceScale / max(originalTransmittance, vec3(1e-5));
}

vec3 getCelestialAtmosphereTint(vec3 surfaceTint, float height) {
    return mix(vec3(1.0), surfaceTint, exp(-max(height, 0.0) / 8000.0));
}

vec3 getCelestialSunlightColor(float sunElevation) {
    float radius = ADV_ATMOSPHERE_RG + max(float(worldUBO.cameraPos.y), 0.0) + 70.0;
    vec3 transmittance = sampleAtmosphereLut(radius, max(sunElevation, 0.0));
    vec3 middayTransmittance = sampleAtmosphereLut(radius, 0.984807753);
    vec3 sunlightColor = transmittance * getCelestialAtmosphereTint(getCelestialSunsetTint(sunElevation),
                                                                  radius - ADV_ATMOSPHERE_RG) /
                         max(middayTransmittance, vec3(1e-4));
    return sunlightColor / max(dot(sunlightColor, vec3(0.2126, 0.7152, 0.0722)), 1e-4);
}

void getCelestialPrimaryDirectLight(out vec3 lightDirection, out vec3 lightRadiance, out float lightScale) {
    vec3 sunDirection = getCelestialSunDirection();
    float sunScale = max(sunDirection.y, 0.0);
    vec3 moonDirection = -sunDirection;
    float moonScale = max(moonDirection.y, 0.0);

    if (sunScale >= moonScale) {
        lightDirection = sunDirection;
        lightScale = getCelestialSunlightScale(sunScale);
        lightRadiance = ADV_SUN_RADIANCE * getCelestialSunlightColor(sunScale) * lightScale;
    } else {
        lightDirection = moonDirection;
        lightRadiance = ADV_MOON_RADIANCE * moonScale;
        lightScale = moonScale;
    }
    float weatherTransmission = mix(1.0, 0.05, smoothstep(0.0, 1.0, skyUBO.rainGradient));
    lightRadiance *= weatherTransmission;
    lightScale *= weatherTransmission;
}

vec2 getCelestialRadianceMultipliers(bool indirectLighting) {
    return indirectLighting ?
               max(vec2(float(ADV_SUN_INDIRECT_LIGHT_MULTIPLIER), float(ADV_MOON_INDIRECT_LIGHT_MULTIPLIER)),
                   vec2(0.0)) :
               vec2(1.0);
}

vec3 getOvercastSkyRadiance(vec3 clearRadiance) {
    vec3 clearSky = max(clearRadiance, vec3(0.0));
    float luminance = dot(clearSky, vec3(0.2126, 0.7152, 0.0722));
    return mix(clearSky, vec3(luminance), 0.85) * 0.35;
}

void getCelestialIndirectLight(out vec3 lightDirection, out vec3 lightRadiance, out float lightScale) {
    getCelestialPrimaryDirectLight(lightDirection, lightRadiance, lightScale);
    float multiplier = getCelestialSunDirection().y >= 0.0 ? float(ADV_SUN_INDIRECT_LIGHT_MULTIPLIER) :
                                                             float(ADV_MOON_INDIRECT_LIGHT_MULTIPLIER);
    lightRadiance *= max(multiplier, 0.0);
}

void buildCelestialSamplingBasis(vec3 normal, out vec3 tangent, out vec3 bitangent) {
    float signZ = normal.z >= 0.0 ? 1.0 : -1.0;
    float basisScale = -1.0 / (signZ + normal.z);
    float basisCrossTerm = normal.x * normal.y * basisScale;
    tangent = vec3(1.0 + signZ * normal.x * normal.x * basisScale, signZ * basisCrossTerm, -signZ * normal.x);
    bitangent = vec3(basisCrossTerm, signZ + normal.y * normal.y * basisScale, -normal.y);
    tangent = normalizeCelestialDirection(tangent, vec3(1.0, 0.0, 0.0));
    bitangent = normalizeCelestialDirection(bitangent, vec3(0.0, 1.0, 0.0));
}

vec3 sampleCelestialDirectionDisk(vec2 randomSample, vec3 centerDir, float tanHalfAngle) {
    centerDir = normalizeCelestialDirection(centerDir, vec3(0.0, 1.0, 0.0));
    vec3 tangent;
    vec3 bitangent;
    buildCelestialSamplingBasis(centerDir, tangent, bitangent);

    randomSample = clamp(randomSample, vec2(0.0), vec2(0.99999994));
    float radius = sqrt(randomSample.x) * tanHalfAngle;
    float angle = TWO_PI * randomSample.y;
    vec2 offset = vec2(cos(angle), sin(angle)) * radius;
    return normalizeCelestialDirection(centerDir + tangent * offset.x + bitangent * offset.y, centerDir);
}

vec3 sampleSunDisk(vec2 randomSample, vec3 sunDir) {
    return sampleCelestialDirectionDisk(randomSample, sunDir, ADV_SUN_DISK_TAN_HALF_ANGLE);
}

float celestialRadicalInverse(uint bits) {
    return float(bitfieldReverse(bits)) * 2.3283064365386963e-10;
}

vec2 celestialHammersley(uint sampleIndex, uint sampleCount, vec2 rotation) {
    vec2 sequence = vec2((float(sampleIndex) + 0.5) / float(sampleCount), celestialRadicalInverse(sampleIndex));
    return fract(sequence + rotation);
}

#endif
