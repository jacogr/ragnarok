# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callback-live allocation witnesses reject hidden complete transport materialization on bounded delivery.
import std/[algorithm, assertions, syncio]
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/node/records as node_records
import ../../../src/storage/record_codec
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/codec/bounded

type
  Fixture = object ## Only stable encoded inputs and independent scalar expectations survive setup.
    collection, batch: seq[byte]
    records: int
    valueBytes: uint64
  Footprint = object ## Explicit nonretaining consumer measures live bytes at synchronous delivery only.
    baseline, maximum, records, perValue: int
    valueBytes: uint64
proc policy(): RecordLimits =
  ## Keep every native case bounded independently of count-derived allocations.
  RecordLimits(trie: StateTrieLimits(items: ElementLimit(1024), perValue: ByteLimit(257),
    totalValueBytes: ByteLimit(1048576), nodes: TrieNodeLimit(10000)),
    records: TrieExportLimits(records: TrieNodeLimit(10000), valueBytes: ByteLimit(1048576)),
    encoded: ByteLimit(1048576))
proc compareRecord(a, b: TrieRecord): int =
  ## The fixture authors strict physical order independently of encoded inspection or delivery.
  let left = array[32, byte](a.digest)
  let right = array[32, byte](b.digest)
  for index in 0..<32:
    if left[index] < right[index]: return -1 # Lexical address order has one exact representation.
    if left[index] > right[index]: return 1
  0
proc fixture(count, size: int): Fixture =
  ## Drop complete maps/transports before the observation; both closed encodings retain identical records.
  var entries = newSeq[StateEntry](count)
  for index in 0..<count:
    var key = default(array[31, byte])
    key[0] = byte(index shr 8)
    key[1] = byte(index and 255)
    var value = newSeq[byte](size)
    for offset in 0..<size:
      value[offset] = byte((index+offset) and 255) # Deterministic distinct complete values include every byte.
    entries[index] = StateEntry(key: StateKey(key), value: value)
  let limits = policy()
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: limits.trie)).value
  var physical = exportFullTrie(trie, limits.records).value
  physical.records.sort(compareRecord)
  Fixture(collection: encodeRecordCollection(RecordCollection(records: physical.records),
      limits).value,
    batch: encodeTrieExport(physical, limits).value, records: physical.records.len,
    valueBytes: uint64(count)*uint64(size))
proc observe(state: var Footprint, record: var TrieRecord): bool =
  ## Never retain records; a full hidden decoded sequence would remain visible throughout these callbacks.
  let occupied = getOccupiedMem()
  assert occupied >= state.baseline
  state.maximum = max(state.maximum, occupied-state.baseline)
  assert record.payload.len <= state.perValue
  assert state.records < 10000 and uint64(record.payload.len) <= 1048576'u64-state.valueBytes
  inc state.records
  state.valueBytes += uint64(record.payload.len)
  true
proc cycle() =
  ## Reverse counts and delivery order while keeping fixtures alive and comparing only same-process boundaries.
  for turn in 0..1:
    let counts = if turn == 0: [32, 512] else: [512, 32]
    for count in counts:
      for size in [32, 257]:
        let source = fixture(count, size)
        for order in 0..1:
          let collection = (order == turn)
          var observed = Footprint(baseline: getOccupiedMem(), maximum: 0,
            records: 0, perValue: size, valueBytes: 0)
          if collection:
            let completed = visitOrderedRecordCollection(source.collection, policy(), observed, observe)
            assert completed.error == RecordError.None
            assert completed.value.records == uint64(source.records)
            assert completed.value.valueBytes == source.valueBytes
          else:
            let completed = visitTrieExport(source.batch, policy(), observed, observe)
            assert completed.error == RecordError.None
            assert completed.value.records == uint64(source.records)
            assert completed.value.valueBytes == source.valueBytes
          assert observed.records == source.records and observed.valueBytes == source.valueBytes
          assert observed.maximum <= size+4096 # One local payload may live; a complete descriptor batch may not.
          assert getOccupiedMem() == observed.baseline # Every local payload and address scratch owner retires.
          assert source.collection.len > 0 and source.batch.len > 0 # Keep both borrowed source owners stable.

let before = getOccupiedMem()
cycle()
assert getOccupiedMem() == before
echo "PASS storage delivery footprint: bounded callback-live owners and complete local release"
