#ifndef ADV_ENVIRONMENT_SKY_GLSL
#define ADV_ENVIRONMENT_SKY_GLSL

#include "environment/parameters.glsl"

#include "environment/celestial.glsl"
#include "environment/indirect_sky.glsl"

bool findCelestialSphereIntersection(vec3 rayOrigin, vec3 rayDir, float radius, out float tNear, out float tFar) {
    float rayProjection = dot(rayOrigin, rayDir);
    float sphereOffset = dot(rayOrigin, rayOrigin) - radius * radius;
    float discriminant = rayProjection * rayProjection - sphereOffset;
    if (discriminant < 0.0) { return false; }
    discriminant = sqrt(discriminant);
    tNear = -rayProjection - discriminant;
    tFar = -rayProjection + discriminant;
    return true;
}

void buildCelestialBillboardBasis(vec3 normal, out vec3 tangent, out vec3 bitangent) {
    float normalSign = normal.z >= 0.0 ? 1.0 : -1.0;
    float basisScale = -1.0 / (normalSign + normal.z);
    float basisCrossTerm = normal.x * normal.y * basisScale;
    tangent =
        vec3(1.0 + normalSign * normal.x * normal.x * basisScale, normalSign * basisCrossTerm, -normalSign * normal.x);
    bitangent = vec3(basisCrossTerm, normalSign + normal.y * normal.y * basisScale, -normal.y);
    tangent = normalize(tangent);
    bitangent = normalize(bitangent);
}

vec4 sampleTextureBaseLod(sampler2D textureSampler, vec2 textureUv) {
    ivec2 texSize = textureSize(textureSampler, 0);
    if (texSize.x <= 0 || texSize.y <= 0) { return vec4(0.0); }
    vec2 halfTexel = 0.5 / vec2(texSize);
    vec2 clampedUv = clamp(textureUv, halfTexel, vec2(1.0) - halfTexel);
    return sampleTexture(textureSampler, clampedUv, 0.0, false);
}

vec4 sampleAtlasTileBaseLod(sampler2D textureSampler, vec2 tileUv, uvec2 atlasTileCount, uvec2 tile) {
    ivec2 texSize = textureSize(textureSampler, 0);
    if (texSize.x <= 0 || texSize.y <= 0) { return vec4(0.0); }

    vec2 invTileCount = 1.0 / vec2(atlasTileCount);
    vec2 tileMin = vec2(tile) * invTileCount;
    vec2 tileMax = tileMin + invTileCount;
    vec2 halfTexel = 0.5 / vec2(texSize);
    vec2 minUv = tileMin + halfTexel;
    vec2 maxUv = tileMax - halfTexel;
    vec2 atlasUv = mix(minUv, maxUv, clamp(tileUv, 0.0, 1.0));
    return sampleTexture(textureSampler, atlasUv, 0.0, false);
}

float calculateCelestialSquareAlignment(float tanHalf) {
    return inversesqrt(1.0 + 2.0 * tanHalf * tanHalf);
}

vec4 evaluateSunBillboard(vec3 rayDir) {
    vec3 sunDir = getCelestialSunDirection();
    float viewAlignment = dot(rayDir, sunDir);
    if (viewAlignment <= 0.0) { return vec4(0.0); }

    float tanHalf = tan(0.03);
    float minSquareAlignment = calculateCelestialSquareAlignment(tanHalf);
    if (viewAlignment < minSquareAlignment) { return vec4(0.0); }

    vec3 right;
    vec3 up;
    buildCelestialBillboardBasis(sunDir, right, up);
    vec2 basisProjection = vec2(dot(rayDir, right), dot(rayDir, up));
    vec2 diskCoord = basisProjection / max(viewAlignment, 1e-4);
    vec2 absDiskCoord = abs(diskCoord);
    if (absDiskCoord.x > tanHalf || absDiskCoord.y > tanHalf) { return vec4(0.0); }
    vec2 textureUv = diskCoord / tanHalf * 0.5 + 0.5;
    return sampleTextureBaseLod(textures[nonuniformEXT(skyUBO.sunTextureID)], textureUv);
}

vec4 evaluateMoonBillboard(vec3 rayDir) {
    vec3 moonDir = getCelestialMoonDirection();
    float viewAlignment = dot(rayDir, moonDir);
    if (viewAlignment <= 0.0) { return vec4(0.0); }

    float tanHalf = tan(0.05);
    float minSquareAlignment = calculateCelestialSquareAlignment(tanHalf);
    if (viewAlignment < minSquareAlignment) { return vec4(0.0); }

    vec3 right;
    vec3 up;
    buildCelestialBillboardBasis(moonDir, right, up);
    vec2 basisProjection = vec2(dot(rayDir, right), dot(rayDir, up));
    vec2 diskCoord = basisProjection / max(viewAlignment, 1e-4);
    vec2 absDiskCoord = abs(diskCoord);
    if (absDiskCoord.x > tanHalf || absDiskCoord.y > tanHalf) { return vec4(0.0); }
    vec2 textureUv = diskCoord / tanHalf * 0.5 + 0.5;
    uvec2 atlasTileCount = uvec2(4u, 2u);
    uvec2 tile = uvec2(skyUBO.moonPhase % atlasTileCount.x, (skyUBO.moonPhase / atlasTileCount.x) % atlasTileCount.y);
    return sampleAtlasTileBaseLod(textures[nonuniformEXT(skyUBO.moonTextureID)], textureUv, atlasTileCount, tile);
}

vec3 calculateCelestialBillboardRadiance(vec3 rayDir, vec3 transmittance, bool indirectLighting) {
    vec2 radianceMultipliers = getCelestialRadianceMultipliers(indirectLighting);
    if (worldUBO.skyType != 1) { return vec3(0.0); }

    float rainVisibility = 1.0 - skyUBO.rainGradient;
    vec3 radiance = vec3(0.0);

    vec4 sunSample = evaluateSunBillboard(rayDir);
    if (sunSample.a > 1e-4) {
        vec3 sunsetTint = getCelestialAtmosphereTint(getCelestialSunsetTint(getCelestialSunDirection().y),
                                                   max(float(worldUBO.cameraPos.y), 0.0) + 70.0);
        radiance += sunSample.rgb * ADV_SUN_RADIANCE * sunsetTint *
                    radianceMultipliers.x * transmittance * sunSample.a * rainVisibility;
    }

    vec4 moonSample = evaluateMoonBillboard(rayDir);
    if (moonSample.a > 1e-4) {
        radiance += moonSample.rgb * ADV_MOON_RADIANCE * radianceMultipliers.y * max(transmittance, vec3(0.03)) *
                    rainVisibility;
    }

    return radiance;
}

bool isSkyVisible() {
    if (skyUBO.cameraSubmersionType == 0 || skyUBO.cameraSubmersionType == 2) { return false; }
    if (skyUBO.hasBlindnessOrDarkness > 0) { return false; }
    return worldUBO.skyType == 1;
}

vec3 sanitizeSkyRadiance(vec3 radiance) {
    if (any(isnan(radiance)) || any(isinf(radiance))) { return vec3(0.0); }
    return max(radiance, vec3(0.0));
}

vec3 normalizeSkyDirection(vec3 direction) {
    float lengthSquared = dot(direction, direction);
    if (lengthSquared <= 1e-8 || isnan(lengthSquared) || isinf(lengthSquared) || any(isnan(direction)) ||
        any(isinf(direction))) {
        return vec3(0.0, 1.0, 0.0);
    }
    return direction * inversesqrt(lengthSquared);
}

bool isCelestialBillboardVisible(vec3 rayDirection) {
    if (!isSkyVisible()) { return false; }

    vec3 rayDir = normalizeSkyDirection(rayDirection);
    float cameraHeight = worldUBO.cameraViewMatInv[3].y;
    vec3 planetPosition = vec3(0.0, ADV_ATMOSPHERE_RG + cameraHeight + 70.0, 0.0);
    float groundNear;
    float groundFar;
    bool isBlockedByGround =
        findCelestialSphereIntersection(planetPosition, rayDir, ADV_ATMOSPHERE_RG, groundNear, groundFar) &&
        groundFar > 1e-3;
    if (isBlockedByGround) { return false; }

    return evaluateSunBillboard(rayDir).a > 1e-4 || evaluateMoonBillboard(rayDir).a > 1e-4;
}

vec3 calculateSkyRadiance(vec3 rayDirection, bool indirectLighting) {
    if (worldUBO.skyType == 2u && skyUBO.cameraSubmersionType != 0u &&
        skyUBO.cameraSubmersionType != 2u && skyUBO.hasBlindnessOrDarkness == 0u) {
        return srgbToLinear(max(worldUBO.fogColor.rgb, vec3(0.0))) * (indirectLighting ? 3.0 : 1.0);
    }
    if (!isSkyVisible()) { return vec3(0.0); }

    vec3 rayDir = normalizeSkyDirection(rayDirection);
    float rainGradient = skyUBO.rainGradient;
    vec3 clearRadiance =
        indirectLighting ? texture(skyIndirectRadianceTexture, rayDir).rgb : texture(skyRadianceTexture, rayDir).rgb;
    vec3 rainyRadiance = getOvercastSkyRadiance(clearRadiance);
    vec3 radiance = mix(clearRadiance, rainyRadiance, rainGradient);

    float cameraHeight = worldUBO.cameraViewMatInv[3].y;
    vec3 planetPosition = vec3(0.0, ADV_ATMOSPHERE_RG + cameraHeight + 70.0, 0.0);
    float planetRadius = clamp(length(planetPosition), ADV_ATMOSPHERE_RG, ADV_ATMOSPHERE_RT);
    vec3 planetUp = planetPosition / max(planetRadius, 1e-6);
    float rayUpDot = clamp(dot(planetUp, rayDir), -1.0, 1.0);
    vec3 transmittance = sampleAtmosphereLut(planetRadius, rayUpDot);

    float groundNear;
    float groundFar;
    bool isBlockedByGround =
        findCelestialSphereIntersection(planetPosition, rayDir, ADV_ATMOSPHERE_RG, groundNear, groundFar) &&
        groundFar > 1e-3;
    if (!isBlockedByGround) {
        radiance += calculateCelestialBillboardRadiance(rayDir, transmittance, indirectLighting);
    }

    return sanitizeSkyRadiance(radiance);
}

vec3 calculateSkyRadiance(vec3 rayDirection) {
    return calculateSkyRadiance(rayDirection, false);
}

vec3 calculateIndirectSkyRadiance(vec3 rayDirection) {
    return calculateSkyRadiance(rayDirection, true);
}

#endif
