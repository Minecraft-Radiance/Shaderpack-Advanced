#ifndef ADV_PATH_INDIRECT_QUEUE_GLSL
#define ADV_PATH_INDIRECT_QUEUE_GLSL

#include "core/bindings.glsl"

#ifndef ADV_NRD_MODE
#    define ADV_NRD_MODE 0
#endif
#ifndef MCVR_USE_NRD
#    define MCVR_USE_NRD 0
#endif

uint indirectQueueCapacity() {
#if MCVR_USE_NRD
    if (uint(ADV_NRD_MODE) == 2u) { return ((uint(ADV_RENDER_WIDTH) + 1u) / 2u) * uint(ADV_RENDER_HEIGHT); }
#endif
    return uint(ADV_RENDER_WIDTH) * uint(ADV_RENDER_HEIGHT);
}

#ifdef ADV_INDIRECT_QUEUE_WRITE
layout(std430, set = 5, binding = ADV_INDIRECT_RAY_QUEUE_BINDING) buffer IndirectRayQueueBuffer {
    uint indirectRayPixels[];
};
layout(std430, set = 5, binding = ADV_DIFFUSE_DISPATCH_BINDING) buffer IndirectDiffuseArgsBuffer {
    uint indirectDiffuseWidth;
    uint indirectDiffuseHeight;
    uint indirectDiffuseDepth;
};
layout(std430, set = 5, binding = ADV_SPECULAR_DISPATCH_BINDING) buffer IndirectSpecularArgsBuffer {
    uint indirectSpecularWidth;
    uint indirectSpecularHeight;
    uint indirectSpecularDepth;
};

uint reserveIndirectRays(bool specular, uint count) {
    return specular ? atomicAdd(indirectSpecularWidth, count) : atomicAdd(indirectDiffuseWidth, count);
}

void storeIndirectRay(ivec2 pixel, bool specular, uint queueIndex) {
    uint width = uint(ADV_RENDER_WIDTH);
    uint capacity = indirectQueueCapacity();
    uint linearPixel = uint(pixel.y) * width + uint(pixel.x);
    if (specular) {
        if (queueIndex < capacity) { indirectRayPixels[capacity - 1u - queueIndex] = linearPixel; }
    } else {
        if (queueIndex < capacity) { indirectRayPixels[queueIndex] = linearPixel; }
    }
}
#else
layout(std430, set = 5, binding = ADV_INDIRECT_RAY_QUEUE_BINDING) readonly buffer IndirectRayQueueBuffer {
    uint indirectRayPixels[];
};

ivec2 loadIndirectRayPixel(uint launchIndex, bool specular) {
    uint width = uint(ADV_RENDER_WIDTH);
    uint capacity = indirectQueueCapacity();
    uint queueIndex = specular ? capacity - 1u - launchIndex : launchIndex;
    uint linearPixel = indirectRayPixels[queueIndex];
    return ivec2(int(linearPixel % width), int(linearPixel / width));
}
#endif

#endif
