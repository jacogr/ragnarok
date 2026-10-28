# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Small application-head context binds exact sealed header, full parameters and posterior state revision.
## Its enclosing contextual journal supplies integrity and local restart authority; this is no import certificate.

import ./[chain, checkpoint_identity]
import ../chain/[genesis, provider, parameters]
import ../state/store
import ../storage/[database_identity, node_repository]
import ../codec/[header, state_trie, bounded]

type
  DiskHeadError* {.pure.} = enum ## Failed/default results expose no partial header, chain or encoded bytes.
    Uninitialized, None, InvalidFormat, LimitExceeded, WrongChain, GenerationMismatch,
    IdentityFailure, HeaderFailure, StateFailure, ContextMismatch, CaptureFailure, ApplicationFailure
  DiskHeadResult*[T] = object ## Only complete context encoding or restored single-head ownership may escape.
    case status: DiskHeadError
    of None: completed: T
    else: discard # Refusals never grant a partially reconstructed canonical owner.

const
  HeadMagic = "RAGNAROK-DISK-HEAD-V1\n"
  BodyHeadMagic = "RAGNAROK-DISK-HEAD-V2\n"
  ChainOffset = HeadMagic.len
  GenerationOffset = ChainOffset+32
  IdentityOffset = GenerationOffset+8
  LengthOffset = IdentityOffset+ApplicationCheckpointIdentityBytes
  DiskHeadPrefixBytes* = LengthOffset+8 ## V1 header-only prefix; also the smallest permitted local-head entry.
  DiskBodyHeadPrefixBytes* = LengthOffset+16 ## V2 adds an E8 complete-block length before header and body bytes.

func error*[T](outcome: DiskHeadResult[T]): DiskHeadError =
  ## Read a typed stage refusal without exposing a default payload.
  outcome.status
func value*[T](outcome: DiskHeadResult[T]): T {.inline,
    requires: outcome.status == DiskHeadError.None.} =
  ## Only fully encoded or matching structurally restored context grants access.
  outcome.completed
func number(bytes: openArray[byte], offset: int): uint64 =
  ## All internal callers prove complete E8 fields before reading any octet.
  result = 0
  for index in 0..<8: result = result or (uint64(bytes[offset+index]) shl (index*8))
proc putNumber(bytes: var seq[byte], offset: int, value: uint64) =
  ## Fixed prefix allocation precedes every generation/header-length write.
  for index in 0..<8: bytes[offset+index] = byte((value shr (index*8)) and 255)
proc encodeDiskHead*(owner: ApplicationChain, chain: StorageChainId,
    generation: RepositoryGeneration, limit: ByteLimit): DiskHeadResult[seq[byte]] =
  ## Capture matching canonical facts and owned header bytes before any disk publication begins.
  if uint64(generation) == 0: return DiskHeadResult[seq[byte]](
      status: DiskHeadError.GenerationMismatch)
  let maximum = min(uint64(limit), uint64(high(int)))
  if maximum < uint64(DiskHeadPrefixBytes):
    return DiskHeadResult[seq[byte]](status: DiskHeadError.LimitExceeded)
  let identity = captureApplicationCheckpointIdentity(owner)
  if identity.error != ApplicationCheckpointIdentityError.None:
    return DiskHeadResult[seq[byte]](status: DiskHeadError.IdentityFailure)
  let selected = owner.chainView.bestBlock.value
  let info = selected.header.headerInfo
  if info.error != HeaderError.None:
    return DiskHeadResult[seq[byte]](status: DiskHeadError.HeaderFailure)
  let bodyLength = if selected.hasBlockBody: selected.blockBodyLength else: 0
  let prefix = if selected.hasBlockBody: DiskBodyHeadPrefixBytes else: DiskHeadPrefixBytes
  if uint64(prefix) > maximum or uint64(info.value.consumed) > maximum-uint64(prefix) or
      uint64(bodyLength) > maximum-uint64(prefix)-uint64(info.value.consumed):
    return DiskHeadResult[seq[byte]](status: DiskHeadError.LimitExceeded)
  let encoded = encodeApplicationCheckpointIdentity(identity.value, ByteLimit(ApplicationCheckpointIdentityBytes))
  if encoded.error != ApplicationCheckpointIdentityError.None:
    return DiskHeadResult[seq[byte]](status: DiskHeadError.IdentityFailure)
  var bytes = newSeq[byte](prefix+info.value.consumed+bodyLength)
  let magic = if selected.hasBlockBody: BodyHeadMagic else: HeadMagic
  for index, character in magic: bytes[index] = byte(
      character) # Exact version has no fallback interpretation.
  let chainBytes = array[32, byte](chain)
  for index in 0..<32: bytes[ChainOffset+index] = chainBytes[index]
  putNumber(bytes, GenerationOffset, uint64(generation))
  let metadata = encoded.value
  for index, octet in metadata: bytes[IdentityOffset+index] = octet
  putNumber(bytes, LengthOffset, uint64(info.value.consumed))
  if selected.hasBlockBody:
    putNumber(bytes, LengthOffset+8, uint64(bodyLength)) # V2 explicitly distinguishes complete bytes from a header-only seed.
  let header = encodeOwnedHeader(selected.header, bytes.toOpenArray(prefix,
      prefix+info.value.consumed-1))
  if header.error != HeaderError.None:
    return DiskHeadResult[seq[byte]](status: DiskHeadError.HeaderFailure)
  if selected.hasBlockBody:
    let body = selected.blockBody # Extent was admitted before copying immutable bytes.
    for index, octet in body: bytes[prefix+info.value.consumed+index] = octet
  DiskHeadResult[seq[byte]](status: DiskHeadError.None, completed: bytes)
proc restoreDiskHead*(bytes: openArray[byte], chain: StorageChainId,
    generation: RepositoryGeneration, configuration: Parameters, state: StateStoreSnapshot,
    limit: ByteLimit): DiskHeadResult[ApplicationChain] =
  ## Restore only journal-verified local context against selected chain/profile/generation and complete map.
  ## External imports must use their independent trust path; this structural capture authenticates no seals.
  if uint64(bytes.len) > uint64(limit):
    return DiskHeadResult[ApplicationChain](status: DiskHeadError.LimitExceeded)
  if bytes.len <= DiskHeadPrefixBytes:
    return DiskHeadResult[ApplicationChain](status: DiskHeadError.InvalidFormat)
  var withBody = true
  for index, character in BodyHeadMagic:
    if bytes[index] != byte(character): withBody = false # Version choice is exact; malformed V2 never decodes as V1.
  let prefix = if withBody: DiskBodyHeadPrefixBytes else: DiskHeadPrefixBytes
  let magic = if withBody: BodyHeadMagic else: HeadMagic
  for index, character in magic:
    if bytes[index] != byte(character):
      return DiskHeadResult[ApplicationChain](status: DiskHeadError.InvalidFormat)
  if bytes.len <= prefix:
    return DiskHeadResult[ApplicationChain](status: DiskHeadError.InvalidFormat)
  let chainBytes = array[32, byte](chain)
  for index in 0..<32:
    if bytes[ChainOffset+index] != chainBytes[index]:
      return DiskHeadResult[ApplicationChain](status: DiskHeadError.WrongChain)
  if uint64(generation) == 0 or number(bytes, GenerationOffset) != uint64(generation):
    return DiskHeadResult[ApplicationChain](status: DiskHeadError.GenerationMismatch)
  let headerLength = number(bytes, LengthOffset)
  let bodyLength = if withBody: number(bytes, LengthOffset+8) else: 0'u64
  let remaining = uint64(bytes.len-prefix)
  if headerLength == 0 or headerLength > remaining or bodyLength != remaining-headerLength or
      (withBody and bodyLength == 0):
    return DiskHeadResult[ApplicationChain](status: DiskHeadError.InvalidFormat)
  let identity = decodeApplicationCheckpointIdentity(bytes.toOpenArray(IdentityOffset,
      LengthOffset-1),
    ByteLimit(ApplicationCheckpointIdentityBytes))
  if identity.error != ApplicationCheckpointIdentityError.None:
    return DiskHeadResult[ApplicationChain](status: DiskHeadError.IdentityFailure)
  if state.forkStateStore.error != StateStoreError.None:
    return DiskHeadResult[ApplicationChain](status: DiskHeadError.StateFailure)
  if configuration.encodeParameters != identity.value.parameters.encodeParameters or
      array[32, byte](state.commitment.root) != array[32, byte](identity.value.stateRoot):
    return DiskHeadResult[ApplicationChain](status: DiskHeadError.ContextMismatch)
  let headerEnd = prefix+int(headerLength) # Input extents prove host conversion and addition.
  let captured = captureBlockSnapshot(bytes.toOpenArray(prefix, headerEnd-1), state, configuration)
  if captured.error != GenesisError.None:
    return DiskHeadResult[ApplicationChain](status: DiskHeadError.CaptureFailure)
  let complete = if withBody: withBlockBody(captured.value, bytes.toOpenArray(headerEnd, bytes.high))
    else: captured # Legacy contexts retain explicit body unavailability.
  if complete.error != GenesisError.None:
    return DiskHeadResult[ApplicationChain](status: DiskHeadError.CaptureFailure)
  let restored = initApplicationChain(genesisView(complete))
  if restored.error != ApplicationChainError.None:
    return DiskHeadResult[ApplicationChain](status: DiskHeadError.ApplicationFailure)
  let checked = captureApplicationCheckpointIdentity(restored.value)
  if checked.error != ApplicationCheckpointIdentityError.None or
      not sameApplicationCheckpoint(checked.value, identity.value):
    return DiskHeadResult[ApplicationChain](status: DiskHeadError.ContextMismatch)
  DiskHeadResult[ApplicationChain](status: DiskHeadError.None, completed: restored.value)
