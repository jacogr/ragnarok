# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_preimage_integration_arc_release"}

## Signed lookup integration freezes exact request/value bytes, complete-map roots and inherited source ownership.

import std/assertions
import std/envvars
import std/syncio
import ../../../src/state/accumulation_current_preimages as state_accumulation_current_preimages
import ../../../src/state/accumulation_preimages as state_accumulation_preimages
import ../../../src/state/accumulation_current_activity as state_accumulation_current_activity
import ../../../src/state/accumulation_activity as state_accumulation_activity
import ../../../src/state/accumulation_current_validators as state_accumulation_current_validators
import ../../../src/state/core_service_activity as state_core_service_activity
import ../../../src/state/preimages as state_preimages
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/header as codec_header
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/crypto/primitives as crypto_primitives
import ../../support/state_accumulation_current_activity_context
import ../../support/state_accumulation_provision_integration
import ../../support/state_report_context
import ../../support/testing_arc_evidence

# Failure injection starts after authenticated blocks and every earlier private stage have been built.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

# All authority remains in the retained source; these policies only bound actual work.
proc limits(items = 3'u64, bytes = 4'u64): AccumulationPreimageLimits =
  AccumulationPreimageLimits(items: ElementLimit(items), bytes: ByteLimit(bytes))

proc activity(source: PreparedCurrentAccumulationValidators): PreparedCurrentAccumulationActivity =
  ## Prepare the preceding genuine C(13) candidate with sufficient independent resource ceilings.
  prepareCurrentAccumulationActivity(source, AccumulationActivityConfig(componentBytes: ByteLimit(1024),
    preimages: PreimageLimits(items: ElementLimit(3), perBlob: ByteLimit(3),
        totalBlobBytes: ByteLimit(4)),
    incoming: ElementLimit(2), available: ElementLimit(1), digests: ElementLimit(2),
    assurances: ElementLimit(5), provisions: ElementLimit(2), accumulation: ElementLimit(2),
    services: ElementLimit(2), activityBytes: ByteLimit(4096))).value

# Derive only namespace keys with existing primitives; literal raw bytes and histories are independent of integration.
proc valueEntry(service: uint32, bytes: seq[byte]): StateEntry =
  let hash = ServicePreimageHash(array[32, byte](blake2b256(bytes).value))
  servicePreimageEntry(ServiceIndex(service), hash, bytes,
    ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(uint64(bytes.len)))).value

proc expected(fixture: CurrentActivityFixture, prior: StateStoreSnapshot, blobs, provided: bool,
    slot: uint32): StateStoreSnapshot =
  ## Enumerate every independently known source key, then add only literal expected fulfillment records.
  var rows: seq[StateEntry] = @[]
  let requests = @[integrationRequest(42, @[73'u8]), integrationRequest(99, @[]),
    integrationRequest(99, @[81'u8, 82, 83])]
  var history = @[1'u8]
  for shift in 0..<4: history.add(byte((slot shr (8*shift)) and 255)) # One canonical E4 supplied slot.
  for original in fixture.entries:
    var bytes = prior.lookup(original.key).value.bytes
    if blobs:
      for request in requests:
        if array[31, byte](request.key) == array[31, byte](original.key):
          bytes = history # Existing guest fulfillment has the same authenticated timestamp.
    rows.add(StateEntry(key: original.key, value: bytes))
  rows.add(StateEntry(key: chapterKey(StateChapter(16)),
    value: prior.lookup(chapterKey(StateChapter(16))).value.bytes)) # This absent original chapter was added by finalization.
  if provided:
    for entry in [valueEntry(42, @[73'u8]), valueEntry(99, @[81'u8])]:
      assert prior.lookup(entry.key).value.bytes == entry.value
      rows.add(entry) # Genuine earlier guest values remain, without a second insertion.
  assert rows.len == prior.commitment.entries, "known keys exhaust the complete source mapping"
  if blobs:
    for index, entry in [valueEntry(42, @[73'u8]), valueEntry(99, @[]),
        valueEntry(99, @[81'u8, 82, 83])]:
      if not (provided and index == 0): rows.add(entry) # Only two new keys when the guest already provided service 42.
  newStateStore(rows, state_report_context.limits()).value.snapshot.value

proc witness(base: OwnedReport, blobs = false, combined = false, provided = false,
    slot = 2'u32): PreparedCurrentAccumulationPreimages =
  ## Exact full-map equality proves every unrelated chapter/account and completed guest effect is preserved.
  let fixture = currentActivityFixture(base, blobs = blobs, available = combined,
    guarantees = (if combined: 2 else: 0), provided = provided, slot = slot)
  let source = activity(fixture.source)
  let prior = source.currentActivityState.value
  let oracle = expected(fixture, prior, blobs, provided, slot)
  let outcome = prepareCurrentAccumulationPreimages(source, limits())
  assert outcome.error == CurrentAccumulationPreimageError.None
  result = outcome.value
  let state = result.currentPreimagesState.value
  let facts = result.currentPreimagesInfo.value
  assert uint32(facts.slot) == slot
  assert facts.admitted.items == (if blobs: 3 else: 0)
  assert facts.admitted.services == (if blobs: 2 else: 0)
  assert uint64(facts.admitted.bytes) == uint64(if blobs: 4 else: 0)
  assert array[32, byte](state.commitment.root) == array[32, byte](oracle.commitment.root)
  assert state.commitment.entries == oracle.commitment.entries
  assert sameStateSnapshot(prior, result.currentPreimagesSource.value.currentActivityState.value)
  assert sameStateSnapshot(source.currentActivityPreimages.value.preimagePrior.value,
    result.currentPreimagesSource.value.currentActivityPreimages.value.preimagePrior.value)
  for number in [3'u8, 13, 14, 15, 16, 250]:
    let key = chapterKey(StateChapter(number))
    assert state.lookup(key).value.bytes == prior.lookup(key).value.bytes, "earlier chapters unchanged"
  if blobs:
    for index, request in [integrationRequest(42, @[73'u8]), integrationRequest(99, @[]),
        integrationRequest(99, @[81'u8, 82, 83])]:
      assert prior.lookup(request.key).value.bytes == (if provided and index == 0:
        @[1'u8, byte(slot), 0, 0, 0] else: @[0'u8]), "no mutation of original activity map"
      assert state.lookup(request.key).value.bytes == @[1'u8, byte(slot), 0, 0, 0]
    assert state.lookup(valueEntry(99, @[]).key).value.byteLength == 0, "empty value is present, not absent"
  let retry = prepareCurrentAccumulationPreimages(source, limits()).value.currentPreimagesState.value
  assert array[32, byte](retry.commitment.root) == array[32, byte](state.commitment.root), "source reuse is deterministic"

proc policies(source: PreparedCurrentAccumulationActivity) =
  ## Early policy refusals perform no hashing; exact and full-width limits use actual admitted populations.
  for short in [limits(items = 2), limits(bytes = 3)]:
    failHash(1)
    assert prepareCurrentAccumulationPreimages(source, short).error ==
        CurrentAccumulationPreimageError.LimitExceeded
    assert hashCalls() == 0
  failHash(0)
  for policy in [limits(), limits(high(uint64), high(uint64))]:
    assert prepareCurrentAccumulationPreimages(source, policy).error ==
        CurrentAccumulationPreimageError.None

proc backend(source: PreparedCurrentAccumulationActivity) =
  ## Refuse both the first request key and the last complete-map hash after earlier successful preparation.
  let prior = source.currentActivityState.value
  let root = array[32, byte](prior.commitment.root)
  let request = integrationRequest(42, @[73'u8]).key
  failHash(0)
  discard prepareCurrentAccumulationPreimages(source, limits()).value
  let total = hashCalls()
  assert total > 6, "fulfillment namespace keys precede full-map Merklization"
  for after in [0.cint, 1.cint, total-1]:
    failAfter(after)
    let refused = prepareCurrentAccumulationPreimages(source, limits())
    assert refused.error == CurrentAccumulationPreimageError.PreimageFailure
    assert refused.preimageError == PreimageTransitionError.BackendFailure
    assert array[32, byte](source.currentActivityState.value.commitment.root) == root
    assert prior.lookup(request).value.bytes == @[0'u8]
  failHash(0)
  assert prepareCurrentAccumulationPreimages(source, limits()).error ==
      CurrentAccumulationPreimageError.None

proc cycle(source: PreparedCurrentAccumulationActivity) =
  ## Scoped success and early/late failures release every derived owner before the next iteration.
  failHash(0)
  let candidate = prepareCurrentAccumulationPreimages(source, limits()).value
  assert candidate.currentPreimagesInfo.value.admitted.items == 3
  let total = hashCalls()
  failAfter(0)
  assert prepareCurrentAccumulationPreimages(source, limits()).preimageError ==
      PreimageTransitionError.BackendFailure
  failAfter(total-1)
  assert prepareCurrentAccumulationPreimages(source, limits()).preimageError ==
      PreimageTransitionError.BackendFailure
  failHash(0)

proc main() {.raises.} =
  ## Native fixtures supply the static report; real signed block preparation and guests establish all source authority.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<wire.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  discard witness(base)
  discard witness(base, blobs = true)
  discard witness(base, blobs = true, combined = true)
  discard witness(base, blobs = true, provided = true)
  discard witness(base, blobs = true, slot = 12)
  let source = activity(currentActivityFixture(base, blobs = true).source)
  policies(source)
  backend(source)
  let empty = default(PreparedCurrentAccumulationPreimages)
  assert empty.currentPreimagesSource.error == CurrentAccumulationPreimageError.Uninitialized
  assert empty.currentPreimagesInfo.error == CurrentAccumulationPreimageError.Uninitialized
  assert empty.currentPreimagesState.error == CurrentAccumulationPreimageError.Uninitialized
  failHash(1)
  let invalid = prepareCurrentAccumulationPreimages(default(PreparedCurrentAccumulationActivity),
      limits())
  assert invalid.error == CurrentAccumulationPreimageError.InvalidSource
  assert hashCalls() == 0
  failHash(0)
  var retained = default(PreparedCurrentAccumulationPreimages)
  block:
    let local = activity(currentActivityFixture(base, blobs = true).source)
    retained = prepareCurrentAccumulationPreimages(local, limits()).value
  var facts = retained.currentPreimagesInfo.value
  facts.slot = HeaderSlot(99)
  facts.admitted.items = 0
  assert uint32(retained.currentPreimagesInfo.value.slot) == 2
  assert retained.currentPreimagesInfo.value.admitted.items == 3
  let detached = retained.currentPreimagesState.value
  retained = default(PreparedCurrentAccumulationPreimages)
  assert detached.lookup(valueEntry(42, @[73'u8]).key).value.bytes == @[73'u8], "snapshot outlives its plan"
  cycle(source)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(source) # Genuine earlier source remains fixed; every new result is released.
  let after = getOccupiedMem()
  assert before == after, "bound preimage integration ARC release"
  recordArcRelease("pvm_current_preimage_integration", 1000, before, after)
  echo "PVM current preimage integration passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fixture I/O failure is a strict failed native run.
except:
  quit(2)
