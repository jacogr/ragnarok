# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native storage replay of seven pinned pre/post mapping pairs, without executing their blocks.
import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../../src/state/store
import ../../../src/codec/[state_trie, state_layout, bounded]

type
  ## Trusted published bytes and commitments, independently checked before fixture preparation.
  Mapping = object
    entries: seq[StateEntry]
    root: StateRoot
    nodes: uint64

## Decode exact fixture bytes; a dash represents a present value with zero octets.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Preserve present-empty values rather than omitting their key.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Parse every byte without accepting truncated, uppercase or non-hex fixture tokens.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    for c in pair: assert c in {'0'..'9', 'a'..'f'} # Input is generated lowercase ASCII hex.
    var octet = 0'u8
    assert parseHex(pair, octet) == 2
    result[i] = octet

## Parse one complete mapping; exact framing rejects truncated or extra fixture tokens.
proc mapping(line: string): Mapping {.raises.} =
  let parts = line.splitWhitespace()
  assert parts.len >= 3
  let rawRoot = unhex(parts[0])
  assert rawRoot.len == 32
  var root = default(array[32, byte])
  for i in 0..<32: root[i] = rawRoot[i] # Copy all root bytes, including leading zeroes.
  var nodes = 0'u64
  assert parseBiggestUInt(parts[1], nodes) == parts[1].len
  let count = parseInt(parts[2])
  assert count >= 0 and count <= 1024 and parts.len == 3+2*count
  var entries = newSeq[StateEntry](count)
  # The original 31-byte identities are never shortened or interpreted as service namespaces.
  for i in 0..<count:
    let rawKey = unhex(parts[3+2*i])
    assert rawKey.len == 31
    var key = default(array[31, byte])
    for j in 0..<31: key[j] = rawKey[j] # Copy every original key octet.
    entries[i] = StateEntry(key: StateKey(key), value: unhex(parts[4+2*i]))
  Mapping(entries: entries, root: StateRoot(root), nodes: nodes)

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

## Bind all public lookups, exact entry/node counts and root bytes to an original published mapping.
proc matches(snapshot: StateStoreSnapshot, expected: Mapping) =
  let committed = snapshot.commitment
  assert committed.entries == expected.entries.len and committed.nodes == expected.nodes
  assert array[32, byte](committed.root) == array[32, byte](expected.root)
  # Count equality plus lookup equality excludes both missing and extra stored entries.
  for entry in expected.entries:
    let found = snapshot.lookup(entry.key)
    assert found.error == StateStoreError.None
    assert found.value.byteLength == entry.value.len and found.value.bytes == entry.value

## Select finite budgets for both complete maps and either direction's unique-key writes.
proc policy(before, after: Mapping): StateStoreLimits =
  var perValue = 0'u64
  var total = 0'u64
  for entries in [before.entries, after.entries]:
    var sum = 0'u64
    # Fixture sizes are small, but checked additions keep the test meaningful under wrapping arithmetic.
    for entry in entries:
      let size = uint64(entry.value.len)
      assert size <= 16777216'u64 and sum <= high(uint64)-size
      sum += size
      perValue = max(perValue, size)
    total = max(total, sum)
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(max(before.entries.len,
      after.entries.len)),
    perValue: ByteLimit(perValue), totalValueBytes: ByteLimit(total),
    nodes: TrieNodeLimit(max(before.nodes, after.nodes))),
    writes: ElementLimit(before.entries.len+after.entries.len), writeValueBytes: ByteLimit(total))

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
  let path = getEnv("RAGNAROK_STORE_REPLAY")
  assert path.len > 0
  let lines = readFile(path).splitLines()
  assert lines.len == 15 and lines[14] == ""
  # Preserve all seven sources as separate pairs, including repeated roots between observations.
  for i in 0..<7: replay(mapping(lines[2*i]), mapping(lines[2*i+1]))
  echo "PASS state store replay: seven published pairs, forward/reordered/inverse writes and snapshots"

try:
  main()
except:
  # Missing/malformed trusted fixtures never become a successful zero-case discovery.
  quit(2)
