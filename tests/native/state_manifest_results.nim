# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic manifest guards and a genuine complete-map positive control share the linked implementation.
import std/[assertions, cmdline, syncio]
import ../../src/state/[manifest, global_snapshot, store]
import ../../src/codec/[bounded, assurances]
import ../../src/codec/state/[consensus as state_consensus, layout as state_layout,
    trie as state_trie, composition as state_composition]
include ./composition_fixture
proc extract(outcome: StateManifestResult[ValidatedStateManifest]): ValidatedStateManifest {.noinline.} =
  ## Preserve the dynamic success assertion instead of constant-folding an inactive default variant.
  outcome.value
proc reason(outcome: StateManifestResult[ValidatedStateManifest]): StateCompositionError {.noinline.} =
  ## Only actual composition refusal can expose a nested decoder/backend reason.
  outcome.compositionError
let mode = paramStr(1)
case mode
of "value":
  discard extract(default(StateManifestResult[ValidatedStateManifest])) # A default witness has no full-state source.
of "reason":
  discard reason(default(StateManifestResult[ValidatedStateManifest])) # Defaults carry no composition reason.
of "invalid":
  let refused = validateStateManifest(default(ValidatedGlobalState), [], StateManifestLimits())
  assert refused.error == StateManifestError.InvalidSource
  discard extract(refused) # An actual source refusal cannot be read as a complete matching witness.
of "ok":
  let fixture = compositionFixture(paramStr(2))
  var entries: seq[StateEntry] = @[]
  for i in 1..16:
    entries.add(StateEntry(key: chapterKey(StateChapter(i)), value: fixture[
        i-1])) # Independent complete global-only map.
  let mapLimits = StateTrieLimits(items: ElementLimit(32), nodes: TrieNodeLimit(63),
    perValue: ByteLimit(65536), totalValueBytes: ByteLimit(262144))
  let source = newStateStore(entries, StateStoreLimits(trie: mapLimits,
    writes: ElementLimit(32), writeValueBytes: ByteLimit(262144))).value.snapshot.value
  let globals = validateGlobalState(source, StateProfile(cores: CoreCount(2),
    current: ValidatorCount(6), previous: ValidatorCount(6), epochSlots: EpochSlots(2)),
    GlobalStateLimits(chapter: StateChapterPolicy(items: ElementLimit(1000),
      maxBytes: ByteLimit(65536)), totalBytes: ByteLimit(262144))).value
  let result = validateStateManifest(globals, [], StateManifestLimits(serialized: mapLimits))
  let completed = extract(result)
  assert completed.manifestInfo.value.services == 0
  assert sameStateSnapshot(completed.manifestSource.value,
      source) # Genuine dynamic success must work before misuse verdicts are accepted.
  echo "state-manifest-results: ok"
else:
  quit(2) # Unknown modes cannot satisfy successful controls or guard diagnostics.
