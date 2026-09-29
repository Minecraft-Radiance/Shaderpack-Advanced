#ifndef ADV_SCENE_RESOURCES_GLSL
#define ADV_SCENE_RESOURCES_GLSL

#include "common/shared.hpp"

layout(set = 0, binding = 0) uniform sampler2D textures[];
layout(set = 1, binding = 1) readonly buffer BlasOffsets {
    uint offsets[];
}
blasOffsets;
layout(set = 1, binding = 2) readonly buffer IndexBufferAddresses {
    uint64_t addrs[];
}
indexBufferAddrs;
layout(set = 1, binding = 7) readonly buffer TextureMappingBuffer {
    TextureMapping mapping;
};

#include "scene/instances.glsl"

layout(set = 2, binding = 0) uniform WorldUniform {
    WorldUBO worldUBO;
};
layout(set = 2, binding = 1) uniform LastWorldUniform {
    WorldUBO lastWorldUBO;
};
layout(set = 2, binding = 2) uniform SkyUniform {
    SkyUBO skyUBO;
};

layout(std430, buffer_reference, buffer_reference_align = 4) readonly buffer IndexBuffer {
    uint indices[];
};

#include "util/vertex.glsl"

#ifndef ADV_SCENE_RESOURCES_NO_PREVIOUS_GEOMETRY
#    include "scene/motion.glsl"
#endif

#endif
