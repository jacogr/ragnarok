# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual managed regular files exercise empty, exact chunk, tail and configured read ceilings.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/storage_io
import ../../../src/storage/[managed_io, managed_manifest, file_errors]
import ../../../src/codec/bounded

proc scenario(size: int) {.raises.} =
  ## Every detached byte survives repeated short reads and preserves the selected inode's contents.
  resetIo()
  var path = "storage-read-buffer-" & $size & "-" & $int(storageProcessId())
  var directory = default(ManagedDirectory)
  assert initializeManagedDirectory(directory, path) == FileError.None
  var source = newSeq[byte](size)
  for index in 0..<source.len:
    source[index] = byte(index mod 251) # Distinguish every partial chunk and final boundary byte.
  let epoch = ManagedEpoch(1)
  assert createManagedFile(directory, ManagedFileKind.Snapshot, epoch, source,
    ByteLimit(uint64(size))) == FileError.None
  for chunk in [1, 7, 4096]:
    resetIo()
    limitReads(csize_t(chunk))
    var loaded = readManagedFile(directory, ManagedFileKind.Snapshot, epoch, ByteLimit(uint64(size)))
    assert loaded.error == FileError.None
    let bytes = loaded.value
    assert bytes == source
    if size > 0:
      var copied = loaded.value
      copied[0] = copied[0] xor 255'u8
      assert loaded.value == source # Public copy access remains detached and leaves its owner intact.
    let occupied = getOccupiedMem()
    var owned = loaded.takeValue
    assert loaded.error == FileError.Uninitialized
    assert getOccupiedMem() == occupied and owned == source
    if owned.len > 0:
      owned[0] = owned[0] xor 255'u8 # Transferred bytes remain private from the authored source buffer.
      assert source[0] == 0
  resetIo()
  if size > 0:
    let refused = readManagedFile(directory, ManagedFileKind.Snapshot, epoch,
      ByteLimit(uint64(size-1)))
    assert refused.error == FileError.LimitExceeded and ioCalls(readIo) == 0
  assert removeManagedFile(directory, ManagedFileKind.Snapshot, epoch) == FileError.None
  assert directory.close == FileError.None
  var lock = path & "/LOCK"
  assert posix.unlink(lock.toCString()) == 0 and posix.rmdir(path.toCString()) == 0

try:
  for size in [0, 1, 4095, 4096, 4097, 16384]:
    scenario(size) # Real descriptors and injected short progress retain the ordinary native read ABI.
except:
  quit(2)
echo "PASS storage read buffers: exact bytes, short progress, empty files and independent copies"
