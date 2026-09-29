#ifndef ADV_ENVIRONMENT_CLOUD_SHADE_GLSL
#define ADV_ENVIRONMENT_CLOUD_SHADE_GLSL

#include "environment/cloud/integrate.glsl"

bool isCloudRadianceFinite(vec3 radiance) {
    return !any(isnan(radiance)) && !any(isinf(radiance));
}

CloudRadiance shadeCloud(vec3 rayOrigin,
                         vec3 rayDirection,
                         vec3 skyBackgroundRadiance,
                         int viewStepCount,
                         int lightStepCount,
                         int ambientStepCount,
                         bool indirectLighting) {
    CloudRadiance cloudRadiance;
    cloudRadiance.radiance = max(skyBackgroundRadiance, vec3(0.0));
    cloudRadiance.transmittance = 1.0;
    cloudRadiance.hitMask = 0.0;
    if (ADV_CLOUD_MODE != 2u) { return cloudRadiance; }

    cloudRadiance = integrateCloud(rayOrigin, rayDirection, cloudRadiance.radiance, max(viewStepCount, 1),
                                   max(lightStepCount, 1), max(ambientStepCount, 1), indirectLighting);
    if (!isCloudRadianceFinite(cloudRadiance.radiance) || isnan(cloudRadiance.transmittance) ||
        isinf(cloudRadiance.transmittance)) {
        cloudRadiance.radiance = max(skyBackgroundRadiance, vec3(0.0));
        cloudRadiance.transmittance = 1.0;
        cloudRadiance.hitMask = 0.0;
    } else {
        cloudRadiance.radiance = max(cloudRadiance.radiance, vec3(0.0));
        cloudRadiance.transmittance = clamp(cloudRadiance.transmittance, 0.0, 1.0);
    }
    return cloudRadiance;
}

vec3 shadeIndirectCloud(vec3 rayOrigin, vec3 rayDirection, vec3 skyBackgroundRadiance) {
    if (ADV_CLOUD_INDIRECT_ENABLED == 0) { return max(skyBackgroundRadiance, vec3(0.0)); }
    return shadeCloud(rayOrigin, rayDirection, skyBackgroundRadiance, ADV_CLOUD_INDIRECT_VIEW_STEPS,
                      ADV_CLOUD_INDIRECT_LIGHT_STEPS, ADV_CLOUD_INDIRECT_AMBIENT_STEPS, true)
        .radiance;
}

#endif
