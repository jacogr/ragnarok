# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Capture scalar checkpoint context from one selected application head and its exact canonical complete map.
## This metadata is not a consensus certificate or authorization to adopt a recovered chain.

import ./chain as app_chain
import ../chain/genesis as chain_genesis
import ../chain/provider as chain_provider
import ../chain/parameters as chain_parameters
import ../state/store as state_store
import ../codec/state_trie as codec_state_trie
import ../codec/bounded as codec_bounded
import ../crypto/primitives as crypto_primitives

type
  ApplicationCheckpointSlot* = distinct uint32 ## Captured block time remains distinct from disk generations and slot-file selectors.
  ApplicationCheckpointIdentity* = object ## Fixed-size metadata retains no state, header or history ARC graph.
    initialized: bool
    blockIdentity: BlockHash
    stateCommitment: StateRoot
    timeslot: ApplicationCheckpointSlot
    configuration: Parameters
  ApplicationCheckpointIdentityError* {.pure.} = enum ## Defaults and refused captures expose no partially usable binding.
    Uninitialized, None, MissingHead, StateMismatch, LimitExceeded, InvalidFormat,
      InvalidParameters, ChecksumMismatch, BackendFailure
  ApplicationCheckpointIdentityResult* = object ## Successful capture or local decoding returns complete metadata; decoding grants no independent trust.
    case status: ApplicationCheckpointIdentityError
    of None:
      completed: ApplicationCheckpointIdentity
    else:
      discard # Default or mismatched context carries only its refusal.
func ready*(identity: ApplicationCheckpointIdentity): bool =
  ## Initialization is separate from valid zero-valued roots or timeslots.
  identity.initialized
func error*(outcome: ApplicationCheckpointIdentityResult): ApplicationCheckpointIdentityError =
  ## Inspect refusal without extracting or changing a binding.
  outcome.status
func value*(outcome: ApplicationCheckpointIdentityResult): ApplicationCheckpointIdentity {.inline,
    requires: outcome.status == ApplicationCheckpointIdentityError.None.} =
  ## Failed/default captures cannot expose scalar context for publication.
  outcome.completed
func blockHash*(identity: ApplicationCheckpointIdentity): BlockHash {.inline,
    requires: identity.initialized.} =
  ## The exact sealed-header identity differs from both prior and posterior state roots.
  identity.blockIdentity
func stateRoot*(identity: ApplicationCheckpointIdentity): StateRoot {.inline,
    requires: identity.initialized.} =
  ## This is the selected complete posterior map root, never the header's prior-state field.
  identity.stateCommitment
func slot*(identity: ApplicationCheckpointIdentity): ApplicationCheckpointSlot {.inline,
    requires: identity.initialized.} =
  ## Preserve the selected header/map time without granting disk-generation authority.
  identity.timeslot
func parameters*(identity: ApplicationCheckpointIdentity): Parameters {.inline,
    requires: identity.initialized.} =
  ## Copy the complete immutable scalar tuple, including fields unrelated to Merklization.
  identity.configuration
proc sameApplicationCheckpoint*(left, right: ApplicationCheckpointIdentity): bool =
  ## Root equality alone cannot substitute for exact block, time and complete profile agreement; defaults never match.
  if not left.ready or not right.ready: return false # Zero-filled metadata is not an initialized checkpoint context.
  array[32, byte](left.blockIdentity) == array[32, byte](right.blockIdentity) and
    array[32, byte](left.stateCommitment) == array[32, byte](right.stateCommitment) and
    uint32(left.timeslot) == uint32(right.timeslot) and
    left.configuration.encodeParameters == right.configuration.encodeParameters
proc captureApplicationCheckpointIdentity*(chain: ApplicationChain): ApplicationCheckpointIdentityResult =
  ## Capture from the private canonical pair, proving exact immutable map ownership before retaining only scalars.
  let selected = chain.chainView.bestBlock
  if selected.error != GenesisError.None:
    return ApplicationCheckpointIdentityResult(status: ApplicationCheckpointIdentityError.MissingHead) # Missing context cannot be inferred from a root or empty map.
  let state = chain.stateSnapshot
  if state.error != StateStoreError.None or not sameStateSnapshot(state.value,
      selected.value.stateSnapshot):
    return ApplicationCheckpointIdentityResult(status: ApplicationCheckpointIdentityError.StateMismatch) # Independently reconstructed equal roots do not prove canonical owner agreement.
  let head = selected.value
  if head.chainParameters.hasExplicitExpungePeriod:
    return ApplicationCheckpointIdentityResult(status: ApplicationCheckpointIdentityError.InvalidParameters) # Ephemeral Fuzz interpretation must not disappear in the unchanged durable V1 tuple.
  ApplicationCheckpointIdentityResult(status: ApplicationCheckpointIdentityError.None,
    completed: ApplicationCheckpointIdentity(initialized: true, blockIdentity: head.blockHash,
      stateCommitment: state.value.commitment.root, timeslot: ApplicationCheckpointSlot(head.slot),
      configuration: head.chainParameters))

const
  IdentityMagic = "RAGNAROK-APP-V1\n"
  ApplicationCheckpointIdentityBytes* = 238 ## Fixed metadata extent includes the full 122-byte profile and 32-byte checksum.
  IdentityPayloadBytes = ApplicationCheckpointIdentityBytes - 32

type ApplicationCheckpointEncodingResult* = object ## Failed/default encoding has no partial output buffer.
  case status: ApplicationCheckpointIdentityError
  of None:
    completed: seq[byte]
  else:
    discard # No failure can masquerade as a complete encoded identity.
func error*(outcome: ApplicationCheckpointEncodingResult): ApplicationCheckpointIdentityError =
  ## Inspect encoding refusal without extracting private bytes.
  outcome.status
func value*(outcome: ApplicationCheckpointEncodingResult): seq[byte] {.inline,
    requires: outcome.status == ApplicationCheckpointIdentityError.None.} =
  ## Only fully encoded and checksummed metadata is exposed as independently owned bytes.
  outcome.completed
proc encodeApplicationCheckpointIdentity*(identity: ApplicationCheckpointIdentity,
    limit: ByteLimit): ApplicationCheckpointEncodingResult =
  ## Prove the fixed allocation ceiling before copying exact scalar fields or invoking the maintained hash primitive.
  if not identity.ready: return ApplicationCheckpointEncodingResult(
      status: ApplicationCheckpointIdentityError.Uninitialized)
  if uint64(limit) < uint64(ApplicationCheckpointIdentityBytes):
    return ApplicationCheckpointEncodingResult(status: ApplicationCheckpointIdentityError.LimitExceeded)
  var bytes = newSeq[byte](ApplicationCheckpointIdentityBytes)
  for index, character in IdentityMagic:
    bytes[index] = byte(character) # Version/domain excludes other local checkpoint envelopes.
  let blockHash = array[32, byte](identity.blockIdentity)
  let root = array[32, byte](identity.stateCommitment)
  for index in 0..<32:
    bytes[16 + index] = blockHash[index]
    bytes[48 + index] = root[index] # Both identities retain all bits, without replacing posterior root by header prior state.
  for index in 0..<4:
    bytes[80 + index] = byte((uint32(identity.timeslot) shr (8 * index)) and
        255) # Exact E4 little-endian block time.
  let configuration = identity.configuration.encodeParameters
  for index in 0..<ParameterBytes:
    bytes[84 + index] = configuration[index] # Every parameter participates, including fields unrelated to state hashing.
  let digest = blake2b256(bytes.toOpenArray(0, IdentityPayloadBytes - 1))
  if digest.error != CryptoError.None:
    return ApplicationCheckpointEncodingResult(status: ApplicationCheckpointIdentityError.BackendFailure)
  let checksum = array[32, byte](digest.value)
  for index in 0..<32:
    bytes[IdentityPayloadBytes + index] = checksum[
        index] # Integrity covers the entire versioned scalar tuple, not external authority.
  ApplicationCheckpointEncodingResult(status: ApplicationCheckpointIdentityError.None,
      completed: bytes)
proc decodeApplicationCheckpointIdentity*(bytes: openArray[byte],
    limit: ByteLimit): ApplicationCheckpointIdentityResult =
  ## Decode one exact local representation; initialized metadata remains untrusted until compared with independent caller context.
  if uint64(bytes.len) > uint64(limit):
    return ApplicationCheckpointIdentityResult(status: ApplicationCheckpointIdentityError.LimitExceeded)
  if bytes.len != ApplicationCheckpointIdentityBytes:
    return ApplicationCheckpointIdentityResult(status: ApplicationCheckpointIdentityError.InvalidFormat)
  for index, character in IdentityMagic:
    if bytes[index] != byte(character):
      return ApplicationCheckpointIdentityResult(status: ApplicationCheckpointIdentityError.InvalidFormat) # A checksum never enables version fallback.
  let digest = blake2b256(bytes.toOpenArray(0, IdentityPayloadBytes - 1))
  if digest.error != CryptoError.None:
    return ApplicationCheckpointIdentityResult(status: ApplicationCheckpointIdentityError.BackendFailure)
  let checksum = array[32, byte](digest.value)
  for index in 0..<32:
    if bytes[IdentityPayloadBytes + index] != checksum[index]:
      return ApplicationCheckpointIdentityResult(status: ApplicationCheckpointIdentityError.ChecksumMismatch) # Corrupt metadata exposes no usable fields.
  let configuration = decodeParameters(bytes.toOpenArray(84, IdentityPayloadBytes - 1))
  if not configuration.ok:
    return ApplicationCheckpointIdentityResult(status: ApplicationCheckpointIdentityError.InvalidParameters) # Complete fixed bytes still must satisfy the existing parameter invariants.
  var blockHash = default(array[32, byte])
  var root = default(array[32, byte])
  for index in 0..<32:
    blockHash[index] = bytes[16 + index]
    root[index] = bytes[48 + index] # Fixed extent was proved before any field read.
  var slot = 0'u32
  for index in 0..<4:
    slot = slot or (uint32(bytes[80 + index]) shl (8 *
        index)) # Disjoint shifts preserve full-width time without wrapping addition.
  ApplicationCheckpointIdentityResult(status: ApplicationCheckpointIdentityError.None,
    completed: ApplicationCheckpointIdentity(initialized: true, blockIdentity: BlockHash(blockHash),
      stateCommitment: StateRoot(root), timeslot: ApplicationCheckpointSlot(slot),
          configuration: configuration.value))
