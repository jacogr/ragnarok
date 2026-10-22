# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent complete bytes anchor all service permutations across four disjoint logical namespaces.
import std/[assertions, envvars, strutils, syncio]
import ../../support/state_complete_serialization_context
import ../../../src/state/[checkpoint, store, manifest, global_snapshot, validated_checkpoint]
import ../../../src/codec/[bounded, assurances, state_consensus, state_layout, state_trie, state_composition]
include ../../native/composition_fixture
const
  profile = StateProfile(cores: CoreCount(2), current: ValidatorCount(6), previous: ValidatorCount(
      6), epochSlots: EpochSlots(2))
  mapLimits = StateTrieLimits(items: ElementLimit(32), nodes: TrieNodeLimit(4096),
      perValue: ByteLimit(65536), totalValueBytes: ByteLimit(262144))
  stores = StateStoreLimits(trie: mapLimits, writes: ElementLimit(32), writeValueBytes: ByteLimit(262144))
  limits = StateCheckpointLimits(checkpointBytes: ByteLimit(524288), store: stores,
    globals: GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(1000),
        maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144)),
    manifest: StateManifestLimits(services: ElementLimit(4), serialized: mapLimits,
        storageKeyBytes: ByteLimit(65)))
proc order(rank: int): array[4, int] =
  ## Factoradic enumeration covers all 24 orders without aliased in-place sequence mutation.
  result = default(array[4, int])
  var used = default(array[4, bool])
  var remainder = rank
  for position in 0..<4:
    let factor = if position == 0: 6 elif position == 1: 2 else: 1
    var choice = remainder div factor
    remainder = remainder mod factor
    for candidate in 0..<4:
      if not used[candidate]:
        if choice == 0:
          result[position] = candidate
          used[candidate] = true
          break # Choose each original service identity exactly once.
        choice -= 1
proc check(chapters: StateChapters, expected: seq[byte], group, rank: int) =
  ## Compare complete canonical bytes and expected-root restoration for each declaration order.
  var services: seq[StateService] = @[]
  for index in order(rank): services.add(serializationService(4*group+index))
  let composed = composeState(chapters, services, mapLimits, ByteLimit(65)).value
  var entries: seq[StateEntry] = @[]
  for i in 0..<32: entries.add(composed.stateEntryAt(state_composition.StateEntryIndex(uint64(i))).value)
  let snapshot = newStateStore(entries, stores).value.snapshot.value
  assert encodeFullCheckpoint(snapshot, limits.checkpointBytes).value == expected
  var root = default(array[32, byte])
  for i in 0..<32: root[i] = expected[25+i]
  let restored = decodeValidatedCheckpoint(expected, StateRoot(root), services, profile, limits)
  assert restored.error == ValidatedCheckpointError.None
  assert encodeFullCheckpoint(restored.value.manifestSource.value, limits.checkpointBytes).value == expected
proc main() {.raises.} =
  ## Eight complete sources exercise metadata and raw child maps under every unique service order.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var chapters = default(StateChapters)
  for i in 1..16:
    chapters[StateChapterId(i)] = captureStateChapter(StateChapterId(i), fixture[i-1], profile,
        limits.globals.chapter).value
  var group = 0
  for line in readFile(getEnv("RAGNAROK_MULTISERVICE_SERIALIZATION")).splitLines():
    if line.len == 0: continue # Only fixture newline framing is ignored.
    assert group < 8
    let expected = serializationOctets(line)
    for rank in 0..<24: check(chapters, expected, group, rank)
    inc group
  assert group == 8
  echo "state-multiservice-serialization: ok (192 cases)"
try:
  main()
except:
  quit(2) # Fixture/setup failures cannot qualify a native comparison.
