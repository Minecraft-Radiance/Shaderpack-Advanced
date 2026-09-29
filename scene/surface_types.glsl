#ifndef ADV_SCENE_SURFACE_TYPES_GLSL
#define ADV_SCENE_SURFACE_TYPES_GLSL

struct Surface {
    bool isValid;
    uint category;
    uint instanceMask;
    uint instanceIndex;
    uint geometryBufferIndex;
    uint primitiveId;
    vec3 position;
    float rayDistance;
    vec3 previousPosition;
    bool hasPreviousPosition;
    vec3 outwardGeometryNormal;
    vec3 geometryNormal;
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
    bool isFrontFace;
    bool isHand;
    bool isCloud;
    bool isWater;
    bool isNonReflective;
    bool isPortal;
    bool hasParallax;
    bool isParallaxSideWall;
    int parallaxNormalTextureId;
    vec2 parallaxAtlasMin;
    vec2 parallaxAtlasMax;
    vec2 parallaxReferenceUv;
    vec2 parallaxContinuousUv;
    float parallaxDepth;
    float parallaxMaxDepthWorld;
    bool shouldTraceParallaxHeight;
    vec3 parallaxPlanePosition;
    vec3 parallaxBaseNormal;
    vec3 parallaxDPdu;
    vec3 parallaxDPdv;
};

#endif
