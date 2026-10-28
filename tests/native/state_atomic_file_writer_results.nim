# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Raw native ownership cannot leak read payloads or silently abandon a live cooperative lock.

import std/cmdline
import std/assertions
import std/posix/posix
import ../../src/lib/atomic_file_writer as lib_atomic_file_writer
import ../../src/lib/atomic_file as lib_atomic_file
import ../../src/codec/bounded as codec_bounded

proc forgotten() =
  ## A live raw resource reaches its own explicit-close destructor contract.
  var writer = default(AtomicFileWriter)
  assert writer.openAtomicFileWriter("build/state-atomic-file-writer-result.bin") ==
      AtomicFileError.None
proc main() =
  ## Real binary/empty controls validate the same owner used by default, closed and failed-read probes.
  let mode = paramStr(1)
  if mode == "unclosed":
    forgotten() # Process exit is not a substitute for the library's checked retirement obligation.
  else:
    var path = "build/state-atomic-file-writer-result.bin"
    var lockPath = path & ".lock"
    defer:
      discard posix.unlink(path.toCString())
      discard posix.unlink(lockPath.toCString()) # Cleanup follows explicit native owner retirement below.
    var writer = default(AtomicFileWriter)
    defer: discard writer.close()
    if mode == "default":
      discard writer.read(ByteLimit(100)).value # Default owners have no file payload.
    else:
      assert writer.openAtomicFileWriter(path) == AtomicFileError.None
      if mode == "missing":
        discard writer.read(ByteLimit(100)).value # Holding a lock does not make absent data exist.
      else:
        assert writer.replace([0'u8, 255], ByteLimit(2)) == AtomicFileError.None
        assert writer.read(ByteLimit(2)).value == @[0'u8, 255]
        assert writer.close() == AtomicFileError.None
        if mode == "closed":
          discard writer.read(ByteLimit(2)).value # Earlier success cannot authorize later closed-owner reads.
        else:
          assert not writer.opened # Genuine success retires every native handle before returning.
main()
