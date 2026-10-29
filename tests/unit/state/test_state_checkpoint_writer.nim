# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_checkpoint_writer_arc_release"}

## Native stable-inode locks serialize independent owners and forked processes without retaining state aliases.

import std/[assertions, syncio]
import std/posix/posix
import ../../../src/state/checkpoint/[writer as checkpoint_writer, file as checkpoint_file]
import ../../../src/state/store
import ../../../src/codec/state/trie as state_trie
import ../../../src/codec/bounded
import ../../support/arc_evidence

proc setMask(mask: Mode): Mode {.importc: "umask", cdecl, header: "<sys/stat.h>".}
  ## The test chooses and restores its process-local creation mask for an exact permission witness.

const FileName = "state-checkpoint-writer.bin"
proc cycle() =
  ## Each isolated ownership cycle opens, contends, retires and reacquires the same persistent lock inode.
  var first = default(CheckpointWriter)
  defer: discard first.close()
  var second = default(CheckpointWriter)
  defer: discard second.close()
  assert first.openCheckpointWriter(FileName) == CheckpointFileError.None
  assert first.openCheckpointWriter("different-path") == CheckpointFileError.Busy
  assert second.openCheckpointWriter(FileName) == CheckpointFileError.Busy
  assert first.close() == CheckpointFileError.None
  assert not first.opened
  assert second.openCheckpointWriter(FileName) == CheckpointFileError.None
  assert second.close() == CheckpointFileError.None
  assert second.close() == CheckpointFileError.None
proc contention() =
  ## A separately opened child descriptor must not acquire the parent's inherited locked inode.
  var writer = default(CheckpointWriter)
  defer: discard writer.close()
  assert writer.openCheckpointWriter(FileName) == CheckpointFileError.None
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    var other = default(CheckpointWriter)
    let outcome = other.openCheckpointWriter(FileName)
    let retired = other.close()
    if outcome != CheckpointFileError.Busy or retired != CheckpointFileError.None:
      posix.exitnow(3) # Only real cross-process contention satisfies this witness.
    posix.exitnow(0) # Do not destruct copied parent owners; OS exit retires inherited descriptor references.
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var ignored = 0.cint
      discard posix.waitpid(child, ignored, 0) # All failed parent paths join the bounded child.
  var status = 0.cint
  assert posix.waitpid(child, status, 0) == child
  reaped = true
  assert WIFEXITED(status) and WEXITSTATUS(status) == 0
  assert writer.opened
  var waiting = default(CheckpointWriter)
  defer: discard waiting.close()
  assert waiting.openCheckpointWriter(FileName) == CheckpointFileError.Busy
  assert writer.close() == CheckpointFileError.None
  assert waiting.openCheckpointWriter(FileName) == CheckpointFileError.None
proc main() =
  ## Verify path ownership, guarded delegation, nonblocking contention, reopen and parent-only ARC release.
  let previousMask = setMask(Mode(0o077))
  defer: discard setMask(previousMask) # Other test processes and later caller operations retain their original policy.
  var path = FileName
  var lockPath = FileName & ".lock"
  defer:
    discard posix.unlink(path.toCString())
    discard posix.unlink(lockPath.toCString()) # Tests remove their lock inode only after every owner/child has retired.
  var writer = default(CheckpointWriter)
  defer: discard writer.close()
  assert not writer.opened
  assert writer.close() == CheckpointFileError.None
  assert writer.openCheckpointWriter("") == CheckpointFileError.InvalidPath
  assert writer.openCheckpointWriter("missing-parent/checkpoint") == CheckpointFileError.IoFailure
  var invalidPath = "xyz"
  invalidPath[1] = char(0)
  assert writer.openCheckpointWriter(invalidPath) == CheckpointFileError.InvalidPath
  let snapshot = newStateStore([], default(StateStoreLimits)).value.snapshot.value
  assert writer.save(snapshot, ByteLimit(100)).error == CheckpointFileError.Uninitialized
  assert writer.load(snapshot.commitment.root, default(StateStoreLimits), ByteLimit(100)).error ==
      CheckpointFileError.Uninitialized
  var source = FileName
  assert writer.openCheckpointWriter(source) == CheckpointFileError.None
  var metadata = default(Stat)
  assert posix.stat(lockPath.toCString(), metadata) == 0
  assert (metadata.st_mode and Mode(0o777)) == Mode(0o600), "exact SDK-created lock permissions"
  source[0] = 'x'
  assert writer.openCheckpointWriter("different-writer-destination") == CheckpointFileError.Busy
  assert writer.save(snapshot, ByteLimit(0)).error == CheckpointFileError.InvalidCheckpoint
  assert writer.opened
  assert writer.save(snapshot, ByteLimit(100)).error == CheckpointFileError.None
  assert writer.load(snapshot.commitment.root, default(StateStoreLimits), ByteLimit(100)).error ==
      CheckpointFileError.None
  assert loadFullCheckpoint(FileName, snapshot.commitment.root, default(StateStoreLimits),
      ByteLimit(100)).error == CheckpointFileError.None
  assert writer.close() == CheckpointFileError.None
  assert writer.save(snapshot, ByteLimit(100)).error == CheckpointFileError.Uninitialized
  contention()
  cycle()
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle() # Serial host-only observations follow joined cross-process tests; no cross-process allocator metric is claimed.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_checkpoint_writer", 1000, before, after)
  echo "PASS checkpoint writers: explicit lock ownership, process contention and guarded lifecycle"
main()
