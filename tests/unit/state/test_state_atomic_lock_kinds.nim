# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_atomic_lock_kinds_arc_release"}

## Advisory ownership requires a regular non-symlink lock inode and never waits on a special-file peer.

import std/[assertions, syncio]
import std/posix/posix
import ../../../src/lib/atomic/file as atomic_file
import ../../../src/lib/atomic/file/writer as atomic_file_writer
import ../../../src/codec/bounded
import ../../support/arc_evidence

proc makeFifo(path: cstring, mode: Mode): cint {.importc: "mkfifo", cdecl, header: "<sys/stat.h>".}
  ## The real SDK FIFO API is absent from the pinned public POSIX wrapper.
const FileName = "state-atomic-lock-kinds.bin"
proc cycle(fifoPath: string) =
  ## Real special-file refusals leave no live ownership or retained destination bytes.
  var owner = default(AtomicFileWriter)
  assert owner.openAtomicFileWriter(fifoPath) == AtomicFileError.IoFailure
  assert not owner.opened
  assert owner.close() == AtomicFileError.None
proc main() =
  ## Every refused inode kind remains intact; removing it permits ordinary exclusive 0600 lock creation.
  var path = FileName
  var lockPath = path & ".lock"
  var target = "state-atomic-lock-target.bin"
  var fifoBase = "state-atomic-lock-fifo.bin"
  var fifoLock = fifoBase & ".lock"
  discard posix.unlink(lockPath.toCString())
  discard posix.unlink(fifoLock.toCString())
  defer:
    discard posix.unlink(path.toCString())
    discard posix.unlink(lockPath.toCString())
    discard posix.rmdir(lockPath.toCString())
    discard posix.unlink(target.toCString())
    discard posix.unlink(fifoLock.toCString()) # Test-only cleanup follows explicit retirement of every native owner below.
  var owner = default(AtomicFileWriter)
  defer: discard owner.close()
  assert makeFifo(lockPath.toCString(), Mode(0o600)) == 0
  assert owner.openAtomicFileWriter(FileName) == AtomicFileError.IoFailure
  assert not owner.opened
  var metadata = default(Stat)
  assert posix.lstat(lockPath.toCString(), metadata) == 0 and S_ISFIFO(
      metadata.st_mode) # Refusal cannot unlink or replace the existing special inode.
  assert posix.unlink(lockPath.toCString()) == 0
  assert posix.mkdir(lockPath.toCString(), Mode(0o700)) == 0
  assert owner.openAtomicFileWriter(FileName) == AtomicFileError.IoFailure
  assert posix.rmdir(lockPath.toCString()) == 0
  assert replaceAtomicFile(target, [7'u8], ByteLimit(1)) == AtomicFileError.None
  assert posix.symlink(target.toCString(), lockPath.toCString()) == 0
  assert owner.openAtomicFileWriter(FileName) == AtomicFileError.IoFailure
  assert readBoundedFile(target, ByteLimit(1)).value == @[
      7'u8] # An existing symlink target cannot be locked or mutated through the lock path.
  assert posix.unlink(lockPath.toCString()) == 0
  var absent = "state-atomic-lock-missing-target.bin"
  discard posix.unlink(absent.toCString())
  assert posix.symlink(absent.toCString(), lockPath.toCString()) == 0
  assert owner.openAtomicFileWriter(FileName) == AtomicFileError.IoFailure
  assert readBoundedFile(absent, ByteLimit(0)).error ==
      AtomicFileError.IoFailure # Creation must not follow a dangling lock symlink to a new target.
  assert posix.unlink(lockPath.toCString()) == 0
  assert owner.openAtomicFileWriter(FileName) == AtomicFileError.None
  var contender = default(AtomicFileWriter)
  defer: discard contender.close()
  assert contender.openAtomicFileWriter(FileName) == AtomicFileError.Busy
  assert owner.close() == AtomicFileError.None
  assert contender.openAtomicFileWriter(FileName) == AtomicFileError.None
  assert contender.close() == AtomicFileError.None
  assert makeFifo(fifoLock.toCString(), Mode(0o600)) == 0
  cycle(fifoBase)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(fifoBase) # Each nonblocking special-file open must close before failure returns.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_atomic_lock_kinds", 1000, before, after)
  echo "PASS lock inode admission: nonblocking FIFO refusal, no symlink following and regular ownership"
main()
