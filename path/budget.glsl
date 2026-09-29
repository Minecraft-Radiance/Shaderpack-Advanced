#ifndef ADV_PATH_BUDGET_GLSL
#define ADV_PATH_BUDGET_GLSL

#ifndef ADV_PATH_BOUNCE_COUNT
#    define ADV_PATH_BOUNCE_COUNT 4
#endif

const uint ADV_PATH_RAY_BUDGET = uint(ADV_PATH_BOUNCE_COUNT);

bool hasPathRayBudget(uint usedRayCount) {
    return usedRayCount < ADV_PATH_RAY_BUDGET;
}

uint remainingPathRayBudget(uint usedRayCount) {
    return usedRayCount < ADV_PATH_RAY_BUDGET ? ADV_PATH_RAY_BUDGET - usedRayCount : 0u;
}

#endif
