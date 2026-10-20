# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_refinement_outcome_arc_release"}

## Real package-bound guests verify Psi_R result selection, gas normalization, output policy and immutable final owners.

import std/[assertions, syncio]
import ../../../src/state/[refinement_outcome, refinement_bootstrap, refinement_dispatch]
import ../../../src/pvm/[machine, step, gas, host_fetch, refinement_exports, output]
import ../../../src/codec/[bounded, composite, work_digest]
import ../../support/[pvm_refinement_outcome, arc_evidence]

proc run(bootstrap: PreparedRefinementBootstrap, limits = refinementLimits()):
    RefinementInvocationResult[RefinementInvocation] =
  ## Only a genuine original bootstrap enters the production runner; terminal triples are never supplied.
  runRefinementInvocation(bootstrap, [], refinementInputs(), ExportOffset(7), limits)
proc check(invocation: RefinementInvocation, kind: WorkKind, used: uint64, exports = 0'u64) =
  ## Validate copied normalized facts and enforce absence of successful bytes on every protocol work error.
  let info = invocation.refinementInfo.value
  assert info.kind == kind and uint64(info.gasUsed) == used
  assert uint32(info.service) == 42 and uint64(info.core) == 5 and uint64(info.item) == 0
  assert uint64(info.exports) == exports and uint64(invocation.refinementExports.value.count) == exports
  if kind != WorkKind.Success:
    assert info.outputBytes == 0 and invocation.refinementOutput.error ==
        RefinementInvocationError.NotSuccess
  else:
    assert info.outputBytes == uint64(invocation.refinementOutput.value.len)

let halt = @[50'u8, 0]
let literal = [refinementImmediate(7, 196608), refinementImmediate(8, 3), halt]
let bootstrap = refinementFixture(literal)
let price = refinementPrice(bootstrap)
let completed = run(bootstrap).value
check(completed, WorkKind.Success, price)
assert completed.refinementOutput.value == @[21'u8, 22, 23]
assert completed.refinementBootstrap.value.bootstrapPackageHash.value.bytes ==
    bootstrap.bootstrapPackageHash.value.bytes
# Read-only output, zero length and unreadable natural ranges all follow Psi_M before local copy policy.
for pointer in [65536'u64, 196608, 69631, 0x100010000'u64, high(uint64)]:
  let guest = refinementFixture([refinementImmediate(7, pointer), refinementImmediate(8, 3), halt])
  var cap = refinementLimits()
  cap.output = OutputByteLimit(if pointer in [65536'u64, 196608]: 3'u64 else: 0'u64)
  let done = run(guest, cap).value
  check(done, WorkKind.Success, refinementPrice(guest))
  let expected = if pointer == 65536: @[11'u8, 12, 13]
    elif pointer == 196608: @[21'u8, 22, 23] else: newSeq[byte]()
  assert done.refinementOutput.value == expected # A readable prefix before a missing page never leaks as partial output.
let zero = refinementFixture([refinementImmediate(7, high(uint64)), refinementImmediate(8, 0), halt])
var zeroPolicy = refinementLimits()
zeroPolicy.output = OutputByteLimit(0)
assert run(zero, zeroPolicy).value.refinementOutput.value.len == 0
let huge = refinementFixture([refinementImmediate(7, 65536), refinementImmediate(8, high(uint64)), halt])
assert run(huge, zeroPolicy).value.refinementOutput.value.len == 0
# Exact and spare gas normalize identically; underfunded instruction pricing preserves unspent credit.
for credit in [0'u64, 1, price-1, price, price+1]:
  let guest = refinementFixture(literal, credit)
  let done = run(guest).value
  check(done, if credit < price: WorkKind.OutOfGas else: WorkKind.Success,
    if credit < price: 0'u64 else: price)
# Host debt and adopted heap OOG consume drained credit exactly once, never debt beyond the original allowance.
let gasInstructions = [@[10'u8, 0], halt]
let gasPrice = refinementPrice(refinementFixture(gasInstructions))
for available in [0'u64, 47, 48]:
  let done = run(refinementFixture(gasInstructions, gasPrice+available)).value
  check(done, if available < 48: WorkKind.OutOfGas else: WorkKind.Success, gasPrice+available)
let heapInstructions = [refinementImmediate(7, 50), @[10'u8, 1], halt]
let heapPrice = refinementPrice(refinementFixture(heapInstructions))
check(run(refinementFixture(heapInstructions, heapPrice+395)).value, WorkKind.OutOfGas, heapPrice+395)
let heapFailure = run(refinementFixture(heapInstructions, heapPrice+396))
assert heapFailure.error == RefinementInvocationError.HostFailure
assert heapFailure.hostError == RefinementDispatchError.LimitExceeded # Local page capacity is not protocol OOG.
# A halt retains exports independently of output readability and declared report-level export-count policy.
let prefix = @[refinementImmediate(7, 65536), refinementImmediate(8, 3), @[10'u8, 8]]
let exportInstructions = @[prefix[0], prefix[1], prefix[2], refinementImmediate(7, 196608),
    refinementImmediate(8, 3), halt]
let exporting = refinementFixture(exportInstructions)
let exportPrice = refinementPrice(exporting)
let exported = run(exporting).value
check(exported, WorkKind.Success, exportPrice+3521, 1)
assert exported.refinementOutput.value == @[21'u8, 22, 23]
let segment = array[4104, byte](exported.refinementExports.value.segment(ExportCount(0)))
assert segment[0] == 11 and segment[1] == 12 and segment[2] == 13
for index in 3..<4104: assert segment[index] == 0
let emptyExportInstructions = @[prefix[0], prefix[1], prefix[2], refinementImmediate(7, high(
    uint64)), refinementImmediate(8, 3), halt]
let emptyExport = refinementFixture(emptyExportInstructions)
let retained = run(emptyExport, zeroPolicy).value
check(retained, WorkKind.Success, refinementPrice(emptyExport)+3521, 1)
assert retained.refinementOutput.value.len == 0
# Panic and physical page fault discard previously appended exports; host OOG does so without inflating used gas.
for ending in [@[0'u8], @[52'u8, 0, 0, 0, 0, 1]]:
  let instructions = @[prefix[0], prefix[1], prefix[2], ending, halt]
  let guest = refinementFixture(instructions)
  check(run(guest).value, WorkKind.Panic, refinementPrice(guest)+3521)
let debtInstructions = @[prefix[0], prefix[1], prefix[2], @[10'u8, 0], halt]
let debtPrice = refinementPrice(refinementFixture(debtInstructions))
check(run(refinementFixture(debtInstructions, debtPrice+3521+47)).value, WorkKind.OutOfGas,
    debtPrice+3521+47)
# BAD/BIG short-circuit all unrelated input/capture/execution/output policies and consume zero gas.
for big in [false, true]:
  let guest = refinementFixture([halt], missing = not big, oversized = big)
  let terminal = runRefinementInvocation(guest, [255'u8], default(RefinementInputs), ExportOffset(
      high(uint64)),
    default(RefinementInvocationLimits)).value
  check(terminal, if big: WorkKind.Big else: WorkKind.Bad, 0)
# Local errors expose their original stage/reason, with no normalizable output owner or partial gas accounting.
assert run(default(PreparedRefinementBootstrap)).error == RefinementInvocationError.InvalidBootstrap
var cap = refinementLimits()
cap.output = OutputByteLimit(2)
assert run(bootstrap, cap).error == RefinementInvocationError.LimitExceeded
assert run(exporting, cap).error == RefinementInvocationError.LimitExceeded # A late output refusal exposes no prior export.
let malformedInputs = runRefinementInvocation(bootstrap, [], default(RefinementInputs),
    ExportOffset(7), refinementLimits())
assert malformedInputs.error == RefinementInvocationError.BootstrapFailure
assert malformedInputs.bootstrapError == RefinementBootstrapError.InvalidInputs
cap = refinementLimits()
cap.capture.encoding = FetchEncodingLimit(0)
let captureFailure = run(bootstrap, cap)
assert captureFailure.error == RefinementInvocationError.BootstrapFailure
assert captureFailure.bootstrapError == RefinementBootstrapError.LimitExceeded
for policy in 0..<3:
  cap = refinementLimits()
  case policy
  of 0: cap.steps = ExecutionStepLimit(0)
  of 1: cap.calls = HostCallLimit(0)
  else: cap.cycles = GasCycleLimit(0)
  let failed = run(exporting, cap)
  assert failed.error == RefinementInvocationError.ExecutionFailure
  assert failed.executionError == (if policy == 0: StepError.StepLimitExceeded
    elif policy == 1: StepError.HostCallLimitExceeded else: StepError.GasCycleLimitExceeded)
cap = refinementLimits()
cap.exports = ExportLimits(items: ElementLimit(0), bytes: ByteLimit(0))
let exportFailure = run(exporting, cap)
assert exportFailure.error == RefinementInvocationError.HostFailure
assert exportFailure.hostError == RefinementDispatchError.LimitExceeded
let fetchInstructions = [refinementImmediate(7, 196608), refinementImmediate(8, 0),
    refinementImmediate(9, 3),
  refinementImmediate(10, 13), refinementImmediate(11, 0), @[10'u8, 2], halt]
cap = refinementLimits()
cap.copy = MemoryByteLimit(2)
let copyFailure = run(refinementFixture(fetchInstructions), cap)
assert copyFailure.error == RefinementInvocationError.HostFailure
assert copyFailure.hostError == RefinementDispatchError.LimitExceeded
let limitedInner = run(refinementFixture([@[10'u8, 9], halt]))
assert limitedInner.error == RefinementInvocationError.HostFailure
assert limitedInner.hostError == RefinementDispatchError.LimitExceeded
# Saved output/source/exports remain immutable after extraction, copied metadata mutation and independent replay.
var changed = completed.refinementOutput.value
changed[0] = 255
var info = completed.refinementInfo.value
info.kind = WorkKind.Bad
info.gasUsed = Gas(high(uint64))
assert completed.refinementOutput.value == @[21'u8, 22, 23]
check(completed, WorkKind.Success, price)
assert uint64(run(exporting).value.refinementInfo.value.exports) == 1
assert default(RefinementInvocation).refinementInfo.error == RefinementInvocationError.Uninitialized
assert default(RefinementInvocation).refinementOutput.error ==
    RefinementInvocationError.Uninitialized
assert default(RefinementInvocation).refinementExports.error ==
    RefinementInvocationError.Uninitialized
assert default(RefinementInvocation).refinementBootstrap.error ==
    RefinementInvocationError.Uninitialized
# Fresh bootstraps, final copied bytes and export successors retire each cycle, including a later output refusal.
proc cycle() =
  ## No original mutable source or transient terminal CPU survives the complete normalized owner lifetime.
  let fresh = refinementFixture(exportInstructions)
  check(run(fresh).value, WorkKind.Success, exportPrice+3521, 1)
  var limited = refinementLimits()
  limited.output = OutputByteLimit(2)
  assert run(fresh, limited).error == RefinementInvocationError.LimitExceeded
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_refinement_outcome", 1000, before, after)
echo "PVM refinement outcome passed"
echo "ARC_RELEASE cycles=1000 unchanged"
