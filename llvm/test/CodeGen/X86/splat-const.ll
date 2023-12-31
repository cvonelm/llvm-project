; NOTE: Assertions have been autogenerated by utils/update_llc_test_checks.py
; RUN: llc < %s -mcpu=penryn | FileCheck %s --check-prefix=SSE
; RUN: llc < %s -mcpu=sandybridge | FileCheck %s --check-prefix=AVX
; RUN: llc < %s -mcpu=haswell | FileCheck %s --check-prefix=AVX2
; This checks that lowering for creation of constant vectors is sane and
; doesn't use redundant shuffles. (fixes PR22276)
target triple = "x86_64-unknown-unknown"

define <4 x i32> @zero_vector() {
; SSE-LABEL: zero_vector:
; SSE:       # %bb.0:
; SSE-NEXT:    xorps %xmm0, %xmm0
; SSE-NEXT:    retq
;
; AVX-LABEL: zero_vector:
; AVX:       # %bb.0:
; AVX-NEXT:    vxorps %xmm0, %xmm0, %xmm0
; AVX-NEXT:    retq
;
; AVX2-LABEL: zero_vector:
; AVX2:       # %bb.0:
; AVX2-NEXT:    vxorps %xmm0, %xmm0, %xmm0
; AVX2-NEXT:    retq
  %zero = insertelement <4 x i32> undef, i32 0, i32 0
  %splat = shufflevector <4 x i32> %zero, <4 x i32> undef, <4 x i32> zeroinitializer
  ret <4 x i32> %splat
}

; Note that for the "const_vector" versions, lowering that uses a shuffle
; instead of a load would be legitimate, if it's a single broadcast shuffle.
; (as opposed to the previous mess)
; However, this is not the current preferred lowering.
define <4 x i32> @const_vector() {
; SSE-LABEL: const_vector:
; SSE:       # %bb.0:
; SSE-NEXT:    movaps {{.*#+}} xmm0 = [42,42,42,42]
; SSE-NEXT:    retq
;
; AVX-LABEL: const_vector:
; AVX:       # %bb.0:
; AVX-NEXT:    vbroadcastss {{.*#+}} xmm0 = [42,42,42,42]
; AVX-NEXT:    retq
;
; AVX2-LABEL: const_vector:
; AVX2:       # %bb.0:
; AVX2-NEXT:    vbroadcastss {{.*#+}} xmm0 = [42,42,42,42]
; AVX2-NEXT:    retq
  %const = insertelement <4 x i32> undef, i32 42, i32 0
  %splat = shufflevector <4 x i32> %const, <4 x i32> undef, <4 x i32> zeroinitializer
  ret <4 x i32> %splat
}
