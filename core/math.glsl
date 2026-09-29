#ifndef ADV_CORE_MATH_GLSL
#define ADV_CORE_MATH_GLSL

bool isFinite(float scalar) {
    return !isnan(scalar) && !isinf(scalar);
}

bool isFinite(vec2 vector) {
    return !any(isnan(vector)) && !any(isinf(vector));
}

bool isFinite(vec3 vector) {
    return !any(isnan(vector)) && !any(isinf(vector));
}

bool isFinite(vec4 vector) {
    return !any(isnan(vector)) && !any(isinf(vector));
}

vec3 normalize(vec3 vector, vec3 fallback) {
    float lengthSquared = dot(vector, vector);
    if (!isFinite(vector) || !isFinite(lengthSquared) || lengthSquared <= 1e-12) { return fallback; }
    return vector * inversesqrt(lengthSquared);
}

#endif
