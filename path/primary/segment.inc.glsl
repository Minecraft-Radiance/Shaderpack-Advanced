HitPayload hit;
resetHit(hit, coneWidth, coneSpread, ADV_TRACE_ROLE_PRIMARY);
Surface surface = invalidSurface();
bool shouldStorePrefetchedTransmissionGuide = isPrefetchedRefractionHitReady;
if (ADV_PRIMARY_FIRST_SEGMENT) {
    bool hasStoredIdentity;
    uint discoveryRayBudgetUsed = 0u;
    if (!loadPrimaryHit(packedPixel, coneSpread, hit, hasStoredIdentity, discoveryRayBudgetUsed,
                        discoveryTemporalDepth) &&
        hasStoredIdentity) {
        storeInvalidPathOutputs(packedPixel, checker.flatPixel);
        return;
    }
    rayBudgetUsed = min(discoveryRayBudgetUsed, ADV_PATH_RAY_BUDGET);
} else if (isPrefetchedRefractionHitReady) {
    hit = prefetchedRefractionHit;
    isPrefetchedRefractionHitReady = false;
} else {
    if (!hasPathRayBudget(rayBudgetUsed)) { ADV_PRIMARY_SEGMENT_STOP; }
    hit = findBudgetedSegmentHit(rayOrigin, rayDirection, coneWidth, coneSpread, currentMedium, currentGlassIsHand, 0u,
                                 rayBudgetUsed);
}

if (!isHitValid(hit)) {
    if (shouldStorePrefetchedTransmissionGuide) { imageStore(primaryDiffuseAlbedoImage, checker.flatPixel, vec4(0.0)); }
    if (shouldCaptureTransparentSpecularHitDistance) {
        transparentSpecularHitDistance = INF_DISTANCE;
        shouldCaptureTransparentSpecularHitDistance = false;
    }
    if (bounce != 0u && currentMedium != ADV_MEDIUM_GLASS) {
        throughput *= f16vec3(segmentTransmittance(currentMedium, float(ADV_PRIMARY_MAX_DISTANCE)));
    }
    pathLength = INF_DISTANCE;
    isSky = true;
    bounceCount = bounce;
    ADV_PRIMARY_SEGMENT_STOP;
}

bool decoded = decodeSurface(hit, rayOrigin, rayDirection, ADV_PRIMARY_FIRST_SEGMENT, surface);
if (!decoded) {
    storeInvalidPathOutputs(packedPixel, checker.flatPixel);
    return;
}
if (shouldStorePrefetchedTransmissionGuide) {
    storePrimaryTransmissionGuide(checker.flatPixel, vec4(0.0), 0.0, true, currentMedium, surface);
}
if (shouldCaptureTransparentSpecularHitDistance) {
    transparentSpecularHitDistance = surface.rayDistance;
    shouldCaptureTransparentSpecularHitDistance = false;
}
terminalSurfaceMedium = surface.medium;
terminalCategory = surface.category;

if (ADV_PRIMARY_FIRST_SEGMENT) {
    firstInterfaceFlags |= ADV_PATH_FLAG_FIRST_HIT_VALID;
    float temporalDepth = discoveryTemporalDepth;
    vec2 temporalMotion = vec2(0.0);
    if (!isChunkGeometryBufferIndex(hit.geometryBufferIndex) || surface.isHand) {
        temporalMotion = loadPrimaryTemporalMotion(packedPixel);
    } else {
        vec3 originalPosition = cameraOrigin + primaryDirection * hit.hitT;
        vec3 previousOriginalPosition = originalPosition + vec3(worldUBO.cameraPos.xyz - lastWorldUBO.cameraPos.xyz);
        vec4 previousView = lastWorldUBO.cameraEffectedViewMat * vec4(previousOriginalPosition, 1.0);
        if (isFinite(previousView) && previousView.z < -1e-6) {
            vec4 previousClip = lastWorldUBO.cameraProjMat * previousView;
            if (isFinite(previousClip) && previousClip.w > 1e-8) {
                vec2 previousPixel = (previousClip.xy / previousClip.w * 0.5 + 0.5) * vec2(flatExtent);
                temporalMotion = previousPixel - (vec2(checker.flatPixel) + 0.5 + worldUBO.cameraJitter);
                if (!isFinite(temporalMotion)) { temporalMotion = vec2(0.0); }
            }
        }
    }
    if (surface.isWater) {
        firstInterfaceFlags |= ADV_PATH_FLAG_FIRST_HIT_WATER;
    } else if (surface.medium == ADV_MEDIUM_GLASS) {
        firstInterfaceFlags |= ADV_PATH_FLAG_FIRST_HIT_GLASS;
    } else if (surface.isCloud) {
        firstInterfaceFlags |= ADV_PATH_FLAG_FIRST_HIT_CLOUD;
    }
    bool isFirstHitDynamic = !isChunkGeometryBufferIndex(surface.geometryBufferIndex);
    if (isFirstHitDynamic) { firstInterfaceFlags |= ADV_PATH_FLAG_FIRST_HIT_DYNAMIC; }
    if (surface.isHand) { firstInterfaceFlags |= ADV_PATH_FLAG_FIRST_HIT_HAND; }
    bool useFirstHitPrimitiveHash = isFirstHitDynamic && !surface.isHand;
    firstInterfaceSurfaceHash = makePathSurfaceHash(
        uvec3(surface.instanceIndex, surface.geometryBufferIndex, surface.primitiveId), useFirstHitPrimitiveHash);

    bool isTemporalCandidateValid = !surface.hasParallax && isPrimaryHitFinite(temporalDepth) && temporalDepth >= 0.0 &&
                                    temporalDepth < ADV_PRIMARY_TEMPORAL_INVALID_DEPTH &&
                                    isPrimaryHitFinite(temporalMotion);
    float firstHitDepth =
        isTemporalCandidateValid ? temporalDepth : -(worldUBO.cameraEffectedViewMat * vec4(surface.position, 1.0)).z;
    vec4 normalRoughness =
        vec4(normalize(surface.shadingNormal, surface.geometryNormal), clamp(surface.roughness, 0.0, 1.0));
    vec4 albedoMetallic = vec4(clamp(surface.albedo * clamp(surface.opacity, 0.0, 1.0), vec3(0.0), vec3(1.0)),
                               clamp(surface.metallic, 0.0, 1.0));
    vec2 firstInterfaceMotion = vec2(0.0);
    vec3 previousFirstPosition = surface.hasPreviousPosition ?
                                     surface.previousPosition :
                                     surface.position + vec3(worldUBO.cameraPos.xyz - lastWorldUBO.cameraPos.xyz);
    vec2 projectedFirstInterfaceMotion;
    float previousFirstDepth;
    bool hasPreviousFirstProjection =
        projectPreviousPosition(previousFirstPosition, vec2(checker.flatPixel) + 0.5 + worldUBO.cameraJitter,
                                vec2(flatExtent), projectedFirstInterfaceMotion, previousFirstDepth);
    if (hasPreviousFirstProjection) {
        firstInterfacePreviousDepth = clamp(previousFirstDepth, 0.0, ADV_PRIMARY_FP16_MAX);
    }
    if (isTemporalCandidateValid) {
        firstInterfaceMotion = temporalMotion;
    } else if (hasPreviousFirstProjection) {
        firstInterfaceMotion = projectedFirstInterfaceMotion;
    }
    float parallaxGuide = surface.hasParallax ? 0.25 : 0.0;
    storePrimaryGuides(checker.flatPixel, albedoMetallic, vec4(clamp(surface.f0, vec3(0.0), vec3(1.0)), parallaxGuide),
                       normalRoughness, isFinite(firstInterfaceMotion) ? firstInterfaceMotion : vec2(0.0),
                       clamp(firstHitDepth, 0.0, ADV_PRIMARY_FP16_MAX));
#if MCVR_USE_NRD_SEPARATE_DIRECT
    vec3 directLightGuideNormal = normalRoughness.xyz;
    float directLightGuideRoughness = normalRoughness.w;
    vec2 directLightGuideMotion = isFinite(firstInterfaceMotion) ? firstInterfaceMotion : vec2(0.0);
    float directLightGuideDepth = clamp(firstHitDepth, 0.0, ADV_PRIMARY_FP16_MAX);
    float directLightGuidePreviousDepth = firstInterfacePreviousDepth;
    bool directLightGuideValid = isFinite(directLightGuideNormal) && isFinite(directLightGuideMotion) &&
                                 isFinite(directLightGuideDepth) && isFinite(directLightGuidePreviousDepth) &&
                                 directLightGuideDepth < ADV_PRIMARY_FP16_MAX * 0.9 &&
                                 directLightGuidePreviousDepth < ADV_PRIMARY_FP16_MAX * 0.9;
    storePrimaryDirectGuide(checker.flatPixel, directLightGuideNormal, directLightGuideRoughness,
                            directLightGuideMotion, directLightGuideDepth, directLightGuidePreviousDepth, false,
                            directLightGuideValid);
#endif
}

pathLength += surface.rayDistance;
#if MCVR_USE_NRD_SEPARATE_DIRECT
directLightGuideApparentPathLength += surface.rayDistance * directLightGuideReferenceIor / max(float(currentIor), 1e-5);
#endif
f16vec3 mediumTransmission = f16vec3(1.0);
if (bounce != 0u && currentMedium != ADV_MEDIUM_GLASS) {
    mediumTransmission = f16vec3(segmentTransmittance(currentMedium, surface.rayDistance));
}
coneWidth += surface.rayDistance * coneSpread;
bounceCount = bounce;

if (pathLength >= float(max(worldUBO.renderDistanceBlocks, worldUBO.vistaDistanceBlocks)) && surface.medium != ADV_MEDIUM_CLOUD) {
    throughput *= mediumTransmission;
    terminalAction = ADV_MEDIA_ACTION_STOP;
    terminal = makePathTerminal(surface);
    ADV_PRIMARY_SEGMENT_STOP;
}

bool isPerfectMetal = surface.metallic == 1.0 && surface.roughness < 0.01;
if (surface.isWater || surface.medium == ADV_MEDIUM_GLASS) { hasPassedTransparent = true; }
uint hitMedium = surface.medium;
if (hitMedium == ADV_MEDIUM_GLASS && surface.opacity >= 1.0 - 1e-6) { hitMedium = ADV_MEDIUM_SOLID; }
uint nextMedium = hitMedium;
if (currentMedium == hitMedium) {
    nextMedium = ADV_MEDIUM_AIR;
} else if (hitMedium == ADV_MEDIUM_CLOUD && !surface.isFrontFace) {
    nextMedium = currentMedium;
}
bool nextGlassIsHand =
    nextMedium == ADV_MEDIUM_GLASS && (currentMedium == ADV_MEDIUM_GLASS ? currentGlassIsHand : surface.isHand);
float16_t nextIor = float16_t(mediumIor(nextMedium, surface.ior));
vec3 interfaceNormal = opticalInterfaceNormal(surface, rayDirection);
float cosIncident = clamp(dot(rayDirection, -interfaceNormal), 0.0, 1.0);
float criticalCos = cosCriticalAngle(float(currentIor), float(nextIor));
bool hasTotalInternalReflection = criticalCos >= 0.0 && cosIncident <= criticalCos;
float fresnel = interfaceFresnel(cosIncident, float(currentIor), float(nextIor));
if (ADV_PRIMARY_FIRST_SEGMENT && (surface.isWater || surface.medium == ADV_MEDIUM_GLASS)) {
    vec3 interfaceSpecularAlbedo =
        isPerfectMetal ? clamp(surface.f0, vec3(0.0), vec3(1.0)) : vec3(hasTotalInternalReflection ? 1.0 : fresnel);
    storePrimarySpecularGuide(checker.flatPixel, interfaceSpecularAlbedo);
}

uint action;
if (isPerfectMetal) {
    action = ADV_MEDIA_ACTION_REFLECT;
    throughput *= f16vec3(surface.f0);
} else {
    CheckerAction transition = checkerAction(currentMedium, nextMedium);
    bool actionEvenField = checker.isEvenField;
    bool checkerSplit =
        (transition.oddAction & ADV_MEDIA_ACTION_SPLIT) != 0u && (transition.evenAction & ADV_MEDIA_ACTION_SPLIT) != 0u;
    if (primaryUsesHalfRateIndirect() && splitBounce == 0u && checkerSplit) {
        actionEvenField =
            halfRateSplitActionEvenField(checker, flatExtent, ADV_PRIMARY_FIRST_SEGMENT && surface.isCloud);
    }
    action = selectAction(transition, actionEvenField, splitBounce != 0u, hasTotalInternalReflection);
}
bool shouldSplitAtCurrentSurface = (action & ADV_MEDIA_ACTION_SPLIT) != 0u;
if (shouldSplitAtCurrentSurface) {
    throughput *= f16vec3(2.0);
    splitBounce = bounce + 1u;
    action &= ~ADV_MEDIA_ACTION_SPLIT;
    coneSpread *= 2.0;
}
if ((action & ADV_MEDIA_ACTION_BLEND) != 0u) { action &= ~ADV_MEDIA_ACTION_BLEND; }
if (action == ADV_MEDIA_ACTION_INVBLEND) { action = ADV_MEDIA_ACTION_STOP; }

bool isFirstInterfaceReflection = ADV_PRIMARY_FIRST_SEGMENT &&
                                  (surface.isWater || surface.medium == ADV_MEDIUM_GLASS) &&
                                  action == ADV_MEDIA_ACTION_REFLECT;
if (isFirstInterfaceReflection) { firstInterfaceFlags |= ADV_PATH_FLAG_FIRST_INTERFACE_SPECULAR; }
if (action == ADV_MEDIA_ACTION_REFLECT && currentMedium != ADV_MEDIUM_GLASS && nextMedium == ADV_MEDIUM_GLASS &&
    (surface.roughness > 0.01 || surface.metallic < 1.0)) {
    action = ADV_MEDIA_ACTION_STOP;
}

bool shouldProvidePrimaryRefractionGuide = ADV_PRIMARY_FIRST_SEGMENT &&
                                           (action == ADV_MEDIA_ACTION_REFRACT || isFirstInterfaceReflection) &&
                                           surface.isWater && surface.roughness <= 0.2 && !hasTotalInternalReflection;
bool hasResolvedPrimaryRefraction = false;
vec3 primaryRefractionOrigin = surface.position;
vec3 primaryRefractionDirection = rayDirection;
if (shouldProvidePrimaryRefractionGuide &&
    resolvePrimaryRefractionBranch(
        surface, rayDirection, currentIor, nextIor, primaryRefractionOrigin, primaryRefractionDirection)) {
    hasResolvedPrimaryRefraction = true;
    uint reservedPrimarySegments = action == ADV_MEDIA_ACTION_REFLECT ? 1u : 0u;
    if (remainingPathRayBudget(rayBudgetUsed) > reservedPrimarySegments) {
        HitPayload refractionHit =
            findBudgetedSegmentHit(primaryRefractionOrigin, primaryRefractionDirection, coneWidth, coneSpread,
                                   nextMedium, nextGlassIsHand, reservedPrimarySegments, rayBudgetUsed);
        if (action == ADV_MEDIA_ACTION_REFRACT) {
            prefetchedRefractionHit = refractionHit;
            isPrefetchedRefractionHitReady = true;
        } else {
            Surface primaryTransmissionGuideSurface;
            if (isHitValid(refractionHit) &&
                decodeSurface(refractionHit, primaryRefractionOrigin, primaryRefractionDirection, false,
                              primaryTransmissionGuideSurface)) {
                storePrimaryTransmissionGuide(checker.flatPixel, vec4(surface.albedo, surface.metallic),
                                              surface.opacity, surface.isWater, nextMedium,
                                              primaryTransmissionGuideSurface);
            } else {
                imageStore(primaryDiffuseAlbedoImage, checker.flatPixel, vec4(0.0));
            }
        }
    }
}
terminalAction = action;

if (action == ADV_MEDIA_ACTION_REFLECT) {
    if (shouldSplitAtCurrentSurface || isFirstInterfaceReflection) {
        shouldCaptureTransparentSpecularHitDistance = true;
    }
    if (!isPerfectMetal) {
        if (currentMedium == ADV_MEDIUM_WATER && hitMedium == ADV_MEDIUM_WATER) {
            throughput *= f16vec3(0.85 + 4.0 * surface.roughness);
        }
        throughput *= f16vec3(fresnel);
    }
    throughput *= mediumTransmission;
    vec3 reflected =
        normalize(reflect(rayDirection, surface.shadingNormal), reflect(rayDirection, surface.geometryNormal));
    if (dot(reflected, surface.geometryNormal) <= 0.0) {
        reflected = normalize(reflect(rayDirection, surface.geometryNormal), -rayDirection);
    }
    rayDirection = reflected;
    vec3 branchPosition;
    vec3 branchNormal;
    bool isTransparentBranch = surface.transmission > EPS;
    if (!resolvePrimaryBranchOrigin(surface, rayDirection, isTransparentBranch, branchPosition, branchNormal)) {
        throughput = f16vec3(0.0);
        terminal = makePathTerminal(surface);
        ADV_PRIMARY_SEGMENT_STOP;
    }
    rayOrigin = surface.hasParallax ? offsetParallaxExit(branchPosition, branchNormal, rayDirection) :
                                      offsetRay(branchPosition, branchNormal, rayDirection);
    bounceCount = bounce + 1u;
    if (bounce == ADV_PATH_RAY_BUDGET || !hasPathRayBudget(rayBudgetUsed)) {
        terminal = makePathTerminal(surface);
        ADV_PRIMARY_SEGMENT_STOP;
    }
    ADV_PRIMARY_SEGMENT_CONTINUE;
}

if (action == ADV_MEDIA_ACTION_REFRACT) {
    vec3 refractionOrigin = primaryRefractionOrigin;
    vec3 refractionDirection = primaryRefractionDirection;
    bool isRefractionResolved =
        hasResolvedPrimaryRefraction || resolvePrimaryRefractionBranch(surface, rayDirection, currentIor, nextIor,
                                                                       refractionOrigin, refractionDirection);
    if (!isRefractionResolved) {
        throughput *= mediumTransmission;
        rayDirection = normalize(reflect(rayDirection, surface.geometryNormal), -rayDirection);
        vec3 branchPosition;
        vec3 branchNormal;
        resolvePrimaryBranchOrigin(surface, rayDirection, true, branchPosition, branchNormal);
        rayOrigin = surface.hasParallax ? offsetParallaxExit(branchPosition, branchNormal, rayDirection) :
                                          offsetRay(surface.position, surface.geometryNormal, rayDirection);
        terminalAction = ADV_MEDIA_ACTION_REFLECT;
        bounceCount = bounce + 1u;
        if (bounce == ADV_PATH_RAY_BUDGET || !hasPathRayBudget(rayBudgetUsed)) {
            terminal = makePathTerminal(surface);
            ADV_PRIMARY_SEGMENT_STOP;
        }
        ADV_PRIMARY_SEGMENT_CONTINUE;
    }
    throughput *= f16vec3(1.0 - fresnel) * mediumTransmission;
    rayDirection = refractionDirection;
    if (nextMedium == ADV_MEDIUM_GLASS || currentMedium == ADV_MEDIUM_GLASS) {
        throughput *= f16vec3(surface.transmissionColor);
    }
    rayOrigin = refractionOrigin;
    currentMedium = nextMedium;
    currentIor = nextIor;
    currentGlassIsHand = nextGlassIsHand;
    bounceCount = bounce + 1u;
    if (bounce == ADV_PATH_RAY_BUDGET || (!isPrefetchedRefractionHitReady && !hasPathRayBudget(rayBudgetUsed))) {
        terminal = makePathTerminal(surface);
        ADV_PRIMARY_SEGMENT_STOP;
    }
    ADV_PRIMARY_SEGMENT_CONTINUE;
}

if (action == ADV_MEDIA_ACTION_PASS) {
    throughput *= mediumTransmission;
    vec3 branchPosition;
    vec3 branchNormal;
    resolvePrimaryBranchOrigin(surface, rayDirection, true, branchPosition, branchNormal);
    if (surface.hasParallax) {
        rayOrigin = offsetParallaxExit(branchPosition, branchNormal, rayDirection);
    } else {
        float offsetSide = dot(rayDirection, surface.outwardGeometryNormal) >= 0.0 ? 1.0 : -1.0;
        rayOrigin = surface.position + surface.outwardGeometryNormal * (0.01 * offsetSide);
    }
    currentMedium = nextMedium;
    currentIor = nextIor;
    bounceCount = bounce + 1u;
    if (bounce == ADV_PATH_RAY_BUDGET || !hasPathRayBudget(rayBudgetUsed)) {
        terminal = makePathTerminal(surface);
        ADV_PRIMARY_SEGMENT_STOP;
    }
    ADV_PRIMARY_SEGMENT_CONTINUE;
}

throughput *= mediumTransmission;
terminal = makePathTerminal(surface);
ADV_PRIMARY_SEGMENT_STOP;
