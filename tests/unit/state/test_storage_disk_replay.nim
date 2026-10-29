# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real-file standalone replay of all seven pinned mapping pairs without executing their blocks.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, envvars, parseutils, strutils, syncio]
import std/posix/posix
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/node/records as node_records
import ../../../src/storage/record_codec
import ../../../src/storage/node/repository as node_repository
import ../../../src/storage/file/repository as file_repository
import ../../../src/storage/[database_identity, revision_retention, durability]
import ../../../src/codec/state/[trie as state_trie, layout as state_layout]
import ../../../src/codec/bounded

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

## Find a fixture key by linear scan, independent of production path copying.
proc find(entries: seq[StateEntry], key: StateKey): int =
  for i, entry in entries:
    if array[31, byte](entry.key) == array[31, byte](key): return i # Exact identity only.
  -1

## Derive a unique-key batch from two complete maps; snapshots supply no expectations.
proc difference(before, after: Mapping): seq[TrieWrite] =
  result = @[]
  # Only keys absent from the destination need deletion.
  for entry in before.entries:
    if find(after.entries, entry.key) < 0:
      result.add TrieWrite(key: entry.key, kind: TrieWriteKind.Delete)
  # Insert new keys and replace changed values, preserving empty values as ordinary Put operations.
  for entry in after.entries:
    let old = find(before.entries, entry.key)
    if old < 0 or before.entries[old].value != entry.value:
      result.add TrieWrite(key: entry.key, kind: TrieWriteKind.Put, value: entry.value)

## Bind all public lookups, exact entry/node counts and root bytes to an original published mapping.
proc matches(snapshot: FullStateTrie, expected: Mapping) =
  let committed = snapshot.commitment
  assert committed.entries == expected.entries.len and committed.nodes == expected.nodes
  assert array[32, byte](committed.root) == array[32, byte](expected.root)
  # Count equality plus lookup equality excludes both missing and extra stored entries.
  for entry in expected.entries:
    let found = snapshot.lookup(entry.key)
    assert found.error == TrieError.None
    assert found.value.byteLength == entry.value.len and found.value.bytes == entry.value

## Select finite budgets for both complete maps and either direction's unique-key writes.
proc policy(before, after: Mapping): FullStateTrieLimits =
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
  FullStateTrieLimits(trie: StateTrieLimits(items: ElementLimit(max(before.entries.len,
      after.entries.len)),
    perValue: ByteLimit(perValue), totalValueBytes: ByteLimit(total),
    nodes: TrieNodeLimit(max(before.nodes, after.nodes))),
    writes: ElementLimit(before.entries.len+after.entries.len), writeValueBytes: ByteLimit(total))

## Replay durable full/delta/inverse batches with strict reopen and independently retained views.
proc replay(before, after: Mapping) =
  ## Raw physical changes reconstruct all original values under independently pinned roots.
  let limits = policy(before, after)
  let recordLimits = TrieExportLimits(records: limits.trie.nodes,
    valueBytes: limits.trie.totalValueBytes)
  let codec = RecordLimits(trie: limits.trie, records: recordLimits, encoded: ByteLimit(high(uint64)))
  assert before.nodes <= high(uint64)-after.nodes
  assert uint64(limits.trie.totalValueBytes) <= high(uint64) div 2
  let storage = RepositoryLimits(codec: codec, records: ElementLimit(before.nodes+after.nodes),
    valueBytes: ByteLimit(uint64(limits.trie.totalValueBytes)*2))
  let initial = newFullStateTrie(before.entries, limits).value
  let target = initial.apply(difference(before, after)).value
  let path = "storage-disk-replay.db"
  let journal = JournalLimits(repository: storage, bytes: ByteLimit(134217728))
  var repository = default(FileRepository)
  assert initializeFileRepository(repository, path, default(StorageChainId), journal) == FileError.None
  defer:
    # Fixture/IO exceptions must still release native ownership before process teardown.
    if repository.opened: discard repository.close
    var nativePath = path
    discard posix.unlink(nativePath.toCString())
  var pins = newRevisionRetention(ElementLimit(2))
  let first = repository.publish(repository.snapshot.value,
    exportFullTrie(initial, recordLimits).value).value
  let pin = pins.retain(first).value
  matches(restoreFullTrie(first, before.root, limits).value, before)
  assert repository.close == FileError.None
  assert openFileRepository(repository, path, default(StorageChainId), journal) == FileError.None
  let base = repository.snapshot.value
  matches(restoreFullTrie(base, before.root, limits).value, before)
  let next = repository.publish(base, exportTrieChanges(initial, target, recordLimits).value).value
  let later = pins.retain(next).value
  assert repository.synchronize.value == StorageDurability.FileAndDirectorySynced
  matches(restoreFullTrie(next, after.root, limits).value, after)
  matches(restoreFullTrie(pins.lookup(pin).value, before.root, limits).value, before)
  assert repository.close == FileError.None
  assert openFileRepository(repository, path, default(StorageChainId), journal) == FileError.None
  matches(restoreFullTrie(repository.snapshot.value, after.root, limits).value, after)
  let reverted = target.apply(difference(after, before)).value
  let last = repository.publish(repository.snapshot.value,
    exportTrieChanges(target, reverted, recordLimits).value).value
  assert uint64(last.generation) == 3
  assert repository.close == FileError.None
  assert openFileRepository(repository, path, default(StorageChainId), journal) == FileError.None
  matches(restoreFullTrie(repository.snapshot.value, before.root, limits).value, before)
  assert repository.close == FileError.None
  matches(restoreFullTrie(pins.lookup(later).value, after.root, limits).value, after)
  matches(restoreFullTrie(first, before.root, limits).value, before)
  assert pins.release(pin) == RetentionError.None and pins.release(later) == RetentionError.None
  assert pins.close == RetentionError.None

## Trusted input errors fail the suite independently of ordinary typed trie failures.
proc main() {.raises.} =
  let path = getEnv("RAGNAROK_STORE_REPLAY")
  assert path.len > 0
  let lines = readFile(path).splitLines()
  assert lines.len == 15 and lines[14] == ""
  # Preserve all seven sources as separate pairs, including repeated roots between observations.
  for i in 0..<7: replay(mapping(lines[2*i]), mapping(lines[2*i+1]))
  echo "PASS storage disk replay: seven published pairs, durable full/delta/inverse frames, reopen and retained views"

try:
  main()
except:
  # Missing/malformed trusted fixtures never become a successful zero-case discovery.
  quit(2)
