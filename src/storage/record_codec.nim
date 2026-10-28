# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict versioned physical trie-record batches; validates shape/budgets before node hashes.
## Record validation is local integrity, not complete graph verification or chain authority.

import std/algorithm
import std/assertions
import ./node_records as storage_node_records
import ../codec/state_trie as codec_state_trie
import ../codec/state_layout as codec_state_layout
import ../codec/bounded as codec_bounded

const
  CollectionMagic = "RAGNAROK-RECORDS-V1\n"
  CollectionHeaderBytes = CollectionMagic.len+8
  RecordMagic = "RAGNAROK-TRIE-V1\n"
  RecordHeaderBytes = RecordMagic.len + 88
  TrieExportHeaderBytes* = RecordHeaderBytes ## Minimum exact body extent for one local physical batch.

type
  RecordLimits* = object ## Separate complete target metadata, detached payloads and encoded extents.
    trie*: StateTrieLimits
    records*: TrieExportLimits
    encoded*: ByteLimit
  RecordError* {.pure.} = enum ## No default/refused operation exposes bytes or records.
    Uninitialized, None, InvalidFormat, NonCanonical, LimitExceeded, DuplicateNode,
    HashMismatch, BackendFailure, ConsumerRefused
  RecordBatchInfo* = object ## Exact target-bearing delivery summary; fields grant no graph or mutation authority.
    base*, root*: StateRoot
    entries*, nodes*, records*, valueBytes*: uint64
  RecordCollectionInfo* = object ## Successful delivery summary; no retained records or graph authority.
    records*, valueBytes*: uint64
  RecordPreparation*[T] = proc(state: var T, info: RecordCollectionInfo) {.nimcall.}
    ## Required nonnil capacity preparation after structural/duplicate preflight; conveys no integrity authority.
  RecordConsumer*[T] = proc(state: var T, record: var TrieRecord): bool {.nimcall.}
    ## Required nonnil synchronous owner transfer; false stops delivery with ConsumerRefused.
  RecordDeliveryCallbacks[T] = object ## Fixed callback fields prevent generic call-site name rebinding.
    before: RecordPreparation[T]
    record: RecordConsumer[T]
  RecordScan = object ## Private exact-input structural preflight; retains no borrowed byte address.
    batch: TrieExport
    count, header: int
    valueBytes: uint64
    firstPrefix, lastPrefix: uint64
  PrefixMode {.pure.} = enum ## Default plans conservatively check all full identities; only proved distinct prefixes omit them.
    All, Unique, Selected
  PrefixPlan = object ## Private repeated-prefix inventory bounds selected full-width checks without changing record integrity.
    mode: PrefixMode
    prefixes: seq[uint64]
    records: int
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
proc takeValue*[T](outcome: var RecordResult[T]): T {.inline,
    requires: outcome.status == RecordError.None.} =
  ## Transfer one validated transport owner; the consumed result exposes only Uninitialized afterward.
  result = move(outcome.completed)
  outcome = RecordResult[T](status: RecordError.Uninitialized)
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
proc payloadBudget(limits: RecordLimits, collection: bool): uint64 =
  ## Single-root transports retain complete-map ceilings; multi-root collections use the physical union ceiling.
  if not collection:
    min(uint64(limits.records.valueBytes), uint64(limits.trie.totalValueBytes))
  else:
    uint64(limits.records.valueBytes)
proc checkMetadata(batch: TrieExport, count: uint64, limits: RecordLimits,
    collection: bool): RecordError =
  ## Count-only collections never manufacture target-root claims to reuse physical validation.
  if not collection:
    metadata(batch, count, limits)
  else:
    if count > uint64(limits.records.records) or count > uint64(high(int) div sizeof(TrieRecord)):
      return RecordError.LimitExceeded
    RecordError.None
proc extent(batch: TrieExport, records: openArray[TrieRecord], limits: RecordLimits,
    collection: bool): RecordResult[int] =
  ## Validate all canonical fields and arithmetic before allocating hash/sort/output buffers.
  let checked = checkMetadata(batch, uint64(records.len), limits, collection)
  if checked != RecordError.None: return RecordResult[int](status: checked)
  let maximum = min(uint64(limits.encoded), uint64(high(int)))
  var size = uint64(RecordHeaderBytes)
  if collection: size = uint64(CollectionHeaderBytes)
  if size > maximum: return RecordResult[int](status: RecordError.LimitExceeded)
  var bytes = 0'u64
  for record in records:
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
      let bound = payloadBudget(limits, collection)
      if payload > uint64(limits.trie.perValue) or payload > bound-bytes or payload > maximum-size:
        return RecordResult[int](status: RecordError.LimitExceeded)
      bytes += payload
      size += payload
    else:
      if record.payload.len != 0 or array[31, byte](record.key) != default(array[31, byte]) or
          (zero(record.left) and zero(record.right)):
        return RecordResult[int](status: RecordError.NonCanonical) # Empty branches and spare fields have no canonical meaning.
  RecordResult[int](status: RecordError.None, completed: int(size))

proc recordIntegrity(record: TrieRecord, limits: RecordLimits): RecordError =
  ## Hash exactly one structurally admitted record; raw callers still require independent shape/budget preflight.
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

func hashPrefix(digest: StateNodeHash): uint64 =
  ## Pack all first-eight physical bytes bijectively; this scratch key never substitutes for a full address.
  let bytes = array[32, byte](digest)
  result = 0
  for index in 0..<8: result = result or (uint64(bytes[index]) shl (index*8))

proc planPrefixes(prefixes: var seq[uint64]): PrefixPlan =
  ## Keep exact full comparisons only for sparse collision groups; dense collisions use the original whole check.
  prefixes.sort()
  let count = prefixes.len
  var first = 0
  var groups = 0
  var records = 0
  while first < count:
    let prefix = prefixes[first]
    var stop = first+1
    while stop < count and prefixes[stop] == prefix: inc stop # Sorted equality defines one complete collision group.
    if stop-first > 1:
      prefixes[groups] = prefix # Compact only behind unread input; group order stays sorted and unique.
      inc groups
      records += stop-first # Disjoint groups bound the accumulated count by the already checked record extent.
    first = stop
  if groups == 0: return PrefixPlan(mode: PrefixMode.Unique)
  if records > count div 4:
    return PrefixPlan(mode: PrefixMode.All) # Retire compact scratch before the dense full-width fallback.
  prefixes.setLen(groups)
  PrefixPlan(mode: PrefixMode.Selected, prefixes: move(prefixes), records: records)

func containsPrefix(plan: PrefixPlan, prefix: uint64): bool =
  ## Selected collisions retain complete equality groups; binary membership cannot omit an equal full address.
  var first = 0
  var stop = plan.prefixes.len
  while first < stop:
    let middle = first+(stop-first) div 2
    if plan.prefixes[middle] < prefix: first = middle+1
    elif plan.prefixes[middle] > prefix: stop = middle
    else: return true
  false

proc recordPrefixPlan(records: openArray[TrieRecord]): PrefixPlan =
  ## Endpoint collisions need no compact allocation; other collisions are narrowed only by an exact whole-prefix scan.
  if records.len < 2: return PrefixPlan(mode: PrefixMode.Unique)
  if hashPrefix(records[0].digest) == hashPrefix(records[records.len-1].digest):
    return PrefixPlan(mode: PrefixMode.All) # This is inconclusive, never an early duplicate error.
  var prefixes = newSeq[uint64](records.len)
  for index, record in records: prefixes[index] = hashPrefix(record.digest)
  planPrefixes(prefixes)

proc duplicateIdentities(identities: var seq[StateNodeHash]): RecordError =
  ## Only complete physical address equality can reject a duplicate; no prefix supplies identity authority.
  identities.sort(compareHash)
  for index in 1..<identities.len:
    if compareHash(identities[index-1], identities[index]) == 0: return RecordError.DuplicateNode
  RecordError.None

proc validateRecords(batch: TrieExport, records: openArray[TrieRecord], limits: RecordLimits,
    collection: bool, ordered = false): RecordError =
  ## Verify each physical node commitment; only the private decoder's strict first pass can supply order.
  let checked = extent(batch, records, limits, collection)
  if checked.error != RecordError.None: return checked.error
  if not ordered:
    let plan = recordPrefixPlan(records)
    if plan.mode != PrefixMode.Unique:
      # Other records have prefixes distinct from every collision group and therefore cannot duplicate any identity.
      let count = if plan.mode == PrefixMode.All: records.len else: plan.records
      var identities = newSeq[StateNodeHash](count)
      var next = 0
      for record in records:
        if plan.mode == PrefixMode.All or plan.containsPrefix(hashPrefix(record.digest)):
          identities[next] = record.digest
          inc next
      assert next == identities.len # Whole-prefix counting and stable raw input must select the same complete groups.
      let duplicate = duplicateIdentities(identities)
      if duplicate != RecordError.None: return duplicate
  for record in records:
    let checked = recordIntegrity(record, limits)
    if checked != RecordError.None: return checked # Preserve the first exact local integrity refusal.
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

proc encodeRecords(batch: TrieExport, records: openArray[TrieRecord], limits: RecordLimits,
    collection: bool, prefixBytes = 0'u64, suffixBytes = 0'u64,
    outputLimit = ByteLimit(high(uint64))): RecordResult[seq[byte]] =
  ## Serialize only a locally verified batch; the borrowed source remains stable throughout.
  let checked = extent(batch, records, limits, collection)
  if checked.error != RecordError.None: return RecordResult[seq[byte]](status: checked.error)
  let maximum = min(uint64(outputLimit), uint64(high(int)))
  if prefixBytes > maximum or suffixBytes > maximum-prefixBytes:
    return RecordResult[seq[byte]](status: RecordError.LimitExceeded)
  let reserved = prefixBytes+suffixBytes
  if uint64(checked.value) > maximum-reserved:
    return RecordResult[seq[byte]](status: RecordError.LimitExceeded)
  let validated = validateRecords(batch, records, limits, collection)
  if validated != RecordError.None: return RecordResult[seq[byte]](status: validated)
  var output = newSeq[byte](int(reserved+uint64(checked.value)))
  var magic = RecordMagic
  if collection: magic = CollectionMagic
  let prefix = int(prefixBytes)
  for i, character in magic: output[prefix+i] = byte(character) # Exact transport domain has no fallback.
  var offset = prefix+magic.len
  if not collection:
    putHash(output, offset, array[32, byte](batch.base)); offset += 32
    putHash(output, offset, array[32, byte](batch.root)); offset += 32
    putNumber(output, offset, batch.entries); offset += 8
    putNumber(output, offset, batch.nodes); offset += 8
  putNumber(output, offset, uint64(records.len)); offset += 8
  for record in records:
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
  assert offset == output.len-int(suffixBytes) # Strict bounded writer ends exactly at the reserved trailer.
  RecordResult[seq[byte]](status: RecordError.None, completed: output)

proc scanRecords(input: openArray[byte], limits: RecordLimits, collection: bool,
    ordered: bool): RecordResult[RecordScan] =
  ## Prove every serialized extent, count, canonical field and aggregate limit before allocation or crypto.
  if uint64(input.len) > uint64(limits.encoded): return RecordResult[RecordScan](
      status: RecordError.LimitExceeded)
  var header = RecordHeaderBytes
  var magic = RecordMagic
  if collection:
    header = CollectionHeaderBytes
    magic = CollectionMagic
  if input.len < header: return RecordResult[RecordScan](
      status: RecordError.InvalidFormat)
  for i, character in magic:
    if input[i] != byte(character): return RecordResult[RecordScan](
        status: RecordError.InvalidFormat)
  var offset = magic.len
  var batch = default(TrieExport)
  if not collection:
    batch.base = StateRoot(readHash(input, offset))
    batch.root = StateRoot(readHash(input, offset+32))
    batch.entries = number(input, offset+64)
    batch.nodes = number(input, offset+72)
    offset += 80 # Only target-bearing batches carry complete-root claims.
  let count = number(input, offset)
  offset = header
  if count > uint64((input.len-offset) div 72): return RecordResult[RecordScan](
      status: RecordError.InvalidFormat)
  let checked = checkMetadata(batch, count, limits, collection)
  if checked != RecordError.None: return RecordResult[RecordScan](status: checked)
  var bytes = 0'u64
  var previous = default(StateNodeHash)
  var firstPrefix = 0'u64
  var lastPrefix = 0'u64
  for i in 0..<int(count):
    if input.len-offset < 33: return RecordResult[RecordScan](status: RecordError.InvalidFormat)
    if zero(StateNodeHash(readHash(input, offset+1))):
      return RecordResult[RecordScan](status: RecordError.NonCanonical) # Reserved empty addresses cannot own a physical record.
    if not ordered:
      if i == 0: firstPrefix = number(input, offset+1) # Existing complete digest bounds prove each endpoint read.
      if i == int(count)-1: lastPrefix = number(input, offset+1)
    if ordered:
      # Prove canonical unique physical order from borrowed bytes before allocating any records or hash scratch.
      let digest = StateNodeHash(readHash(input, offset+1))
      if i > 0:
        let order = compareHash(previous, digest)
        if order == 0: return RecordResult[RecordScan](status: RecordError.DuplicateNode)
        if order > 0: return RecordResult[RecordScan](status: RecordError.NonCanonical)
      previous = digest
    let tag = input[offset]
    offset += 33 # Both record forms begin with a tag and complete digest.
    if tag == 0:
      if input.len-offset < 39: return RecordResult[RecordScan](status: RecordError.InvalidFormat)
      let size = number(input, offset+31)
      offset += 39
      if size > uint64(input.len-offset): return RecordResult[RecordScan](
          status: RecordError.InvalidFormat)
      let bound = payloadBudget(limits, collection)
      if size > uint64(limits.trie.perValue) or size > bound-bytes:
        return RecordResult[RecordScan](status: RecordError.LimitExceeded)
      bytes += size
      offset += int(size) # Remaining-input proof makes narrowing and addition safe.
    elif tag == 1:
      if input.len-offset < 64: return RecordResult[RecordScan](status: RecordError.InvalidFormat)
      if zero(StateNodeHash(readHash(input, offset))) and
          zero(StateNodeHash(readHash(input, offset+32))):
        return RecordResult[RecordScan](status: RecordError.NonCanonical) # No raw record allocation is needed to reject an empty branch.
      offset += 64 # Physical branches retain both complete child identities.
    else:
      return RecordResult[RecordScan](status: RecordError.NonCanonical)
  if offset != input.len: return RecordResult[RecordScan](status: RecordError.InvalidFormat)
  RecordResult[RecordScan](status: RecordError.None, completed: RecordScan(
    batch: batch, count: int(count), header: header, valueBytes: bytes,
    firstPrefix: firstPrefix, lastPrefix: lastPrefix))

proc readRecord(input: openArray[byte], offset: var int): TrieRecord =
  ## Decode one owned transport only after whole-input scan; the borrowed input stays stable during this call.
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
    result = TrieRecord(kind: TrieRecordKind.Leaf, digest: digest, key: StateKey(key),
        payload: payload)
  else:
    result = TrieRecord(kind: TrieRecordKind.Branch, digest: digest,
      left: StateNodeHash(readHash(input, offset)), right: StateNodeHash(readHash(input, offset+32)))
    offset += 64

proc decodeRecords(input: openArray[byte], limits: RecordLimits, collection: bool,
    ordered = false): RecordResult[TrieExport] =
  ## Detached decoding shares the exact structural preflight with bounded admission consumers.
  let scanned = scanRecords(input, limits, collection, ordered)
  if scanned.error != RecordError.None:
    return RecordResult[TrieExport](status: scanned.error)
  let shape = scanned.value
  var batch = shape.batch
  let count = shape.count
  let header = shape.header
  var offset = header
  batch.records = newSeq[TrieRecord](int(count))
  offset = header
  for i in 0..<int(count):
    batch.records[i] = readRecord(input, offset) # Each descriptor receives one independent payload owner.
  let validated = validateRecords(batch, batch.records, limits, collection, ordered)
  if validated != RecordError.None: return RecordResult[TrieExport](status: validated)
  RecordResult[TrieExport](status: RecordError.None, completed: batch)


proc validateTrieExport*(batch: TrieExport, limits: RecordLimits): RecordError =
  ## Preserve exact single-target metadata, record and complete-map byte ceilings.
  validateRecords(batch, batch.records, limits, false)
proc encodeTrieExport*(batch: TrieExport, limits: RecordLimits): RecordResult[seq[byte]] =
  ## Preserve the existing single-target representation byte for byte.
  encodeRecords(batch, batch.records, limits, false)
proc encodeFramedTrieExport*(batch: TrieExport, limits: RecordLimits,
    prefixBytes, suffixBytes: uint64, outputLimit: ByteLimit): RecordResult[seq[byte]] =
  ## Strictly validate borrowed mutable records, then encode into one owned buffer with zero-filled reservations.
  ## Requested nonnegative extents and the independent whole-output ceiling are proved before allocation/hashing.
  ## Body policy, duplicate rejection and every local hash remain mandatory; reservations grant no graph authority.
  encodeRecords(batch, batch.records, limits, false, prefixBytes, suffixBytes, outputLimit)

proc decodeTrieExport*(input: openArray[byte], limits: RecordLimits): RecordResult[TrieExport] =
  ## Decode only the existing target-bearing domain with no collection fallback.
  decodeRecords(input, limits, false)
proc validateRecordCollection*(collection: RecordCollection, limits: RecordLimits): RecordError =
  ## Validate canonical unique physical records under an explicit aggregate union budget.
  validateRecords(default(TrieExport), collection.records, limits, true)
proc measureRecordCollection*(collection: RecordCollection, limits: RecordLimits): RecordResult[int] =
  ## Preflight canonical shape and exact encoded extent without hashing or allocating record/output storage.
  extent(default(TrieExport), collection.records, limits, true)
proc encodeRecordCollection*(collection: RecordCollection, limits: RecordLimits): RecordResult[seq[byte]] =
  ## Borrow records directly, preflighting before any transport/output allocation.
  encodeRecords(default(TrieExport), collection.records, limits, true)
proc decodeRecordCollection*(input: openArray[byte], limits: RecordLimits): RecordResult[
    RecordCollection] =
  ## Preflight every extent before allocation/hashing; complete graphs require separate admission.
  var decoded = decodeRecords(input, limits, true)
  if decoded.error != RecordError.None: return RecordResult[RecordCollection](status: decoded.error)
  var batch = decoded.takeValue # The collection owns the decoder's exact validated record buffer.
  RecordResult[RecordCollection](status: RecordError.None,
    completed: RecordCollection(records: move(batch.records)))

proc decodeOrderedRecordCollection*(input: openArray[byte], limits: RecordLimits): RecordResult[
    RecordCollection] =
  ## Require strict physical-address order before allocation while independently hashing every record once.
  ## This decoder grants no complete-graph authority and accepts no validation bypass flag.
  var decoded = decodeRecords(input, limits, true, true)
  if decoded.error != RecordError.None: return RecordResult[RecordCollection](status: decoded.error)
  var batch = decoded.takeValue # The collection owns the decoder's exact validated record buffer.
  RecordResult[RecordCollection](status: RecordError.None,
    completed: RecordCollection(records: move(batch.records)))

proc inputPrefixPlan(input: openArray[byte], shape: RecordScan): PrefixPlan =
  ## Bounded scan endpoints cheaply reject an inconclusive compact plan, without authorizing any identity or integrity.
  if shape.count < 2: return PrefixPlan(mode: PrefixMode.Unique)
  if shape.firstPrefix == shape.lastPrefix: return PrefixPlan(mode: PrefixMode.All)
  var prefixes = newSeq[uint64](shape.count)
  var offset = shape.header
  for index in 0..<shape.count:
    # Whole-input preflight proved complete fields and widths; borrowed bytes remain stable through this call.
    prefixes[index] = number(input, offset+1)
    let tag = input[offset]
    offset += 33
    if tag == 0:
      let size = int(number(input, offset+31))
      offset += 39
      offset += size
    else:
      offset += 64
  planPrefixes(prefixes)

proc uniqueInputRecords(input: openArray[byte], shape: RecordScan): RecordError =
  ## Exact prefix groups bound full-width scratch; shape-only inspection still conveys no local integrity/graph authority.
  let plan = inputPrefixPlan(input, shape)
  if plan.mode == PrefixMode.Unique: return RecordError.None
  let count = if plan.mode == PrefixMode.All: shape.count else: plan.records
  var identities = newSeq[StateNodeHash](count)
  var next = 0
  var offset = shape.header
  for index in 0..<shape.count:
    # Dense/endpoint fallback checks every address; sparse groups include every possible full-width duplicate.
    if plan.mode == PrefixMode.All or plan.containsPrefix(number(input, offset+1)):
      identities[next] = StateNodeHash(readHash(input, offset+1))
      inc next
    let tag = input[offset]
    offset += 33
    if tag == 0:
      let size = int(number(input, offset+31))
      offset += 39
      offset += size
    else:
      offset += 64
  assert next == identities.len # Validated stable input and complete prefix groups must agree exactly.
  duplicateIdentities(identities)

proc ignorePreparation[T](state: var T, info: RecordCollectionInfo) =
  ## Existing delivery calls need no capacity callback and retain their original observable behavior.
  discard

proc deliverRecords[T](input: openArray[byte], limits: RecordLimits, collection, ordered: bool,
    state: var T, consume: RecordConsumer[T], prepare: RecordPreparation[T]): RecordResult[RecordScan] =
  ## Local structural/duplicate checks precede all crypto and callbacks; each delivered owner stays detached.
  let scanned = scanRecords(input, limits, collection, ordered)
  if scanned.error != RecordError.None: return RecordResult[RecordScan](status: scanned.error)
  let shape = scanned.value
  if not ordered:
    let unique = uniqueInputRecords(input, shape)
    if unique != RecordError.None: return RecordResult[RecordScan](status: unique)
  let callbacks = RecordDeliveryCallbacks[T](before: prepare, record: consume)
  callbacks.before(state, RecordCollectionInfo(records: uint64(shape.count),
      valueBytes: shape.valueBytes))
  var offset = shape.header
  for index in 0..<shape.count:
    # Stable input preserves the complete scan's bounds through each synchronous callback.
    var record = readRecord(input, offset)
    let checked = recordIntegrity(record, limits)
    if checked != RecordError.None: return RecordResult[RecordScan](status: checked)
    if not callbacks.record(state, record): return RecordResult[RecordScan](
        status: RecordError.ConsumerRefused)
  RecordResult[RecordScan](status: RecordError.None, completed: shape)

proc visitOrderedRecordCollection*[T](input: openArray[byte], limits: RecordLimits,
    state: var T, consume: RecordConsumer[T]): RecordResult[RecordCollectionInfo] =
  ## Preflight stable borrowed input, then deliver one owned locally hashed record at a time.
  ## Visited prefixes remain provisional until success; callbacks must stage privately for transactional use.
  ## The callback may move the payload; no borrow into input or the local record may escape.
  let prepare: RecordPreparation[T] = ignorePreparation[T]
  let delivered = deliverRecords(input, limits, true, true, state, consume, prepare)
  if delivered.error != RecordError.None:
    return RecordResult[RecordCollectionInfo](status: delivered.error)
  let shape = delivered.value
  RecordResult[RecordCollectionInfo](status: RecordError.None,
    completed: RecordCollectionInfo(records: uint64(shape.count), valueBytes: shape.valueBytes))

proc visitTrieExport*[T](input: openArray[byte], limits: RecordLimits,
    state: var T, consume: RecordConsumer[T]): RecordResult[RecordBatchInfo] =
  ## Deliver target-bearing records in serialized order after whole-input shape/budget/duplicate preflight.
  ## Stable bytes are borrowed synchronously; callbacks own one record and must treat prefixes as provisional.
  let prepare: RecordPreparation[T] = ignorePreparation[T]
  let delivered = deliverRecords(input, limits, false, false, state, consume, prepare)
  if delivered.error != RecordError.None: return RecordResult[RecordBatchInfo](
      status: delivered.error)
  let shape = delivered.value
  RecordResult[RecordBatchInfo](status: RecordError.None, completed: RecordBatchInfo(
    base: shape.batch.base, root: shape.batch.root, entries: shape.batch.entries,
    nodes: shape.batch.nodes, records: uint64(shape.count), valueBytes: shape.valueBytes))

proc inspectOrderedRecordCollection*(input: openArray[byte], limits: RecordLimits): RecordResult[
    RecordCollectionInfo] =
  ## Inspect all canonical extents/order and budgets without crypto, descriptors, payloads or graph authority.
  ## The scalar summary can size private staging; actual delivery must independently validate the stable input.
  let scanned = scanRecords(input, limits, true, true)
  if scanned.error != RecordError.None:
    return RecordResult[RecordCollectionInfo](status: scanned.error)
  let shape = scanned.value
  RecordResult[RecordCollectionInfo](status: RecordError.None,
    completed: RecordCollectionInfo(records: uint64(shape.count), valueBytes: shape.valueBytes))

proc inspectTrieExport*(input: openArray[byte], limits: RecordLimits): RecordResult[
    RecordBatchInfo] =
  ## Inspect target metadata and exact extents/duplicates using only bounded address scratch, without crypto.
  ## This summary conveys no integrity or graph authority and never permits a delivery/admission bypass.
  let scanned = scanRecords(input, limits, false, false)
  if scanned.error != RecordError.None: return RecordResult[RecordBatchInfo](status: scanned.error)
  let shape = scanned.value
  let unique = uniqueInputRecords(input, shape)
  if unique != RecordError.None: return RecordResult[RecordBatchInfo](status: unique)
  RecordResult[RecordBatchInfo](status: RecordError.None, completed: RecordBatchInfo(
    base: shape.batch.base, root: shape.batch.root, entries: shape.batch.entries,
    nodes: shape.batch.nodes, records: uint64(shape.count), valueBytes: shape.valueBytes))

proc visitOrderedRecordCollection*[T](input: openArray[byte], limits: RecordLimits,
    state: var T, prepare: RecordPreparation[T], consume: RecordConsumer[T]): RecordResult[
    RecordCollectionInfo] =
  ## Reserve exact private capacity once after structural preflight and before any local integrity hashing.
  ## Preparation and visited prefixes remain provisional; stable input and independent graph admission are required.
  let delivered = deliverRecords(input, limits, true, true, state, consume, prepare)
  if delivered.error != RecordError.None:
    return RecordResult[RecordCollectionInfo](status: delivered.error)
  let shape = delivered.value
  RecordResult[RecordCollectionInfo](status: RecordError.None,
    completed: RecordCollectionInfo(records: uint64(shape.count), valueBytes: shape.valueBytes))

proc visitTrieExport*[T](input: openArray[byte], limits: RecordLimits,
    state: var T, prepare: RecordPreparation[T], consume: RecordConsumer[T]): RecordResult[
        RecordBatchInfo] =
  ## Preflight unordered extents/duplicates once, prepare private capacity, then hash and transfer one record at a time.
  ## Metadata is not integrity authority; callers must stage every preparation/record effect until complete success.
  let delivered = deliverRecords(input, limits, false, false, state, consume, prepare)
  if delivered.error != RecordError.None: return RecordResult[RecordBatchInfo](
      status: delivered.error)
  let shape = delivered.value
  RecordResult[RecordBatchInfo](status: RecordError.None, completed: RecordBatchInfo(
    base: shape.batch.base, root: shape.batch.root, entries: shape.batch.entries,
    nodes: shape.batch.nodes, records: uint64(shape.count), valueBytes: shape.valueBytes))
