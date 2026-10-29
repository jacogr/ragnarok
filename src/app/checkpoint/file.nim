# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded synchronous file adapters preserve whole application envelopes and independently supplied recovery context.
## Startup/offline callers own scheduling; these APIs never run in transport callbacks or adopt a canonical chain.
import ../chain
import ./[identity as checkpoint_identity, codec as checkpoint_codec,
    transfer as checkpoint_transfer]
import ../../state/[store, checkpoint]
import ../../codec/bounded
import ../../lib/atomic/file as atomic_file
import ../../lib/atomic/file/writer as atomic_file_writer

type
  ApplicationCheckpointFileError* {.pure.} = enum ## Native and selected codec failures never carry a partial map or successful publication receipt.
    Uninitialized, None, InvalidPath, IoFailure, LimitExceeded, Busy, PublishedUnsynced,
      IdentityFailure, CheckpointFailure, ContextMismatch
  ApplicationCheckpointFileResult*[T] = object ## Only durable publication or complete independently bound restoration exposes its payload.
    case status: ApplicationCheckpointFileError
    of None:
      completed: T
    of IdentityFailure:
      identityReason: ApplicationCheckpointIdentityError
    of CheckpointFailure:
      checkpointReason: CheckpointError
    else:
      discard # Native/default/context failures retain only their outer reason.
func error*[T](outcome: ApplicationCheckpointFileResult[T]): ApplicationCheckpointFileError =
  ## Inspect precise native/context status without exposing private alternatives.
  outcome.status
func value*[T](outcome: ApplicationCheckpointFileResult[T]): T {.inline, requires: outcome.status ==
    ApplicationCheckpointFileError.None.} =
  ## Publication uncertainty and failed restoration cannot supply a success receipt or complete map.
  outcome.completed
func identityError*[T](outcome: ApplicationCheckpointFileResult[
    T]): ApplicationCheckpointIdentityError {.inline, requires: outcome.status ==
    ApplicationCheckpointFileError.IdentityFailure.} =
  ## Only actual failed capture/identity decoding supplies this typed cause.
  outcome.identityReason
func checkpointError*[T](outcome: ApplicationCheckpointFileResult[T]): CheckpointError {.inline,
    requires: outcome.status == ApplicationCheckpointFileError.CheckpointFailure.} =
  ## Only actual complete-map decoding supplies this typed cause.
  outcome.checkpointReason
func toApplicationCheckpointFileError*(error: AtomicFileError): ApplicationCheckpointFileError =
  ## Exhaustive mapping preserves native uncertainty and locking distinctions for the owning facade.
  case error
  of AtomicFileError.Uninitialized: ApplicationCheckpointFileError.Uninitialized
  of AtomicFileError.None: ApplicationCheckpointFileError.None
  of AtomicFileError.InvalidPath: ApplicationCheckpointFileError.InvalidPath
  of AtomicFileError.IoFailure: ApplicationCheckpointFileError.IoFailure
  of AtomicFileError.LimitExceeded: ApplicationCheckpointFileError.LimitExceeded
  of AtomicFileError.PublishedUnsynced: ApplicationCheckpointFileError.PublishedUnsynced
  of AtomicFileError.Busy: ApplicationCheckpointFileError.Busy
proc refused(prepared: PreparedApplicationCheckpoint): ApplicationCheckpointFileResult[
    ApplicationCheckpointIdentity] =
  ## Translate only preparation reasons; accidental internal success translation fails closed.
  case prepared.error
  of ApplicationCheckpointError.IdentityFailure:
    ApplicationCheckpointFileResult[ApplicationCheckpointIdentity](
        status: ApplicationCheckpointFileError.IdentityFailure,
        identityReason: prepared.identityError)
  of ApplicationCheckpointError.CheckpointFailure:
    ApplicationCheckpointFileResult[ApplicationCheckpointIdentity](
        status: ApplicationCheckpointFileError.CheckpointFailure,
        checkpointReason: prepared.checkpointError)
  of ApplicationCheckpointError.LimitExceeded:
    ApplicationCheckpointFileResult[ApplicationCheckpointIdentity](
        status: ApplicationCheckpointFileError.LimitExceeded)
  of ApplicationCheckpointError.ContextMismatch:
    ApplicationCheckpointFileResult[ApplicationCheckpointIdentity](
        status: ApplicationCheckpointFileError.ContextMismatch)
  else:
    default(ApplicationCheckpointFileResult[ApplicationCheckpointIdentity]) # Defaults or an invalid internal success call never become successful file publication.
proc saveApplicationCheckpoint*(path: string, prepared: PreparedApplicationCheckpoint,
    limit: ByteLimit): ApplicationCheckpointFileResult[ApplicationCheckpointIdentity] =
  ## Publish identity and complete map in one existing durable atomic replacement; no separate metadata window exists.
  if prepared.error != ApplicationCheckpointError.None: return refused(prepared)
  let published = prepared.publish(path, limit)
  if published != AtomicFileError.None:
    return ApplicationCheckpointFileResult[ApplicationCheckpointIdentity](
        status: toApplicationCheckpointFileError(
        published)) # Possibly visible but unsynchronized publication remains payload-free.
  ApplicationCheckpointFileResult[ApplicationCheckpointIdentity](
      status: ApplicationCheckpointFileError.None, completed: prepared.identity)
proc saveApplicationCheckpoint*(path: string, owner: ApplicationChain,
    limit: ByteLimit): ApplicationCheckpointFileResult[ApplicationCheckpointIdentity] =
  ## Explicit synchronous source preparation retires all graph borrows before the native file replacement begins.
  var prepared = prepareApplicationCheckpoint(owner, limit)
  saveApplicationCheckpoint(path, prepared, limit)
proc restored(bytes: BoundedFileResult, expected: ApplicationCheckpointIdentity,
    limits: StateStoreLimits, limit: ByteLimit): ApplicationCheckpointFileResult[StateStore] =
  ## A bounded regular file must reach true EOF and checked close before codec-owned state allocation.
  if bytes.error != AtomicFileError.None:
    return ApplicationCheckpointFileResult[StateStore](status: toApplicationCheckpointFileError(bytes.error))
  let decoded = decodeApplicationCheckpoint(bytes.value, expected, limits, limit)
  case decoded.error
  of ApplicationCheckpointError.None:
    ApplicationCheckpointFileResult[StateStore](status: ApplicationCheckpointFileError.None,
        completed: decoded.value)
  of ApplicationCheckpointError.IdentityFailure:
    ApplicationCheckpointFileResult[StateStore](status: ApplicationCheckpointFileError.IdentityFailure,
        identityReason: decoded.identityError)
  of ApplicationCheckpointError.CheckpointFailure:
    ApplicationCheckpointFileResult[StateStore](status: ApplicationCheckpointFileError.CheckpointFailure,
        checkpointReason: decoded.checkpointError)
  of ApplicationCheckpointError.LimitExceeded:
    ApplicationCheckpointFileResult[StateStore](status: ApplicationCheckpointFileError.LimitExceeded)
  of ApplicationCheckpointError.ContextMismatch:
    ApplicationCheckpointFileResult[StateStore](status: ApplicationCheckpointFileError.ContextMismatch)
  of ApplicationCheckpointError.Uninitialized:
    default(ApplicationCheckpointFileResult[StateStore]) # An uninitialized internal decoder result cannot grant restored state.
proc loadApplicationCheckpoint*(path: string, expected: ApplicationCheckpointIdentity,
    limits: StateStoreLimits, limit: ByteLimit): ApplicationCheckpointFileResult[StateStore] =
  ## Missing independent context refuses before opening any path; file metadata is never promoted into trust.
  if not expected.ready:
    return ApplicationCheckpointFileResult[StateStore](
      status: ApplicationCheckpointFileError.IdentityFailure,
      identityReason: ApplicationCheckpointIdentityError.Uninitialized)
  restored(readBoundedFile(path, limit), expected, limits, limit)

proc saveApplicationCheckpoint*(writer: var AtomicFileWriter,
    prepared: PreparedApplicationCheckpoint, limit: ByteLimit): ApplicationCheckpointFileResult[
        ApplicationCheckpointIdentity] =
  ## The existing cooperative native owner serializes one whole-envelope publication without retaining application graphs.
  if prepared.error != ApplicationCheckpointError.None: return refused(prepared)
  let published = prepared.publish(writer, limit)
  if published != AtomicFileError.None:
    return ApplicationCheckpointFileResult[ApplicationCheckpointIdentity](
        status: toApplicationCheckpointFileError(published))
  ApplicationCheckpointFileResult[ApplicationCheckpointIdentity](
      status: ApplicationCheckpointFileError.None, completed: prepared.identity)
proc loadApplicationCheckpoint*(writer: var AtomicFileWriter,
    expected: ApplicationCheckpointIdentity,

limits: StateStoreLimits, limit: ByteLimit): ApplicationCheckpointFileResult[StateStore] =
  ## Require independent trust before any owner-path read, then share bounded EOF/checked-close and decode behavior.
  if not expected.ready:
    return ApplicationCheckpointFileResult[StateStore](
      status: ApplicationCheckpointFileError.IdentityFailure,
      identityReason: ApplicationCheckpointIdentityError.Uninitialized)
  restored(writer.read(limit), expected, limits, limit)

proc verified(loaded: ApplicationCheckpointFileResult[StateStore],
    expected: ApplicationCheckpointIdentity): ApplicationCheckpointFileResult[
    ApplicationCheckpointIdentity] =
  ## Complete restored state stays on its allocating caller thread; successful verification returns fixed matching context only.
  case loaded.error
  of ApplicationCheckpointFileError.None:
    ApplicationCheckpointFileResult[ApplicationCheckpointIdentity](
        status: ApplicationCheckpointFileError.None, completed: expected)
  of ApplicationCheckpointFileError.IdentityFailure:
    ApplicationCheckpointFileResult[ApplicationCheckpointIdentity](
        status: ApplicationCheckpointFileError.IdentityFailure,
        identityReason: loaded.identityError)
  of ApplicationCheckpointFileError.CheckpointFailure:
    ApplicationCheckpointFileResult[ApplicationCheckpointIdentity](
        status: ApplicationCheckpointFileError.CheckpointFailure,
        checkpointReason: loaded.checkpointError)
  else:
    ApplicationCheckpointFileResult[ApplicationCheckpointIdentity](
        status: loaded.error) # Native/budget/context refusals grant no verified context.
proc verifyApplicationCheckpoint*(path: string, expected: ApplicationCheckpointIdentity,
    limits: StateStoreLimits, limit: ByteLimit): ApplicationCheckpointFileResult[
        ApplicationCheckpointIdentity] =
  ## Verify bounded complete bytes against independent trust, retiring every decoded graph before returning scalar context.
  let loaded = loadApplicationCheckpoint(path, expected, limits, limit)
  verified(loaded, expected)
proc verifyApplicationCheckpoint*(writer: var AtomicFileWriter,
    expected: ApplicationCheckpointIdentity,

limits: StateStoreLimits, limit: ByteLimit): ApplicationCheckpointFileResult[
        ApplicationCheckpointIdentity] =
  ## Cooperative exclusion shares the same strict whole-envelope verifier without returning any decoded map owner.
  let loaded = loadApplicationCheckpoint(writer, expected, limits, limit)
  verified(loaded, expected)
