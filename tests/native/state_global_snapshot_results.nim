# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime guards reject default values and inactive nested chapter reasons with a genuine positive control.
import std/assertions
import std/cmdline
import std/syncio
import ../../src/state/global_snapshot as state_global_snapshot
import ../../src/state/store as state_store
import ../../src/codec/state_composition as codec_state_composition
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/assurances as codec_assurances
import ../../src/codec/state_consensus as codec_state_consensus
include nimony_composition_fixture
proc extract(outcome: GlobalStateResult[ValidatedGlobalState]): ValidatedGlobalState {.noinline.} =
  ## Preserve a dynamic successful-payload guard instead of constant-folding a default variant.
  outcome.value
proc failed(outcome: GlobalStateResult[ValidatedGlobalState]): StateChapterId {.noinline.} =
  ## Exercise the chapter-specific alternative check in the linked runtime.
  outcome.failedChapter
proc reason(outcome: GlobalStateResult[ValidatedGlobalState]): StateCompositionError {.noinline.} =
  ## Exercise the nested reason check in the linked runtime.
  outcome.chapterError
let mode = paramStr(1)
case mode
of "value":
  discard extract(default(GlobalStateResult[ValidatedGlobalState])) # Defaults carry no serialization certificate.
of "chapter":
  discard failed(default(GlobalStateResult[ValidatedGlobalState])) # Only chapter-specific refusals carry identities.
of "reason":
  discard reason(default(GlobalStateResult[ValidatedGlobalState])) # No inactive decoder reason is readable.
of "missing":
  let empty = newStateStore([], StateStoreLimits()).value.snapshot.value
  let refused = validateGlobalState(empty, default(StateProfile), GlobalStateLimits())
  assert refused.error == GlobalStateError.MissingChapter
  assert refused.failedChapter == StateChapterId.Pools
  discard extract(refused) # Actual complete-map absence carries no successful certificate.
of "ok":
  let fixture = compositionFixture(paramStr(2))
  var entries: seq[StateEntry] = @[]
  for i in 1..16:
    entries.add(StateEntry(key: chapterKey(StateChapter(i)), value: fixture[
        i-1])) # Independent canonical source bytes.
  let source = newStateStore(entries, StateStoreLimits(trie: StateTrieLimits(
    items: ElementLimit(32), nodes: TrieNodeLimit(63), perValue: ByteLimit(65536),
    totalValueBytes: ByteLimit(262144)), writes: ElementLimit(32),
    writeValueBytes: ByteLimit(262144))).value.snapshot.value
  let profile = StateProfile(cores: CoreCount(2), current: ValidatorCount(6),
    previous: ValidatorCount(6), epochSlots: EpochSlots(2))
  let validated = validateGlobalState(source, profile, GlobalStateLimits(
    chapter: StateChapterPolicy(items: ElementLimit(1000), maxBytes: ByteLimit(65536)),
    totalBytes: ByteLimit(262144)))
  let success = extract(validated)
  assert sameStateSnapshot(success.globalSource.value,
      source) # Genuine successful payload extraction precedes misuse checks.
  let failed = default(ValidatedGlobalState).globalSource
  assert failed.error == GlobalStateError.Uninitialized # Positive control executes a real owner accessor.
  echo "state-global-snapshot-results: ok"
else:
  quit(2) # An unknown selector cannot stand in for a passing guard.
