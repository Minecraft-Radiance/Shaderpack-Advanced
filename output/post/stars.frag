#version 460
#extension GL_EXT_nonuniform_qualifier : enable
#extension GL_GOOGLE_include_directive : require

#include "common/shared.hpp"
#include "core/bindings.glsl"

layout(set = 1, binding = 0) uniform WorldUniform {
    WorldUBO worldUBO;
};

layout(set = 1, binding = 1) uniform SkyUniform {
    SkyUBO skyUBO;
};

layout(set = 3, binding = 5, r8ui) readonly uniform uimage2D segmentationMaskImage;

layout(set = 4, binding = ADV_STAR_CLOUD_TRANSMITTANCE_SAMPLED_BINDING) uniform sampler2D starCloudTransmittanceTexture;

layout(location = 0) in vec3 pos;
layout(location = 1) in vec4 colorLayer;
layout(location = 2) in vec2 screenUv;

layout(location = 0) out vec4 fragColor;

const uint SEGMENTATION_CATEGORY_CELESTIAL = 8u;

bool overlapsCelestialSegmentation(vec2 uv) {
    ivec2 resolution = imageSize(segmentationMaskImage);
    if (resolution.x <= 0 || resolution.y <= 0) { return false; }

    vec2 clampedUv = clamp(uv, vec2(0.0), vec2(1.0));
    ivec2 centerPixel = clamp(ivec2(floor(clampedUv * vec2(resolution))), ivec2(0), resolution - ivec2(1));
    for (int offsetY = -2; offsetY <= 2; ++offsetY) {
        for (int offsetX = -2; offsetX <= 2; ++offsetX) {
            ivec2 samplePixel = clamp(centerPixel + ivec2(offsetX, offsetY), ivec2(0), resolution - ivec2(1));
            uint category = imageLoad(segmentationMaskImage, samplePixel).r;
            if ((category & SEGMENTATION_CATEGORY_CELESTIAL) != 0u) { return true; }
        }
    }
    return false;
}

float loadCloudTransmittance(ivec2 pixel, ivec2 resolution) {
    return clamp(texelFetch(starCloudTransmittanceTexture, clamp(pixel, ivec2(0), resolution - ivec2(1)), 0).r, 0.0,
                 1.0);
}

float sampleConservativeCloudTransmittance(vec2 uv) {
    ivec2 resolution = textureSize(starCloudTransmittanceTexture, 0);
    if (resolution.x <= 0 || resolution.y <= 0) { return 1.0; }

    vec2 clampedUv = clamp(uv, vec2(0.0), vec2(1.0));
    ivec2 pixel = clamp(ivec2(floor(clampedUv * vec2(resolution))), ivec2(0), resolution - ivec2(1));
    float minTransmittance = 1.0;

    for (int offsetY = -2; offsetY <= 2; ++offsetY) {
        for (int offsetX = -2; offsetX <= 2; ++offsetX) {
            float transmittance = loadCloudTransmittance(pixel + ivec2(offsetX, offsetY), resolution);
            minTransmittance = min(minTransmittance, transmittance);
        }
    }

    return minTransmittance;
}

void main() {
    if (worldUBO.skyType != 1) { discard; }
    if (overlapsCelestialSegmentation(screenUv)) { discard; }

    float progress = skyUBO.rainGradient;
    vec4 color = colorLayer;
    color.a *= 1.0 - progress;
    if (color.a <= 1.0 / 255.0) { discard; }
    float cloudTransmittance = sampleConservativeCloudTransmittance(screenUv);
    if (cloudTransmittance < 0.999) { discard; }

    fragColor = color;
    gl_FragDepth = 0.999999;
}
