#ifndef ADV_PATH_INDIRECT_SCATTERING_GLSL
#define ADV_PATH_INDIRECT_SCATTERING_GLSL

struct PathIndirectSample {
    vec3 direction;
    vec3 throughput;
    float segmentRoughness;
    uint medium;
    bool isValid;
};

vec3 indirectInterfaceNormal(HitGeometry geometry, SurfaceMaterial material, vec3 incidentDirection) {
    vec3 geometryNormal = normalize(geometry.geometryNormal, vec3(0.0, 1.0, 0.0));
    if (!material.isWater) { return geometryNormal; }

    vec3 mappedNormal = normalize(material.shadingNormal, geometryNormal);
    if (dot(mappedNormal, geometryNormal) < 0.0) { mappedNormal = -mappedNormal; }
    return dot(incidentDirection, mappedNormal) < -1e-5 ? mappedNormal : geometryNormal;
}

PathIndirectSample sampleIndirectInterface(HitGeometry geometry,
                                           SurfaceMaterial material,
                                           vec3 incomingDirection,
                                           uint currentMedium,
                                           inout uint glassExteriorMedium,
                                           inout uint seed) {
    PathIndirectSample sampleValue;
    sampleValue.direction = vec3(0.0);
    sampleValue.throughput = vec3(0.0);
    sampleValue.segmentRoughness = 0.0;
    sampleValue.medium = currentMedium;
    sampleValue.isValid = false;

    uint hitMedium = material.isWater ? ADV_MEDIUM_WATER : ADV_MEDIUM_GLASS;
    uint nextMedium;
    if (hitMedium == ADV_MEDIUM_WATER) {
        nextMedium = currentMedium == ADV_MEDIUM_WATER ? ADV_MEDIUM_AIR : ADV_MEDIUM_WATER;
    } else if (currentMedium == ADV_MEDIUM_GLASS) {
        nextMedium = glassExteriorMedium;
    } else {
        glassExteriorMedium = currentMedium;
        nextMedium = ADV_MEDIUM_GLASS;
    }

    vec3 interfaceNormal = indirectInterfaceNormal(geometry, material, incomingDirection);
    float sourceIor = mediumIor(currentMedium, material.ior);
    float destinationIor = mediumIor(nextMedium, material.ior);
    float cosIncident = clamp(dot(-incomingDirection, interfaceNormal), 0.0, 1.0);
    float criticalCos = cosCriticalAngle(sourceIor, destinationIor);
    bool hasTotalInternalReflection = criticalCos >= 0.0 && cosIncident <= criticalCos;
    float fresnel = interfaceFresnel(cosIncident, sourceIor, destinationIor);
    bool chooseReflection = hasTotalInternalReflection || rand(seed) < fresnel;

    if (chooseReflection) {
        vec3 reflected = reflect(incomingDirection, material.shadingNormal);
        if (!isFinite(reflected) || dot(reflected, geometry.geometryNormal) <= 1e-6) {
            reflected = reflect(incomingDirection, geometry.geometryNormal);
        }
        sampleValue.direction = normalize(reflected, -incomingDirection);
        sampleValue.throughput = vec3(1.0);
        sampleValue.segmentRoughness = clamp(material.roughness, 0.0, 1.0);
        sampleValue.medium = currentMedium;
        sampleValue.isValid = dot(sampleValue.direction, geometry.geometryNormal) > 1e-6;
        return sampleValue;
    }

    vec3 refracted = refract(incomingDirection, interfaceNormal, sourceIor / max(destinationIor, 1e-5));
    if (!isFinite(refracted) || dot(refracted, refracted) <= 1e-10) { return sampleValue; }
    sampleValue.direction = normalize(refracted, incomingDirection);
    sampleValue.throughput =
        hitMedium == ADV_MEDIUM_GLASS ? clamp(material.transmissionColor, vec3(0.0), vec3(1.0)) : vec3(1.0);
    sampleValue.segmentRoughness = 0.0;
    sampleValue.medium = nextMedium;
    sampleValue.isValid = max(sampleValue.throughput.r, max(sampleValue.throughput.g, sampleValue.throughput.b)) > 1e-6;
    return sampleValue;
}

PathIndirectSample
sampleIndirectOpaque(HitGeometry geometry, SurfaceMaterial material, vec3 incomingDirection, inout uint seed) {
    PathIndirectSample sampleValue;
    sampleValue.direction = vec3(0.0);
    sampleValue.throughput = vec3(0.0);
    sampleValue.segmentRoughness = 0.0;
    sampleValue.medium = ADV_MEDIUM_AIR;
    sampleValue.isValid = false;

    vec3 geometryNormal = normalize(geometry.geometryNormal, vec3(0.0, 1.0, 0.0));
    vec3 shadingNormal = normalize(material.shadingNormal, geometryNormal);
    vec3 viewDirection = normalize(-incomingDirection, shadingNormal);
    vec3 diffuseWeight = diffuseAlbedo(material.albedo, material.metallic);
    vec3 viewFresnel = fresnelSchlick(material.f0, max(dot(viewDirection, shadingNormal), 0.0));
    float diffuseEnergy = luminance((vec3(1.0) - viewFresnel) * diffuseWeight);
    float specularEnergy = luminance(viewFresnel);
    float energySum = diffuseEnergy + specularEnergy;
    if (!isFinite(energySum) || energySum <= 1e-8) { return sampleValue; }

    float specularProbability = specularEnergy / energySum;
    if (diffuseEnergy <= 1e-8) {
        specularProbability = 1.0;
    } else if (specularEnergy <= 1e-8) {
        specularProbability = 0.0;
    } else {
        specularProbability = clamp(specularProbability, 0.05, 0.95);
    }

    if (rand(seed) < specularProbability) {
        SpecularSample specular = sampleSpecularAboveGeometry(viewDirection, shadingNormal, geometryNormal,
                                                              material.roughness, vec2(rand(seed), rand(seed)));
        if (!specular.isValid) { return sampleValue; }
        vec3 halfVector = normalize(viewDirection + specular.direction, shadingNormal);
        vec3 fresnel = fresnelSchlick(material.f0, max(dot(viewDirection, halfVector), 0.0));
        sampleValue.direction = specular.direction;
        sampleValue.throughput = specular.throughput * fresnel / max(specularProbability, 1e-5);
        sampleValue.segmentRoughness = clamp(material.roughness, 0.0, 1.0);
    } else {
        vec3 direction = sampleCosineHemisphere(vec2(rand(seed), rand(seed)), shadingNormal);
        if (dot(direction, geometryNormal) <= 1e-6) {
            direction = sampleCosineHemisphere(vec2(rand(seed), rand(seed)), geometryNormal);
        }
        if (!isFinite(direction) || dot(direction, geometryNormal) <= 1e-6) { return sampleValue; }
        vec3 halfVector = normalize(viewDirection + direction, shadingNormal);
        vec3 fresnel = fresnelSchlick(material.f0, max(dot(viewDirection, halfVector), 0.0));
        sampleValue.direction = direction;
        sampleValue.throughput = (vec3(1.0) - fresnel) * diffuseWeight / max(1.0 - specularProbability, 1e-5);
        sampleValue.segmentRoughness = 1.0;
    }

    sampleValue.throughput = sanitizeRadiance(sampleValue.throughput);
    sampleValue.isValid = isFinite(sampleValue.direction) && isFinite(sampleValue.throughput) &&
                          max(sampleValue.throughput.r, max(sampleValue.throughput.g, sampleValue.throughput.b)) > 1e-6;
    return sampleValue;
}

bool isIndirectInterfaceMaterial(SurfaceMaterial material) {
    return material.isWater ||
           (material.medium == ADV_MEDIUM_GLASS && (material.opacity < 1.0 - 1e-6 || material.transmission > 1e-6));
}

PathIndirectSample sampleIndirectSurface(HitGeometry geometry,
                                         SurfaceMaterial material,
                                         vec3 incomingDirection,
                                         uint currentMedium,
                                         inout uint glassExteriorMedium,
                                         inout uint seed) {
    if (isIndirectInterfaceMaterial(material)) {
        return sampleIndirectInterface(geometry, material, incomingDirection, currentMedium, glassExteriorMedium, seed);
    }
    PathIndirectSample sampleValue = sampleIndirectOpaque(geometry, material, incomingDirection, seed);
    sampleValue.medium = currentMedium;
    return sampleValue;
}

#endif
