# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded management observations without retaining a database or canonical graph owner.
## Current process RSS and filesystem space are sampled once per second. Database sizes are
## sampled every ten seconds; flat directories advance by at most sixteen entries per turn.

import std/[strutils, monotimes]
import std/posix/posix
import ./file_status
import ../lib/json_writer

type
  VolumeInfo {.importc: "struct statvfs", header: "<sys/statvfs.h>", bycopy.} = object
    ## Native headers own layout; counts are checked before byte multiplication.
    f_frsize, f_blocks, f_bfree, f_bavail: uint64
  ResourceSampler* = object ## One private directory stream and copied scalar samples; no storage API aliases.
    directory: DirStream
    directoryOpen: bool
    nextMemory, nextDatabase, sampled: int64
    memoryKnown, diskKnown, databaseKnown, databaseEnabled: bool
    resident, heapOccupied, heapReserved: uint64
    total, free, available, logical, allocated, files: uint64
    scanLogical, scanAllocated, scanFiles: uint64
    scanCount: int
    filesystemPath, databasePath, databaseStatus: string

proc volumeStatus(path: cstring, info: var VolumeInfo): cint {.importc: "statvfs",
    header: "<sys/statvfs.h>".}
  ## Query one explicitly selected local filesystem; no directory traversal occurs.
when defined(macosx):
  type TaskMemory {.importc: "struct mach_task_basic_info", header: "<mach/mach.h>",
      bycopy.} = object
    ## Native task_info writes the complete header-defined object; only resident_size is inspected.
    resident_size: uint64
  proc currentTask(): cuint {.importc: "mach_task_self", header: "<mach/mach.h>".}
    ## Resolve the current process task without a foreign process handle.
  proc taskInfo(task: cuint, kind: cint, output: pointer,
      count: ptr cuint): cint {.importc: "task_info", header: "<mach/mach.h>".}
    ## Mach returns current resident bytes, rather than the lifetime peak from getrusage.
  let MemoryKind {.importc: "MACH_TASK_BASIC_INFO", header: "<mach/mach.h>".}: cint
  let MemoryCount {.importc: "MACH_TASK_BASIC_INFO_COUNT", header: "<mach/mach.h>".}: cuint
else:
  proc pageSize(): cint {.importc: "getpagesize", header: "<unistd.h>".}
    ## The OS page size converts procfs resident-page observations into bytes.

proc `=copy`*(destination: var ResourceSampler, source: ResourceSampler) {.error: "ResourceSampler owns a directory stream".}
  ## Copying would duplicate native stream cleanup authority.
proc `=dup`*(source: ResourceSampler): ResourceSampler {.error.}
  ## Implicit aggregate duplication is prohibited too.
proc `=destroy`*(sampler: ResourceSampler) =
  ## Directory scans may retire midway without retaining handles or strings.
  var directory = sampler.directory # A mutable copy lets this retiring owner call the public close API.
  discard closeDirStream(directory)
  `=destroy`(sampler.filesystemPath)
  `=destroy`(sampler.databasePath)
  `=destroy`(sampler.databaseStatus)

proc close*(sampler: var ResourceSampler) =
  ## Idempotent native stream retirement before an enclosing server is reused.
  discard closeDirStream(sampler.directory)
  sampler.directoryOpen = false

proc configure*(sampler: var ResourceSampler, database, fallback: string) =
  ## Memory backends have zero database disk usage; filesystem reporting still uses the management directory.
  sampler.close()
  sampler.databasePath = database
  sampler.filesystemPath = if database.len > 0: database else: fallback
  sampler.databaseEnabled = database.len > 0
  sampler.databaseKnown = database.len == 0
  sampler.databaseStatus = if database.len == 0: "memory" else: "pending"
  sampler.logical = 0; sampler.allocated = 0; sampler.files = 0
  sampler.nextMemory = 0; sampler.nextDatabase = 0

proc product(count, unit: uint64, output: var uint64): bool =
  ## Native counts may be malformed or enormous; never publish wrapping byte arithmetic.
  if unit == 0 or count > high(uint64) div unit: return false
  output = count * unit
  true

proc residentBytes(output: var uint64): bool =
  ## Return only a complete current-RSS observation; failure is not a zero-byte process.
  when defined(macosx):
    var memory = default(TaskMemory)
    var count = MemoryCount
    if taskInfo(currentTask(), MemoryKind, addr memory, addr count) != 0: return false
    output = memory.resident_size
    true
  elif defined(linux):
    let fd = posix.open("/proc/self/statm", O_RDONLY)
    if fd < 0: return false
    defer: discard posix.close(fd) # A bounded procfs read owns no persistent descriptor.
    var bytes = default(array[256, char])
    let length = posix.read(fd, addr bytes[0], bytes.len)
    if length <= 0 or length == bytes.len: return false
    var field = 0
    var pages = 0'u64
    var digits = 0
    for index in 0..<length:
      let c = bytes[index]
      if c == ' ':
        if field == 1: break # Only the second procfs field is resident-page count.
        inc field
      elif field == 1:
        if c notin {'0'..'9'}: return false
        let digit = uint64(ord(c) - ord('0'))
        if pages > (high(uint64) - digit) div 10: return false
        pages = pages * 10 + digit
        inc digits
    let size = pageSize()
    if digits == 0 or size <= 0: return false # Validate before unsigned conversion or any output mutation.
    result = product(pages, uint64(size), output) # Explicit result assignment avoids deferred expression lowering.
  else:
    false # Unsupported platforms expose null rather than substituting peak RSS.

proc failScan(sampler: var ResourceSampler, reason: string) =
  ## Failed/oversized/non-flat scans expose no plausible partial database total.
  sampler.close()
  sampler.databaseKnown = false
  sampler.databaseStatus = reason

proc countFile(sampler: var ResourceSampler, status: FileStatus): bool =
  ## Sum observed logical and allocated file extents after proving every multiply and addition.
  if status.st_size < 0 or status.st_blocks < 0: return false
  var allocated = 0'u64
  if not product(uint64(status.st_blocks), 512, allocated): return false
  let logical = uint64(status.st_size)
  if logical > high(uint64) - sampler.scanLogical or allocated > high(uint64) -
      sampler.scanAllocated:
    return false # No wrapped size reaches an admin response.
  sampler.scanLogical += logical
  sampler.scanAllocated += allocated
  inc sampler.scanFiles
  true

proc finishScan(sampler: var ResourceSampler, now: int64) =
  ## Publish one completed observational scan; this is not a transactional database snapshot.
  sampler.close()
  sampler.logical = sampler.scanLogical
  sampler.allocated = sampler.scanAllocated
  sampler.files = sampler.scanFiles
  sampler.sampled = now
  sampler.databaseKnown = true
  sampler.databaseStatus = "ready"

proc tick*(sampler: var ResourceSampler) =
  ## Bounded local metadata work runs outside HTTP dispatch and never touches leased database owners.
  let now = getMonoTime().ticks div 1_000_000
  if now >= sampler.nextMemory:
    sampler.nextMemory = now + 1000
    sampler.memoryKnown = residentBytes(sampler.resident)
    sampler.heapOccupied = uint64(getOccupiedMem()) # Pinned allocator counters belong to the dispatcher thread only.
    sampler.heapReserved = uint64(getTotalMem())
    var volume = default(VolumeInfo)
    sampler.diskKnown = volumeStatus(sampler.filesystemPath.toCString(), volume) == 0
    if sampler.diskKnown:
      sampler.diskKnown = product(volume.f_blocks, volume.f_frsize, sampler.total) and
        product(volume.f_bfree, volume.f_frsize, sampler.free) and
        product(volume.f_bavail, volume.f_frsize, sampler.available)
  if sampler.databaseEnabled and not sampler.directoryOpen and now >= sampler.nextDatabase:
    sampler.nextDatabase = now + 10000
    sampler.scanLogical = 0; sampler.scanAllocated = 0; sampler.scanFiles = 0; sampler.scanCount = 0
    var status = default(FileStatus)
    if readStatus(sampler.databasePath.toCString(), status) != 0:
      sampler.failScan("unavailable") # Missing/changing databases do not look empty.
    elif S_ISREG(Mode(status.st_mode)):
      if sampler.countFile(status): sampler.finishScan(now) # Journal layout is one explicitly selected file.
      else: sampler.failScan("overflow")
    elif S_ISDIR(Mode(status.st_mode)):
      sampler.directoryOpen = openDirStream(sampler.directory, sampler.databasePath.toCString()) == 0
      if not sampler.directoryOpen: sampler.failScan("unavailable")
      else: sampler.databaseStatus = "sampling" # An older completed sample remains labelled by its age.
    else: sampler.failScan("unsupported-layout") # Symlinks/devices are never followed as database roots.
  for step in 0..<16:
    if sampler.directoryOpen:
      var entryName: cstring = ""
      var entryType: uint8 = 0
      let entry = nextDirEntry(sampler.directory, entryName, entryType)
      if entry == 0:
        sampler.finishScan(now) # Only successful EOF publishes a complete total.
      elif entry < 0:
        sampler.failScan("unavailable")
      elif sampler.scanCount == 4096:
        sampler.failScan("entry-limit") # A large directory cannot monopolize the dispatcher indefinitely.
      else:
        inc sampler.scanCount
        let name = $entryName # The public stream API supplies a terminated name valid until the next entry.
        if name notin [".", ".."]:
          var status = default(FileStatus)
          var child = sampler.databasePath & "/" & name
          if readStatus(child.toCString(), status) != 0:
            sampler.failScan("unavailable")
          elif not S_ISREG(Mode(status.st_mode)):
            sampler.failScan("unsupported-layout") # Managed layout is flat; recursive partial totals are not invented.
          elif not sampler.countFile(status): sampler.failScan("overflow")

proc snapshot*(sampler: ResourceSampler): JsonValue =
  ## Null marks failed or pending measurements; byte fields have explicit scopes and sampling age.
  let age = max(0'i64, getMonoTime().ticks div 1_000_000 - sampler.sampled)
  let database = jsonObject([("enabled", json(sampler.databaseEnabled)),
    ("status", json(sampler.databaseStatus)),
    ("logicalBytes", if sampler.databaseKnown: json(sampler.logical) else: jsonNull()),
    ("allocatedBytes", if sampler.databaseKnown: json(sampler.allocated) else: jsonNull()),
    ("files", if sampler.databaseKnown: json(sampler.files) else: jsonNull()),
    ("sampleAgeMs", if sampler.databaseKnown and sampler.databaseEnabled: json(age) else: jsonNull())])
  jsonObject([("memory", jsonObject([
    ("residentBytes", if sampler.memoryKnown: json(sampler.resident) else: jsonNull()),
    ("dispatcherHeapOccupiedBytes", json(sampler.heapOccupied)),
    ("dispatcherHeapReservedBytes", json(sampler.heapReserved))])),
    ("filesystem", jsonObject([("path", json(sampler.filesystemPath)),
      ("totalBytes", if sampler.diskKnown: json(sampler.total) else: jsonNull()),
      ("freeBytes", if sampler.diskKnown: json(sampler.free) else: jsonNull()),
      ("availableBytes", if sampler.diskKnown: json(sampler.available) else: jsonNull())])),
    ("database", database)])
