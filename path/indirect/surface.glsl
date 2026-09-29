#ifndef ADV_PATH_INDIRECT_SURFACE_GLSL
#define ADV_PATH_INDIRECT_SURFACE_GLSL

#include "path/state.glsl"
#include "lighting/cache/query.glsl"
#include "util/vista_material.glsl"

struct HitGeometry {
    bool isValid;
    uvec3 indices;
    vec3 bary;
    vec3 position;
    float rayDistance;
    float triangleArea;
    vec3 outwardNormal;
    vec3 geometryNormal;
    uint category;
    uint instanceMask;
    bool isFrontFace;
};

struct SurfaceMaterial {
    bool isValid;
    vec3 shadingNormal;
    vec3 albedo;
    vec3 f0;
    vec3 emission;
    vec3 transmissionColor;
    float transmission;
    float roughness;
    float metallic;
    float ior;
    float opacity;
    uint medium;
    bool isCloud;
    bool isWater;
};

HitGeometry invalidHitGeometry() {
    HitGeometry geometry;
    geometry.isValid = false;
    geometry.indices = uvec3(0u);
    geometry.bary = vec3(0.0);
    geometry.position = vec3(0.0);
    geometry.rayDistance = 0.0;
    geometry.triangleArea = 0.0;
    geometry.outwardNormal = vec3(0.0, 1.0, 0.0);
    geometry.geometryNormal = vec3(0.0, 1.0, 0.0);
    geometry.category = ADV_HIT_CATEGORY_DEFAULT;
    geometry.instanceMask = 0u;
    geometry.isFrontFace = true;
    return geometry;
}

SurfaceMaterial invalidSurfaceMaterial() {
    SurfaceMaterial material;
    material.isValid = false;
    material.shadingNormal = vec3(0.0, 1.0, 0.0);
    material.albedo = vec3(0.0);
    material.f0 = vec3(0.04);
    material.emission = vec3(0.0);
    material.transmissionColor = vec3(1.0);
    material.transmission = 0.0;
    material.roughness = 1.0;
    material.metallic = 0.0;
    material.ior = ADV_GLASS_IOR;
    material.opacity = 1.0;
    material.medium = ADV_MEDIUM_SOLID;
    material.isCloud = false;
    material.isWater = false;
    return material;
}

bool decodeHitGeometry(HitPayload hit, vec3 rayOrigin, vec3 rayDirection, out HitGeometry geometry) {
    geometry = invalidHitGeometry();
    if (!isHitValid(hit)) { return false; }

    uint i0, i1, i2;
    loadTriangleIndices(hit.geometryBufferIndex, hit.primitiveId, i0, i1, i2);
    PositionVertex p0 = loadPositionVertex(hit.geometryBufferIndex, i0);
    PositionVertex p1 = loadPositionVertex(hit.geometryBufferIndex, i1);
    PositionVertex p2 = loadPositionVertex(hit.geometryBufferIndex, i2);
    vec3 bary = vec3(1.0 - hit.barycentrics.x - hit.barycentrics.y, hit.barycentrics.x, hit.barycentrics.y);
    if (!isFinite(bary)) { return false; }

    AccelerationStructureInstance instance = tlasInstances.instances[hit.instanceIndex];
    vec3 worldP0 = transformPoint(instance, p0.pos);
    vec3 worldP1 = transformPoint(instance, p1.pos);
    vec3 worldP2 = transformPoint(instance, p2.pos);
    vec3 position = bary.x * worldP0 + bary.y * worldP1 + bary.z * worldP2;
    if (!isFinite(position)) { position = rayOrigin + rayDirection * hit.hitT; }

    vec3 areaVector = cross(worldP1 - worldP0, worldP2 - worldP0);
    float triangleArea = 0.5 * length(areaVector);
    vec3 outwardNormal = normalize(areaVector, vec3(0.0, 1.0, 0.0));
    bool isFrontFace = hit.isFrontFace != 0u;
    vec3 geometryNormal = isFrontFace ? outwardNormal : -outwardNormal;
    bool isValid = isFinite(position) && isFinite(outwardNormal) && isFinite(geometryNormal) && isFinite(hit.hitT) &&
                   hit.hitT >= 0.0;
    if (!isValid) { return false; }

    geometry.isValid = true;
    geometry.indices = uvec3(i0, i1, i2);
    geometry.bary = bary;
    geometry.position = position;
    geometry.rayDistance = hit.hitT;
    geometry.triangleArea = isFinite(triangleArea) ? max(triangleArea, 0.0) : 0.0;
    geometry.outwardNormal = outwardNormal;
    geometry.geometryNormal = geometryNormal;
    geometry.category = hit.category;
    geometry.instanceMask = hit.instanceMask;
    geometry.isFrontFace = isFrontFace;
    return true;
}

float surfaceFootprint(float coneWidthAtHit, HitGeometry geometry, vec3 rayDirection) {
    float projectedCosine = max(abs(dot(rayDirection, geometry.geometryNormal)), 0.05);
    return max(coneWidthAtHit, 0.0) / projectedCosine;
}

float cacheFootprint(float textureConeRadiusAtHit, HitGeometry geometry, vec3 rayDirection, float segmentRoughness) {
    float roughness = clamp(segmentRoughness, 0.0, 1.0);
    float alpha = roughness * roughness;
    float alphaSquared = alpha * alpha;
    float scatteringWidth =
        2.0 * max(geometry.rayDistance, 0.0) * sqrt(0.5 * alphaSquared / max(1.0 - alphaSquared, 1e-4));
    float pixelFootprintWidth = 2.0 * surfaceFootprint(textureConeRadiusAtHit, geometry, rayDirection);
    return max(pixelFootprintWidth, scatteringWidth);
}

RadianceCacheHit makeRadianceCacheHit(HitGeometry geometry, float surfaceFootprint) {
    RadianceCacheHit cacheHit;
    cacheHit.position = geometry.position;
    cacheHit.outwardNormal = geometry.outwardNormal;
    cacheHit.distance = geometry.rayDistance;
    cacheHit.surfaceFootprint = max(surfaceFootprint, 0.0);
    cacheHit.category = geometry.category;
    cacheHit.instanceMask = geometry.instanceMask;
    return cacheHit;
}

bool decodeSurfaceMaterial(HitPayload hit,
                           HitGeometry geometry,
                           vec3 rayDirection,
                           float coneWidthAtHit,
                           out SurfaceMaterial indirectMaterial) {
    indirectMaterial = invalidSurfaceMaterial();
    if (!geometry.isValid) { return false; }

    PositionVertex p0 = loadPositionVertex(hit.geometryBufferIndex, geometry.indices.x);
    PositionVertex p1 = loadPositionVertex(hit.geometryBufferIndex, geometry.indices.y);
    PositionVertex p2 = loadPositionVertex(hit.geometryBufferIndex, geometry.indices.z);
    MaterialVertex m0 = loadMaterialVertex(hit.geometryBufferIndex, geometry.indices.x);
    MaterialVertex m1 = loadMaterialVertex(hit.geometryBufferIndex, geometry.indices.y);
    MaterialVertex m2 = loadMaterialVertex(hit.geometryBufferIndex, geometry.indices.z);

    uint packedData = m0.packedData;
    bool shouldUseTexture = hasTexture(packedData);
    bool shouldUseColorLayer = hasColorLayer(packedData);
    bool shouldUseOverlay = hasOverlay(packedData);
    bool shouldUseGlint = hasGlint(packedData);
    uint alphaMode = getAlphaMode(packedData);
    vec4 colorLayer = shouldUseColorLayer ? geometry.bary.x * m0.colorLayer + geometry.bary.y * m1.colorLayer +
                                                geometry.bary.z * m2.colorLayer :
                                            vec4(1.0);

    vec2 uv = vec2(0.0);
    vec2 atlasMin = vec2(0.0);
    vec2 atlasMax = vec2(1.0);
    vec3 localDPdu = p1.pos - p0.pos;
    vec3 localDPdv = p2.pos - p0.pos;
    TextureMapEntry textureMap = TextureMapEntry(-1, -1, -1);
    float lod = 0.0;
    if (shouldUseTexture) {
        uv = geometry.bary.x * m0.textureUV + geometry.bary.y * m1.textureUV + geometry.bary.z * m2.textureUV;
        atlasMin = min(m0.textureUV, min(m1.textureUV, m2.textureUV));
        atlasMax = max(m0.textureUV, max(m1.textureUV, m2.textureUV));
        computedposduDv(p0.pos, p1.pos, p2.pos, m0.textureUV, m1.textureUV, m2.textureUV, localDPdu, localDPdv);
        lod = lodWithCone(textures[nonuniformEXT(m0.textureID)], uv, max(coneWidthAtHit, 0.0), localDPdu, localDPdv);
        textureMap = mapping.entries[m0.textureID];
    }

    bool isCloud = (geometry.instanceMask & CLOUD_MASK) != 0u;
    bool isWater = (geometry.instanceMask & BOAT_WATER_MASK) != 0u || hasWaterMaterial(m0);
    if (shouldUseTexture && textureMap.flag >= 0) {
        ivec4 materialFlags =
            ivec4(round(sampleTexture(textures[nonuniformEXT(textureMap.flag)], uv, ceil(lod), false) * 255.0));
        isWater = isWater || (materialFlags.r & 0x1) != 0;
    }

    vec4 albedoSample = vec4(1.0);
    vec4 specularSample = LABPBR_DEFAULT_SPECULAR;
    vec4 normalSample = LABPBR_DEFAULT_NORMAL;
    if (shouldUseTexture) {
        albedoSample =
            sampleLabPbrAlbedo(textures[nonuniformEXT(m0.textureID)], uv, atlasMin, atlasMax, lod, alphaMode);
        if (textureMap.specular >= 0) {
            specularSample = sampleLabPbrSpecular(textures[nonuniformEXT(textureMap.specular)], uv, atlasMin, atlasMax,
                                                  lod, ADV_PBR_SAMPLING_MODE);
        }
        if (isWater && textureMap.normal >= 0) {
            normalSample = samplePBRTexture(textures[nonuniformEXT(textureMap.normal)], uv, atlasMin, atlasMax, lod,
                                            ADV_PBR_SAMPLING_MODE);
        }
    }

    float surfaceAlpha = resolveSurfaceOpacity(albedoSample.a * colorLayer.a, alphaMode);
    vec3 tint = max(albedoSample.rgb * colorLayer.rgb, vec3(0.0));
    if (hasVistaMaterial(m0) && !isWater && worldUBO.vistaTextureID != 0u) {
        vec2 vistaUv = geometry.bary.x * m0.textureUV + geometry.bary.y * m1.textureUV +
            geometry.bary.z * m2.textureUV;
        tint = vistaAlbedo(textures[nonuniformEXT(worldUBO.vistaTextureID)], m0, vistaUv, tint,
            surfaceFootprint(coneWidthAtHit, geometry, rayDirection));
    }
    if (shouldUseOverlay) {
        vec4 overlay =
            sampleTexture(textures[nonuniformEXT(worldUBO.overlayTextureID)], vec2(m0.overlayUV), 0.0, false);
        tint = max(mix(overlay.rgb, tint, overlay.a), vec3(0.0));
    }
    if (shouldUseGlint) {
        vec2 glintUv = geometry.bary.x * m0.glintUV + geometry.bary.y * m1.glintUV + geometry.bary.z * m2.glintUV;
        glintUv = (worldUBO.textureMat * vec4(glintUv, 0.0, 1.0)).xy;
        vec3 glint = sampleTexture(textures[nonuniformEXT(m0.glintTexture)], glintUv, 0.0, false).rgb;
        tint += glint * glint;
    }

    LabPBRMat material = convertLabPBRMaterial(vec4(tint, surfaceAlpha), specularSample, normalSample);
    vec3 shadingNormal = geometry.geometryNormal;
    if (isWater && shouldUseTexture && textureMap.normal >= 0) {
        AccelerationStructureInstance instance = tlasInstances.instances[hit.instanceIndex];
        vec3 dPdu = transformVector(instance, localDPdu);
        vec3 dPdv = transformVector(instance, localDPdv);
        vec3 tangent, bitangent;
        buildBasis(dPdu, dPdv, geometry.geometryNormal, tangent, bitangent);
        shadingNormal = applyNormalMap(material.normal, tangent, bitangent, geometry.geometryNormal, -rayDirection);
    }

    uint medium = ADV_MEDIUM_SOLID;
    bool isPortal =
        geometry.category == ADV_HIT_CATEGORY_END_PORTAL || geometry.category == ADV_HIT_CATEGORY_END_GATEWAY;
    bool isNonReflective = geometry.category == ADV_HIT_CATEGORY_NO_REFLECT;
    if (isCloud) {
        medium = ADV_MEDIUM_CLOUD;
    } else if (isWater) {
        medium = ADV_MEDIUM_WATER;
    } else if (!isPortal && !isNonReflective && (material.transmission > EPS || surfaceAlpha < 1.0 - EPS)) {
        medium = ADV_MEDIUM_GLASS;
    }

    float vertexEmission =
        geometry.bary.x * m0.albedoEmission + geometry.bary.y * m1.albedoEmission + geometry.bary.z * m2.albedoEmission;
    vec3 emission = max(tint * (material.emission + vertexEmission) * float(ADV_EMISSION_SCALE), vec3(0.0));
    if (isWater) {
        surfaceAlpha = 0.0;
        material.f0 = vec3(0.02);
        material.metallic = 0.0;
        material.transmission = 1.0;
        material.ior = ADV_WATER_IOR;
        material.roughness = 0.012;
        tint = vec3(1.0);
        emission = vec3(0.0);
    } else if (isCloud) {
        material.f0 = vec3(0.04);
        material.roughness = 1.0;
        material.metallic = 0.0;
        material.transmission = 0.0;
        material.ior = ADV_CLOUD_IOR;
        tint = vec3(1.0);
        emission = vec3(0.0);
        shadingNormal = geometry.geometryNormal;
    }

    bool isValid = isFinite(shadingNormal) && isFinite(tint) && isFinite(material.f0) && isFinite(emission);
    if (!isValid) { return false; }

    if (isChunkGeometryBufferIndex(hit.geometryBufferIndex) && !isWater && !isCloud && !isPortal && !isNonReflective) {
        material.albedo = tint;
        applyGroundWetness(material, groundWetness(geometry.position, geometry.outwardNormal));
        tint = material.albedo;
    }

    indirectMaterial.isValid = true;
    indirectMaterial.shadingNormal = shadingNormal;
    indirectMaterial.albedo = max(tint, vec3(0.0));
    indirectMaterial.f0 = clamp(material.f0, vec3(0.0), vec3(1.0));
    indirectMaterial.emission = emission;
    indirectMaterial.transmissionColor = alphaBlendedTransmission(tint, surfaceAlpha);
    indirectMaterial.transmission = clamp(material.transmission, 0.0, 1.0);
    indirectMaterial.roughness = clamp(material.roughness, 0.0, 1.0);
    indirectMaterial.metallic = clamp(material.metallic, 0.0, 1.0);
    indirectMaterial.ior = clamp(material.ior, 1.0001, 3.0);
    indirectMaterial.opacity = clamp(surfaceAlpha, 0.0, 1.0);
    indirectMaterial.medium = medium;
    indirectMaterial.isCloud = isCloud;
    indirectMaterial.isWater = isWater;
    return true;
}

#endif
