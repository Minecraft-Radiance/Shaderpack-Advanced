#ifndef ADV_OUTPUT_DIRECT_GLSL
#define ADV_OUTPUT_DIRECT_GLSL

#include "output/resources.glsl"

vec4 loadOutputSpecularAlbedo(ivec2 pixel) {
    return imageLoad(outputSpecularAlbedoImage, pixel);
}

vec4 loadOutputNormalRoughness(ivec2 pixel) {
    return imageLoad(outputNormalRoughnessImage, pixel);
}

float loadOutputLinearDepth(ivec2 pixel) {
    return imageLoad(outputLinearDepthImage, pixel).x;
}

vec4 loadOutputBaseEmission(ivec2 pixel) {
    return imageLoad(outputBaseEmissionImage, pixel);
}

vec4 loadOutputDirectLightGuideNormalRoughness(ivec2 pixel) {
#if MCVR_USE_NRD_SEPARATE_DIRECT
    return imageLoad(directLightGuideNormalRoughnessImage, pixel);
#else
    return vec4(0.0);
#endif
}

vec4 loadOutputDirectLightGuideMotionDepth(ivec2 pixel) {
#if MCVR_USE_NRD_SEPARATE_DIRECT
    return imageLoad(directLightGuideMotionDepthImage, pixel);
#else
    return vec4(0.0);
#endif
}

void storeOutputSpecularAlbedo(ivec2 pixel, vec4 value) {
    imageStore(outputSpecularAlbedoImage, pixel, value);
}

float decodeDirectHitDistance(float rawDistance, out bool isDynamic) {
    isDynamic = isSignalFinite(rawDistance) && rawDistance < -1e-6;
    if (!isSignalFinite(rawDistance)) { return 0.0; }
    return clamp(abs(rawDistance), 0.0, ADV_SIGNAL_FP16_MAX);
}

#if MCVR_USE_NRD_SEPARATE_DIRECT
float encodeDirectHitDistance(float distance, bool isDynamic) {
    float safeDistance = clamp(abs(distance), 0.0, ADV_SIGNAL_FP16_MAX);
    return isDynamic && safeDistance > 1e-6 && safeDistance < ADV_SIGNAL_FP16_MAX ? -safeDistance : safeDistance;
}

bool isDirectGuideValid(vec4 normalRoughness, vec4 motionDepth) {
    return isSignalFinite(normalRoughness) && isSignalFinite(motionDepth) &&
           dot(normalRoughness.xyz, normalRoughness.xyz) > 1e-8 && motionDepth.z > 0.0 &&
           motionDepth.z < ADV_SIGNAL_FP16_MAX * 0.9 && motionDepth.w > 0.0 &&
           motionDepth.w < ADV_SIGNAL_FP16_MAX * 0.9;
}
#endif

struct SunLobes {
    bool isEligible;
    bool hasSample;
    bool isSplitReflection;
    bool hasDiffuseLobe;
    bool hasSpecularLobe;
    vec3 diffuse;
    vec3 specular;
    vec3 lightDirection;
    float hitDistance;
    bool isDynamic;
};

SunLobes emptySunLobes() {
    SunLobes result;
    result.isEligible = false;
    result.hasSample = false;
    result.isSplitReflection = false;
    result.hasDiffuseLobe = false;
    result.hasSpecularLobe = false;
    result.diffuse = vec3(0.0);
    result.specular = vec3(0.0);
    result.lightDirection = vec3(0.0, 1.0, 0.0);
    result.hitDistance = 0.0;
    result.isDynamic = false;
    return result;
}

vec3 sunDirectionInMedium(vec3 airDirection, uint medium) {
    return medium == ADV_MEDIUM_WATER ? underwaterDirectionToLight(airDirection) : airDirection;
}

SunLobes evaluateSunLobes(ResolvePath path, vec4 diffuseBrdfVisibility, vec4 specularBrdfVisibility) {
    SunLobes result = emptySunLobes();
    uint flags = pathFlags(path.key);
    bool isSky = isSkyPath(path.key);
    bool isFirstInterfaceReflection = (flags & ADV_PATH_FLAG_FIRST_INTERFACE_SPECULAR) != 0u;
    bool hasTerminalSurface = (flags & ADV_PATH_FLAG_TERMINAL_SURFACE) != 0u;
    result.isSplitReflection = isFirstInterfaceReflection && isSplitPath(path.key);
    result.isEligible = isPathValid(path.key) && !isSky && hasTerminalSurface &&
                        (flags & (ADV_PATH_FLAG_NO_REFLECT | ADV_PATH_FLAG_PORTAL)) == 0u;
    if (!result.isEligible || !isSignalFinite(diffuseBrdfVisibility) || !isSignalFinite(specularBrdfVisibility)) {
        return result;
    }

    vec3 lightDirection;
    vec3 lightRadiance;
    float lightScale;
    getCelestialPrimaryDirectLight(lightDirection, lightRadiance, lightScale);
    uint terminalMedium = pathTerminalMedium(path.key);
    vec3 terminalLightDirection = sunDirectionInMedium(lightDirection, terminalMedium);
    result.lightDirection = terminalLightDirection;
    if (worldUBO.skyType != 1u || lightScale <= 1e-6) { return result; }

    vec3 unshadowedLight = signalSanitizeRadiance(lightRadiance);
    unshadowedLight *= cloudLightVisibility(path.position + vec3(worldUBO.cameraPos.xyz), lightDirection,
                                            max(ADV_CLOUD_LIGHT_STEPS, 1), 0.175);
    bool dynamicBlocker;
    float blockerDistance = decodeDirectHitDistance(specularBrdfVisibility.w, dynamicBlocker);
    result.hasSample = blockerDistance > 1e-6;
    result.hitDistance = result.hasSample ? blockerDistance : 0.0;
    const uint temporallyUnstableMask = ADV_PATH_FLAG_DYNAMIC | ADV_PATH_FLAG_FIRST_HIT_DYNAMIC;
    result.isDynamic = result.hasSample && (dynamicBlocker || (flags & temporallyUnstableMask) != 0u);
    if (!result.hasSample) { return result; }
    result.hasDiffuseLobe = !isFirstInterfaceReflection;
    result.hasSpecularLobe = true;

    vec3 throughput = signalSanitizeRadiance(path.throughput);
    vec3 surfaceDiffuseAlbedo = diffuseAlbedo(path.albedo, path.metallic) * clamp(path.opacity, 0.0, 1.0);
    vec3 diffuseContribution =
        signalSanitizeRadiance(diffuseBrdfVisibility.rgb * unshadowedLight * surfaceDiffuseAlbedo * throughput);
    vec3 specularContribution = signalSanitizeRadiance(specularBrdfVisibility.rgb * unshadowedLight * throughput);
    if (isFirstInterfaceReflection) {
        result.specular = signalSanitizeRadiance(diffuseContribution + specularContribution);
    } else {
        result.diffuse = diffuseContribution;
        result.specular = specularContribution;
    }
    return result;
}

struct ResolvedSunLobes {
    bool hasReflectionSample;
    bool hasDirectSample;
    bool hasDirectDiffuseLobe;
    bool hasDirectSpecularLobe;
    vec3 reflectionSpecular;
    vec4 reflectionDirectionMoment;
    vec3 directDiffuse;
    vec3 directSpecular;
    vec3 directLightDirection;
    float hitDistance;
    bool isDynamic;
};

ResolvedSunLobes emptyResolvedSunLobes() {
    ResolvedSunLobes result;
    result.hasReflectionSample = false;
    result.hasDirectSample = false;
    result.hasDirectDiffuseLobe = false;
    result.hasDirectSpecularLobe = false;
    result.reflectionSpecular = vec3(0.0);
    result.reflectionDirectionMoment = vec4(0.0);
    result.directDiffuse = vec3(0.0);
    result.directSpecular = vec3(0.0);
    result.directLightDirection = vec3(0.0, 1.0, 0.0);
    result.hitDistance = 0.0;
    result.isDynamic = false;
    return result;
}

void accumulateSunBranch(inout ResolvedSunLobes result, SunLobes branch, float branchWeight) {
    if (!branch.isEligible || !branch.hasSample) { return; }

    float weight = clamp(branchWeight, 0.0, 1.0);
    if (branch.isSplitReflection) {
        vec3 contribution = signalSanitizeRadiance(branch.specular * weight);
        result.hasReflectionSample = true;
        result.reflectionSpecular = signalSanitizeRadiance(result.reflectionSpecular + contribution);
        float directionWeight = min(signalLuminance(contribution), ADV_SIGNAL_FP16_MAX);
        result.reflectionDirectionMoment +=
            vec4(signalNormalize(branch.lightDirection, vec3(0.0)) * directionWeight, directionWeight);
        return;
    }

    bool shouldReplaceShadow = !result.hasDirectSample || branch.hitDistance < result.hitDistance;
    result.hasDirectSample = true;
    result.hasDirectDiffuseLobe = result.hasDirectDiffuseLobe || branch.hasDiffuseLobe;
    result.hasDirectSpecularLobe = result.hasDirectSpecularLobe || branch.hasSpecularLobe;
    result.directDiffuse = signalSanitizeRadiance(result.directDiffuse + branch.diffuse * weight);
    result.directSpecular = signalSanitizeRadiance(result.directSpecular + branch.specular * weight);
    result.isDynamic = result.isDynamic || branch.isDynamic;
    if (shouldReplaceShadow) {
        result.directLightDirection = branch.lightDirection;
        result.hitDistance = branch.hitDistance;
    }
}

bool areSplitPathsCompatible(ResolvePath current, ResolvePath paired, ivec2 currentFlatPixel, ivec2 pairedFlatPixel) {
    if (!isPathValid(paired.key) || !isSplitPath(current.key) || !isSplitPath(paired.key) ||
        pathSplitBounce(current.key) != pathSplitBounce(paired.key)) {
        return false;
    }

    uint currentFlags = pathFlags(current.key);
    uint pairedFlags = pathFlags(paired.key);
    uint currentSurfaceHash = pathSurfaceHash(current.key);
    uint pairedSurfaceHash = pathSurfaceHash(paired.key);
    if (currentSurfaceHash == 0u || currentSurfaceHash != pairedSurfaceHash) { return false; }
    const uint firstInterfaceMask =
        ADV_PATH_FLAG_FIRST_HIT_WATER | ADV_PATH_FLAG_FIRST_HIT_GLASS | ADV_PATH_FLAG_FIRST_HIT_CLOUD;
    if ((currentFlags & firstInterfaceMask) != (pairedFlags & firstInterfaceMask) ||
        ((currentFlags ^ pairedFlags) & (ADV_PATH_FLAG_FIRST_HIT_DYNAMIC | ADV_PATH_FLAG_FIRST_HIT_HAND)) != 0u) {
        return false;
    }

    bool isFirstTransparentSplit =
        pathSplitBounce(current.key) == 1u &&
        (currentFlags & (ADV_PATH_FLAG_FIRST_HIT_WATER | ADV_PATH_FLAG_FIRST_HIT_GLASS)) != 0u;
    bool currentIsReflection = (currentFlags & ADV_PATH_FLAG_FIRST_INTERFACE_SPECULAR) != 0u;
    bool pairedIsReflection = (pairedFlags & ADV_PATH_FLAG_FIRST_INTERFACE_SPECULAR) != 0u;
    if (isFirstTransparentSplit && currentIsReflection == pairedIsReflection) { return false; }

    vec4 currentNormalRoughness = loadOutputNormalRoughness(currentFlatPixel);
    vec4 pairedNormalRoughness = loadOutputNormalRoughness(pairedFlatPixel);
    float currentDepth = loadOutputLinearDepth(currentFlatPixel);
    float pairedDepth = loadOutputLinearDepth(pairedFlatPixel);
    if (!isSignalFinite(currentNormalRoughness) || !isSignalFinite(pairedNormalRoughness) ||
        !isSignalFinite(currentDepth) || !isSignalFinite(pairedDepth) || currentDepth <= 0.0 || pairedDepth <= 0.0) {
        return false;
    }

    vec3 currentNormal = signalNormalize(currentNormalRoughness.xyz, vec3(0.0));
    vec3 pairedNormal = signalNormalize(pairedNormalRoughness.xyz, vec3(0.0));
    float minimumDepth = min(currentDepth, pairedDepth);
    float depthTolerance = 0.05 + minimumDepth * 0.02;
    return dot(currentNormal, pairedNormal) >= 0.8 && abs(currentDepth - pairedDepth) <= depthTolerance;
}

bool loadPairedSunLobes(ResolvePath current,
                        CheckerCoordinate currentChecker,
                        ivec2 candidateFlatPixel,
                        ivec2 flatExtent,
                        out SunLobes pairedCelestial,
                        out ivec2 pairedFlatPixel) {
    pairedCelestial = emptySunLobes();
    pairedFlatPixel = currentChecker.flatPixel;
    if (any(lessThan(candidateFlatPixel, ivec2(0))) || any(greaterThanEqual(candidateFlatPixel, flatExtent))) {
        return false;
    }

    CheckerCoordinate candidateChecker = flatToChecker(candidateFlatPixel, flatExtent);
    if (!candidateChecker.isValid || candidateChecker.isEvenField == currentChecker.isEvenField) { return false; }

    ResolvePath paired = loadResolvePath(candidateChecker.packedPixel);
    if (!areSplitPathsCompatible(current, paired, currentChecker.flatPixel, candidateChecker.flatPixel)) {
        return false;
    }

    pairedCelestial = evaluateSunLobes(
        paired, imageLoad(sunBrdfDistanceImage, ivec3(candidateChecker.packedPixel, ADV_SUN_DIFFUSE_LAYER)),
        imageLoad(sunBrdfDistanceImage, ivec3(candidateChecker.packedPixel, ADV_SUN_SPECULAR_LAYER)));
    pairedFlatPixel = candidateChecker.flatPixel;
    return true;
}

ResolvedSunLobes
resolveSunLobes(SunLobes current, SunLobes paired, bool hasCompatiblePair, bool normalizeSingleBranch) {
    ResolvedSunLobes result = emptyResolvedSunLobes();
    float branchWeight = hasCompatiblePair || normalizeSingleBranch ? 0.5 : 1.0;
    accumulateSunBranch(result, current, branchWeight);
    if (hasCompatiblePair) { accumulateSunBranch(result, paired, branchWeight); }
    return result;
}

#endif
