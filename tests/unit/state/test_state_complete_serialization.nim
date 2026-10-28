# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently authored complete bytes qualify typed composition and explicit-root checkpoint restoration.
import std/assertions
import std/envvars
import std/strutils
import std/syncio
import std/parseutils
import ../../support/state_complete_serialization_context
import ../../../src/state/checkpoint as state_checkpoint
import ../../../src/state/store as state_store
import ../../../src/state/manifest as state_manifest
import ../../../src/state/global_snapshot as state_global_snapshot
import ../../../src/state/validated_checkpoint as state_validated_checkpoint
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/state_consensus as codec_state_consensus
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/codec/state_requests as codec_state_requests
include ../../native/nimony_composition_fixture
const
  profile = StateProfile(cores: CoreCount(2), current: ValidatorCount(6),
    previous: ValidatorCount(6), epochSlots: EpochSlots(2))
  mapLimits = StateTrieLimits(items: ElementLimit(20), nodes: TrieNodeLimit(2048),
    perValue: ByteLimit(65536), totalValueBytes: ByteLimit(262144))
  stores = StateStoreLimits(trie: mapLimits, writes: ElementLimit(20), writeValueBytes: ByteLimit(262144))
  limits = StateCheckpointLimits(checkpointBytes: ByteLimit(524288), store: stores,
    globals: GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(1000),
      maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144)),
    manifest: StateManifestLimits(services: ElementLimit(1), serialized: mapLimits,
      storageKeyBytes: ByteLimit(65)))
proc check(fixture: seq[seq[byte]], expected: seq[byte], caseId: int) =
  ## Compose logical fields and require every envelope byte before decoding independently supplied bytes.
  var chapters = default(StateChapters)
  for i in 1..16:
    var input = fixture[i-1]
    if i == 11:
      input = newSeq[byte](4)
      for j in 0..<4: input[j] = byte((serializationWord(caseId, 1, 32) shr (j*8)) and 255)
    chapters[StateChapterId(i)] = captureStateChapter(StateChapterId(i), input, profile,
      limits.globals.chapter).value
  let services = @[serializationService(caseId)]
  let composed = composeState(chapters, services, mapLimits, ByteLimit(65)).value
  var entries: seq[StateEntry] = @[]
  for i in 0..<20: entries.add(composed.stateEntryAt(codec_state_composition.StateEntryIndex(uint64(i))).value)
  let snapshot = newStateStore(entries, stores).value.snapshot.value
  assert encodeFullCheckpoint(snapshot, limits.checkpointBytes).value == expected
  # The expected root is copied from Python-authored bytes, independently of the native composition.
  var root = default(array[32, byte])
  for i in 0..<32: root[i] = expected[25+i]
  let restored = decodeValidatedCheckpoint(expected, StateRoot(root), services, profile, limits)
  assert restored.error == ValidatedCheckpointError.None
  assert encodeFullCheckpoint(restored.value.manifestSource.value, limits.checkpointBytes).value == expected
proc main() {.raises.} =
  ## Run every pinned independent complete state; require exact fixture cardinality and no skipped rows.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  let lines = readFile(getEnv("RAGNAROK_COMPLETE_SERIALIZATION")).splitLines()
  var count = 0
  for line in lines:
    if line.len == 0: continue # Only the final newline is ignorable fixture framing.
    assert count < 32
    check(fixture, serializationOctets(line), count)
    inc count
  assert count == 32
  echo "state-complete-serialization: ok (32 cases)"
try:
  main()
except:
  quit(2) # Missing or malformed fixtures cannot count as successful serialization checks.
