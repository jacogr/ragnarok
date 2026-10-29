# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_atomic_file_sync_arc_release"}

## Explicit recovery synchronization preserves bytes and native ownership, rejecting special files without blocking.

import std/[assertions, syncio]
import std/posix/posix
import ../../../src/lib/atomic/file as atomic_file
import ../../../src/lib/atomic/file/writer as atomic_file_writer
import ../../../src/codec/bounded
import ../../support/arc_evidence

proc makeFifo(path: cstring, mode: Mode): cint {.importc: "mkfifo", cdecl, header: "<sys/stat.h>".}
  ## Real FIFO creation uses the SDK API absent from the pinned public POSIX wrapper.

const FileName = "state-atomic-file-sync.bin"
proc cycle(writer: var AtomicFileWriter) =
  ## Repeated file/parent synchronization and real missing-file refusals retire all transient native paths/descriptors.
  assert writer.synchronize() == AtomicFileError.None
  assert syncAtomicFile("state-atomic-file-sync-missing.bin") == AtomicFileError.IoFailure
proc main() =
  ## Binary and empty regular files are preserved; no failure can fabricate a completed durability boundary.
  var path = FileName
  var lockPath = FileName & ".lock"
  var fifo = "state-atomic-file-sync.fifo"
  var missing = "state-atomic-file-sync-missing.bin"
  discard posix.unlink(missing.toCString())
  discard posix.unlink(fifo.toCString())
  defer:
    discard posix.unlink(path.toCString())
    discard posix.unlink(lockPath.toCString())
    discard posix.unlink(fifo.toCString()) # Test-owned namespace cleanup follows explicit native owner retirement below.
  var writer = default(AtomicFileWriter)
  defer: discard writer.close()
  assert writer.synchronize() == AtomicFileError.Uninitialized
  assert syncAtomicFile("") == AtomicFileError.InvalidPath
  assert syncAtomicFile("bad\0path") == AtomicFileError.InvalidPath
  assert syncAtomicFile(".") == AtomicFileError.IoFailure
  assert syncAtomicFile(missing) == AtomicFileError.IoFailure
  assert makeFifo(fifo.toCString(), Mode(0o600)) == 0
  assert syncAtomicFile(fifo) == AtomicFileError.IoFailure # Opening nonblocking plus kind validation cannot wait for a FIFO peer.
  assert writer.openAtomicFileWriter(FileName) == AtomicFileError.None
  assert writer.synchronize() == AtomicFileError.IoFailure # Lock ownership does not imply an existing destination.
  assert writer.replace([0'u8, 255, 9], ByteLimit(3)) == AtomicFileError.None
  assert writer.synchronize() == AtomicFileError.None
  assert writer.read(ByteLimit(3)).value == @[0'u8, 255, 9]
  assert syncAtomicFile(FileName) == AtomicFileError.None
  assert writer.read(ByteLimit(3)).value == @[0'u8, 255, 9] # Synchronization never rewrites the selected bytes.
  assert writer.replace([], ByteLimit(0)) == AtomicFileError.None
  assert writer.synchronize() == AtomicFileError.None
  assert writer.read(ByteLimit(0)).value.len == 0
  cycle(writer)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(writer) # Only transient resources retire; the stable cooperative owner remains active throughout.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_atomic_file_sync", 1000, before, after)
  assert writer.close() == AtomicFileError.None
  assert writer.synchronize() == AtomicFileError.Uninitialized
  echo "PASS file recovery sync: regular-file and parent durability, exact bytes and bounded native ownership"
main()
