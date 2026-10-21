# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Capture explicitly trusted operator inputs once, independently of the checkpoint being restored.
## Checksums and sealed hashes bind bytes; the operator supplies authority, not this local decoder.
import ./[checkpoint_identity, checkpoint_recovery]
import ../codec/bounded
import ../crypto/primitives
import ../state/store

const MaxRecoveryHeaderBytes* = 256 * 1024 ## Match structural chain capture's existing sealed-header ceiling.
type
  TrustedApplicationCheckpoint* = object ## Private immutable inputs prevent header replacement after trust capture.
    initialized: bool
    context: ApplicationCheckpointIdentity
    sealed: seq[byte]
  CheckpointTrustError* {.pure.} = enum ## Defaults and refusals contain no usable trust owner.
    Uninitialized, None, LimitExceeded, IdentityFailure, InvalidHeader, HeaderMismatch, BackendFailure
  CheckpointTrustResult* = object ## Only an exact canonical identity and hash-matching bounded header grant captured inputs.
    case status: CheckpointTrustError
    of None:
      completed: TrustedApplicationCheckpoint
    of IdentityFailure:
      identityReason: ApplicationCheckpointIdentityError
    else:
      discard # Header/limit/native failures expose no partially trusted input.
func ready*(trust: TrustedApplicationCheckpoint): bool =
  ## Default zero-filled context cannot activate recovery.
  trust.initialized
func identity*(trust: TrustedApplicationCheckpoint): ApplicationCheckpointIdentity {.inline,
    requires: trust.initialized.} =
  ## Return only fixed copied context; sealed bytes remain private.
  trust.context
func error*(outcome: CheckpointTrustResult): CheckpointTrustError =
  ## Observe capture refusal without payload extraction.
  outcome.status
func value*(outcome: CheckpointTrustResult): TrustedApplicationCheckpoint {.inline,
    requires: outcome.status == CheckpointTrustError.None.} =
  ## Failed/default capture never grants operator authority.
  outcome.completed
func identityError*(outcome: CheckpointTrustResult): ApplicationCheckpointIdentityError {.inline,
    requires: outcome.status == CheckpointTrustError.IdentityFailure.} =
  ## Preserve only actual canonical identity decoding errors.
  outcome.identityReason
proc captureCheckpointTrust*(identityBytes, sealedHeader: openArray[byte],
    limit: ByteLimit): CheckpointTrustResult =
  ## The caller explicitly selects these bytes as trusted; do not pass metadata extracted from an untrusted checkpoint.
  if sealedHeader.len == 0 or sealedHeader.len > MaxRecoveryHeaderBytes:
    return CheckpointTrustResult(status: CheckpointTrustError.InvalidHeader)
  if uint64(identityBytes.len) > uint64(limit) or uint64(sealedHeader.len) > uint64(limit) - uint64(
      identityBytes.len):
    return CheckpointTrustResult(status: CheckpointTrustError.LimitExceeded) # Subtraction proves aggregate extent without wrapping.
  let context = decodeApplicationCheckpointIdentity(identityBytes, ByteLimit(uint64(
      ApplicationCheckpointIdentityBytes)))
  if context.error != ApplicationCheckpointIdentityError.None:
    return CheckpointTrustResult(status: CheckpointTrustError.IdentityFailure,
      identityReason: context.error)
  let hashed = blake2b256(sealedHeader)
  if hashed.error != CryptoError.None:
    return CheckpointTrustResult(status: CheckpointTrustError.BackendFailure)
  if array[32, byte](hashed.value) != array[32, byte](context.value.blockHash):
    return CheckpointTrustResult(status: CheckpointTrustError.HeaderMismatch)
  var owned = newSeq[byte](sealedHeader.len)
  for index, octet in sealedHeader:
    owned[index] = octet # The bounded copy is private and cannot alias caller mutation.
  CheckpointTrustResult(status: CheckpointTrustError.None,
    completed: TrustedApplicationCheckpoint(initialized: true, context: context.value,
        sealed: owned))
proc decodeTrustedCheckpoint*(bytes: openArray[byte], trust: TrustedApplicationCheckpoint,
    limits: StateStoreLimits, limit: ByteLimit): ApplicationRecoveryResult =
  ## Borrow exact captured inputs synchronously; a default owner reaches recovery's MissingTrust gate first.
  decodeRecoveryCheckpoint(bytes, trust.sealed, trust.context, limits, limit)
proc loadTrustedCheckpoint*(path: string, trust: TrustedApplicationCheckpoint,
    limits: StateStoreLimits, limit: ByteLimit): ApplicationRecoveryResult =
  ## File recovery cannot reread or substitute trusted identity/header bytes after capture.
  loadRecoveryCheckpoint(path, trust.sealed, trust.context, limits, limit)
