# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_atomic_file_arc_release"}

## Raw byte publication supports checkpoint control metadata without inventing state or root authority.

import std/[assertions, syncio]
import std/posix/posix
import ../../../src/lib/atomic_file
import ../../../src/codec/bounded
import ../../support/arc_evidence

const FileName = "state-atomic-file.bin"
proc cycle(bytes: seq[byte]) =
  ## Each real synchronized replacement and refused short ceiling releases its temporary owners.
  assert replaceAtomicFile(FileName, bytes, ByteLimit(uint64(bytes.len))) == AtomicFileError.None
  assert replaceAtomicFile(FileName, bytes, ByteLimit(0)) == AtomicFileError.LimitExceeded
proc main() {.raises.} =
  ## Exact and empty byte payloads remain distinct from any higher-level checkpoint/header interpretation.
  var path = FileName
  var directory = "state-atomic-file-target"
  defer: discard posix.unlink(path.toCString()) # Only runner-owned generated data is removed after completion.
  discard posix.rmdir(directory.toCString())
  assert posix.mkdir(directory.toCString(), Mode(0o700)) == 0
  defer: discard posix.rmdir(directory.toCString()) # This real target forces post-write rename refusal.
  assert default(AtomicFileError) == AtomicFileError.Uninitialized
  assert replaceAtomicFile(FileName, [], ByteLimit(0)) == AtomicFileError.None
  assert readFile(FileName) == ""
  let bytes = @[0'u8, 255, 1, 0, 128]
  assert replaceAtomicFile(FileName, bytes, ByteLimit(5)) == AtomicFileError.None
  let actual = readFile(FileName)
  assert actual.len == bytes.len
  for index, octet in bytes:
    assert byte(actual[index]) == octet # Binary NUL/high octets are copied exactly, without text interpretation.
  assert replaceAtomicFile(FileName, bytes, ByteLimit(4)) == AtomicFileError.LimitExceeded
  assert readFile(FileName) == actual
  assert replaceAtomicFile("", bytes, ByteLimit(5)) == AtomicFileError.InvalidPath
  var invalid = "xyz"
  invalid[1] = char(0)
  assert replaceAtomicFile(invalid, bytes, ByteLimit(5)) == AtomicFileError.InvalidPath
  assert replaceAtomicFile("missing-parent/file", bytes, ByteLimit(5)) == AtomicFileError.IoFailure
  assert replaceAtomicFile(directory, bytes, ByteLimit(5)) == AtomicFileError.IoFailure
  assert readFile(FileName) == actual # Failed independent publications cannot truncate the existing complete file.
  cycle(bytes)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(bytes) # Each success performs real OS file and directory synchronization.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_atomic_file", 1000, before, after)
  echo "PASS atomic byte files: exact bounded payloads, durable replacement and rollback"
try:
  main() # Filesystem errors cannot satisfy the explicit success transcript.
except:
  quit(2)
