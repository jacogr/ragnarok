# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authenticate unchanged-format detached full checkpoints against the independently selected original logical successor.
import ../../../state/current/logical as current_logical
import ../../../state/[checkpoint, store]
import ../../../codec/bounded
type
  ImportedLogicalCheckpoint* = object ## Original logical provenance and separately decoded physical ownership stay distinguishable.
    initialized: bool
    logical: CurrentLogicalState
    restored: StateStoreSnapshot
  LogicalCheckpointImportError* {.pure.} = enum ## Defaults and invalid logical owners grant no decoded map or producer prefix.
    Uninitialized, None, InvalidLogical, InvalidImport, CheckpointFailure
  LogicalCheckpointImportResult*[T] = object ## Only full independent-root authentication authorizes a detached import observation.
    case status: LogicalCheckpointImportError
    of None: completed: T
    of CheckpointFailure: checkpointReason: CheckpointError
    else: discard # No failed alternative exposes partially decoded physical ownership.
func error*[T](outcome: LogicalCheckpointImportResult[T]): LogicalCheckpointImportError =
  ## Observe the selected immutable stage without granting root or installation authority.
  outcome.status
func value*[T](outcome: LogicalCheckpointImportResult[T]): T {.inline, requires: outcome.status ==
    LogicalCheckpointImportError.None.} =
  ## Extract only complete independently authenticated imports and their original owner observations.
  outcome.completed
func checkpointError*[T](outcome: LogicalCheckpointImportResult[T]): CheckpointError {.inline,
    requires: outcome.status == LogicalCheckpointImportError.CheckpointFailure.} =
  ## Preserve exact structural, quota, root and primitive backend refusal causes.
  outcome.checkpointReason
proc importLogicalCheckpoint*(source: CurrentLogicalState, wire: openArray[byte],
    limits: StateStoreLimits, wireLimit: ByteLimit): LogicalCheckpointImportResult[
        ImportedLogicalCheckpoint] =
  ## Borrow stable bytes synchronously; the original qualified successor chooses the expected root independently of the envelope.
  let context = source.currentLogicalContext
  if context.error != CurrentLogicalError.None:
    return LogicalCheckpointImportResult[ImportedLogicalCheckpoint](
        status: LogicalCheckpointImportError.InvalidLogical)
  let decoded = decodeFullCheckpoint(wire, context.value.state.commitment.root, limits, wireLimit)
  if decoded.error != CheckpointError.None:
    return LogicalCheckpointImportResult[ImportedLogicalCheckpoint](
        status: LogicalCheckpointImportError.CheckpointFailure, checkpointReason: decoded.error)
  LogicalCheckpointImportResult[ImportedLogicalCheckpoint](
    status: LogicalCheckpointImportError.None,
    completed: ImportedLogicalCheckpoint(initialized: true, logical: source,
        restored: decoded.value.snapshot.value))
proc importedLogicalSource*(captured: ImportedLogicalCheckpoint): LogicalCheckpointImportResult[
    CurrentLogicalState] =
  ## Retain the original qualified logical owner; decoded equal-root maps cannot replace its producer identity.
  if not captured.initialized:
    return LogicalCheckpointImportResult[CurrentLogicalState](
        status: LogicalCheckpointImportError.InvalidImport)
  LogicalCheckpointImportResult[CurrentLogicalState](status: LogicalCheckpointImportError.None,
      completed: captured.logical)
proc importedLogicalSnapshot*(captured: ImportedLogicalCheckpoint): LogicalCheckpointImportResult[
    StateStoreSnapshot] =
  ## Observe the separately owned authenticated physical map without fabricating a current update or adopting it.
  if not captured.initialized:
    return LogicalCheckpointImportResult[StateStoreSnapshot](
        status: LogicalCheckpointImportError.InvalidImport)
  LogicalCheckpointImportResult[StateStoreSnapshot](status: LogicalCheckpointImportError.None,
      completed: captured.restored)
