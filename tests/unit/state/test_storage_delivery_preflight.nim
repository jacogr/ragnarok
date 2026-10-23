# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored malformed extents and limits must refuse before preparation, hashing or provisional delivery.
import std/[algorithm, assertions, syncio]
import ../../support/storage_samples
import ../../../src/storage/[full_state_trie, node_records, record_codec]
import ../../../src/codec/[state_layout, state_trie, bounded]
type Trace = object ## Callback counters remain independent of codec metadata and native hash counters.
  starts, records: int
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Retain real hashing while observing exact zero-work preflight boundaries.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Capture local crypto work without substituting digests.
proc prepare(state: var Trace, info: RecordCollectionInfo) =
  ## The callback's common name intentionally matches the API formal; private binding must remain unambiguous.
  assert state.starts == 0 and int(calls()) == 0
  inc state.starts
proc consume(state: var Trace, record: var TrieRecord): bool =
  ## The common consumer name also matches the API formal and cannot shadow its bound procedure value.
  assert state.starts == 1 and state.records < 16
  inc state.records
  true
proc exercise(input: openArray[byte], limits: RecordLimits, collection: bool,
    expected: RecordError, records = 0) =
  ## Invalid structures leave both callbacks and crypto untouched and retire all local scratch.
  var state = Trace(starts: 0, records: 0)
  reset(0)
  let before = getOccupiedMem()
  let error = if collection:
    visitOrderedRecordCollection(input, limits, state, prepare, consume).error
  else:
    visitTrieExport(input, limits, state, prepare, consume).error
  assert error == expected
  if expected == RecordError.None:
    assert state.starts == 1 and state.records == records and int(calls()) == records
  else:
    assert state.starts == 0 and state.records == 0 and int(calls()) == 0
  assert getOccupiedMem() == before
proc putNumber(input: var seq[byte], offset: int, value: uint64) =
  ## The corpus owns exact fixed-width edits; prove every destination before writing little-endian bytes.
  assert offset >= 0 and offset <= input.len-8
  for index in 0..<8:
    input[offset+index] = byte((value shr (index*8)) and 255)
proc compareRecord(a, b: TrieRecord): int =
  ## Independent canonical fixture order uses complete address bytes, never an exported trusted scan token.
  let left = array[32, byte](a.digest)
  let right = array[32, byte](b.digest)
  for index in 0..<32:
    if left[index] < right[index]: return -1 # A fixed-width lexical comparison has no alternate order.
    if left[index] > right[index]: return 1
  0

proc cycle() =
  ## Freeze expected refusals independently of both detached and visitor parser implementations.
  let policy = storageLimits().codec
  let batch = exportFullTrie(storageTrie(7), policy.records).value
  let wire = encodeTrieExport(batch, policy).value
  var sorted = batch.records
  sorted.sort(compareRecord)
  let collection = encodeRecordCollection(RecordCollection(records: sorted), policy).value
  for length in 0..<wire.len:
    exercise(wire.toOpenArray(0, length-1), policy, false, RecordError.InvalidFormat)
  for length in 0..<collection.len:
    exercise(collection.toOpenArray(0, length-1), policy, true, RecordError.InvalidFormat)
  exercise(wire, policy, false, RecordError.None, 3)
  exercise(collection, policy, true, RecordError.None, 3)
  exercise(wire, policy, true, RecordError.InvalidFormat)
  exercise(collection, policy, false, RecordError.InvalidFormat)
  let header = "RAGNAROK-TRIE-V1\n".len+88
  var edited = wire
  putNumber(edited, header-8, high(uint64))
  exercise(edited, policy, false, RecordError.InvalidFormat)
  edited = wire
  putNumber(edited, header-8, 0)
  exercise(edited, policy, false, RecordError.InvalidFormat)
  edited = wire
  putNumber(edited, header+64, high(uint64))
  exercise(edited, policy, false, RecordError.InvalidFormat)
  edited = wire
  putNumber(edited, "RAGNAROK-TRIE-V1\n".len+64, 17)
  exercise(edited, policy, false, RecordError.LimitExceeded)
  edited = wire
  putNumber(edited, "RAGNAROK-TRIE-V1\n".len+72, 501)
  exercise(edited, policy, false, RecordError.NonCanonical)
  edited = wire
  edited[header] = 2
  exercise(edited, policy, false, RecordError.NonCanonical)
  edited = wire
  for index in header+1..<header+33:
    edited[index] = 0 # Empty physical identities cannot be admitted even under a nonempty target claim.
  exercise(edited, policy, false, RecordError.NonCanonical)
  edited = wire
  let branch = header+146
  assert batch.records[2].kind == TrieRecordKind.Branch
  for index in branch+33..<branch+97:
    edited[index] = 0 # A late structurally empty branch must refuse before earlier valid leaf callbacks.
  exercise(edited, policy, false, RecordError.NonCanonical)
  edited = wire
  edited.add(0)
  exercise(edited, policy, false, RecordError.InvalidFormat)
  var narrow = policy
  narrow.trie.perValue = ByteLimit(0)
  exercise(wire, narrow, false, RecordError.LimitExceeded)
  exercise(collection, narrow, true, RecordError.LimitExceeded)
  narrow = policy
  narrow.records.records = TrieNodeLimit(2)
  exercise(wire, narrow, false, RecordError.LimitExceeded)
  exercise(collection, narrow, true, RecordError.LimitExceeded)
  narrow = policy
  narrow.trie.totalValueBytes = ByteLimit(0)
  exercise(wire, narrow, false, RecordError.LimitExceeded)
  exercise(collection, narrow, true, RecordError.None,
      3) # Collections retain an independent physical union budget.
  narrow = policy
  narrow.encoded = ByteLimit(wire.len-1)
  exercise(wire, narrow, false, RecordError.LimitExceeded)
  var reversed = RecordCollection(records: @[])
  for index in 0..<sorted.len:
    reversed.records.add(sorted[sorted.len-1-index])
  let outOfOrder = encodeRecordCollection(reversed, policy).value
  exercise(outOfOrder, policy, true, RecordError.NonCanonical)
  let collectionHeader = "RAGNAROK-RECORDS-V1\n".len+8
  let firstExtent = if sorted[0].kind == TrieRecordKind.Leaf: 72+sorted[0].payload.len else: 97
  var duplicate: seq[byte] = @[]
  for index in 0..<collectionHeader+firstExtent:
    duplicate.add(collection[index]) # Preserve the header and first exact record.
  for index in collectionHeader..<collectionHeader+firstExtent:
    duplicate.add(collection[index]) # Adjacent equal addresses prove duplicate refusal before order descent.
  for index in collectionHeader+firstExtent..<collection.len:
    duplicate.add(collection[index])
  putNumber(duplicate, collectionHeader-8, 4)
  exercise(duplicate, policy, true, RecordError.DuplicateNode)
  let empty = encodeRecordCollection(RecordCollection(), policy).value
  exercise(empty, policy, true, RecordError.None)
  let emptyBatch = encodeTrieExport(default(TrieExport), policy).value
  exercise(emptyBatch, policy, false, RecordError.None)

let before = getOccupiedMem()
cycle()
assert getOccupiedMem() == before
echo "PASS storage delivery preflight: exact malformed corpus, no callbacks or crypto, local cleanup"
