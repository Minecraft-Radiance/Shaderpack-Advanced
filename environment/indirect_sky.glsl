#ifndef ADV_ENVIRONMENT_INDIRECT_SKY_GLSL
#define ADV_ENVIRONMENT_INDIRECT_SKY_GLSL

#include "core/bindings.glsl"

layout(set = 5, binding = ADV_SKY_INDIRECT_RADIANCE_BINDING) uniform samplerCube skyIndirectRadianceTexture;

#endif
