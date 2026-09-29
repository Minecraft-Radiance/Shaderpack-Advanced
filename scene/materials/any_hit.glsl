#ifndef ADV_SCENE_MATERIALS_ANY_HIT_GLSL
#define ADV_SCENE_MATERIALS_ANY_HIT_GLSL

#include "util/vista_material.glsl"

#include "scene/resources.glsl"
#include "scene/materials/alpha.glsl"
#include "scene/materials/labpbr.glsl"
#include "scene/materials/parallax.glsl"
#include "util/ray_cone.glsl"

struct AnyHitMaterial {
    uint instanceMask;
    uint alphaMode;
    bool isCovered;
    bool isTransparent;
    bool isShadowTransparent;
    bool isWater;
    bool isCloud;
    bool doesParallaxOcclude;
    vec3 tint;
    vec3 shadowTransmission;
    float opacity;
};

bool isAnyHitWaterProbeSurface(vec2 hitAttributes) {
    uint instanceIndex = gl_InstanceCustomIndexEXT;
    if ((loadInstanceMask(instanceIndex) & BOAT_WATER_MASK) != 0u) { return true; }
    uint geometryBufferIndex = getGeometryBufferIndex(instanceIndex, gl_GeometryIndexEXT);
    uint i0, i1, i2;
    loadTriangleIndices(geometryBufferIndex, gl_PrimitiveID, i0, i1, i2);
    uvec2 info = loadMaterialFlagsAndTexture(geometryBufferIndex, i0);
    MaterialVertex m0;
    m0.packedData = info.x;
    m0.textureID = info.y;
    if (hasWaterMaterial(m0)) { return true; }
    if (!hasTexture(m0.packedData)) { return false; }
    int flagTexture = mapping.entries[m0.textureID].flag;
    if (flagTexture < 0) { return false; }
    m0 = loadMaterialVertex(geometryBufferIndex, i0);
    MaterialVertex m1 = loadMaterialVertex(geometryBufferIndex, i1);
    MaterialVertex m2 = loadMaterialVertex(geometryBufferIndex, i2);
    vec3 bary = vec3(1.0 - hitAttributes.x - hitAttributes.y, hitAttributes.x, hitAttributes.y);
    vec2 uv = bary.x * m0.textureUV + bary.y * m1.textureUV + bary.z * m2.textureUV;
    ivec4 flags = ivec4(round(sampleTexture(textures[nonuniformEXT(flagTexture)], uv, 0.0, false) * 255.0));
    return (flags.r & 0x1) != 0;
}

bool doesAnyHitParallaxOcclude(PositionVertex p0,
                               PositionVertex p1,
                               PositionVertex p2,
                               MaterialVertex m0,
                               MaterialVertex m1,
                               MaterialVertex m2,
                               vec3 bary,
                               uint packedData,
                               bool isExcludedSurface) {
#if ADV_PARALLAX_ENABLED == 0
    return true;
#else
    if (!hasTexture(packedData)) { return true; }
    TextureMapEntry textureMap = mapping.entries[m0.textureID];
    if (!canEvaluateParallaxHeight(true, textureMap.normal, packedData, isExcludedSurface)) { return true; }

    vec2 uv0 = m0.textureUV;
    vec2 uv1 = m1.textureUV;
    vec2 uv2 = m2.textureUV;
    vec2 uv = bary.x * uv0 + bary.y * uv1 + bary.z * uv2;
    vec2 atlasMin = min(uv0, min(uv1, uv2));
    vec2 atlasMax = max(uv0, max(uv1, uv2));
    vec3 localDPdu;
    vec3 localDPdv;
    computedposduDv(p0.pos, p1.pos, p2.pos, uv0, uv1, uv2, localDPdu, localDPdv);

    mat3 objectToWorld = mat3(gl_ObjectToWorld3x4EXT);
    mat3 normalMatrix = transpose(mat3(gl_WorldToObject3x4EXT));
    vec3 dPdu = objectToWorld * localDPdu;
    vec3 dPdv = objectToWorld * localDPdv;
    vec3 fallbackNormal = normalizeF(normalMatrix * cross(p1.pos - p0.pos, p2.pos - p0.pos), vec3(0.0, 1.0, 0.0));
    vec3 baseNormal = normalizeF(cross(dPdu, dPdv), fallbackNormal);
    if (dot(baseNormal, -gl_WorldRayDirectionEXT) < 0.0) { baseNormal = -baseNormal; }

    float maxDepth = heightMapMaxDepthWorld(atlasMin, atlasMax, dPdu, dPdv);
    if (maxDepth <= heightMapMinWorldDepth) { return true; }

    vec3 planePosition = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;
    ParallaxSurfaceState surface = makeParallaxSurfaceState(uv, 0.0, planePosition, baseNormal, false);
    ParallaxVisibility visibility;
    resolveParallaxVisibility(textureMap.normal, atlasMin, atlasMax, uv, planePosition, dPdu, dPdv, baseNormal,
                              maxDepth, true, surface, gl_WorldRayDirectionEXT, ADV_PARALLAX_SECONDARY_MAX_STEPS,
                              visibility);
    return isParallaxVisibilityBlocked(visibility);
#endif
}

AnyHitMaterial loadAnyHitMaterial(vec2 hitAttributes,
                                  float coneWidth,
                                  float coneSpread,
                                  bool shouldEvaluateParallaxOcclusion,
                                  bool shouldEvaluateShadowMaterial) {
    AnyHitMaterial material;
    material.instanceMask = 0u;
    material.alphaMode = ALPHA_MODE_OPAQUE;
    material.isCovered = true;
    material.isTransparent = false;
    material.isShadowTransparent = false;
    material.isWater = false;
    material.isCloud = false;
    material.doesParallaxOcclude = true;
    material.tint = vec3(1.0);
    material.shadowTransmission = vec3(1.0);
    material.opacity = 1.0;

    uint instanceIndex = gl_InstanceCustomIndexEXT;
    material.instanceMask = loadInstanceMask(instanceIndex);
    material.isCloud = (material.instanceMask & CLOUD_MASK) != 0u;

    uint geometryBufferIndex = getGeometryBufferIndex(instanceIndex, gl_GeometryIndexEXT);
    uint i0, i1, i2;
    loadTriangleIndices(geometryBufferIndex, gl_PrimitiveID, i0, i1, i2);
    uvec2 info = loadMaterialFlagsAndTexture(geometryBufferIndex, i0);
    MaterialVertex m0;
    m0.packedData = info.x;
    m0.textureID = info.y;
    uint packedData = m0.packedData;
    bool shouldUseTexture = hasTexture(packedData);
    bool shouldUseColorLayer = hasColorLayer(packedData);
    material.alphaMode = getAlphaMode(packedData);
    material.isWater = (material.instanceMask & BOAT_WATER_MASK) != 0u || hasWaterMaterial(m0);
    TextureMapEntry textureMap = shouldUseTexture ? mapping.entries[m0.textureID] : TextureMapEntry(-1, -1, -1);
    bool needsParallax = false;
#if ADV_PARALLAX_ENABLED != 0
    needsParallax = shouldEvaluateParallaxOcclusion && shouldUseTexture &&
        canEvaluateParallaxHeight(true, textureMap.normal, packedData, material.isWater || material.isCloud);
#endif
    if (material.alphaMode == ALPHA_MODE_OPAQUE && textureMap.flag < 0 && !needsParallax) {
        return material;
    }
    m0 = loadMaterialVertex(geometryBufferIndex, i0);
    MaterialVertex m1 = loadMaterialVertex(geometryBufferIndex, i1);
    MaterialVertex m2 = loadMaterialVertex(geometryBufferIndex, i2);

    vec3 bary = vec3(1.0 - hitAttributes.x - hitAttributes.y, hitAttributes.x, hitAttributes.y);
    vec4 colorLayer =
        shouldUseColorLayer ? bary.x * m0.colorLayer + bary.y * m1.colorLayer + bary.z * m2.colorLayer : vec4(1.0);
    vec4 albedo = vec4(1.0);
    vec2 uv = vec2(0.0);
    float lod = 0.0;
    if (shouldUseTexture) {
        uv = bary.x * m0.textureUV + bary.y * m1.textureUV + bary.z * m2.textureUV;
        vec2 atlasMin = min(m0.textureUV, min(m1.textureUV, m2.textureUV));
        vec2 atlasMax = max(m0.textureUV, max(m1.textureUV, m2.textureUV));
        float coneRadius = max(coneWidth + gl_HitTEXT * coneSpread, 0.0);
        if (coneRadius > 0.0) {
            PositionVertex p0 = loadPositionVertex(geometryBufferIndex, i0);
            PositionVertex p1 = loadPositionVertex(geometryBufferIndex, i1);
            PositionVertex p2 = loadPositionVertex(geometryBufferIndex, i2);
            vec3 dPdu, dPdv;
            computedposduDv(p0.pos, p1.pos, p2.pos, m0.textureUV, m1.textureUV, m2.textureUV, dPdu, dPdv);
            lod = lodWithCone(textures[nonuniformEXT(m0.textureID)], uv, coneRadius, dPdu, dPdv);
        }
        albedo =
            sampleLabPbrAlbedo(textures[nonuniformEXT(m0.textureID)], uv, atlasMin, atlasMax, lod, material.alphaMode);
    }

    float rawAlpha = clamp(albedo.a * colorLayer.a, 0.0, 1.0);
    material.isCovered = isAlphaCovered(rawAlpha, material.alphaMode);
    material.opacity = resolveSurfaceOpacity(rawAlpha, material.alphaMode);
    if (!material.isCovered) { return material; }
    material.tint = max(albedo.rgb * colorLayer.rgb, vec3(0.0));
    if (hasVistaMaterial(m0) && !hasWaterMaterial(m0) && worldUBO.vistaTextureID != 0u) {
        vec2 vistaUv = bary.x * m0.textureUV + bary.y * m1.textureUV + bary.z * m2.textureUV;
        material.tint = vistaAlbedo(textures[nonuniformEXT(worldUBO.vistaTextureID)], m0, vistaUv,
            material.tint, max(coneWidth + gl_HitTEXT * coneSpread, 0.0));
    }
    material.isTransparent = material.isCovered && material.opacity < 1.0 - EPS;
    if (shouldUseTexture && textureMap.flag >= 0) {
        ivec4 materialFlags =
            ivec4(round(sampleTexture(textures[nonuniformEXT(textureMap.flag)], uv, ceil(lod), false) * 255.0));
        material.isWater = material.isWater || (materialFlags.r & 0x1) != 0;
    }

    if (shouldEvaluateShadowMaterial && material.isCovered && isAlphaBlendedMode(material.alphaMode) &&
        !material.isWater && !material.isCloud) {
        vec3 shadowTint = material.tint;
        if (hasOverlay(packedData)) {
            vec4 overlay =
                sampleTexture(textures[nonuniformEXT(worldUBO.overlayTextureID)], vec2(m0.overlayUV), 0.0, false);
            shadowTint = max(mix(overlay.rgb, shadowTint, overlay.a), vec3(0.0));
        }
        if (hasGlint(packedData)) {
            vec2 glintUv = bary.x * m0.glintUV + bary.y * m1.glintUV + bary.z * m2.glintUV;
            glintUv = (worldUBO.textureMat * vec4(glintUv, 0.0, 1.0)).xy;
            vec3 glint = sampleTexture(textures[nonuniformEXT(m0.glintTexture)], glintUv, 0.0, false).rgb;
            shadowTint += glint * glint;
        }

        vec4 specular = LABPBR_DEFAULT_SPECULAR;
        if (shouldUseTexture && textureMap.specular >= 0) {
            vec2 atlasMin = min(m0.textureUV, min(m1.textureUV, m2.textureUV));
            vec2 atlasMax = max(m0.textureUV, max(m1.textureUV, m2.textureUV));
            specular = sampleLabPbrSpecular(textures[nonuniformEXT(textureMap.specular)], uv, atlasMin, atlasMax, lod,
                                            ADV_PBR_SAMPLING_MODE);
        }

        LabPBRMat shadowMaterial =
            convertLabPBRMaterial(vec4(shadowTint, material.opacity), specular, LABPBR_DEFAULT_NORMAL);
        material.isShadowTransparent = shadowMaterial.transmission > EPS || material.isTransparent;
        if (material.isShadowTransparent) {
            material.shadowTransmission = alphaBlendedTransmission(shadowTint, material.opacity);
        }
    }

    bool isExcludedFromParallax = !material.isCovered || material.isTransparent || material.isWater || material.isCloud;
    if (shouldEvaluateParallaxOcclusion && shouldUseTexture && !isExcludedFromParallax) {
        PositionVertex p0 = loadPositionVertex(geometryBufferIndex, i0);
        PositionVertex p1 = loadPositionVertex(geometryBufferIndex, i1);
        PositionVertex p2 = loadPositionVertex(geometryBufferIndex, i2);
        material.doesParallaxOcclude =
            doesAnyHitParallaxOcclude(p0, p1, p2, m0, m1, m2, bary, packedData, isExcludedFromParallax);
    }
    return material;
}

vec3 anyHitTransmission(AnyHitMaterial material) {
    return alphaBlendedTransmission(material.tint, material.opacity);
}

#endif
