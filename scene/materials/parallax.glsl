#ifndef ADV_SCENE_MATERIALS_PARALLAX_GLSL
#define ADV_SCENE_MATERIALS_PARALLAX_GLSL

#include "util/height_map.glsl"

#ifndef ADV_PARALLAX_ENABLED
#    define ADV_PARALLAX_ENABLED 0
#endif
#ifndef ADV_PBR_SAMPLING_MODE
#    define ADV_PBR_SAMPLING_MODE uint(0)
#endif

const float ADV_PARALLAX_MIN_VIEW_DOT = 0.001;
const float ADV_PARALLAX_CLOSE_DISTANCE = 32.0;
const int ADV_PARALLAX_PRIMARY_MAX_STEPS = 32;
const int ADV_PARALLAX_SECONDARY_MAX_STEPS = 32;

struct ParallaxMapping {
    bool hasHeightMapSurface;
    bool shouldTraceLocalHeight;
    float maxDepthWorld;
    HeightMapHit initialHit;
    vec2 initialContinuousUv;
    bool isInitialSideWall;
    vec3 initialGeometricNormal;
    vec3 worldPosition;
    float actualHitDistance;
};

struct ParallaxTraceHit {
    bool hasHit;
    float t;
    vec2 uv;
    vec2 continuousUv;
    float depth;
    bool isSideWall;
    vec3 geometricNormal;
};

struct ParallaxSurfaceState {
    vec2 uv;
    vec2 continuousUv;
    float depth;
    vec3 worldPosition;
    vec3 geometricNormal;
    bool isSideWall;
};

const uint ADV_PARALLAX_VISIBILITY_EXIT_TOP = 0u;
const uint ADV_PARALLAX_VISIBILITY_EXIT_BOUNDARY_CLEAR = 1u;
const uint ADV_PARALLAX_VISIBILITY_BLOCK_LOCAL = 2u;
const uint ADV_PARALLAX_VISIBILITY_BLOCK_BOUNDARY = 3u;

struct ParallaxVisibility {
    uint kind;
    vec3 origin;
    vec3 normal;
    float distance;
};

bool canEvaluateParallaxHeight(bool shouldUseTexture, int normalTextureID, uint packedData, bool isExcludedSurface) {
    return ADV_PARALLAX_ENABLED != 0 && shouldUseTexture && normalTextureID >= 0 && !hasNoHeightSurface(packedData) &&
           getCoordinate(packedData) != 1u && !isExcludedSurface;
}

bool isParallaxVisibilityBlocked(ParallaxVisibility visibility) {
    return visibility.kind == ADV_PARALLAX_VISIBILITY_BLOCK_LOCAL ||
           visibility.kind == ADV_PARALLAX_VISIBILITY_BLOCK_BOUNDARY;
}

ParallaxSurfaceState
makeParallaxSurfaceState(vec2 uv, float depth, vec3 worldPosition, vec3 geometricNormal, bool isSideWall) {
    ParallaxSurfaceState surface;
    surface.uv = uv;
    surface.continuousUv = uv;
    surface.depth = depth;
    surface.worldPosition = worldPosition;
    surface.geometricNormal = geometricNormal;
    surface.isSideWall = isSideWall;
    return surface;
}

ParallaxSurfaceState makeParallaxSurfaceState(
    vec2 uv, vec2 continuousUv, float depth, vec3 worldPosition, vec3 geometricNormal, bool isSideWall) {
    ParallaxSurfaceState surface;
    surface.uv = uv;
    surface.continuousUv = continuousUv;
    surface.depth = depth;
    surface.worldPosition = worldPosition;
    surface.geometricNormal = geometricNormal;
    surface.isSideWall = isSideWall;
    return surface;
}

vec3 calculateParallaxBasePlaneWorldPos(
    vec2 uv, vec2 referenceUv, vec3 referenceWorldPos, vec3 dPduWorld, vec3 dPdvWorld) {
    vec2 uvOffset = uv - referenceUv;
    return referenceWorldPos + dPduWorld * uvOffset.x + dPdvWorld * uvOffset.y;
}

vec3 calculateParallaxHeightWorldPos(vec2 uv,
                                     float depth,
                                     vec2 referenceUv,
                                     vec3 referenceWorldPos,
                                     vec3 dPduWorld,
                                     vec3 dPdvWorld,
                                     vec3 baseGeoNormal) {
    return calculateParallaxBasePlaneWorldPos(uv, referenceUv, referenceWorldPos, dPduWorld, dPdvWorld) -
           baseGeoNormal * depth;
}

void storeParallaxVisibility(uint visibilityKind,
                             vec2 uv,
                             float depth,
                             float travelDistance,
                             vec3 normal,
                             vec2 referenceUv,
                             vec3 referenceWorldPos,
                             vec3 dPduWorld,
                             vec3 dPdvWorld,
                             vec3 baseGeoNormal,
                             out ParallaxVisibility visibility) {
    visibility.kind = visibilityKind;
    visibility.origin =
        calculateParallaxHeightWorldPos(uv, depth, referenceUv, referenceWorldPos, dPduWorld, dPdvWorld, baseGeoNormal);
    visibility.normal = normal;
    visibility.distance = travelDistance;
}

bool shouldTracePrimaryParallaxHeight(float lod, vec3 surfaceWorldPos) {
    vec3 cameraOrigin = worldUBO.cameraEffectedViewMatInv[3].xyz;
    return lod == 0.0 || distance(surfaceWorldPos, cameraOrigin) <= ADV_PARALLAX_CLOSE_DISTANCE;
}

float calculateParallaxBoundaryDistance(
    vec2 continuousUv, vec2 rateUv, vec2 tileMin, vec2 tileMax, out ivec2 boundaryStep) {
    float tU = INF_DISTANCE;
    float tV = INF_DISTANCE;
    boundaryStep = ivec2(0);

    if (rateUv.x > 1e-9) {
        tU = (tileMax.x - continuousUv.x) / rateUv.x;
    } else if (rateUv.x < -1e-9) {
        tU = (tileMin.x - continuousUv.x) / rateUv.x;
    }
    if (rateUv.y > 1e-9) {
        tV = (tileMax.y - continuousUv.y) / rateUv.y;
    } else if (rateUv.y < -1e-9) {
        tV = (tileMin.y - continuousUv.y) / rateUv.y;
    }

    float boundaryT = min(tU, tV);
    if (boundaryT == INF_DISTANCE || boundaryT < -heightMapTraceBias) { return INF_DISTANCE; }
    boundaryT = max(boundaryT, 0.0);

    if (tU <= boundaryT + heightMapTraceBias) { boundaryStep.x = rateUv.x > 0.0 ? 1 : -1; }
    if (tV <= boundaryT + heightMapTraceBias) { boundaryStep.y = rateUv.y > 0.0 ? 1 : -1; }
    if (boundaryStep.x != 0 && boundaryStep.y != 0) {
        if (abs(rateUv.x) > abs(rateUv.y)) {
            boundaryStep.y = 0;
        } else if (abs(rateUv.y) > abs(rateUv.x)) {
            boundaryStep.x = 0;
        }
    }

    return boundaryT;
}

vec2 calculateParallaxClosedBoundaryUv(
    vec2 boundaryContinuousUv, ivec2 boundaryStep, vec2 tileMin, vec2 tileMax, ivec2 textureSize) {
    vec2 texelInset = 0.5 / vec2(max(textureSize, ivec2(1)));
    vec2 tileCenter = 0.5 * (tileMin + tileMax);
    vec2 insideMin = min(tileMin + texelInset, tileCenter);
    vec2 insideMax = max(tileMax - texelInset, tileCenter);
    vec2 uv = clamp(boundaryContinuousUv, tileMin, tileMax);

    if (boundaryStep.x > 0) {
        uv.x = insideMax.x;
    } else if (boundaryStep.x < 0) {
        uv.x = insideMin.x;
    }
    if (boundaryStep.y > 0) {
        uv.y = insideMax.y;
    } else if (boundaryStep.y < 0) {
        uv.y = insideMin.y;
    }

    return clamp(uv, insideMin, insideMax);
}

bool isFiniteParallaxFloat(float scalar) {
    return !isnan(scalar) && !isinf(scalar);
}

bool isFiniteParallaxVec2(vec2 vector) {
    return !any(isnan(vector)) && !any(isinf(vector));
}

bool sampleParallaxBoundaryDepth(sampler2D tex,
                                 vec2 tileMin,
                                 vec2 tileMax,
                                 vec2 boundaryContinuousUv,
                                 ivec2 boundaryStep,
                                 ivec2 textureSize,
                                 float maxDepth,
                                 uint samplingMode,
                                 out vec2 boundaryUv,
                                 out float boundarySurfaceDepth) {
    boundaryUv = calculateParallaxClosedBoundaryUv(boundaryContinuousUv, boundaryStep, tileMin, tileMax, textureSize);
    boundarySurfaceDepth = sampleHeightDepth(tex, boundaryUv, tileMin, tileMax, 0, samplingMode, maxDepth);
    return isFiniteParallaxVec2(boundaryUv) && isFiniteParallaxFloat(boundarySurfaceDepth);
}

bool isParallaxPrimaryBoundaryOccupied(float rayDepth, float boundarySurfaceDepth) {
    return isFiniteParallaxFloat(rayDepth) && isFiniteParallaxFloat(boundarySurfaceDepth) &&
           rayDepth >= boundarySurfaceDepth - heightMapTraceBias;
}

void initParallaxTraceMiss(vec2 uv, vec2 continuousUv, float depth, vec3 geometricNormal, out ParallaxTraceHit hit) {
    hit.hasHit = false;
    hit.t = INF_DISTANCE;
    hit.uv = uv;
    hit.continuousUv = continuousUv;
    hit.depth = depth;
    hit.isSideWall = false;
    hit.geometricNormal = geometricNormal;
}

void copyParallaxTraceHitToHeightMapHit(ParallaxTraceHit source, out HeightMapHit target) {
    target.hit = source.hasHit;
    target.t = source.t;
    target.uv = source.uv;
    target.depth = source.depth;
}

vec2 calculateTexelCenterUv(ivec2 texel, ivec2 size) {
    return (vec2(texel) + vec2(0.5)) / vec2(size);
}

vec3 calculateParallaxSideWallNormal(
    ivec2 texelStep, vec3 worldDir, vec3 dPduWorld, vec3 dPdvWorld, vec3 baseGeoNormal) {
    vec3 normal = vec3(0.0);
    if (texelStep.x != 0) {
        vec3 fallback = -float(texelStep.x) * normalizeF(dPduWorld, baseGeoNormal);
        normal += float(texelStep.x) * normalizeF(cross(dPdvWorld, -baseGeoNormal), fallback);
    }
    if (texelStep.y != 0) {
        vec3 fallback = -float(texelStep.y) * normalizeF(dPdvWorld, baseGeoNormal);
        normal += float(texelStep.y) * normalizeF(cross(-baseGeoNormal, dPduWorld), fallback);
    }

    normal = normalizeF(normal, baseGeoNormal);
    if (dot(normal, worldDir) > 0.0) { normal = -normal; }
    return normal;
}

void storeParallaxTopHit(
    float t, vec2 uv, vec2 continuousUv, float depth, vec3 baseGeoNormal, out ParallaxTraceHit hit) {
    hit.hasHit = true;
    hit.t = t;
    hit.uv = uv;
    hit.continuousUv = continuousUv;
    hit.depth = depth;
    hit.isSideWall = false;
    hit.geometricNormal = baseGeoNormal;
}

void storeParallaxSideWallHit(
    float t, vec2 uv, vec2 continuousUv, float depth, vec3 geometricNormal, out ParallaxTraceHit hit) {
    hit.hasHit = true;
    hit.t = t;
    hit.uv = uv;
    hit.continuousUv = continuousUv;
    hit.depth = depth;
    hit.isSideWall = true;
    hit.geometricNormal = geometricNormal;
}

bool traceNearestHeightMapLimited(sampler2D tex,
                                  vec2 minUV,
                                  vec2 maxUV,
                                  vec2 uv,
                                  vec2 continuousUv,
                                  float depth,
                                  vec3 worldDir,
                                  vec3 dPdu,
                                  vec3 dPdv,
                                  vec3 baseNormal,
                                  float maxDepth,
                                  int maxTraceSteps,
                                  float maxDistance,
                                  out bool hasReachedTraceLimit,
                                  out ParallaxTraceHit hit) {
    initParallaxTraceMiss(uv, continuousUv, depth, baseNormal, hit);
    hasReachedTraceLimit = false;
    if (maxTraceSteps <= 0 || maxDepth <= heightMapMinWorldDepth) { return false; }

    ivec2 size = textureSize(tex, 0);
    if (size.x <= 0 || size.y <= 0) { return false; }

    vec2 boundsMin = heightMapMinUV(minUV, maxUV, size);
    vec2 boundsMax = heightMapMaxUV(minUV, maxUV, size);
    vec2 rateUV = directionToRateUv(worldDir, dPdu, dPdv);
    float depthRate = dot(worldDir, -baseNormal);

    ivec2 atlasTexelMin = clampTexelCoord(ivec2(floor(min(minUV, maxUV) * vec2(size))), size);
    ivec2 atlasTexelMax = clampTexelCoord(ivec2(ceil(max(minUV, maxUV) * vec2(size)) - vec2(1.0)), size);

    vec2 uvCurrent = wrapUvInRect(continuousUv, boundsMin, boundsMax);
    vec2 continuousCurrent = continuousUv;
    ivec2 texel = wrapTexelInRect(ivec2(floor(uvCurrent * vec2(size))), atlasTexelMin, atlasTexelMax);

    int maxSteps = min(maxTraceSteps, heightMapNearestMaxSteps);
    if (maxSteps <= 0) { return false; }

    float tCurrent = 0.0;
    float depthCurrent = depth;

    int step = 0;
    while (step < maxSteps) {
        if (tCurrent > maxDistance + heightMapTraceBias || depthCurrent < -heightMapTraceBias) {
            hasReachedTraceLimit = true;
            return false;
        }

        float surfaceDepth = sampleHeightDepthNearest(tex, texel, atlasTexelMin, atlasTexelMax, uvCurrent, maxDepth);
        if (depthCurrent >= surfaceDepth - heightMapTraceBias) {
            storeParallaxTopHit(tCurrent, uvCurrent, continuousCurrent, max(depthCurrent, surfaceDepth), baseNormal,
                                hit);
            return true;
        }

        if (maxDistance <= heightMapTraceBias || tCurrent >= maxDistance - heightMapTraceBias) {
            hasReachedTraceLimit = true;
            return false;
        }

        float tTop = INF_DISTANCE;
        if (depthRate > 1e-6 && surfaceDepth > depthCurrent) { tTop = (surfaceDepth - depthCurrent) / depthRate; }

        float tU = INF_DISTANCE;
        float tV = INF_DISTANCE;
        bool shouldStepU = false;
        bool shouldStepV = false;

        if (rateUV.x > 1e-9) {
            float boundary = (float(texel.x + 1)) / float(size.x);
            tU = (boundary - uvCurrent.x) / rateUV.x;
            shouldStepU = true;
        } else if (rateUV.x < -1e-9) {
            float boundary = float(texel.x) / float(size.x);
            tU = (boundary - uvCurrent.x) / rateUV.x;
            shouldStepU = true;
        }

        if (rateUV.y > 1e-9) {
            float boundary = (float(texel.y + 1)) / float(size.y);
            tV = (boundary - uvCurrent.y) / rateUV.y;
            shouldStepV = true;
        } else if (rateUV.y < -1e-9) {
            float boundary = float(texel.y) / float(size.y);
            tV = (boundary - uvCurrent.y) / rateUV.y;
            shouldStepV = true;
        }

        float tAbove = INF_DISTANCE;
        if (depthRate < -1e-6) { tAbove = -depthCurrent / depthRate; }

        float tBoundary = min(tU, tV);
        float remainingDistance = max(maxDistance - tCurrent, 0.0);
        bool isTopHitNext = tTop <= min(tBoundary, tAbove) + heightMapTraceBias && tTop < INF_DISTANCE;
        if (isTopHitNext && tTop <= remainingDistance + heightMapTraceBias) {
            float dt = max(tTop, 0.0);
            vec2 continuousHitUv = continuousCurrent + rateUV * dt;
            vec2 hitUv = wrapUvInRect(continuousHitUv, boundsMin, boundsMax);
            storeParallaxTopHit(tCurrent + dt, hitUv, continuousHitUv, surfaceDepth, baseNormal, hit);
            return true;
        }

        float nextExitOrBoundary = min(tAbove, tBoundary);
        if (nextExitOrBoundary > remainingDistance + heightMapTraceBias || nextExitOrBoundary == INF_DISTANCE) {
            hasReachedTraceLimit = true;
            return false;
        }
        if (tAbove <= tBoundary + heightMapTraceBias) {
            hasReachedTraceLimit = true;
            return false;
        }

        float dt = max(tBoundary, 0.0);
        if (dt > remainingDistance + heightMapTraceBias) {
            hasReachedTraceLimit = true;
            return false;
        }
        tCurrent += dt;

        vec2 boundaryUv = uvCurrent + rateUV * dt;
        vec2 continuousBoundaryUv = continuousCurrent + rateUV * dt;
        float boundaryDepth = depthCurrent + depthRate * dt;

        ivec2 texelStep = ivec2(0);
        if (shouldStepU && abs(tU - tBoundary) <= heightMapTraceBias) { texelStep.x = rateUV.x > 0.0 ? 1 : -1; }
        if (shouldStepV && abs(tV - tBoundary) <= heightMapTraceBias) { texelStep.y = rateUV.y > 0.0 ? 1 : -1; }
        if (texelStep.x != 0 && texelStep.y != 0) {
            if (abs(rateUV.x) > abs(rateUV.y)) {
                texelStep.y = 0;
            } else if (abs(rateUV.y) > abs(rateUV.x)) {
                texelStep.x = 0;
            }
        }

        ivec2 nextTexelUnwrapped = texel + texelStep;
        vec2 nextUv =
            wrapBoundaryUvInRect(boundaryUv, nextTexelUnwrapped, atlasTexelMin, atlasTexelMax, boundsMin, boundsMax);
        ivec2 nextTexel = wrapTexelInRect(nextTexelUnwrapped, atlasTexelMin, atlasTexelMax);
        float nextDepth = sampleHeightDepthNearest(tex, nextTexel, atlasTexelMin, atlasTexelMax, nextUv, maxDepth);

        if (shouldContinueTexelTop(surfaceDepth, nextDepth, boundaryDepth)) {
            storeParallaxTopHit(tCurrent, nextUv, continuousBoundaryUv, surfaceDepth, baseNormal, hit);
            return true;
        }

        if (boundaryDepth >= nextDepth - heightMapTraceBias) {
            vec3 sideNormal = calculateParallaxSideWallNormal(texelStep, worldDir, dPdu, dPdv, baseNormal);
            storeParallaxSideWallHit(tCurrent, calculateTexelCenterUv(nextTexel, size), continuousBoundaryUv,
                                     max(boundaryDepth, nextDepth), sideNormal, hit);
            return true;
        }

        texel = nextTexel;
        uvCurrent = nextUv;
        continuousCurrent = continuousBoundaryUv;
        depthCurrent = boundaryDepth;
        ++step;
    }

    hasReachedTraceLimit = tCurrent >= maxDistance - heightMapTraceBias || depthCurrent < -heightMapTraceBias;
    return false;
}

void copyBilinearHeightHit(
    HeightMapHit source, vec2 startContinuousUv, vec2 rateUV, vec3 baseGeoNormal, out ParallaxTraceHit hit) {
    initParallaxTraceMiss(source.uv, startContinuousUv, source.depth, baseGeoNormal, hit);
    hit.hasHit = source.hit;
    hit.t = source.t;
    hit.uv = source.uv;
    hit.continuousUv = startContinuousUv + rateUV * source.t;
    hit.depth = source.depth;
    hit.geometricNormal = baseGeoNormal;
}

float resolveFiniteParallaxTraceDistance(float depth, float depthRate, float maxDepth, float requestedDistance) {
    if (isFiniteParallaxFloat(requestedDistance) && requestedDistance < INF_DISTANCE * 0.25) {
        return max(requestedDistance, 0.0);
    }

    if (depthRate > 1e-6) { return max((maxDepth - depth) / depthRate, 0.0); }
    if (depthRate < -1e-6) { return max(depth / -depthRate, 0.0); }
    return 0.0;
}

bool canTraceParallaxDistanceExactly(sampler2D tex,
                                     vec2 rateUV,
                                     float depthRate,
                                     float maxDepth,
                                     float maxDistance,
                                     uint samplingMode,
                                     int maxTraceSteps) {
    if (!isFiniteParallaxFloat(maxDistance) || !isFiniteParallaxVec2(rateUV) || !isFiniteParallaxFloat(depthRate) ||
        maxTraceSteps <= 0) {
        return false;
    }
    if (maxDistance <= heightMapTraceBias) { return true; }

    ivec2 size = textureSize(tex, 0);
    if (size.x <= 0 || size.y <= 0) { return false; }

    float requiredSteps;
    int availableSteps;
    if (samplingMode == 0u) {
        vec2 texelDistance = abs(rateUV) * vec2(size) * maxDistance;
        requiredSteps = ceil(texelDistance.x) + ceil(texelDistance.y) + 2.0;
        availableSteps = min(maxTraceSteps, heightMapNearestMaxSteps);
    } else {
        float texelTravel = max(abs(rateUV.x) * float(size.x), abs(rateUV.y) * float(size.y));
        float depthTravel = abs(depthRate) / max(maxDepth, heightMapMinWorldDepth) * float(max(size.x, size.y));
        float stepWorld = 0.5 / max(max(texelTravel, depthTravel), 1e-4);
        requiredSteps = ceil(maxDistance / stepWorld);
        availableSteps = min(maxTraceSteps, heightMapBilinearMaxSteps);
    }

    return requiredSteps <= float(max(availableSteps, 0));
}

bool traceLayeredParallaxHeightMap(sampler2D tex,
                                   vec2 minUV,
                                   vec2 maxUV,
                                   vec2 continuousUv,
                                   float depth,
                                   vec3 worldDir,
                                   vec3 dPdu,
                                   vec3 dPdv,
                                   vec3 baseNormal,
                                   float maxDepth,
                                   float maxDistance,
                                   uint samplingMode,
                                   int maxTraceSteps,
                                   out bool hasReachedTraceLimit,
                                   out ParallaxTraceHit hit) {
    vec2 boundsMin = min(minUV, maxUV);
    vec2 boundsMax = max(minUV, maxUV);
    vec2 startUv = wrapUvInRect(continuousUv, boundsMin, boundsMax);
    initParallaxTraceMiss(startUv, continuousUv, depth, baseNormal, hit);
    hasReachedTraceLimit = false;
    if (maxTraceSteps <= 0 || maxDepth <= heightMapMinWorldDepth) { return false; }

    ivec2 size = textureSize(tex, 0);
    if (size.x <= 0 || size.y <= 0) { return false; }

    vec2 rateUV = directionToRateUv(worldDir, dPdu, dPdv);
    float depthRate = dot(worldDir, -baseNormal);
    if (!isFiniteParallaxVec2(rateUV) || !isFiniteParallaxFloat(depthRate)) { return false; }

    float traceDistance = resolveFiniteParallaxTraceDistance(depth, depthRate, maxDepth, maxDistance);
    if (!isFiniteParallaxFloat(traceDistance)) { return false; }

    float startSurfaceDepth = sampleHeightDepth(tex, startUv, boundsMin, boundsMax, 0, samplingMode, maxDepth);
    if (!isFiniteParallaxFloat(startSurfaceDepth)) { return false; }
    if (depth >= startSurfaceDepth - heightMapTraceBias) {
        storeParallaxTopHit(0.0, startUv, continuousUv, max(depth, startSurfaceDepth), baseNormal, hit);
        return true;
    }
    if (traceDistance <= heightMapTraceBias) {
        hasReachedTraceLimit = true;
        return false;
    }

    int layerCount =
        max(1, min(maxTraceSteps, samplingMode == 0u ? heightMapNearestMaxSteps : heightMapBilinearMaxSteps));
    float tPrev = 0.0;
    for (int layer = 1; layer <= layerCount; ++layer) {
        float tCurrent = traceDistance * (float(layer) / float(layerCount));
        vec2 continuousCurrentUv = continuousUv + rateUV * tCurrent;
        vec2 currentUv = wrapUvInRect(continuousCurrentUv, boundsMin, boundsMax);
        float depthCurrent = depth + depthRate * tCurrent;
        float surfaceCurrent = sampleHeightDepth(tex, currentUv, boundsMin, boundsMax, 0, samplingMode, maxDepth);
        if (!isFiniteParallaxFloat(depthCurrent) || !isFiniteParallaxFloat(surfaceCurrent)) { return false; }

        if (depthCurrent >= surfaceCurrent - heightMapTraceBias) {
            float lowerT = tPrev;
            float upperT = tCurrent;
            for (int refine = 0; refine < heightMapBilinearBinarySteps; ++refine) {
                float middleT = 0.5 * (lowerT + upperT);
                vec2 middleUv = wrapUvInRect(continuousUv + rateUV * middleT, boundsMin, boundsMax);
                float middleDepth = depth + depthRate * middleT;
                float middleSurface = sampleHeightDepth(tex, middleUv, boundsMin, boundsMax, 0, samplingMode, maxDepth);
                if (middleDepth >= middleSurface - heightMapTraceBias) {
                    upperT = middleT;
                } else {
                    lowerT = middleT;
                }
            }

            float hitT = upperT;
            vec2 continuousHitUv = continuousUv + rateUV * hitT;
            vec2 hitUv = wrapUvInRect(continuousHitUv, boundsMin, boundsMax);
            float hitDepth = sampleHeightDepth(tex, hitUv, boundsMin, boundsMax, 0, samplingMode, maxDepth);
            storeParallaxTopHit(hitT, hitUv, continuousHitUv, hitDepth, baseNormal, hit);
            return true;
        }

        tPrev = tCurrent;
    }

    hasReachedTraceLimit = true;
    return false;
}

bool traceParallaxHeightMap(sampler2D tex,
                            vec2 minUV,
                            vec2 maxUV,
                            vec2 uv,
                            vec2 continuousUv,
                            float depth,
                            vec3 worldDir,
                            vec3 dPdu,
                            vec3 dPdv,
                            vec3 baseNormal,
                            float maxDepth,
                            float maxDistance,
                            uint samplingMode,
                            int maxTraceSteps,
                            out bool hasReachedTraceLimit,
                            out ParallaxTraceHit hit) {
    vec2 rateUV = directionToRateUv(worldDir, dPdu, dPdv);
    float depthRate = dot(worldDir, -baseNormal);
    float finiteDistance = resolveFiniteParallaxTraceDistance(depth, depthRate, maxDepth, maxDistance);
    bool shouldUseExactTrace =
        canTraceParallaxDistanceExactly(tex, rateUV, depthRate, maxDepth, finiteDistance, samplingMode, maxTraceSteps);
    hasReachedTraceLimit = false;

    if (!shouldUseExactTrace) {
        return traceLayeredParallaxHeightMap(tex, minUV, maxUV, continuousUv, depth, worldDir, dPdu, dPdv, baseNormal,
                                             maxDepth, finiteDistance, samplingMode, maxTraceSteps,
                                             hasReachedTraceLimit, hit);
    }

    if (samplingMode == 0u) {
        return traceNearestHeightMapLimited(tex, minUV, maxUV, uv, continuousUv, depth, worldDir, dPdu, dPdv,
                                            baseNormal, maxDepth, maxTraceSteps, finiteDistance, hasReachedTraceLimit,
                                            hit);
    }

    HeightMapHit bilinearHit;
    bool hasHit = traceBilinearHeightMapLimited(tex, minUV, maxUV, uv, depth, worldDir, dPdu, dPdv, baseNormal,
                                                maxDepth, finiteDistance, maxTraceSteps, bilinearHit);
    copyBilinearHeightHit(bilinearHit, continuousUv, directionToRateUv(worldDir, dPdu, dPdv), baseNormal, hit);
    hasReachedTraceLimit = !hasHit;
    return hasHit;
}

bool tracePrimaryParallaxHeightMap(sampler2D tex,
                                   vec2 minUV,
                                   vec2 maxUV,
                                   vec2 uv,
                                   vec2 continuousUv,
                                   float depth,
                                   vec3 worldDir,
                                   vec3 dPdu,
                                   vec3 dPdv,
                                   vec3 baseNormal,
                                   float maxDepth,
                                   uint samplingMode,
                                   int maxTraceSteps,
                                   out ParallaxTraceHit hit) {
    initParallaxTraceMiss(uv, continuousUv, depth, baseNormal, hit);
    if (maxTraceSteps <= 0 || maxDepth <= heightMapMinWorldDepth) { return false; }

    ivec2 size = textureSize(tex, 0);
    if (size.x <= 0 || size.y <= 0) { return false; }

    vec2 tileMin = heightMapMinUV(minUV, maxUV, size);
    vec2 tileMax = heightMapMaxUV(minUV, maxUV, size);
    vec2 rateUv = directionToRateUv(worldDir, dPdu, dPdv);
    float depthRate = dot(worldDir, -baseNormal);
    if (!isFiniteParallaxVec2(rateUv) || !isFiniteParallaxFloat(depthRate)) { return false; }
    ivec2 boundaryStep;
    float boundaryT = calculateParallaxBoundaryDistance(continuousUv, rateUv, tileMin, tileMax, boundaryStep);
    float topExitT = depthRate < -1e-6 ? max(depth / -depthRate, 0.0) : INF_DISTANCE;

    if (boundaryT <= heightMapTraceBias && boundaryT < INF_DISTANCE * 0.25 &&
        boundaryT <= topExitT + heightMapTraceBias) {
        vec2 boundaryContinuousUv = continuousUv + rateUv * max(boundaryT, 0.0);
        float boundaryDepth = depth + depthRate * max(boundaryT, 0.0);
        vec2 boundaryUv;
        float boundarySurfaceDepth;
        if (sampleParallaxBoundaryDepth(tex, tileMin, tileMax, boundaryContinuousUv, boundaryStep, size, maxDepth,
                                        samplingMode, boundaryUv, boundarySurfaceDepth) &&
            isParallaxPrimaryBoundaryOccupied(boundaryDepth, boundarySurfaceDepth)) {
            vec3 sideNormal = calculateParallaxSideWallNormal(boundaryStep, worldDir, dPdu, dPdv, baseNormal);
            storeParallaxSideWallHit(max(boundaryT, 0.0), boundaryUv, boundaryContinuousUv,
                                     max(boundaryDepth, boundarySurfaceDepth), sideNormal, hit);
            return true;
        }
        return false;
    }

    float maxTraceDistance = min(topExitT, boundaryT);
    if (maxTraceDistance == INF_DISTANCE) { maxTraceDistance = INF_DISTANCE * 0.5; }
    float interiorTraceDistance = max(maxTraceDistance - 2.0 * heightMapTraceBias, 0.0);
    int traceStepBudget = heightMapTraceStepBudget(tex, tileMin, tileMax, maxTraceSteps);
    bool hasReachedTraceLimit;
    if (traceParallaxHeightMap(tex, tileMin, tileMax, uv, continuousUv, depth, worldDir, dPdu, dPdv, baseNormal,
                               maxDepth, interiorTraceDistance, samplingMode, traceStepBudget, hasReachedTraceLimit,
                               hit)) {
        return true;
    }
    if (!hasReachedTraceLimit) { return false; }

    if (boundaryT < INF_DISTANCE * 0.25 && boundaryT <= topExitT + heightMapTraceBias) {
        vec2 boundaryContinuousUv = continuousUv + rateUv * boundaryT;
        float boundaryDepth = depth + depthRate * boundaryT;
        vec2 boundaryUv;
        float boundarySurfaceDepth;
        if (sampleParallaxBoundaryDepth(tex, tileMin, tileMax, boundaryContinuousUv, boundaryStep, size, maxDepth,
                                        samplingMode, boundaryUv, boundarySurfaceDepth) &&
            isParallaxPrimaryBoundaryOccupied(boundaryDepth, boundarySurfaceDepth)) {
            vec3 sideNormal = calculateParallaxSideWallNormal(boundaryStep, worldDir, dPdu, dPdv, baseNormal);
            storeParallaxSideWallHit(boundaryT, boundaryUv, boundaryContinuousUv,
                                     max(boundaryDepth, boundarySurfaceDepth), sideNormal, hit);
            return true;
        }
    }

    return false;
}

void traceLocalHeightVisibility(int normalTextureID,
                                vec2 atlasUvMin,
                                vec2 atlasUvMax,
                                vec2 referenceUv,
                                vec3 referenceWorldPos,
                                vec3 dPduWorld,
                                vec3 dPdvWorld,
                                vec3 baseGeoNormal,
                                float maxDepthWorld,
                                ParallaxSurfaceState surface,
                                vec3 worldDir,
                                int maxTraceSteps,
                                out ParallaxVisibility visibility) {
    storeParallaxVisibility(ADV_PARALLAX_VISIBILITY_EXIT_TOP, surface.continuousUv, surface.depth, 0.0,
                            surface.geometricNormal, referenceUv, referenceWorldPos, dPduWorld, dPdvWorld,
                            baseGeoNormal, visibility);
    if (normalTextureID < 0 || maxDepthWorld <= heightMapMinWorldDepth) { return; }

    ivec2 heightMapSize = textureSize(textures[nonuniformEXT(normalTextureID)], 0);
    if (heightMapSize.x <= 0 || heightMapSize.y <= 0) { return; }
    vec2 traceAtlasUvMin = heightMapMinUV(atlasUvMin, atlasUvMax, heightMapSize);
    vec2 traceAtlasUvMax = heightMapMaxUV(atlasUvMin, atlasUvMax, heightMapSize);
    int traceStepBudget = heightMapTraceStepBudget(textures[nonuniformEXT(normalTextureID)], traceAtlasUvMin,
                                                   traceAtlasUvMax, maxTraceSteps);

    float startBias = 2.0 * heightMapTraceBias;
    vec2 rateUV = directionToRateUv(worldDir, dPduWorld, dPdvWorld);
    float depthRate = dot(worldDir, -baseGeoNormal);
    if (!isFiniteParallaxVec2(rateUV) || !isFiniteParallaxFloat(depthRate)) { return; }
    vec2 tileMin = traceAtlasUvMin;
    vec2 tileMax = traceAtlasUvMax;
    bool isSourceOutsideTile = any(lessThan(surface.continuousUv, tileMin - vec2(heightMapTraceBias))) ||
                               any(greaterThan(surface.continuousUv, tileMax + vec2(heightMapTraceBias)));
    if (isSourceOutsideTile) {
        visibility.kind = ADV_PARALLAX_VISIBILITY_EXIT_TOP;
        visibility.origin = surface.worldPosition;
        visibility.normal = surface.geometricNormal;
        visibility.distance = 0.0;
        return;
    }

    ivec2 boundaryStep;
    float sourceBoundaryT =
        calculateParallaxBoundaryDistance(surface.continuousUv, rateUV, tileMin, tileMax, boundaryStep);
    if (sourceBoundaryT <= startBias + heightMapTraceBias && sourceBoundaryT < INF_DISTANCE * 0.25) {
        float boundaryDistance = max(sourceBoundaryT, 0.0);
        vec2 boundaryContinuousUv = surface.continuousUv + rateUV * boundaryDistance;
        float boundaryDepth = surface.depth + depthRate * boundaryDistance;
        float sourceTopExitT = depthRate < -1e-6 ? max(surface.depth / -depthRate, 0.0) : INF_DISTANCE;
        if (sourceTopExitT + heightMapTraceBias < sourceBoundaryT) {
            vec2 exitContinuousUv = surface.continuousUv + rateUV * sourceTopExitT;
            storeParallaxVisibility(ADV_PARALLAX_VISIBILITY_EXIT_TOP, exitContinuousUv, 0.0, sourceTopExitT,
                                    baseGeoNormal, referenceUv, referenceWorldPos, dPduWorld, dPdvWorld, baseGeoNormal,
                                    visibility);
        } else if (surface.isSideWall && dot(worldDir, surface.geometricNormal) > 0.0) {
            storeParallaxVisibility(ADV_PARALLAX_VISIBILITY_EXIT_BOUNDARY_CLEAR, boundaryContinuousUv,
                                    max(boundaryDepth, 0.0), boundaryDistance, surface.geometricNormal, referenceUv,
                                    referenceWorldPos, dPduWorld, dPdvWorld, baseGeoNormal, visibility);
        } else {
            vec3 sideNormal =
                calculateParallaxSideWallNormal(boundaryStep, worldDir, dPduWorld, dPdvWorld, baseGeoNormal);
            storeParallaxVisibility(ADV_PARALLAX_VISIBILITY_BLOCK_BOUNDARY, boundaryContinuousUv,
                                    max(boundaryDepth, 0.0), boundaryDistance, sideNormal, referenceUv,
                                    referenceWorldPos, dPduWorld, dPdvWorld, baseGeoNormal, visibility);
        }
        return;
    }

    vec2 continuousUv = surface.continuousUv + rateUV * startBias;
    vec2 uv = wrapUvInRect(continuousUv, traceAtlasUvMin, traceAtlasUvMax);
    float depth = surface.depth + depthRate * startBias;
    if (dot(surface.geometricNormal, baseGeoNormal) > 0.5 && depthRate < 0.0) {
        depth = min(depth, surface.depth - startBias);
    }

    float boundaryT = max(sourceBoundaryT - startBias, 0.0);
    float topExitT = depthRate < -1e-6 ? max(depth / -depthRate, 0.0) : INF_DISTANCE;
    float maxTraceDistance = min(topExitT, boundaryT);
    if (maxTraceDistance == INF_DISTANCE) { maxTraceDistance = INF_DISTANCE * 0.5; }
    float interiorTraceDistance = max(maxTraceDistance - 2.0 * heightMapTraceBias, 0.0);

    bool shouldFallbackToBilinear =
        ADV_PBR_SAMPLING_MODE == 0u && shouldFallbackNearestSecondaryToBilinear(worldDir, baseGeoNormal);
    ParallaxTraceHit localHit;
    bool hasReachedTraceLimit;
    uint traceSamplingMode = shouldFallbackToBilinear ? 1u : ADV_PBR_SAMPLING_MODE;
    bool isLocallyBlocked = traceParallaxHeightMap(textures[nonuniformEXT(normalTextureID)], traceAtlasUvMin,
                                                   traceAtlasUvMax, uv, continuousUv, depth, worldDir, dPduWorld,
                                                   dPdvWorld, baseGeoNormal, maxDepthWorld, interiorTraceDistance,
                                                   traceSamplingMode, traceStepBudget, hasReachedTraceLimit, localHit);
    if (isLocallyBlocked) {
        storeParallaxVisibility(ADV_PARALLAX_VISIBILITY_BLOCK_LOCAL, localHit.continuousUv, localHit.depth,
                                startBias + localHit.t, localHit.geometricNormal, referenceUv, referenceWorldPos,
                                dPduWorld, dPdvWorld, baseGeoNormal, visibility);
        return;
    }
    if (!hasReachedTraceLimit) { return; }

    if (topExitT + heightMapTraceBias < boundaryT) {
        vec2 exitContinuousUv = continuousUv + rateUV * topExitT;
        storeParallaxVisibility(ADV_PARALLAX_VISIBILITY_EXIT_TOP, exitContinuousUv, 0.0, startBias + topExitT,
                                baseGeoNormal, referenceUv, referenceWorldPos, dPduWorld, dPdvWorld, baseGeoNormal,
                                visibility);
        return;
    }

    if (boundaryT < INF_DISTANCE * 0.25) {
        vec2 boundaryContinuousUv = continuousUv + rateUV * boundaryT;
        float boundaryDepth = depth + depthRate * boundaryT;
        vec3 sideNormal = calculateParallaxSideWallNormal(boundaryStep, worldDir, dPduWorld, dPdvWorld, baseGeoNormal);
        storeParallaxVisibility(ADV_PARALLAX_VISIBILITY_BLOCK_BOUNDARY, boundaryContinuousUv, max(boundaryDepth, 0.0),
                                startBias + boundaryT, sideNormal, referenceUv, referenceWorldPos, dPduWorld, dPdvWorld,
                                baseGeoNormal, visibility);
        return;
    }
}

void initializeParallaxMapping(bool shouldUseTexture,
                               int normalTextureID,
                               uint packedData,
                               vec2 atlasUvMin,
                               vec2 atlasUvMax,
                               vec2 uv,
                               float lod,
                               vec3 dPduWorld,
                               vec3 dPdvWorld,
                               vec3 baseGeoNormal,
                               vec3 planeHitWorldPos,
                               vec3 rayDirection,
                               vec3 viewDir,
                               float planeHitT,
                               bool isExcludedSurface,
                               out ParallaxMapping parallaxMapping) {
    parallaxMapping.hasHeightMapSurface = false;
    parallaxMapping.shouldTraceLocalHeight = false;
    parallaxMapping.maxDepthWorld = 0.0;
    parallaxMapping.initialHit.hit = false;
    parallaxMapping.initialHit.t = 0.0;
    parallaxMapping.initialHit.uv = uv;
    parallaxMapping.initialHit.depth = 0.0;
    parallaxMapping.initialContinuousUv = uv;
    parallaxMapping.isInitialSideWall = false;
    parallaxMapping.initialGeometricNormal = baseGeoNormal;
    parallaxMapping.worldPosition = planeHitWorldPos;
    parallaxMapping.actualHitDistance = planeHitT;

#if ADV_PARALLAX_ENABLED == 0
    return;
#endif

    bool canEvaluateHeight =
        canEvaluateParallaxHeight(shouldUseTexture, normalTextureID, packedData, isExcludedSurface);
    if (!canEvaluateHeight) { return; }

    parallaxMapping.maxDepthWorld = heightMapMaxDepthWorld(atlasUvMin, atlasUvMax, dPduWorld, dPdvWorld);
    parallaxMapping.hasHeightMapSurface = parallaxMapping.maxDepthWorld > heightMapMinWorldDepth &&
                                          dot(viewDir, baseGeoNormal) > ADV_PARALLAX_MIN_VIEW_DOT;
    parallaxMapping.shouldTraceLocalHeight =
        parallaxMapping.hasHeightMapSurface && shouldTracePrimaryParallaxHeight(lod, planeHitWorldPos);
    if (!parallaxMapping.shouldTraceLocalHeight) { return; }

    ParallaxTraceHit tracedInitialHit;
    if (tracePrimaryParallaxHeightMap(textures[nonuniformEXT(normalTextureID)], atlasUvMin, atlasUvMax, uv, uv, 0.0,
                                      rayDirection, dPduWorld, dPdvWorld, baseGeoNormal, parallaxMapping.maxDepthWorld,
                                      ADV_PBR_SAMPLING_MODE, ADV_PARALLAX_PRIMARY_MAX_STEPS, tracedInitialHit)) {
        copyParallaxTraceHitToHeightMapHit(tracedInitialHit, parallaxMapping.initialHit);
        parallaxMapping.initialContinuousUv = tracedInitialHit.continuousUv;
        parallaxMapping.isInitialSideWall = tracedInitialHit.isSideWall;
        parallaxMapping.initialGeometricNormal = tracedInitialHit.geometricNormal;
        parallaxMapping.worldPosition = planeHitWorldPos + rayDirection * tracedInitialHit.t;
        parallaxMapping.actualHitDistance = planeHitT + tracedInitialHit.t;
    }
}

void resolveParallaxVisibility(int normalTextureID,
                               vec2 atlasUvMin,
                               vec2 atlasUvMax,
                               vec2 referenceUv,
                               vec3 referenceWorldPos,
                               vec3 dPduWorld,
                               vec3 dPdvWorld,
                               vec3 baseGeoNormal,
                               float maxDepthWorld,
                               bool shouldTraceLocalHeight,
                               ParallaxSurfaceState surface,
                               vec3 worldDir,
                               int maxTraceSteps,
                               out ParallaxVisibility visibility) {
    visibility.kind = ADV_PARALLAX_VISIBILITY_EXIT_TOP;
    visibility.origin = surface.worldPosition;
    visibility.normal = surface.geometricNormal;
    visibility.distance = 0.0;

#if ADV_PARALLAX_ENABLED == 0
    return;
#endif

    if (!shouldTraceLocalHeight) {
        if (maxDepthWorld > heightMapMinWorldDepth) {
            visibility.origin = calculateParallaxBasePlaneWorldPos(surface.continuousUv, referenceUv, referenceWorldPos,
                                                                   dPduWorld, dPdvWorld);
            visibility.normal = baseGeoNormal;
        }
        return;
    }

    traceLocalHeightVisibility(normalTextureID, atlasUvMin, atlasUvMax, referenceUv, referenceWorldPos, dPduWorld,
                               dPdvWorld, baseGeoNormal, maxDepthWorld, surface, worldDir, maxTraceSteps, visibility);
}

bool resolveParallaxExitOrigin(int normalTextureID,
                               vec2 atlasUvMin,
                               vec2 atlasUvMax,
                               vec2 referenceUv,
                               vec3 referenceWorldPos,
                               vec3 dPduWorld,
                               vec3 dPdvWorld,
                               vec3 baseGeoNormal,
                               float maxDepthWorld,
                               bool shouldTraceLocalHeight,
                               ParallaxSurfaceState surface,
                               vec3 worldDir,
                               int maxTraceSteps,
                               out vec3 originPos,
                               out vec3 originNormal) {
    ParallaxVisibility visibility;
    resolveParallaxVisibility(normalTextureID, atlasUvMin, atlasUvMax, referenceUv, referenceWorldPos, dPduWorld,
                              dPdvWorld, baseGeoNormal, maxDepthWorld, shouldTraceLocalHeight, surface, worldDir,
                              maxTraceSteps, visibility);
    originPos = visibility.origin;
    originNormal = visibility.normal;
    return !isParallaxVisibilityBlocked(visibility);
}

#endif
