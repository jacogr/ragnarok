# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_atomic_file_writer_arc_release"}

## Cooperative raw ownership supports control records without fabricating complete JAM state.

import std/[assertions, syncio]
import std/posix/posix
import ../../../src/lib/[atomic_file_writer, atomic_file]
import ../../../src/codec/bounded
import ../../support/arc_evidence

const FileName = "state-atomic-file-writer.bin"
proc cycle() =
  ## Serial open/contend/close/reopen cycles retain one stable lock inode and no payload graph.
  var first = default(AtomicFileWriter)
  defer: discard first.close()
  var second = default(AtomicFileWriter)
  defer: discard second.close()
  assert first.openAtomicFileWriter(FileName) == AtomicFileError.None
  assert second.openAtomicFileWriter(FileName) == AtomicFileError.Busy
  assert first.close() == AtomicFileError.None
  assert second.openAtomicFileWriter(FileName) == AtomicFileError.None
  assert second.close() == AtomicFileError.None
proc main() =
  ## Exact raw binary/empty data, caller path mutation and refusal recovery remain independent of state format.
  var path = FileName
  var lockPath = FileName & ".lock"
  defer:
    discard posix.unlink(path.toCString())
    discard posix.unlink(lockPath.toCString()) # Only test-owned paths are removed after explicit owner retirement.
  var writer = default(AtomicFileWriter)
  defer: discard writer.close()
  assert not writer.opened
  assert writer.replace([], ByteLimit(0)) == AtomicFileError.Uninitialized
  assert writer.read(ByteLimit(0)).error == AtomicFileError.Uninitialized
  assert writer.openAtomicFileWriter("") == AtomicFileError.InvalidPath
  var source = FileName
  assert writer.openAtomicFileWriter(source) == AtomicFileError.None
  source[0] = 'x'
  assert writer.openAtomicFileWriter("other-raw-destination") == AtomicFileError.Busy
  let bytes = @[0'u8, 255, 7]
  assert writer.replace(bytes, ByteLimit(3)) == AtomicFileError.None
  assert writer.read(ByteLimit(3)).value == bytes
  assert readBoundedFile(FileName, ByteLimit(3)).value == bytes
  assert writer.replace(bytes, ByteLimit(2)) == AtomicFileError.LimitExceeded
  assert writer.read(ByteLimit(3)).value == bytes # A refused control record cannot truncate existing bytes or lose the lock.
  assert writer.replace([], ByteLimit(0)) == AtomicFileError.None
  assert writer.read(ByteLimit(0)).value.len == 0
  assert writer.close() == AtomicFileError.None
  assert writer.close() == AtomicFileError.None
  assert writer.read(ByteLimit(0)).error == AtomicFileError.Uninitialized
  assert writer.replace([], ByteLimit(0)) == AtomicFileError.Uninitialized
  cycle()
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle() # Managed path ownership and all descriptor retirement paths are host-only observations.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_atomic_file_writer", 1000, before, after)
  echo "PASS raw file writers: schema-independent locks, binary records and explicit ownership"
main()
