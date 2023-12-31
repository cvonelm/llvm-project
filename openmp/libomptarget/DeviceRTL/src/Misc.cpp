//===--------- Misc.cpp - OpenMP device misc interfaces ----------- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
//
//===----------------------------------------------------------------------===//

#include "Types.h"

#include "Debug.h"

#pragma omp begin declare target device_type(nohost)

namespace ompx {
namespace impl {

double getWTick();

double getWTime();

/// AMDGCN Implementation
///
///{
#pragma omp begin declare variant match(device = {arch(amdgcn)})

double getWTick() { return ((double)1E-9); }

double getWTime() {
  // The intrinsics for measuring time have undocumented frequency
  // This will probably need to be found by measurement on a number of
  // architectures. Until then, return 0, which is very inaccurate as a
  // timer but resolves the undefined symbol at link time.
  return 0;
}

#pragma omp end declare variant

/// NVPTX Implementation
///
///{
#pragma omp begin declare variant match(                                       \
        device = {arch(nvptx, nvptx64)},                                       \
            implementation = {extension(match_any)})

double getWTick() {
  // Timer precision is 1ns
  return ((double)1E-9);
}

double getWTime() {
  unsigned long long nsecs;
  asm volatile("mov.u64  %0, %%globaltimer;" : "=l"(nsecs));
  return (double)nsecs * getWTick();
}

#pragma omp end declare variant

} // namespace impl
} // namespace ompx

/// Interfaces
///
///{

extern "C" {
int32_t __kmpc_cancellationpoint(IdentTy *, int32_t, int32_t) {
  FunctionTracingRAII();
  return 0;
}

int32_t __kmpc_cancel(IdentTy *, int32_t, int32_t) {
  FunctionTracingRAII();
  return 0;
}

double omp_get_wtick(void) { return ompx::impl::getWTick(); }

double omp_get_wtime(void) { return ompx::impl::getWTime(); }
}

///}
#pragma omp end declare target
