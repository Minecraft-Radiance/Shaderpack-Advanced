#ifndef ADV_LIGHTING_RESTIR_PACKING_GLSL
#define ADV_LIGHTING_RESTIR_PACKING_GLSL

#include "lighting/restir/storage.glsl"

vec2 restirSignNotZero(vec2 vector) {
    return vec2(vector.x >= 0.0 ? 1.0 : -1.0, vector.y >= 0.0 ? 1.0 : -1.0);
}

vec2 encodeRestirOctNormal(vec3 normal) {
    vec3 normalizedNormal = brdfNormalize(normal, vec3(0.0, 1.0, 0.0));
    normalizedNormal /= max(abs(normalizedNormal.x) + abs(normalizedNormal.y) + abs(normalizedNormal.z), 1e-8);
    vec2 encoded = normalizedNormal.xy;
    if (normalizedNormal.z < 0.0) { encoded = (vec2(1.0) - abs(encoded.yx)) * restirSignNotZero(encoded); }
    return encoded;
}

vec3 decodeRestirOctNormal(uint packedNormal) {
    vec2 encoded = unpackSnorm2x16(packedNormal);
    vec3 normal = vec3(encoded, 1.0 - abs(encoded.x) - abs(encoded.y));
    if (normal.z < 0.0) { normal.xy = (vec2(1.0) - abs(normal.yx)) * restirSignNotZero(normal.xy); }
    return brdfNormalize(normal, vec3(0.0, 1.0, 0.0));
}

uint packRestirNormal(vec3 normal) {
    return packSnorm2x16(encodeRestirOctNormal(normal));
}

uint packRestirConfidence(float confidence) {
    float bounded = isBrdfFinite(confidence) ? clamp(confidence, 0.0, 65504.0) : 0.0;
    return packHalf2x16(vec2(bounded, 0.0)) & 0xffffu;
}

uint unpackRestirLightIndex(uint packedValue) {
    return packedValue & ADV_RESTIR_SOURCE_INDEX_MASK;
}

float unpackRestirConfidence(uint packedValue) {
    uint packedHalf = (packedValue >> ADV_RESTIR_CONFIDENCE_SHIFT) & 0xffffu;
    return unpackHalf2x16(packedHalf).x;
}

uint packRestirSampleParam(bool isSecondTriangle, vec2 randomSample) {
    vec2 clampedSample = clamp(randomSample, vec2(0.0), vec2(1.0));
    uint u = uint(round(clampedSample.x * 65535.0)) & ADV_RESTIR_SAMPLE_U_MASK;
    uint v = uint(round(clampedSample.y * 32767.0)) & ADV_RESTIR_SAMPLE_V_MASK;
    return u | (v << ADV_RESTIR_SAMPLE_V_SHIFT) | (isSecondTriangle ? ADV_RESTIR_SAMPLE_TRIANGLE_BIT : 0u);
}

vec2 unpackRestirSampleXi(uint sampleParam) {
    return vec2(float(sampleParam & ADV_RESTIR_SAMPLE_U_MASK) / 65535.0,
                float((sampleParam >> ADV_RESTIR_SAMPLE_V_SHIFT) & ADV_RESTIR_SAMPLE_V_MASK) / 32767.0);
}

bool isRestirSecondTriangle(uint sampleParam) {
    return (sampleParam & ADV_RESTIR_SAMPLE_TRIANGLE_BIT) != 0u;
}

#endif
