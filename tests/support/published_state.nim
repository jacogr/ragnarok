# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared exact published mapping fixtures retain original keys, values and independent roots.

import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../src/state/store
import ../../src/codec/[state_trie, state_layout, bounded]

type
  ## Trusted published bytes and commitments, independently checked before fixture preparation.
  Mapping* = object
    entries*: seq[StateEntry]
    root*: StateRoot
    nodes*: uint64

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
proc mapping*(line: string): Mapping {.raises.} =
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

## Bind all public lookups, exact entry/node counts and root bytes to an original published mapping.
proc matches*(snapshot: StateStoreSnapshot, expected: Mapping) =
  let committed = snapshot.commitment
  assert committed.entries == expected.entries.len and committed.nodes == expected.nodes
  assert array[32, byte](committed.root) == array[32, byte](expected.root)
  # Count equality plus lookup equality excludes both missing and extra stored entries.
  for entry in expected.entries:
    let found = snapshot.lookup(entry.key)
    assert found.error == StateStoreError.None
    assert found.value.byteLength == entry.value.len and found.value.bytes == entry.value

## Select finite budgets for both complete maps and either direction's unique-key writes.
proc policy*(before, after: Mapping): StateStoreLimits =
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

proc publishedMappings*(): seq[Mapping] {.raises.} =
  ## Fail closed on missing, truncated or extra fixtures rather than accepting zero replay cases.
  let path = getEnv("RAGNAROK_STORE_REPLAY")
  assert path.len > 0
  let lines = readFile(path).splitLines()
  assert lines.len == 15 and lines[14] == ""
  result = @[]
  for index in 0..<14:
    result.add(mapping(lines[index])) # Preserve all source identities, including repeated roots between published observations.
