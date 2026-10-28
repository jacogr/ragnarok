# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact managed snapshot bytes bind a complete retained root union and context to chain/schema/generation.
## Encoding consumes opaque validated selections; decoding admits every complete graph before success.
import std/algorithm
import std/assertions
import ./node_repository as storage_node_repository
import ./node_records as storage_node_records
import ./record_codec as storage_record_codec
import ./database_identity as storage_database_identity
import ../codec/bounded as codec_bounded
import ../codec/state_trie as codec_state_trie
import ../crypto/primitives as crypto_primitives
const
  Magic = "RAGNAROK-SNAPSHOT-V1\n"
  HeaderBytes = Magic.len+113
  Overhead = HeaderBytes+32
type
  SnapshotLimits* = object ## Snapshot extent and root/context limits are separate from per-commit batches.
    repository*: RepositoryLimits
    roots*: ElementLimit
    context*: ByteLimit
    bytes*: ByteLimit
  SnapshotError* {.pure.} = enum ## Default/refused snapshots expose no candidate owner or bytes.
    Uninitialized, None, InvalidFormat, WrongIdentity, LimitExceeded, ChecksumMismatch,
    PolicyMismatch, RecordFailure, RepositoryFailure, BackendFailure
  SnapshotEncoding* = object ## Detached serialized output and its bound prefix checksum.
    bytes*: seq[byte]
    checksum*: StorageChecksum
  RepositorySnapshot* = object ## Successfully admitted independent repository plus detached selected context.
    repository*: NodeRepository
    context*: seq[byte]
    checksum*: StorageChecksum
  SnapshotResult*[T] = object ## Private result alternatives expose only successful complete payloads.
    case status: SnapshotError
    of None: completed: T
    of RecordFailure: recordReason: RecordError
    of RepositoryFailure: repositoryReason: RepositoryError
    else: discard
func error*[T](outcome: SnapshotResult[T]): SnapshotError =
  ## Observe only the selected codec reason.
  outcome.status
func value*[T](outcome: SnapshotResult[T]): T {.inline, requires: outcome.status ==
    SnapshotError.None.} =
  ## Extract bytes or restored owners only after complete admission.
  outcome.completed
proc takeValue*[T](outcome: var SnapshotResult[T]): T {.inline,
    requires: outcome.status == SnapshotError.None.} =
  ## Transfer admitted bytes/owners once; the consumed result retains no success payload or authority.
  result = move(outcome.completed)
  outcome = SnapshotResult[T](status: SnapshotError.Uninitialized)
func recordError*[T](outcome: SnapshotResult[T]): RecordError {.requires: outcome.status ==
    SnapshotError.RecordFailure.} =
  ## Preserve a selected physical record refusal without returning decoded prefixes.
  outcome.recordReason
func repositoryError*[T](outcome: SnapshotResult[T]): RepositoryError {.requires: outcome.status ==
    SnapshotError.RepositoryFailure.} =
  ## Inspect only a selected complete-graph failure.
  outcome.repositoryReason
proc putNumber(output: var seq[byte], offset: int, number: uint64) =
  ## Exact output preflight proves each little-endian E8 field.
  for index in 0..<8: output[offset+index] = byte((number shr (8*index)) and 255)
func number(input: openArray[byte], offset: int): uint64 =
  ## Fixed header/extent checks precede every read.
  result = 0
  for index in 0..<8: result = result or (uint64(input[offset+index]) shl (8*index))
proc putHash(output: var seq[byte], offset: int, hash: array[32, byte]) =
  ## Copy a fixed identity only inside the preflighted output extent.
  for index in 0..<32: output[offset+index] = hash[index]
func readHash(input: openArray[byte], offset: int): array[32, byte] =
  ## Copy one proved complete scalar identity.
  result = default(array[32, byte])
  for index in 0..<32: result[index] = input[offset+index]
proc physicalLimits(limits: SnapshotLimits, bytes: ByteLimit): RecordLimits =
  ## Snapshot union budgets do not alter ordinary batch policy or complete-state graph ceilings.
  result = limits.repository.codec
  result.records = TrieExportLimits(records: TrieNodeLimit(uint64(limits.repository.records)),
    valueBytes: limits.repository.valueBytes)
  result.encoded = bytes
proc compareSnapshotRoot(left, right: StateRoot): int =
  ## Detached root identities retain the canonical complete-byte order of the existing snapshot domain.
  let a = array[32, byte](left)
  let b = array[32, byte](right)
  for index in 0..<32:
    if a[index] < b[index]: return -1 # Later octets cannot change the first differing identity byte.
    if a[index] > b[index]: return 1
  0

proc encodeRepositorySnapshot*(selection: RepositorySelection, chain: StorageChainId,
    schema: StorageSchema, context: openArray[byte], limits: SnapshotLimits): SnapshotResult[
        SnapshotEncoding] =
  ## Bound metadata/body extents, serialize the opaque admitted union, then hash the outer frame once.
  if not selection.initialized: return default(SnapshotResult[SnapshotEncoding])
  if schema notin {StorageSchema.FullNodesV1, StorageSchema.FullStateV1} or
      (schema == StorageSchema.FullNodesV1 and context.len != 0):
    return SnapshotResult[SnapshotEncoding](status: SnapshotError.InvalidFormat)
  let inherited = selection.repositoryLimits.codec.trie
  let required = limits.repository.codec.trie
  let inheritedShape = [uint64(inherited.items), uint64(inherited.nodes),
    uint64(inherited.perValue), uint64(inherited.totalValueBytes)]
  let requiredShape = [uint64(required.items), uint64(required.nodes),
    uint64(required.perValue), uint64(required.totalValueBytes)]
  if inheritedShape != requiredShape:
    return SnapshotResult[SnapshotEncoding](status: SnapshotError.PolicyMismatch)
  let maximum = min(uint64(limits.bytes), uint64(high(int)))
  if maximum < uint64(Overhead) or uint64(context.len) > uint64(limits.context):
    return SnapshotResult[SnapshotEncoding](status: SnapshotError.LimitExceeded)
  var remaining = maximum-uint64(Overhead)
  let count = selection.retainedRootCount
  if uint64(count) > uint64(limits.roots) or uint64(count) > remaining div 32:
    return SnapshotResult[SnapshotEncoding](status: SnapshotError.LimitExceeded)
  let rootBytes = count*32
  remaining -= uint64(rootBytes)
  if uint64(context.len) > remaining:
    return SnapshotResult[SnapshotEncoding](status: SnapshotError.LimitExceeded)
  remaining -= uint64(context.len)
  let codec = physicalLimits(limits, ByteLimit(remaining))
  let measured = measureRepositorySelection(selection, codec)
  if measured.error != RepositoryError.None:
    return SnapshotResult[SnapshotEncoding](status: SnapshotError.RepositoryFailure,
        repositoryReason: measured.error)
  var roots = selection.retainedRoots
  roots.sort(compareSnapshotRoot) # Preserve exact snapshot order without materializing detached physical records.
  let generation = selection.generation
  let commitment = selection.commitment
  let prefixBytes = HeaderBytes+rootBytes+context.len
  var framed = encodeFramedRepositorySelection(selection, codec, uint64(prefixBytes), 32, limits.bytes)
  if framed.error != RepositoryError.None:
    return SnapshotResult[SnapshotEncoding](status: SnapshotError.RepositoryFailure,
        repositoryReason: framed.error)
  var output = framed.takeValue # Records already occupy their final frame positions; only metadata/checksum remain.
  for index, character in Magic: output[index] = byte(character)
  let base = Magic.len
  putHash(output, base, array[32, byte](chain))
  output[base+32] = byte(ord(schema))
  putNumber(output, base+33, uint64(generation))
  putHash(output, base+41, array[32, byte](commitment.root))
  putNumber(output, base+73, uint64(commitment.entries))
  putNumber(output, base+81, commitment.nodes)
  putNumber(output, base+89, uint64(roots.len))
  putNumber(output, base+97, uint64(context.len))
  putNumber(output, base+105, uint64(measured.value))
  var offset = HeaderBytes
  for root in roots:
    putHash(output, offset, array[32, byte](root))
    offset += 32 # Root-count preflight proved the complete variable inventory.
  for octet in context:
    output[offset] = octet
    inc offset # Context retains exact application bytes without interpreting their authority.
  assert offset == prefixBytes # Metadata ends at the already-serialized collection, without another body copy.
  let hashed = blake2b256(output.toOpenArray(0, output.len-33))
  if hashed.error != CryptoError.None: return SnapshotResult[SnapshotEncoding](
      status: SnapshotError.BackendFailure)
  let checksum = array[32, byte](hashed.value)
  putHash(output, output.len-32, checksum)
  SnapshotResult[SnapshotEncoding](status: SnapshotError.None,
    completed: SnapshotEncoding(bytes: output, checksum: StorageChecksum(checksum)))
proc decodeRepositorySnapshot*(input: openArray[byte], chain: StorageChainId,
    schema: StorageSchema, limits: SnapshotLimits): SnapshotResult[RepositorySnapshot] =
  ## Preflight all borrowed extents, verify integrity, then admit every declared complete graph.
  if schema notin {StorageSchema.FullNodesV1, StorageSchema.FullStateV1}:
    return SnapshotResult[RepositorySnapshot](status: SnapshotError.WrongIdentity)
  if uint64(input.len) > uint64(limits.bytes): return SnapshotResult[RepositorySnapshot](
      status: SnapshotError.LimitExceeded)
  if input.len < Overhead: return SnapshotResult[RepositorySnapshot](
      status: SnapshotError.InvalidFormat)
  for index, character in Magic:
    if input[index] != byte(character): return SnapshotResult[RepositorySnapshot](
        status: SnapshotError.InvalidFormat)
  let base = Magic.len
  if input[base+32] != byte(ord(schema)) or readHash(input, base) != array[32, byte](chain):
    return SnapshotResult[RepositorySnapshot](status: SnapshotError.WrongIdentity)
  let generation = number(input, base+33)
  let entries = number(input, base+73)
  let nodes = number(input, base+81)
  let count = number(input, base+89)
  let context = number(input, base+97)
  let body = number(input, base+105)
  if generation == 0 or count == 0: return SnapshotResult[RepositorySnapshot](
      status: SnapshotError.InvalidFormat)
  if count > uint64(limits.roots) or count > uint64(high(int) div sizeof(StateRoot)) or entries >
      uint64(high(int)) or entries > uint64(limits.repository.codec.trie.items) or
      nodes > uint64(limits.repository.codec.trie.nodes):
    return SnapshotResult[RepositorySnapshot](status: SnapshotError.LimitExceeded)
  if context > uint64(limits.context): return SnapshotResult[RepositorySnapshot](
      status: SnapshotError.LimitExceeded)
  var remaining = input.len-Overhead
  if count > uint64(remaining div 32): return SnapshotResult[RepositorySnapshot](
      status: SnapshotError.InvalidFormat)
  let rootBytes = int(count)*32
  remaining -= rootBytes
  if context > uint64(remaining): return SnapshotResult[RepositorySnapshot](
      status: SnapshotError.InvalidFormat)
  remaining -= int(context)
  if body != uint64(remaining): return SnapshotResult[RepositorySnapshot](
      status: SnapshotError.InvalidFormat)
  if schema == StorageSchema.FullNodesV1 and context != 0:
    return SnapshotResult[RepositorySnapshot](status: SnapshotError.InvalidFormat)
  let hashed = blake2b256(input.toOpenArray(0, input.len-33))
  if hashed.error != CryptoError.None: return SnapshotResult[RepositorySnapshot](
      status: SnapshotError.BackendFailure)
  let checksum = array[32, byte](hashed.value)
  if readHash(input, input.len-32) != checksum:
    return SnapshotResult[RepositorySnapshot](status: SnapshotError.ChecksumMismatch)
  let bodyOffset = HeaderBytes+rootBytes+int(context)
  var roots = newSeq[StateRoot](int(count))
  for index in 0..<roots.len: roots[index] = StateRoot(readHash(input, HeaderBytes+index*32))
  let commitment = StateTrieCommitment(root: StateRoot(readHash(input, base+41)), entries: int(
    entries), nodes: nodes)
  let admitted = decodeRepositoryImage(input.toOpenArray(bodyOffset, input.len-33),
    RepositoryGeneration(generation), commitment, roots, limits.repository, limits.roots, ByteLimit(body))
  if admitted.error == RepositoryError.InvalidRecords:
    # Fused admission preserves the original physical-codec diagnostic without a second hash pass.
    return SnapshotResult[RepositorySnapshot](status: SnapshotError.RecordFailure,
      recordReason: admitted.recordError)
  if admitted.error != RepositoryError.None:
    return SnapshotResult[RepositorySnapshot](status: SnapshotError.RepositoryFailure,
      repositoryReason: admitted.error)
  var ownedContext = newSeq[byte](int(context))
  for index in 0..<ownedContext.len: ownedContext[index] = input[HeaderBytes+rootBytes+index]
  SnapshotResult[RepositorySnapshot](status: SnapshotError.None,
    completed: RepositorySnapshot(repository: admitted.value, context: ownedContext,
        checksum: StorageChecksum(checksum)))
