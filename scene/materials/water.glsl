#ifndef ADV_SCENE_MATERIALS_WATER_GLSL
#define ADV_SCENE_MATERIALS_WATER_GLSL

#ifndef ADV_WATER_WAVES_ENABLED
#    define ADV_WATER_WAVES_ENABLED 1
#endif
#ifndef ADV_WATER_CAUSTICS_STRENGTH
#    define ADV_WATER_CAUSTICS_STRENGTH 1.0
#endif

const vec4 ADV_WATER_MAIN_WAVE_FREQUENCY = vec4(0.24543693, 0.36530147, 0.51501519, 0.72220521);
const vec4 ADV_WATER_MAIN_WAVE_AMPLITUDE = vec4(0.2200, 0.1400, 0.0850, 0.0500);
const vec4 ADV_WATER_DETAIL_WAVE_FREQUENCY = vec4(1.34639685, 1.96349541, 2.73181970, 3.92699082);
const vec4 ADV_WATER_DETAIL_WAVE_AMPLITUDE = vec4(0.0100, 0.0060, 0.0035, 0.0018);
const float ADV_WATER_WAVE_STRENGTH = 1.35;
const vec4 ADV_WATER_MAIN_WAVE_PHASE_OFFSET = vec4(0.0, 1.713, 4.129, 2.337);
const vec4 ADV_WATER_DETAIL_WAVE_PHASE_OFFSET = vec4(5.217, 0.913, 3.481, 2.029);

const vec4 ADV_WATER_MAIN_WAVE_DIRECTION_X = vec4(0.93969262, 0.60181502, 0.85716730, -0.15643447);
const vec4 ADV_WATER_MAIN_WAVE_DIRECTION_Z = vec4(0.34202014, 0.79863551, -0.51503807, 0.98768834);
const vec4 ADV_WATER_DETAIL_WAVE_DIRECTION_X = vec4(0.99756405, 0.79863551, 0.20791169, -0.75470958);
const vec4 ADV_WATER_DETAIL_WAVE_DIRECTION_Z = vec4(-0.06975647, 0.60181502, 0.97814760, 0.65605903);

const float ADV_WATER_DAY_PHASE_PER_TICK = 6.28318530717958648 / 24000.0;
const vec4 ADV_WATER_MAIN_WAVE_ANGULAR_SPEED = vec4(-79.0, -103.0, -139.0, -179.0) * ADV_WATER_DAY_PHASE_PER_TICK;
const vec4 ADV_WATER_DETAIL_WAVE_ANGULAR_SPEED = vec4(-223.0, -281.0, -347.0, -419.0) * ADV_WATER_DAY_PHASE_PER_TICK;

struct WaterWaveDomain {
    vec2 position;
    vec2 dx;
    vec2 dz;
    vec2 dxx;
    vec2 dxz;
    vec2 dzz;
};

WaterWaveDomain waterWaveDomain(vec2 absoluteWaterPosition) {
    const vec2 waveVectorA = vec2(0.0936, 0.0702);
    const vec2 waveVectorB = vec2(-0.02627, 0.06596);
    const vec2 displacementA = vec2(-2.0, 3.1);
    const vec2 displacementB = vec2(2.9, 1.4);
    vec2 phase = vec2(dot(absoluteWaterPosition, waveVectorA), dot(absoluteWaterPosition, waveVectorB)) +
                 worldUBO.gameTime * 6.28318530717958648 * vec2(-7.0, -11.0) + vec2(0.731, 2.417);
    vec2 sine = sin(phase);
    vec2 cosine = cos(phase);
    vec2 curvatureA = -displacementA * sine.x;
    vec2 curvatureB = -displacementB * sine.y;
    WaterWaveDomain domain;
    domain.position = absoluteWaterPosition + displacementA * sine.x + displacementB * sine.y;
    domain.dx = vec2(1.0, 0.0) + displacementA * (cosine.x * waveVectorA.x) +
                displacementB * (cosine.y * waveVectorB.x);
    domain.dz = vec2(0.0, 1.0) + displacementA * (cosine.x * waveVectorA.y) +
                displacementB * (cosine.y * waveVectorB.y);
    domain.dxx = curvatureA * (waveVectorA.x * waveVectorA.x) + curvatureB * (waveVectorB.x * waveVectorB.x);
    domain.dxz = curvatureA * (waveVectorA.x * waveVectorA.y) + curvatureB * (waveVectorB.x * waveVectorB.y);
    domain.dzz = curvatureA * (waveVectorA.y * waveVectorA.y) + curvatureB * (waveVectorB.y * waveVectorB.y);
    return domain;
}

vec4 waterMainWavePhase(vec2 absoluteWaterPosition) {
    vec4 directionalPosition = absoluteWaterPosition.x * ADV_WATER_MAIN_WAVE_DIRECTION_X +
                               absoluteWaterPosition.y * ADV_WATER_MAIN_WAVE_DIRECTION_Z;
    float animationTicks = worldUBO.gameTime * 24000.0;
    return directionalPosition * ADV_WATER_MAIN_WAVE_FREQUENCY + animationTicks * ADV_WATER_MAIN_WAVE_ANGULAR_SPEED +
           ADV_WATER_MAIN_WAVE_PHASE_OFFSET;
}

vec4 waterDetailWavePhase(vec2 absoluteWaterPosition) {
    vec4 directionalPosition = absoluteWaterPosition.x * ADV_WATER_DETAIL_WAVE_DIRECTION_X +
                               absoluteWaterPosition.y * ADV_WATER_DETAIL_WAVE_DIRECTION_Z;
    float animationTicks = worldUBO.gameTime * 24000.0;
    return directionalPosition * ADV_WATER_DETAIL_WAVE_FREQUENCY +
           animationTicks * ADV_WATER_DETAIL_WAVE_ANGULAR_SPEED + ADV_WATER_DETAIL_WAVE_PHASE_OFFSET;
}

vec4 waterWaveFootprintFilter(vec4 waveVectorX, vec4 waveVectorZ, vec3 rayDirection, float coneRadius) {
    vec4 projectedWaveVector = rayDirection.x * waveVectorX + rayDirection.z * waveVectorZ;
    float radius = max(coneRadius, 0.0);
    vec4 phaseVariance = radius * radius *
                         (waveVectorX * waveVectorX + waveVectorZ * waveVectorZ +
                          projectedWaveVector * projectedWaveVector / max(rayDirection.y * rayDirection.y, 1e-8));
    return exp(-phaseVariance / 6.0);
}

vec2 waterSurfaceSlope(vec2 absoluteWaterPosition, vec3 rayDirection, float coneRadius, out float unresolvedVariance) {
    WaterWaveDomain domain = waterWaveDomain(absoluteWaterPosition);
    vec4 mainWaveX = ADV_WATER_MAIN_WAVE_FREQUENCY *
                     (ADV_WATER_MAIN_WAVE_DIRECTION_X * domain.dx.x + ADV_WATER_MAIN_WAVE_DIRECTION_Z * domain.dx.y);
    vec4 mainWaveZ = ADV_WATER_MAIN_WAVE_FREQUENCY *
                     (ADV_WATER_MAIN_WAVE_DIRECTION_X * domain.dz.x + ADV_WATER_MAIN_WAVE_DIRECTION_Z * domain.dz.y);
    vec4 detailWaveX = ADV_WATER_DETAIL_WAVE_FREQUENCY *
                       (ADV_WATER_DETAIL_WAVE_DIRECTION_X * domain.dx.x + ADV_WATER_DETAIL_WAVE_DIRECTION_Z * domain.dx.y);
    vec4 detailWaveZ = ADV_WATER_DETAIL_WAVE_FREQUENCY *
                       (ADV_WATER_DETAIL_WAVE_DIRECTION_X * domain.dz.x + ADV_WATER_DETAIL_WAVE_DIRECTION_Z * domain.dz.y);
    vec4 mainFilter = waterWaveFootprintFilter(mainWaveX, mainWaveZ, rayDirection, coneRadius);
    vec4 detailFilter = waterWaveFootprintFilter(detailWaveX, detailWaveZ, rayDirection, coneRadius);
    vec4 mainDerivative = ADV_WATER_MAIN_WAVE_AMPLITUDE * cos(waterMainWavePhase(domain.position)) * mainFilter;
    vec4 detailDerivative = ADV_WATER_DETAIL_WAVE_AMPLITUDE * cos(waterDetailWavePhase(domain.position)) * detailFilter;
    vec4 mainVariance = ADV_WATER_MAIN_WAVE_AMPLITUDE * ADV_WATER_MAIN_WAVE_AMPLITUDE *
                         (mainWaveX * mainWaveX + mainWaveZ * mainWaveZ);
    vec4 detailVariance = ADV_WATER_DETAIL_WAVE_AMPLITUDE * ADV_WATER_DETAIL_WAVE_AMPLITUDE *
                           (detailWaveX * detailWaveX + detailWaveZ * detailWaveZ);
    unresolvedVariance = (dot(mainVariance, vec4(1.0) - mainFilter * mainFilter) +
                            dot(detailVariance, vec4(1.0) - detailFilter * detailFilter)) *
                           (0.5 * ADV_WATER_WAVE_STRENGTH * ADV_WATER_WAVE_STRENGTH);
    vec2 slope = vec2(dot(mainDerivative, mainWaveX) + dot(detailDerivative, detailWaveX),
                      dot(mainDerivative, mainWaveZ) + dot(detailDerivative, detailWaveZ));
    return slope * ADV_WATER_WAVE_STRENGTH;
}

vec3 waterWaveBandHessian(vec4 secondDerivative, vec4 directionX, vec4 directionZ) {
    return vec3(dot(secondDerivative, directionX * directionX), dot(secondDerivative, directionX * directionZ),
                dot(secondDerivative, directionZ * directionZ));
}

vec3 waterWaveHessian(vec2 absoluteWaterPosition) {
    WaterWaveDomain domain = waterWaveDomain(absoluteWaterPosition);
    vec4 mainPhase = waterMainWavePhase(domain.position);
    vec4 detailPhase = waterDetailWavePhase(domain.position);
    vec4 mainSecondDerivative = -ADV_WATER_MAIN_WAVE_AMPLITUDE * ADV_WATER_MAIN_WAVE_FREQUENCY *
                                ADV_WATER_MAIN_WAVE_FREQUENCY * sin(mainPhase);
    vec4 detailSecondDerivative = -ADV_WATER_DETAIL_WAVE_AMPLITUDE * ADV_WATER_DETAIL_WAVE_FREQUENCY *
                                  ADV_WATER_DETAIL_WAVE_FREQUENCY * sin(detailPhase);
    vec3 mainHessian =
        waterWaveBandHessian(mainSecondDerivative, ADV_WATER_MAIN_WAVE_DIRECTION_X, ADV_WATER_MAIN_WAVE_DIRECTION_Z);
    vec3 detailHessian = waterWaveBandHessian(detailSecondDerivative, ADV_WATER_DETAIL_WAVE_DIRECTION_X,
                                              ADV_WATER_DETAIL_WAVE_DIRECTION_Z);
    vec3 hessian = mainHessian + detailHessian;
    vec4 mainDerivative = ADV_WATER_MAIN_WAVE_AMPLITUDE * ADV_WATER_MAIN_WAVE_FREQUENCY * cos(mainPhase);
    vec4 detailDerivative = ADV_WATER_DETAIL_WAVE_AMPLITUDE * ADV_WATER_DETAIL_WAVE_FREQUENCY * cos(detailPhase);
    vec2 gradient = vec2(dot(mainDerivative, ADV_WATER_MAIN_WAVE_DIRECTION_X) +
                             dot(detailDerivative, ADV_WATER_DETAIL_WAVE_DIRECTION_X),
                         dot(mainDerivative, ADV_WATER_MAIN_WAVE_DIRECTION_Z) +
                             dot(detailDerivative, ADV_WATER_DETAIL_WAVE_DIRECTION_Z));
    vec2 hessianDx = vec2(dot(hessian.xy, domain.dx), dot(hessian.yz, domain.dx));
    vec2 hessianDz = vec2(dot(hessian.xy, domain.dz), dot(hessian.yz, domain.dz));
    return vec3(dot(domain.dx, hessianDx) + dot(gradient, domain.dxx),
                dot(domain.dx, hessianDz) + dot(gradient, domain.dxz),
                dot(domain.dz, hessianDz) + dot(gradient, domain.dzz)) * ADV_WATER_WAVE_STRENGTH;
}

float waterWaveCaustics(vec2 absoluteWaterPosition, vec3 directionToLight, float waterRayLength) {
    float strength = clamp(float(ADV_WATER_CAUSTICS_STRENGTH), 0.0, 4.0);
    if (strength <= 0.0) { return 1.0; }
    float directionLengthSquared = dot(directionToLight, directionToLight);
    if (waterRayLength <= 1e-4 || directionLengthSquared <= 1e-10 || any(isnan(directionToLight)) ||
        any(isinf(directionToLight))) {
        return 1.0;
    }

    vec3 lightDirection = directionToLight * inversesqrt(directionLengthSquared);
    float lightElevation = max(lightDirection.y, 0.0);
    if (lightElevation <= 0.01) { return 1.0; }

    float verticalDepth = max(waterRayLength, 0.0) * lightElevation;
    vec3 hessian = waterWaveHessian(absoluteWaterPosition);

    float eta = ADV_AIR_IOR / ADV_WATER_IOR;
    float projectionScale = min(verticalDepth, 12.0) * (1.0 - eta) * 1.70;
    float jacobianXX = 1.0 + projectionScale * hessian.x;
    float jacobianXZ = projectionScale * hessian.y;
    float jacobianZZ = 1.0 + projectionScale * hessian.z;
    float jacobianArea = abs(jacobianXX * jacobianZZ - jacobianXZ * jacobianXZ);

    float footprintSoftness = 0.10 + 0.018 * verticalDepth;
    float concentration = (1.0 + footprintSoftness) / (jacobianArea + footprintSoftness);
    float contrast = concentration - 1.0;
    float brightContrast = max(contrast, 0.0);
    float darkContrast = min(contrast, 0.0);
    contrast = brightContrast / (1.0 + 0.42 * brightContrast) + darkContrast / (1.0 + 0.65 * abs(darkContrast));

    float formation = smoothstep(0.15, 1.10, verticalDepth);
    float depthFade = 1.0 / (1.0 + 0.012 * verticalDepth * verticalDepth);
    float elevationWeight = smoothstep(0.08, 0.45, lightElevation);
    float caustics = 1.0 + contrast * 1.45 * formation * depthFade * elevationWeight;
    return max(1.0 + (clamp(caustics, 0.42, 3.40) - 1.0) * strength, 0.0);
}

#endif
