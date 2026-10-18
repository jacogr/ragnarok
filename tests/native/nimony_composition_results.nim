# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated default/actual composition failures cannot expose chapters, maps, roots or extracted entries.
include ../../src/codec/state_composition
include ./composition_fixture
let profile = StateProfile(cores: CoreCount(2), current: ValidatorCount(6),
    previous: ValidatorCount(6), epochSlots: EpochSlots(2))
let policy = StateChapterPolicy(items: ElementLimit(1000000), maxBytes: ByteLimit(8000000))
let limits = StateTrieLimits(items: ElementLimit(1000), perValue: ByteLimit(8000000),
    totalValueBytes: ByteLimit(16000000), nodes: TrieNodeLimit(250000))
# Refusals apply only to the separately linked test observer.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
fail(0)
var baseline = default(StateChapters)
let raw = compositionFixture(paramStr(3))
# Every mandatory chapter is independently authored and captured under one explicit profile.
for number in 1..16:
  let chapter = StateChapterId(number)
  baseline[chapter] = captureStateChapter(chapter, raw[number-1], profile, policy).value
let useDefault = paramStr(2) == "default"
var invalidProfile = profile
invalidProfile.cores = CoreCount(1)
let noBytes = StateChapterPolicy(items: ElementLimit(100), maxBytes: ByteLimit(0))
var noItems = limits
noItems.items = ElementLimit(0)
var noNodes = limits
noNodes.nodes = TrieNodeLimit(0)
var wrongChapter = baseline
wrongChapter[StateChapterId.Outputs] = baseline[StateChapterId.Time]
var wrongProfile = baseline
var other = profile
other.cores = CoreCount(3)
wrongProfile[StateChapterId.Entropy] = captureStateChapter(StateChapterId.Entropy, newSeq[byte](
    128), other, policy).value
let source = StateService(service: ServiceIndex(7))
let missing = StateService(service: ServiceIndex(7), captured: @[default(ServiceValueSnapshot)])
let keyed = serviceStorageEntry(ServiceIndex(8), [], [], ServiceEntryLimits(keyBytes: ByteLimit(0),
    valueBytes: ByteLimit(0))).value
let wrongService = StateService(service: ServiceIndex(7), captured: @[captureServiceValue(
    ServiceIndex(8), keyed.key, [], ByteLimit(0)).value])
let owner = composeState(baseline, [], limits, ByteLimit(1)).value
case paramStr(1)
of "capture-config":
  # Neither defaults nor these actual failures may authorize complete application payloads.
  let parsed = if useDefault: default(StateCompositionResult[
      StateChapterSnapshot]) else: captureStateChapter(StateChapterId.Time, [], invalidProfile, policy)
  assert parsed.error == (if useDefault: StateCompositionError.Uninitialized else: StateCompositionError.InvalidConfig)
  discard parsed.value
of "capture-policy":
  # Neither defaults nor these actual failures may authorize complete application payloads.
  let parsed = if useDefault: default(StateCompositionResult[
      StateChapterSnapshot]) else: captureStateChapter(StateChapterId.Time, [0'u8], profile, noBytes)
  assert parsed.error == (if useDefault: StateCompositionError.Uninitialized else: StateCompositionError.LimitExceeded)
  discard parsed.value
of "capture-short":
  # Neither defaults nor these actual failures may authorize complete application payloads.
  let parsed = if useDefault: default(StateCompositionResult[
      StateChapterSnapshot]) else: captureStateChapter(StateChapterId.Time, [], profile, policy)
  assert parsed.error == (if useDefault: StateCompositionError.Uninitialized else: StateCompositionError.Truncated)
  discard parsed.value
of "capture-tail":
  # Neither defaults nor these actual failures may authorize complete application payloads.
  let parsed = if useDefault: default(StateCompositionResult[
      StateChapterSnapshot]) else: captureStateChapter(StateChapterId.Time, [0'u8, 0, 0, 0, 0],
      profile, policy)
  assert parsed.error == (if useDefault: StateCompositionError.Uninitialized else: StateCompositionError.TrailingBytes)
  discard parsed.value
of "capture-framing":
  # Neither defaults nor these actual failures may authorize complete application payloads.
  let parsed = if useDefault: default(StateCompositionResult[
      StateChapterSnapshot]) else: captureStateChapter(StateChapterId.Outputs, [128'u8, 0], profile, policy)
  assert parsed.error == (if useDefault: StateCompositionError.Uninitialized else: StateCompositionError.NonCanonical)
  discard parsed.value
of "capture-chapter":
  # Neither defaults nor these actual failures may authorize complete application payloads.
  let parsed = if useDefault: default(StateCompositionResult[
      StateChapterSnapshot]) else: captureStateChapter(StateChapterId(0), [], profile, policy)
  assert parsed.error == (if useDefault: StateCompositionError.Uninitialized else: StateCompositionError.InvalidComponent)
  discard parsed.value
of "compose-owner":
  # Neither defaults nor these actual failures may authorize complete application payloads.
  let parsed = if useDefault: default(StateCompositionResult[StateSnapshot]) else: composeState(
      default(StateChapters), [], limits, ByteLimit(1))
  assert parsed.error == (if useDefault: StateCompositionError.Uninitialized else: StateCompositionError.InvalidOwner)
  discard parsed.value
of "compose-chapter":
  # Neither defaults nor these actual failures may authorize complete application payloads.
  let parsed = if useDefault: default(StateCompositionResult[StateSnapshot]) else: composeState(
      wrongChapter, [], limits, ByteLimit(1))
  assert parsed.error == (if useDefault: StateCompositionError.Uninitialized else: StateCompositionError.WrongChapter)
  discard parsed.value
of "compose-profile":
  # Neither defaults nor these actual failures may authorize complete application payloads.
  let parsed = if useDefault: default(StateCompositionResult[StateSnapshot]) else: composeState(
      wrongProfile, [], limits, ByteLimit(1))
  assert parsed.error == (if useDefault: StateCompositionError.Uninitialized else: StateCompositionError.ProfileMismatch)
  discard parsed.value
of "compose-policy":
  # Neither defaults nor these actual failures may authorize complete application payloads.
  let parsed = if useDefault: default(StateCompositionResult[StateSnapshot]) else: composeState(
      baseline, [], noItems, ByteLimit(1))
  assert parsed.error == (if useDefault: StateCompositionError.Uninitialized else: StateCompositionError.LimitExceeded)
  discard parsed.value
of "compose-captured-owner":
  # Neither defaults nor these actual failures may authorize complete application payloads.
  let parsed = if useDefault: default(StateCompositionResult[StateSnapshot]) else: composeState(
      baseline, [missing], limits, ByteLimit(1))
  assert parsed.error == (if useDefault: StateCompositionError.Uninitialized else: StateCompositionError.InvalidOwner)
  discard parsed.value
of "compose-captured-context":
  # Neither defaults nor these actual failures may authorize complete application payloads.
  let parsed = if useDefault: default(StateCompositionResult[StateSnapshot]) else: composeState(
      baseline, [wrongService], limits, ByteLimit(1))
  assert parsed.error == (if useDefault: StateCompositionError.Uninitialized else: StateCompositionError.InvalidComponent)
  discard parsed.value
of "compose-duplicate":
  # Neither defaults nor these actual failures may authorize complete application payloads.
  let parsed = if useDefault: default(StateCompositionResult[StateSnapshot]) else: composeState(
      baseline, [source, source], limits, ByteLimit(1))
  assert parsed.error == (if useDefault: StateCompositionError.Uninitialized else: StateCompositionError.DuplicateKey)
  discard parsed.value
of "compose-backend":
  # Neither defaults nor these actual failures may authorize complete application payloads.
  fail(1)
  let parsed = if useDefault: default(StateCompositionResult[StateSnapshot]) else: composeState(
      baseline, [source], limits, ByteLimit(1))
  assert parsed.error == (if useDefault: StateCompositionError.Uninitialized else: StateCompositionError.BackendFailure)
  discard parsed.value
of "compose-nodes":
  # Neither defaults nor these actual failures may authorize complete application payloads.
  let parsed = if useDefault: default(StateCompositionResult[StateSnapshot]) else: composeState(
      baseline, [], noNodes, ByteLimit(1))
  assert parsed.error == (if useDefault: StateCompositionError.Uninitialized else: StateCompositionError.LimitExceeded)
  discard parsed.value
of "commitment-owner":
  # Neither defaults nor these actual failures may authorize complete application payloads.
  let parsed = if useDefault: default(StateCompositionResult[
      StateTrieCommitment]) else: stateCommitment(default(StateSnapshot))
  assert parsed.error == (if useDefault: StateCompositionError.Uninitialized else: StateCompositionError.InvalidOwner)
  discard parsed.value.root
of "entry-owner":
  # Neither defaults nor these actual failures may authorize complete application payloads.
  let parsed = if useDefault: default(StateCompositionResult[StateEntry]) else: stateEntryAt(
      default(StateSnapshot), StateEntryIndex(0))
  assert parsed.error == (if useDefault: StateCompositionError.Uninitialized else: StateCompositionError.InvalidOwner)
  discard parsed.value.value.len
of "entry-index":
  # Neither defaults nor these actual failures may authorize complete application payloads.
  let parsed = if useDefault: default(StateCompositionResult[StateEntry]) else: stateEntryAt(owner,
      StateEntryIndex(high(uint64)))
  assert parsed.error == (if useDefault: StateCompositionError.Uninitialized else: StateCompositionError.InvalidIndex)
  discard parsed.value.value.len
else:
  # Unknown fixture requests are setup failures rather than success-precondition evidence.
  quit 2
