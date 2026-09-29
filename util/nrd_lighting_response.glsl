#ifndef NRD_LIGHTING_RESPONSE_GLSL
#define NRD_LIGHTING_RESPONSE_GLSL

uint nrdLightingNormalBin(vec3 normal) {
    vec3 direction = vec3(dot(normal, vec3(1, 2, 2)), dot(normal, vec3(2, 1, -2)),
        dot(normal, vec3(-2, 2, -1)));
    return uint(direction.x >= 0) | (uint(direction.y >= 0) << 1) | (uint(direction.z >= 0) << 2);
}

#ifdef NRD_LIGHTING_RESPONSE_READ
ivec2 nrdLightingGridSize() {
    return imageSize(lightingResponseImage) / ivec2(1, 9);
}

bool nrdLightingDirectEmpty(ivec2 tile) {
    return imageLoad(lightingResponseImage, ivec2(tile.x, tile.y * 9 + 8)).r > .5;
}

float nrdSampleLightingResponse(ivec2 pixel, vec3 normal) {
    ivec2 size = nrdLightingGridSize();
    vec2 position = clamp((vec2(pixel) + .5) / 32.0 - .5, vec2(0), vec2(size - 1));
    ivec2 p = ivec2(floor(position)), q = min(p + 1, size - 1);
    vec2 f = fract(position);
    f = f * f * (3.0 - 2.0 * f);
    int bin = int(nrdLightingNormalBin(normal));
    vec2 a = imageLoad(lightingResponseImage, ivec2(p.x, p.y * 9 + bin)).rg;
    vec2 b = imageLoad(lightingResponseImage, ivec2(q.x, p.y * 9 + bin)).rg;
    vec2 c = imageLoad(lightingResponseImage, ivec2(p.x, q.y * 9 + bin)).rg;
    vec2 d = imageLoad(lightingResponseImage, ivec2(q.x, q.y * 9 + bin)).rg;
    vec4 weight = vec4((1 - f.x) * (1 - f.y), f.x * (1 - f.y), (1 - f.x) * f.y, f.x * f.y) *
        vec4(a.y, b.y, c.y, d.y);
    return dot(weight, vec4(a.x, b.x, c.x, d.x)) / max(dot(weight, vec4(1)), 1e-6);
}

#endif
#endif
