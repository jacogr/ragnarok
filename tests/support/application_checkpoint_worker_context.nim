# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared detached producers and bounded real-thread waits keep application worker tests independent of canonical graph lifetime.
import std/[assertions, monotimes, times]
import std/posix/posix
import ../../src/app/checkpoint/[worker as checkpoint_worker, transfer as checkpoint_transfer]
import ../../src/codec/bounded
import ./application_checkpoint_context
proc detachedApplicationCheckpoint*(variant = CheckpointFixtureVariant.Original): PreparedApplicationCheckpoint {.raises.} =
  ## Every source state/header/history owner retires before the sole encoded buffer returns.
  let owner = checkpointFixture(variant)
  prepareApplicationCheckpoint(owner, ByteLimit(100000))
proc waitApplicationCheckpoint*(worker: var ApplicationCheckpointWorker) =
  ## Tests yield under a monotonic deadline while production uses a condition-driven native thread.
  let started = getMonoTime()
  while worker.phase != ApplicationCheckpointWorkerPhase.Done:
    assert (getMonoTime() - started).inSeconds < 20, "application checkpoint worker deadline"
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # This is test-only scheduling, not a production latency guarantee.
