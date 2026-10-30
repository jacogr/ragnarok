# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Sole-owner application envelope bytes detach all canonical graphs before any publication or I/O offload.
import ../chain
import ./[codec as checkpoint_codec, identity as checkpoint_identity]
import ../../state/checkpoint
import ../../codec/bounded
import ../../lib/atomic/file as atomic_file
import ../../lib/atomic/file/writer as atomic_file_writer

type PreparedApplicationCheckpoint* = object ## Only ready owners retain exact complete envelope bytes and fixed captured context.
  case status: ApplicationCheckpointError
  of None:
    bytes: seq[byte]
    context: ApplicationCheckpointIdentity
  of IdentityFailure:
    identityReason: ApplicationCheckpointIdentityError
  of CheckpointFailure:
    checkpointReason: CheckpointError
  else:
    discard # Default and failed preparation retain only selected reasons.

proc `=copy`*(destination: var PreparedApplicationCheckpoint,
    source: PreparedApplicationCheckpoint) {.error.}
  ## Encoded bytes must never acquire another implicit owner across an I/O boundary.

proc `=dup`*(source: PreparedApplicationCheckpoint): PreparedApplicationCheckpoint {.error.}
  ## Actual ARC lowering independently rejects implicit duplication.

proc `=wasMoved`*(prepared: var PreparedApplicationCheckpoint) {.nodestroy, inline.} =
  ## A moved source loses readiness without freeing the sole buffer now owned by its destination.
  prepared.status = ApplicationCheckpointError.Uninitialized

proc `=destroy`*(prepared: PreparedApplicationCheckpoint) =
  ## Only the active ready alternative owns managed bytes; context and reasons are fixed scalar data.
  if prepared.status == ApplicationCheckpointError.None:
    `=destroy`(prepared.bytes) # Retire the sole buffer exactly once.

func error*(prepared: PreparedApplicationCheckpoint): ApplicationCheckpointError =
  ## Inspect preparation without granting byte or context access.
  prepared.status

func identityError*(prepared: PreparedApplicationCheckpoint): ApplicationCheckpointIdentityError {.inline,
    requires: prepared.status == ApplicationCheckpointError.IdentityFailure.} =
  ## Only actual failed context capture/encoding carries this reason.
  prepared.identityReason

func checkpointError*(prepared: PreparedApplicationCheckpoint): CheckpointError {.inline,
    requires: prepared.status == ApplicationCheckpointError.CheckpointFailure.} =
  ## Only actual complete-map refusal carries this reason.
  prepared.checkpointReason

func identity*(prepared: PreparedApplicationCheckpoint): ApplicationCheckpointIdentity {.inline,
    requires: prepared.status == ApplicationCheckpointError.None.} =
  ## Copy fixed context without retaining a canonical map, header or history.
  prepared.context

func byteLength*(prepared: PreparedApplicationCheckpoint): int {.inline,
    requires: prepared.status == ApplicationCheckpointError.None.} =
  ## Observe bounded extent without exposing mutable or borrowed byte storage.
  prepared.bytes.len

proc prepareApplicationCheckpoint*(owner: ApplicationChain,
    limit: ByteLimit): PreparedApplicationCheckpoint =
  ## Synchronous preparation must run outside transport callbacks; only independent encoded bytes survive return.
  let encoded = encodeApplicationCheckpoint(owner, limit)
  case encoded.error
  of ApplicationCheckpointError.None:
    let identity = captureApplicationCheckpointIdentity(owner).value
    PreparedApplicationCheckpoint(status: ApplicationCheckpointError.None, bytes: encoded.value,
        context: identity)
  of ApplicationCheckpointError.IdentityFailure:
    PreparedApplicationCheckpoint(status: ApplicationCheckpointError.IdentityFailure,
        identityReason: encoded.identityError)
  of ApplicationCheckpointError.CheckpointFailure:
    PreparedApplicationCheckpoint(status: ApplicationCheckpointError.CheckpointFailure,
        checkpointReason: encoded.checkpointError)
  else:
    PreparedApplicationCheckpoint(status: encoded.error) # Refused extent/default inputs retain no buffer or graph.

proc publish*(prepared: PreparedApplicationCheckpoint, path: string,
    limit: ByteLimit): AtomicFileError =
  ## Borrow the sole complete bytes for existing durable single-file replacement; failed/moved owners never touch a path.
  if prepared.status != ApplicationCheckpointError.None: return AtomicFileError.Uninitialized
  replaceAtomicFile(path, prepared.bytes, limit)

proc publish*(prepared: PreparedApplicationCheckpoint, writer: var AtomicFileWriter,
    limit: ByteLimit): AtomicFileError =
  ## A cooperative raw owner supplies serialized publication without retaining a canonical application graph.
  if prepared.status != ApplicationCheckpointError.None: return AtomicFileError.Uninitialized
  writer.replace(prepared.bytes, limit)
