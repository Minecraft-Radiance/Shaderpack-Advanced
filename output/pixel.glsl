#ifndef ADV_OUTPUT_PIXEL_GLSL
#define ADV_OUTPUT_PIXEL_GLSL

#include "output/direct.glsl"
#include "output/environment.glsl"

struct PixelSignals {
    RawRadiance indirectRaw;
    vec4 diffuseDirection;
    vec4 specularDirection;
    float diffuseHitDistance;
    float specularHitDistance;
    vec4 clearOutput;
    vec4 baseEmission;
#if MCVR_USE_NRD
    vec3 cloudSpecularCarrier;
#endif
#if MCVR_USE_NRD_SEPARATE_DIRECT
    RawRadiance directRaw;
    float directHitDistance;
#endif
};

PixelSignals emptyPixelSignals() {
    PixelSignals result;
    result.indirectRaw.diffuse = vec4(0.0);
    result.indirectRaw.specular = vec4(0.0);
    result.diffuseDirection = vec4(0.0);
    result.specularDirection = vec4(0.0);
    result.diffuseHitDistance = 0.0;
    result.specularHitDistance = 0.0;
    result.clearOutput = vec4(0.0);
    result.baseEmission = vec4(0.0);

#if MCVR_USE_NRD
    result.cloudSpecularCarrier = vec3(0.0);
#endif
#if MCVR_USE_NRD_SEPARATE_DIRECT
    result.directRaw.diffuse = vec4(0.0);
    result.directRaw.specular = vec4(0.0);
    result.directHitDistance = 0.0;
#endif
    return result;
}

void storePixelSignals(ivec2 pixel, PixelSignals result) {
    imageStore(outputIndirectDiffuseRadianceImage, pixel, result.indirectRaw.diffuse);
    imageStore(outputIndirectSpecularRadianceImage, pixel, result.indirectRaw.specular);
    imageStore(outputIndirectDiffuseHitDistanceImage, pixel, vec4(result.diffuseHitDistance));
    imageStore(outputIndirectSpecularHitDistanceImage, pixel, vec4(result.specularHitDistance));
    imageStore(outputIndirectDiffuseDirectionImage, pixel, result.diffuseDirection);
    imageStore(outputIndirectSpecularDirectionImage, pixel, result.specularDirection);
    imageStore(outputClearImage, pixel, result.clearOutput);
    imageStore(outputBaseEmissionImage, pixel, result.baseEmission);
#if MCVR_USE_NRD_SEPARATE_DIRECT
    storeDirectRawRadiance(pixel, result.directRaw);
    imageStore(outputDirectDiffuseRadianceImage, pixel, result.directRaw.diffuse);
    imageStore(outputDirectSpecularRadianceImage, pixel, result.directRaw.specular);
    imageStore(directHitDistanceImage, pixel, vec4(result.directHitDistance));
#endif
}

void clearPixelSignals(ivec2 pixel) {
    storePixelSignals(pixel, emptyPixelSignals());
    imageStore(outputNormalRoughnessImage, pixel, vec4(0.0, 1.0, 0.0, 1.0));
#if MCVR_USE_NRD
    vec4 specularGuide = loadOutputSpecularAlbedo(pixel);
    imageStore(outputSpecularAlbedoImage, pixel, vec4(specularGuide.rgb, 0.0));
#endif
    imageStore(outputRefractionImage, pixel, vec4(0.0));
    imageStore(outputFogImage, pixel, vec4(0.0, 0.0, 0.0, -1.0));
#if MCVR_USE_NRD_SEPARATE_DIRECT
    imageStore(directLightGuideNormalRoughnessImage, pixel, vec4(0.0));
    imageStore(directLightGuideMotionDepthImage, pixel, vec4(0.0));
#endif
    imageStore(outputSegmentationImage, pixel, uvec4(ADV_SIGNAL_SEGMENTATION_SKIP, 0u, 0u, 0u));
    imageStore(starCloudTransmittanceImage, pixel, vec4(0.0));
}

#if MCVR_USE_NRD
bool isCloudSplitPath(PathKey key) {
    uint flags = pathFlags(key);
    return isPathValid(key) && isSplitPath(key) && (flags & ADV_PATH_FLAG_FIRST_HIT_CLOUD) != 0u;
}

bool isCloudPairCompatible(PathKey first, PathKey second) {
    if (!isCloudSplitPath(first) || !isCloudSplitPath(second) || pathSplitBounce(first) != pathSplitBounce(second) ||
        isSkyPath(first) == isSkyPath(second)) {
        return false;
    }
    uint surfaceFlags = isSkyPath(first) ? pathFlags(second) : pathFlags(first);
    return (surfaceFlags & (ADV_PATH_FLAG_CLOUD | ADV_PATH_FLAG_TERMINAL_SURFACE)) ==
           (ADV_PATH_FLAG_CLOUD | ADV_PATH_FLAG_TERMINAL_SURFACE);
}

shared vec3 cloudSpecularTile[64];
#endif

PixelSignals resolvePixel(CheckerCoordinate checker, ivec2 flatExtent, ResolvePath primary) {
    PixelSignals result = emptyPixelSignals();
    ivec2 packedPixel = checker.packedPixel;

    uint flags = pathFlags(primary.key);
    bool isFirstTransparentSplit = isSplitPath(primary.key) && pathSplitBounce(primary.key) == 1u &&
                                   (flags & (ADV_PATH_FLAG_FIRST_HIT_WATER | ADV_PATH_FLAG_FIRST_HIT_GLASS)) != 0u;
#if MCVR_USE_NRD
    bool routeCloudToSpecular = isCloudSplitPath(primary.key);
    vec4 specularGuide = loadOutputSpecularAlbedo(checker.flatPixel);
    storeOutputSpecularAlbedo(checker.flatPixel,
                              vec4(specularGuide.rgb, isFirstTransparentSplit || routeCloudToSpecular ? 1.0 : specularGuide.a));
#else
    const bool routeCloudToSpecular = false;
#endif
    bool isSky = isSkyPath(primary.key);
    bool isVanillaCloudTransmission = isSky && (flags & ADV_PATH_FLAG_FIRST_HIT_CLOUD) != 0u;
    bool isFirstInterfaceReflection = (flags & ADV_PATH_FLAG_FIRST_INTERFACE_SPECULAR) != 0u;
    bool isFirstInterfaceTransmission = isFirstTransparentSplit && !isFirstInterfaceReflection;
    bool hasTerminalSurface = (flags & ADV_PATH_FLAG_TERMINAL_SURFACE) != 0u;
    bool shouldShadeSurface =
        hasTerminalSurface && !isSky && (flags & (ADV_PATH_FLAG_NO_REFLECT | ADV_PATH_FLAG_PORTAL)) == 0u;
    bool useSplitCarrier = indirectUsesSplitCarrier(primary.key);
    uint splitCarrierLobe = useSplitCarrier ? indirectSplitCarrierLobe(checker.flatPixel, primary.key) : 0u;
    bool routeBranchDiffuseToSpecular = indirectRoutesDiffuseToSpecular(checker.flatPixel, primary.key);
    bool routeBranchSpecularToDiffuse = indirectRoutesSpecularToDiffuse(checker.flatPixel, primary.key);
    bool useFullRateLobes = indirectUsesFullRateLobes(primary.key);
    bool hasDiffuseCheckerSample = false;
    bool hasSpecularCheckerSample = false;
    float splitBranchWeight = indirectSplitBranchWeight(primary.key);
    f16vec3 throughput = f16vec3(signalSanitizeRadiance(primary.throughput) * splitBranchWeight);
    f16vec3 diffuseSum = f16vec3(0.0);
    f16vec3 specularSum = f16vec3(0.0);
#if MCVR_USE_NRD_SEPARATE_DIRECT
    f16vec3 directDiffuseSum = f16vec3(0.0);
    f16vec3 directSpecularSum = f16vec3(0.0);
#endif
    f16vec4 diffuseMoment = f16vec4(0.0);
    f16vec4 specularMoment = f16vec4(0.0);
#if MCVR_USE_NRD_SEPARATE_DIRECT
    bool hasCelestialDirectSample = false;
    bool hasDirectDiffuseSample = false;
    bool hasDirectSpecularSample = false;
    float celestialHitDistance = 0.0;
    bool celestialDynamicBlocker = false;
    bool usePairedCelestialDirectGuide = false;
    ivec2 pairedCelestialDirectGuidePixel = checker.flatPixel;
#endif

    IndirectSignals indirect = loadIndirectSignals(checker, primary);
    if (shouldShadeSurface) {
        RawRadiance checkerLobes = indirect.radiance;
        hasDiffuseCheckerSample = checkerLobes.diffuse.a > 0.0 && isSignalFinite(checkerLobes.diffuse);
        hasSpecularCheckerSample = checkerLobes.specular.a > 0.0 && isSignalFinite(checkerLobes.specular);
        if (hasDiffuseCheckerSample) {
            vec3 contribution = signalSanitizeRadiance(checkerLobes.diffuse.rgb);
            if (routeBranchDiffuseToSpecular) {
                accumulateRadiance(specularSum, contribution);
                accumulateDirectionMoment(specularMoment, signalDirectionFromMoment(indirect.diffuseDirection),
                                          contribution);
            } else {
                accumulateRadiance(diffuseSum, contribution);
                accumulateDirectionMoment(diffuseMoment, signalDirectionFromMoment(indirect.diffuseDirection),
                                          contribution);
            }
        }
        if (hasSpecularCheckerSample) {
            vec3 contribution = signalSanitizeRadiance(checkerLobes.specular.rgb);
            vec3 direction = signalDirectionFromMoment(indirect.specularDirection);
            if (routeBranchSpecularToDiffuse) {
                accumulateRadiance(diffuseSum, contribution);
                accumulateDirectionMoment(diffuseMoment, direction, contribution);
            } else {
                accumulateRadiance(specularSum, contribution);
                accumulateDirectionMoment(specularMoment, direction, contribution);
            }
        }
        {
            vec4 contribution = imageLoad(restirDiffuseRadianceImage, checker.flatPixel);
            if (contribution.a > 0.0 && isSignalFinite(contribution)) {
                vec3 radiance = signalSanitizeRadiance(contribution.rgb * splitBranchWeight);
                vec3 direction =
                    signalDirectionFromMoment(imageLoad(restirDiffuseDirectionMomentImage, checker.flatPixel));
                if (routeBranchDiffuseToSpecular) {
                    accumulateRadiance(specularSum, radiance);
                    accumulateDirectionMoment(specularMoment, direction, radiance);
                } else {
                    accumulateRadiance(diffuseSum, radiance);
                    accumulateDirectionMoment(diffuseMoment, direction, radiance);
                }
            }
        }
    }

    {
        SunLobes currentCelestial =
            evaluateSunLobes(primary, imageLoad(sunBrdfDistanceImage, ivec3(packedPixel, ADV_SUN_DIFFUSE_LAYER)),
                             imageLoad(sunBrdfDistanceImage, ivec3(packedPixel, ADV_SUN_SPECULAR_LAYER)));
        SunLobes pairedCelestial = emptySunLobes();
        bool hasCompatiblePair = false;
        ivec2 pairedFlatPixel = checker.flatPixel;
        if (isSplitPath(primary.key)) {
            hasCompatiblePair =
                loadPairedSunLobes(primary, checker, ivec2(checker.flatPixel.x ^ 1, checker.flatPixel.y), flatExtent,
                                   pairedCelestial, pairedFlatPixel);
        }

#if MCVR_USE_NRD_SEPARATE_DIRECT
        bool currentProvidesDirect =
            currentCelestial.isEligible && currentCelestial.hasSample && !currentCelestial.isSplitReflection;
        bool pairedProvidesDirect = hasCompatiblePair && pairedCelestial.isEligible && pairedCelestial.hasSample &&
                                    !pairedCelestial.isSplitReflection;
        usePairedCelestialDirectGuide = !currentProvidesDirect && pairedProvidesDirect;
        if (usePairedCelestialDirectGuide) { pairedCelestialDirectGuidePixel = pairedFlatPixel; }
#endif

        ResolvedSunLobes celestial =
            resolveSunLobes(currentCelestial, pairedCelestial, hasCompatiblePair, useSplitCarrier);

        if (celestial.hasReflectionSample && (!useSplitCarrier || splitCarrierLobe == 1u)) {
            accumulateRadiance(specularSum, celestial.reflectionSpecular);
            accumulateDirectionMoment(specularMoment, signalDirectionFromMoment(celestial.reflectionDirectionMoment),
                                      celestial.reflectionSpecular);
        }
#if MCVR_USE_NRD_SEPARATE_DIRECT
        hasCelestialDirectSample = celestial.hasDirectSample;
        if (celestial.hasDirectSample) {
            accumulateRadiance(directDiffuseSum, celestial.directDiffuse);
            accumulateRadiance(directSpecularSum, celestial.directSpecular);
            hasDirectDiffuseSample = hasDirectDiffuseSample || celestial.hasDirectDiffuseLobe;
            hasDirectSpecularSample = hasDirectSpecularSample || celestial.hasDirectSpecularLobe;
            celestialHitDistance = celestial.hitDistance;
            celestialDynamicBlocker = celestial.isDynamic;
        }
#else
        if (celestial.hasDirectSample) {
            if (useSplitCarrier) {
                if (splitCarrierLobe == 0u) {
                    accumulateRadiance(diffuseSum, celestial.directDiffuse);
                    accumulateDirectionMoment(diffuseMoment, celestial.directLightDirection, celestial.directDiffuse);
                } else {
                    accumulateRadiance(specularSum, celestial.directSpecular);
                    accumulateDirectionMoment(specularMoment, celestial.directLightDirection, celestial.directSpecular);
                }
            } else {
                accumulateRadiance(diffuseSum, celestial.directDiffuse);
                accumulateDirectionMoment(diffuseMoment, celestial.directLightDirection, celestial.directDiffuse);
            }
            if (!useSplitCarrier) {
                accumulateRadiance(specularSum, celestial.directSpecular);
                accumulateDirectionMoment(specularMoment, celestial.directLightDirection, celestial.directSpecular);
            }
        }
#endif
    }

    vec4 refraction = imageLoad(transmissionRadianceImage, packedPixel);
    bool isRefractionValid = refraction.a > 0.0 && isSignalFinite(refraction);
    bool isRefractionEnvironment = isRefractionValid && primary.transparentSpecularHitDistance < 0.0;
    if (isRefractionValid) {
        vec3 contribution = signalSanitizeRadiance(refraction.rgb * vec3(throughput));
        if (routeBranchSpecularToDiffuse) {
            accumulateRadiance(diffuseSum, contribution);
            accumulateDirectionMoment(diffuseMoment, -primary.rayDirection, contribution);
        } else {
            accumulateRadiance(specularSum, contribution);
            accumulateDirectionMoment(specularMoment, -primary.rayDirection, contribution);
        }
    }

    vec4 rawEmission = loadOutputBaseEmission(checker.flatPixel);
    vec3 emission = hasTerminalSurface && !isSky && rawEmission.a > 0.0 && isSignalFinite(rawEmission) ?
                        signalSanitizeRadiance(rawEmission.rgb * vec3(throughput)) :
                        vec3(0.0);
    float cloudTransmittance = 1.0;
    vec3 clearRadiance =
        isSky ? signalSanitizeRadiance(sampleResolvedSky(primary, cloudTransmittance) * vec3(throughput)) : vec3(0.0);
    if (useSplitCarrier && isSky) {
        if (splitCarrierLobe == 0u) {
            accumulateRadiance(diffuseSum, clearRadiance);
            accumulateDirectionMoment(diffuseMoment, -primary.rayDirection, clearRadiance);
        } else {
            accumulateRadiance(specularSum, clearRadiance);
            accumulateDirectionMoment(specularMoment, -primary.rayDirection, clearRadiance);
        }
        clearRadiance = vec3(0.0);
    } else if (isVanillaCloudTransmission) {
        accumulateRadiance(diffuseSum, clearRadiance);
        accumulateDirectionMoment(diffuseMoment, -primary.rayDirection, clearRadiance);
        clearRadiance = vec3(0.0);
    }
    if (isFirstInterfaceReflection && isSky) {
        accumulateRadiance(specularSum, clearRadiance);
        accumulateDirectionMoment(specularMoment, -primary.rayDirection, clearRadiance);
        clearRadiance = vec3(0.0);
    }
    if (useSplitCarrier && signalLuminance(emission) > 1e-8) {
        if (splitCarrierLobe == 0u) {
            accumulateRadiance(diffuseSum, emission);
            accumulateDirectionMoment(diffuseMoment, -primary.rayDirection, emission);
        } else {
            accumulateRadiance(specularSum, emission);
            accumulateDirectionMoment(specularMoment, -primary.rayDirection, emission);
        }
        emission = vec3(0.0);
    }

    vec3 fogInscatter;
    vec3 fogTransmittance;
    bool isScalarFogCompatible;
    vec3 transmittedFogInscatter = vec3(0.0);
    vec3 transmittedFogTransmittance = vec3(1.0);
    vec3 cameraOrigin;
    vec3 cameraDirection;
    buildVirtualCameraRay(checker.flatPixel, flatExtent, worldUBO.cameraProjMatInv, worldUBO.cameraEffectedViewMatInv,
                          worldUBO.cameraJitter, cameraOrigin, cameraDirection);
    float firstHitDepth = imageLoad(outputFirstHitDepthImage, checker.flatPixel).x;
    bool shouldUseDimensionFog =
        !isCameraUnderwater(skyUBO.cameraSubmersionType) && (worldUBO.skyType == 0u || worldUBO.skyType == 2u);
    if (shouldUseDimensionFog) {
        sampleDimensionFog(firstHitDepth, cameraDirection, fogInscatter, fogTransmittance, isScalarFogCompatible);
    } else {
        float firstInterfaceDistance = volumePrimaryRayDistance(firstHitDepth, cameraDirection);
        sampleIntegratedVolume(checker.flatPixel, flatExtent, firstInterfaceDistance, firstInterfaceDistance,
                               cameraDirection, fogInscatter, fogTransmittance, isScalarFogCompatible);
        if (volumeAllowsTransparentIndirect(flags) && isFirstInterfaceTransmission &&
            isSignalFinite(primary.pathLength) && primary.pathLength > firstInterfaceDistance + 1e-4) {
            vec3 terminalFogInscatter;
            vec3 terminalFogTransmittance;
            bool unusedScalarCompatibility;
            float terminalAirDistance = (flags & ADV_VOLUME_PATH_FIRST_HIT_WATER_BIT) != 0u ?
                                            firstInterfaceDistance : primary.pathLength;
            sampleIntegratedVolume(checker.flatPixel, flatExtent, primary.pathLength, terminalAirDistance,
                                   cameraDirection, terminalFogInscatter, terminalFogTransmittance,
                                   unusedScalarCompatibility);
            resolveVolumeSegment(fogInscatter, fogTransmittance, terminalFogInscatter, terminalFogTransmittance,
                                 transmittedFogInscatter, transmittedFogTransmittance);
        }
    }

    vec3 diffuse = signalSanitizeRadiance(vec3(diffuseSum) * transmittedFogTransmittance);
    vec3 specular = signalSanitizeRadiance(vec3(specularSum) * transmittedFogTransmittance);
#if MCVR_USE_NRD_SEPARATE_DIRECT
    vec3 directDiffuse = signalSanitizeRadiance(vec3(directDiffuseSum) * transmittedFogTransmittance);
    vec3 directSpecular = signalSanitizeRadiance(vec3(directSpecularSum) * transmittedFogTransmittance);
#endif
    emission = signalSanitizeRadiance(emission * transmittedFogTransmittance);
    clearRadiance = signalSanitizeRadiance(clearRadiance * transmittedFogTransmittance);

    vec3 transmittedFogContribution =
        signalSanitizeRadiance(transmittedFogInscatter * signalSanitizeRadiance(vec3(throughput)));
    bool carryTransmittedFogInClear =
        isSky && !useSplitCarrier && !isVanillaCloudTransmission && !isFirstInterfaceReflection;
    if (carryTransmittedFogInClear) {
        clearRadiance = signalSanitizeRadiance(clearRadiance + transmittedFogContribution);
    } else if (useSplitCarrier && splitCarrierLobe == 0u) {
        diffuse = signalSanitizeRadiance(diffuse + transmittedFogContribution);
        accumulateDirectionMoment(diffuseMoment, -primary.rayDirection, transmittedFogContribution);
    } else {
        specular = signalSanitizeRadiance(specular + transmittedFogContribution);
        accumulateDirectionMoment(specularMoment, -primary.rayDirection, transmittedFogContribution);
    }

    diffuse = signalSanitizeRadiance(diffuse * fogTransmittance);
    specular = signalSanitizeRadiance(specular * fogTransmittance);
#if MCVR_USE_NRD_SEPARATE_DIRECT
    directDiffuse = signalSanitizeRadiance(directDiffuse * fogTransmittance);
    directSpecular = signalSanitizeRadiance(directSpecular * fogTransmittance);
#endif
    emission = signalSanitizeRadiance(emission * fogTransmittance);
    clearRadiance = signalSanitizeRadiance(clearRadiance * fogTransmittance);

    float scalarFog = clamp((fogTransmittance.r + fogTransmittance.g + fogTransmittance.b) / 3.0, 0.0, 1.0);
    bool shouldExtractScalarFog = isScalarFogCompatible && scalarFog > 1e-4;
    float fogComposeTransmittance = shouldExtractScalarFog ? scalarFog : 1.0;
    if (shouldExtractScalarFog) {
        float inverseFog = 1.0 / scalarFog;
        diffuse = signalSanitizeRadiance(diffuse * inverseFog);
        specular = signalSanitizeRadiance(specular * inverseFog);
#if MCVR_USE_NRD_SEPARATE_DIRECT
        directDiffuse = signalSanitizeRadiance(directDiffuse * inverseFog);
        directSpecular = signalSanitizeRadiance(directSpecular * inverseFog);
#endif
        emission = signalSanitizeRadiance(emission * inverseFog);
        clearRadiance = signalSanitizeRadiance(clearRadiance * inverseFog);
    }

#if MCVR_USE_NRD_SEPARATE_DIRECT
    if (usePairedCelestialDirectGuide) {
        vec4 pairedNormalRoughness = loadOutputDirectLightGuideNormalRoughness(pairedCelestialDirectGuidePixel);
        vec4 pairedMotionDepth = loadOutputDirectLightGuideMotionDepth(pairedCelestialDirectGuidePixel);
        if (isDirectGuideValid(pairedNormalRoughness, pairedMotionDepth)) {
            imageStore(directLightGuideNormalRoughnessImage, checker.flatPixel, pairedNormalRoughness);
            imageStore(directLightGuideMotionDepthImage, checker.flatPixel, pairedMotionDepth);
        }
    }
    float directHitDistance = hasCelestialDirectSample ? celestialHitDistance : 0.0;
    bool directDynamicBlocker = hasCelestialDirectSample && celestialDynamicBlocker;
    if (!routeCloudToSpecular) {
        result.directHitDistance = encodeDirectHitDistance(directHitDistance, directDynamicBlocker);
        result.directRaw.diffuse = vec4(directDiffuse, hasDirectDiffuseSample ? 1.0 : 0.0);
        result.directRaw.specular = vec4(directSpecular, hasDirectSpecularSample ? 1.0 : 0.0);
    }
#endif

#if MCVR_USE_NRD
    if (routeCloudToSpecular) {
        result.cloudSpecularCarrier = signalSanitizeRadiance(diffuse + specular + emission
#    if MCVR_USE_NRD_SEPARATE_DIRECT
                                                             + directDiffuse + directSpecular
#    endif
        );
        result.baseEmission.a = primary.previousPathDepth;
    } else
#endif
    {
        RawRadiance raw;
        bool hasDiffuseSignal = hasDiffuseCheckerSample || signalLuminance(diffuse) > 1e-8;
        bool hasSpecularSignal = hasSpecularCheckerSample || signalLuminance(specular) > 1e-8;
        if (useSplitCarrier) {
            bool hasCarrierSignal = splitCarrierLobe == 0u ? hasDiffuseSignal : hasSpecularSignal;
            hasCarrierSignal = hasCarrierSignal || isRefractionValid || isSky;
            raw.diffuse = splitCarrierLobe == 0u && hasCarrierSignal ? vec4(diffuse, 1.0) : vec4(0.0);
            raw.specular = splitCarrierLobe == 1u && hasCarrierSignal ? vec4(specular, 1.0) : vec4(0.0);
        } else {
            raw.diffuse =
                vec4(diffuse, hasDiffuseSignal && (shouldShadeSurface || isVanillaCloudTransmission) ? 1.0 : 0.0);
            raw.specular = vec4(specular, hasSpecularSignal && (shouldShadeSurface || isRefractionValid ||
                                                                (isFirstInterfaceReflection && isSky)) ?
                                              1.0 :
                                              0.0);
        }

        float diffuseHitDistance = signalSanitizeDepth(indirect.diffuseDistance, 0.0);
        float specularHitDistance = signalSanitizeDepth(indirect.specularDistance, 0.0);
        if (isVanillaCloudTransmission) { diffuseHitDistance = 1000.0; }
        if (isFirstInterfaceReflection) {
            float transparentDistance = signalSanitizeDepth(abs(primary.transparentSpecularHitDistance), 0.0);
            if (transparentDistance > 1e-6) { specularHitDistance = transparentDistance; }
            if (transparentDistance > 1e-6) { diffuseHitDistance = transparentDistance; }
        } else if (isSplitPath(primary.key) && isRefractionValid) {
            specularHitDistance = signalSanitizeDepth(abs(primary.transparentSpecularHitDistance), 0.0);
        }
        if (useSplitCarrier) {
            float carrierHitDistance = max(diffuseHitDistance, specularHitDistance);
            if (isSky) { carrierHitDistance = 1000.0; }
            if (splitCarrierLobe == 0u) {
                diffuseHitDistance = carrierHitDistance;
                specularHitDistance = 0.0;
            } else {
                diffuseHitDistance = 0.0;
                specularHitDistance = carrierHitDistance;
            }
        }

        vec4 diffuseDirection = signalPackDirectionMoment(vec4(diffuseMoment));
        vec4 specularDirection = signalPackDirectionMoment(vec4(specularMoment));
        bool preserveCloudLobes = useFullRateLobes || (flags & ADV_PATH_FLAG_FIRST_HIT_CLOUD) != 0u;
#if MCVR_USE_NRD
        if (indirectUsesHalfRate() && isFirstTransparentSplit) {
            if (raw.diffuse.a <= 0.0) {
                diffuseHitDistance = 0.0;
                diffuseDirection = vec4(0.0);
            }
            if (raw.specular.a <= 0.0) {
                specularHitDistance = 0.0;
                specularDirection = vec4(0.0);
            }
        } else
#endif
        {
            if (!hasDiffuseCheckerSample && !preserveCloudLobes) {
                diffuseHitDistance = 0.0;
                diffuseDirection = vec4(0.0);
            }
            if (!hasSpecularCheckerSample && !preserveCloudLobes) {
                specularHitDistance = 0.0;
                specularDirection = vec4(0.0);
            }
        }
        result.indirectRaw = raw;
        result.diffuseHitDistance = diffuseHitDistance;
        result.specularHitDistance = specularHitDistance;
        result.diffuseDirection = raw.diffuse.a > 0.0 ? diffuseDirection : vec4(0.0);
        result.specularDirection = raw.specular.a > 0.0 ? specularDirection : vec4(0.0);
        result.clearOutput = isSky && !useSplitCarrier && !isVanillaCloudTransmission && !isFirstInterfaceReflection ?
                                 vec4(clearRadiance, 1.0) :
                                 vec4(0.0);
        result.baseEmission = vec4(emission, primary.previousPathDepth);
        if (indirectUsesHalfRate() && isFirstTransparentSplit && isRefractionEnvironment) {
            result.baseEmission.a = -max(abs(primary.previousPathDepth), 1e-3);
        }
    }

    imageStore(outputRefractionImage, checker.flatPixel, vec4(0.0));
    imageStore(outputFogImage, checker.flatPixel, vec4(fogInscatter, fogComposeTransmittance));
    imageStore(outputSegmentationImage, checker.flatPixel, uvec4(surfaceSegmentation(primary), 0u, 0u, 0u));

    float starVisibility = isSky ? (ADV_CLOUD_MODE == 2u ? clamp(cloudTransmittance, 0.0, 1.0) : 1.0) : 0.0;
    starVisibility *= scalarFog;
    imageStore(starCloudTransmittanceImage, checker.flatPixel, vec4(starVisibility));
    return result;
}

#endif
