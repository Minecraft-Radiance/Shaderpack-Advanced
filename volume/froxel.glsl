#ifndef ADV_VOLUME_FROXEL_GLSL
#define ADV_VOLUME_FROXEL_GLSL

#include "core/bindings.glsl"
#include "core/checkerboard.glsl"
#include "environment/parameters.glsl"
#include "scene/materials/media.glsl"

#ifndef ADV_VOLUME_HISTORY_READY
#    define ADV_VOLUME_HISTORY_READY false
#endif
#ifndef ADV_VOLUME_LIGHT_SHADING
#    define ADV_VOLUME_LIGHT_SHADING 1
#endif
#ifndef MCVR_USE_DLSSRR
#    define MCVR_USE_DLSSRR 0
#endif

#if MCVR_USE_DLSSRR
#    undef ADV_FROXEL_RESOLUTION_MODE
#    define ADV_FROXEL_RESOLUTION_MODE 1
#elif !defined(ADV_FROXEL_RESOLUTION_MODE)
#    define ADV_FROXEL_RESOLUTION_MODE 0
#endif

const ivec3 ADV_VOLUME_DIRECT_EXTENT = ivec3(256, 128, 64);
const ivec3 ADV_VOLUME_INDIRECT_EXTENT = ivec3(128, 64, 32);
const float ADV_VOLUME_RANGE = 50.0;
const float ADV_VOLUME_SLICE_CURVATURE = 10.0;
const float ADV_VOLUME_PI = 3.14159265358979323846;
const float ADV_VOLUME_HISTORY_MEDIUM_OFFSET = 1.0;
const float ADV_VOLUME_DIRECT_MAX_HISTORY = 16.0;
const float ADV_VOLUME_INDIRECT_MAX_HISTORY = 200.0;
const uint ADV_VOLUME_PATH_FIRST_HIT_WATER_BIT = 1u << 11u;
const uint ADV_VOLUME_PATH_FIRST_HIT_GLASS_BIT = 1u << 12u;

ivec3 volumeCheckerboardDispatchExtent(ivec3 extent) {
    return ivec3((extent.x + 1) / 2, extent.y, extent.z);
}

ivec3 volumeCheckerboardCoordinate(ivec3 dispatchCoordinate, uint phase) {
    uint xParity = (phase ^ ((uint(dispatchCoordinate.y) + uint(dispatchCoordinate.z)) & 1u)) & 1u;
    return ivec3(dispatchCoordinate.x * 2 + int(xParity), dispatchCoordinate.yz);
}

#ifndef ADV_VOLUME_AIR_ANISOTROPY
#    define ADV_VOLUME_AIR_ANISOTROPY 0.75
#endif
#ifndef ADV_VOLUME_WATER_ANISOTROPY
#    define ADV_VOLUME_WATER_ANISOTROPY 0.55
#endif
#ifndef ADV_VOLUME_AIR_SCATTERING_ALBEDO
#    define ADV_VOLUME_AIR_SCATTERING_ALBEDO vec3(0.9)
#endif
#ifndef ADV_VOLUME_WATER_SCATTERING_ALBEDO
#    define ADV_VOLUME_WATER_SCATTERING_ALBEDO vec3(0.12, 0.42, 0.55)
#endif

bool isVolumeFinite(float scalar) {
    return !isnan(scalar) && !isinf(scalar);
}

bool isVolumeFinite(vec3 vector) {
    return !any(isnan(vector)) && !any(isinf(vector));
}

vec3 volumeNormalize(vec3 vector, vec3 fallback) {
    float lengthSquared = dot(vector, vector);
    if (!isVolumeFinite(vector) || !isVolumeFinite(lengthSquared) || lengthSquared <= 1e-12) { return fallback; }
    return vector * inversesqrt(lengthSquared);
}

float volumeDistanceFromW(float w) {
    float coordinate = clamp(w, 0.0, 1.0);
    return ADV_VOLUME_RANGE * (pow(ADV_VOLUME_SLICE_CURVATURE + 1.0, coordinate) - 1.0) / ADV_VOLUME_SLICE_CURVATURE;
}

float volumeWFromDistance(float distance) {
    float normalized = max(distance, 0.0) * (ADV_VOLUME_SLICE_CURVATURE / ADV_VOLUME_RANGE) + 1.0;
    return clamp(log(normalized) / log(ADV_VOLUME_SLICE_CURVATURE + 1.0), 0.0, 1.0);
}

float volumeSliceCenterW(int slice, int depth) {
    return (float(slice) + 0.5) / float(max(depth, 1));
}

float volumeSliceFrontW(int slice, int depth) {
    return float(slice) / float(max(depth, 1));
}

vec2 volumeUvFromFroxel(ivec2 coordinate, ivec2 extent) {
    return (vec2(coordinate) + 0.5) / vec2(max(extent, ivec2(1)));
}

vec3 volumeCameraOrigin() {
    return worldUBO.cameraEffectedViewMatInv[3].xyz;
}

vec3 volumeRayDirection(vec2 uv) {
    vec2 ndc = uv * 2.0 - 1.0;
    vec4 viewPosition = worldUBO.cameraProjMatInv * vec4(ndc, 0.0, 1.0);
    if (!isVolumeFinite(viewPosition.w) || abs(viewPosition.w) <= 1e-8) { return vec3(0.0, 0.0, -1.0); }
    viewPosition /= viewPosition.w;
    return volumeNormalize(vec3(worldUBO.cameraEffectedViewMatInv * vec4(viewPosition.xyz, 0.0)), vec3(0.0, 0.0, -1.0));
}

ivec2 volumeFlatPixel(vec2 uv) {
    ivec2 extent = ivec2(int(ADV_RENDER_WIDTH), int(ADV_RENDER_HEIGHT));
    return clamp(ivec2(uv * vec2(extent)), ivec2(0), extent - ivec2(1));
}

ivec2 volumePackedPixel(vec2 uv) {
    ivec2 flatExtent = ivec2(int(ADV_RENDER_WIDTH), int(ADV_RENDER_HEIGHT));
    CheckerCoordinate checker = flatToChecker(volumeFlatPixel(uv), flatExtent);
    return checker.isValid ? checker.packedPixel : ivec2(-1);
}

float volumePrimaryRayDistance(float viewDepth, vec3 rayDirection) {
    if (!isVolumeFinite(viewDepth) || viewDepth >= 65504.0 * 0.9) { return ADV_ENVIRONMENT_MAX_DISTANCE; }
    float depthPerDistance = -(mat3(worldUBO.cameraEffectedViewMat) * rayDirection).z;
    if (!isVolumeFinite(depthPerDistance) || depthPerDistance <= 1e-6) { return ADV_VOLUME_RANGE; }
    return clamp(viewDepth / depthPerDistance, 0.0, ADV_ENVIRONMENT_MAX_DISTANCE);
}

bool volumeHasTransparentFirstInterface(uint pathFlags) {
    return (pathFlags & (ADV_VOLUME_PATH_FIRST_HIT_WATER_BIT | ADV_VOLUME_PATH_FIRST_HIT_GLASS_BIT)) != 0u;
}

bool volumeAllowsTransparentIndirect(uint pathFlags) {
#if ADV_VOLUME_LIGHT_SHADING != 0
    return volumeHasTransparentFirstInterface(pathFlags);
#else
    return false;
#endif
}

bool isVolumeCameraHistoryValid() {
    if (!bool(ADV_VOLUME_HISTORY_READY)) { return false; }
    if (worldUBO.skyType != lastWorldUBO.skyType || worldUBO.worldBottomY != lastWorldUBO.worldBottomY ||
        worldUBO.worldTopY != lastWorldUBO.worldTopY) {
        return false;
    }
    vec3 cameraDelta = vec3(worldUBO.cameraPos.xyz - lastWorldUBO.cameraPos.xyz);
    if (!isVolumeFinite(cameraDelta) || length(cameraDelta) > 8.0) { return false; }
    vec3 currentForward =
        volumeNormalize(vec3(worldUBO.cameraEffectedViewMatInv * vec4(0.0, 0.0, -1.0, 0.0)), vec3(0.0, 0.0, -1.0));
    vec3 previousForward =
        volumeNormalize(vec3(lastWorldUBO.cameraEffectedViewMatInv * vec4(0.0, 0.0, -1.0, 0.0)), vec3(0.0, 0.0, -1.0));
    return dot(currentForward, previousForward) > 0.5;
}

bool volumeReproject(vec3 currentScenePosition, ivec3 volumeExtent, out vec3 previousUvw) {
    previousUvw = vec3(0.0);
    if (!isVolumeCameraHistoryValid() || !isVolumeFinite(currentScenePosition)) { return false; }

    vec3 absolutePosition = currentScenePosition + vec3(worldUBO.cameraPos.xyz);
    vec3 previousScenePosition = absolutePosition - vec3(lastWorldUBO.cameraPos.xyz);
    vec4 previousView = lastWorldUBO.cameraEffectedViewMat * vec4(previousScenePosition, 1.0);
    vec4 previousClip = lastWorldUBO.cameraProjMat * previousView;
    if (!isVolumeFinite(previousView.xyz) || !isVolumeFinite(previousClip.xyz) || !isVolumeFinite(previousClip.w) ||
        previousClip.w <= 1e-8) {
        return false;
    }

    vec2 previousNdc = previousClip.xy / previousClip.w;
    if (any(greaterThan(abs(previousNdc), vec2(1.01)))) { return false; }
    vec2 previousUv = previousNdc * 0.5 + 0.5;
    vec2 texelInset = 0.5 / vec2(volumeExtent.xy);
    previousUvw.xy = clamp(previousUv, texelInset, vec2(1.0) - texelInset);
    previousUvw.z = volumeWFromDistance(length(previousView.xyz));
    return isVolumeFinite(previousUvw);
}

float volumeEncodeHistory(float historyLength, bool isUnderwater) {
    float encoded = clamp(historyLength, 0.0, ADV_VOLUME_INDIRECT_MAX_HISTORY) + ADV_VOLUME_HISTORY_MEDIUM_OFFSET;
    return isUnderwater ? -encoded : encoded;
}

float volumeDecodeHistory(float encoded) {
    if (!isVolumeFinite(encoded)) { return 0.0; }
    return max(abs(encoded) - ADV_VOLUME_HISTORY_MEDIUM_OFFSET, 0.0);
}

bool isVolumeHistoryMediumCompatible(float encoded, bool isUnderwater) {
    if (!isVolumeFinite(encoded) || abs(encoded) < ADV_VOLUME_HISTORY_MEDIUM_OFFSET) { return false; }
    return isUnderwater ? encoded < 0.0 : encoded > 0.0;
}

float volumeHistorySampleWeight(float encodedHistory) {
    float historyLength = volumeDecodeHistory(encodedHistory);
    return clamp((historyLength - 1.0) / 3.0, 0.0, 1.0) + 0.001;
}

bool canCarryVolumeHistory(vec4 history, bool isHistoryValid, bool isUnderwater) {
    return isHistoryValid && isVolumeHistoryMediumCompatible(history.w, isUnderwater) &&
           volumeDecodeHistory(history.w) > 0.0 && isVolumeFinite(history.rgb);
}

float volumeDensity(vec3 scenePosition, bool isUnderwater) {
    if (isUnderwater || worldUBO.skyType != 1u) { return 1.0; }
    float absoluteHeight = scenePosition.y + float(worldUBO.cameraPos.y);
    float heightDensity = exp(-max(absoluteHeight - 64.0, 0.0) * 0.012);
    float worldHeight = max(float(worldUBO.worldTopY - worldUBO.worldBottomY), 1.0);
    float nearGround = clamp((float(worldUBO.worldTopY) - absoluteHeight) / worldHeight, 0.0, 1.0);
    return clamp(max(heightDensity, nearGround * 0.25), 0.05, 1.0);
}

vec3 volumeAirMieExtinction(float rain) {
    float fogRange = max(worldUBO.fogEnd - worldUBO.fogStart, 1.0);
    float minecraftFog = max(2.0 / fogRange, 0.0) * 0.02;
    vec3 mie = ADV_ATMOSPHERE_BETA_M * mix(18.0, 54.0, rain);
    return mie * 1.15 + vec3(minecraftFog + 0.004 * rain);
}

vec3 volumeExtinction(bool isUnderwater) {
    if (isUnderwater) { return max(mediumExtinction(ADV_MEDIUM_WATER), vec3(1e-5)); }
    float rain = worldUBO.skyType == 1u ? clamp(skyUBO.rainGradient, 0.0, 1.0) : 0.0;
    return max(ADV_ATMOSPHERE_BETA_R * 18.0 + volumeAirMieExtinction(rain), vec3(1e-6));
}

vec3 volumeScattering(bool isUnderwater) {
    vec3 extinction = volumeExtinction(isUnderwater);
    return extinction * (isUnderwater ? ADV_VOLUME_WATER_SCATTERING_ALBEDO : ADV_VOLUME_AIR_SCATTERING_ALBEDO);
}

float volumeHenyeyGreenstein(float anisotropy, float cosine) {
    float clampedAnisotropy = clamp(anisotropy, -0.95, 0.95);
    float denominator =
        max(1.0 + clampedAnisotropy * clampedAnisotropy - 2.0 * clampedAnisotropy * clamp(cosine, -1.0, 1.0), 1e-5);
    return (1.0 - clampedAnisotropy * clampedAnisotropy) / (denominator * sqrt(denominator));
}

vec4 volumeTemporalBlend(
    vec3 currentInscatter, vec4 previous, bool isPreviousValid, bool isUnderwater, float maximumHistory) {
    vec3 sanitizedInscatter = isVolumeFinite(currentInscatter) ? max(currentInscatter, vec3(0.0)) : vec3(0.0);
    float previousLength = isPreviousValid && isVolumeHistoryMediumCompatible(previous.w, isUnderwater) ?
                               min(volumeDecodeHistory(previous.w), maximumHistory) :
                               0.0;
    bool shouldUsePrevious = previousLength > 0.0 && isVolumeFinite(previous.rgb);
    float historyLength = min((shouldUsePrevious ? previousLength : 0.0) + 1.0, maximumHistory);
    vec3 blendedInscatter = shouldUsePrevious ?
                                mix(max(previous.rgb, vec3(0.0)), sanitizedInscatter, 1.0 / max(historyLength, 1.0)) :
                                sanitizedInscatter;
    if (!isVolumeFinite(blendedInscatter)) { blendedInscatter = sanitizedInscatter; }
    return vec4(clamp(blendedInscatter, vec3(0.0), vec3(65504.0)), volumeEncodeHistory(historyLength, isUnderwater));
}

vec4 volumeDecayOccludedHistory(vec4 previous, bool isPreviousValid, bool isUnderwater) {
    if (!isPreviousValid || !isVolumeHistoryMediumCompatible(previous.w, isUnderwater) ||
        !isVolumeFinite(previous.rgb)) {
        return vec4(0.0, 0.0, 0.0, volumeEncodeHistory(0.0, isUnderwater));
    }
    float historyLength = max(volumeDecodeHistory(previous.w) - 1.0, 0.0);
    vec3 radiance = max(previous.rgb, vec3(0.0));
    if (historyLength <= 0.0) { radiance *= 0.8; }
    return vec4(clamp(radiance, vec3(0.0), vec3(65504.0)), volumeEncodeHistory(historyLength, isUnderwater));
}

#endif
