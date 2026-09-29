#ifndef ADV_PATH_DIRECT_GLSL
#define ADV_PATH_DIRECT_GLSL

#ifndef ADV_SUN_SHADOW_MAX_DISTANCE
#    define ADV_SUN_SHADOW_MAX_DISTANCE max(1000.0, float(worldUBO.vistaDistanceBlocks))
#endif
#ifndef ADV_PATH_SHADOW_MISS_INDEX
#    define ADV_PATH_SHADOW_MISS_INDEX 0
#endif

vec3 sunOffsetOrigin(vec3 position, vec3 normal, vec3 direction) {
    float side = dot(direction, normal) >= 0.0 ? 1.0 : -1.0;
    return position + normal * (side * 0.0002);
}

const uint ADV_SUN_SAMPLE_COUNT = 1u;

void storeSunLobes(ivec2 packedPixel, vec3 diffuse, vec3 specular, float hitT) {
    imageStore(sunBrdfDistanceImage, ivec3(packedPixel, ADV_SUN_DIFFUSE_LAYER), vec4(sanitizeRadiance(diffuse), hitT));
    imageStore(sunBrdfDistanceImage, ivec3(packedPixel, ADV_SUN_SPECULAR_LAYER),
               vec4(sanitizeRadiance(specular), hitT));
}

float sunBlockerDistance(SunShadowTrace shadow, out bool isDynamic) {
    float maximumDistance = float(ADV_SUN_SHADOW_MAX_DISTANCE);
    bool hasOccluder =
        isFinite(shadow.blockerHitT) && shadow.blockerHitT > 1e-6 && shadow.blockerHitT < maximumDistance - 1e-3;
    isDynamic = shadow.dynamicBlocker != 0u && hasOccluder;
    if (shadow.reachedLight != 0u && !hasOccluder) { return 65504.0; }
    return hasOccluder ? clamp(shadow.blockerHitT, 1e-3, 65504.0) : 0.0;
}

void shadeSun(ivec2 packedPixel, CheckerCoordinate checker, ShadingPath primary) {
    uint flags = pathFlags(primary.key);
    if (!isPathValid(primary.key) || isSkyPath(primary.key) || (flags & ADV_PATH_FLAG_TERMINAL_SURFACE) == 0u ||
        (flags & (ADV_PATH_FLAG_NO_REFLECT | ADV_PATH_FLAG_PORTAL)) != 0u) {
        storeSunLobes(packedPixel, vec3(0.0), vec3(0.0), 0.0);
        return;
    }

    vec3 lightDirection;
    vec3 lightRadiance;
    float lightScale;
    getCelestialPrimaryDirectLight(lightDirection, lightRadiance, lightScale);
    if (worldUBO.skyType != 1u || lightScale <= 1e-6) {
        storeSunLobes(packedPixel, vec3(0.0), vec3(0.0), 0.0);
        return;
    }

    vec3 geometryNormal = brdfNormalize(primary.geometryNormal, vec3(0.0, 1.0, 0.0));
    vec3 shadingNormal = brdfNormalize(primary.shadingNormal, geometryNormal);
    vec3 viewDirection = brdfNormalize(-primary.rayDirection, shadingNormal);
    uint terminalMedium = pathTerminalMedium(primary.key);
    bool isStartingUnderwater = terminalMedium == ADV_MEDIUM_WATER;
    vec3 centerSurfaceDirection = isStartingUnderwater ? underwaterDirectionToLight(lightDirection) : lightDirection;
    if (dot(geometryNormal, centerSurfaceDirection) <= 1e-6) {
        storeSunLobes(packedPixel, vec3(0.0), vec3(0.0), 1e-3);
        return;
    }
    DirectBrdf centerBrdf = evaluateDirectBrdf(shadingNormal, centerSurfaceDirection, viewDirection,
                                               clamp(primary.f0, vec3(0.0), vec3(1.0)), primary.roughness);
    bool isSecondarySurface = pathBounceCount(primary.key) != 0u;
    uint mask = WORLD_MASK | CLOUD_MASK | BOAT_WATER_MASK;
    if ((flags & ADV_PATH_FLAG_HAND) == 0u) { mask |= PLAYER_MASK; }
    uint shadowFlags = isSecondarySurface ? ADV_SHADOW_FLAG_DISABLE_PARALLAX : 0u;

    vec3 averageTransmission = vec3(0.0);
    vec2 sequenceRotation = blueNoise2(blueNoiseTexture, checker.flatPixel, worldUBO.seed, 0u);
    float lightSampleWeight = 1.0 / float(ADV_SUN_SAMPLE_COUNT);
    float bestVisibleImportance = 0.0;
    float representativeHitT = 0.0;
    bool representativeDynamic = false;
    float fallbackHitT = 0.0;
    bool fallbackDynamic = false;

    for (uint sampleIndex = 0u; sampleIndex < ADV_SUN_SAMPLE_COUNT; ++sampleIndex) {
        vec2 diskSample = celestialHammersley(sampleIndex, ADV_SUN_SAMPLE_COUNT, sequenceRotation);
        vec3 sampledAirDirection = sampleSunDisk(diskSample, lightDirection);
        vec3 sampledSurfaceDirection =
            isStartingUnderwater ? underwaterDirectionToLight(sampledAirDirection) : sampledAirDirection;
        if (dot(geometryNormal, sampledSurfaceDirection) <= 1e-6) { continue; }

        vec3 primaryExitPosition = primary.position;
        vec3 primaryExitNormal = geometryNormal;
        if (!isSecondarySurface &&
            !resolvePathParallaxExit(primary.parallax, primary.position, primary.geometryNormal,
                                     sampledSurfaceDirection, primaryExitPosition, primaryExitNormal)) {
            continue;
        }

        vec3 origin = sunOffsetOrigin(primaryExitPosition, primaryExitNormal, sampledSurfaceDirection);
        uint sunRayFlags = pathNeedsBackFaceCull(primary.key) ?
                               uint(ADV_RAY_FLAGS) | gl_RayFlagsCullBackFacingTrianglesEXT :
                               uint(ADV_RAY_FLAGS);
        SunShadowTrace shadow = traceSunShadow(origin, sampledAirDirection, sampledSurfaceDirection,
                                               isStartingUnderwater, float(ADV_SUN_SHADOW_MAX_DISTANCE), shadowFlags,
                                               mask, sunRayFlags, uint(ADV_PATH_SHADOW_MISS_INDEX));
        vec3 transmission = shadow.reachedLight != 0u ? sunShadowSanitizeTransmission(shadow.transmission) : vec3(0.0);
        averageTransmission += transmission * lightSampleWeight;

        bool sampleDynamic;
        float sampleHitT = sunBlockerDistance(shadow, sampleDynamic);
        if (sampleHitT > 0.0 && (fallbackHitT <= 0.0 || (sampleHitT < 65504.0 && sampleHitT < fallbackHitT))) {
            fallbackHitT = sampleHitT;
            fallbackDynamic = sampleDynamic;
        }

        float visibleImportance = luminance(transmission);
        if (visibleImportance > bestVisibleImportance && sampleHitT > 0.0) {
            bestVisibleImportance = visibleImportance;
            representativeHitT = sampleHitT;
            representativeDynamic = sampleDynamic;
        }
    }

    if (representativeHitT <= 0.0) {
        representativeHitT = max(fallbackHitT, 1e-3);
        representativeDynamic = fallbackDynamic;
    }
    if (representativeDynamic && representativeHitT > 0.0 && representativeHitT < 65504.0) {
        representativeHitT = -representativeHitT;
    }
    vec3 diffuseBrdfVisibility = centerBrdf.diffuse * averageTransmission;
    vec3 specularBrdfVisibility = centerBrdf.specular * averageTransmission;
    storeSunLobes(packedPixel, diffuseBrdfVisibility, specularBrdfVisibility, representativeHitT);
}

#endif
