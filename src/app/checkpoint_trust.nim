# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Capture explicitly trusted operator inputs once, independently of the checkpoint being restored.
## Checksums and sealed hashes bind bytes; the operator supplies authority, not this local decoder.
import ./checkpoint_identity as app_checkpoint_identity
import ./checkpoint_recovery as app_checkpoint_recovery
import ../codec/bounded as codec_bounded
import ../crypto/primitives as crypto_primitives
import ../state/store as state_store
import ../lib/atomic_file as lib_atomic_file

const MaxRecoveryHeaderBytes* = 256 * 1024 ## Match structural chain capture's existing sealed-header ceiling.
type
  TrustedApplicationCheckpoint* = object ## Private immutable inputs prevent header replacement after trust capture.
    initialized: bool
    context: ApplicationCheckpointIdentity
    sealed: seq[byte]
  CheckpointTrustError* {.pure.} = enum ## Defaults and refusals contain no usable trust owner.
    Uninitialized, None, LimitExceeded, IdentityFailure, InvalidHeader, HeaderMismatch,
      BackendFailure, FileFailure
  CheckpointTrustResult* = object ## Only an exact canonical identity and hash-matching bounded header grant captured inputs.
    case status: CheckpointTrustError
    of None:
      completed: TrustedApplicationCheckpoint
    of IdentityFailure:
      identityReason: ApplicationCheckpointIdentityError
    of FileFailure:
      fileReason: AtomicFileError
    else:
      discard # Header/limit/native failures expose no partially trusted input.
func ready*(trust: TrustedApplicationCheckpoint): bool =
  ## Default zero-filled context cannot activate recovery.
  trust.initialized
func identity*(trust: TrustedApplicationCheckpoint): ApplicationCheckpointIdentity {.inline,
    requires: trust.initialized.} =
  ## Return only fixed copied context; sealed bytes remain private.
  trust.context
func sealedHeaderLength*(trust: TrustedApplicationCheckpoint): int =
  ## Observe bounded transport size without exposing private wire storage or granting a default owner authority.
  if trust.initialized: trust.sealed.len else: 0
proc copySealedHeader*(trust: TrustedApplicationCheckpoint, output: var openArray[byte]): bool =
  ## Copy into independent caller storage only after full capacity admission; defaults/short buffers leave output unchanged.
  if not trust.initialized or output.len < trust.sealed.len: return false
  for index, octet in trust.sealed: output[index] = octet # Capture already detached this immutable wire from the original caller.
  true
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
proc captureHeader(context: ApplicationCheckpointIdentity,
    sealedHeader: openArray[byte]): CheckpointTrustResult =
  ## Both input paths validate identity once and share the exact bounded hash/copy boundary.
  if sealedHeader.len == 0 or sealedHeader.len > MaxRecoveryHeaderBytes:
    return CheckpointTrustResult(status: CheckpointTrustError.InvalidHeader)
  let hashed = blake2b256(sealedHeader)
  if hashed.error != CryptoError.None:
    return CheckpointTrustResult(status: CheckpointTrustError.BackendFailure)
  if array[32, byte](hashed.value) != array[32, byte](context.blockHash):
    return CheckpointTrustResult(status: CheckpointTrustError.HeaderMismatch)
  var owned = newSeq[byte](sealedHeader.len)
  for index, octet in sealedHeader:
    owned[index] = octet # The bounded copy is private and cannot alias caller mutation.
  CheckpointTrustResult(status: CheckpointTrustError.None,
    completed: TrustedApplicationCheckpoint(initialized: true, context: context,
        sealed: owned))
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
  captureHeader(context.value, sealedHeader)
proc decodeTrustedCheckpoint*(bytes: openArray[byte], trust: TrustedApplicationCheckpoint,
    limits: StateStoreLimits, limit: ByteLimit): ApplicationRecoveryResult =
  ## Borrow exact captured inputs synchronously; a default owner reaches recovery's MissingTrust gate first.
  decodeRecoveryCheckpoint(bytes, trust.sealed, trust.context, limits, limit)
proc loadTrustedCheckpoint*(path: string, trust: TrustedApplicationCheckpoint,
    limits: StateStoreLimits, limit: ByteLimit): ApplicationRecoveryResult =
  ## File recovery cannot reread or substitute trusted identity/header bytes after capture.
  loadRecoveryCheckpoint(path, trust.sealed, trust.context, limits, limit)

func fileError*(outcome: CheckpointTrustResult): AtomicFileError {.inline,
    requires: outcome.status == CheckpointTrustError.FileFailure.} =
  ## Preserve only an actual independently selected input-file refusal.
  outcome.fileReason
proc loadCheckpointTrust*(identityPath, headerPath: string,
    limit: ByteLimit): CheckpointTrustResult =
  ## Startup reads fixed canonical identity first, then one bounded header; neither path is the checkpoint being restored.
  if uint64(limit) < uint64(ApplicationCheckpointIdentityBytes):
    return CheckpointTrustResult(status: CheckpointTrustError.LimitExceeded)
  let metadata = readBoundedFile(identityPath, ByteLimit(uint64(
      ApplicationCheckpointIdentityBytes)))
  if metadata.error != AtomicFileError.None:
    return CheckpointTrustResult(status: CheckpointTrustError.FileFailure,
        fileReason: metadata.error)
  let context = decodeApplicationCheckpointIdentity(metadata.value, ByteLimit(uint64(
      ApplicationCheckpointIdentityBytes)))
  if context.error != ApplicationCheckpointIdentityError.None:
    return CheckpointTrustResult(status: CheckpointTrustError.IdentityFailure,
      identityReason: context.error) # Invalid trust identity cannot authorize opening the header path.
  let headerLimit = min(uint64(MaxRecoveryHeaderBytes), uint64(limit) - uint64(ApplicationCheckpointIdentityBytes))
  let header = readBoundedFile(headerPath, ByteLimit(headerLimit))
  if header.error != AtomicFileError.None:
    return CheckpointTrustResult(status: CheckpointTrustError.FileFailure, fileReason: header.error)
  captureHeader(context.value, header.value) # The same captured bytes survive all subsequent checkpoint work.
