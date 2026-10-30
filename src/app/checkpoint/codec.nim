# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One application checkpoint envelope binds exact scalar context to existing canonical complete-map checkpoint bytes.
## Synchronous capture/encoding belongs outside transport callbacks and retains no application graph in its output.

import ../chain
import ./identity as checkpoint_identity
import ../../state/[checkpoint, store]
import ../../codec/bounded

type
  ApplicationCheckpointError* {.pure.} = enum ## Only complete envelopes grant payloads; nested failures retain their selected typed reason.
    Uninitialized, None, LimitExceeded, IdentityFailure, CheckpointFailure, ContextMismatch
  ApplicationCheckpointResult*[T] = object ## Failed/default results have no partial bytes or recovered map.
    case status: ApplicationCheckpointError
    of None:
      completed: T
    of IdentityFailure:
      identityReason: ApplicationCheckpointIdentityError
    of CheckpointFailure:
      checkpointReason: CheckpointError
    else:
      discard # No incomplete payload escapes a refusal.

func error*[T](outcome: ApplicationCheckpointResult[T]): ApplicationCheckpointError =
  ## Inspect the outer status without exposing a mismatched payload or nested reason.
  outcome.status

func value*[T](outcome: ApplicationCheckpointResult[T]): T {.inline, requires: outcome.status ==
    ApplicationCheckpointError.None.} =
  ## Only complete success grants independently owned bytes or restored state.
  outcome.completed

func identityError*[T](outcome: ApplicationCheckpointResult[
    T]): ApplicationCheckpointIdentityError {.inline, requires: outcome.status ==
    ApplicationCheckpointError.IdentityFailure.} =
  ## Preserve only an actual capture/metadata refusal.
  outcome.identityReason

func checkpointError*[T](outcome: ApplicationCheckpointResult[T]): CheckpointError {.inline,
    requires: outcome.status == ApplicationCheckpointError.CheckpointFailure.} =
  ## Preserve only an actual complete-map codec refusal.
  outcome.checkpointReason

proc encodeApplicationCheckpoint*(owner: ApplicationChain,
    limit: ByteLimit): ApplicationCheckpointResult[seq[byte]] =
  ## Prove the entire output extent against both caller and host ceilings before the final allocation.
  let identity = captureApplicationCheckpointIdentity(owner)
  if identity.error != ApplicationCheckpointIdentityError.None:
    return ApplicationCheckpointResult[seq[byte]](
        status: ApplicationCheckpointError.IdentityFailure,
        identityReason: identity.error) # A root alone cannot supply an absent canonical head/context.
  let maximum = min(uint64(limit), uint64(high(int)))
  if maximum < uint64(ApplicationCheckpointIdentityBytes):
    return ApplicationCheckpointResult[seq[byte]](status: ApplicationCheckpointError.LimitExceeded)
  let state = owner.stateSnapshot
  let checkpoint = encodeFullCheckpoint(state.value, ByteLimit(maximum - uint64(
      ApplicationCheckpointIdentityBytes)))
  if checkpoint.error == CheckpointError.LimitExceeded:
    return ApplicationCheckpointResult[seq[byte]](
        status: ApplicationCheckpointError.LimitExceeded) # The context prefix participates in the same aggregate output budget.
  if checkpoint.error != CheckpointError.None:
    return ApplicationCheckpointResult[seq[byte]](
        status: ApplicationCheckpointError.CheckpointFailure, checkpointReason: checkpoint.error)
  let encoded = encodeApplicationCheckpointIdentity(identity.value, ByteLimit(uint64(
      ApplicationCheckpointIdentityBytes)))
  if encoded.error != ApplicationCheckpointIdentityError.None:
    return ApplicationCheckpointResult[seq[byte]](
        status: ApplicationCheckpointError.IdentityFailure,
        identityReason: encoded.error) # No partial envelope is returned after metadata hashing failure.
  let prefix = encoded.value
  let payload = checkpoint.value
  var bytes = newSeq[byte](ApplicationCheckpointIdentityBytes +
      payload.len) # The inner encoder proved payload <= maximum-prefix <= high(int)-prefix.
  for index, octet in prefix:
    bytes[index] = octet # The fixed metadata extent is canonical and already checked.
  for index, octet in payload:
    bytes[ApplicationCheckpointIdentityBytes + index] = octet # Strict complete-map framing follows the fixed prefix without extra trailing data.
  ApplicationCheckpointResult[seq[byte]](status: ApplicationCheckpointError.None, completed: bytes)

proc decodeApplicationCheckpoint*(bytes: openArray[byte], expected: ApplicationCheckpointIdentity,
    limits: StateStoreLimits, limit: ByteLimit): ApplicationCheckpointResult[StateStore] =
  ## Check independent complete context before allocating a restored map; the file's own metadata never supplies trust.
  if not expected.ready:
    return ApplicationCheckpointResult[StateStore](
      status: ApplicationCheckpointError.IdentityFailure,
      identityReason: ApplicationCheckpointIdentityError.Uninitialized) # Default context cannot authorize a default/empty root.
  if uint64(bytes.len) > uint64(limit):
    return ApplicationCheckpointResult[StateStore](status: ApplicationCheckpointError.LimitExceeded)
  if bytes.len < ApplicationCheckpointIdentityBytes:
    return ApplicationCheckpointResult[StateStore](
      status: ApplicationCheckpointError.IdentityFailure,
      identityReason: ApplicationCheckpointIdentityError.InvalidFormat) # Prove the fixed prefix before creating a borrowed slice.
  let identity = decodeApplicationCheckpointIdentity(bytes.toOpenArray(0,
      ApplicationCheckpointIdentityBytes - 1),
    ByteLimit(uint64(ApplicationCheckpointIdentityBytes)))
  if identity.error != ApplicationCheckpointIdentityError.None:
    return ApplicationCheckpointResult[StateStore](
        status: ApplicationCheckpointError.IdentityFailure, identityReason: identity.error)
  if not sameApplicationCheckpoint(identity.value, expected):
    return ApplicationCheckpointResult[StateStore](
        status: ApplicationCheckpointError.ContextMismatch) # Even checksum-valid metadata cannot select another block/profile/time/root.
  let restored = decodeFullCheckpoint(bytes.toOpenArray(ApplicationCheckpointIdentityBytes,
      bytes.len - 1),
    expected.stateRoot, limits, ByteLimit(uint64(limit) - uint64(
        ApplicationCheckpointIdentityBytes)))
  if restored.error == CheckpointError.LimitExceeded:
    return ApplicationCheckpointResult[StateStore](
        status: ApplicationCheckpointError.LimitExceeded) # Both byte and complete-map resource ceilings remain effective.
  if restored.error != CheckpointError.None:
    return ApplicationCheckpointResult[StateStore](
        status: ApplicationCheckpointError.CheckpointFailure, checkpointReason: restored.error)
  ApplicationCheckpointResult[StateStore](status: ApplicationCheckpointError.None,
      completed: restored.value)
