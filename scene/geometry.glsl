#ifndef ADV_SCENE_GEOMETRY_GLSL
#define ADV_SCENE_GEOMETRY_GLSL

#include "core/math.glsl"
#include "scene/instances.glsl"

vec3 transformPoint(AccelerationStructureInstance instance, vec3 point) {
    return vec3(dot(instance.transform0.xyz, point) + instance.transform0.w,
                dot(instance.transform1.xyz, point) + instance.transform1.w,
                dot(instance.transform2.xyz, point) + instance.transform2.w);
}

vec3 transformVector(AccelerationStructureInstance instance, vec3 vector) {
    return vec3(dot(instance.transform0.xyz, vector), dot(instance.transform1.xyz, vector),
                dot(instance.transform2.xyz, vector));
}

void buildBasis(vec3 dPdu, vec3 dPdv, vec3 normal, out vec3 tangent, out vec3 bitangent) {
    tangent = dPdu - normal * dot(normal, dPdu);
    vec3 tangentFallback = abs(normal.y) < 0.999 ? normalize(cross(vec3(0.0, 1.0, 0.0), normal), vec3(1.0, 0.0, 0.0)) :
                                                   vec3(1.0, 0.0, 0.0);
    tangent = normalize(tangent, tangentFallback);
    bitangent = normalize(cross(normal, tangent), dPdv);
    tangent = normalize(cross(bitangent, normal), tangent);
}

vec3 applyNormalMap(vec3 localNormal, vec3 tangent, vec3 bitangent, vec3 geometryNormal, vec3 viewDirection) {
    localNormal.y = -localNormal.y;
    vec3 mapped =
        normalize(tangent * localNormal.x + bitangent * localNormal.y + geometryNormal * localNormal.z, geometryNormal);
    if (dot(mapped, viewDirection) <= 0.0) { return geometryNormal; }
    return mapped;
}

#endif
