# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete-source chapter validation preserves map authority, exact codec refusals and ARC ownership.
# @@Verification={"arc": "state_global_snapshot_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[proof_global_helpers, arc_evidence]
import ../../../src/state/[global_snapshot, store]
import ../../../src/codec/[bounded, assurances, composite]
import ../../../src/codec/state/[layout as state_layout, trie as state_trie,
    composition as state_composition, consensus as state_consensus]
include ../../native/composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse all hashes after constructing the complete immutable test source.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe hashing attempts independently of validator results.
const
  profile = StateProfile(cores: CoreCount(2), current: ValidatorCount(6),
    previous: ValidatorCount(6), epochSlots: EpochSlots(2))
  limits = GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(1000),
    maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))
  stores = StateStoreLimits(trie: mapLimits, writes: ElementLimit(32),
    writeValueBytes: ByteLimit(262144))
proc snapshotOf(entries: seq[StateEntry]): StateStoreSnapshot =
  ## Construct a genuine complete map; never fabricate a retained snapshot from raw payload fields.
  newStateStore(entries, stores).value.snapshot.value
proc detached(entries: seq[StateEntry]): ValidatedGlobalState =
  ## Return only the certificate after temporary input-store and source handles have retired.
  validateGlobalState(snapshotOf(entries), profile, limits).value
proc cycle(source: StateStoreSnapshot) =
  ## Success and refusal temporaries retire before allocator observations.
  let validated = validateGlobalState(source, profile, limits).value
  assert sameStateSnapshot(validated.globalSource.value, source)
  var copied = validated.globalChapters.value
  copied[StateChapterId.Time] = default(StateChapterSnapshot)
  assert validateGlobalState(source, profile, GlobalStateLimits()).error ==
    GlobalStateError.LimitExceeded
  assert validated.globalByteLength.value > 0
proc main() {.raises.} =
  ## Use independent complete chapter bytes and retain an extra opaque row outside the validation claim.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var entries: seq[StateEntry] = @[]
  var total = 0'u64
  var maximum = 0'u64
  for i in 1..16:
    entries.add(StateEntry(key: chapterKey(StateChapter(i)), value: fixture[i-1]))
    total += uint64(fixture[i-1].len)
    maximum = max(maximum, uint64(fixture[i-1].len))
  let opaque = StateEntry(key: chapterServiceKey(StateChapter(255), ServiceIndex(77)),
    value: @[byte(0xff)])
  entries.add(opaque) # Deliberately malformed metadata proves global validation does not claim service validation.
  var owner = newStateStore(entries, stores).value
  let source = owner.snapshot.value
  let retained = detached(entries)
  assert not sameStateSnapshot(retained.globalSource.value, source)
  assert retained.globalSource.value.lookup(opaque.key).value.bytes == opaque.value
  fail(1)
  var exact = limits
  exact.totalBytes = ByteLimit(total)
  exact.chapter.maxBytes = ByteLimit(maximum)
  let validated = validateGlobalState(source, profile, exact).value
  assert validated.globalByteLength.value == total
  assert sameStateSnapshot(validated.globalSource.value, source)
  assert validated.globalSource.value.lookup(opaque.key).value.bytes == opaque.value
  exact.totalBytes = ByteLimit(total-1)
  assert validateGlobalState(source, profile, exact).error == GlobalStateError.LimitExceeded
  exact.totalBytes = ByteLimit(total)
  exact.chapter.maxBytes = ByteLimit(maximum-1)
  assert validateGlobalState(source, profile, exact).error == GlobalStateError.LimitExceeded
  assert validateGlobalState(default(StateStoreSnapshot), profile, limits).error ==
      GlobalStateError.InvalidSource
  let wrong = validateGlobalState(source, default(StateProfile), limits)
  assert wrong.error == GlobalStateError.ChapterFailure
  assert wrong.failedChapter == StateChapterId.Pools
  assert wrong.chapterError == StateCompositionError.InvalidConfig
  var itemLimit = limits
  itemLimit.chapter.items = ElementLimit(0)
  let limited = validateGlobalState(source, profile, itemLimit)
  assert limited.error == GlobalStateError.ChapterFailure
  assert limited.chapterError == StateCompositionError.LimitExceeded # Codec resource refusal remains distinct from malformed present data.
  assert default(ValidatedGlobalState).globalSource.error == GlobalStateError.Uninitialized
  assert default(ValidatedGlobalState).globalChapters.error == GlobalStateError.Uninitialized
  assert default(ValidatedGlobalState).globalByteLength.error == GlobalStateError.Uninitialized
  assert calls() == 0
  fail(0)
  var copy = validated.globalChapters.value
  copy[StateChapterId.Time] = default(StateChapterSnapshot)
  let composed = composeState(validated.globalChapters.value, [], mapLimits, ByteLimit(0)).value
  for i in 0..<16:
    let entry = composed.stateEntryAt(state_composition.StateEntryIndex(uint64(i))).value
    assert array[31, byte](entry.key) == array[31, byte](chapterKey(StateChapter(i+1)))
    assert entry.value == fixture[i] # Typed captures preserve every independent exact byte.
  for i in 0..<16:
    var changed = entries
    changed.delete(i)
    let missing = snapshotOf(changed)
    fail(1)
    let refused = validateGlobalState(missing, profile, limits)
    assert refused.error == GlobalStateError.MissingChapter
    assert refused.failedChapter == StateChapterId(i+1)
    assert calls() == 0
    fail(0)
    changed = entries
    changed[i].value = fixture[i]
    changed[i].value.add(byte(0))
    let suffixed = snapshotOf(changed)
    fail(1)
    let malformed = validateGlobalState(suffixed, profile, limits)
    assert malformed.error == GlobalStateError.ChapterFailure
    assert malformed.failedChapter == StateChapterId(i+1)
    assert malformed.chapterError == StateCompositionError.TrailingBytes
    assert sameStateSnapshot(validated.globalSource.value, source)
    assert calls() == 0
    fail(0)
  var changed = entries
  changed[15].value = @[byte(0xff)] # A late truncated chapter must retire the fifteen earlier captures.
  let late = snapshotOf(changed)
  fail(1)
  let refused = validateGlobalState(late, profile, limits)
  assert refused.error == GlobalStateError.ChapterFailure
  assert refused.failedChapter == StateChapterId.Outputs
  assert refused.chapterError == StateCompositionError.Truncated
  let budgetFirst = validateGlobalState(late, profile, GlobalStateLimits(
    chapter: limits.chapter, totalBytes: ByteLimit(0)))
  assert budgetFirst.error == GlobalStateError.LimitExceeded # Length preflight precedes even early decoding.
  for i in 0..<25: cycle(source) # Warm the exact retained chapter graph before measuring live occupancy.
  let before = getOccupiedMem()
  for i in 0..<1000:
    cycle(source)
    assert validateGlobalState(late, profile, limits).error == GlobalStateError.ChapterFailure
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_global_snapshot", 1000, before, after)
  owner = default(StateStore)
  assert sameStateSnapshot(validated.globalSource.value,
      source) # Caller destruction cannot revoke immutable captures.
  assert calls() == 0
  fail(0)
  echo "state-global-snapshot: ok"
try:
  main()
except:
  quit(2) # Fixture/startup failure never supplies a successful validation or ownership verdict.
