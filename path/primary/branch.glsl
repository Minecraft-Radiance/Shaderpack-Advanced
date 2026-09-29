#ifndef ADV_PATH_PRIMARY_BRANCH_GLSL
#define ADV_PATH_PRIMARY_BRANCH_GLSL

#include "path/primary/trace.glsl"

bool resolvePrimaryBranchOrigin(
    Surface surface, vec3 direction, bool shouldAllowBlockedFallback, out vec3 position, out vec3 normal) {
    position = surface.position;
    normal = surface.geometryNormal;
    if (!surface.hasParallax) { return true; }
    vec3 resolvedPosition;
    vec3 resolvedNormal;
    if (resolveSurfaceParallaxExit(surface, direction, resolvedPosition, resolvedNormal)) {
        position = resolvedPosition;
        normal = resolvedNormal;
        return true;
    }
    return shouldAllowBlockedFallback;
}

bool resolvePrimaryRefractionBranch(Surface surface,
                                    vec3 incidentDirection,
                                    float16_t currentIor,
                                    float16_t nextIor,
                                    out vec3 origin,
                                    out vec3 direction) {
    float16_t etaHalf = currentIor / max(nextIor, float16_t(1e-5));
    vec3 refracted = refract(incidentDirection, opticalInterfaceNormal(surface, incidentDirection), float(etaHalf));
    if (dot(refracted, refracted) <= 1e-10 || !isFinite(refracted)) {
        origin = surface.position;
        direction = incidentDirection;
        return false;
    }

    direction = normalize(refracted, incidentDirection);
    vec3 branchPosition;
    vec3 branchNormal;
    resolvePrimaryBranchOrigin(surface, direction, true, branchPosition, branchNormal);
    if (surface.hasParallax) {
        origin = offsetParallaxExit(branchPosition, branchNormal, direction);
    } else {
        origin = offsetRay(surface.position, surface.outwardGeometryNormal, direction);
    }
    return true;
}

#endif
