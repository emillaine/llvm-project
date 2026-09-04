// RUN: mlir-opt -allow-unregistered-dialect %s -split-input-file -test-greedy-patterns="top-down max-iterations=1" -verify-diagnostics | FileCheck %s

// A rewrite can create an unreachable block after the iteration's initial
// unreachable-block sweep. Do not process its self-referential operation.
// CHECK-LABEL: func.func @insert_unreachable
// CHECK-NOT: arith.addi
// CHECK: return
func.func @insert_unreachable(%arg: i32) {
  "test.greedy_create_block"(%arg) {mode = "unreachable"} : (i32) -> ()
  cf.br ^exit
^exit:
  return
}

// -----

// A block connected before the rewrite returns is processed in this iteration,
// without relying on a fresh reachability cache in the next iteration.
// CHECK-LABEL: func.func @connect_before_return
// CHECK-NOT: "test.greedy_create_block"
// CHECK: return
func.func @connect_before_return(%cond: i1) {
  // expected-remark @+1 {{processed reachable block}}
  "test.greedy_create_block"(%cond) {mode = "reachable"} : (i1) -> ()
  cf.br ^exit
^exit:
  return
}

// -----

// Inserting a new entry can disconnect the old entry without editing its
// terminator.
// CHECK-LABEL: func.func @insert_entry
// CHECK-NEXT: return
// CHECK-NEXT: }
func.func @insert_entry() {
  "test.greedy_create_block"() {mode = "entry"} : () -> ()
  "test.greedy_create_block"() {mode = "observe"} : () -> ()
  cf.br ^exit
^exit:
  return
}

// -----

// An in-place successor change can disconnect a block.
// CHECK-LABEL: func.func @redirect
// CHECK-NOT: "test.greedy_create_block"
// CHECK: return
func.func @redirect() {
  "test.greedy_create_block"() {mode = "redirect"} : () -> ()
  cf.br ^body
^body:
  "test.greedy_create_block"() {mode = "observe"} : () -> ()
  cf.br ^exit
^exit:
  return
}

// -----

// Populate the source cache, then move and erase a nonentry block in one
// rewrite. The next query must not inspect the erased block in that cache.
// CHECK-LABEL: func.func @move_then_erase
// CHECK-NOT: "test.greedy_create_block"
// CHECK: return
func.func @move_then_erase() {
  "test.greedy_create_block"() {mode = "move-erase"} : () -> ()
  // expected-remark @+1 {{processed reachable block}}
  "test.greedy_create_block"() {mode = "observe"} : () -> ()
  cf.br ^body
^body:
  cf.br ^exit
^exit:
  return
}

// -----

// Merging a block preserves reachability of its successors. The cache is
// populated before the rewrite, and the observer must run in this iteration.
// CHECK-LABEL: func.func @merge
// CHECK-NOT: "test.greedy_create_block"
// CHECK: return
func.func @merge() {
  "test.greedy_create_block"() {mode = "merge"} : () -> ()
  cf.br ^body
^body:
  cf.br ^exit
^exit:
  // expected-remark @+1 {{processed reachable block}}
  "test.greedy_create_block"() {mode = "observe"} : () -> ()
  return
}

// -----

// Merging a block and dropping one of its successors must force a rescan:
// preserving reachability based only on the erased block would process ^dead.
// CHECK-LABEL: func.func @merge_disconnect
// CHECK-NOT: "test.greedy_create_block"
// CHECK: return
func.func @merge_disconnect(%cond: i1) {
  "test.greedy_create_block"() {mode = "merge-disconnect"} : () -> ()
  cf.br ^body
^body:
  cf.cond_br %cond, ^exit, ^dead
^dead:
  "test.greedy_create_block"() {mode = "observe"} : () -> ()
  return
^exit:
  // expected-remark @+1 {{processed reachable block}}
  "test.greedy_create_block"() {mode = "observe"} : () -> ()
  return
}
