/*
 * Copyright (c) 2022-2024, NVIDIA CORPORATION.  All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-FileCopyrightText: Copyright (c) 2022-2024, NVIDIA CORPORATION.
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef RANDOM_GLSL
#define RANDOM_GLSL

precision highp float;

uint xxhash32(uvec3 p) {
    const uvec4 primes = uvec4(2246822519U, 3266489917U, 668265263U, 374761393U);
    uint h32;
    h32 = p.z + primes.w + p.x * primes.y;
    h32 = primes.z * ((h32 << 17) | (h32 >> (32 - 17)));
    h32 += p.y * primes.y;
    h32 = primes.z * ((h32 << 17) | (h32 >> (32 - 17)));
    h32 = primes.x * (h32 ^ (h32 >> 15));
    h32 = primes.y * (h32 ^ (h32 >> 13));
    return h32 ^ (h32 >> 16);
}

uint pcg(inout uint state) {
    uint prev = state * 747796405u + 2891336453u;
    uint word = ((prev >> ((prev >> 28u) + 4u)) ^ prev) * 277803737u;
    state = prev;
    return (word >> 22u) ^ word;
}

float rand(inout uint seed) {
    uint r = pcg(seed);
    return float(r) * (1.F / float(0xffffffffu));
}

#endif