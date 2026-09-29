#ifndef ADV_SCENE_INSTANCES_GLSL
#define ADV_SCENE_INSTANCES_GLSL

struct AccelerationStructureInstance {
    vec4 transform0;
    vec4 transform1;
    vec4 transform2;
    uint customIndexAndMask;
    uint sbtOffsetAndFlags;
    uint referenceLow;
    uint referenceHigh;
};

layout(set = 1, binding = 10, std430) readonly buffer TlasInstances {
    AccelerationStructureInstance instances[];
}
tlasInstances;

uint loadInstanceMask(uint instanceID) {
    return (tlasInstances.instances[instanceID].customIndexAndMask >> 24u) & 0xFFu;
}

#endif
