#ifndef HEIGHT_MAP_GLSL
#define HEIGHT_MAP_GLSL

#include "common/shared.hpp"
#include "sampling_helpers.glsl"

const float heightMapMinWorldDepth = 1e-5;
const float heightMapDepthScaleInTexture = 0.25;
const float heightMapTraceBias = 2e-4;
const float heightMapNearestSecondaryBilinearFallbackDepthRate = 0.02;
const int heightMapNearestMaxSteps = 1024;
const int heightMapBilinearMaxSteps = 24;
const int heightMapBilinearBinarySteps = 5;

int heightMapTraceStepBudget(sampler2D tex, vec2 minUV, vec2 maxUV, int requestedSteps) {
    if (requestedSteps <= 4) { return max(requestedSteps, 1); }
    ivec2 size = textureSize(tex, 0);
    if (size.x <= 0 || size.y <= 0) { return 1; }

    vec2 spritePixels = abs(maxUV - minUV) * vec2(size);
    float maxSpriteResolution = max(spritePixels.x, spritePixels.y);
    int resolutionBudget = maxSpriteResolution >= 256.0 ? 12 : maxSpriteResolution >= 128.0 ? 16 : 24;
    return max(1, min(requestedSteps, resolutionBudget));
}

struct HeightMapHit {
    bool hit;
    float t;
    vec2 uv;
    float depth;
};

vec3 normalizeF(vec3 dir, vec3 fallback) {
    float len2 = dot(dir, dir);
    if (len2 <= 1e-12) { return fallback; }
    return dir * inversesqrt(len2);
}

vec2 directionToRateUv(vec3 dir, vec3 dPdu, vec3 dPdv) {
    float a00 = dot(dPdu, dPdu);
    float a01 = dot(dPdu, dPdv);
    float a11 = dot(dPdv, dPdv);
    float det = a00 * a11 - a01 * a01;
    if (abs(det) <= 1e-12) { return vec2(0.0); }

    float b0 = dot(dPdu, dir);
    float b1 = dot(dPdv, dir);
    return vec2((b0 * a11 - b1 * a01) / det, (b1 * a00 - b0 * a01) / det);
}

float heightMapMaxDepthWorld(vec2 minUV, vec2 maxUV, vec3 dPdu, vec3 dPdv) {
    vec2 uvSpan = abs(maxUV - minUV);
    if (uvSpan.x <= 1e-8 && uvSpan.y <= 1e-8) { return 0.0; }

    float textureWorldU = length(dPdu) * uvSpan.x;
    float textureWorldV = length(dPdv) * uvSpan.y;
    float textureWorldSize = max(textureWorldU, textureWorldV);
    return textureWorldSize * heightMapDepthScaleInTexture;
}

int positiveModInt(int value, int period) {
    if (period <= 0) { return 0; }
    int result = value % period;
    return result < 0 ? result + period : result;
}

ivec2 wrapTexelInRect(ivec2 texel, ivec2 minTexel, ivec2 maxTexel) {
    ivec2 span = max(maxTexel - minTexel + ivec2(1), ivec2(1));
    return minTexel + ivec2(positiveModInt(texel.x - minTexel.x, span.x), positiveModInt(texel.y - minTexel.y, span.y));
}

vec2 wrapUvInRect(vec2 uv, vec2 minUV, vec2 maxUV) {
    vec2 boundsMin = min(minUV, maxUV);
    vec2 boundsMax = max(minUV, maxUV);
    vec2 span = max(boundsMax - boundsMin, vec2(1e-8));
    return boundsMin + fract((uv - boundsMin) / span) * span;
}

vec2 wrapBoundaryUvInRect(vec2 boundaryUv, ivec2 nextTexel, ivec2 minTexel, ivec2 maxTexel, vec2 minUV, vec2 maxUV) {
    vec2 boundsMin = min(minUV, maxUV);
    vec2 boundsMax = max(minUV, maxUV);
    vec2 uv = boundaryUv;

    if (nextTexel.x < minTexel.x) {
        uv.x = boundsMax.x;
    } else if (nextTexel.x > maxTexel.x) {
        uv.x = boundsMin.x;
    }

    if (nextTexel.y < minTexel.y) {
        uv.y = boundsMax.y;
    } else if (nextTexel.y > maxTexel.y) {
        uv.y = boundsMin.y;
    }

    return uv;
}

bool shouldContinueTexelTop(float currentDepth, float enteredDepth, float rayDepth) {
    return abs(enteredDepth - currentDepth) <= heightMapTraceBias && rayDepth >= enteredDepth - heightMapTraceBias;
}

bool shouldFallbackNearestSecondaryToBilinear(vec3 worldDir, vec3 baseNormal) {
    float depthRate = dot(worldDir, -baseNormal);
    return depthRate < 0.0 && -depthRate <= heightMapNearestSecondaryBilinearFallbackDepthRate;
}

float sampleHeightDepthNearest(
    sampler2D tex, ivec2 texel, ivec2 atlasTexelMin, ivec2 atlasTexelMax, vec2 uv, float maxDepth) {
    texel = wrapTexelInRect(texel, atlasTexelMin, atlasTexelMax);
    return (1.0 - clamp(sampleTexture(tex, texel, 0, false).w, 0.0, 1.0)) * maxDepth;
}

vec2 heightMapMinUV(vec2 minUV, vec2 maxUV, ivec2 size) {
    return min(minUV, maxUV);
}

vec2 heightMapMaxUV(vec2 minUV, vec2 maxUV, ivec2 size) {
    return max(minUV, maxUV);
}

float sampleHeight(sampler2D tex, vec2 uv, vec2 minUV, vec2 maxUV, int lodLevel, uint samplingMode) {
    ivec2 size = textureSize(tex, lodLevel);
    if (size.x <= 0 || size.y <= 0) { return 1.0; }

    vec2 sampleUv = wrapUvInRect(uv, minUV, maxUV);
    vec4 pbrValue = samplingMode == 0u ? sampleNearest(tex, sampleUv, lodLevel, false) :
                                         sampleBilinear(tex, sampleUv, lodLevel, false);
    return clamp(pbrValue.w, 0.0, 1.0);
}

float sampleHeightDepth(
    sampler2D tex, vec2 uv, vec2 minUV, vec2 maxUV, int lodLevel, uint samplingMode, float maxDepth) {
    float heightValue = sampleHeight(tex, uv, minUV, maxUV, lodLevel, samplingMode);
    return (1.0 - heightValue) * maxDepth;
}

vec3 sampleNormal(sampler2D tex,
                  vec2 uv,
                  vec2 minUV,
                  vec2 maxUV,
                  vec3 dPdu,
                  vec3 dPdv,
                  vec3 fallbackNormal,
                  int lodLevel,
                  uint samplingMode,
                  float maxDepth,
                  vec3 viewDir) {
    ivec2 size = textureSize(tex, lodLevel);
    if (size.x <= 0 || size.y <= 0 || maxDepth <= heightMapMinWorldDepth) { return fallbackNormal; }

    vec2 texelSize = 1.0 / vec2(size);
    float center = sampleHeightDepth(tex, uv, minUV, maxUV, lodLevel, samplingMode, maxDepth);
    float depthU = sampleHeightDepth(tex, uv + vec2(texelSize.x, 0.0), minUV, maxUV, lodLevel, samplingMode, maxDepth);
    float depthV = sampleHeightDepth(tex, uv + vec2(0.0, texelSize.y), minUV, maxUV, lodLevel, samplingMode, maxDepth);

    vec3 displacedDu = dPdu - fallbackNormal * ((depthU - center) / texelSize.x);
    vec3 displacedDv = dPdv - fallbackNormal * ((depthV - center) / texelSize.y);
    vec3 normal = normalizeF(cross(displacedDu, displacedDv), fallbackNormal);
    if (dot(normal, viewDir) < 0.0) { normal = -normal; }
    return normal;
}

bool traceNearestHeightMapLimited(sampler2D tex,
                                  vec2 minUV,
                                  vec2 maxUV,
                                  vec2 uv,
                                  float depth,
                                  vec3 worldDir,
                                  vec3 dPdu,
                                  vec3 dPdv,
                                  vec3 baseNormal,
                                  float maxDepth,
                                  float maxDistance,
                                  int maxTraceSteps,
                                  out HeightMapHit hit) {
    hit.hit = false;
    hit.t = INF_DISTANCE;
    hit.uv = uv;
    hit.depth = depth;

    if (maxDepth <= heightMapMinWorldDepth) { return false; }

    ivec2 size = textureSize(tex, 0);
    if (size.x <= 0 || size.y <= 0) { return false; }

    vec2 boundsMin = heightMapMinUV(minUV, maxUV, size);
    vec2 boundsMax = heightMapMaxUV(minUV, maxUV, size);
    uv = wrapUvInRect(uv, boundsMin, boundsMax);

    vec2 rateUV = directionToRateUv(worldDir, dPdu, dPdv);
    float depthRate = dot(worldDir, -baseNormal);

    ivec2 atlasTexelMin = clampTexelCoord(ivec2(floor(min(minUV, maxUV) * vec2(size))), size);
    ivec2 atlasTexelMax = clampTexelCoord(ivec2(ceil(max(minUV, maxUV) * vec2(size)) - vec2(1.0)), size);
    ivec2 texel = wrapTexelInRect(ivec2(floor(uv * vec2(size))), atlasTexelMin, atlasTexelMax);

    int maxSteps = min(maxTraceSteps, heightMapNearestMaxSteps);

    float tCurrent = 0.0;
    vec2 uvCurrent = uv;
    float depthCurrent = depth;

    int step = 0;
    while (step < maxSteps) {
        if (tCurrent > maxDistance) { break; }
        if (depthCurrent < -heightMapTraceBias) { break; }

        float surfaceDepth = sampleHeightDepthNearest(tex, texel, atlasTexelMin, atlasTexelMax, uvCurrent, maxDepth);
        if (depthCurrent >= surfaceDepth - heightMapTraceBias) {
            hit.hit = true;
            hit.t = tCurrent;
            hit.uv = uvCurrent;
            hit.depth = max(depthCurrent, surfaceDepth);
            return true;
        }

        float tTop = INF_DISTANCE;
        if (depthRate > 1e-6 && surfaceDepth > depthCurrent) { tTop = (surfaceDepth - depthCurrent) / depthRate; }

        float tU = INF_DISTANCE;
        float tV = INF_DISTANCE;
        bool stepU = false;
        bool stepV = false;

        if (rateUV.x > 1e-9) {
            float boundary = (float(texel.x + 1)) / float(size.x);
            tU = (boundary - uvCurrent.x) / rateUV.x;
            stepU = true;
        } else if (rateUV.x < -1e-9) {
            float boundary = float(texel.x) / float(size.x);
            tU = (boundary - uvCurrent.x) / rateUV.x;
            stepU = true;
        }

        if (rateUV.y > 1e-9) {
            float boundary = (float(texel.y + 1)) / float(size.y);
            tV = (boundary - uvCurrent.y) / rateUV.y;
            stepV = true;
        } else if (rateUV.y < -1e-9) {
            float boundary = float(texel.y) / float(size.y);
            tV = (boundary - uvCurrent.y) / rateUV.y;
            stepV = true;
        }

        float tAbove = INF_DISTANCE;
        if (depthRate < -1e-6) { tAbove = -depthCurrent / depthRate; }

        float tBoundary = min(tU, tV);
        if (tTop <= min(tBoundary, tAbove) + heightMapTraceBias && tTop < INF_DISTANCE) {
            tCurrent += max(tTop, 0.0);
            hit.hit = true;
            hit.t = tCurrent;
            hit.uv = uvCurrent + rateUV * max(tTop, 0.0);
            hit.depth = surfaceDepth;
            return true;
        }

        if (tAbove <= tBoundary + heightMapTraceBias) { break; }
        if (tBoundary == INF_DISTANCE) { break; }

        float dt = max(tBoundary, 0.0);
        tCurrent += dt;
        if (tCurrent > maxDistance) { break; }

        vec2 boundaryUv = uvCurrent + rateUV * dt;
        float boundaryDepth = depthCurrent + depthRate * dt;
        bool cornerStep = stepU && stepV && abs(tU - tV) <= heightMapTraceBias;
        if (cornerStep) {
            ivec2 texelD = texel + ivec2(rateUV.x > 0.0 ? 1 : -1, rateUV.y > 0.0 ? 1 : -1);
            texel = wrapTexelInRect(texelD, atlasTexelMin, atlasTexelMax);
            uvCurrent = wrapBoundaryUvInRect(boundaryUv, texelD, atlasTexelMin, atlasTexelMax, boundsMin, boundsMax);
            depthCurrent = boundaryDepth;
            ++step;
            continue;
        }

        bool processU = false;
        if (tU <= tV + heightMapTraceBias) {
            if (tU < tV - heightMapTraceBias) {
                processU = true;
            } else {
                processU = abs(rateUV.x) >= abs(rateUV.y);
            }
        }

        ivec2 nextTexel = texel;
        bool enteredTop = false;

        if (processU) {
            nextTexel += ivec2(rateUV.x > 0.0 ? 1 : -1, 0);
            boundaryUv =
                wrapBoundaryUvInRect(boundaryUv, nextTexel, atlasTexelMin, atlasTexelMax, boundsMin, boundsMax);
            nextTexel = wrapTexelInRect(nextTexel, atlasTexelMin, atlasTexelMax);

            float nextDepth =
                sampleHeightDepthNearest(tex, nextTexel, atlasTexelMin, atlasTexelMax, boundaryUv, maxDepth);
            if (shouldContinueTexelTop(surfaceDepth, nextDepth, boundaryDepth)) { enteredTop = true; }
        }

        if (!processU) {
            nextTexel = texel + ivec2(0, rateUV.y > 0.0 ? 1 : -1);
            boundaryUv =
                wrapBoundaryUvInRect(boundaryUv, nextTexel, atlasTexelMin, atlasTexelMax, boundsMin, boundsMax);
            nextTexel = wrapTexelInRect(nextTexel, atlasTexelMin, atlasTexelMax);

            float nextDepth =
                sampleHeightDepthNearest(tex, nextTexel, atlasTexelMin, atlasTexelMax, boundaryUv, maxDepth);
            if (shouldContinueTexelTop(surfaceDepth, nextDepth, boundaryDepth)) { enteredTop = true; }
        }

        if (enteredTop) {
            hit.hit = true;
            hit.t = tCurrent;
            hit.uv = boundaryUv;
            hit.depth = surfaceDepth;
            return true;
        }

        texel = nextTexel;
        uvCurrent = boundaryUv;
        depthCurrent = boundaryDepth;
        ++step;
    }

    return false;
}

bool traceNearestHeightMap(sampler2D tex,
                           vec2 minUV,
                           vec2 maxUV,
                           vec2 uv,
                           float depth,
                           vec3 worldDir,
                           vec3 dPdu,
                           vec3 dPdv,
                           vec3 baseNormal,
                           float maxDepth,
                           float maxDistance,
                           out HeightMapHit hit) {
    return traceNearestHeightMapLimited(tex, minUV, maxUV, uv, depth, worldDir, dPdu, dPdv, baseNormal, maxDepth,
                                        maxDistance, heightMapNearestMaxSteps, hit);
}

bool traceBilinearHeightMapLimited(sampler2D tex,
                                   vec2 minUV,
                                   vec2 maxUV,
                                   vec2 uv,
                                   float depth,
                                   vec3 worldDir,
                                   vec3 dPdu,
                                   vec3 dPdv,
                                   vec3 baseNormal,
                                   float maxDepth,
                                   float maxDistance,
                                   int maxTraceSteps,
                                   out HeightMapHit hit) {
    hit.hit = false;
    hit.t = INF_DISTANCE;
    hit.uv = uv;
    hit.depth = depth;

    if (maxDepth <= heightMapMinWorldDepth) { return false; }

    ivec2 size = textureSize(tex, 0);
    if (size.x <= 0 || size.y <= 0) { return false; }

    vec2 boundsMin = heightMapMinUV(minUV, maxUV, size);
    vec2 boundsMax = heightMapMaxUV(minUV, maxUV, size);
    uv = wrapUvInRect(uv, boundsMin, boundsMax);

    vec2 rateUV = directionToRateUv(worldDir, dPdu, dPdv);
    float depthRate = dot(worldDir, -baseNormal);
    float texelTravel = max(abs(rateUV.x) * float(size.x), abs(rateUV.y) * float(size.y));
    float depthTravel = abs(depthRate) / max(maxDepth, heightMapMinWorldDepth) * float(max(size.x, size.y));
    float stepWorld = 0.5 / max(max(texelTravel, depthTravel), 1e-4);

    float tPrev = 0.0;
    vec2 uvPrev = uv;
    float depthPrev = depth;
    float surfacePrev = sampleHeightDepth(tex, uvPrev, boundsMin, boundsMax, 0, 1u, maxDepth);
    float fPrev = depthPrev - surfacePrev;
    if (fPrev >= -heightMapTraceBias) {
        hit.hit = true;
        hit.t = 0.0;
        hit.uv = uvPrev;
        hit.depth = surfacePrev;
        return true;
    }

    int maxSteps = min(maxTraceSteps, heightMapBilinearMaxSteps);
    for (int step = 0; step < maxSteps; ++step) {
        float tCurr = min(tPrev + stepWorld, maxDistance);
        vec2 uvCurr = uv + rateUV * tCurr;
        float depthCurr = depth + depthRate * tCurr;
        if (depthCurr < -heightMapTraceBias) { break; }

        float surfaceCurr = sampleHeightDepth(tex, uvCurr, boundsMin, boundsMax, 0, 1u, maxDepth);
        float fCurr = depthCurr - surfaceCurr;
        if (fCurr >= -heightMapTraceBias) {
            float lo = tPrev;
            float hi = tCurr;
            for (int refine = 0; refine < heightMapBilinearBinarySteps; ++refine) {
                float mid = 0.5 * (lo + hi);
                vec2 uvMid = uv + rateUV * mid;
                float depthMid = depth + depthRate * mid;
                float surfaceMid = sampleHeightDepth(tex, uvMid, boundsMin, boundsMax, 0, 1u, maxDepth);
                if (depthMid >= surfaceMid) {
                    hi = mid;
                } else {
                    lo = mid;
                }
            }

            float tHit = hi;
            vec2 uvHit = wrapUvInRect(uv + rateUV * tHit, boundsMin, boundsMax);
            float depthHit = sampleHeightDepth(tex, uvHit, boundsMin, boundsMax, 0, 1u, maxDepth);
            hit.hit = true;
            hit.t = tHit;
            hit.uv = uvHit;
            hit.depth = depthHit;
            return true;
        }

        if (tCurr >= maxDistance - 1e-6) { break; }
        tPrev = tCurr;
        uvPrev = uvCurr;
        depthPrev = depthCurr;
        fPrev = fCurr;
    }

    return false;
}

bool traceBilinearHeightMap(sampler2D tex,
                            vec2 minUV,
                            vec2 maxUV,
                            vec2 uv,
                            float depth,
                            vec3 worldDir,
                            vec3 dPdu,
                            vec3 dPdv,
                            vec3 baseNormal,
                            float maxDepth,
                            float maxDistance,
                            out HeightMapHit hit) {
    return traceBilinearHeightMapLimited(tex, minUV, maxUV, uv, depth, worldDir, dPdu, dPdv, baseNormal, maxDepth,
                                         maxDistance, heightMapBilinearMaxSteps, hit);
}

bool traceHeightMapLimited(sampler2D tex,
                           vec2 minUV,
                           vec2 maxUV,
                           vec2 uv,
                           float depth,
                           vec3 worldDir,
                           vec3 dPdu,
                           vec3 dPdv,
                           vec3 baseNormal,
                           float maxDepth,
                           float maxDistance,
                           uint samplingMode,
                           int maxTraceSteps,
                           out HeightMapHit hit) {
    if (samplingMode == 0u) {
        return traceNearestHeightMapLimited(tex, minUV, maxUV, uv, depth, worldDir, dPdu, dPdv, baseNormal, maxDepth,
                                            maxDistance, maxTraceSteps, hit);
    }

    return traceBilinearHeightMapLimited(tex, minUV, maxUV, uv, depth, worldDir, dPdu, dPdv, baseNormal, maxDepth,
                                         maxDistance, maxTraceSteps, hit);
}

bool traceHeightMap(sampler2D tex,
                    vec2 minUV,
                    vec2 maxUV,
                    vec2 uv,
                    float depth,
                    vec3 worldDir,
                    vec3 dPdu,
                    vec3 dPdv,
                    vec3 baseNormal,
                    float maxDepth,
                    float maxDistance,
                    uint samplingMode,
                    out HeightMapHit hit) {
    int maxTraceSteps = samplingMode == 0u ? heightMapNearestMaxSteps : heightMapBilinearMaxSteps;
    return traceHeightMapLimited(tex, minUV, maxUV, uv, depth, worldDir, dPdu, dPdv, baseNormal, maxDepth, maxDistance,
                                 samplingMode, maxTraceSteps, hit);
}

#endif
