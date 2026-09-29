#ifndef ADV_SCENE_SURFACE_GLSL
#define ADV_SCENE_SURFACE_GLSL

#include "core/math.glsl"
#include "scene/surface_types.glsl"
#include "scene/geometry.glsl"
#include "scene/parallax_state.glsl"

#include "core/bindings.glsl"
#include "scene/materials/media.glsl"
#include "scene/hit.glsl"
#include "scene/materials/alpha.glsl"
#include "scene/materials/water.glsl"
#include "util/color_space.glsl"
#include "util/labpbr.glsl"
#include "scene/materials/wetness.glsl"
#include "util/ray_cone.glsl"
#include "scene/materials/labpbr.glsl"
#include "scene/materials/parallax.glsl"
#include "util/vista_material.glsl"

#ifndef ADV_EMISSION_SCALE
#    define ADV_EMISSION_SCALE 1.0
#endif

vec3 opticalInterfaceNormal(Surface surface, vec3 incidentDirection) {
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

Surface invalidSurface() {
    Surface surface;
    surface.isValid = false;
    surface.category = ADV_HIT_CATEGORY_DEFAULT;
    surface.instanceMask = 0u;
    surface.instanceIndex = 0u;
    surface.geometryBufferIndex = 0u;
    surface.primitiveId = 0u;
    surface.position = vec3(0.0);
    surface.rayDistance = 0.0;
    surface.previousPosition = vec3(0.0);
    surface.hasPreviousPosition = false;
    surface.outwardGeometryNormal = vec3(0.0, 1.0, 0.0);
    surface.geometryNormal = vec3(0.0, 1.0, 0.0);
    surface.shadingNormal = vec3(0.0, 1.0, 0.0);
    surface.albedo = vec3(0.0);
    surface.f0 = vec3(0.0);
    surface.emission = vec3(0.0);
    surface.transmissionColor = vec3(0.0);
    surface.transmission = 0.0;
    surface.roughness = 1.0;
    surface.metallic = 0.0;
    surface.ior = ADV_GLASS_IOR;
    surface.opacity = 1.0;
    surface.medium = ADV_MEDIUM_SOLID;
    surface.isFrontFace = true;
    surface.isHand = false;
    surface.isCloud = false;
    surface.isWater = false;
    surface.isNonReflective = false;
    surface.isPortal = false;
    surface.hasParallax = false;
    surface.isParallaxSideWall = false;
    surface.parallaxNormalTextureId = -1;
    surface.parallaxAtlasMin = vec2(0.0);
    surface.parallaxAtlasMax = vec2(1.0);
    surface.parallaxReferenceUv = vec2(0.0);
    surface.parallaxContinuousUv = vec2(0.0);
    surface.parallaxDepth = 0.0;
    surface.parallaxMaxDepthWorld = 0.0;
    surface.shouldTraceParallaxHeight = false;
    surface.parallaxPlanePosition = vec3(0.0);
    surface.parallaxBaseNormal = vec3(0.0, 1.0, 0.0);
    surface.parallaxDPdu = vec3(1.0, 0.0, 0.0);
    surface.parallaxDPdv = vec3(0.0, 0.0, 1.0);
    return surface;
}

bool resolveSurfaceParallaxExit(Surface surface, vec3 worldDirection, out vec3 origin, out vec3 normal) {
    origin = surface.position;
    normal = surface.geometryNormal;
    if (!surface.hasParallax) { return true; }

    vec2 materialUv = wrapUvInRect(surface.parallaxContinuousUv, surface.parallaxAtlasMin, surface.parallaxAtlasMax);
    ParallaxSurfaceState parallaxSurface =
        makeParallaxSurfaceState(materialUv, surface.parallaxContinuousUv, surface.parallaxDepth, surface.position,
                                 surface.geometryNormal, surface.isParallaxSideWall);
    return resolveParallaxExitOrigin(
        surface.parallaxNormalTextureId, surface.parallaxAtlasMin, surface.parallaxAtlasMax,
        surface.parallaxReferenceUv, surface.parallaxPlanePosition, surface.parallaxDPdu, surface.parallaxDPdv,
        surface.parallaxBaseNormal, surface.parallaxMaxDepthWorld, surface.shouldTraceParallaxHeight, parallaxSurface,
        worldDirection, ADV_PARALLAX_SECONDARY_MAX_STEPS, origin, normal);
}

bool decodeSurface(
    HitPayload hit, vec3 rayOrigin, vec3 rayDirection, bool shouldEvaluateParallax, out Surface surface) {
    surface = invalidSurface();
    if (!isHitValid(hit)) { return false; }

    uint i0, i1, i2;
    PositionVertex p0, p1, p2;
    MaterialVertex m0, m1, m2;
    loadTriangle(hit.geometryBufferIndex, hit.primitiveId, i0, i1, i2, p0, p1, p2, m0, m1, m2);
    vec3 bary = vec3(1.0 - hit.barycentrics.x - hit.barycentrics.y, hit.barycentrics.x, hit.barycentrics.y);
    if (!isFinite(bary)) { return false; }

    AccelerationStructureInstance instance = tlasInstances.instances[hit.instanceIndex];
    vec3 worldP0 = transformPoint(instance, p0.pos);
    vec3 worldP1 = transformPoint(instance, p1.pos);
    vec3 worldP2 = transformPoint(instance, p2.pos);
    vec3 localPosition = bary.x * p0.pos + bary.y * p1.pos + bary.z * p2.pos;
    vec3 position = bary.x * worldP0 + bary.y * worldP1 + bary.z * worldP2;
    if (!isFinite(position)) { position = rayOrigin + rayDirection * hit.hitT; }
    vec3 planePosition = position;

    vec3 outwardNormal = normalize(cross(worldP1 - worldP0, worldP2 - worldP0), vec3(0.0, 1.0, 0.0));
    bool isFrontFace = hit.isFrontFace != 0u;
    vec3 geometryNormal = isFrontFace ? outwardNormal : -outwardNormal;

    uint packedData = m0.packedData;
    bool shouldUseTexture = hasTexture(packedData);
    bool shouldUseColorLayer = hasColorLayer(packedData);
    bool shouldUseOverlay = hasOverlay(packedData);
    bool shouldUseGlint = hasGlint(packedData);
    uint alphaMode = getAlphaMode(packedData);
    vec4 colorLayer =
        shouldUseColorLayer ? bary.x * m0.colorLayer + bary.y * m1.colorLayer + bary.z * m2.colorLayer : vec4(1.0);

    vec2 uv = vec2(0.0);
    vec2 atlasMin = vec2(0.0);
    vec2 atlasMax = vec2(1.0);
    vec3 localDPdu = p1.pos - p0.pos;
    vec3 localDPdv = p2.pos - p0.pos;
    TextureMapEntry textureMap = TextureMapEntry(-1, -1, -1);
    float lod = 0.0;
    if (shouldUseTexture) {
        uv = bary.x * m0.textureUV + bary.y * m1.textureUV + bary.z * m2.textureUV;
        atlasMin = min(m0.textureUV, min(m1.textureUV, m2.textureUV));
        atlasMax = max(m0.textureUV, max(m1.textureUV, m2.textureUV));
        computedposduDv(p0.pos, p1.pos, p2.pos, m0.textureUV, m1.textureUV, m2.textureUV, localDPdu, localDPdv);
        lod = lodWithCone(textures[nonuniformEXT(m0.textureID)], uv,
                          max(hit.coneWidth + hit.hitT * hit.coneSpread, 0.0), localDPdu, localDPdv);
        textureMap = mapping.entries[m0.textureID];
    }

    vec3 dPdu = transformVector(instance, localDPdu);
    vec3 dPdv = transformVector(instance, localDPdv);
    vec3 tangent, bitangent;
    buildBasis(dPdu, dPdv, geometryNormal, tangent, bitangent);

    bool isCloud = (hit.instanceMask & CLOUD_MASK) != 0u;
    bool isHand = (hit.instanceMask & HAND_MASK) != 0u;
    bool isWater = (hit.instanceMask & BOAT_WATER_MASK) != 0u || hasWaterMaterial(m0);
    bool isPortal = hit.category == ADV_HIT_CATEGORY_END_PORTAL || hit.category == ADV_HIT_CATEGORY_END_GATEWAY;
    bool isNonReflective = hit.category == ADV_HIT_CATEGORY_NO_REFLECT;
    if (shouldUseTexture && textureMap.flag >= 0) {
        ivec4 materialFlags =
            ivec4(round(sampleTexture(textures[nonuniformEXT(textureMap.flag)], uv, ceil(lod), false) * 255.0));
        isWater = isWater || (materialFlags.r & 0x1) != 0;
    }

    ParallaxMapping parallaxMapping;
    bool isExcludedFromParallax = !shouldEvaluateParallax || isWater;
    initializeParallaxMapping(shouldUseTexture, textureMap.normal, packedData, atlasMin, atlasMax, uv, lod, dPdu, dPdv,
                              geometryNormal, planePosition, rayDirection, -rayDirection, hit.hitT,
                              isExcludedFromParallax, parallaxMapping);
    vec2 referenceUv = uv;
    uv = parallaxMapping.initialHit.uv;
    position = parallaxMapping.worldPosition;
    float rayDistance = parallaxMapping.actualHitDistance;
    bool hasParallax = parallaxMapping.shouldTraceLocalHeight && parallaxMapping.initialHit.hit &&
                       isFinite(parallaxMapping.initialContinuousUv) && isFinite(position) && isFinite(rayDistance);
    if (parallaxMapping.isInitialSideWall) {
        geometryNormal = normalize(parallaxMapping.initialGeometricNormal, geometryNormal);
        buildBasis(dPdu, dPdv, geometryNormal, tangent, bitangent);
    }

    vec4 albedoSample = vec4(1.0);
    vec4 specularSample = LABPBR_DEFAULT_SPECULAR;
    vec4 normalSample = LABPBR_DEFAULT_NORMAL;
    bool usesSurfaceMaterial = !isWater && !isCloud;
    if (shouldUseTexture && !isWater) {
        albedoSample =
            sampleLabPbrAlbedo(textures[nonuniformEXT(m0.textureID)], uv, atlasMin, atlasMax, lod, alphaMode);
        if (usesSurfaceMaterial && textureMap.specular >= 0) {
            specularSample = sampleLabPbrSpecular(textures[nonuniformEXT(textureMap.specular)], uv, atlasMin, atlasMax,
                                                  lod, ADV_PBR_SAMPLING_MODE);
        }
        if (usesSurfaceMaterial && textureMap.normal >= 0) {
            normalSample = samplePBRTexture(textures[nonuniformEXT(textureMap.normal)], uv, atlasMin, atlasMax, lod,
                                            ADV_PBR_SAMPLING_MODE);
        }
    }

    float surfaceAlpha = resolveSurfaceOpacity(albedoSample.a * colorLayer.a, alphaMode);
    vec3 tint = max(albedoSample.rgb * colorLayer.rgb, vec3(0.0));
    if (hasVistaMaterial(m0) && !isWater && worldUBO.vistaTextureID != 0u) {
        vec2 vistaUv = bary.x * m0.textureUV + bary.y * m1.textureUV + bary.z * m2.textureUV;
        float footprint = max(hit.coneWidth + hit.hitT * hit.coneSpread, 0.0) /
            max(abs(dot(geometryNormal, rayDirection)), 0.05);
        tint = vistaAlbedo(textures[nonuniformEXT(worldUBO.vistaTextureID)], m0, vistaUv, tint, footprint);
    }
    if (usesSurfaceMaterial && shouldUseOverlay) {
        vec4 overlay =
            sampleTexture(textures[nonuniformEXT(worldUBO.overlayTextureID)], vec2(m0.overlayUV), 0.0, false);
        tint = max(mix(overlay.rgb, tint, overlay.a), vec3(0.0));
    }
    if (usesSurfaceMaterial && shouldUseGlint) {
        vec2 glintUv = bary.x * m0.glintUV + bary.y * m1.glintUV + bary.z * m2.glintUV;
        glintUv = (worldUBO.textureMat * vec4(glintUv, 0.0, 1.0)).xy;
        vec3 glint = sampleTexture(textures[nonuniformEXT(m0.glintTexture)], glintUv, 0.0, false).rgb;
        tint += glint * glint;
    }

    LabPBRMat material = convertLabPBRMaterial(vec4(tint, surfaceAlpha), specularSample, normalSample);
    uint medium = ADV_MEDIUM_SOLID;
    if (isCloud) {
        medium = ADV_MEDIUM_CLOUD;
    } else if (isWater) {
        medium = ADV_MEDIUM_WATER;
    } else if (!isPortal && !isNonReflective && (material.transmission > EPS || surfaceAlpha < 1.0 - EPS)) {
        medium = ADV_MEDIUM_GLASS;
    }

    vec3 shadingNormal = geometryNormal;
    vec3 emission = vec3(0.0);
    if (usesSurfaceMaterial) {
        shadingNormal = applyNormalMap(material.normal, tangent, bitangent, geometryNormal, -rayDirection);
        float vertexEmission = bary.x * m0.albedoEmission + bary.y * m1.albedoEmission + bary.z * m2.albedoEmission;
        emission = max(tint * (material.emission + vertexEmission) * float(ADV_EMISSION_SCALE), vec3(0.0));
    }

    if (isWater) {
        surfaceAlpha = 0.0;
        material.albedo = vec3(1.0);
        material.f0 = vec3(0.02);
        material.metallic = 0.0;
        material.transmission = 1.0;
        material.ior = ADV_WATER_IOR;
        tint = vec3(1.0);
        emission = vec3(0.0);
        if (abs(geometryNormal.y) > 0.75) {
            vec2 absoluteWaterPosition = position.xz + vec2(worldUBO.cameraPos.x, worldUBO.cameraPos.z);
            float unresolvedVariance;
            float coneRadius = max(hit.coneWidth + hit.hitT * hit.coneSpread, 0.0);
            vec2 waterSlope = waterSurfaceSlope(absoluteWaterPosition, rayDirection, coneRadius, unresolvedVariance);
            vec3 upwardWaterNormal = normalize(vec3(-waterSlope.x, 1.0, -waterSlope.y), vec3(0.0, 1.0, 0.0));
            shadingNormal = dot(upwardWaterNormal, geometryNormal) >= 0.0 ? upwardWaterNormal : -upwardWaterNormal;
            float geometryFacing = max(dot(geometryNormal, -rayDirection), 1e-5);
            float waveFacing = dot(shadingNormal, -rayDirection);
            float facingBlend = clamp((geometryFacing * 0.05 - waveFacing) /
                                          max(geometryFacing - waveFacing, 1e-5), 0.0, 1.0);
            shadingNormal = normalize(mix(shadingNormal, geometryNormal, facingBlend), geometryNormal);
            float slopeMagnitude = sqrt(dot(waterSlope, waterSlope) + unresolvedVariance);
            material.roughness = clamp(0.008 + 0.030 * slopeMagnitude, 0.008, 0.018);
        } else {
            shadingNormal = geometryNormal;
            material.roughness = 0.012;
        }
    } else if (isCloud) {
        material.albedo = vec3(1.0);
        material.f0 = vec3(0.04);
        material.roughness = 1.0;
        material.metallic = 0.0;
        material.transmission = 0.0;
        material.ior = ADV_CLOUD_IOR;
        tint = vec3(1.0);
        emission = vec3(0.0);
        shadingNormal = geometryNormal;
    }

    if (isChunkGeometryBufferIndex(hit.geometryBufferIndex) && !isWater && !isCloud && !isPortal && !isNonReflective) {
        material.albedo = tint;
        applyGroundWetness(material, groundWetness(planePosition, outwardNormal));
        tint = material.albedo;
    }

    surface.isValid = isFinite(position) && isFinite(rayDistance) && rayDistance >= 0.0 && isFinite(geometryNormal) &&
                      isFinite(shadingNormal) && isFinite(tint);
    surface.category = hit.category;
    surface.instanceMask = hit.instanceMask;
    surface.instanceIndex = hit.instanceIndex;
    surface.geometryBufferIndex = hit.geometryBufferIndex;
    surface.primitiveId = hit.primitiveId;
    surface.position = position;
    surface.rayDistance = rayDistance;
    surface.hasPreviousPosition = loadPreviousGeometryWorldPosition(
        hit.geometryBufferIndex, hit.primitiveId, hit.instanceIndex, bary, localPosition, surface.previousPosition);
    if (surface.hasPreviousPosition) { surface.previousPosition += position - planePosition; }
    surface.outwardGeometryNormal = outwardNormal;
    surface.geometryNormal = geometryNormal;
    surface.shadingNormal = shadingNormal;
    surface.albedo = max(tint, vec3(0.0));
    surface.f0 = clamp(material.f0, vec3(0.0), vec3(1.0));
    surface.emission = emission;
    surface.transmissionColor = alphaBlendedTransmission(tint, surfaceAlpha);
    surface.transmission = clamp(material.transmission, 0.0, 1.0);
    surface.roughness = clamp(material.roughness, 0.0, 1.0);
    surface.metallic = clamp(material.metallic, 0.0, 1.0);
    surface.ior = clamp(material.ior, 1.0001, 3.0);
    surface.opacity = clamp(surfaceAlpha, 0.0, 1.0);
    surface.medium = medium;
    surface.isFrontFace = isFrontFace;
    surface.isHand = isHand;
    surface.isCloud = isCloud;
    surface.isWater = isWater;
    surface.isNonReflective = isNonReflective;
    surface.isPortal = isPortal;
    surface.hasParallax = hasParallax;
    surface.isParallaxSideWall = parallaxMapping.isInitialSideWall;
    surface.parallaxNormalTextureId = textureMap.normal;
    surface.parallaxAtlasMin = atlasMin;
    surface.parallaxAtlasMax = atlasMax;
    surface.parallaxReferenceUv = referenceUv;
    surface.parallaxContinuousUv = parallaxMapping.initialContinuousUv;
    surface.parallaxDepth = parallaxMapping.initialHit.depth;
    surface.parallaxMaxDepthWorld = parallaxMapping.maxDepthWorld;
    surface.shouldTraceParallaxHeight = parallaxMapping.shouldTraceLocalHeight;
    surface.parallaxPlanePosition = planePosition;
    surface.parallaxBaseNormal = isFrontFace ? outwardNormal : -outwardNormal;
    surface.parallaxDPdu = dPdu;
    surface.parallaxDPdv = dPdv;
    return surface.isValid;
}

#endif
