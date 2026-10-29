# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exclusive prepared full-map bytes detach disk publication from the source ARC graph.
## Prepare on a permitted computation/startup path, then transfer the sole buffer owner to an I/O worker.

import ../[checkpoint, store]
import ../../codec/bounded
import ../../codec/state/trie as state_trie
import ../../lib/atomic/file as atomic_file

type PreparedCheckpoint* = object ## Private tagged ownership permits no payload alias or implicit buffer duplication.
  case status: CheckpointError
  of None:
    payload: seq[byte]
    commitment: StateRoot
  else:
    discard # Default/refused preparation retains only its exact codec reason.

proc `=destroy`*(checkpoint: PreparedCheckpoint) =
  ## Only successful preparation owns a sequence requiring ARC retirement.
  if checkpoint.status == CheckpointError.None:
    `=destroy`(checkpoint.payload) # Failed/default alternatives have no byte storage to touch.
proc `=wasMoved`*(checkpoint: var PreparedCheckpoint) {.nodestroy, inline.} =
  ## Disarm the complete success tag after transfer without releasing the destination's sole buffer.
  checkpoint.status = CheckpointError.Uninitialized
proc `=copy`*(destination: var PreparedCheckpoint, source: PreparedCheckpoint) {.error.}
  ## An independent prepared owner must be created explicitly rather than silently aliasing queued bytes.
proc `=dup`*(source: PreparedCheckpoint): PreparedCheckpoint {.error.}
  ## Actual ARC lowering enforces exclusive transfer independently of result-access checks.
func error*(checkpoint: PreparedCheckpoint): CheckpointError =
  ## Preserve the exact codec failure without exposing a partial buffer or root.
  checkpoint.status
func root*(checkpoint: PreparedCheckpoint): StateRoot {.requires:
    checkpoint.status == CheckpointError.None.} =
  ## The scalar complete-root copy does not share the transferred ARC graph or establish chain authority.
  checkpoint.commitment
func byteLength*(checkpoint: PreparedCheckpoint): int {.requires:
    checkpoint.status == CheckpointError.None.} =
  ## Observe only the exact prepared extent, never its mutable sequence owner.
  checkpoint.payload.len
proc prepareFullCheckpoint*(snapshot: StateStoreSnapshot, limit: ByteLimit): PreparedCheckpoint =
  ## Own independent canonical bytes and the exact source root; no source snapshot alias survives this call.
  let encoded = encodeFullCheckpoint(snapshot, limit)
  if encoded.error != CheckpointError.None:
    return PreparedCheckpoint(status: encoded.error) # A refusal cannot carry a default successful root or prefix.
  PreparedCheckpoint(status: CheckpointError.None, payload: encoded.value,
    commitment: snapshot.commitment.root)
proc publish*(checkpoint: PreparedCheckpoint, path: string, limit: ByteLimit): AtomicFileError =
  ## Synchronously publish exact validated bytes without touching or retaining the original complete-map graph.
  if checkpoint.status != CheckpointError.None:
    return AtomicFileError.Uninitialized # Failed/default owners cannot authorize file I/O; inspect error for their exact codec refusal.
  replaceAtomicFile(path, checkpoint.payload, limit)
