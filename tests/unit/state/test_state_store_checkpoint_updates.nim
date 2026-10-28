# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Restored checkpoints must rebuild mutation-capable incremental stores under original trusted roots.
import std/assertions
import std/syncio
import ../../support/codec_published_state
import ../../../src/state/store as state_store
import ../../../src/state/checkpoint as state_checkpoint
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/bounded as codec_bounded

## Find a fixture key by linear scan, independent of the production sorted two-pass merge.
proc find(entries: seq[StateEntry], key: StateKey): int =
  for i, entry in entries:
    if array[31, byte](entry.key) == array[31, byte](key): return i # Exact identity only.
  -1

## Derive a unique-key batch from two complete maps; snapshots supply no expectations.
proc difference(before, after: Mapping): seq[StateWrite] =
  result = @[]
  # Only keys absent from the destination need deletion.
  for entry in before.entries:
    if find(after.entries, entry.key) < 0:
      result.add StateWrite(key: entry.key, kind: StateWriteKind.Delete)
  # Insert new keys and replace changed values, preserving empty values as ordinary Put operations.
  for entry in after.entries:
    let old = find(before.entries, entry.key)
    if old < 0 or before.entries[old].value != entry.value:
      result.add StateWrite(key: entry.key, kind: StateWriteKind.Put, value: entry.value)

proc replay(before, after: Mapping) =
  ## Exercise complete decode, changed updates, forked inverse updates and byte-identical recovery exports.
  let limits = policy(before, after)
  let ceiling = ByteLimit(134217728)
  let original = newStateStore(before.entries, limits).value.snapshot.value
  let encoded = encodeFullCheckpoint(original, ceiling).value
  var restored = decodeFullCheckpoint(encoded, before.root, limits, ceiling).value
  let base = restored.snapshot.value
  let held = base.lookup(before.entries[0].key).value
  matches(base, before)
  let next = restored.apply(difference(before, after)).value
  matches(next, after)
  matches(base, before)
  assert held.bytes == before.entries[0].value
  let nextBytes = encodeFullCheckpoint(next, ceiling).value
  var resumed = decodeFullCheckpoint(nextBytes, after.root, limits, ceiling).value
  var fork = resumed.snapshot.value.forkStateStore.value
  let inverse = fork.apply(difference(after, before)).value
  matches(inverse, before)
  matches(resumed.snapshot.value, after)
  assert encodeFullCheckpoint(inverse, ceiling).value == encoded
  # A narrower future write ceiling after restoration stays inherited by every private fork.
  var short = limits
  short.writes = ElementLimit(0)
  let bounded = decodeFullCheckpoint(encoded, before.root, short, ceiling).value
  var boundedFork = bounded.snapshot.value.forkStateStore.value
  assert boundedFork.apply([StateWrite(key: before.entries[0].key,
    kind: StateWriteKind.Delete)]).error == StateStoreError.LimitExceeded
  matches(boundedFork.snapshot.value, before)
  restored = default(StateStore)
  resumed = default(StateStore)
  fork = default(StateStore)
  assert held.bytes == before.entries[0].value
  matches(inverse, before)

proc main() {.raises.} =
  ## All seven pinned pairs retain their independent root/value/count expectations after checkpoint restore.
  let mappings = publishedMappings()
  for i in 0..<7:
    assert mappings[2*i].entries.len > 0 # Every original source supplies a retained-value lifetime witness.
    replay(mappings[2*i], mappings[2*i+1])
  echo "PASS incremental checkpoint updates: seven published pairs, resumed writes, forks, exact exports and limits"
try:
  main()
except:
  # Missing/malformed trusted inputs and IO errors cannot become a passing zero-case replay.
  quit(2)
