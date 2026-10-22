# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_annulled_outputs_arc_release"}

## Genuine selected yield presence survives zero hashes, cancellation, pair ordering and exact canonical wire limits.
import std/[assertions, syncio]
import ../../../src/state/[accumulation_annulled_outputs, accumulation_annulment,
  accumulation_outcome, accumulation_effects, store]
import ../../../src/codec/[bounded, state_accounts, state_outputs, state_layout, state_trie]
import ../../support/[accumulation_annulment_context, accumulation_batch_context, arc_evidence]

# Selection and C(16)-format encoding do not compute or publish state roots.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc policy(outcomes = 2'u64, items = 2'u64, bytes = 73'u64): AnnulmentOutputLimits =
  ## Independent limits count all inspected producers and the whole selected pair payload.
  AnnulmentOutputLimits(outcomes: ElementLimit(outcomes), log: OutputLogConfig(items: ElementLimit(
      items), maxBytes: ByteLimit(bytes)))
let source = annulmentFixture()
let first = annulmentOriginal(source, 0)
let second = annulmentOriginal(source, 1)
let conflicts = annulmentPrepared(source, first, second)
assert second.outcomeInfo.value.hasYield, "a real original yield exists before cancellation"
failHash(1)
let canceled = prepareAnnulmentOutputs(conflicts, policy(items = 0, bytes = 1)).value
let canceledInfo = canceled.annulmentOutputsInfo.value
assert canceledInfo.outcomes == 2 and canceledInfo.outputs == 0 and canceledInfo.encodedBytes == 1, "N clears selected yield without forgetting original source traversal"
assert canceled.annulmentOutputsEntry.value.value == @[0'u8], "empty output retains its canonical count prefix"
assert canceled.annulmentOutputsSource.value.annulmentInfo.value.annulled == 1, "retain exact conflict certificate, not just copied flags"
let canceledIndex = canceled.annulmentOutputAt(AnnulmentOutputIndex(0))
assert canceledIndex.error == AnnulmentOutputsError.InvalidIndex, "annulled yield cannot be extracted as a zero pair"
let noPrefix = prepareAnnulmentOutputs(conflicts, policy(items = 0, bytes = 0))
assert noPrefix.error == AnnulmentOutputsError.LimitExceeded, "even empty selected output requires one complete prefix byte"
let shortSource = prepareAnnulmentOutputs(conflicts, policy(outcomes = 1, items = 0, bytes = 1))
assert shortSource.error == AnnulmentOutputsError.LimitExceeded, "canceled producers still consume inspection limits"
let invalid = prepareAnnulmentOutputs(default(PreparedAccumulationAnnulment), policy())
assert invalid.error == AnnulmentOutputsError.InvalidSource, "default source cannot fabricate an initialized empty output set"
let emptySource = prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value, [],
    default(AccumulationAnnulmentLimits)).value
let empty = prepareAnnulmentOutputs(emptySource, policy(outcomes = 0, items = 0, bytes = 1)).value
assert empty.annulmentOutputsInfo.value.outcomes == 0 and
    empty.annulmentOutputsInfo.value.outputs == 0
assert empty.annulmentOutputsEntry.value.value == @[0'u8]
assert hashCalls() == 0, "source selection and canonical encoding are hash free"
failHash(0)
# A real all-zero commitment is present, rather than a sentinel for absent output.
let zeroSource = annulmentFixture(supervisor = 99, zeroYield = true)
let zeroFirst = annulmentOriginal(zeroSource, 0)
let zeroSecond = annulmentOriginal(zeroSource, 1)
let zeroSelection = annulmentPrepared(zeroSource, zeroFirst, zeroSecond)
assert zeroSecond.outcomeInfo.value.hasYield, "zero witness actually executed yield"
let originalZero = zeroSecond.outcomeContext.value.effectYield.value
assert array[32, byte](originalZero) == default(array[32, byte]), "guest supplied thirty-two genuinely zero readable bytes"
failHash(1)
let zero = prepareAnnulmentOutputs(zeroSelection, policy(items = 1, bytes = 37)).value
let zeroInfo = zero.annulmentOutputsInfo.value
assert zeroInfo.outputs == 1 and zeroInfo.encodedBytes == 37, "present zero commitment consumes a complete output pair"
let zeroPair = zero.annulmentOutputAt(AnnulmentOutputIndex(0)).value
assert uint32(zeroPair.service) == 99 and array[32, byte](zeroPair.commitment) == default(array[32, byte])
var expectedZero = newSeq[byte](37)
expectedZero[0] = 1
expectedZero[1] = 99 # One natural count, E4 service and exactly32 zero commitment bytes.
let zeroEntry = zero.annulmentOutputsEntry.value
assert array[31, byte](zeroEntry.key) == array[31, byte](chapterKey(StateChapter(16)))
assert zeroEntry.value == expectedZero, "canonical byte-exact zero commitment output"
var copied = zeroPair
copied.service = ServiceIndex(42)
assert uint32(zero.annulmentOutputAt(AnnulmentOutputIndex(0)).value.service) == 99, "copied pairs cannot mutate retained service identity"
var encodedCopy = zero.annulmentOutputsEntry.value
encodedCopy.value[0] = 0
assert zero.annulmentOutputsEntry.value.value == expectedZero, "encoding returns independent bytes on every query"
let huge = zero.annulmentOutputAt(AnnulmentOutputIndex(high(uint64)))
assert huge.error == AnnulmentOutputsError.InvalidIndex, "full-width invalid ordinal is checked before narrowing"
assert hashCalls() == 0
failHash(0)
# Equal commitment bytes from different services remain distinct pairs, sorted by numeric service.
let pairedSource = annulmentFixture(supervisor = 99, parentYield = true)
let a = annulmentOriginal(pairedSource, 0)
let b = annulmentOriginal(pairedSource, 1)
assert a.outcomeInfo.value.hasYield and b.outcomeInfo.value.hasYield, "two real producers yielded"
let reversed = prepareAccumulationAnnulment(pairedSource.inputs, pairedSource.state.snapshot.value,
    [b, a], annulmentPolicy()).value
failHash(1)
let paired = prepareAnnulmentOutputs(reversed, policy()).value
assert paired.annulmentOutputsInfo.value.outputs == 2 and
    paired.annulmentOutputsInfo.value.encodedBytes == 73
let left = paired.annulmentOutputAt(AnnulmentOutputIndex(0)).value
let right = paired.annulmentOutputAt(AnnulmentOutputIndex(1)).value
assert uint32(left.service) == 42 and uint32(right.service) == 99, "execution/certificate array order cannot change pair order"
assert array[32, byte](left.commitment) == array[32, byte](right.commitment), "equal hashes do not deduplicate distinct service/hash pairs"
let wire = paired.annulmentOutputsEntry.value.value
assert wire.len == 73 and wire[0] == 2 and wire[1] == 42 and wire[37] == 99, "exact count and E4 service positions in canonical encoding"
for index in 0..<32:
  assert wire[5+index] == array[32, byte](left.commitment)[index]
  assert wire[41+index] == array[32, byte](right.commitment)[index]
for mode in 0..<3:
  var short = policy()
  case mode
  of 0: short.outcomes = ElementLimit(1) # Bound both original inspections.
  of 1: short.log.items = ElementLimit(1) # Both service/hash pairs consume capacity.
  else: short.log.maxBytes = ByteLimit(72) # Complete two-pair wire payload requires73 bytes.
  let refused = prepareAnnulmentOutputs(reversed, short)
  assert refused.error == AnnulmentOutputsError.LimitExceeded, "every independent output ceiling refuses atomically"
assert hashCalls() == 0
failHash(0)
let absent = default(PreparedAnnulmentOutputs)
assert absent.annulmentOutputsInfo.error == AnnulmentOutputsError.Uninitialized
assert absent.annulmentOutputsSource.error == AnnulmentOutputsError.Uninitialized
assert absent.annulmentOutputsEntry.error == AnnulmentOutputsError.Uninitialized
var detached = default(PreparedAnnulmentOutputs)
block released_sources:
  let temporary = annulmentFixture(supervisor = 99, zeroYield = true)
  let source = annulmentPrepared(temporary, annulmentOriginal(temporary, 0), annulmentOriginal(
      temporary, 1))
  detached = prepareAnnulmentOutputs(source, policy()).value
assert detached.annulmentOutputsInfo.value.outputs == 1, "selected pairs and source certificate survive caller release"
let before = getOccupiedMem()
for iteration in 0..<1000:
  let retained = prepareAnnulmentOutputs(reversed, policy()).value
  assert retained.annulmentOutputsInfo.value.outputs == 2
  assert retained.annulmentOutputsEntry.value.value.len == 73
  let canceled = prepareAnnulmentOutputs(conflicts, policy(items = 0, bytes = 1)).value
  assert canceled.annulmentOutputsInfo.value.outputs == 0
let after = getOccupiedMem()
assert before == after, "selected pair arrays, source owners and encoded byte copies release across 1000 cycles"
recordArcRelease("pvm_annulled_outputs", 1000, before, after)
echo "PVM annulled outputs passed"
echo "ARC_RELEASE cycles=1000 unchanged"
