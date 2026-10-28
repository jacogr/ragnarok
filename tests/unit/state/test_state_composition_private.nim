# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Project-only whole-mapping ownership, preflight, arithmetic and backend cleanup checks.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

# @@Verification={"arc": "composition_arc_release"}

import std/envvars
import ../../support/testing_arc_evidence
include ../../../src/codec/state_composition
include ../../native/nimony_composition_fixture
let profile = StateProfile(cores: CoreCount(2), current: ValidatorCount(6),
    previous: ValidatorCount(6), epochSlots: EpochSlots(2))
let policy = StateChapterPolicy(items: ElementLimit(1000000), maxBytes: ByteLimit(8000000))
let limits = StateTrieLimits(items: ElementLimit(1000), perValue: ByteLimit(8000000),
    totalValueBytes: ByteLimit(16000000), nodes: TrieNodeLimit(250000))
# Native faults are isolated to this observer-linked test binary.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
# Delayed refusal exercises cleanup after service-key work and completed child hashes.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
# Copied attempt counts prove complete parent preflight precedes key/root hashing.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

## Create every typed service source plus an explicitly opaque retained entry in a separate key.
proc service(marker: byte): StateService =
  let encoded = serviceStorageEntry(ServiceIndex(7), [2'u8], [marker], ServiceEntryLimits(
      keyBytes: ByteLimit(1), valueBytes: ByteLimit(1))).value
  result = StateService(service: ServiceIndex(7),
    storage: @[StateStorageItem(key: @[1'u8], value: @[marker, 128'u8, 0])],
    preimages: @[StatePreimageItem(hash: default(ServicePreimageHash), value: @[marker])],
    requests: @[StateRequestItem(hash: default(ServicePreimageHash), length: RequestLength(42),
        history: availableHistory(RequestSlot(128)))],
    captured: @[captureServiceValue(ServiceIndex(7), encoded.key, encoded.value, ByteLimit(1)).value])

## Return a complete retained mapping after source descriptors and temporary child handles retire.
proc escaped(parts: StateChapters, marker: byte): StateSnapshot =
  var original = service(marker)
  let composed = composeState(parts, [original], limits, ByteLimit(1))
  assert composed.error == StateCompositionError.None
  result = composed.value
  original.storage[0].value[0] = 0
  original = default(StateService)

## Every scope releases replaced parents, copied entries and scratch after success and early/late failures.
proc cycle(parts: StateChapters) =
  fail(0)
  var owner = escaped(parts, 17)
  let retained = owner
  owner = escaped(parts, 29)
  assert stateCommitment(retained).value.entries == 21
  assert stateEntryAt(retained, StateEntryIndex(17)).value.value == @[17'u8, 128, 0]
  assert stateEntryAt(owner, StateEntryIndex(17)).value.value[0] == 29
  let root = stateCommitment(retained).value.root
  var extracted = stateEntryAt(retained, StateEntryIndex(17)).value
  extracted.value[0] = 0
  extracted.key = default(StateKey)
  assert stateEntryAt(retained, StateEntryIndex(17)).value.value[0] == 17
  var commitment = stateCommitment(retained).value
  commitment.root = default(StateRoot)
  assert array[32, byte](stateCommitment(retained).value.root) == array[32, byte](root)
  owner = default(StateSnapshot)
  assert stateCommitment(owner).error == StateCompositionError.InvalidOwner
  assert stateEntryAt(retained, StateEntryIndex(high(uint64))).error ==
      StateCompositionError.InvalidIndex
  var changed = parts
  changed[StateChapterId.Time] = default(StateChapterSnapshot)
  assert stateEntryAt(retained, StateEntryIndex(10)).value.value == @[4'u8, 3, 2, 1]
  let source = service(43)
  fail(1)
  assert composeState(parts, [source], limits, ByteLimit(1)).error ==
      StateCompositionError.BackendFailure
  assert hashCalls() == 1
  failAfter(3)
  assert composeState(parts, [source], limits, ByteLimit(1)).error ==
      StateCompositionError.BackendFailure
  assert hashCalls() == 4
  fail(1)
  var short = limits
  short.items = ElementLimit(16)
  assert composeState(parts, [source], short, ByteLimit(1)).error ==
      StateCompositionError.LimitExceeded
  assert hashCalls() == 0
  assert composeState(changed, [source], limits, ByteLimit(1)).error ==
      StateCompositionError.InvalidOwner
  assert hashCalls() == 0
  fail(0)
  assert composeState(parts, [source, source], limits, ByteLimit(1)).error ==
      StateCompositionError.DuplicateKey
  fail(0)
  assert composeState(parts, [source], limits, ByteLimit(1)).error == StateCompositionError.None

var baseline = default(StateChapters)
assert getEnv("RAGNAROK_COMPOSITION_FIXTURE").len > 0, "missing independent chapter fixture"
let raw = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
# Every mandatory chapter is independently authored and captured under one explicit profile.
for number in 1..16:
  let chapter = StateChapterId(number)
  baseline[chapter] = captureStateChapter(chapter, raw[number-1], profile, policy).value
# Check descriptor and aggregate arithmetic directly without forged native arrays or advertised allocations.
let huge = StateTrieLimits(items: ElementLimit(high(uint64)), perValue: ByteLimit(high(uint64)),
    totalValueBytes: ByteLimit(high(uint64)), nodes: TrieNodeLimit(high(uint64)))
var count = uint64(high(int) div sizeof(StateEntry))-1
var total = high(uint64)-3
assert charge(3, huge, count, total) == StateCompositionError.None
assert total == high(uint64)
assert charge(0, huge, count, total) == StateCompositionError.LimitExceeded
count = 0
assert charge(1, huge, count, total) == StateCompositionError.LimitExceeded
assert count == 0 and total == high(uint64)
assert historySize(reavailableHistory(RequestSlot(high(uint32)), RequestSlot(0), RequestSlot(1))) == 13
# Warm every ownership and native refusal path before comparing live occupancy.
for i in 0..<100: cycle(baseline)
let beforeRelease = getOccupiedMem()
# Final chapter/mapping aliases and temporary service sources release all scoped ARC references.
for i in 0..<1000: cycle(baseline)
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Preserve fresh numeric observations independently of portable expected output.
recordArcRelease("state_composition_private", 1000, beforeRelease, afterRelease)
echo "COMPOSITION_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony composition: retained/replaced mappings, fixed copies, preflight and backend cleanup passed"
