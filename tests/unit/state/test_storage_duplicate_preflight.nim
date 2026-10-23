# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Full-width duplicate oracles protect compact uniqueness proofs, hostile prefix fallback and mandatory integrity.
# @@Verification={"arc": "storage_duplicate_preflight_arc_release"}
import std/[assertions, syncio]
import ../../support/[arc_evidence, storage_samples]
import ../../../src/storage/[node_records, record_codec, full_state_trie]
import ../../../src/codec/[state_layout, state_trie, bounded]
type Stage = object ## Preparation/delivery observations never grant integrity to provisional callback prefixes.
  prepared, delivered: int
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Actual primitive refusal must remain observable after any mathematical uniqueness proof.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Duplicate preflight is hash-free; a distinct nonempty raw batch still reaches its first real hash.
proc policy(): RecordLimits =
  ## Fixed finite synthetic inventories contain no values and make no complete-graph authority claim.
  RecordLimits(trie: StateTrieLimits(items: ElementLimit(8192), perValue: ByteLimit(0),
    totalValueBytes: ByteLimit(0), nodes: TrieNodeLimit(200000)), records: TrieExportLimits(
    records: TrieNodeLimit(8192), valueBytes: ByteLimit(0)), encoded: ByteLimit(1048576))
proc records(count, mode: int, duplicate: bool): seq[TrieRecord] =
  ## Deliberately untrusted digests cover distinct/high-bit prefixes, collisions and a final-byte-only discriminator.
  result = newSeq[TrieRecord](count)
  for index in 0..<count:
    var digest = default(array[32, byte])
    digest[0] = 128
    for octet in 0..<8:
      digest[24+octet] = byte((uint64(index+1) shr (octet*8)) and 255)
    if mode == 0 or mode == 4 or mode == 5:
      for octet in 0..<8: digest[octet] = byte((uint64(index+1) shr (octet*8)) and 255)
    elif mode == 2: digest[0] = byte(index mod 17+1)
    elif mode == 3:
      for octet in 8..<31: digest[octet] = 255
      digest[31] = byte((index+1) and 255) # Above256 entries intentionally collide; the full-width oracle decides.
    result[index] = TrieRecord(kind: TrieRecordKind.Leaf, digest: StateNodeHash(digest))
  if (mode == 4 or mode == 5) and result.len > 2:
    var middle = array[32, byte](result[result.len div 2].digest)
    let first = array[32, byte](result[0].digest)
    let bytes = if mode == 4: 8 else: 32
    for octet in 0..<bytes: middle[octet] = first[octet]
    result[result.len div 2].digest = StateNodeHash(
        middle) # Sparse prefix collisions and interior full duplicates.
  if duplicate and result.len > 0:
    let first = result[0]
    result.add(first) # Duplicate the whole physical address, not merely its compact scratch key.
proc duplicates(input: seq[TrieRecord]): bool =
  ## Independent quadratic comparison examines every byte and never relies on sorting or prefix extraction.
  for index in 0..<input.len:
    for prior in 0..<index:
      let a = array[32, byte](input[index].digest)
      let b = array[32, byte](input[prior].digest)
      var equal = true
      for octet in 0..<32:
        if a[octet] != b[octet]: equal = false
      if equal: return true
  false
proc metadata(input: seq[TrieRecord]): TrieExport =
  ## Local nonzero target/count claims are shape-valid; only later complete admission could grant graph authority.
  var root = default(array[32, byte])
  if input.len > 0: root[0] = 1
  TrieExport(root: StateRoot(root), entries: uint64(input.len), nodes: uint64(input.len),
      records: input)
proc put(output: var seq[byte], offset: int, value: uint64) =
  ## The finite authored wire builder proves every E8 field inside its exact checked test-owned extent.
  for index in 0..<8: output[offset+index] = byte((value shr (index*8)) and 255)
proc wire(input: seq[TrieRecord], collection: bool): seq[byte] =
  ## Independently author malformed-hash transport; production writers correctly refuse these synthetic identities.
  let magic = if collection: "RAGNAROK-RECORDS-V1\n" else: "RAGNAROK-TRIE-V1\n"
  let header = magic.len+(if collection: 8 else: 88)
  result = newSeq[byte](header+input.len*72)
  for index, character in magic: result[index] = byte(character)
  if collection: put(result, magic.len, uint64(input.len))
  else:
    if input.len > 0: result[magic.len+32] = 1 # Base stays empty; target/entry/node/count fields have exact public widths.
    put(result, magic.len+64, uint64(input.len))
    put(result, magic.len+72, uint64(input.len))
    put(result, magic.len+80, uint64(input.len))
  var offset = header
  for record in input:
    let digest = array[32, byte](record.digest)
    for index in 0..<32: result[offset+1+index] = digest[index]
    offset+=72 # Zero tag/key/E8 length describe a canonical empty-value leaf with an untrusted digest.
proc prepare(stage: var Stage, info: RecordCollectionInfo) =
  ## Preparation may occur only after successful complete structural and duplicate preflight.
  inc stage.prepared
proc accept(stage: var Stage, record: var TrieRecord): bool =
  ## No synthetic nonempty record may reach this callback while the real provider refuses its local integrity.
  inc stage.delivered
  true
proc exercise(count, mode: int, duplicate: bool) =
  ## Exact full-width duplicate reasons precede hashes/callbacks; all nonempty unique sources still need integrity.
  let input = records(count, mode, duplicate)
  let repeated = duplicates(input)
  let batch = metadata(input)
  let target = wire(input, false)
  let collection = wire(input, true)
  let expected = if repeated: RecordError.DuplicateNode
    elif input.len == 0: RecordError.None else: RecordError.BackendFailure
  for api in 0..<5:
    reset(1)
    let reason = if api == 0: validateRecordCollection(RecordCollection(records: input), policy())
      elif api == 1: encodeTrieExport(batch, policy()).error
      elif api == 2: encodeRecordCollection(RecordCollection(records: input), policy()).error
      elif api == 3: decodeTrieExport(target, policy()).error
      else: decodeRecordCollection(collection, policy()).error
    assert reason == expected
    assert calls() == (if repeated or input.len == 0: 0 else: 1)
  reset(1)
  let inspected = inspectTrieExport(target, policy())
  assert inspected.error == (if repeated: RecordError.DuplicateNode else: RecordError.None)
  assert calls() == 0 # Shape/uniqueness inspection never grants local-integrity or graph authority.
  var stage = Stage(prepared: 0, delivered: 0)
  let delivered = visitTrieExport(target, policy(), stage, prepare, accept)
  assert delivered.error == expected and stage.delivered == 0
  assert stage.prepared == (if repeated: 0 else: 1)
  assert calls() == (if repeated or input.len == 0: 0 else: 1)
  var malformed = target
  if input.len > 0:
    for index in 0..<32: malformed[TrieExportHeaderBytes+1+index] = 0
    reset(1)
    assert inspectTrieExport(malformed, policy()).error == RecordError.NonCanonical
    assert calls() == 0 # Whole-input canonical shape still precedes duplicate and integrity checks.
  reset(0)
proc realControl() =
  ## The real complete fixture must preserve exact strict codec hashes, bytes and successful decoding.
  let limits = storageLimits().codec
  let batch = exportFullTrie(storageTrie(), limits.records).value
  reset(0)
  let encoded = encodeTrieExport(batch, limits).value
  assert calls() == 3
  reset(1)
  assert inspectTrieExport(encoded, limits).error == RecordError.None and calls() == 0
  assert decodeTrieExport(encoded, limits).error == RecordError.BackendFailure and calls() == 1
  reset(0)
  assert decodeTrieExport(encoded, limits).error == RecordError.None and calls() == 3

proc selectedIntegrity() =
  ## Sparse duplicate groups may narrow identity comparison, never integrity checks on the remaining records.
  var entries = newSeq[StateEntry](32)
  for index in 0..<entries.len:
    var key = default(array[31, byte])
    key[0] = byte(index)
    entries[index] = StateEntry(key: StateKey(key))
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: policy().trie)).value
  let source = exportFullTrie(trie, policy().records).value
  var input = source
  let selected = input.records.len div 2
  let first = array[32, byte](input.records[0].digest)
  var changed = array[32, byte](input.records[selected].digest)
  for octet in 0..<8: changed[octet] = first[octet]
  assert changed != first # Distinct full hashes must not be rejected merely because their compact keys collide.
  input.records[selected].digest = StateNodeHash(changed)
  var pairs = 0
  for index in 0..<input.records.len:
    for prior in 0..<index:
      let a = array[32, byte](input.records[index].digest)
      let b = array[32, byte](input.records[prior].digest)
      var equal = true
      for octet in 0..<8:
        if a[octet] != b[octet]: equal = false
      if equal: inc pairs
  assert pairs == 1 and selected > 2 # This fixed real fixture necessarily chooses one sparse two-record group.
  var encoded = encodeTrieExport(source, policy()).value
  var offset = TrieExportHeaderBytes
  for index in 0..<selected:
    offset += (if source.records[index].kind == TrieRecordKind.Leaf: 72 else: 97)
  for octet in 0..<8: encoded[offset+1+octet] = first[octet]
  reset(1)
  assert inspectTrieExport(encoded, policy()).error == RecordError.None and calls() == 0
  reset(0)
  assert encodeTrieExport(input, policy()).error == RecordError.HashMismatch
  assert calls() == selected+1 # Every valid nonselected record before the altered identity must still be hashed.
  reset(0)
  assert decodeTrieExport(encoded, policy()).error == RecordError.HashMismatch
  assert calls() == selected+1

for mode in 0..<6:
  for count in [0, 1, 2, 15, 16, 17, 63, 64, 65, 127, 128, 129, 257]:
    for duplicate in [false, true]: exercise(count, mode, duplicate)
realControl()
selectedIntegrity()
for warmup in 0..<10: exercise(3, 2, true)
let before = getOccupiedMem()
for iteration in 0..<1000:
  exercise(3, 0, false)
  exercise(3, 1, false)
  exercise(3, 2, true)
  exercise(17, 4, false)
  exercise(17, 5, false)
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_duplicate_preflight", 1000, before, after)
echo "PASS storage duplicate preflight: full-width oracle, compact proofs, hostile fallback, strict integrity and ARC"
