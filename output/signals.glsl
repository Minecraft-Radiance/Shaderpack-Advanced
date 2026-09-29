#ifndef ADV_OUTPUT_SIGNALS_GLSL
#define ADV_OUTPUT_SIGNALS_GLSL

#include "core/bindings.glsl"

const float ADV_SIGNAL_FP16_MAX = 65504.0;
const int ADV_RAW_DIFFUSE_LAYER = 0;
const int ADV_RAW_SPECULAR_LAYER = 1;

const uint ADV_SIGNAL_SEGMENTATION_SKIP = 0u;
const uint ADV_SIGNAL_SEGMENTATION_SURFACE = 1u;
const uint ADV_SIGNAL_SEGMENTATION_SKY = 2u;
const uint ADV_SIGNAL_SEGMENTATION_EMISSIVE = 4u;
const uint ADV_SIGNAL_SEGMENTATION_CELESTIAL = 8u;

#if defined(ADV_DIRECT_RADIANCE_WRITE) || defined(ADV_DIRECT_RADIANCE_READ)
#    ifdef ADV_DIRECT_RADIANCE_WRITE
#        define ADV_DIRECT_RADIANCE_ACCESS writeonly
#    else
#        define ADV_DIRECT_RADIANCE_ACCESS readonly
#    endif

layout(set = 5,
       binding = ADV_DIRECT_RADIANCE_BINDING,
       rgba16f) ADV_DIRECT_RADIANCE_ACCESS uniform image2DArray directRadianceImage;

#    undef ADV_DIRECT_RADIANCE_ACCESS
#endif

struct RawRadiance {
    vec4 diffuse;
    vec4 specular;
};

bool isSignalFinite(float scalar) {
    return !isnan(scalar) && !isinf(scalar);
}

bool isSignalFinite(vec3 vector) {
    return !any(isnan(vector)) && !any(isinf(vector));
}

bool isSignalFinite(vec4 vector) {
    return !any(isnan(vector)) && !any(isinf(vector));
}

float signalLuminance(vec3 radiance) {
    return dot(max(radiance, vec3(0.0)), vec3(0.2126, 0.7152, 0.0722));
}

vec3 signalSanitizeRadiance(vec3 radiance) {
    if (!isSignalFinite(radiance)) { return vec3(0.0); }
    return clamp(radiance, vec3(0.0), vec3(ADV_SIGNAL_FP16_MAX));
}

float signalSanitizeDepth(float depth, float fallback) {
    if (!isSignalFinite(depth) || depth < 0.0) { return fallback; }
    return clamp(depth, 0.0, ADV_SIGNAL_FP16_MAX);
}

vec3 signalNormalize(vec3 vector, vec3 fallback) {
    float lengthSquared = dot(vector, vector);
    if (!isSignalFinite(vector) || !isSignalFinite(lengthSquared) || lengthSquared <= 1e-12) { return fallback; }
    return vector * inversesqrt(lengthSquared);
}

vec3 signalDirectionFromMoment(vec4 moment) {
    if (!isSignalFinite(moment) || moment.w <= 1e-8) { return vec3(0.0); }
    return signalNormalize(moment.xyz, vec3(0.0));
}

vec4 signalPackDirectionMoment(vec4 moment) {
    vec3 direction = signalDirectionFromMoment(moment);
    bool isValid = moment.w > 1e-8 && dot(direction, direction) > 1e-8;
    return isValid ? vec4(clamp(direction, vec3(-1.0), vec3(1.0)), 1.0) : vec4(0.0);
}

#if defined(ADV_DIRECT_RADIANCE_WRITE)
void storeDirectRawRadiance(ivec2 pixel, RawRadiance radiance) {
    imageStore(directRadianceImage, ivec3(pixel, ADV_RAW_DIFFUSE_LAYER), radiance.diffuse);
    imageStore(directRadianceImage, ivec3(pixel, ADV_RAW_SPECULAR_LAYER), radiance.specular);
}
#endif

#if defined(ADV_DIRECT_RADIANCE_READ)
RawRadiance loadDirectRawRadiance(ivec2 pixel) {
    RawRadiance radiance;
    radiance.diffuse = imageLoad(directRadianceImage, ivec3(pixel, ADV_RAW_DIFFUSE_LAYER));
    radiance.specular = imageLoad(directRadianceImage, ivec3(pixel, ADV_RAW_SPECULAR_LAYER));
    return radiance;
}
#endif

vec3 signalFoggedRadiance(vec3 baseRadiance, vec3 fogInscatter, float fogTransmittance) {
    float transmittance = isSignalFinite(fogTransmittance) ? clamp(fogTransmittance, 0.0, 1.0) : 1.0;
    return signalSanitizeRadiance(signalSanitizeRadiance(baseRadiance) * transmittance +
                                  signalSanitizeRadiance(fogInscatter));
}

#endif
