# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_computed_inclusion_arc_release"}

## Actual signed guarantee-bearing candidates prove exact inclusion, refusal, provenance and lifetime behavior.

import std/assertions
import std/syncio
import ../../../src/state/computed_inclusion as state_computed_inclusion
import ../../../src/state/computed_batch as state_computed_batch
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/block_codec as codec_block_codec
import ../../support/pvm_computed_inclusion
import ../../support/pvm_computed_batch
import ../../support/testing_arc_evidence

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Force any unexpected new hash call to refuse after original signing/admission completes.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe copied backend counters without faking a successful result.
proc expect[T](outcome: ComputedInclusionResult[T], reason: ComputedInclusionError) =
  ## Check exact selected reasons before successful extraction.
  assert outcome.error == reason, "computed inclusion reason"
let source = inclusionFixture()
let size = source.computedBatchInfo.value.bytes
let exact = ByteLimit(size)
let done = bindComputedInclusion(source, exact).value
assert done.computedInclusionSource.value.computedBatchBytes.value ==
    source.computedBatchBytes.value
let component = done.computedInclusionComponent.value
let info = component.componentInfo.value
assert info.records == 2 and uint64(info.consumed) == size
var wire = newSeq[byte](info.consumed)
assert encodeComponent(component, wire).error == FrameError.None
assert wire == source.computedBatchBytes.value
expect(bindComputedInclusion(source, ByteLimit(size-1)), ComputedInclusionError.LimitExceeded)
expect(bindComputedInclusion(source, ByteLimit(0)), ComputedInclusionError.LimitExceeded)
expect(bindComputedInclusion(default(ComputedGuaranteeBatch), exact),
    ComputedInclusionError.InvalidSource)
let absent = prepareComputedBatch(batchEnvelopes(), batchLimits()).value
expect(bindComputedInclusion(absent, ByteLimit(100000)), ComputedInclusionError.GuaranteeMismatch)
let wrong = inclusionFixture(changed = true)
expect(bindComputedInclusion(wrong, ByteLimit(100000)), ComputedInclusionError.GuaranteeMismatch)
expect(default(IncludedComputedGuarantees).computedInclusionSource,
    ComputedInclusionError.Uninitialized)
expect(default(IncludedComputedGuarantees).computedInclusionStage,
    ComputedInclusionError.Uninitialized)
expect(default(IncludedComputedGuarantees).computedInclusionComponent,
    ComputedInclusionError.Uninitialized)
wire[0] = 0
var copied = done.computedInclusionStage.value.value
copied.snapshot = default(StateStoreSnapshot)
assert done.computedInclusionSource.value.computedBatchInfo.value.guarantees == 2
assert done.computedInclusionStage.value.error == BlockTransitionError.None
reset(1)
expect(bindComputedInclusion(source, exact), ComputedInclusionError.None)
expect(bindComputedInclusion(wrong, ByteLimit(100000)), ComputedInclusionError.GuaranteeMismatch)
assert hashes() == 0, "exact inclusion performs no crypto"
reset(0)
proc detached(): IncludedComputedGuarantees =
  ## Retain genuine batch, signed candidate and posterior after caller handles retire.
  let batch = inclusionFixture()
  bindComputedInclusion(batch, ByteLimit(100000)).value
let retained = detached()
assert retained.computedInclusionComponent.value.componentInfo.value.records == 2
proc cycle(source, wrong: ComputedGuaranteeBatch, bytes: ByteLimit) =
  ## Release full comparison copies and completed owners; late mismatch retains no prefix.
  let included = bindComputedInclusion(source, bytes).value
  discard included.computedInclusionStage.value
  discard included.computedInclusionSource.value
  discard included.computedInclusionComponent.value
  expect(bindComputedInclusion(wrong, bytes), ComputedInclusionError.GuaranteeMismatch)
cycle(source, wrong, exact)
let before = getOccupiedMem()
for i in 0..<1000: cycle(source, wrong, exact) # Fresh successful and mismatching comparisons retire every cycle.
let after = getOccupiedMem()
assert before == after, "computed inclusion ARC release"
recordArcRelease("pvm_computed_inclusion", 1000, before, after)
echo "PVM computed inclusion passed"
echo "ARC_RELEASE cycles=1000 unchanged"
