# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_computed_batch_arc_release"}

## Real shared-context batches prove canonical wire, reporter union, bounded refusal and immutable lifetime behavior.

import std/[assertions, syncio]
import ../../../src/state/[computed_batch, computed_envelope, computed_credentials,
  computed_guarantors,
  computed_roster, computed_transition, computed_profile, store]
import ../../../src/codec/[bounded, assurances, guarantees, state_safrole]
import ../../support/[pvm_computed_batch, arc_evidence]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reject new hashing after original computation and real signature verification complete.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe real hashing counters without manufacturing successful crypto.
proc expect[T](outcome: ComputedBatchResult[T], reason: ComputedBatchError) =
  ## Check exact refusal alternatives before any successful extraction.
  assert outcome.error == reason, "batch reason mismatch"
proc checkWire(sources: seq[ComputedGuaranteeEnvelope], batch: ComputedGuaranteeBatch) =
  ## Independently frame small count and concatenate unchanged standalone tuples, then check maintained codec roundtrip.
  var expected = @[byte(sources.len)]
  for source in sources:
    for octet in source.computedEnvelopeBytes.value:
      expected.add(octet) # Literal count1..3 needs exactly one canonical octet.
  let wire = batch.computedBatchBytes.value
  assert wire == expected, "one outer count followed by exact source guarantees"
  let config = GuaranteeConfig(cores: CoreCount(3), validators: ValidatorCount(9),
      maxBytes: ByteLimit(uint64(wire.len)))
  let decoded = decodeGuarantees(wire, config).value
  assert decoded.count == sources.len and decoded.consumed == wire.len
  var encoded = newSeq[byte](wire.len)
  assert encodeOwnedGuarantees(decoded.owner, encoded).value == wire.len
  assert encoded == wire
proc compare(a, b: StateEdKey): int =
  ## Independent first-difference order witness for copied full keys.
  let left = array[32, byte](a)
  let right = array[32, byte](b)
  for i in 0..<32:
    if left[i] != right[i]: return if left[i] < right[i]: -1 else: 1 # Ignore no suffix bytes.
  0
let sources = batchEnvelopes()
let broad = batchLimits()
let done = prepareComputedBatch(sources, broad).value
let info = done.computedBatchInfo.value
assert info.guarantees == 2 and info.reporters == 6
checkWire(sources, done)
for count in 1..2:
  let batch = prepareComputedBatch(sources.toOpenArray(0, count-1), broad).value
  assert batch.computedBatchInfo.value.guarantees == count
  for index in 0..<count:
    assert batch.computedBatchSourceAt(ComputedBatchIndex(uint64(
        index))).value.computedEnvelopeBytes.value == sources[index].computedEnvelopeBytes.value
for index in 1..<info.reporters:
  let prior = done.computedBatchReporterAt(ComputedBatchReporterIndex(uint64(index-1))).value
  let current = done.computedBatchReporterAt(ComputedBatchReporterIndex(uint64(index))).value
  assert compare(prior, current) < 0, "reporter union strictly sorts every complete key"
for source in sources:
  for index in 0..<source.computedEnvelopeInfo.value.reporters:
    let key = source.computedEnvelopeReporterAt(ComputedReporterIndex(uint64(index))).value
    var occurrences = 0
    for ordinal in 0..<info.reporters:
      if compare(key, done.computedBatchReporterAt(ComputedBatchReporterIndex(uint64(
          ordinal))).value) == 0:
        inc occurrences # Set equality requires each genuine reporter exactly once.
    assert occurrences == 1
let repeated = batchEnvelopes(repeatReporter = true)
let shared = prepareComputedBatch(repeated, broad).value
assert shared.computedBatchInfo.value.reporters == 5, "distinct credential indices sharing Ed identity deduplicate"
checkWire(repeated, shared)
var exact = broad
exact.bytes = ByteLimit(info.bytes)
exact.guarantees = ElementLimit(2)
exact.reporters = ElementLimit(6)
expect(prepareComputedBatch(sources, exact), ComputedBatchError.None)
for which in 0..<4:
  var short = exact
  case which
  of 0: short.bytes = ByteLimit(info.bytes-1) # Reject one byte less than the complete canonical wire.
  of 1: short.guarantees = ElementLimit(1) # Count includes every original immutable source.
  of 2: short.reporters = ElementLimit(5) # Unique actual identities define set capacity.
  else: short.headerBytes = ByteLimit(0) # Header cap applies before candidate encoding.
  expect(prepareComputedBatch(sources, short), ComputedBatchError.LimitExceeded)
expect(prepareComputedBatch([], broad), ComputedBatchError.InvalidSource)
expect(prepareComputedBatch([default(ComputedGuaranteeEnvelope)], broad),
    ComputedBatchError.InvalidSource)
expect(prepareComputedBatch([sources[0], default(ComputedGuaranteeEnvelope)], broad),
    ComputedBatchError.InvalidSource)
expect(prepareComputedBatch([sources[0], sources[0]], broad), ComputedBatchError.NonCanonical)
expect(prepareComputedBatch([sources[1], sources[0]], broad), ComputedBatchError.NonCanonical)
let foreign = batchEnvelopes()
expect(prepareComputedBatch([sources[0], foreign[1]], broad), ComputedBatchError.ContextMismatch)
expect(done.computedBatchSourceAt(ComputedBatchIndex(high(uint64))),
    ComputedBatchError.InvalidIndex)
expect(done.computedBatchReporterAt(ComputedBatchReporterIndex(6)), ComputedBatchError.InvalidIndex)
expect(default(ComputedGuaranteeBatch).computedBatchInfo, ComputedBatchError.Uninitialized)
var wire = done.computedBatchBytes.value
wire[0] = 0
var facts = done.computedBatchInfo.value
facts.guarantees = 0
var key = done.computedBatchReporterAt(ComputedBatchReporterIndex(0)).value
key = default(StateEdKey)
checkWire(sources, done)
assert done.computedBatchInfo.value.guarantees == 2
reset(1)
expect(prepareComputedBatch(sources, broad), ComputedBatchError.None)
assert hashes() == 0, "composition and retained source queries perform no hashing"
reset(0)
proc detached(): ComputedGuaranteeBatch =
  ## Retain every source after all original caller-owned lists and fixtures retire.
  prepareComputedBatch(batchEnvelopes(), batchLimits()).value
let retained = detached()
assert retained.computedBatchInfo.value.reporters == 6
proc cycle(sources: seq[ComputedGuaranteeEnvelope], limits: ComputedBatchLimits) =
  ## Release batch wire, reporter set, source list, copies and a late union-budget refusal.
  let batch = prepareComputedBatch(sources, limits).value
  discard batch.computedBatchBytes.value
  discard batch.computedBatchSourceAt(ComputedBatchIndex(1)).value
  discard batch.computedBatchReporterAt(ComputedBatchReporterIndex(5)).value
  var short = limits
  short.reporters = ElementLimit(5)
  expect(prepareComputedBatch(sources, short), ComputedBatchError.LimitExceeded)
cycle(sources, broad)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(sources, broad) # Fresh roots/copies retire on every bounded iteration.
let after = getOccupiedMem()
assert before == after, "batch ARC release"
recordArcRelease("pvm_computed_batch", 1000, before, after)
echo "PVM computed batch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
