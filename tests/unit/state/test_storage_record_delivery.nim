# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Ordered record delivery preflights all structure, preserves owned values and exposes provisional refusals.
import std/[algorithm, assertions, syncio]
import ../../support/storage_samples
import ../../../src/storage/[full_state_trie, node_records, record_codec]
import ../../../src/codec/[state_layout, state_trie, bounded]

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

let before = getOccupiedMem()
cycle()
assert getOccupiedMem() == before
echo "PASS storage record delivery: exact ownership, preflight, late integrity and consumer refusal"
