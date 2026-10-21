# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact managed manifests select one snapshot/journal epoch without pathname or fallback authority.
## Epochs identify files independently of durable state generations; journal headers bind the manifest checksum.
import std/assertions
import ./[database_identity, node_repository]
import ../codec/[bounded, state_trie]
import ../crypto/primitives
const
  Magic = "RAGNAROK-MANIFEST-V1\n"
  JournalMagic = "RAGNAROK-JOURNAL-V1\n"
  ManagedManifestBytes* = Magic.len+145
  ManagedJournalHeaderBytes* = JournalMagic.len+32
type
  ManagedEpoch* = distinct uint64 ## Monotonic physical file epoch; compaction does not consume a state generation.
  ManagedManifest* = object ## Checked scalar selection of one independently verified snapshot and its journal.
    epoch*: ManagedEpoch
    generation*: RepositoryGeneration
    root*: StateRoot
    snapshotChecksum*: StorageChecksum
    checksum*: StorageChecksum
  ManifestEncoding* = object ## Detached exact manifest bytes with their prefix integrity checksum.
    bytes*: seq[byte]
    checksum*: StorageChecksum
  ManifestError* {.pure.} = enum ## A failed/default result never exposes a selected epoch or prefix.
    Uninitialized, None, InvalidFormat, WrongIdentity, LimitExceeded, ChecksumMismatch, BackendFailure
  ManifestResult*[T] = object ## Only complete validated manifest/header operations expose payloads.
    case status: ManifestError
    of None: completed: T
    else: discard
func error*[T](outcome: ManifestResult[T]): ManifestError =
  ## Read only the selected reason.
  outcome.status
func value*[T](outcome: ManifestResult[T]): T {.inline, requires: outcome.status ==
    ManifestError.None.} =
  ## Extract exact bytes or metadata only after success.
  outcome.completed
proc putNumber(output: var seq[byte], offset: int, number: uint64) =
  ## Callers prove the fixed output header before each E8 write.
  for index in 0..<8: output[offset+index] = byte((number shr (8*index)) and 255)
func number(input: openArray[byte], offset: int): uint64 =
  ## Exact manifest width precedes every E8 read.
  result = 0
  for index in 0..<8: result = result or (uint64(input[offset+index]) shl (8*index))
proc putHash(output: var seq[byte], offset: int, hash: array[32, byte]) =
  ## Copy a complete scalar identity inside the exact output extent.
  for index in 0..<32: output[offset+index] = hash[index]
func readHash(input: openArray[byte], offset: int): array[32, byte] =
  ## Copy only a proved full scalar field.
  result = default(array[32, byte])
  for index in 0..<32: result[index] = input[offset+index]
proc encodeManagedManifest*(chain: StorageChainId, schema: StorageSchema, epoch: ManagedEpoch,
    generation: RepositoryGeneration, root: StateRoot, snapshotChecksum: StorageChecksum,
    limit: ByteLimit): ManifestResult[ManifestEncoding] =
  ## Bind exact chain/schema, nonzero epoch/base generation, root and snapshot bytes under one checksum.
  if uint64(epoch) == 0 or uint64(generation) == 0:
    return ManifestResult[ManifestEncoding](status: ManifestError.InvalidFormat)
  if schema notin {StorageSchema.FullNodesV1, StorageSchema.FullStateV1}:
    return ManifestResult[ManifestEncoding](status: ManifestError.WrongIdentity)
  if uint64(limit) < uint64(ManagedManifestBytes):
    return ManifestResult[ManifestEncoding](status: ManifestError.LimitExceeded)
  var output = newSeq[byte](ManagedManifestBytes)
  for index, character in Magic: output[index] = byte(character)
  let base = Magic.len
  putHash(output, base, array[32, byte](chain))
  output[base+32] = byte(ord(schema))
  putNumber(output, base+33, uint64(epoch))
  putNumber(output, base+41, uint64(generation))
  putHash(output, base+49, array[32, byte](root))
  putHash(output, base+81, array[32, byte](snapshotChecksum))
  let hashed = blake2b256(output.toOpenArray(0, output.len-33))
  if hashed.error != CryptoError.None: return ManifestResult[ManifestEncoding](
      status: ManifestError.BackendFailure)
  let checksum = array[32, byte](hashed.value)
  putHash(output, output.len-32, checksum)
  ManifestResult[ManifestEncoding](status: ManifestError.None,
    completed: ManifestEncoding(bytes: output, checksum: StorageChecksum(checksum)))
proc decodeManagedManifest*(input: openArray[byte], chain: StorageChainId, schema: StorageSchema,
    limit: ByteLimit): ManifestResult[ManagedManifest] =
  ## No unknown schema, trailing bytes or corrupt complete manifest authorizes older-file fallback.
  if uint64(input.len) > uint64(limit): return ManifestResult[ManagedManifest](
      status: ManifestError.LimitExceeded)
  if input.len != ManagedManifestBytes: return ManifestResult[ManagedManifest](
      status: ManifestError.InvalidFormat)
  if schema notin {StorageSchema.FullNodesV1, StorageSchema.FullStateV1}:
    return ManifestResult[ManagedManifest](status: ManifestError.WrongIdentity)
  for index, character in Magic:
    if input[index] != byte(character): return ManifestResult[ManagedManifest](
        status: ManifestError.InvalidFormat)
  let base = Magic.len
  if input[base+32] != byte(ord(schema)) or readHash(input, base) != array[32, byte](chain):
    return ManifestResult[ManagedManifest](status: ManifestError.WrongIdentity)
  let epoch = number(input, base+33)
  let generation = number(input, base+41)
  if epoch == 0 or generation == 0: return ManifestResult[ManagedManifest](
      status: ManifestError.InvalidFormat)
  let hashed = blake2b256(input.toOpenArray(0, input.len-33))
  if hashed.error != CryptoError.None: return ManifestResult[ManagedManifest](
      status: ManifestError.BackendFailure)
  let checksum = array[32, byte](hashed.value)
  if readHash(input, input.len-32) != checksum:
    return ManifestResult[ManagedManifest](status: ManifestError.ChecksumMismatch)
  ManifestResult[ManagedManifest](status: ManifestError.None,
    completed: ManagedManifest(epoch: ManagedEpoch(epoch), generation: RepositoryGeneration(
        generation),
      root: StateRoot(readHash(input, base+49)), snapshotChecksum: StorageChecksum(readHash(input,
          base+81)),
      checksum: StorageChecksum(checksum)))
proc encodeManagedJournalHeader*(checksum: StorageChecksum, limit: ByteLimit): ManifestResult[seq[byte]] =
  ## Bind one new journal to the exact selected manifest rather than a guessed filename generation.
  if uint64(limit) < uint64(ManagedJournalHeaderBytes):
    return ManifestResult[seq[byte]](status: ManifestError.LimitExceeded)
  var output = newSeq[byte](ManagedJournalHeaderBytes)
  for index, character in JournalMagic: output[index] = byte(character)
  putHash(output, JournalMagic.len, array[32, byte](checksum))
  ManifestResult[seq[byte]](status: ManifestError.None, completed: output)
proc validateManagedJournalHeader*(input: openArray[byte],
    checksum: StorageChecksum): ManifestError =
  ## Require exact header bytes before any following frame is interpreted.
  if input.len != ManagedJournalHeaderBytes: return ManifestError.InvalidFormat
  for index, character in JournalMagic:
    if input[index] != byte(character): return ManifestError.InvalidFormat
  if readHash(input, JournalMagic.len) != array[32, byte](
      checksum): return ManifestError.WrongIdentity
  ManifestError.None
