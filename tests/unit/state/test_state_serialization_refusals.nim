# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently recommitted maps isolate precise typed chapter refusals from checkpoint/root failures.
import std/[assertions, envvars, strutils, syncio, parseutils]
import ../../../src/state/[checkpoint, store, global_snapshot, manifest, validated_checkpoint]
import ../../../src/codec/[bounded, assurances, state_consensus, state_layout, state_trie,
    state_composition]
const
  profile = StateProfile(cores: CoreCount(2), current: ValidatorCount(6),
    previous: ValidatorCount(6), epochSlots: EpochSlots(2))
  mapLimits = StateTrieLimits(items: ElementLimit(16), nodes: TrieNodeLimit(2048),
    perValue: ByteLimit(65536), totalValueBytes: ByteLimit(262144))
  limits = StateCheckpointLimits(checkpointBytes: ByteLimit(524288),
    store: StateStoreLimits(trie: mapLimits, writes: ElementLimit(16), writeValueBytes: ByteLimit(
        262144)),
    globals: GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(1000),
      maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144)),
    manifest: StateManifestLimits(services: ElementLimit(0), serialized: mapLimits,
      storageKeyBytes: ByteLimit(0)))
proc octets(text: string): seq[byte] =
  ## Decode exact pinned hex; fixture errors are setup failures rather than passing negative tests.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    var octet: byte = 0
    assert parseHex(text[2*i..2*i+1], octet) == 2
    result[i] = octet
proc check(mode: string, chapter: int, input: seq[byte]) =
  ## Validate the independently recomputed root first, then test the exact selected typed stage.
  assert input.len >= 57
  var root = default(array[32, byte])
  for i in 0..<32: root[i] = input[25+i]
  let raw = decodeFullCheckpoint(input, StateRoot(root), limits.store, limits.checkpointBytes)
  assert raw.error == CheckpointError.None
  assert encodeFullCheckpoint(raw.value.snapshot.value, limits.checkpointBytes).value == input
  let typed = decodeValidatedCheckpoint(input, StateRoot(root), [], profile, limits)
  if mode == "V":
    assert chapter == 0
    assert typed.error == ValidatedCheckpointError.None
    var shortWire = limits
    shortWire.checkpointBytes = ByteLimit(uint64(input.len-1))
    let refusedWire = decodeValidatedCheckpoint(input, StateRoot(root), [], profile, shortWire)
    assert refusedWire.error == ValidatedCheckpointError.CheckpointFailure
    assert refusedWire.checkpointError == CheckpointError.LimitExceeded
    var shortGlobal = limits
    shortGlobal.globals.chapter.maxBytes = ByteLimit(0)
    let refusedGlobal = decodeValidatedCheckpoint(input, StateRoot(root), [], profile, shortGlobal)
    assert refusedGlobal.error == ValidatedCheckpointError.GlobalFailure
    assert refusedGlobal.globalFailure.error == GlobalStateError.LimitExceeded
    var shortManifest = limits
    shortManifest.manifest.serialized.items = ElementLimit(15)
    let refusedManifest = decodeValidatedCheckpoint(input, StateRoot(root), [], profile, shortManifest)
    assert refusedManifest.error == ValidatedCheckpointError.ManifestFailure
    assert refusedManifest.manifestFailure.error == StateManifestError.LimitExceeded
  else:
    assert chapter >= 1 and chapter <= 16
    assert typed.error == ValidatedCheckpointError.GlobalFailure
    let failure = typed.globalFailure
    if mode == "M":
      assert failure.error == GlobalStateError.MissingChapter
    else:
      assert mode == "T"
      assert failure.error == GlobalStateError.ChapterFailure
      assert failure.chapterError == StateCompositionError.TrailingBytes
    assert failure.failedChapter == StateChapterId(chapter)
  root[0] = root[0] xor 1
  let untrusted = decodeValidatedCheckpoint(input, StateRoot(root), [], profile, limits)
  assert untrusted.error == ValidatedCheckpointError.CheckpointFailure
  assert untrusted.checkpointError == CheckpointError.RootMismatch
proc main() {.raises.} =
  ## Require every chapter omission and exact-consumption witness plus a genuine fully valid control.
  var count = 0
  for line in readFile(getEnv("RAGNAROK_SERIALIZATION_REFUSALS")).splitLines():
    if line.len == 0: continue # The pinned file ends with a newline.
    let fields = line.splitWhitespace()
    assert fields.len == 3
    let chapter = parseInt(fields[1])
    check(fields[0], chapter, octets(fields[2]))
    inc count
  assert count == 33
  echo "state-serialization-refusals: ok (33 cases)"
try:
  main()
except:
  quit(2) # Malformed trusted fixture transport never counts as an intended typed refusal.
