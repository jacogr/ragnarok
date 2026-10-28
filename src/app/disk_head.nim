# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Small application-head context binds exact sealed header, full parameters and posterior state revision.
## Its enclosing contextual journal supplies integrity and local restart authority; this is no import certificate.

import ./chain as app_chain
import ./checkpoint_identity as app_checkpoint_identity
import ../chain/genesis as chain_genesis
import ../chain/provider as chain_provider
import ../chain/parameters as chain_parameters
import ../state/store as state_store
import ../storage/database_identity as storage_database_identity
import ../storage/node_repository as storage_node_repository
import ../codec/header as codec_header
import ../codec/state_trie as codec_state_trie
import ../codec/bounded as codec_bounded

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
  ChainOffset = HeadMagic.len
  GenerationOffset = ChainOffset+32
  IdentityOffset = GenerationOffset+8
  LengthOffset = IdentityOffset+ApplicationCheckpointIdentityBytes
  DiskHeadPrefixBytes* = LengthOffset+8 ## All fixed facts precede one exact bounded sealed-header encoding.

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
  if uint64(info.value.consumed) > maximum-uint64(DiskHeadPrefixBytes):
    return DiskHeadResult[seq[byte]](status: DiskHeadError.LimitExceeded)
  let encoded = encodeApplicationCheckpointIdentity(identity.value, ByteLimit(ApplicationCheckpointIdentityBytes))
  if encoded.error != ApplicationCheckpointIdentityError.None:
    return DiskHeadResult[seq[byte]](status: DiskHeadError.IdentityFailure)
  var bytes = newSeq[byte](DiskHeadPrefixBytes+info.value.consumed)
  for index, character in HeadMagic: bytes[index] = byte(
      character) # Exact version has no fallback interpretation.
  let chainBytes = array[32, byte](chain)
  for index in 0..<32: bytes[ChainOffset+index] = chainBytes[index]
  putNumber(bytes, GenerationOffset, uint64(generation))
  let metadata = encoded.value
  for index, octet in metadata: bytes[IdentityOffset+index] = octet
  putNumber(bytes, LengthOffset, uint64(info.value.consumed))
  let header = encodeOwnedHeader(selected.header, bytes.toOpenArray(DiskHeadPrefixBytes, bytes.high))
  if header.error != HeaderError.None:
    return DiskHeadResult[seq[byte]](status: DiskHeadError.HeaderFailure)
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
  for index, character in HeadMagic:
    if bytes[index] != byte(character):
      return DiskHeadResult[ApplicationChain](status: DiskHeadError.InvalidFormat)
  let chainBytes = array[32, byte](chain)
  for index in 0..<32:
    if bytes[ChainOffset+index] != chainBytes[index]:
      return DiskHeadResult[ApplicationChain](status: DiskHeadError.WrongChain)
  if uint64(generation) == 0 or number(bytes, GenerationOffset) != uint64(generation):
    return DiskHeadResult[ApplicationChain](status: DiskHeadError.GenerationMismatch)
  if number(bytes, LengthOffset) != uint64(bytes.len-DiskHeadPrefixBytes):
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
  let captured = captureBlockSnapshot(bytes.toOpenArray(DiskHeadPrefixBytes, bytes.high), state, configuration)
  if captured.error != GenesisError.None:
    return DiskHeadResult[ApplicationChain](status: DiskHeadError.CaptureFailure)
  let restored = initApplicationChain(genesisView(captured))
  if restored.error != ApplicationChainError.None:
    return DiskHeadResult[ApplicationChain](status: DiskHeadError.ApplicationFailure)
  let checked = captureApplicationCheckpointIdentity(restored.value)
  if checked.error != ApplicationCheckpointIdentityError.None or
      not sameApplicationCheckpoint(checked.value, identity.value):
    return DiskHeadResult[ApplicationChain](status: DiskHeadError.ContextMismatch)
  DiskHeadResult[ApplicationChain](status: DiskHeadError.None, completed: restored.value)
