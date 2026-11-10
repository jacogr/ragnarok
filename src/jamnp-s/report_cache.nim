# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded main-thread retention of complete hash-checked reports, independent of canonical state graphs.
## Cached content has no guarantee, execution, availability or judgment authority.

import std/assertions
import ./[read_stream, read_validation]
import ../chain/reports

const MaxCachedReports* = 64 ## Fixed row capacity, independent of untrusted peer/report counts.
const MaxReportCacheBytes* = 2*1024*1024 ## Logical framed bytes retained after insertion; allocator/transient copies are separate.
const MaxCachedReportBytes* = 64*1024 ## Local per-entry policy never widens ordinary request/reply limits.

type
  ReportCacheError* {.pure.} = enum ## Default/miss/refusal never exposes cached bytes or a report prefix.
    Uninitialized, None, Missing, InvalidReport, LimitExceeded, Exhausted, BackendFailure
  ReportCacheResult* = object ## Complete success alone carries a request-bound frozen reply.
    case status: ReportCacheError
    of None: completed: ReadReply
    else: discard             # Failed lookup has no accepted owner.
  CacheEntry = object ## Private immutable reply bytes accompany fixed identity and main-thread replacement age.
    used: bool
    identity: array[32, byte]
    age: uint64
    reply: ReadReply
  ReportCache* = object ## Default is an empty bounded value owner; no native handles, map aliases or borrowed workers exist here.
    entries: seq[CacheEntry]
    count, bytes: int
    next: uint64

func error*(outcome: ReportCacheResult): ReportCacheError =
  ## Observe a miss without extracting an empty successful reply.
  outcome.status

func value*(outcome: ReportCacheResult): ReadReply {.requires: outcome.status ==
    ReportCacheError.None.} =
  ## Frozen request facts still require a live exact node read ticket before sending.
  outcome.completed

func len*(cache: ReportCache): int =
  ## Scalar capacity observation never accesses a worker-owned graph.
  cache.count

func byteLength*(cache: ReportCache): int =
  ## Count logical framed bytes, including each E4 prefix.
  cache.bytes

proc clear*(cache: var ReportCache) =
  ## Retire all detached owners; replacement generations have no externally exposed ticket authority.
  cache = default(ReportCache)

proc identity(request: ReadRequest): array[32, byte] {.requires: request.valid and request.kind ==
    ReadKind.Report.} =
  ## Complete fixed requests provide exactly one full report hash.
  let payload = request.payload
  result = default(array[32, byte])
  for index in 0..<32: result[index] = payload[index]

proc removeOldest(cache: var ReportCache) =
  ## One bounded scan removes the least recently inserted/accessed owner before retaining the replacement.
  var oldest = -1
  for index in 0..<cache.entries.len:
    if cache.entries[index].used:
      if oldest < 0 or cache.entries[index].age < cache.entries[oldest].age: oldest = index
  assert oldest >= 0 and cache.count > 0
  cache.bytes -= cache.entries[oldest].reply.byteLength
  dec cache.count
  cache.entries[oldest] = default(CacheEntry)

proc remember*(cache: var ReportCache, checked: CheckedReadReply): ReportCacheError =
  ## Only a complete sealed verifier result can enter retention; peer bytes and guessed hashes cannot populate it directly.
  if not checked.valid: return ReportCacheError.InvalidReport
  if checked.kind != ReadKind.Report: return ReportCacheError.InvalidReport
  if cache.next == high(uint64): return ReportCacheError.Exhausted
  let hash = identity(checked.request)
  for index in 0..<cache.entries.len:
    if cache.entries[index].used and cache.entries[index].identity == hash:
      inc cache.next
      cache.entries[index].age = cache.next
      return ReportCacheError.None # Duplicate content neither allocates another reply nor consumes capacity.
  let report = checked.workReport
  let metadata = ownedReportInfo(report)
  if metadata.error != OwnershipError.None: return ReportCacheError.InvalidReport
  let size = metadata.value.consumed
  if size <= 0 or size > MaxCachedReportBytes-4: return ReportCacheError.LimitExceeded
  var wire = newSeq[byte](size+4)
  for index in 0..<4: wire[index] = byte((uint32(size) shr (8*index)) and 255)
  let encoded = encodeOwnedReport(report, wire.toOpenArray(4, wire.len-1))
  if encoded.error != OwnershipError.None or encoded.value !=
      size: return ReportCacheError.BackendFailure
  let frozen = captureReadReply(checked.request, wire)
  if frozen.error != ReadError.None: return ReportCacheError.BackendFailure
  while cache.count >= MaxCachedReports or cache.bytes > MaxReportCacheBytes-wire.len:
    cache.removeOldest() # Private invariant guarantees a nonempty victim whenever capacity/bytes need reclamation.
  if cache.entries.len == 0:
    cache.entries = newSeq[CacheEntry](MaxCachedReports) # Allocate bounded slots only on the first accepted report.
  var position = -1
  for index in 0..<cache.entries.len:
    if not cache.entries[index].used:
      position = index
      break
  assert position >= 0
  inc cache.next
  cache.entries[position] = CacheEntry(used: true, identity: hash, age: cache.next,
      reply: frozen.value)
  inc cache.count
  cache.bytes += wire.len
  ReportCacheError.None

proc find*(cache: var ReportCache, request: ReadRequest): ReportCacheResult =
  ## Full method/hash binding protects both lookup and later native response matching.
  if not request.valid: return ReportCacheResult(status: ReportCacheError.InvalidReport)
  if request.kind != ReadKind.Report: return ReportCacheResult(
      status: ReportCacheError.InvalidReport)
  let hash = identity(request)
  for index in 0..<cache.entries.len:
    if cache.entries[index].used and cache.entries[index].identity == hash:
      if cache.next < high(uint64):
        inc cache.next
        cache.entries[index].age = cache.next # Exhausted age space does not invalidate already checked retained content.
      return ReportCacheResult(status: ReportCacheError.None, completed: cache.entries[index].reply)
  ReportCacheResult(status: ReportCacheError.Missing)
