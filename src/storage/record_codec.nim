# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict versioned physical trie-record batches; validates shape/budgets before node hashes.
## Record validation is local integrity, not complete graph verification or chain authority.

import std/algorithm
import ./node_records
import ../codec/[state_trie, state_layout, bounded]

const
  RecordMagic = "RAGNAROK-TRIE-V1\n"
  RecordHeaderBytes = RecordMagic.len + 88

type
  RecordLimits* = object ## Separate complete target metadata, detached payloads and encoded extents.
    trie*: StateTrieLimits
    records*: TrieExportLimits
    encoded*: ByteLimit
  RecordError* {.pure.} = enum ## No default/refused operation exposes bytes or records.
    Uninitialized, None, InvalidFormat, NonCanonical, LimitExceeded, DuplicateNode,
    HashMismatch, BackendFailure
  RecordResult*[T] = object ## Private alternatives require successful selection before extraction.
    case status: RecordError
    of None: completed: T
    else: discard           # Errors contain no mutable buffers or partially validated records.

func error*[T](outcome: RecordResult[T]): RecordError =
  ## Read the precise refusal without exposing any payload.
  outcome.status
func value*[T](outcome: RecordResult[T]): T {.inline,
    requires: outcome.status == RecordError.None.} =
  ## Extract only a completed locally validated transport object.
  outcome.completed
func zero(hash: StateNodeHash): bool =
  ## The all-zero address is reserved for an empty physical subtree.
  array[32, byte](hash) == default(array[32, byte])
proc compareHash(a, b: StateNodeHash): int =
  ## Lexicographic fixed identities support bounded duplicate rejection.
  let left = array[32, byte](a)
  let right = array[32, byte](b)
  for i in 0..<32:
    if left[i] < right[i]: return -1 # First differing byte determines address order.
    if left[i] > right[i]: return 1
  0
func metadata(batch: TrieExport, count: uint64, limits: RecordLimits): RecordError =
  ## Check target claims and descriptor extent independently of dependency availability.
  if batch.entries > uint64(limits.trie.items) or batch.nodes > uint64(limits.trie.nodes) or
      count > uint64(limits.records.records) or count > uint64(high(int) div sizeof(TrieRecord)):
    return RecordError.LimitExceeded
  if array[32, byte](batch.root) == default(array[32, byte]):
    if batch.entries != 0 or batch.nodes != 0 or count != 0: return RecordError.NonCanonical
  else:
    if batch.entries == 0 or batch.nodes < batch.entries: return RecordError.NonCanonical
    if batch.entries <= high(uint64) div 249 and batch.nodes > batch.entries*249:
      return RecordError.NonCanonical # Topology claims cannot exceed the full key-depth bound.
  RecordError.None
proc extent(batch: TrieExport, limits: RecordLimits): RecordResult[int] =
  ## Validate all canonical fields and arithmetic before allocating hash/sort/output buffers.
  let checked = metadata(batch, uint64(batch.records.len), limits)
  if checked != RecordError.None: return RecordResult[int](status: checked)
  let maximum = min(uint64(limits.encoded), uint64(high(int)))
  var size = uint64(RecordHeaderBytes)
  if size > maximum: return RecordResult[int](status: RecordError.LimitExceeded)
  var bytes = 0'u64
  for record in batch.records:
    if record.kind notin {TrieRecordKind.Leaf, TrieRecordKind.Branch}:
      return RecordResult[int](status: RecordError.NonCanonical) # Reject unknown raw enum tags.
    if zero(record.digest): return RecordResult[int](status: RecordError.NonCanonical)
    let fixed = if record.kind == TrieRecordKind.Leaf: 72'u64 else: 97'u64
    if fixed > maximum-size: return RecordResult[int](status: RecordError.LimitExceeded)
    size += fixed
    if record.kind == TrieRecordKind.Leaf:
      if not zero(record.left) or not zero(record.right):
        return RecordResult[int](status: RecordError.NonCanonical) # Leaf records carry no physical edges.
      let payload = uint64(record.payload.len)
      let bound = min(uint64(limits.records.valueBytes), uint64(limits.trie.totalValueBytes))
      if payload > uint64(limits.trie.perValue) or payload > bound-bytes or payload > maximum-size:
        return RecordResult[int](status: RecordError.LimitExceeded)
      bytes += payload
      size += payload
    else:
      if record.payload.len != 0 or array[31, byte](record.key) != default(array[31, byte]) or
          (zero(record.left) and zero(record.right)):
        return RecordResult[int](status: RecordError.NonCanonical) # Empty branches and spare fields have no canonical meaning.
  RecordResult[int](status: RecordError.None, completed: int(size))

proc validateTrieExport*(batch: TrieExport, limits: RecordLimits): RecordError =
  ## Verify each physical node commitment; graph completeness/routing require the repository layer.
  let checked = extent(batch, limits)
  if checked.error != RecordError.None: return checked.error
  var identities = newSeq[StateNodeHash](batch.records.len)
  for i, record in batch.records: identities[i] = record.digest # Fixed scratch has been preflighted.
  identities.sort(compareHash)
  for i in 1..<identities.len:
    if compareHash(identities[i-1], identities[i]) == 0: return RecordError.DuplicateNode
  for record in batch.records:
    var encoded = default(EncodedStateNode)
    if record.kind == TrieRecordKind.Leaf:
      let leaf = encodeStateLeaf(record.key, record.payload, limits.trie.perValue)
      if leaf.error != StateLayoutError.None: return RecordError.BackendFailure
      encoded = leaf.value
    else:
      encoded = encodeStateBranch(record.left, record.right) # Use full physical children to produce exact JAM B bytes.
    let hashed = hashStateNode(encoded)
    if hashed.error != StateLayoutError.None: return RecordError.BackendFailure
    if array[32, byte](hashed.value) != array[32, byte](
        record.digest): return RecordError.HashMismatch
  RecordError.None

proc putNumber(output: var seq[byte], offset: int, number: uint64) =
  ## Callers prove eight output bytes before fixed little-endian encoding.
  for i in 0..<8: output[offset+i] = byte((number shr (8*i)) and 255)
func number(input: openArray[byte], offset: int): uint64 =
  ## Callers prove eight input bytes before decoding the complete fixed-width count.
  result = 0
  for i in 0..<8: result = result or (uint64(input[offset+i]) shl (8*i))
proc putHash(output: var seq[byte], offset: int, hash: array[32, byte]) =
  ## Copy one full physical identity after extent preflight.
  for i in 0..<32: output[offset+i] = hash[i]
func readHash(input: openArray[byte], offset: int): array[32, byte] =
  ## Decode copied identity bytes from a caller-proved fixed extent.
  result = default(array[32, byte])
  for i in 0..<32: result[i] = input[offset+i]

proc encodeTrieExport*(batch: TrieExport, limits: RecordLimits): RecordResult[seq[byte]] =
  ## Serialize only a locally verified batch; the borrowed source remains stable throughout.
  let checked = extent(batch, limits)
  if checked.error != RecordError.None: return RecordResult[seq[byte]](status: checked.error)
  let validated = validateTrieExport(batch, limits)
  if validated != RecordError.None: return RecordResult[seq[byte]](status: validated)
  var output = newSeq[byte](checked.value)
  for i, character in RecordMagic: output[i] = byte(character) # Exact version has no fallback.
  var offset = RecordMagic.len
  putHash(output, offset, array[32, byte](batch.base)); offset += 32
  putHash(output, offset, array[32, byte](batch.root)); offset += 32
  putNumber(output, offset, batch.entries); offset += 8
  putNumber(output, offset, batch.nodes); offset += 8
  putNumber(output, offset, uint64(batch.records.len)); offset += 8
  for record in batch.records:
    output[offset] = byte(ord(record.kind)); inc offset # Tags have exact one-byte widths.
    putHash(output, offset, array[32, byte](record.digest)); offset += 32
    if record.kind == TrieRecordKind.Leaf:
      let key = array[31, byte](record.key)
      for i in 0..<31: output[offset+i] = key[i]
      offset += 31
      putNumber(output, offset, uint64(record.payload.len)); offset += 8
      for octet in record.payload:
        output[offset] = octet
        inc offset # Preflight included the complete raw value, even for hashed protocol leaves.
    else:
      putHash(output, offset, array[32, byte](record.left)); offset += 32
      putHash(output, offset, array[32, byte](record.right)); offset += 32
  RecordResult[seq[byte]](status: RecordError.None, completed: output)

proc decodeTrieExport*(input: openArray[byte], limits: RecordLimits): RecordResult[TrieExport] =
  ## Bound and scan the entire borrowed input before allocating records or invoking crypto.
  if uint64(input.len) > uint64(limits.encoded): return RecordResult[TrieExport](
      status: RecordError.LimitExceeded)
  if input.len < RecordHeaderBytes: return RecordResult[TrieExport](
      status: RecordError.InvalidFormat)
  for i, character in RecordMagic:
    if input[i] != byte(character): return RecordResult[TrieExport](
        status: RecordError.InvalidFormat)
  var offset = RecordMagic.len
  var batch = TrieExport(base: StateRoot(readHash(input, offset)),
    root: StateRoot(readHash(input, offset+32)), entries: number(input, offset+64),
    nodes: number(input, offset+72))
  let count = number(input, offset+80)
  offset = RecordHeaderBytes
  if count > uint64((input.len-offset) div 72): return RecordResult[TrieExport](
      status: RecordError.InvalidFormat)
  let checked = metadata(batch, count, limits)
  if checked != RecordError.None: return RecordResult[TrieExport](status: checked)
  var bytes = 0'u64
  for i in 0..<int(count):
    if input.len-offset < 33: return RecordResult[TrieExport](status: RecordError.InvalidFormat)
    let tag = input[offset]
    offset += 33 # Both record forms begin with a tag and complete digest.
    if tag == 0:
      if input.len-offset < 39: return RecordResult[TrieExport](status: RecordError.InvalidFormat)
      let size = number(input, offset+31)
      offset += 39
      if size > uint64(input.len-offset): return RecordResult[TrieExport](
          status: RecordError.InvalidFormat)
      let bound = min(uint64(limits.records.valueBytes), uint64(limits.trie.totalValueBytes))
      if size > uint64(limits.trie.perValue) or size > bound-bytes:
        return RecordResult[TrieExport](status: RecordError.LimitExceeded)
      bytes += size
      offset += int(size) # Remaining-input proof makes narrowing and addition safe.
    elif tag == 1:
      if input.len-offset < 64: return RecordResult[TrieExport](status: RecordError.InvalidFormat)
      offset += 64 # Physical branches retain both complete child identities.
    else:
      return RecordResult[TrieExport](status: RecordError.NonCanonical)
  if offset != input.len: return RecordResult[TrieExport](status: RecordError.InvalidFormat)
  batch.records = newSeq[TrieRecord](int(count))
  offset = RecordHeaderBytes
  for i in 0..<int(count):
    let tag = input[offset]
    let digest = StateNodeHash(readHash(input, offset+1))
    offset += 33
    if tag == 0:
      var key = default(array[31, byte])
      for j in 0..<31: key[j] = input[offset+j] # First pass proved this entire fixed prefix.
      let size = int(number(input, offset+31))
      offset += 39
      var payload = newSeq[byte](size)
      for j in 0..<size: payload[j] = input[offset+j]
      offset += size
      batch.records[i] = TrieRecord(kind: TrieRecordKind.Leaf, digest: digest, key: StateKey(key),
          payload: payload)
    else:
      batch.records[i] = TrieRecord(kind: TrieRecordKind.Branch, digest: digest,
        left: StateNodeHash(readHash(input, offset)), right: StateNodeHash(readHash(input, offset+32)))
      offset += 64
  let validated = validateTrieExport(batch, limits)
  if validated != RecordError.None: return RecordResult[TrieExport](status: validated)
  RecordResult[TrieExport](status: RecordError.None, completed: batch)
