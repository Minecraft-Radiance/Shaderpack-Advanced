#ifndef ADV_PATH_STATE_GLSL
#define ADV_PATH_STATE_GLSL

#include "path/budget.glsl"
#include "path/primary/hit_buffer.glsl"
#include "scene/surface.glsl"
#include "scene/camera.glsl"
#include "path/types.glsl"

#ifdef ADV_PATH_RECORD_WRITE
#    define ADV_PATH_RECORD_ACCESS writeonly
#    define ADV_PATH_HIT_DISTANCE_ACCESS writeonly
#elif defined(ADV_PATH_HIT_DISTANCE_WRITE)
#    define ADV_PATH_RECORD_ACCESS readonly
#    define ADV_PATH_HIT_DISTANCE_ACCESS writeonly
#else
#    define ADV_PATH_RECORD_ACCESS readonly
#    define ADV_PATH_HIT_DISTANCE_ACCESS readonly
#endif

layout(set = 5,
       binding = ADV_PATH_POSITION_LENGTH_BINDING,
       rgba32f) ADV_PATH_RECORD_ACCESS uniform image2D pathPositionLengthImage;
layout(set = 5, binding = ADV_PATH_NORMALS_BINDING, rg32ui) ADV_PATH_RECORD_ACCESS uniform uimage2D pathNormalsImage;
layout(set = 5,
       binding = ADV_PATH_ALBEDO_ROUGHNESS_BINDING,
       rgba16f) ADV_PATH_RECORD_ACCESS uniform image2D pathAlbedoRoughnessImage;
layout(set = 5,
       binding = ADV_PATH_F0_METALLIC_BINDING,
       rgba16f) ADV_PATH_RECORD_ACCESS uniform image2D pathF0MetallicImage;
layout(set = 5,
       binding = ADV_PATH_THROUGHPUT_BINDING,
       rgba16f) ADV_PATH_RECORD_ACCESS uniform image2D pathThroughputImage;
layout(set = 5, binding = ADV_PATH_METADATA_BINDING, rg32ui) ADV_PATH_RECORD_ACCESS uniform uimage2D pathMetadataImage;
layout(set = 5,
       binding = ADV_PATH_TRANSMISSION_DISTANCE_BINDING,
       r32f) ADV_PATH_HIT_DISTANCE_ACCESS uniform image2D pathTransmissionDistanceImage;
layout(set = 5,
       binding = ADV_PATH_RAY_DIRECTION_DEPTH_BINDING,
       rgba16f) ADV_PATH_RECORD_ACCESS uniform image2D pathRayDirectionDepthImage;
layout(set = 5, binding = ADV_PATH_PARALLAX_BINDING, rgba32f) ADV_PATH_RECORD_ACCESS uniform image2D pathParallaxImage;

#undef ADV_PATH_RECORD_ACCESS
#undef ADV_PATH_HIT_DISTANCE_ACCESS

PathRecord invalidPathRecord() {
    PathRecord record;
    record.key = PathKey(0u, 0u);
    record.position = vec3(0.0);
    record.pathLength = 0.0;
    record.shadingNormal = vec3(0.0);
    record.roughness = 1.0;
    record.geometryNormal = vec3(0.0);
    record.albedo = vec3(0.0);
    record.metallic = 0.0;
    record.f0 = vec3(0.0);
    record.parallax = invalidParallaxState();
    record.opacity = 1.0;
    record.throughput = vec3(0.0);
    record.rayDirection = vec3(0.0, 0.0, -1.0);
    record.previousPathDepth = ADV_PRIMARY_TEMPORAL_INVALID_DEPTH;
    record.transparentSpecularHitDistance = 0.0;
    return record;
}

PathKey packPathKey(uint flags,
                    uint splitBounce,
                    uint bounceCount,
                    uint rayBudgetUsed,
                    uint terminalMedium,
                    uint action,
                    uint surfaceMedium,
                    uint category) {
    uint packed = (splitBounce & 0x0fu) | ((bounceCount & 0x0fu) << 4u) | ((terminalMedium & 0x0fu) << 8u) |
                  ((surfaceMedium & 0x0fu) << 12u) | ((action & 0x0fu) << 16u) | ((category & 0x07u) << 20u) |
                  ((rayBudgetUsed & 0x0fu) << 23u);
    return PathKey(flags, packed);
}

uint pathFlags(PathKey key) {
    return key.flags;
}
uint pathSurfaceHash(PathKey key) {
    return (key.flags >> ADV_PATH_SURFACE_HASH_SHIFT) & ADV_PATH_SURFACE_HASH_MASK;
}
uint makePathSurfaceHash(uvec3 identity, bool isDynamic) {
    uint hash = identity.x * 0x9e3779b9u ^ identity.y * 0x85ebca6bu;
    if (isDynamic) { hash ^= identity.z * 0xc2b2ae35u; }
    hash ^= hash >> 16u;
    hash *= 0x7feb352du;
    hash ^= hash >> 15u;
    uint compact = hash & ADV_PATH_SURFACE_HASH_MASK;
    return compact != 0u ? compact : 1u;
}
uint packPathSurfaceHash(uint flags, uint surfaceHash) {
    return flags | ((surfaceHash & ADV_PATH_SURFACE_HASH_MASK) << ADV_PATH_SURFACE_HASH_SHIFT);
}
bool isPathValid(PathKey key) {
    return (pathFlags(key) & ADV_PATH_FLAG_VALID) != 0u;
}
bool isSkyPath(PathKey key) {
    return (pathFlags(key) & ADV_PATH_FLAG_SKY) != 0u;
}
bool isSplitPath(PathKey key) {
    return (pathFlags(key) & ADV_PATH_FLAG_SPLIT) != 0u;
}
uint pathSplitBounce(PathKey key) {
    return key.packed & 0x0fu;
}
uint pathBounceCount(PathKey key) {
    return (key.packed >> 4u) & 0x0fu;
}
uint pathRayBudgetUsed(PathKey key) {
    return (key.packed >> 23u) & 0x0fu;
}
uint pathTerminalMedium(PathKey key) {
    return (key.packed >> 8u) & 0x0fu;
}
uint pathSurfaceMedium(PathKey key) {
    return (key.packed >> 12u) & 0x0fu;
}
uint pathCategory(PathKey key) {
    return (key.packed >> 20u) & 0x07u;
}

bool pathNeedsBackFaceCull(PathKey key) {
    uint flags = pathFlags(key);
    if ((flags & ADV_PATH_FLAG_CLOUD) != 0u) { return false; }
    return (flags & ADV_PATH_FLAG_AFTER_TRANSPARENT) != 0u;
}

#ifdef ADV_PATH_RECORD_WRITE
void storePathRecord(ivec2 packedPixel, PathRecord record) {
    bool hasTransport = any(notEqual(vec4(record.throughput, record.opacity), vec4(1.0)));
    bool hasTransparentDistance =
        record.transparentSpecularHitDistance != 0.0 ||
        (pathFlags(record.key) & (ADV_PATH_FLAG_FIRST_HIT_WATER | ADV_PATH_FLAG_FIRST_HIT_GLASS |
                                  ADV_PATH_FLAG_FIRST_INTERFACE_SPECULAR | ADV_PATH_FLAG_AFTER_TRANSPARENT)) != 0u;
    bool hasParallax = isParallaxStateValid(record.parallax) && record.parallax.hit.x <= ADV_PRIMARY_HIT_INSTANCE_MASK;
    record.key.packed |= hasTransport ? ADV_PATH_STATE_TRANSPORT : 0u;
    record.key.packed |= hasTransparentDistance ? ADV_PATH_STATE_TRANSPARENT_DISTANCE : 0u;
    record.key.packed |= hasParallax ? ADV_PATH_STATE_PARALLAX : 0u;
    record.key.packed |= hasParallax && (record.parallax.hit.w & ADV_PARALLAX_HIT_FLAG_SIDE_WALL) != 0u ?
                             ADV_PATH_STATE_PARALLAX_SIDE_WALL : 0u;
    imageStore(pathPositionLengthImage, packedPixel, vec4(record.position, record.pathLength));
    imageStore(pathNormalsImage, packedPixel,
               uvec4(packPrimaryTemporalNormal(record.shadingNormal), packPrimaryTemporalNormal(record.geometryNormal),
                     0u, 0u));
    imageStore(pathAlbedoRoughnessImage, packedPixel, vec4(record.albedo, record.roughness));
    imageStore(pathF0MetallicImage, packedPixel, vec4(record.f0, record.metallic));
    if (hasTransport) { imageStore(pathThroughputImage, packedPixel, vec4(record.throughput, record.opacity)); }
    imageStore(pathMetadataImage, packedPixel, uvec4(record.key.flags, record.key.packed, 0u, 0u));
    if (hasTransparentDistance) {
        imageStore(pathTransmissionDistanceImage, packedPixel, vec4(record.transparentSpecularHitDistance));
    }
    imageStore(pathRayDirectionDepthImage, packedPixel, vec4(record.rayDirection, record.previousPathDepth));
#    if ADV_PARALLAX_ENABLED != 0
    if (hasParallax) {
        imageStore(pathParallaxImage, packedPixel,
                   vec4(record.parallax.continuousUv, record.parallax.depth, record.parallax.maxDepthWorld));
#        ifdef ADV_PRIMARY_HIT_IDENTITY_READ_WRITE
        uvec4 identity = uvec4(0u);
        if (isParallaxStateValid(record.parallax) && record.parallax.hit.x <= ADV_PRIMARY_HIT_INSTANCE_MASK) {
            uint packedInstance =
                record.parallax.hit.x |
                ((pathCategory(record.key) & ADV_PRIMARY_HIT_CATEGORY_MASK) << ADV_PRIMARY_HIT_CATEGORY_SHIFT) |
                ADV_PRIMARY_HIT_VALID_BIT;
            if ((record.parallax.hit.w & ADV_PARALLAX_HIT_FLAG_FRONT_FACE) != 0u) {
                packedInstance |= ADV_PRIMARY_HIT_FRONT_FACE_BIT;
            }
            identity = uvec4(packedInstance, record.parallax.hit.yz, floatBitsToUint(1.0));
        }
        storePrimaryHitIdentity(packedPixel, identity);
#        endif
    }
#    endif
}
#else
PathKey loadPathKey(ivec2 packedPixel) {
    uvec2 raw = imageLoad(pathMetadataImage, packedPixel).xy;
    return PathKey(raw.x, raw.y);
}

void loadPathNormals(ivec2 packedPixel, out vec3 shadingNormal, out vec3 geometryNormal) {
    uvec2 packed = imageLoad(pathNormalsImage, packedPixel).xy;
    shadingNormal = unpackPrimaryTemporalNormal(packed.x);
    geometryNormal = unpackPrimaryTemporalNormal(packed.y);
}

vec4 loadPathTransport(ivec2 packedPixel, PathKey key) {
    return (key.packed & ADV_PATH_STATE_TRANSPORT) != 0u ? imageLoad(pathThroughputImage, packedPixel) : vec4(1.0);
}

ParallaxState loadPathParallax(ivec2 packedPixel, PathKey key) {
    ParallaxState parallaxState = invalidParallaxState();
#    if ADV_PARALLAX_ENABLED != 0
    if ((key.packed & ADV_PATH_STATE_PARALLAX) == 0u) { return parallaxState; }
    uvec4 identity = loadPrimaryHitIdentity(packedPixel);
    if (!isPrimaryHitIdentityValid(identity)) { return parallaxState; }
    vec4 texel = imageLoad(pathParallaxImage, packedPixel);
    uint flags = (identity.x & ADV_PRIMARY_HIT_FRONT_FACE_BIT) != 0u ? ADV_PARALLAX_HIT_FLAG_FRONT_FACE : 0u;
    if ((key.packed & ADV_PATH_STATE_PARALLAX_SIDE_WALL) != 0u) { flags |= ADV_PARALLAX_HIT_FLAG_SIDE_WALL; }
    parallaxState.hit = uvec4(identity.x & ADV_PRIMARY_HIT_INSTANCE_MASK, identity.y, identity.z, flags);
    parallaxState.continuousUv = texel.xy;
    parallaxState.depth = texel.z;
    parallaxState.maxDepthWorld = texel.w;
#    endif
    return parallaxState;
}

DiffusePath loadDiffusePath(ivec2 packedPixel) {
    DiffusePath path;
    path.key = loadPathKey(packedPixel);
    vec4 positionPath = imageLoad(pathPositionLengthImage, packedPixel);
    path.position = positionPath.xyz;
    path.pathLength = positionPath.w;
    loadPathNormals(packedPixel, path.shadingNormal, path.geometryNormal);
    path.medium = pathTerminalMedium(path.key);
    path.parallax = loadPathParallax(packedPixel, path.key);
    return path;
}

SpecularPath loadSpecularPath(ivec2 packedPixel) {
    SpecularPath path;
    path.key = loadPathKey(packedPixel);
    vec4 positionPath = imageLoad(pathPositionLengthImage, packedPixel);
    path.position = positionPath.xyz;
    path.pathLength = positionPath.w;
    loadPathNormals(packedPixel, path.shadingNormal, path.geometryNormal);
    path.roughness = imageLoad(pathAlbedoRoughnessImage, packedPixel).w;
    path.rayDirection = imageLoad(pathRayDirectionDepthImage, packedPixel).xyz;
    path.medium = pathTerminalMedium(path.key);
    path.parallax = loadPathParallax(packedPixel, path.key);
    return path;
}

TransmissionPath loadTransmissionPath(ivec2 packedPixel) {
    TransmissionPath path;
    path.key = loadPathKey(packedPixel);
    vec4 positionPath = imageLoad(pathPositionLengthImage, packedPixel);
    vec4 albedoRoughness = imageLoad(pathAlbedoRoughnessImage, packedPixel);
    vec4 throughputOpacity = loadPathTransport(packedPixel, path.key);
    path.position = positionPath.xyz;
    path.pathLength = positionPath.w;
    loadPathNormals(packedPixel, path.shadingNormal, path.geometryNormal);
    path.albedo = albedoRoughness.xyz;
    path.opacity = throughputOpacity.w;
    path.rayDirection = imageLoad(pathRayDirectionDepthImage, packedPixel).xyz;
    path.parallax = loadPathParallax(packedPixel, path.key);
    return path;
}

ShadingPath loadShadingPath(ivec2 packedPixel) {
    ShadingPath path;
    path.key = loadPathKey(packedPixel);
    vec4 albedoRoughness = imageLoad(pathAlbedoRoughnessImage, packedPixel);
    vec4 f0Metallic = imageLoad(pathF0MetallicImage, packedPixel);
    vec4 throughputOpacity = loadPathTransport(packedPixel, path.key);
    path.position = imageLoad(pathPositionLengthImage, packedPixel).xyz;
    loadPathNormals(packedPixel, path.shadingNormal, path.geometryNormal);
    path.albedo = albedoRoughness.xyz;
    path.roughness = albedoRoughness.w;
    path.f0 = f0Metallic.xyz;
    path.metallic = f0Metallic.w;
    path.throughput = throughputOpacity.xyz;
    path.opacity = throughputOpacity.w;
    path.rayDirection = imageLoad(pathRayDirectionDepthImage, packedPixel).xyz;
    path.parallax = loadPathParallax(packedPixel, path.key);
    return path;
}

#    ifndef ADV_PATH_HIT_DISTANCE_WRITE
ResolvePath loadResolvePath(ivec2 packedPixel) {
    ResolvePath path;
    path.key = loadPathKey(packedPixel);
    vec4 albedoRoughness = imageLoad(pathAlbedoRoughnessImage, packedPixel);
    vec4 f0Metallic = imageLoad(pathF0MetallicImage, packedPixel);
    vec4 throughputOpacity = loadPathTransport(packedPixel, path.key);
    vec4 positionPath = imageLoad(pathPositionLengthImage, packedPixel);
    path.position = positionPath.xyz;
    path.pathLength = positionPath.w;
    loadPathNormals(packedPixel, path.shadingNormal, path.geometryNormal);
    path.albedo = albedoRoughness.xyz;
    path.roughness = albedoRoughness.w;
    path.f0 = f0Metallic.xyz;
    path.metallic = f0Metallic.w;
    path.throughput = throughputOpacity.xyz;
    path.opacity = throughputOpacity.w;
    vec4 rayDirectionDepth = imageLoad(pathRayDirectionDepthImage, packedPixel);
    path.rayDirection = rayDirectionDepth.xyz;
    path.previousPathDepth = rayDirectionDepth.w;
    path.transparentSpecularHitDistance = (path.key.packed & ADV_PATH_STATE_TRANSPARENT_DISTANCE) != 0u ?
                                              imageLoad(pathTransmissionDistanceImage, packedPixel).x :
                                              0.0;
    return path;
}
#    endif
#endif

#endif
