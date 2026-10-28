# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP-derived bytes qualify all sixteen native typed chapter encoders and complete current maps.
import std/assertions
import std/envvars
import std/strutils
import std/syncio
import ../../support/state_complete_serialization_context
import ../../support/state_typed_global_context
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
const
  mapLimits = StateTrieLimits(items: ElementLimit(20), nodes: TrieNodeLimit(4096),
    perValue: ByteLimit(2000000), totalValueBytes: ByteLimit(8000000))
  stores = StateStoreLimits(trie: mapLimits, writes: ElementLimit(20), writeValueBytes: ByteLimit(8000000))
  policy = StateChapterPolicy(items: ElementLimit(50000), maxBytes: ByteLimit(2000000))
  limits = StateCheckpointLimits(checkpointBytes: ByteLimit(9000000), store: stores,
    globals: GlobalStateLimits(chapter: policy, totalBytes: ByteLimit(8000000)),
    manifest: StateManifestLimits(services: ElementLimit(1), serialized: mapLimits,
      storageKeyBytes: ByteLimit(65)))
proc reason(error: StateCompositionError): string =
  ## Match the oracle's stable typed reason names without weakening the native success contract.
  ($error).toLowerAscii
proc check(fields: seq[string], ordinal: int) {.raises.} =
  ## Exact complete bytes and independent root must survive composition and typed checkpoint restoration.
  assert fields.len == 24
  let profile = StateProfile(cores: CoreCount(uint64(parseInt(fields[0]))),
    current: ValidatorCount(uint64(parseInt(fields[1]))), previous: ValidatorCount(uint64(parseInt(
        fields[2]))),
    epochSlots: EpochSlots(uint64(parseInt(fields[3]))))
  assert parseInt(fields[4]) == ordinal mod 2
  assert parseInt(fields[5]) == ordinal
  let failures = fields[23].split(',')
  assert failures.len == 16
  let typed = typedGlobalEntries(profile, ordinal mod 2)
  var chapters = default(StateChapters)
  for i in 1..16:
    let input = serializationOctets(fields[5+i])
    assert typed[i-1].value == input # Expected bytes are GP-derived, never native decoder output.
    assert array[31, byte](typed[i-1].key) == array[31, byte](chapterKey(StateChapter(i)))
    let chapter = StateChapterId(i)
    var exact = policy
    exact.maxBytes = ByteLimit(uint64(input.len))
    let captured = captureStateChapter(chapter, typed[i-1].value, profile, exact)
    assert captured.error == StateCompositionError.None
    chapters[chapter] = captured.value
    # Reject every proper last-byte truncation using the independently predicted child reason.
    var prefix = newSeq[byte](input.len-1)
    for j in 0..<prefix.len: prefix[j] = input[j] # Explicit copy avoids the pinned generic sequence-slice compiler defect.
    let truncated = captureStateChapter(chapter, prefix, profile, policy)
    assert reason(truncated.error) == failures[i-1]
    var suffixed = input
    suffixed.add(0)
    assert captureStateChapter(chapter, suffixed, profile, policy).error ==
        StateCompositionError.TrailingBytes
    exact.maxBytes = ByteLimit(uint64(input.len-1))
    assert captureStateChapter(chapter, input, profile, exact).error ==
        StateCompositionError.LimitExceeded
  let services = @[serializationService(ordinal)]
  let composed = composeState(chapters, services, mapLimits, ByteLimit(65))
  assert composed.error == StateCompositionError.None
  var entries: seq[StateEntry] = @[]
  for i in 0..<20: entries.add(composed.value.stateEntryAt(codec_state_composition.StateEntryIndex(
      uint64(i))).value)
  let snapshot = newStateStore(entries, stores).value.snapshot.value
  let expected = serializationOctets(fields[22])
  assert encodeFullCheckpoint(snapshot, limits.checkpointBytes).value == expected
  var root = default(array[32, byte])
  for i in 0..<32: root[i] = expected[25+i]
  let restored = decodeValidatedCheckpoint(expected, StateRoot(root), services, profile, limits)
  assert restored.error == ValidatedCheckpointError.None
  assert encodeFullCheckpoint(restored.value.manifestSource.value,
      limits.checkpointBytes).value == expected
proc main() {.raises.} =
  ## Every generated profile/schedule row is mandatory; setup failure is never a negative-test pass.
  var count = 0
  for line in readFile(getEnv("RAGNAROK_TYPED_SERIALIZATION")).splitLines():
    if line.len == 0: continue # Ignore only the generated fixture's terminating newline.
    assert count < 8
    check(line.splitWhitespace(), count)
    inc count
  assert count == 8
  echo "state-typed-serialization: ok (8 complete states, 128 typed encoders)"
try:
  main()
except:
  quit(2) # Missing, malformed or incomplete input is an actual suite failure.
