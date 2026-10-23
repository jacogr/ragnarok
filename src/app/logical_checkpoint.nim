# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Capture unchanged-format complete checkpoints only from the original producer retained by complete logical qualification.
import ../state/[current_logical, current_checkpoint]
import ../codec/bounded
type
  LogicalCheckpointError* {.pure.} = enum ## Default logical source and the exact existing checkpoint refusal remain distinct.
    Uninitialized, None, InvalidLogical, CheckpointFailure
  LogicalCheckpointResult* = object ## Only whole unchanged-format capture grants a retained original producer capsule.
    case status: LogicalCheckpointError
    of None: completed: CurrentUpdateCheckpoint
    of CheckpointFailure: checkpointReason: CurrentCheckpointResult[CurrentUpdateCheckpoint]
    else: discard # No default/refusal grants root, bytes or source authority.
func error*(outcome: LogicalCheckpointResult): LogicalCheckpointError =
  ## Observe the selected immutable stage without granting its payload.
  outcome.status
func value*(outcome: LogicalCheckpointResult): CurrentUpdateCheckpoint {.inline,
    requires: outcome.status == LogicalCheckpointError.None.} =
  ## Retain the original source-bound checkpoint; independent trust and adoption remain separate.
  outcome.completed
func checkpointFailure*(outcome: LogicalCheckpointResult): CurrentCheckpointResult[
    CurrentUpdateCheckpoint] {.inline, requires: outcome.status ==
    LogicalCheckpointError.CheckpointFailure.} =
  ## Preserve exact encoding, resource and original-source refusal causes.
  outcome.checkpointReason
proc captureLogicalCheckpoint*(source: CurrentLogicalState,
    limit: ByteLimit): LogicalCheckpointResult =
  ## Host-side original update extraction cannot substitute detached complete maps or headers; caller holds all ARC aliases outside native leases.
  let update = source.currentLogicalUpdate
  if update.error != CurrentLogicalError.None:
    return LogicalCheckpointResult(status: LogicalCheckpointError.InvalidLogical)
  let checkpoint = captureCurrentUpdateCheckpoint(update.value, limit)
  if checkpoint.error != CurrentCheckpointError.None:
    return LogicalCheckpointResult(status: LogicalCheckpointError.CheckpointFailure,
        checkpointReason: checkpoint)
  LogicalCheckpointResult(status: LogicalCheckpointError.None, completed: checkpoint.value)
