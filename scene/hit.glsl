#ifndef ADV_SCENE_HIT_GLSL
#define ADV_SCENE_HIT_GLSL

#ifndef ADV_HIT_WITH_TRANSMISSION
#    define ADV_HIT_WITH_TRANSMISSION 0
#endif

const uint ADV_HIT_KIND_NONE = 0u;
const uint ADV_HIT_KIND_TRIANGLE = 1u;

const uint ADV_HIT_CATEGORY_DEFAULT = 0u;
const uint ADV_HIT_CATEGORY_NO_REFLECT = 1u;
const uint ADV_HIT_CATEGORY_END_PORTAL = 2u;
const uint ADV_HIT_CATEGORY_END_GATEWAY = 3u;

const uint ADV_TRACE_ROLE_PRIMARY = 0u;
const uint ADV_TRACE_ROLE_SECONDARY_OPAQUE = 1u;
const uint ADV_TRACE_ROLE_SECONDARY_SPECULAR = 2u;
const uint ADV_TRACE_ROLE_SECONDARY_DIFFUSE = 3u;

struct HitPayload {
    float coneWidth;
    float coneSpread;
    uint role;
    uint hitKind;

    uint instanceIndex;
    uint geometryBufferIndex;
    uint primitiveId;
    uint category;

    float hitT;
    vec2 barycentrics;
    uint isFrontFace;
    uint instanceMask;
#if ADV_HIT_WITH_TRANSMISSION != 0
    f16vec3 transmission;
#endif
};

void resetHit(inout HitPayload payload, float coneWidth, float coneSpread, uint role) {
    payload.coneWidth = coneWidth;
    payload.coneSpread = coneSpread;
    payload.role = role;
    payload.hitKind = ADV_HIT_KIND_NONE;
    payload.instanceIndex = 0u;
    payload.geometryBufferIndex = 0u;
    payload.primitiveId = 0u;
    payload.category = ADV_HIT_CATEGORY_DEFAULT;
    payload.hitT = 0.0;
    payload.barycentrics = vec2(0.0);
    payload.isFrontFace = 0u;
    payload.instanceMask = 0u;
#if ADV_HIT_WITH_TRANSMISSION != 0
    payload.transmission = f16vec3(1.0);
#endif
}

bool isHitValid(HitPayload payload) {
    return payload.hitKind == ADV_HIT_KIND_TRIANGLE && payload.hitT > 0.0 && !isnan(payload.hitT) &&
           !isinf(payload.hitT);
}

#endif
