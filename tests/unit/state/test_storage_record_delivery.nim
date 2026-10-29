# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Ordered record delivery preflights all structure, preserves owned values and exposes provisional refusals.
import std/[algorithm, assertions, syncio]
import ../../support/storage_samples
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/node/records as node_records
import ../../../src/storage/record_codec
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/codec/bounded

type Delivery = object ## Explicit caller-owned state never retains a borrow into the source buffer.
  records: seq[TrieRecord]
  calls, stopAfter: int
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Clear observed hash calls while keeping real primitive implementations enabled.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count actual local integrity work separately from callback execution.
proc compareRecord(a, b: TrieRecord): int =
  ## Author a canonical physical order without trusting decoder sort behavior.
  let left = array[32, byte](a.digest)
  let right = array[32, byte](b.digest)
  for index in 0..<32:
    if left[index] < right[index]: return -1 # The first distinct byte determines physical order.
    if left[index] > right[index]: return 1
  0
proc sameRecords(a, b: seq[TrieRecord]): bool =
  ## Compare nominal address/key representations explicitly; no implicit raw-object equality is assumed.
  if a.len != b.len: return false
  for index in 0..<a.len:
    let left = a[index]
    let right = b[index]
    if left.kind != right.kind or left.payload != right.payload or
        array[32, byte](left.digest) != array[32, byte](right.digest) or
        array[31, byte](left.key) != array[31, byte](right.key) or
        array[32, byte](left.left) != array[32, byte](right.left) or
        array[32, byte](left.right) != array[32, byte](right.right):
      return false # Every physical field, including unused canonical fields, remains exact.
  true
proc accept(state: var Delivery, record: var TrieRecord): bool =
  ## Stop explicitly at the selected prefix; otherwise consume the sole detached record owner.
  inc state.calls
  if state.stopAfter >= 0 and state.records.len >= state.stopAfter: return false
  state.records.add(move(record))
  true
proc cycle() =
  ## Compare exact records, all prefixes, malformed tails, late hashes, consumer refusal and source retirement.
  let policy = storageLimits().codec
  var physical = exportFullTrie(storageTrie(7), policy.records).value.records
  physical.sort(compareRecord)
  let expected = RecordCollection(records: physical)
  var wire = encodeRecordCollection(expected, policy).value
  reset(0)
  let occupied = getOccupiedMem()
  let inspected = inspectOrderedRecordCollection(wire, policy)
  assert inspected.error == RecordError.None and inspected.value.records == uint64(physical.len)
  assert inspected.value.valueBytes == 2 and int(calls()) == 0
  assert getOccupiedMem() == occupied # Ordered structural inspection retains no descriptor or payload allocation.
  var delivered = Delivery(stopAfter: -1)
  reset(0)
  let completed = visitOrderedRecordCollection(wire, policy, delivered, accept)
  assert completed.error == RecordError.None
  assert completed.value.records == uint64(physical.len) and completed.value.valueBytes == 2
  assert sameRecords(delivered.records, physical) and delivered.calls == physical.len
  assert int(calls()) == physical.len # Each admitted small-value record hashes exactly once.
  for length in 0..<wire.len:
    # A malformed final extent refuses before the first callback or cryptographic operation.
    var prefix = Delivery(stopAfter: -1)
    reset(0)
    assert visitOrderedRecordCollection(wire.toOpenArray(0, length-1), policy,
      prefix, accept).error != RecordError.None
    assert prefix.calls == 0 and int(calls()) == 0
  var trailing = wire
  trailing.add(0)
  var malformed = Delivery(stopAfter: -1)
  assert visitOrderedRecordCollection(trailing, policy, malformed, accept).error ==
      RecordError.InvalidFormat
  assert malformed.calls == 0
  var offset = "RAGNAROK-RECORDS-V1\n".len+8
  var last = offset
  for record in physical:
    # The authored fixture has one-byte leaves and canonical fixed branch extents.
    last = offset
    if record.kind == TrieRecordKind.Leaf: offset += 73
    else: offset += 97
  var corrupt = wire
  if physical[^1].kind == TrieRecordKind.Leaf:
    corrupt[last+72] = corrupt[last+72] xor 1 # A late payload mismatch passes structural preflight.
  else:
    corrupt[last+33] = corrupt[last+33] xor 1 # A nonempty branch still needs exact local integrity.
  var provisional = Delivery(stopAfter: -1)
  assert visitOrderedRecordCollection(corrupt, policy, provisional, accept).error ==
      RecordError.HashMismatch
  assert provisional.records.len == physical.len-1 and provisional.calls == physical.len-1
  var stopped = Delivery(stopAfter: 1)
  assert visitOrderedRecordCollection(wire, policy, stopped, accept).error ==
      RecordError.ConsumerRefused
  assert stopped.records.len == 1 and stopped.calls == 2
  wire[0] = 0 # All callback-retained records outlive and remain independent of mutable source bytes.
  assert sameRecords(delivered.records, physical)
  let empty = encodeRecordCollection(RecordCollection(), policy).value
  var none = Delivery(stopAfter: -1)
  assert visitOrderedRecordCollection(empty, policy, none, accept).value.records == 0
  assert none.calls == 0

proc batchCycle() =
  ## Preserve target metadata and serialized order while rejecting all duplicates before hashes or delivery.
  let policy = storageLimits().codec
  let physical = exportFullTrie(storageTrie(7), policy.records).value
  var wire = encodeTrieExport(physical, policy).value
  reset(0)
  let inspected = inspectTrieExport(wire, policy)
  assert inspected.error == RecordError.None and inspected.value.records == uint64(
      physical.records.len)
  assert inspected.value.valueBytes == 2 and int(calls()) == 0
  assert array[32, byte](inspected.value.root) == array[32, byte](physical.root)
  var delivered = Delivery(stopAfter: -1)
  reset(0)
  let completed = visitTrieExport(wire, policy, delivered, accept)
  assert completed.error == RecordError.None
  let info = completed.value
  assert array[32, byte](info.base) == array[32, byte](physical.base)
  assert array[32, byte](info.root) == array[32, byte](physical.root)
  assert info.entries == physical.entries and info.nodes == physical.nodes
  assert info.records == uint64(physical.records.len) and info.valueBytes == 2
  assert sameRecords(delivered.records, physical.records) and int(calls()) == physical.records.len
  let header = "RAGNAROK-TRIE-V1\n".len+88
  var duplicate = wire
  for index in header..<header+73:
    duplicate.add(wire[index]) # The authored first record is a complete one-byte leaf.
  duplicate[header-8] = byte(physical.records.len+1)
  var none = Delivery(stopAfter: -1)
  reset(0)
  assert visitTrieExport(duplicate, policy, none, accept).error == RecordError.DuplicateNode
  assert none.calls == 0 and int(calls()) == 0
  assert inspectTrieExport(duplicate, policy).error == RecordError.DuplicateNode
  assert int(calls()) == 0
  duplicate[header+72] = duplicate[header+72] xor 1 # Duplicate refusal still precedes a hash mismatch.
  assert visitTrieExport(duplicate, policy, none, accept).error == RecordError.DuplicateNode
  assert none.calls == 0 and int(calls()) == 0
  var narrow = policy
  narrow.records.valueBytes = ByteLimit(1)
  assert visitTrieExport(wire, narrow, none, accept).error == RecordError.LimitExceeded
  assert none.calls == 0 and int(calls()) == 0
  wire[0] = 0
  assert sameRecords(delivered.records, physical.records) # Success owns records independently of retired bytes.

type PreparedDelivery = object ## Preparation summary has no integrity authority over later record delivery.
  delivery: Delivery
  starts: int
  declaredRecords, declaredBytes: uint64
proc prepared(stopAfter = -1): PreparedDelivery =
  ## Explicitly initialize every observed counter and the consumer's optional refusal point.
  PreparedDelivery(delivery: Delivery(records: @[], calls: 0, stopAfter: stopAfter),
    starts: 0, declaredRecords: 0, declaredBytes: 0)
proc prepare(state: var PreparedDelivery, info: RecordCollectionInfo) =
  ## Preparation occurs once, after whole-input shape/duplicate checks and before the first hash.
  assert state.starts == 0 and int(calls()) == 0
  state.starts = 1
  state.declaredRecords = info.records
  state.declaredBytes = info.valueBytes
proc acceptPrepared(state: var PreparedDelivery, record: var TrieRecord): bool =
  ## Every real local record follows its provisional preparation phase.
  assert state.starts == 1
  accept(state.delivery, record)
proc preparedCycle() =
  ## Check both overloads, zero-work malformed/duplicate refusal, empty preparation and provisional late failures.
  let policy = storageLimits().codec
  let batch = exportFullTrie(storageTrie(7), policy.records).value
  var records = batch.records
  records.sort(compareRecord)
  let collection = encodeRecordCollection(RecordCollection(records: records), policy).value
  let wire = encodeTrieExport(batch, policy).value
  var ordered = prepared()
  reset(0)
  assert visitOrderedRecordCollection(collection, policy, ordered, prepare, acceptPrepared).error ==
      RecordError.None
  assert ordered.starts == 1 and ordered.declaredRecords == uint64(records.len)
  assert ordered.declaredBytes == 2 and sameRecords(ordered.delivery.records, records)
  var target = prepared()
  reset(0)
  assert visitTrieExport(wire, policy, target, prepare, acceptPrepared).error == RecordError.None
  assert target.starts == 1 and target.declaredRecords == uint64(batch.records.len)
  assert target.declaredBytes == 2 and sameRecords(target.delivery.records, batch.records)
  var invalid = collection
  invalid.add(0)
  var none = prepared()
  reset(0)
  assert visitOrderedRecordCollection(invalid, policy, none, prepare, acceptPrepared).error ==
      RecordError.InvalidFormat
  assert none.starts == 0 and none.delivery.calls == 0 and int(calls()) == 0
  let header = "RAGNAROK-TRIE-V1\n".len+88
  var duplicate = wire
  for index in header..<header+73:
    duplicate.add(wire[index]) # A complete authored leaf is duplicated after exact original records.
  duplicate[header-8] = byte(batch.records.len+1)
  assert visitTrieExport(duplicate, policy, none, prepare, acceptPrepared).error ==
      RecordError.DuplicateNode
  assert none.starts == 0 and none.delivery.calls == 0 and int(calls()) == 0
  let empty = encodeRecordCollection(RecordCollection(), policy).value
  var zero = prepared()
  reset(0)
  assert visitOrderedRecordCollection(empty, policy, zero, prepare, acceptPrepared).value.records == 0
  assert zero.starts == 1 and zero.declaredRecords == 0 and zero.delivery.calls == 0
  var corrupt = wire
  corrupt[corrupt.len-1] = corrupt[corrupt.len-1] xor 1
  var provisional = prepared()
  reset(0)
  assert visitTrieExport(corrupt, policy, provisional, prepare, acceptPrepared).error ==
      RecordError.HashMismatch
  assert provisional.starts == 1 and provisional.delivery.records.len == batch.records.len-1
  var stopped = prepared(1)
  reset(0)
  assert visitTrieExport(wire, policy, stopped, prepare, acceptPrepared).error ==
      RecordError.ConsumerRefused
  assert stopped.starts == 1 and stopped.delivery.records.len == 1 and stopped.delivery.calls == 2

let before = getOccupiedMem()
cycle()
batchCycle()
preparedCycle()
assert getOccupiedMem() == before
echo "PASS storage record delivery: exact ownership, preflight, late integrity and consumer refusal"
