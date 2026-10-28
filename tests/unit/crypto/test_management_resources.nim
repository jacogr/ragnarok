# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "management_resources_arc_release"}

## Real filesystem accounting, incremental bounded scans, unavailable values and resource retirement.
import std/assertions
import std/syncio
import ../../support/testing_arc_evidence
include ../../../src/management/resources

proc processId(): cint {.importc: "getpid", header: "<unistd.h>".}
  ## Make fixture paths private to this native test process.
proc resizeFile(fd: cint, size: int64): cint {.importc: "ftruncate", header: "<unistd.h>".}
  ## A sparse fixture distinguishes logical database bytes from disk allocation.

var directory = "/tmp/ragnarok-resources-" & $processId()
assert mkdir(directory.toCString(), Mode(0o700)) == 0
var sparse = directory & "/journal"
let fd = posix.open(sparse.toCString(), O_CREAT or O_EXCL or O_WRONLY, Mode(0o600))
assert fd >= 0 and resizeFile(fd, 1048576) == 0
assert posix.close(fd) == 0
block single_file:
  var sampler = default(ResourceSampler)
  sampler.configure(sparse, directory)
  sampler.tick()
  assert sampler.databaseKnown and sampler.logical == 1048576 and sampler.files == 1
  assert sampler.allocated < sampler.logical # Sparse extents do not consume their entire logical length.
  assert sampler.memoryKnown and sampler.resident > 0
  assert sampler.diskKnown and sampler.available <= sampler.free and sampler.free <= sampler.total
  assert "\"residentBytes\":" in $sampler.snapshot()
  assert "\"logicalBytes\":1048576" in $sampler.snapshot()

# More than one turn's worth of entries proves incomplete scans never appear as empty databases.
for index in 0..<20:
  var path = directory & "/file-" & $index
  let file = posix.open(path.toCString(), O_CREAT or O_EXCL or O_WRONLY, Mode(0o600))
  assert file >= 0 and resizeFile(file, 3) == 0
  assert posix.close(file) == 0
block flat_directory:
  var sampler = default(ResourceSampler)
  sampler.configure(directory, directory)
  sampler.tick()
  assert sampler.directoryOpen and not sampler.databaseKnown
  assert "\"logicalBytes\":null" in $sampler.snapshot()
  sampler.tick()
  assert not sampler.directoryOpen and sampler.databaseKnown
  assert sampler.logical == 1048636 and sampler.files == 21
  sampler.close()
  sampler.close() # Repeated cleanup cannot close an unrelated descriptor.
block admission_limit:
  var sampler = default(ResourceSampler)
  sampler.configure(directory, directory)
  sampler.tick()
  sampler.scanCount = 4096 # An existing partial stream must refuse the next entry beyond the hard limit.
  sampler.tick()
  assert not sampler.directoryOpen and not sampler.databaseKnown
  assert sampler.databaseStatus == "entry-limit" and "\"logicalBytes\":null" in $sampler.snapshot()
block read_failure:
  var sampler = default(ResourceSampler)
  sampler.configure(directory, directory)
  sampler.tick()
  assert sampler.directoryOpen and not sampler.databaseKnown
  assert closeDirStream(sampler.directory) == 0 # Force a mid-scan read failure through the public API.
  sampler.tick()
  assert not sampler.directoryOpen and not sampler.databaseKnown
  assert sampler.databaseStatus == "unavailable" and "\"logicalBytes\":null" in $sampler.snapshot()
block missing:
  var sampler = default(ResourceSampler)
  sampler.configure(directory & "/missing", directory)
  sampler.tick()
  assert not sampler.databaseKnown and not sampler.diskKnown
  assert "\"freeBytes\":null" in $sampler.snapshot()
block memory_backend:
  var sampler = default(ResourceSampler)
  sampler.configure("", directory)
  sampler.tick()
  assert sampler.databaseKnown and not sampler.databaseEnabled and sampler.logical == 0
  assert sampler.diskKnown and "\"status\":\"memory\"" in $sampler.snapshot()
block overflow:
  var answer = 0'u64
  assert not product(high(uint64), 512, answer)
  var sampler = default(ResourceSampler)
  sampler.scanLogical = high(uint64)
  assert not sampler.countFile(FileStatus(st_size: 1, st_blocks: 0)) # No wrapped aggregate is published.

# Native directory ownership and dynamic strings retire even when a scan is abandoned midway.
let before = getOccupiedMem()
for cycle in 0..<1000:
  block abandon:
    var sampler = default(ResourceSampler)
    sampler.configure(directory, directory)
    sampler.tick()
    assert sampler.directoryOpen
let after = getOccupiedMem()
assert before == after
recordArcRelease("management_resources", 1000, before, after)

# A nested directory is an unsupported layout, not an uncounted zero-byte file.
var nested = directory & "/nested"
assert mkdir(nested.toCString(), Mode(0o700)) == 0
block unsupported:
  var sampler = default(ResourceSampler)
  sampler.configure(directory, directory)
  for turn in 0..<4: sampler.tick() # Finish this bounded fixture's stream across dispatcher turns.
  assert not sampler.databaseKnown and sampler.databaseStatus == "unsupported-layout"
assert rmdir(nested.toCString()) == 0
for index in 0..<20:
  var path = directory & "/file-" & $index
  assert unlink(path.toCString()) == 0
assert unlink(sparse.toCString()) == 0
assert rmdir(directory.toCString()) == 0

echo "Management resource tests passed"
