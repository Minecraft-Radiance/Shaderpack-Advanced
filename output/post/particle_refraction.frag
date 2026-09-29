#version 460
#extension GL_EXT_nonuniform_qualifier : enable
#extension GL_GOOGLE_include_directive : require

#include "common/shared.hpp"
#include "core/bindings.glsl"

#ifndef ADV_POST_RAIN_REFRACTION_ENABLED
#    define ADV_POST_RAIN_REFRACTION_ENABLED 1
#endif

#ifndef ADV_POST_RAIN_SPLASH_REFRACTION_OFFSET_PERCENT
#    define ADV_POST_RAIN_SPLASH_REFRACTION_OFFSET_PERCENT 5.0
#endif

#ifndef ADV_POST_RAIN_SPLASH_SCATTERING_PERCENT
#    define ADV_POST_RAIN_SPLASH_SCATTERING_PERCENT 15.0
#endif

#ifndef ADV_POST_RAIN_SPLASH_LENS_PER_TEXEL
#    define ADV_POST_RAIN_SPLASH_LENS_PER_TEXEL 0
#endif

layout(set = 0, binding = 0) uniform sampler2D textures[];

layout(set = 1, binding = 0) uniform WorldUniform {
    WorldUBO worldUBO;
};

layout(set = 4, binding = ADV_POST_SCENE_COLOR_BINDING) uniform sampler2D postSceneColorTexture;

layout(location = 0) in vec3 pos;
layout(location = 3) flat in uint useColorLayer;
layout(location = 4) in vec4 colorLayer;
layout(location = 5) flat in uint useTexture;
layout(location = 7) in vec2 textureUV;
layout(location = 10) flat in uint textureID;

layout(location = 0) out vec4 fragColor;

struct RainSplashSample {
    ivec2 basePixel;
    ivec2 samplePixel;
    float coverage;
    float edge;
    float center;
};

float particleLinearDepth() {
    return max(-(mat4(mat3(worldUBO.cameraEffectedViewMat)) * vec4(pos, 1.0)).z, 0.0);
}

ivec2 currentPixel(ivec2 resolution) {
    return clamp(ivec2(gl_FragCoord.xy), ivec2(0), resolution - ivec2(1));
}

vec3 sampleLdr(ivec2 pixel) {
    return texelFetch(postSceneColorTexture, pixel, 0).rgb;
}

float rainSplashLensCoordinate() {
#if ADV_POST_RAIN_SPLASH_LENS_PER_TEXEL == 0
    return textureUV.x;
#else
    ivec2 textureResolution = textureSize(textures[nonuniformEXT(textureID)], 0);
    if (textureResolution.x <= 0) { return textureUV.x; }
    return fract(textureUV.x * float(textureResolution.x));
#endif
}

RainSplashSample rainSplashSample(ivec2 resolution, float particleAlpha) {
    RainSplashSample lens;
    lens.basePixel = currentPixel(resolution);
    lens.samplePixel = lens.basePixel;
    lens.coverage = smoothstep(0.04, 0.45, particleAlpha);
    lens.edge = 0.0;
    lens.center = 0.0;

#if ADV_POST_RAIN_REFRACTION_ENABLED == 0
    return lens;
#else
    float lensCoordinate = rainSplashLensCoordinate();
    float cylinderX = clamp(lensCoordinate * 2.0 - 1.0, -0.985, 0.985);
    float cylinderZ = sqrt(max(1.0 - cylinderX * cylinderX, 1e-4));
    float cylinderSlope = clamp(cylinderX / max(cylinderZ, 0.16), -5.0, 5.0);
    float bend = sign(cylinderSlope) * pow(abs(cylinderSlope) / 5.0, 0.62);

    float silhouetteMask = 1.0 - smoothstep(0.985, 1.0, abs(cylinderX));
    float lensMask = lens.coverage * silhouetteMask;
    float maxOffsetPixels =
        float(resolution.x) * clamp(ADV_POST_RAIN_SPLASH_REFRACTION_OFFSET_PERCENT, 0.0, 100.0) * 0.01;
    int offsetPixels = int(round(bend * lensMask * maxOffsetPixels));

    lens.samplePixel = clamp(lens.basePixel + ivec2(offsetPixels, 0), ivec2(0), resolution - ivec2(1));
    lens.edge = pow(clamp(abs(cylinderX), 0.0, 1.0), 3.0) * lensMask;
    lens.center = pow(clamp(1.0 - abs(cylinderX), 0.0, 1.0), 2.5) * lensMask;
    return lens;
#endif
}

vec4 composeRainSplash(vec4 particleColor) {
    ivec2 resolution = textureSize(postSceneColorTexture, 0);
    if (resolution.x <= 0 || resolution.y <= 0) { discard; }

    RainSplashSample lens = rainSplashSample(resolution, particleColor.a);
    vec3 baseColor = sampleLdr(lens.basePixel);
    float scattering = clamp(ADV_POST_RAIN_SPLASH_SCATTERING_PERCENT, 0.0, 100.0) * 0.01;

#if ADV_POST_RAIN_REFRACTION_ENABLED == 0
    vec3 rainColor = baseColor * particleColor.rgb * (particleColor.a * scattering);
    return vec4(clamp(baseColor + rainColor, vec3(0.0), vec3(1.0)), 1.0);
#else
    vec3 refractedColor = sampleLdr(lens.samplePixel);
    vec3 incidentColor = max(baseColor, refractedColor);
    vec3 rainTint = incidentColor * particleColor.rgb * scattering * (0.45 * lens.coverage + 0.55 * lens.edge);
    vec3 highlight = incidentColor * (scattering * (0.20 * lens.edge + 0.05 * lens.center));
    return vec4(clamp(refractedColor + rainTint + highlight, vec3(0.0), vec3(1.0)), 1.0);
#endif
}

void main() {
    if (useTexture == 0u) { discard; }

    vec4 color = texture(textures[nonuniformEXT(textureID)], textureUV);
    if (useColorLayer > 0u) { color *= colorLayer; }
    if (color.a < 0.1) { discard; }

    float linearDepth = particleLinearDepth();
    fragColor = composeRainSplash(color);

    gl_FragDepth = clamp(linearDepth / 1000.0, 0.0, 1.0);
}
