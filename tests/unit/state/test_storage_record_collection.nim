# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Record collections preserve shared physical encoding with independent multi-root aggregate ceilings.
import std/[assertions, syncio]
import ../../support/storage_samples
import ../../../src/storage/[full_state_trie, node_records, record_codec]
import ../../../src/codec/[state_layout, state_trie, bounded]
let limits = storageLimits().codec
let first = storageTrie(7)
let last = storageTrie(8)
var records = exportFullTrie(first, limits.records).value.records
for record in exportTrieChanges(first, last, limits.records).value.records:
  records.add(record) # The shared leaf appears only once in this multi-root union.
let collection = RecordCollection(records: records)
var physical = limits
physical.trie.totalValueBytes = ByteLimit(2)
physical.records.valueBytes = ByteLimit(3)
let encoded = encodeRecordCollection(collection, physical).value
assert measureRecordCollection(collection, physical).value == encoded.len
assert decodeRecordCollection(encoded, physical).value.records.len == 5
assert decodeTrieExport(encoded, physical).error == RecordError.InvalidFormat
let ordinary = encodeTrieExport(exportFullTrie(first, limits.records).value, limits).value
assert decodeRecordCollection(ordinary, physical).error == RecordError.InvalidFormat
for size in 0..<encoded.len:
  assert decodeRecordCollection(encoded.toOpenArray(0, size-1), physical).error !=
      RecordError.None # No partial record union escapes.
var short = physical
short.records.valueBytes = ByteLimit(2)
assert encodeRecordCollection(collection, short).error == RecordError.LimitExceeded
assert decodeRecordCollection(encoded, short).error == RecordError.LimitExceeded
short = physical
short.records.records = TrieNodeLimit(4)
assert decodeRecordCollection(encoded, short).error == RecordError.LimitExceeded
short = physical
short.encoded = ByteLimit(encoded.len-1)
assert decodeRecordCollection(encoded, short).error == RecordError.LimitExceeded
var duplicate = collection
duplicate.records.add(records[0])
assert validateRecordCollection(duplicate, limits) == RecordError.DuplicateNode
var altered = collection
altered.records[0].payload[0] = 99
assert validateRecordCollection(altered, limits) == RecordError.HashMismatch
var huge = encoded
for index in 0..<8: huge["RAGNAROK-RECORDS-V1\n".len+index] = 255
assert decodeRecordCollection(huge, physical).error != RecordError.None
let empty = encodeRecordCollection(default(RecordCollection), physical).value
assert decodeRecordCollection(empty, physical).value.records.len == 0
var trailing = encoded
trailing.add(0'u8)
assert decodeRecordCollection(trailing, physical).error == RecordError.InvalidFormat
echo "PASS storage record collection: exact domain, union budgets, truncation and integrity"
