#ifndef ADV_PATH_TRANSMISSION_SHADE_GLSL
#define ADV_PATH_TRANSMISSION_SHADE_GLSL

#ifndef ADV_REFRACTION_MAX_DISTANCE
#    define ADV_REFRACTION_MAX_DISTANCE max(1000.0, float(worldUBO.vistaDistanceBlocks))
#endif

const float ADV_REFRACTION_GLASS_EXTINCTION_SCALE = 0.5;

struct TransmissionInterface {
    bool isValid;
    bool isWater;
    uint medium;
    vec3 position;
    vec3 geometryNormal;
    vec3 shadingNormal;
    vec3 albedo;
    float opacity;
    float ior;
    float rayDistance;
};

TransmissionInterface invalidTransmissionInterface() {
    TransmissionInterface refractionInterface;
    refractionInterface.isValid = false;
    refractionInterface.isWater = false;
    refractionInterface.medium = ADV_MEDIUM_SOLID;
    refractionInterface.position = vec3(0.0);
    refractionInterface.geometryNormal = vec3(0.0, 1.0, 0.0);
    refractionInterface.shadingNormal = vec3(0.0, 1.0, 0.0);
    refractionInterface.albedo = vec3(0.0);
    refractionInterface.opacity = 1.0;
    refractionInterface.ior = ADV_GLASS_IOR;
    refractionInterface.rayDistance = 0.0;
    return refractionInterface;
}

TransmissionInterface makeTransmissionInterface(Surface surface) {
    TransmissionInterface refractionInterface = invalidTransmissionInterface();
    refractionInterface.isValid = surface.isValid;
    refractionInterface.isWater = surface.isWater;
    refractionInterface.medium = surface.medium;
    refractionInterface.position = surface.position;
    refractionInterface.geometryNormal = surface.geometryNormal;
    refractionInterface.shadingNormal = surface.shadingNormal;
    refractionInterface.albedo = surface.albedo;
    refractionInterface.opacity = surface.opacity;
    refractionInterface.ior = surface.ior;
    refractionInterface.rayDistance = surface.rayDistance;
    return refractionInterface;
}

TransmissionInterface loadTransmissionInterface(TransmissionPath primary) {
    TransmissionInterface refractionInterface = invalidTransmissionInterface();
    refractionInterface.isValid = true;
    refractionInterface.isWater = (pathFlags(primary.key) & ADV_PATH_FLAG_WATER) != 0u;
    refractionInterface.medium = pathSurfaceMedium(primary.key);
    refractionInterface.position = primary.position;
    refractionInterface.geometryNormal = normalize(primary.geometryNormal, vec3(0.0, 1.0, 0.0));
    refractionInterface.shadingNormal = normalize(primary.shadingNormal, refractionInterface.geometryNormal);
    refractionInterface.albedo = max(primary.albedo, vec3(0.0));
    refractionInterface.opacity = clamp(primary.opacity, 0.0, 1.0);
    refractionInterface.ior = ADV_GLASS_IOR;
    return refractionInterface;
}

void clearTransmissionOutput(ivec2 packedPixel) {
    clearTransmissionState(packedPixel);
    imageStore(transmissionRadianceImage, packedPixel, vec4(0.0));
}

uint refractionMask() {
    uint mask = WORLD_MASK | CLOUD_MASK | BOAT_WATER_MASK;
    if (worldUBO.isFirstPerson == 0u) { mask |= PLAYER_MASK; }
    return mask;
}

uint refractionCullFlags() {
    return uint(ADV_RAY_FLAGS) | gl_RayFlagsCullBackFacingTrianglesEXT;
}

HitPayload traceRefractionHit(vec3 origin,
                              vec3 direction,
                              float tMin,
                              float tMax,
                              float coneWidth,
                              float coneSpread,
                              uint role,
                              uint mask,
                              uint rayFlags) {
    resetHit(hitPayload, coneWidth, coneSpread, role);
    traceRayEXT(topLevelAS, rayFlags, mask, 1, 1, uint(ADV_PATH_SURFACE_MISS_INDEX), origin, tMin, direction, tMax, 0);
    return hitPayload;
}

HitPayload
findRefractionSegmentHit(vec3 origin, vec3 direction, float coneWidth, float coneSpread, inout uint rayBudgetUsed) {
    HitPayload closest =
        traceRefractionHit(origin, direction, 0.0, float(ADV_REFRACTION_MAX_DISTANCE), coneWidth, coneSpread,
                           ADV_TRACE_ROLE_PRIMARY, refractionMask(), refractionCullFlags());
    ++rayBudgetUsed;
    return closest;
}

vec3 refractionOffsetAlongNormal(vec3 position, vec3 offsetNormal) {
    const float originThreshold = 1.0 / 32.0;
    const float floatScale = 1.0 / 65536.0;
    const float integerScale = 256.0;
    ivec3 integerOffset = ivec3(integerScale * offsetNormal);
    ivec3 positionBits = floatBitsToInt(position);
    ivec3 offsetBits = ivec3(position.x < 0.0 ? -integerOffset.x : integerOffset.x,
                             position.y < 0.0 ? -integerOffset.y : integerOffset.y,
                             position.z < 0.0 ? -integerOffset.z : integerOffset.z);
    vec3 integerPosition = intBitsToFloat(positionBits + offsetBits);
    return vec3(abs(position.x) < originThreshold ? position.x + floatScale * offsetNormal.x : integerPosition.x,
                abs(position.y) < originThreshold ? position.y + floatScale * offsetNormal.y : integerPosition.y,
                abs(position.z) < originThreshold ? position.z + floatScale * offsetNormal.z : integerPosition.z);
}

vec3 refractionOffsetRay(vec3 position, vec3 normal, vec3 direction) {
    float side = dot(direction, normal) >= 0.0 ? 1.0 : -1.0;
    return refractionOffsetAlongNormal(position, normal * side);
}

void resolveInitialRefractionBranchOrigin(TransmissionPath primary,
                                          bool isCameraPrimary,
                                          vec3 direction,
                                          out bool hasParallax,
                                          out vec3 position,
                                          out vec3 normal) {
    position = primary.position;
    normal = normalize(primary.geometryNormal, vec3(0.0, 1.0, 0.0));
    hasParallax = isCameraPrimary && isParallaxStateValid(primary.parallax);
    if (!hasParallax) { return; }
    vec3 resolvedPosition;
    vec3 resolvedNormal;
    if (resolveParallaxStateExit(primary.parallax, primary.position, primary.geometryNormal, direction,
                                 resolvedPosition, resolvedNormal)) {
        position = resolvedPosition;
        normal = resolvedNormal;
    }
}

uint refractionSurfaceMedium(TransmissionInterface surface) {
    if (surface.medium == ADV_MEDIUM_WATER) { return ADV_MEDIUM_WATER; }
    if (surface.medium == ADV_MEDIUM_GLASS && surface.opacity < 1.0 - 1e-6) { return ADV_MEDIUM_GLASS; }
    return ADV_MEDIUM_SOLID;
}

vec3 refractionOpticalNormal(TransmissionInterface surface, vec3 incidentDirection) {
    vec3 geometryNormal = normalize(surface.geometryNormal, vec3(0.0, 1.0, 0.0));
#if ADV_WATER_WAVES_ENABLED != 0
    if (surface.isWater) {
        vec3 waveNormal = normalize(surface.shadingNormal, geometryNormal);
        if (dot(waveNormal, geometryNormal) < 0.0) { waveNormal = -waveNormal; }
        if (dot(incidentDirection, waveNormal) < -1e-5) { return waveNormal; }
    }
#endif
    return geometryNormal;
}

f16vec3 glassSegmentTransmittance(vec3 surfaceTint, float distance) {
    float clampedDistance = clamp(distance, 0.0, ADV_MAX_MEDIA_EXTINCTION_DISTANCE);
    vec3 absorption = max(vec3(1.0) - clamp(surfaceTint, vec3(0.0), vec3(1.0)), vec3(0.0));
    return f16vec3(exp(-absorption * clampedDistance * ADV_REFRACTION_GLASS_EXTINCTION_SCALE));
}

vec3 sanitizeRefractionRadiance(vec3 radiance) {
    if (!isFinite(radiance)) { return vec3(0.0); }
    return clamp(radiance, vec3(0.0), vec3(ADV_TRANSMISSION_STATE_FP16_MAX));
}

float refractionFresnelTransmission(float cosIncident,
                                    float sourceIor,
                                    float destinationIor,
                                    out bool hasTotalInternalReflection) {
    float eta = sourceIor / max(destinationIor, 1e-5);
    float k = eta * eta * (1.0 - cosIncident * cosIncident);
    hasTotalInternalReflection = k > 1.0;
    if (hasTotalInternalReflection) { return 1.0; }
    float cosTransmitted = sqrt(max(1.0 - k, 0.0));
    float denominator = max(sourceIor + destinationIor, 1e-5);
    float r0 = (sourceIor - destinationIor) / denominator;
    r0 *= r0;
    float fresnelFactor = sourceIor <= destinationIor ? 1.0 - cosIncident : 1.0 - cosTransmitted;
    float fresnelFactorSquared = fresnelFactor * fresnelFactor;
    float reflection = r0 + (1.0 - r0) * fresnelFactorSquared * fresnelFactorSquared * fresnelFactor;
    return clamp(1.0 - reflection, 0.0, 1.0);
}

void shadeTransmission(ivec2 packedPixel, ivec2 flatExtent, TransmissionPath primary) {
    uint primaryFlags = pathFlags(primary.key);
    bool isTerminalSurface = (primaryFlags & ADV_PATH_FLAG_TERMINAL_SURFACE) != 0u;
    uint splitBounce = pathSplitBounce(primary.key);
    uint bounceCount = pathBounceCount(primary.key);
    if (!isPathValid(primary.key) || !isSplitPath(primary.key) || splitBounce == 0u || splitBounce > bounceCount ||
        isSkyPath(primary.key) || !isTerminalSurface || primary.opacity >= 1.0 - 1e-6) {
        clearTransmissionOutput(packedPixel);
        return;
    }

    TransmissionInterface currentSurface = loadTransmissionInterface(primary);
    uint hitSurfaceMedium = refractionSurfaceMedium(currentSurface);
    if (hitSurfaceMedium != ADV_MEDIUM_WATER && hitSurfaceMedium != ADV_MEDIUM_GLASS) {
        clearTransmissionOutput(packedPixel);
        return;
    }
    clearTransmissionState(packedPixel);

    float coneSpread =
        coneSpreadFromFov(fovYFromProj(worldUBO.cameraProjMat), fovXFromProj(worldUBO.cameraProjMat), vec2(flatExtent));
    float coneWidth = max(primary.pathLength, 0.0) * coneSpread;
    vec3 rayDirection = normalize(primary.rayDirection, vec3(0.0, 0.0, -1.0));
    vec3 rayOrigin = currentSurface.position;
    f16vec3 transmission = f16vec3(1.0);
    uint currentMedium = pathTerminalMedium(primary.key);
    if (currentMedium >= ADV_MEDIUM_COUNT) {
        currentMedium = isCameraUnderwater(skyUBO.cameraSubmersionType) ? ADV_MEDIUM_WATER : ADV_MEDIUM_AIR;
    }
    float16_t currentIor = float16_t(mediumIor(currentMedium, ADV_GLASS_IOR));
    uint glassExteriorMedium = currentMedium == ADV_MEDIUM_GLASS ? ADV_MEDIUM_AIR : currentMedium;
    float distanceThroughAir = 0.0;
    float totalRefractionDistance = 0.0;
    bool hasReachedSky = false;
    bool hasReachedSolid = false;
    HitPayload terminalHit;
    resetHit(terminalHit, 0.0, coneSpread, ADV_TRACE_ROLE_PRIMARY);
    uint rayBudgetUsed = pathRayBudgetUsed(primary.key);

    for (uint transition = 0u; transition < ADV_PATH_RAY_BUDGET; ++transition) {
        if (!hasPathRayBudget(rayBudgetUsed)) { break; }
        uint nextMedium;
        float16_t nextIor;
        if (hitSurfaceMedium == ADV_MEDIUM_WATER) {
            nextMedium = currentMedium == ADV_MEDIUM_WATER ? ADV_MEDIUM_AIR : ADV_MEDIUM_WATER;
            nextIor = float16_t(mediumIor(nextMedium, ADV_GLASS_IOR));
        } else if (currentMedium == ADV_MEDIUM_GLASS) {
            nextMedium = glassExteriorMedium;
            nextIor = float16_t(mediumIor(nextMedium, ADV_GLASS_IOR));
        } else {
            glassExteriorMedium = currentMedium;
            nextMedium = ADV_MEDIUM_GLASS;
            nextIor = float16_t(mediumIor(nextMedium, currentSurface.ior));
        }

        vec3 interfaceNormal = refractionOpticalNormal(currentSurface, rayDirection);
        float cosIncident = clamp(dot(-rayDirection, interfaceNormal), 0.0, 1.0);
        float16_t etaHalf = currentIor / max(nextIor, float16_t(1e-5));
        bool hasTotalInternalReflection;
        float fresnelTransmission =
            refractionFresnelTransmission(cosIncident, float(currentIor), float(nextIor), hasTotalInternalReflection);
        vec3 refracted =
            hasTotalInternalReflection ? vec3(0.0) : refract(rayDirection, interfaceNormal, float(etaHalf));
        hasTotalInternalReflection =
            hasTotalInternalReflection || dot(refracted, refracted) <= 1e-10 || !isFinite(refracted);
        if (hasTotalInternalReflection) {
            rayDirection = normalize(reflect(rayDirection, interfaceNormal), -rayDirection);
            nextMedium = currentMedium;
            nextIor = currentIor;
        } else {
            transmission *= f16vec3(fresnelTransmission);
            if (hitSurfaceMedium == ADV_MEDIUM_GLASS) { transmission *= f16vec3(1.0 - currentSurface.opacity); }
            rayDirection = normalize(refracted, rayDirection);
        }

        bool shouldUsePrimaryParallax = false;
        vec3 branchPosition = currentSurface.position;
        vec3 branchNormal = currentSurface.geometryNormal;
        if (transition == 0u) {
            resolveInitialRefractionBranchOrigin(primary, bounceCount == 0u, rayDirection, shouldUsePrimaryParallax,
                                                 branchPosition, branchNormal);
        }
        if (shouldUsePrimaryParallax) {
            float side = dot(rayDirection, branchNormal) >= 0.0 ? 1.0 : -1.0;
            rayOrigin = branchPosition + branchNormal * (side * 0.0002);
        } else {
            rayOrigin = refractionOffsetRay(currentSurface.position, currentSurface.geometryNormal, rayDirection);
        }

        HitPayload hit;
        resetHit(hit, coneWidth, coneSpread, ADV_TRACE_ROLE_PRIMARY);
        hit = findRefractionSegmentHit(rayOrigin, rayDirection, coneWidth, coneSpread, rayBudgetUsed);
        TransmissionInterface nextSurface = invalidTransmissionInterface();
        Surface decodedSurface = invalidSurface();
        if (isHitValid(hit)) {
            if (!decodeSurface(hit, rayOrigin, rayDirection, false, decodedSurface)) {
                transmission = f16vec3(0.0);
                hasReachedSolid = true;
                break;
            }
            nextSurface = makeTransmissionInterface(decodedSurface);
        }
        float segmentDistance = isHitValid(hit) ? nextSurface.rayDistance : float(ADV_REFRACTION_MAX_DISTANCE);
        totalRefractionDistance += segmentDistance;
        f16vec3 mediumTransmission = f16vec3(segmentTransmittance(nextMedium, segmentDistance));
        transmission *= mediumTransmission;
        if (nextMedium == ADV_MEDIUM_GLASS) {
            transmission *= glassSegmentTransmittance(currentSurface.albedo, segmentDistance);
        }
        if (nextMedium == ADV_MEDIUM_AIR) { distanceThroughAir += segmentDistance; }
        coneWidth += segmentDistance * coneSpread;
        currentMedium = nextMedium;
        currentIor = nextIor;

        vec3 transmission32 = vec3(transmission);
        if (!isFinite(transmission32) || max(transmission32.r, max(transmission32.g, transmission32.b)) <= 1e-5) {
            transmission = f16vec3(0.0);
            hasReachedSolid = true;
            break;
        }
        if (!isHitValid(hit)) {
            hasReachedSky = true;
            break;
        }
        hitSurfaceMedium = refractionSurfaceMedium(nextSurface);
        if (hitSurfaceMedium == ADV_MEDIUM_SOLID) {
            hasReachedSolid = true;
            terminalHit = hit;
            break;
        }
        currentSurface = nextSurface;
    }

    if (hasReachedSky) {
        vec3 skyRadiance = shadeIndirectCloud(rayOrigin, rayDirection, calculateSkyRadiance(rayDirection));
        vec3 refractionRadiance = sanitizeRefractionRadiance(skyRadiance * vec3(transmission));
        if (isFinite(totalRefractionDistance)) {
            imageStore(pathTransmissionDistanceImage, packedPixel, vec4(-max(totalRefractionDistance, 1e-4)));
            imageStore(transmissionRadianceImage, packedPixel, vec4(refractionRadiance, 1.0));
        } else {
            clearTransmissionOutput(packedPixel);
        }
        return;
    }

    if (hasReachedSolid && isHitValid(terminalHit)) {
        storeTransmissionState(packedPixel, terminalHit, rayDirection, coneWidth, coneSpread, vec3(transmission),
                               totalRefractionDistance, distanceThroughAir, currentMedium, rayBudgetUsed);
    }
    imageStore(transmissionRadianceImage, packedPixel, vec4(0.0));
}

#endif
