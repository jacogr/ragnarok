# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Full-state checkpoint ownership delegates native locking to a mode-independent raw file owner.
## Typed state encoding and independently trusted roots remain at the state adapter boundary.

import ../../lib/atomic/file/writer as atomic_file_writer
import ./file as checkpoint_file
import ../store
import ../../codec/bounded
import ../../codec/state/trie as state_trie

type CheckpointWriter* = object ## Exclusive composite owns its native child; callers cannot bypass full-state adapters.
  native: AtomicFileWriter

proc `=copy`*(destination: var CheckpointWriter, source: CheckpointWriter) {.error.}
  ## Composite state owners must reject duplication independently of their field's hook lifting.
proc `=dup`*(source: CheckpointWriter): CheckpointWriter {.error.}
  ## Actual ARC lowering checks the state-facing resource contract too.
proc `=wasMoved`*(writer: var CheckpointWriter) {.nodestroy, inline.} =
  ## Disarm transferred fields through their own move hooks; never destroy the destination resources.
  `=wasMoved`(writer.native)

proc `=destroy`*(writer: CheckpointWriter) =
  ## The child's checked destruction requires explicit close and retires its managed path bytes.
  `=destroy`(writer.native)
func opened*(writer: CheckpointWriter): bool =
  ## Read only native ownership, never its descriptor/path or a canonical state alias.
  writer.native.opened
proc openCheckpointWriter*(writer: var CheckpointWriter, path: string): CheckpointFileError =
  ## Acquire the shared cooperative lock namespace without changing full-state startup semantics.
  toCheckpointFileError(writer.native.openAtomicFileWriter(path))
proc close*(writer: var CheckpointWriter): CheckpointFileError =
  ## Explicit child retirement preserves idempotence and every native close outcome.
  toCheckpointFileError(writer.native.close())
proc save*(writer: var CheckpointWriter, snapshot: StateStoreSnapshot,
    limit: ByteLimit): CheckpointFileResult[StateStoreSnapshot] =
  ## A raw file owner cannot bypass complete-state format validation or durable-success extraction.
  saveFullCheckpoint(writer.native, snapshot, limit)
proc load*(writer: var CheckpointWriter, expected: StateRoot, limits: StateStoreLimits,
    limit: ByteLimit): CheckpointFileResult[StateStore] =
  ## Every state-facing owner read retains the independently trusted complete-root requirement.
  loadFullCheckpoint(writer.native, expected, limits, limit)
