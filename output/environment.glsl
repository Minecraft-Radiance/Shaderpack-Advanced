#ifndef ADV_OUTPUT_ENVIRONMENT_GLSL
#define ADV_OUTPUT_ENVIRONMENT_GLSL

#include "output/resources.glsl"

vec3 sampleResolvedSky(ResolvePath primary, out float cloudTransmittance) {
    vec3 skyRadiance = calculateSkyRadiance(primary.rayDirection);
    cloudTransmittance = 1.0;
    if (ADV_CLOUD_MODE != 2u) { return skyRadiance; }

    vec3 cloudOrigin = primary.position - primary.rayDirection * ADV_ENVIRONMENT_MAX_DISTANCE;
    CloudRadiance cloudRadiance = shadeCloud(cloudOrigin, primary.rayDirection, skyRadiance, ADV_CLOUD_VIEW_STEPS,
                                             ADV_CLOUD_LIGHT_STEPS, ADV_CLOUD_AMBIENT_STEPS, false);
    cloudTransmittance = clamp(cloudRadiance.transmittance, 0.0, 1.0);
    return cloudRadiance.radiance;
}

float16_t addPositiveHalf(float16_t current, float16_t delta) {
    float16_t maximum = float16_t(ADV_SIGNAL_FP16_MAX);
    return current + min(max(delta, float16_t(0.0)), maximum - current);
}

float16_t addSignedHalf(float16_t current, float16_t delta) {
    float16_t maximum = float16_t(ADV_SIGNAL_FP16_MAX);
    if (delta > float16_t(0.0) && current >= float16_t(0.0)) { return current + min(delta, maximum - current); }
    if (delta < float16_t(0.0) && current <= float16_t(0.0)) { return current - min(-delta, maximum + current); }
    return current + delta;
}

void accumulateRadiance(inout f16vec3 sum, vec3 contribution) {
    f16vec3 delta = f16vec3(contribution);
    sum.x = addPositiveHalf(sum.x, delta.x);
    sum.y = addPositiveHalf(sum.y, delta.y);
    sum.z = addPositiveHalf(sum.z, delta.z);
}

void accumulateDirectionMoment(inout f16vec4 moment, vec3 direction, vec3 contribution) {
    float weight = min(signalLuminance(contribution), ADV_SIGNAL_FP16_MAX);
    if (weight <= 1e-8) { return; }
    vec3 normalizedDirection = signalNormalize(direction, vec3(0.0));
    if (dot(normalizedDirection, normalizedDirection) <= 1e-8) { return; }
    f16vec3 delta = f16vec3(normalizedDirection) * float16_t(weight);
    moment.x = addSignedHalf(moment.x, delta.x);
    moment.y = addSignedHalf(moment.y, delta.y);
    moment.z = addSignedHalf(moment.z, delta.z);
    moment.w = addPositiveHalf(moment.w, float16_t(weight));
}

uint surfaceSegmentation(ResolvePath primary) {
    uint flags = pathFlags(primary.key);
    if ((flags & ADV_PATH_FLAG_HAND) != 0u) { return ADV_SIGNAL_SEGMENTATION_SKIP; }
    if (isSkyPath(primary.key) || (flags & ADV_PATH_FLAG_CLOUD) != 0u) {
        uint category = ADV_SIGNAL_SEGMENTATION_SKY;
        if (isSkyPath(primary.key) && isCelestialBillboardVisible(primary.rayDirection)) {
            category |= ADV_SIGNAL_SEGMENTATION_CELESTIAL;
        }
        return category;
    }
    if ((flags & ADV_PATH_FLAG_TERMINAL_SURFACE) == 0u) { return ADV_SIGNAL_SEGMENTATION_SKIP; }
    if ((flags & (ADV_PATH_FLAG_PORTAL | ADV_PATH_FLAG_EMISSIVE)) != 0u) { return ADV_SIGNAL_SEGMENTATION_EMISSIVE; }
    return ADV_SIGNAL_SEGMENTATION_SURFACE;
}

vec3 sampleFarVolumeVisibility(vec2 uv, float distance) {
    ivec2 extent = textureSize(volumeFarVisibilityTexture, 0);
    vec2 texel = uv * vec2(extent) - 0.5;
    ivec2 base = ivec2(floor(texel));
    vec2 fraction = fract(texel);
    vec3 visibility = vec3(0.0);
    float totalWeight = 0.0;
    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            ivec2 coordinate = clamp(base + ivec2(x, y), ivec2(0), extent - 1);
            vec4 sampleValue = texelFetch(volumeFarVisibilityTexture, coordinate, 0);
            vec2 bilinearWeight = mix(vec2(1.0) - fraction, fraction, bvec2(x != 0, y != 0));
            float depthWeight = exp(-abs(sampleValue.a - distance) / max(distance * 0.05, 1.0));
            float weight = bilinearWeight.x * bilinearWeight.y * depthWeight;
            visibility += sampleValue.rgb * weight;
            totalWeight += weight;
        }
    }
    return totalWeight > 1e-6 ? clamp(visibility / totalWeight, vec3(0.0), vec3(1.0)) : vec3(0.0);
}

void sampleIntegratedVolume(ivec2 flatPixel,
                            ivec2 flatExtent,
                            float pathDistance,
                            float airDistance,
                            vec3 rayDirection,
                            out vec3 inscatter,
                            out vec3 transmittance,
                            out bool isScalarCompatible) {
    inscatter = vec3(0.0);
    transmittance = vec3(1.0);
    isScalarCompatible = true;
    if (!isSignalFinite(pathDistance) || pathDistance <= 1e-5) { return; }

    float distance = min(pathDistance, ADV_VOLUME_RANGE);
    vec3 uvw = vec3((vec2(flatPixel) + 0.5) / vec2(flatExtent), volumeWFromDistance(distance));
    vec3 directEncoded = texture(volumeDirectIntegralTexture, uvw).rgb;
    vec3 giEncoded = texture(volumeIndirectIntegralTexture, uvw).rgb;
    vec3 sampledTransmittance = texture(volumeTransmittanceTexture, uvw).rgb;
    if (isSignalFinite(directEncoded)) { inscatter += max(directEncoded, vec3(0.0)) * max(directEncoded, vec3(0.0)); }
    if (isSignalFinite(giEncoded)) { inscatter += max(giEncoded, vec3(0.0)) * max(giEncoded, vec3(0.0)); }
    if (isSignalFinite(sampledTransmittance)) { transmittance = clamp(sampledTransmittance, vec3(0.0), vec3(1.0)); }
    if (airDistance > ADV_VOLUME_RANGE && worldUBO.skyType == 1u &&
        !isCameraUnderwater(skyUBO.cameraSubmersionType)) {
        float farDistance = min(airDistance, ADV_ENVIRONMENT_MAX_DISTANCE);
        float cameraHeight = float(worldUBO.cameraPos.y) + volumeCameraOrigin().y;
        float startHeight = max(cameraHeight + rayDirection.y * ADV_VOLUME_RANGE - 64.0, 0.0);
        float endHeight = max(cameraHeight + rayDirection.y * farDistance - 64.0, 0.0);
        float heightDelta = (endHeight - startHeight) * 0.012;
        float averageDensity = abs(heightDelta) > 1e-3 ?
                                   (exp(-startHeight * 0.012) - exp(-endHeight * 0.012)) / heightDelta :
                                   exp(-(startHeight + endHeight) * 0.006);
        vec3 farTransmittance = exp(-volumeExtinction(false) * averageDensity * (farDistance - ADV_VOLUME_RANGE) * 1.6);
        vec3 skyDirection = normalize(vec3(rayDirection.x, max(rayDirection.y, 0.04), rayDirection.z));
        vec3 skyRadiance = max(textureLod(skyRadianceTexture, skyDirection, 0.0).rgb, vec3(0.0));
        vec3 ambientRadiance = min(skyRadiance, max(textureLod(skyRadianceTexture, vec3(0.0, 1.0, 0.0), 0.0).rgb,
                                                   vec3(0.0)));
        vec3 visibility = sampleFarVolumeVisibility(uvw.xy, farDistance);
        skyRadiance = mix(ambientRadiance, skyRadiance, visibility);
        vec3 rainRadiance = getOvercastSkyRadiance(skyRadiance);
        vec3 farRadiance = mix(skyRadiance, rainRadiance, clamp(skyUBO.rainGradient, 0.0, 1.0));
        inscatter += transmittance * farRadiance * ADV_VOLUME_AIR_SCATTERING_ALBEDO * (vec3(1.0) - farTransmittance);
        transmittance *= farTransmittance;
    }
    inscatter = signalSanitizeRadiance(inscatter);
    float minimumValue = min(transmittance.r, min(transmittance.g, transmittance.b));
    float maximumValue = max(transmittance.r, max(transmittance.g, transmittance.b));
    isScalarCompatible = maximumValue - minimumValue <= 1e-3;
}

void resolveVolumeSegment(vec3 startInscatter,
                          vec3 startTransmittance,
                          vec3 endInscatter,
                          vec3 endTransmittance,
                          out vec3 segmentInscatter,
                          out vec3 segmentTransmittance) {
    segmentInscatter = vec3(0.0);
    segmentTransmittance = vec3(1.0);
    if (!isSignalFinite(startInscatter) || !isSignalFinite(startTransmittance) || !isSignalFinite(endInscatter) ||
        !isSignalFinite(endTransmittance)) {
        return;
    }

    vec3 safeStartTransmittance = max(startTransmittance, vec3(1e-4));
    segmentTransmittance = clamp(endTransmittance / safeStartTransmittance, vec3(0.0), vec3(1.0));
    segmentInscatter = signalSanitizeRadiance(max(endInscatter - startInscatter, vec3(0.0)) / safeStartTransmittance);
}

void sampleDimensionFog(
    float viewDepth, vec3 viewDirection, out vec3 inscatter, out vec3 transmittance, out bool isScalarCompatible) {
    float distance = INF_DISTANCE;
    float depthPerDistance = -(mat3(worldUBO.cameraEffectedViewMat) * viewDirection).z;
    if (isSignalFinite(viewDepth) && viewDepth < ADV_SIGNAL_FP16_MAX * 0.9 && isSignalFinite(depthPerDistance) &&
        depthPerDistance > 1e-6) {
        distance = max(viewDepth / depthPerDistance, 0.0);
    }
    float fogStart = worldUBO.fogStart;
    float fogEnd = worldUBO.fogEnd;
    float renderDistance = max(float(worldUBO.renderDistanceBlocks), 32.0);
    if (!isSignalFinite(fogStart) || !isSignalFinite(fogEnd) || fogEnd <= fogStart ||
        fogEnd > renderDistance * 4.0) {
        fogEnd = worldUBO.skyType == 0u ? min(renderDistance, 96.0) : renderDistance;
        fogStart = fogEnd * (worldUBO.skyType == 0u ? 0.05 : 0.75);
    }
    float density = 2.0 / max(fogEnd - fogStart, 1e-3);
    float opticalDepth = max(distance - fogStart, 0.0) * density;
    float fogTransmittance = clamp(exp(-max(opticalDepth, 0.0)), 0.0, 1.0);
    transmittance = vec3(fogTransmittance);
    inscatter = signalSanitizeRadiance(srgbToLinear(max(worldUBO.fogColor.rgb, vec3(0.0))) * (1.0 - fogTransmittance));
    isScalarCompatible = true;
}

#endif
