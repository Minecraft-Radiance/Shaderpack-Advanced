#ifndef ADV_LIGHTING_RESTIR_STABILITY_GLSL
#define ADV_LIGHTING_RESTIR_STABILITY_GLSL

const float ADV_RESTIR_MAX_REUSE_GEOMETRY_RATIO = 8.0;
const float ADV_RESTIR_OUTLIER_RELATIVE_LIMIT = 8.0;

float restirEmitterGeometry(vec3 surfaceToLight, vec3 lightNormal) {
    float distanceSquared = dot(surfaceToLight, surfaceToLight);
    if (isnan(distanceSquared) || isinf(distanceSquared) || distanceSquared <= 1e-8) { return 0.0; }
    return max(dot(lightNormal, -surfaceToLight * inversesqrt(distanceSquared)), 0.0) / distanceSquared;
}

bool isRestirGeometryTransferStable(vec3 donorToLight, vec3 receiverToLight, vec3 lightNormal) {
    float donorGeometry = restirEmitterGeometry(donorToLight, lightNormal);
    float receiverGeometry = restirEmitterGeometry(receiverToLight, lightNormal);
    return donorGeometry > 0.0 && receiverGeometry > 0.0 &&
           receiverGeometry <= donorGeometry * ADV_RESTIR_MAX_REUSE_GEOMETRY_RATIO;
}

void includeRestirOutlierReference(inout vec2 largest, float irradiance) {
    largest = vec2(max(largest.x, irradiance), max(largest.y, min(largest.x, irradiance)));
}

float restirOutlierWeightScale(float irradiance, float reference, uint compatibleCount, uint litCount) {
    if (compatibleCount < 5u || litCount < 4u || reference <= 1e-6 || irradiance <= 1e-6) { return 1.0; }
    return min(1.0, ADV_RESTIR_OUTLIER_RELATIVE_LIMIT * reference / irradiance);
}

#endif
