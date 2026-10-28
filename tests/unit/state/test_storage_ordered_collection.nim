# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Canonical collection decoding rejects unordered/duplicate borrowed identities before allocation or hashing.
import std/algorithm
import std/assertions
import std/syncio
import ../../support/storage_samples
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/record_codec as storage_record_codec
import ../../../src/codec/state_trie as codec_state_trie
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Keep real hashes while resetting the existing primitive observer.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count genuine physical integrity attempts after shape/order preflight.
proc compare(left, right: TrieRecord): int =
  ## Independent lexical address comparison constructs a canonical test transport.
  let a = array[32, byte](left.digest)
  let b = array[32, byte](right.digest)
  for index in 0..<32:
    if a[index] < b[index]: return -1
    if a[index] > b[index]: return 1
  0
let limits = storageLimits().codec
var records = exportFullTrie(storageTrie(), limits.records).value.records
records.sort(compare)
let wire = encodeRecordCollection(RecordCollection(records: records), limits).value
reset(0)
let decoded = decodeOrderedRecordCollection(wire, limits)
assert decoded.error == RecordError.None and decoded.value.records.len == 3
assert int(calls()) == 3
for stop in 0..<wire.len:
  assert decodeOrderedRecordCollection(wire.toOpenArray(0, stop-1), limits).error !=
      RecordError.None
var reversed = records
let first = reversed[0]
let second = reversed[1]
reversed[0] = second
reversed[1] = first
let unordered = encodeRecordCollection(RecordCollection(records: reversed), limits).value
assert decodeRecordCollection(unordered, limits).error == RecordError.None
reset(0)
assert decodeOrderedRecordCollection(unordered, limits).error == RecordError.NonCanonical
assert int(calls()) == 0
# Two equal-length independently hashed leaf records allow an exact duplicate descriptor splice.
let raw = exportFullTrie(storageTrie(), limits.records).value.records
var duplicate = encodeRecordCollection(RecordCollection(records: @[raw[0], raw[1]]), limits).value
const header = "RAGNAROK-RECORDS-V1".len+1+8
const leaf = 73
assert duplicate.len == header+2*leaf
for index in 0..<leaf:
  let octet = duplicate[header+index]
  duplicate[header+leaf+index] = octet # Counts/extents remain valid; identities are deliberately repeated.
reset(0)
assert decodeOrderedRecordCollection(duplicate, limits).error == RecordError.DuplicateNode
assert int(calls()) == 0
assert decodeRecordCollection(duplicate, limits).error == RecordError.DuplicateNode
let empty = encodeRecordCollection(default(RecordCollection), limits).value
assert decodeOrderedRecordCollection(empty, limits).value.records.len == 0
var corrupt = wire
corrupt[wire.len-1] = corrupt[wire.len-1] xor 1
assert decodeOrderedRecordCollection(corrupt, limits).error == RecordError.HashMismatch
echo "PASS storage ordered collection: canonical order, early duplicates, full integrity and truncation"
