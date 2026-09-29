#ifndef ADV_LIGHTING_BSDF_GLSL
#define ADV_LIGHTING_BSDF_GLSL

#include "util/random.glsl"

const float ADV_BRDF_PI = 3.14159265358979323846;
const float ADV_BRDF_INV_PI = 1.0 / ADV_BRDF_PI;
const float ADV_GGX_MIN_ALPHA = 0.001;
const float ADV_DIRECT_MIN_LINEAR_ROUGHNESS = 0.01;
const float ADV_FP16_MAX = 65504.0;

struct SpecularSample {
    vec3 direction;
    vec3 throughput;
    bool isValid;
};

struct DirectBrdf {
    vec3 diffuse;
    vec3 specular;
};

struct LobeMixtureThroughput {
    vec3 diffuse;
    vec3 specular;
    bool isValid;
};

bool isBrdfFinite(float scalar) {
    return !isnan(scalar) && !isinf(scalar);
}

bool isBrdfFinite(vec3 vector) {
    return !any(isnan(vector)) && !any(isinf(vector));
}

vec3 brdfNormalize(vec3 vector, vec3 fallback) {
    float lengthSquared = dot(vector, vector);
    if (!isBrdfFinite(vector) || !isBrdfFinite(lengthSquared) || lengthSquared <= 1e-12) { return fallback; }
    return vector * inversesqrt(lengthSquared);
}

float luminance(vec3 color) {
    return dot(max(color, vec3(0.0)), vec3(0.2126, 0.7152, 0.0722));
}

float pow5(float scalar) {
    float squared = scalar * scalar;
    return squared * squared * scalar;
}

vec3 diffuseAlbedo(vec3 baseColor, float metallic) {
    return max(baseColor, vec3(0.0)) * (1.0 - clamp(metallic, 0.0, 1.0));
}

vec3 fresnelSchlick(vec3 f0, float viewHalfCosine) {
    float fresnelWeight = pow5(1.0 - clamp(viewHalfCosine, 0.0, 1.0));
    vec3 f90 = vec3(clamp(50.0 * luminance(f0), 0.0, 1.0));
    return f90 * fresnelWeight + (1.0 - fresnelWeight) * f0;
}

void brdfBasis(vec3 normal, out vec3 tangent, out vec3 bitangent) {
    vec3 n = brdfNormalize(normal, vec3(0.0, 1.0, 0.0));
    float signZ = n.z >= 0.0 ? 1.0 : -1.0;
    float scale = -1.0 / (signZ + n.z);
    float crossTerm = n.x * n.y * scale;
    tangent = vec3(1.0 + signZ * n.x * n.x * scale, signZ * crossTerm, -signZ * n.x);
    bitangent = vec3(crossTerm, signZ + n.y * n.y * scale, -n.y);
    tangent = brdfNormalize(tangent, vec3(1.0, 0.0, 0.0));
    bitangent = brdfNormalize(bitangent, vec3(0.0, 0.0, 1.0));
}

vec3 brdfToLocal(vec3 vector, vec3 tangent, vec3 bitangent, vec3 normal) {
    return vec3(dot(vector, tangent), dot(vector, bitangent), dot(vector, normal));
}

vec3 brdfToWorld(vec3 vector, vec3 tangent, vec3 bitangent, vec3 normal) {
    return vector.x * tangent + vector.y * bitangent + vector.z * normal;
}

vec2 blueNoise2(sampler2D blueNoiseTexture, ivec2 pixel, uint frameSeed, uint dimension) {
    ivec2 noiseExtent = textureSize(blueNoiseTexture, 0);
    if (any(lessThanEqual(noiseExtent, ivec2(0)))) {
        uint seed = xxhash32(uvec3(uvec2(max(pixel, ivec2(0))), frameSeed ^ (dimension * 0x9e3779b9u)));
        return vec2(rand(seed), rand(seed));
    }

    uint offsetSeed = xxhash32(uvec3(frameSeed, dimension, 0x68bc21ebu));
    ivec2 offset = ivec2(int(offsetSeed & 0xffffu), int((offsetSeed >> 16u) & 0xffffu));
    ivec2 noisePixel = ivec2((pixel.x + offset.x) % noiseExtent.x, (pixel.y + offset.y) % noiseExtent.y);
    vec4 sampleValue = texelFetch(blueNoiseTexture, noisePixel, 0);
    vec2 noiseSample = (dimension & 1u) == 0u ? sampleValue.rg : sampleValue.ba;
    return clamp(noiseSample, vec2(0.0), vec2(0.99999994));
}

vec3 sampleCosineHemisphere(vec2 randomSample, vec3 normal) {
    float radius = sqrt(clamp(randomSample.x, 0.0, 1.0));
    float angle = 2.0 * ADV_BRDF_PI * randomSample.y;
    vec3 localDirection = vec3(radius * cos(angle), radius * sin(angle), sqrt(max(1.0 - radius * radius, 0.0)));
    vec3 n = brdfNormalize(normal, vec3(0.0, 1.0, 0.0));
    vec3 tangent;
    vec3 bitangent;
    brdfBasis(n, tangent, bitangent);
    return brdfNormalize(brdfToWorld(localDirection, tangent, bitangent, n), n);
}

float ggxG1(vec2 alphaSquared, vec3 localDirection) {
    float zSquared = max(localDirection.z * localDirection.z, 1e-8);
    float root = sqrt(1.0 + dot(alphaSquared, localDirection.xy * localDirection.xy) / zSquared);
    return 1.0 / max(0.5 * root + 0.5, 1e-6);
}

SpecularSample sampleSpecular(vec3 viewDirection, vec3 shadingNormal, float linearRoughness, vec2 randomSample) {
    SpecularSample specularSample;
    specularSample.direction = vec3(0.0);
    specularSample.throughput = vec3(0.0);
    specularSample.isValid = false;

    vec3 normal = brdfNormalize(shadingNormal, vec3(0.0, 1.0, 0.0));
    vec3 view = brdfNormalize(viewDirection, normal);
    if (dot(normal, view) <= 1e-6) { return specularSample; }

    if (linearRoughness == 0.0) {
        specularSample.direction = brdfNormalize(reflect(-view, normal), normal);
        specularSample.throughput = vec3(1.0);
        specularSample.isValid = dot(specularSample.direction, normal) > 1e-6;
        return specularSample;
    }

    vec3 tangent;
    vec3 bitangent;
    brdfBasis(normal, tangent, bitangent);
    vec3 localView = brdfToLocal(view, tangent, bitangent, normal);

    float alpha = max(linearRoughness * linearRoughness, ADV_GGX_MIN_ALPHA);
    vec2 alpha2D = vec2(alpha);
    vec3 stretchedView = brdfNormalize(vec3(alpha2D * localView.xy, localView.z), vec3(0.0, 0.0, 1.0));
    float viewXYLengthSquared = dot(stretchedView.xy, stretchedView.xy);
    vec3 axisX = viewXYLengthSquared > 0.0 ?
                     vec3(-stretchedView.y, stretchedView.x, 0.0) * inversesqrt(viewXYLengthSquared) :
                     vec3(1.0, 0.0, 0.0);
    vec3 axisY = cross(stretchedView, axisX);

    float radius = sqrt(clamp(randomSample.x, 0.0, 1.0));
    float phi = 2.0 * ADV_BRDF_PI * randomSample.y;
    float t1 = radius * cos(phi);
    float t2 = radius * sin(phi);
    float blend = 0.5 * (1.0 + stretchedView.z);
    t2 = mix(sqrt(max(1.0 - t1 * t1, 0.0)), t2, blend);
    vec3 stretchedNormal = t1 * axisX + t2 * axisY + sqrt(max(1.0 - t1 * t1 - t2 * t2, 0.0)) * stretchedView;
    vec3 localHalf =
        brdfNormalize(vec3(alpha2D * stretchedNormal.xy, max(stretchedNormal.z, 0.0)), vec3(0.0, 0.0, 1.0));
    vec3 localLight = reflect(-localView, localHalf);

    float lightHalfCosine = clamp(dot(localHalf, localLight), 0.0, 1.0);
    if (lightHalfCosine < 1e-5 || localLight.z <= 1e-6) { return specularSample; }

    vec2 alphaSquared = alpha2D * alpha2D;
    float g1Incoming = ggxG1(alphaSquared, localView);
    float g1Outgoing = ggxG1(alphaSquared, localLight);
    float correlatedDenominator = g1Outgoing + g1Incoming - g1Outgoing * g1Incoming;
    float g2OverG1 = g1Outgoing / max(correlatedDenominator, 1e-6);

    specularSample.direction = brdfNormalize(brdfToWorld(localLight, tangent, bitangent, normal), normal);
    specularSample.throughput = vec3(clamp(g2OverG1, 0.0, ADV_FP16_MAX));
    specularSample.isValid = isBrdfFinite(specularSample.direction) && isBrdfFinite(specularSample.throughput) &&
                             dot(specularSample.direction, normal) > 1e-6;
    return specularSample;
}

SpecularSample sampleSpecularAboveGeometry(
    vec3 viewDirection, vec3 shadingNormal, vec3 geometryNormal, float linearRoughness, vec2 randomSample) {
    SpecularSample sampleValue = sampleSpecular(viewDirection, shadingNormal, linearRoughness, randomSample);
    if (sampleValue.isValid && dot(sampleValue.direction, geometryNormal) > 1e-6) { return sampleValue; }
    sampleValue = sampleSpecular(viewDirection, geometryNormal, linearRoughness, randomSample);
    if (sampleValue.isValid && dot(sampleValue.direction, geometryNormal) > 1e-6) { return sampleValue; }
    if (linearRoughness <= 0.25) {
        vec3 reflected = brdfNormalize(reflect(-viewDirection, geometryNormal), geometryNormal);
        if (isBrdfFinite(reflected) && dot(reflected, geometryNormal) > 1e-6) {
            sampleValue.direction = reflected;
            sampleValue.throughput = vec3(1.0);
            sampleValue.isValid = true;
        }
    }
    return sampleValue;
}

float ggxDistribution(float alphaSquared, float normalHalfCosine) {
    float denominator = (normalHalfCosine * alphaSquared - normalHalfCosine) * normalHalfCosine + 1.0;
    return alphaSquared / max(ADV_BRDF_PI * denominator * denominator, 1e-8);
}

float schlickVisibility(float alpha, float normalViewCosine, float normalLightCosine) {
    float k = alpha * 0.5;
    float view = normalViewCosine * (1.0 - k) + k;
    float light = normalLightCosine * (1.0 - k) + k;
    return 0.25 / max(view * light, 1e-8);
}

float burleyDiffuse(float linearRoughness, float normalViewCosine, float normalLightCosine, float viewHalfCosine) {
    float fd90 = 0.5 + 2.0 * viewHalfCosine * viewHalfCosine * linearRoughness;
    float fdView = 1.0 + (fd90 - 1.0) * pow5(1.0 - normalViewCosine);
    float fdLight = 1.0 + (fd90 - 1.0) * pow5(1.0 - normalLightCosine);
    return ADV_BRDF_INV_PI * fdView * fdLight;
}

LobeMixtureThroughput evaluateLobeMixtureThroughput(vec3 shadingNormal,
                                                    vec3 geometryNormal,
                                                    vec3 viewDirection,
                                                    vec3 lightDirection,
                                                    vec3 albedo,
                                                    vec3 f0,
                                                    float linearRoughness,
                                                    float metallic,
                                                    float specularProbability) {
    LobeMixtureThroughput result;
    result.diffuse = vec3(0.0);
    result.specular = vec3(0.0);
    result.isValid = false;

    vec3 normal = brdfNormalize(shadingNormal, vec3(0.0, 1.0, 0.0));
    vec3 geometricNormal = brdfNormalize(geometryNormal, normal);
    vec3 view = brdfNormalize(viewDirection, normal);
    vec3 light = brdfNormalize(lightDirection, normal);
    float normalView = dot(normal, view);
    float normalLight = dot(normal, light);
    if (normalView <= 1e-6 || normalLight <= 1e-6 || dot(geometricNormal, light) <= 1e-6) { return result; }

    vec3 halfVector = view + light;
    float halfLengthSquared = dot(halfVector, halfVector);
    if (!isBrdfFinite(halfLengthSquared) || halfLengthSquared <= 1e-12) { return result; }
    halfVector *= inversesqrt(halfLengthSquared);
    float normalHalf = max(dot(normal, halfVector), 0.0);
    float viewHalf = max(dot(view, halfVector), 0.0);
    if (normalHalf <= 1e-6 || viewHalf <= 1e-6) { return result; }

    float roughness = clamp(linearRoughness, 0.0, 1.0);
    float alpha = max(roughness * roughness, ADV_GGX_MIN_ALPHA);
    float alphaSquared = alpha * alpha;
    float distribution = ggxDistribution(alphaSquared, normalHalf);

    vec3 tangent;
    vec3 bitangent;
    brdfBasis(normal, tangent, bitangent);
    vec3 localView = brdfToLocal(view, tangent, bitangent, normal);
    vec3 localLight = brdfToLocal(light, tangent, bitangent, normal);
    vec2 alphaSquared2D = vec2(alphaSquared);
    float g1View = ggxG1(alphaSquared2D, localView);
    float g1Light = ggxG1(alphaSquared2D, localLight);
    float correlatedDenominator = g1Light + g1View - g1Light * g1View;
    float g2 = g1Light * g1View / max(correlatedDenominator, 1e-6);

    float diffusePdf = normalLight * ADV_BRDF_INV_PI;
    float specularPdf = g1View * distribution / max(4.0 * normalView, 1e-6);
    float specularSelection = clamp(specularProbability, 0.0, 1.0);
    float mixturePdf = mix(diffusePdf, specularPdf, specularSelection);
    if (!isBrdfFinite(mixturePdf) || mixturePdf <= 1e-8) { return result; }

    vec3 fresnel = fresnelSchlick(clamp(f0, vec3(0.0), vec3(1.0)), viewHalf);
    vec3 diffuseWeight = diffuseAlbedo(albedo, metallic);
    float diffuseBrdfCos = burleyDiffuse(roughness, normalView, normalLight, viewHalf) * normalLight;
    vec3 specularBrdfCos = fresnel * distribution * g2 / max(4.0 * normalView, 1e-6);
    result.diffuse = diffuseWeight * diffuseBrdfCos / mixturePdf;
    result.specular = specularBrdfCos / mixturePdf;
    if (!isBrdfFinite(result.diffuse) || !isBrdfFinite(result.specular)) {
        result.diffuse = vec3(0.0);
        result.specular = vec3(0.0);
        return result;
    }
    result.diffuse = clamp(result.diffuse, vec3(0.0), vec3(ADV_FP16_MAX));
    result.specular = clamp(result.specular, vec3(0.0), vec3(ADV_FP16_MAX));
    result.isValid = true;
    return result;
}

DirectBrdf
evaluateDirectBrdf(vec3 shadingNormal, vec3 lightDirection, vec3 viewDirection, vec3 f0, float linearRoughness) {
    DirectBrdf directBrdf;
    directBrdf.diffuse = vec3(0.0);
    directBrdf.specular = vec3(0.0);

    vec3 normal = brdfNormalize(shadingNormal, vec3(0.0, 1.0, 0.0));
    vec3 light = brdfNormalize(lightDirection, normal);
    vec3 view = brdfNormalize(viewDirection, normal);
    float normalLight = max(dot(normal, light), 0.0);
    float normalView = max(dot(normal, view), 0.0);
    if (normalLight <= 0.0 || normalView <= 0.0) { return directBrdf; }

    vec3 halfVector = light + view;
    float halfLengthSquared = dot(halfVector, halfVector);
    if (halfLengthSquared <= 1e-12) { return directBrdf; }
    halfVector *= inversesqrt(halfLengthSquared);
    float normalHalf = max(dot(normal, halfVector), 0.0);
    float viewHalf = max(dot(view, halfVector), 0.0);
    float roughness = max(clamp(linearRoughness, 0.0, 1.0), ADV_DIRECT_MIN_LINEAR_ROUGHNESS);
    float alpha = roughness * roughness;
    float distribution = ggxDistribution(alpha * alpha, normalHalf);
    float visibility = schlickVisibility(alpha, normalView, normalLight);
    vec3 fresnel = fresnelSchlick(clamp(f0, vec3(0.0), vec3(1.0)), viewHalf);
    float diffuse = burleyDiffuse(roughness, normalView, normalLight, viewHalf);

    directBrdf.diffuse = (vec3(1.0) - fresnel) * diffuse * normalLight;
    directBrdf.specular = fresnel * distribution * visibility * normalLight;
    if (!isBrdfFinite(directBrdf.diffuse)) { directBrdf.diffuse = vec3(0.0); }
    if (!isBrdfFinite(directBrdf.specular)) { directBrdf.specular = vec3(0.0); }
    return directBrdf;
}

vec3 sampleUnitSphere(vec2 randomSample) {
    float z = 1.0 - 2.0 * clamp(randomSample.x, 0.0, 1.0);
    float radius = sqrt(max(1.0 - z * z, 0.0));
    float phi = 2.0 * ADV_BRDF_PI * randomSample.y;
    return vec3(radius * cos(phi), radius * sin(phi), z);
}

vec3 sanitizeRadiance(vec3 radiance) {
    if (!isBrdfFinite(radiance)) { return vec3(0.0); }
    return clamp(radiance, vec3(0.0), vec3(ADV_FP16_MAX));
}

#endif
