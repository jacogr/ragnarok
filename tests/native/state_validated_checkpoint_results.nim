# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Linked checkpoint validation must reject inactive payload/phase access and support a genuine expected-root control.
import std/[assertions, cmdline, syncio]
import ../../src/state/[validated_checkpoint, checkpoint, store, global_snapshot, manifest]
import ../../src/codec/[bounded, assurances, state_consensus, state_layout, state_trie, state_composition]
include composition_fixture
proc extract(outcome: ValidatedCheckpointResult): ValidatedStateManifest {.noinline.} =
  ## Keep success extraction dynamic so a compiler rejection cannot count as a runtime guard.
  outcome.value
proc checkpointReason(outcome: ValidatedCheckpointResult): CheckpointError {.noinline.} =
  ## Read only the active checkpoint failure alternative.
  outcome.checkpointError
proc globalReason(outcome: ValidatedCheckpointResult): GlobalStateError {.noinline.} =
  ## Read only the active global failure alternative.
  outcome.globalFailure.error
proc manifestReason(outcome: ValidatedCheckpointResult): StateManifestError {.noinline.} =
  ## Read only the active manifest failure alternative.
  outcome.manifestFailure.error
let mode = paramStr(1)
case mode
of "value":
  discard extract(default(ValidatedCheckpointResult)) # Defaults cannot fabricate restored state.
of "checkpoint":
  discard checkpointReason(default(ValidatedCheckpointResult)) # Defaults have no envelope reason.
of "global":
  discard globalReason(default(ValidatedCheckpointResult)) # Defaults have no failed global result.
of "manifest":
  discard manifestReason(default(ValidatedCheckpointResult)) # Defaults have no failed manifest result.
of "format":
  let refused = decodeValidatedCheckpoint([], default(StateRoot), [], default(StateProfile),
    StateCheckpointLimits())
  assert refused.error == ValidatedCheckpointError.CheckpointFailure
  assert refused.checkpointError == CheckpointError.InvalidFormat
  discard extract(refused) # Actual format refusal carries no complete-map witness.
of "ok":
  let fixture = compositionFixture(paramStr(2))
  var entries: seq[StateEntry] = @[]
  for i in 1..16:
    entries.add(StateEntry(key: chapterKey(StateChapter(i)), value: fixture[
        i-1])) # Independent exact global-only map.
  let mapLimits = StateTrieLimits(items: ElementLimit(32), nodes: TrieNodeLimit(63),
    perValue: ByteLimit(65536), totalValueBytes: ByteLimit(262144))
  let stores = StateStoreLimits(trie: mapLimits, writes: ElementLimit(32),
      writeValueBytes: ByteLimit(262144))
  let source = newStateStore(entries, stores).value.snapshot.value
  let wire = encodeFullCheckpoint(source, ByteLimit(524288)).value
  let result = decodeValidatedCheckpoint(wire, source.commitment.root, [],
    StateProfile(cores: CoreCount(2), current: ValidatorCount(6), previous: ValidatorCount(6),
        epochSlots: EpochSlots(2)),
    StateCheckpointLimits(checkpointBytes: ByteLimit(524288), store: stores,
      globals: GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(1000),
        maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144)),
      manifest: StateManifestLimits(serialized: mapLimits)))
  let completed = extract(result)
  assert completed.manifestInfo.value.entries == 16 # Genuine dynamic successful extraction is required before accepting misuse evidence.
  echo "state-validated-checkpoint-results: ok"
else:
  quit(2) # Unknown selectors cannot replace successful controls or exact assertion diagnostics.
