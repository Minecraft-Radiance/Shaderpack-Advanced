#version 460

layout(set = 3, binding = 0) uniform sampler2D postCopyInput;

layout(location = 0) out vec4 outColor;

void main() {
    ivec2 inputSize = textureSize(postCopyInput, 0);
    ivec2 pixel = clamp(ivec2(gl_FragCoord.xy), ivec2(0), inputSize - ivec2(1));
    outColor = texelFetch(postCopyInput, pixel, 0);
}
