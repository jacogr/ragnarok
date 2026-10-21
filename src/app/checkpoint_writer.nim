# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exclusive host-thread application checkpoint owner shares existing raw locks, durable replacement and bounded reads.
import ./[chain, checkpoint_identity, checkpoint_transfer, checkpoint_file]
import ../state/store
import ../codec/bounded
import ../lib/atomic_file_writer

type ApplicationCheckpointWriter* = object ## The copied destination and sole lock descriptor remain private in the native child.
  native: AtomicFileWriter
proc `=copy`*(destination: var ApplicationCheckpointWriter,
    source: ApplicationCheckpointWriter) {.error.}
  ## Composite ownership independently rejects duplicate native retirement obligations.
proc `=dup`*(source: ApplicationCheckpointWriter): ApplicationCheckpointWriter {.error.}
  ## Actual ARC lowering must reject copying even when the child is noncopyable.
proc `=destroy`*(writer: ApplicationCheckpointWriter) =
  ## Explicit close must retire the inherited cooperative lock before managed paths disappear.
  `=destroy`(writer.native)
func opened*(writer: ApplicationCheckpointWriter): bool =
  ## Observe lifecycle without exposing descriptors, mutable paths or the native child.
  writer.native.opened
proc openApplicationCheckpointWriter*(writer: var ApplicationCheckpointWriter,
    path: string): ApplicationCheckpointFileError =
  ## Startup deep-copies one destination and acquires the existing regular non-symlink lock inode.
  toApplicationCheckpointFileError(writer.native.openAtomicFileWriter(path))
proc close*(writer: var ApplicationCheckpointWriter): ApplicationCheckpointFileError =
  ## Idempotent explicit retirement disarms once and never unlinks the stable lock inode.
  toApplicationCheckpointFileError(writer.native.close())
proc save*(writer: var ApplicationCheckpointWriter, prepared: PreparedApplicationCheckpoint,
    limit: ByteLimit): ApplicationCheckpointFileResult[ApplicationCheckpointIdentity] =
  ## Prepared publication borrows independent bytes, retaining no canonical graph between calls.
  saveApplicationCheckpoint(writer.native, prepared, limit)
proc save*(writer: var ApplicationCheckpointWriter, owner: ApplicationChain,
    limit: ByteLimit): ApplicationCheckpointFileResult[ApplicationCheckpointIdentity] =
  ## Reject closed owners before synchronous preparation; callers schedule this computation outside callbacks.
  if not writer.opened: return default(ApplicationCheckpointFileResult[ApplicationCheckpointIdentity])
  var prepared = prepareApplicationCheckpoint(owner, limit)
  saveApplicationCheckpoint(writer.native, prepared, limit)
proc load*(writer: var ApplicationCheckpointWriter, expected: ApplicationCheckpointIdentity,
    limits: StateStoreLimits, limit: ByteLimit): ApplicationCheckpointFileResult[StateStore] =
  ## Full independent context and explicit recovered-store policy remain mandatory under the same lock.
  loadApplicationCheckpoint(writer.native, expected, limits, limit)

proc verify*(writer: var ApplicationCheckpointWriter, expected: ApplicationCheckpointIdentity,
    limits: StateStoreLimits, limit: ByteLimit): ApplicationCheckpointFileResult[
        ApplicationCheckpointIdentity] =
  ## Only fixed matching context escapes complete verification; all byte/map allocation retires on this calling thread.
  verifyApplicationCheckpoint(writer.native, expected, limits, limit)
