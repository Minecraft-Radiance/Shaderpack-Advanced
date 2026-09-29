#ifndef ADV_OUTPUT_INDIRECT_GLSL
#define ADV_OUTPUT_INDIRECT_GLSL

layout(set = 5, binding = ADV_DIFFUSE_RADIANCE_BINDING, rgba16f) readonly uniform image2D diffuseRadianceImage;
layout(set = 5, binding = ADV_DIFFUSE_HIT_DISTANCE_BINDING, r32f) readonly uniform image2D diffuseHitDistanceImage;
layout(set = 5,
       binding = ADV_DIFFUSE_DIRECTION_MOMENT_BINDING,
       rgba16f) readonly uniform image2D diffuseDirectionMomentImage;
layout(set = 5, binding = ADV_SPECULAR_RADIANCE_BINDING, rgba16f) readonly uniform image2D specularRadianceImage;
layout(set = 5, binding = ADV_SPECULAR_HIT_DISTANCE_BINDING, r32f) readonly uniform image2D specularHitDistanceImage;
layout(set = 5,
       binding = ADV_SPECULAR_DIRECTION_MOMENT_BINDING,
       rgba16f) readonly uniform image2D specularDirectionMomentImage;

struct IndirectSignals {
    RawRadiance radiance;
    float diffuseDistance;
    float specularDistance;
    vec4 diffuseDirection;
    vec4 specularDirection;
};

IndirectSignals emptyIndirectSignals() {
    return IndirectSignals(RawRadiance(vec4(0.0), vec4(0.0)), 0.0, 0.0, vec4(0.0), vec4(0.0));
}

vec4 roundIndirectHalf(vec4 value) {
    return vec4(unpackHalf2x16(packHalf2x16(value.xy)), unpackHalf2x16(packHalf2x16(value.zw)));
}

vec3 checkerViewFresnel(ResolvePath primary) {
    vec3 normal = brdfNormalize(primary.shadingNormal, vec3(0.0, 1.0, 0.0));
    vec3 view = brdfNormalize(-primary.rayDirection, normal);
    float roughnessSquared = primary.roughness * primary.roughness;
    vec3 effectiveHalf = brdfNormalize(mix(normal, normal + view, roughnessSquared), normal);
    return fresnelSchlick(clamp(primary.f0, vec3(0.0), vec3(1.0)), max(dot(view, effectiveHalf), 0.0));
}

vec4 checkerDirectionMoment(vec4 sourceMoment, vec3 contribution) {
    float directionLengthSquared = dot(sourceMoment.xyz, sourceMoment.xyz);
    if (!isFinite(sourceMoment) || sourceMoment.w <= 1e-8 || !isFinite(directionLengthSquared) ||
        directionLengthSquared <= 1e-12) {
        return vec4(0.0);
    }
    vec3 direction = sourceMoment.xyz * inversesqrt(directionLengthSquared);
    float weight = min(luminance(contribution), ADV_FP16_MAX);
    return weight > 1e-8 ? vec4(direction * weight, weight) : vec4(0.0);
}

IndirectSignals resolveIndirectSignals(ivec2 pixel,
                                       ResolvePath primary,
                                       vec4 diffuseRadiance,
                                       float diffuseDistance,
                                       vec4 diffuseDirection,
                                       vec4 specularRadiance,
                                       float specularDistance,
                                       vec4 specularDirection) {
    if (!isLobeSurfaceShadeable(primary.key)) { return emptyIndirectSignals(); }
    vec3 throughput = sanitizeRadiance(primary.throughput) * indirectSplitBranchWeight(primary.key);
    vec3 viewFresnel = checkerViewFresnel(primary);
    vec3 surfaceDiffuseAlbedo = diffuseAlbedo(primary.albedo, primary.metallic) * clamp(primary.opacity, 0.0, 1.0);
    bool isFirstInterfaceReflection = (pathFlags(primary.key) & ADV_PATH_FLAG_FIRST_INTERFACE_SPECULAR) != 0u;

    LobeSurface lobeSurface = makeLobeSurface(primary);
    bool useFullRateLobes = indirectUsesFullRateLobes(primary.key);
    bool useLobeMixture = usesStochasticLobes(lobeSurface);
    LobeSelection lobeSelection = selectLobe(pixel, lobeSurface);
    float estimatorWeight = useFullRateLobes ? 1.0 : lobeEstimatorWeight(lobeSelection);
    bool hasSample = hasIndirectSample(primary.key);
    bool hasDiffuse = hasSample && (useFullRateLobes || useLobeMixture || lobeSelection.lobe == 0u);
    vec3 diffuseContribution = vec3(0.0);
    float diffuseHitDistance = 0.0;
    vec4 diffuseDirectionMoment = vec4(0.0);
    bool hasSpecular = hasSample && (useFullRateLobes || useLobeMixture || lobeSelection.lobe == 1u);
    vec3 specularContribution = vec3(0.0);
    float specularHitDistance = 0.0;
    vec4 specularDirectionMoment = vec4(0.0);

    if (useLobeMixture && hasSample) {
        bool sampledSpecular = lobeSelection.lobe == 1u;
        vec4 radiance = sampledSpecular ? specularRadiance : diffuseRadiance;
        vec4 sampledDirectionMoment = sampledSpecular ? specularDirection : diffuseDirection;
        float sampledHitDistance = sampledSpecular ? specularDistance : diffuseDistance;
        bool hasResolvedMixtureSample = radiance.a > 0.0 && isFinite(radiance);
        hasDiffuse = hasDiffuse && hasResolvedMixtureSample;
        hasSpecular = hasSpecular && hasResolvedMixtureSample;
        diffuseHitDistance = hasResolvedMixtureSample ? sampledHitDistance : 0.0;
        specularHitDistance = hasResolvedMixtureSample ? sampledHitDistance : 0.0;
        if (hasResolvedMixtureSample && isFinite(sampledDirectionMoment) && sampledDirectionMoment.w > 1e-8) {
            vec3 sampledDirection = normalize(sampledDirectionMoment.xyz, primary.shadingNormal);
            LobeMixtureThroughput mixture = evaluateLobeMixtureThroughput(
                primary.shadingNormal, primary.geometryNormal, -primary.rayDirection, sampledDirection, primary.albedo,
                primary.f0, primary.roughness, primary.metallic, specularLobeProbability(lobeSurface));
            if (mixture.isValid) {
                diffuseContribution = sanitizeRadiance(radiance.rgb * mixture.diffuse * throughput);
                specularContribution = sanitizeRadiance(radiance.rgb * mixture.specular * throughput);
                diffuseDirectionMoment = checkerDirectionMoment(sampledDirectionMoment, diffuseContribution);
                specularDirectionMoment = checkerDirectionMoment(sampledDirectionMoment, specularContribution);
            }
        }
    } else if (hasDiffuse) {
        vec4 radiance = diffuseRadiance;
        hasDiffuse = radiance.a > 0.0 && isFinite(radiance);
        if (hasDiffuse) {
            diffuseContribution = sanitizeRadiance(radiance.rgb * (vec3(1.0) - viewFresnel) * surfaceDiffuseAlbedo *
                                                   throughput * estimatorWeight);
        }
        if (hasDiffuse) {
            diffuseHitDistance = isFirstInterfaceReflection ? abs(primary.transparentSpecularHitDistance) : diffuseDistance;
            diffuseDirectionMoment = checkerDirectionMoment(diffuseDirection, diffuseContribution);
        }
    }

    if (!useLobeMixture && hasSpecular) {
        vec4 radiance = specularRadiance;
        hasSpecular = radiance.a > 0.0 && isFinite(radiance);
        if (hasSpecular) {
            specularContribution = sanitizeRadiance(radiance.rgb * viewFresnel * throughput * estimatorWeight);
        }
        if (hasSpecular) {
            specularHitDistance =
                isFirstInterfaceReflection ? abs(primary.transparentSpecularHitDistance) : specularDistance;
            specularDirectionMoment = checkerDirectionMoment(specularDirection, specularContribution);
        }
    }

    RawRadiance raw;
    raw.diffuse = hasDiffuse ? vec4(diffuseContribution, 1.0) : vec4(0.0);
    raw.specular = hasSpecular ? vec4(specularContribution, 1.0) : vec4(0.0);
    IndirectSignals result;
    result.radiance = RawRadiance(roundIndirectHalf(raw.diffuse), roundIndirectHalf(raw.specular));
    result.diffuseDistance = float(
        float16_t(hasDiffuse && isFinite(diffuseHitDistance) ? clamp(diffuseHitDistance, 0.0, ADV_FP16_MAX) : 0.0));
    result.specularDistance = float(
        float16_t(hasSpecular && isFinite(specularHitDistance) ? clamp(specularHitDistance, 0.0, ADV_FP16_MAX) : 0.0));
    result.diffuseDirection =
        roundIndirectHalf(hasDiffuse ? signalPackDirectionMoment(diffuseDirectionMoment) : vec4(0.0));
    result.specularDirection =
        roundIndirectHalf(hasSpecular ? signalPackDirectionMoment(specularDirectionMoment) : vec4(0.0));
    return result;
}

IndirectSignals loadIndirectSignals(CheckerCoordinate checker, ResolvePath primary) {
    ivec2 extent = ivec2(int(ADV_RENDER_WIDTH), int(ADV_RENDER_HEIGHT));
    if (indirectUsesHalfRate() &&
        any(notEqual(checker.flatPixel, indirectPairRepresentative(checker.flatPixel, extent)))) {
        return emptyIndirectSignals();
    }
    if (!isLobeSurfaceShadeable(primary.key) || !hasPathRayBudget(pathRayBudgetUsed(primary.key)) ||
        !hasIndirectSample(primary.key)) {
        return emptyIndirectSignals();
    }
    LobeSurface surface = makeLobeSurface(primary);
    uint selectedLobe = selectedLobe(checker.flatPixel, surface);
    bool bothLobes = indirectUsesFullRateLobes(primary.key) && !indirectUsesHalfRate();
    vec4 diffuse = vec4(0.0);
    float diffuseDistance = 0.0;
    vec4 diffuseDirection = vec4(0.0);
    vec4 specular = vec4(0.0);
    float specularDistance = 0.0;
    vec4 specularDirection = vec4(0.0);
    if (bothLobes || selectedLobe == 0u) {
        diffuse = imageLoad(diffuseRadianceImage, checker.packedPixel);
        diffuseDistance = imageLoad(diffuseHitDistanceImage, checker.packedPixel).x;
        diffuseDirection = imageLoad(diffuseDirectionMomentImage, checker.packedPixel);
    }
    if (bothLobes || selectedLobe == 1u) {
        specular = imageLoad(specularRadianceImage, checker.packedPixel);
        specularDistance = imageLoad(specularHitDistanceImage, checker.packedPixel).x;
        specularDirection = imageLoad(specularDirectionMomentImage, checker.packedPixel);
    }
    return resolveIndirectSignals(checker.flatPixel, primary, diffuse, diffuseDistance, diffuseDirection, specular,
                                  specularDistance, specularDirection);
}
#endif
