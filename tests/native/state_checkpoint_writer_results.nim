# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A writer must own its lock before payload extraction and explicitly retire before destruction.

import std/[cmdline, assertions]
import std/posix/posix
import ../../src/state/checkpoint/[writer as checkpoint_writer, file as checkpoint_file]
import ../../src/state/store
import ../../src/codec/bounded

proc forgotten() =
  ## Leaving a successfully opened owner active must reach the destructor's exact checked contract.
  var writer = default(CheckpointWriter)
  assert writer.openCheckpointWriter("build/state-checkpoint-writer-result.bin") ==
      CheckpointFileError.None
proc main() =
  ## The same executable provides real initialized success and default/closed extraction refusals.
  let mode = paramStr(1)
  if mode == "unclosed":
    forgotten() # A forgotten lock cannot silently outlive the owner's scope.
  else:
    var path = "build/state-checkpoint-writer-result.bin"
    var lockPath = path & ".lock"
    defer:
      discard posix.unlink(path.toCString())
      discard posix.unlink(lockPath.toCString()) # Generated lock cleanup follows explicit writer retirement below.
    var writer = default(CheckpointWriter)
    defer: discard writer.close()
    let snapshot = newStateStore([], default(StateStoreLimits)).value.snapshot.value
    if mode == "load-default":
      discard writer.load(snapshot.commitment.root, default(StateStoreLimits), ByteLimit(
          100)).value # A default owner has no authorized file payload.
    elif mode == "save-default":
      discard writer.save(snapshot, ByteLimit(100)).value # A default owner has no publication success.
    else:
      let opened = writer.openCheckpointWriter(path)
      assert opened == CheckpointFileError.None, "writer guard open " & $opened
      assert writer.save(snapshot, ByteLimit(100)).error == CheckpointFileError.None, "writer guard save"
      assert writer.load(snapshot.commitment.root, default(StateStoreLimits), ByteLimit(
          100)).error == CheckpointFileError.None
      assert writer.close() == CheckpointFileError.None, "writer guard close"
      if mode == "closed":
        discard writer.save(snapshot, ByteLimit(100)).value # Previously successful ownership cannot authorize later writes.
      else:
        assert not writer.opened # The positive control returns with every native lock retired.
main()
