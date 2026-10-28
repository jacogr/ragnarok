# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native storage replay of seven pinned pre/post mapping pairs, without executing their blocks.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/assertions
import std/syncio
import ../../support/codec_published_state
import ../../../src/state/store as state_store
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

## Replay forward, reordered and inverse batches, preserving both historical versions and retained views.
proc replay(before, after: Mapping) =
  let limits = policy(before, after)
  let initialized = newStateStore(before.entries, limits)
  assert initialized.error == StateStoreError.None
  var state = initialized.value
  let prior = state.snapshot.value
  matches(prior, before)
  assert before.entries.len > 0
  let held = prior.lookup(before.entries[0].key).value
  var changes = difference(before, after)
  let applied = state.apply(changes)
  assert applied.error == StateStoreError.None
  matches(applied.value, after)
  matches(prior, before)
  assert held.bytes == before.entries[0].value
  # Removed source keys must be absent, not present with an invented empty value.
  for entry in before.entries:
    if find(after.entries, entry.key) < 0:
      assert applied.value.lookup(entry.key).error == StateStoreError.MissingKey
  var independent = initialized.value
  var reversed = newSeq[StateWrite](changes.len)
  # Reverse only the batch order; preserve every borrowed key/value and the original mapping.
  for i in 0..<changes.len: reversed[i] = changes[changes.len-1-i]
  changes = reversed
  let reordered = independent.apply(changes)
  assert reordered.error == StateStoreError.None
  matches(reordered.value, after)
  let restored = state.apply(difference(after, before))
  assert restored.error == StateStoreError.None
  matches(restored.value, before)
  matches(applied.value, after)
  assert held.bytes == before.entries[0].value
  if changes.len > 0:
    # A deliberately insufficient batch budget rejects atomically even on real published state.
    var short = limits
    short.writes = ElementLimit(changes.len-1)
    let limited = newStateStore(before.entries, short)
    assert limited.error == StateStoreError.None
    var unchanged = limited.value
    assert unchanged.apply(changes).error == StateStoreError.LimitExceeded
    matches(unchanged.snapshot.value, before)

## Trusted input errors fail the suite independently of ordinary typed store failures.
proc main() {.raises.} =
  let mappings = publishedMappings()
  for i in 0..<7:
    replay(mappings[2*i], mappings[2*i+1]) # Each published pair still owns independent forward/inverse replay assertions.
  echo "PASS state store replay: seven published pairs, forward/reordered/inverse writes and snapshots"

try:
  main()
except:
  # Missing/malformed trusted fixtures never become a successful zero-case discovery.
  quit(2)
