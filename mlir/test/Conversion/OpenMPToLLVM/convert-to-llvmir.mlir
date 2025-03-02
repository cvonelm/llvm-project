// RUN: mlir-opt -convert-openmp-to-llvm -split-input-file %s | FileCheck %s
// RUN: mlir-opt -convert-to-llvm -split-input-file %s | FileCheck %s

// CHECK-LABEL: llvm.func @foo(i64, i64)
func.func private @foo(index, index)

// CHECK-LABEL: llvm.func @critical_block_arg
func.func @critical_block_arg() {
  // CHECK: omp.critical
  omp.critical {
  // CHECK-NEXT: ^[[BB0:.*]](%[[ARG1:.*]]: i64, %[[ARG2:.*]]: i64):
  ^bb0(%arg1: index, %arg2: index):
    // CHECK-NEXT: llvm.call @foo(%[[ARG1]], %[[ARG2]]) : (i64, i64) -> ()
    func.call @foo(%arg1, %arg2) : (index, index) -> ()
    omp.terminator
  }
  return
}

// -----

// CHECK: omp.critical.declare @[[MUTEX:.*]] hint(contended, speculative)
omp.critical.declare @mutex hint(contended, speculative)

// CHECK: llvm.func @critical_declare
func.func @critical_declare() {
  // CHECK: omp.critical(@[[MUTEX]])
  omp.critical(@mutex) {
    omp.terminator
  }
  return
}

// -----

// CHECK-LABEL: llvm.func @master_block_arg
func.func @master_block_arg() {
  // CHECK: omp.master
  omp.master {
  // CHECK-NEXT: ^[[BB0:.*]](%[[ARG1:.*]]: i64, %[[ARG2:.*]]: i64):
  ^bb0(%arg1: index, %arg2: index):
    // CHECK-DAG: %[[CAST_ARG1:.*]] = builtin.unrealized_conversion_cast %[[ARG1]] : i64 to index
    // CHECK-DAG: %[[CAST_ARG2:.*]] = builtin.unrealized_conversion_cast %[[ARG2]] : i64 to index
    // CHECK-NEXT: "test.payload"(%[[CAST_ARG1]], %[[CAST_ARG2]]) : (index, index) -> ()
    "test.payload"(%arg1, %arg2) : (index, index) -> ()
    omp.terminator
  }
  return
}

// -----

// CHECK-LABEL: llvm.func @branch_loop
func.func @branch_loop() {
  %start = arith.constant 0 : index
  %end = arith.constant 0 : index
  // CHECK: omp.parallel
  omp.parallel {
    // CHECK-NEXT: llvm.br ^[[BB1:.*]](%{{[0-9]+}}, %{{[0-9]+}} : i64, i64
    cf.br ^bb1(%start, %end : index, index)
  // CHECK-NEXT: ^[[BB1]](%[[ARG1:[0-9]+]]: i64, %[[ARG2:[0-9]+]]: i64):{{.*}}
  ^bb1(%0: index, %1: index):
    // CHECK-NEXT: %[[CMP:[0-9]+]] = llvm.icmp "slt" %[[ARG1]], %[[ARG2]] : i64
    %2 = arith.cmpi slt, %0, %1 : index
    // CHECK-NEXT: llvm.cond_br %[[CMP]], ^[[BB2:.*]](%{{[0-9]+}}, %{{[0-9]+}} : i64, i64), ^[[BB3:.*]]
    cf.cond_br %2, ^bb2(%end, %end : index, index), ^bb3
  // CHECK-NEXT: ^[[BB2]](%[[ARG3:[0-9]+]]: i64, %[[ARG4:[0-9]+]]: i64):
  ^bb2(%3: index, %4: index):
    // CHECK-NEXT: llvm.br ^[[BB1]](%[[ARG3]], %[[ARG4]] : i64, i64)
    cf.br ^bb1(%3, %4 : index, index)
  // CHECK-NEXT: ^[[BB3]]:
  ^bb3:
    omp.flush
    omp.barrier
    omp.taskwait
    omp.taskyield
    omp.terminator
  }
  return
}

// -----

// CHECK-LABEL: @wsloop
// CHECK: (%[[ARG0:.*]]: i64, %[[ARG1:.*]]: i64, %[[ARG2:.*]]: i64, %[[ARG3:.*]]: i64, %[[ARG4:.*]]: i64, %[[ARG5:.*]]: i64)
func.func @wsloop(%arg0: index, %arg1: index, %arg2: index, %arg3: index, %arg4: index, %arg5: index) {
  // CHECK: omp.parallel
  omp.parallel {
    // CHECK: omp.wsloop {
    "omp.wsloop"() ({
      // CHECK: omp.loop_nest (%[[ARG6:.*]], %[[ARG7:.*]]) : i64 = (%[[ARG0]], %[[ARG1]]) to (%[[ARG2]], %[[ARG3]]) step (%[[ARG4]], %[[ARG5]]) {
      omp.loop_nest (%arg6, %arg7) : index = (%arg0, %arg1) to (%arg2, %arg3) step (%arg4, %arg5) {
        // CHECK-DAG: %[[CAST_ARG6:.*]] = builtin.unrealized_conversion_cast %[[ARG6]] : i64 to index
        // CHECK-DAG: %[[CAST_ARG7:.*]] = builtin.unrealized_conversion_cast %[[ARG7]] : i64 to index
        // CHECK: "test.payload"(%[[CAST_ARG6]], %[[CAST_ARG7]]) : (index, index) -> ()
        "test.payload"(%arg6, %arg7) : (index, index) -> ()
        omp.yield
      }
      omp.terminator
    }) : () -> ()
    omp.terminator
  }
  return
}

// -----

// CHECK-LABEL: @atomic_write
// CHECK: (%[[ARG0:.*]]: !llvm.ptr)
// CHECK: %[[VAL0:.*]] = llvm.mlir.constant(1 : i32) : i32
// CHECK: omp.atomic.write %[[ARG0]] = %[[VAL0]] memory_order(relaxed) : !llvm.ptr, i32
func.func @atomic_write(%a: !llvm.ptr) -> () {
  %1 = arith.constant 1 : i32
  omp.atomic.write %a = %1 hint(none) memory_order(relaxed) : !llvm.ptr, i32
  return
}

// -----

// CHECK-LABEL: @atomic_read
// CHECK: (%[[ARG0:.*]]: !llvm.ptr, %[[ARG1:.*]]: !llvm.ptr)
// CHECK: omp.atomic.read %[[ARG1]] = %[[ARG0]] hint(contended) memory_order(acquire) : !llvm.ptr
func.func @atomic_read(%a: !llvm.ptr, %b: !llvm.ptr) -> () {
  omp.atomic.read %b = %a memory_order(acquire) hint(contended) : !llvm.ptr, i32
  return
}

// -----

func.func @atomic_update() {
  %0 = llvm.mlir.addressof @_QFsEc : !llvm.ptr
  omp.atomic.update   %0 : !llvm.ptr {
  ^bb0(%arg0: i32):
    %1 = arith.constant 1 : i32
    %2 = arith.addi %arg0, %1  : i32
    omp.yield(%2 : i32)
  }
  return
}
llvm.mlir.global internal @_QFsEc() : i32 {
  %0 = arith.constant 10 : i32
  llvm.return %0 : i32
}

// CHECK-LABEL: @atomic_update
// CHECK: %[[GLOBAL_VAR:.*]] = llvm.mlir.addressof @_QFsEc : !llvm.ptr
// CHECK: omp.atomic.update   %[[GLOBAL_VAR]] : !llvm.ptr {
// CHECK: ^bb0(%[[IN_VAL:.*]]: i32):
// CHECK:   %[[CONST_1:.*]] = llvm.mlir.constant(1 : i32) : i32
// CHECK:   %[[OUT_VAL:.*]] = llvm.add %[[IN_VAL]], %[[CONST_1]]  : i32
// CHECK:   omp.yield(%[[OUT_VAL]] : i32)
// CHECK: }

// -----

// CHECK-LABEL: @threadprivate
// CHECK: (%[[ARG0:.*]]: !llvm.ptr)
// CHECK: %[[VAL0:.*]] = omp.threadprivate %[[ARG0]] : !llvm.ptr -> !llvm.ptr
func.func @threadprivate(%a: !llvm.ptr) -> () {
  %1 = omp.threadprivate %a : !llvm.ptr -> !llvm.ptr
  return
}

// -----

// CHECK:      llvm.func @loop_nest_block_arg(%[[LOWER:.*]]: i32, %[[UPPER:.*]]: i32, %[[ITER:.*]]: i64) {
// CHECK:      omp.simd {
// CHECK-NEXT: omp.loop_nest (%[[ARG_0:.*]]) : i32 = (%[[LOWER]])
// CHECK-SAME: to (%[[UPPER]]) inclusive step (%[[LOWER]]) {
// CHECK:      llvm.br ^[[BB1:.*]](%[[ITER]] : i64)
// CHECK:        ^[[BB1]](%[[VAL_0:.*]]: i64):
// CHECK:          %[[VAL_1:.*]] = llvm.icmp "slt" %[[VAL_0]], %[[ITER]] : i64
// CHECK:          llvm.cond_br %[[VAL_1]], ^[[BB2:.*]], ^[[BB3:.*]]
// CHECK:        ^[[BB2]]:
// CHECK:          %[[VAL_2:.*]] = llvm.add %[[VAL_0]], %[[ITER]]  : i64
// CHECK:          llvm.br ^[[BB1]](%[[VAL_2]] : i64)
// CHECK:        ^[[BB3]]:
// CHECK:          omp.yield
func.func @loop_nest_block_arg(%val : i32, %ub : i32, %i : index) {
  omp.simd {
    omp.loop_nest (%arg0) : i32 = (%val) to (%ub) inclusive step (%val) {
      cf.br ^bb1(%i : index)
    ^bb1(%0: index):
      %1 = arith.cmpi slt, %0, %i : index
      cf.cond_br %1, ^bb2, ^bb3
    ^bb2:
      %2 = arith.addi %0, %i : index
      cf.br ^bb1(%2 : index)
    ^bb3:
      omp.yield
    }
    omp.terminator
  }
  return
}

// -----

// CHECK-LABEL: @task_depend
// CHECK:  (%[[ARG0:.*]]: !llvm.ptr) {
// CHECK:  omp.task depend(taskdependin -> %[[ARG0]] : !llvm.ptr) {
// CHECK:    omp.terminator
// CHECK:  }
// CHECK:   llvm.return
// CHECK: }

func.func @task_depend(%arg0: !llvm.ptr) {
  omp.task depend(taskdependin -> %arg0 : !llvm.ptr) {
    omp.terminator
  }
  return
}

// -----

// CHECK-LABEL: @_QPomp_target_data
// CHECK: (%[[ARG0:.*]]: !llvm.ptr, %[[ARG1:.*]]: !llvm.ptr, %[[ARG2:.*]]: !llvm.ptr, %[[ARG3:.*]]: !llvm.ptr)
// CHECK: %[[MAP0:.*]] = omp.map.info var_ptr(%[[ARG0]] : !llvm.ptr, i32)   map_clauses(to) capture(ByRef) -> !llvm.ptr {name = ""}
// CHECK: %[[MAP1:.*]] = omp.map.info var_ptr(%[[ARG1]] : !llvm.ptr, i32)   map_clauses(to) capture(ByRef) -> !llvm.ptr {name = ""}
// CHECK: %[[MAP2:.*]] = omp.map.info var_ptr(%[[ARG2]] : !llvm.ptr, i32)   map_clauses(always, exit_release_or_enter_alloc) capture(ByRef) -> !llvm.ptr {name = ""}
// CHECK: omp.target_enter_data map_entries(%[[MAP0]], %[[MAP1]], %[[MAP2]] : !llvm.ptr, !llvm.ptr, !llvm.ptr)
// CHECK: %[[MAP3:.*]] = omp.map.info var_ptr(%[[ARG0]] : !llvm.ptr, i32)   map_clauses(from) capture(ByRef) -> !llvm.ptr {name = ""}
// CHECK: %[[MAP4:.*]] = omp.map.info var_ptr(%[[ARG1]] : !llvm.ptr, i32)   map_clauses(from) capture(ByRef) -> !llvm.ptr {name = ""}
// CHECK: %[[MAP5:.*]] = omp.map.info var_ptr(%[[ARG2]] : !llvm.ptr, i32)   map_clauses(exit_release_or_enter_alloc) capture(ByRef) -> !llvm.ptr {name = ""}
// CHECK: %[[MAP6:.*]] = omp.map.info var_ptr(%[[ARG3]] : !llvm.ptr, i32)   map_clauses(always, delete) capture(ByRef) -> !llvm.ptr {name = ""}
// CHECK: omp.target_exit_data map_entries(%[[MAP3]], %[[MAP4]], %[[MAP5]], %[[MAP6]] : !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr)

llvm.func @_QPomp_target_data(%a : !llvm.ptr, %b : !llvm.ptr, %c : !llvm.ptr, %d : !llvm.ptr) {
  %0 = omp.map.info var_ptr(%a : !llvm.ptr, i32)   map_clauses(to) capture(ByRef) -> !llvm.ptr {name = ""}
  %1 = omp.map.info var_ptr(%b : !llvm.ptr, i32)   map_clauses(to) capture(ByRef) -> !llvm.ptr {name = ""}
  %2 = omp.map.info var_ptr(%c : !llvm.ptr, i32)   map_clauses(always, exit_release_or_enter_alloc) capture(ByRef) -> !llvm.ptr {name = ""}
  omp.target_enter_data map_entries(%0, %1, %2 : !llvm.ptr, !llvm.ptr, !llvm.ptr) {}
  %3 = omp.map.info var_ptr(%a : !llvm.ptr, i32)   map_clauses(from) capture(ByRef) -> !llvm.ptr {name = ""}
  %4 = omp.map.info var_ptr(%b : !llvm.ptr, i32)   map_clauses(from) capture(ByRef) -> !llvm.ptr {name = ""}
  %5 = omp.map.info var_ptr(%c : !llvm.ptr, i32)   map_clauses(exit_release_or_enter_alloc) capture(ByRef) -> !llvm.ptr {name = ""}
  %6 = omp.map.info var_ptr(%d : !llvm.ptr, i32)   map_clauses(always, delete) capture(ByRef) -> !llvm.ptr {name = ""}
  omp.target_exit_data map_entries(%3, %4, %5, %6 : !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) {}
  llvm.return
}

// -----

// CHECK-LABEL: @_QPomp_target_data_region
// CHECK: (%[[ARG0:.*]]: !llvm.ptr, %[[ARG1:.*]]: !llvm.ptr) {
// CHECK: %[[MAP_0:.*]] = omp.map.info var_ptr(%[[ARG0]] : !llvm.ptr, !llvm.array<1024 x i32>)  map_clauses(tofrom) capture(ByRef) -> !llvm.ptr {name = ""}
// CHECK: omp.target_data map_entries(%[[MAP_0]] : !llvm.ptr) {
// CHECK:           %[[VAL_1:.*]] = llvm.mlir.constant(10 : i32) : i32
// CHECK:           llvm.store %[[VAL_1]], %[[ARG1]] : i32, !llvm.ptr
// CHECK:           omp.terminator
// CHECK:         }
// CHECK:         llvm.return

llvm.func @_QPomp_target_data_region(%a : !llvm.ptr, %i : !llvm.ptr) {
  %1 = omp.map.info var_ptr(%a : !llvm.ptr, !llvm.array<1024 x i32>)   map_clauses(tofrom) capture(ByRef) -> !llvm.ptr {name = ""}
  omp.target_data map_entries(%1 : !llvm.ptr) {
    %2 = llvm.mlir.constant(10 : i32) : i32
    llvm.store %2, %i : i32, !llvm.ptr
    omp.terminator
  }
  llvm.return
}

// -----

// CHECK-LABEL:   llvm.func @_QPomp_target(
// CHECK:                             %[[ARG_0:.*]]: !llvm.ptr,
// CHECK:                             %[[ARG_1:.*]]: !llvm.ptr) {
// CHECK:           %[[VAL_0:.*]] = llvm.mlir.constant(64 : i32) : i32
// CHECK:           %[[MAP1:.*]] = omp.map.info var_ptr(%[[ARG_0]] : !llvm.ptr, !llvm.array<1024 x i32>)   map_clauses(tofrom) capture(ByRef) -> !llvm.ptr {name = ""}
// CHECK:           %[[MAP2:.*]] = omp.map.info var_ptr(%[[ARG_1]] : !llvm.ptr, i32)   map_clauses(implicit, exit_release_or_enter_alloc) capture(ByCopy) -> !llvm.ptr {name = ""}
// CHECK:           omp.target thread_limit(%[[VAL_0]] : i32) map_entries(%[[MAP1]] -> %[[BB_ARG0:.*]], %[[MAP2]] -> %[[BB_ARG1:.*]] : !llvm.ptr, !llvm.ptr) {
// CHECK:             %[[VAL_1:.*]] = llvm.mlir.constant(10 : i32) : i32
// CHECK:             llvm.store %[[VAL_1]], %[[BB_ARG1]] : i32, !llvm.ptr
// CHECK:             omp.terminator
// CHECK:           }
// CHECK:           llvm.return
// CHECK:         }

llvm.func @_QPomp_target(%a : !llvm.ptr, %i : !llvm.ptr) {
  %0 = llvm.mlir.constant(64 : i32) : i32
  %1 = omp.map.info var_ptr(%a : !llvm.ptr, !llvm.array<1024 x i32>)   map_clauses(tofrom) capture(ByRef) -> !llvm.ptr {name = ""}
  %3 = omp.map.info var_ptr(%i : !llvm.ptr, i32)   map_clauses(implicit, exit_release_or_enter_alloc) capture(ByCopy) -> !llvm.ptr {name = ""}
  omp.target   thread_limit(%0 : i32) map_entries(%1 -> %arg0, %3 -> %arg1 : !llvm.ptr, !llvm.ptr) {
    %2 = llvm.mlir.constant(10 : i32) : i32
    llvm.store %2, %arg1 : i32, !llvm.ptr
    omp.terminator
  }
  llvm.return
}

// -----

// CHECK-LABEL: @_QPsb
// CHECK: omp.sections
// CHECK: omp.section
// CHECK: llvm.br
// CHECK: llvm.icmp
// CHECK: llvm.cond_br
// CHECK: llvm.br
// CHECK: omp.terminator
// CHECK: omp.terminator
// CHECK: llvm.return

llvm.func @_QPsb() {
  %0 = llvm.mlir.constant(0 : i64) : i64
  %1 = llvm.mlir.constant(10 : i64) : i64
  %2 = llvm.mlir.constant(1 : i64) : i64
  omp.sections   {
    omp.section {
      llvm.br ^bb1(%1 : i64)
    ^bb1(%3: i64):  // 2 preds: ^bb0, ^bb2
      %4 = llvm.icmp "sgt" %3, %0 : i64
      llvm.cond_br %4, ^bb2, ^bb3
    ^bb2:  // pred: ^bb1
      %5 = llvm.sub %3, %2  : i64
      llvm.br ^bb1(%5 : i64)
    ^bb3:  // pred: ^bb1
      omp.terminator
    }
    omp.terminator
  }
  llvm.return
}

// -----

// CHECK:  omp.declare_reduction @eqv_reduction : i32 init
// CHECK:  ^bb0(%{{.*}}: i32):
// CHECK:    %[[TRUE:.*]] = llvm.mlir.constant(true) : i1
// CHECK:    %[[TRUE_EXT:.*]] = llvm.zext %[[TRUE]] : i1 to i32
// CHECK:    omp.yield(%[[TRUE_EXT]] : i32)
// CHECK:  } combiner {
// CHECK:  ^bb0(%[[ARG_1:.*]]: i32, %[[ARG_2:.*]]: i32):
// CHECK:    %[[ZERO:.*]] = llvm.mlir.constant(0 : i64) : i32
// CHECK:    %[[CMP_1:.*]] = llvm.icmp "ne" %[[ARG_1]], %[[ZERO]] : i32
// CHECK:    %[[CMP_2:.*]] = llvm.icmp "ne" %[[ARG_2]], %[[ZERO]] : i32
// CHECK:    %[[COMBINE_VAL:.*]] = llvm.icmp "eq" %[[CMP_1]], %[[CMP_2]] : i1
// CHECK:    %[[COMBINE_VAL_EXT:.*]] = llvm.zext %[[COMBINE_VAL]] : i1 to i32
// CHECK:    omp.yield(%[[COMBINE_VAL_EXT]] : i32)
// CHECK-LABEL:  @_QPsimple_reduction
// CHECK:    %[[RED_ACCUMULATOR:.*]] = llvm.alloca %{{.*}} x i32 {bindc_name = "x", uniq_name = "_QFsimple_reductionEx"} : (i64) -> !llvm.ptr
// CHECK:    omp.parallel
// CHECK:      omp.wsloop reduction(@eqv_reduction %{{.+}} -> %[[PRV:.+]] : !llvm.ptr)
// CHECK-NEXT:   omp.loop_nest {{.*}}{
// CHECK:          %[[LPRV:.+]] = llvm.load %[[PRV]] : !llvm.ptr -> i32
// CHECK:          %[[CMP:.+]] = llvm.icmp "eq" %{{.*}}, %[[LPRV]] : i32
// CHECK:          %[[ZEXT:.+]] = llvm.zext %[[CMP]] : i1 to i32
// CHECK:          llvm.store %[[ZEXT]], %[[PRV]] : i32, !llvm.ptr
// CHECK:          omp.yield
// CHECK:        omp.terminator
// CHECK:      omp.terminator
// CHECK:    llvm.return

omp.declare_reduction @eqv_reduction : i32 init {
^bb0(%arg0: i32):
  %0 = llvm.mlir.constant(true) : i1
  %1 = llvm.zext %0 : i1 to i32
  omp.yield(%1 : i32)
} combiner {
^bb0(%arg0: i32, %arg1: i32):
  %0 = llvm.mlir.constant(0 : i64) : i32
  %1 = llvm.icmp "ne" %arg0, %0 : i32
  %2 = llvm.icmp "ne" %arg1, %0 : i32
  %3 = llvm.icmp "eq" %1, %2 : i1
  %4 = llvm.zext %3 : i1 to i32
  omp.yield(%4 : i32)
}
llvm.func @_QPsimple_reduction(%arg0: !llvm.ptr {fir.bindc_name = "y"}) {
  %0 = llvm.mlir.constant(100 : i32) : i32
  %1 = llvm.mlir.constant(1 : i32) : i32
  %2 = llvm.mlir.constant(true) : i1
  %3 = llvm.mlir.constant(1 : i64) : i64
  %4 = llvm.alloca %3 x i32 {bindc_name = "x", uniq_name = "_QFsimple_reductionEx"} : (i64) -> !llvm.ptr
  %5 = llvm.zext %2 : i1 to i32
  llvm.store %5, %4 : i32, !llvm.ptr
  omp.parallel {
    %6 = llvm.alloca %3 x i32 {adapt.valuebyref, in_type = i32, operandSegmentSizes = array<i32: 0, 0>, pinned} : (i64) -> !llvm.ptr
    omp.wsloop reduction(@eqv_reduction %4 -> %prv : !llvm.ptr) {
      omp.loop_nest (%arg1) : i32 = (%1) to (%0) inclusive step (%1) {
        llvm.store %arg1, %6 : i32, !llvm.ptr
        %7 = llvm.load %6 : !llvm.ptr -> i32
        %8 = llvm.sext %7 : i32 to i64
        %9 = llvm.sub %8, %3  : i64
        %10 = llvm.getelementptr %arg0[0, %9] : (!llvm.ptr, i64) -> !llvm.ptr, !llvm.array<100 x i32>
        %11 = llvm.load %10 : !llvm.ptr -> i32
        %12 = llvm.load %prv : !llvm.ptr -> i32
        %13 = llvm.icmp "eq" %11, %12 : i32
        %14 = llvm.zext %13 : i1 to i32
        llvm.store %14, %prv : i32, !llvm.ptr
        omp.yield
      }
      omp.terminator
    }
    omp.terminator
  }
  llvm.return
}

// -----

// CHECK-LABEL:  @_QQmain
llvm.func @_QQmain() {
  %0 = llvm.mlir.constant(0 : index) : i64
  %1 = llvm.mlir.constant(5 : index) : i64
  %2 = llvm.mlir.constant(1 : index) : i64
  %3 = llvm.mlir.constant(1 : i64) : i64
  %4 = llvm.alloca %3 x i32 : (i64) -> !llvm.ptr
// CHECK: omp.taskgroup
  omp.taskgroup   {
    %5 = llvm.trunc %2 : i64 to i32
    llvm.br ^bb1(%5, %1 : i32, i64)
  ^bb1(%6: i32, %7: i64):  // 2 preds: ^bb0, ^bb2
    %8 = llvm.icmp "sgt" %7, %0 : i64
    llvm.cond_br %8, ^bb2, ^bb3
  ^bb2:  // pred: ^bb1
    llvm.store %6, %4 : i32, !llvm.ptr
// CHECK: omp.task
    omp.task   {
// CHECK: llvm.call @[[CALL_FUNC:.*]]({{.*}}) :
      llvm.call @_QFPdo_work(%4) : (!llvm.ptr) -> ()
// CHECK: omp.terminator
      omp.terminator
    }
    %9 = llvm.load %4 : !llvm.ptr -> i32
    %10 = llvm.add %9, %5  : i32
    %11 = llvm.sub %7, %2  : i64
    llvm.br ^bb1(%10, %11 : i32, i64)
  ^bb3:  // pred: ^bb1
    llvm.store %6, %4 : i32, !llvm.ptr
// CHECK: omp.terminator
    omp.terminator
  }
  llvm.return
}
// CHECK: @[[CALL_FUNC]]
llvm.func @_QFPdo_work(%arg0: !llvm.ptr {fir.bindc_name = "i"}) {
  llvm.return
}

// -----

// CHECK-LABEL:  @sub_
llvm.func @sub_() {
  %0 = llvm.mlir.constant(0 : index) : i64
  %1 = llvm.mlir.constant(1 : index) : i64
  %2 = llvm.mlir.constant(1 : i64) : i64
  %3 = llvm.alloca %2 x i32 {bindc_name = "i", in_type = i32, operandSegmentSizes = array<i32: 0, 0>, uniq_name = "_QFsubEi"} : (i64) -> !llvm.ptr
// CHECK: omp.ordered.region
  omp.ordered.region {
    %4 = llvm.trunc %1 : i64 to i32
    llvm.br ^bb1(%4, %1 : i32, i64)
  ^bb1(%5: i32, %6: i64):  // 2 preds: ^bb0, ^bb2
    %7 = llvm.icmp "sgt" %6, %0 : i64
    llvm.cond_br %7, ^bb2, ^bb3
  ^bb2:  // pred: ^bb1
    llvm.store %5, %3 : i32, !llvm.ptr
    %8 = llvm.load %3 : !llvm.ptr -> i32
// CHECK: llvm.add
    %9 = arith.addi %8, %4 : i32
// CHECK: llvm.sub
    %10 = arith.subi %6, %1 : i64
    llvm.br ^bb1(%9, %10 : i32, i64)
  ^bb3:  // pred: ^bb1
    llvm.store %5, %3 : i32, !llvm.ptr
// CHECK: omp.terminator
    omp.terminator
  }
  llvm.return
}

// -----

// CHECK-LABEL:   llvm.func @_QPtarget_map_with_bounds(
// CHECK:           %[[ARG_0:.*]]: !llvm.ptr, %[[ARG_1:.*]]: !llvm.ptr, %[[ARG_2:.*]]: !llvm.ptr) {
// CHECK: %[[C_01:.*]] = llvm.mlir.constant(4 : index) : i64
// CHECK: %[[C_02:.*]] = llvm.mlir.constant(1 : index) : i64
// CHECK: %[[C_03:.*]] = llvm.mlir.constant(1 : index) : i64
// CHECK: %[[C_04:.*]] = llvm.mlir.constant(1 : index) : i64
// CHECK: %[[BOUNDS0:.*]] = omp.map.bounds   lower_bound(%[[C_02]] : i64) upper_bound(%[[C_01]] : i64) stride(%[[C_04]] : i64) start_idx(%[[C_04]] : i64)
// CHECK: %[[MAP0:.*]] = omp.map.info var_ptr(%[[ARG_1]] : !llvm.ptr, !llvm.array<10 x i32>)   map_clauses(tofrom) capture(ByRef) bounds(%[[BOUNDS0]]) -> !llvm.ptr {name = ""}
// CHECK: %[[C_11:.*]] = llvm.mlir.constant(4 : index) : i64
// CHECK: %[[C_12:.*]] = llvm.mlir.constant(1 : index) : i64
// CHECK: %[[C_13:.*]] = llvm.mlir.constant(1 : index) : i64
// CHECK: %[[C_14:.*]] = llvm.mlir.constant(1 : index) : i64
// CHECK: %[[BOUNDS1:.*]] = omp.map.bounds   lower_bound(%[[C_12]] : i64) upper_bound(%[[C_11]] : i64) stride(%[[C_14]] : i64) start_idx(%[[C_14]] : i64)
// CHECK: %[[MAP1:.*]] = omp.map.info var_ptr(%[[ARG_2]] : !llvm.ptr, !llvm.array<10 x i32>)   map_clauses(tofrom) capture(ByRef) bounds(%[[BOUNDS1]]) -> !llvm.ptr {name = ""}
// CHECK: omp.target   map_entries(%[[MAP0]] -> %[[BB_ARG0:.*]], %[[MAP1]]  -> %[[BB_ARG1:.*]] : !llvm.ptr, !llvm.ptr) {
// CHECK:   omp.terminator
// CHECK: }
// CHECK: llvm.return
// CHECK:}

llvm.func @_QPtarget_map_with_bounds(%arg0: !llvm.ptr, %arg1: !llvm.ptr, %arg2: !llvm.ptr) {
  %0 = llvm.mlir.constant(4 : index) : i64
  %1 = llvm.mlir.constant(1 : index) : i64
  %2 = llvm.mlir.constant(1 : index) : i64
  %3 = llvm.mlir.constant(1 : index) : i64
  %4 = omp.map.bounds   lower_bound(%1 : i64) upper_bound(%0 : i64) stride(%3 : i64) start_idx(%3 : i64)
  %5 = omp.map.info var_ptr(%arg1 : !llvm.ptr, !llvm.array<10 x i32>)   map_clauses(tofrom) capture(ByRef) bounds(%4) -> !llvm.ptr {name = ""}
  %6 = llvm.mlir.constant(4 : index) : i64
  %7 = llvm.mlir.constant(1 : index) : i64
  %8 = llvm.mlir.constant(1 : index) : i64
  %9 = llvm.mlir.constant(1 : index) : i64
  %10 = omp.map.bounds   lower_bound(%7 : i64) upper_bound(%6 : i64) stride(%9 : i64) start_idx(%9 : i64)
  %11 = omp.map.info var_ptr(%arg2 : !llvm.ptr, !llvm.array<10 x i32>)   map_clauses(tofrom) capture(ByRef) bounds(%10) -> !llvm.ptr {name = ""}
  omp.target   map_entries(%5 -> %arg3, %11 -> %arg4: !llvm.ptr, !llvm.ptr) {
    omp.terminator
  }
  llvm.return
}

// -----

// CHECK: omp.private {type = private} @x.privatizer : !llvm.struct<{{.*}}> alloc {
omp.private {type = private} @x.privatizer : memref<?xf32> alloc {
// CHECK: ^bb0(%arg0: !llvm.struct<{{.*}}>):
^bb0(%arg0: memref<?xf32>):
  // CHECK: omp.yield(%arg0 : !llvm.struct<{{.*}}>)
  omp.yield(%arg0 : memref<?xf32>)
}

// -----

// CHECK: omp.private {type = firstprivate} @y.privatizer : i64 alloc {
omp.private {type = firstprivate} @y.privatizer : index alloc {
// CHECK: ^bb0(%arg0: i64):
^bb0(%arg0: index):
  // CHECK: omp.yield(%arg0 : i64)
  omp.yield(%arg0 : index)
// CHECK: } copy {
} copy {
// CHECK: ^bb0(%arg0: i64, %arg1: i64):
^bb0(%arg0: index, %arg1: index):
  // CHECK: omp.yield(%arg0 : i64)
  omp.yield(%arg0 : index)
}

// -----

// CHECK-LABEL: llvm.func @omp_cancel_cancellation_point()
func.func @omp_cancel_cancellation_point() -> () {
  omp.parallel {
    // CHECK: omp.cancel cancellation_construct_type(parallel)
    omp.cancel cancellation_construct_type(parallel)
    // CHECK: omp.cancellation_point cancellation_construct_type(parallel)
    omp.cancellation_point cancellation_construct_type(parallel)
    omp.terminator
  }
  return
}

// -----

// CHECK-LABEL: llvm.func @omp_distribute(
// CHECK-SAME:  %[[ARG0:.*]]: i64)
func.func @omp_distribute(%arg0 : index) -> () {
  // CHECK: omp.distribute dist_schedule_static dist_schedule_chunk_size(%[[ARG0]] : i64) {
  omp.distribute dist_schedule_static dist_schedule_chunk_size(%arg0 : index) {
    omp.loop_nest (%iv) : index = (%arg0) to (%arg0) step (%arg0) {
      omp.yield
    }
    omp.terminator
  }
  return
}

// -----

// CHECK-LABEL: llvm.func @omp_teams(
// CHECK-SAME:  %[[ARG0:.*]]: !llvm.ptr, %[[ARG1:.*]]: !llvm.ptr, %[[ARG2:.*]]: i64)
func.func @omp_teams(%arg0 : memref<i32>) -> () {
  // CHECK: omp.teams allocate(%{{.*}} : !llvm.struct<(ptr, ptr, i64)> -> %{{.*}} : !llvm.struct<(ptr, ptr, i64)>)
  omp.teams allocate(%arg0 : memref<i32> -> %arg0 : memref<i32>) {
    omp.terminator
  }
  return
}

// -----

// CHECK-LABEL: llvm.func @omp_ordered(
// CHECK-SAME:  %[[ARG0:.*]]: i64)
func.func @omp_ordered(%arg0 : index) -> () {
  omp.wsloop ordered(1) {
    omp.loop_nest (%iv) : index = (%arg0) to (%arg0) step (%arg0) {
      // CHECK: omp.ordered depend_vec(%[[ARG0]] : i64) {doacross_num_loops = 1 : i64}
      omp.ordered depend_vec(%arg0 : index) {doacross_num_loops = 1 : i64}
      omp.yield
    }
    omp.terminator
  }
  return
}

// -----

// CHECK-LABEL: @omp_taskloop(
// CHECK-SAME:  %[[ARG0:.*]]: i64, %[[ARG1:.*]]: !llvm.ptr, %[[ARG2:.*]]: !llvm.ptr, %[[ARG3:.*]]: i64)
func.func @omp_taskloop(%arg0: index, %arg1 : memref<i32>) {
  // CHECK: omp.parallel {
  omp.parallel {
    // CHECK: omp.taskloop allocate(%{{.*}} : !llvm.struct<(ptr, ptr, i64)> -> %{{.*}} : !llvm.struct<(ptr, ptr, i64)>) {
    omp.taskloop allocate(%arg1 : memref<i32> -> %arg1 : memref<i32>) {
      // CHECK: omp.loop_nest (%[[IV:.*]]) : i64 = (%[[ARG0]]) to (%[[ARG0]]) step (%[[ARG0]]) {
      omp.loop_nest (%iv) : index = (%arg0) to (%arg0) step (%arg0) {
        // CHECK-DAG: %[[CAST_IV:.*]] = builtin.unrealized_conversion_cast %[[IV]] : i64 to index
        // CHECK: "test.payload"(%[[CAST_IV]]) : (index) -> ()
        "test.payload"(%iv) : (index) -> ()
        omp.yield
      }
      omp.terminator
    }
    omp.terminator
  }
  return
}
