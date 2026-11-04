# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded main-thread retention of complete hash-checked preimages, independent of canonical state graphs.
## Cached content has no guarantee, execution, availability or judgment authority.
import std/assertions
import ./[read_stream, read_validation]


const MaxCachedPreimages* = 8 ## Fixed row capacity, independent of untrusted peer/preimage counts.
const MaxPreimageCacheBytes* = 32*1024*1024 ## Logical framed bytes retained after insertion; allocator/transient copies are separate.
const MaxCachedPreimageBytes* = MaxReadReplyBytes ## Local per-entry policy never widens ordinary request/reply limits.

type
  PreimageCacheError* {.pure.} = enum ## Default/miss/refusal never exposes cached bytes or a preimage prefix.
    Uninitialized, None, Missing, InvalidPreimage, LimitExceeded, Exhausted, BackendFailure
  PreimageCacheResult* = object ## Complete success alone carries a request-bound frozen reply.
    case status: PreimageCacheError
    of None: completed: ReadReply
    else: discard               # Failed lookup has no accepted owner.
  CacheEntry = object ## Private immutable reply bytes accompany fixed identity and main-thread replacement age.
    used: bool
    identity: array[32, byte]
    age: uint64
    reply: ReadReply
  PreimageCache* = object ## Default is an empty bounded value owner; no native handles, map aliases or borrowed workers exist here.
    entries: array[MaxCachedPreimages, CacheEntry]
    count, bytes: int
    next: uint64

func error*(outcome: PreimageCacheResult): PreimageCacheError =
  ## Observe a miss without extracting an empty successful reply.
  outcome.status
func value*(outcome: PreimageCacheResult): ReadReply {.requires: outcome.status ==
    PreimageCacheError.None.} =
  ## Frozen request facts still require a live exact node read ticket before sending.
  outcome.completed
func len*(cache: PreimageCache): int =
  ## Scalar capacity observation never accesses a worker-owned graph.
  cache.count
func byteLength*(cache: PreimageCache): int =
  ## Count logical framed bytes, including each E4 prefix.
  cache.bytes
proc clear*(cache: var PreimageCache) =
  ## Retire all detached owners; replacement generations have no externally exposed ticket authority.
  cache = default(PreimageCache)
proc identity(request: ReadRequest): array[32, byte] {.requires: request.valid and request.kind ==
    ReadKind.Preimage.} =
  ## Complete fixed requests provide exactly one full preimage hash.
  let payload = request.payload
  result = default(array[32, byte])
  for index in 0..<32: result[index] = payload[index]
proc removeOldest(cache: var PreimageCache) =
  ## One bounded scan removes the least recently inserted/accessed owner before retaining the replacement.
  var oldest = -1
  for index in 0..<MaxCachedPreimages:
    if cache.entries[index].used:
      if oldest < 0 or cache.entries[index].age < cache.entries[oldest].age: oldest = index
  assert oldest >= 0 and cache.count > 0
  cache.bytes -= cache.entries[oldest].reply.byteLength
  dec cache.count
  cache.entries[oldest] = default(CacheEntry)
proc remember*(cache: var PreimageCache, checked: CheckedReadReply): PreimageCacheError =
  ## Only a complete sealed verifier result can enter retention; peer bytes and guessed hashes cannot populate it directly.
  if not checked.valid: return PreimageCacheError.InvalidPreimage
  if checked.kind != ReadKind.Preimage: return PreimageCacheError.InvalidPreimage
  if cache.next == high(uint64): return PreimageCacheError.Exhausted
  let hash = identity(checked.request)
  for index in 0..<MaxCachedPreimages:
    if cache.entries[index].used and cache.entries[index].identity == hash:
      inc cache.next
      cache.entries[index].age = cache.next
      return PreimageCacheError.None # Duplicate content neither allocates another reply nor consumes capacity.
  let size = checked.preimageByteLength
  if size > MaxCachedPreimageBytes-4: return PreimageCacheError.LimitExceeded
  let body = checked.preimageBytes
  var wire = newSeq[byte](size+4)
  for index in 0..<4: wire[index] = byte((uint32(size) shr (8*index)) and 255)
  for index in 0..<body.len: wire[4+index] = body[index]
  let frozen = captureReadReply(checked.request, wire)
  if frozen.error != ReadError.None: return PreimageCacheError.BackendFailure
  while cache.count >= MaxCachedPreimages or cache.bytes > MaxPreimageCacheBytes-wire.len:
    cache.removeOldest() # Private invariant guarantees a nonempty victim whenever capacity/bytes need reclamation.
  var position = -1
  for index in 0..<MaxCachedPreimages:
    if not cache.entries[index].used:
      position = index
      break
  assert position >= 0
  inc cache.next
  cache.entries[position] = CacheEntry(used: true, identity: hash, age: cache.next,
      reply: frozen.value)
  inc cache.count
  cache.bytes += wire.len
  PreimageCacheError.None
proc find*(cache: var PreimageCache, request: ReadRequest): PreimageCacheResult =
  ## Full method/hash binding protects both lookup and later native response matching.
  if not request.valid: return PreimageCacheResult(status: PreimageCacheError.InvalidPreimage)
  if request.kind != ReadKind.Preimage: return PreimageCacheResult(
      status: PreimageCacheError.InvalidPreimage)
  let hash = identity(request)
  for index in 0..<MaxCachedPreimages:
    if cache.entries[index].used and cache.entries[index].identity == hash:
      if cache.next < high(uint64):
        inc cache.next
        cache.entries[index].age = cache.next # Exhausted age space does not invalidate already checked retained content.
      return PreimageCacheResult(status: PreimageCacheError.None, completed: cache.entries[index].reply)
  PreimageCacheResult(status: PreimageCacheError.Missing)

proc contains*(cache: PreimageCache, request: ReadRequest, bodyBytes: uint32): bool =
  ## Compare complete identity/length using frozen metadata without copying retained content.
  if not request.valid or request.kind != ReadKind.Preimage: return false
  if uint64(bodyBytes) > uint64(MaxCachedPreimageBytes-4): return false
  let hash = identity(request)
  for index in 0..<MaxCachedPreimages:
    if cache.entries[index].used and cache.entries[index].identity == hash and
        cache.entries[index].reply.byteLength == int(bodyBytes)+4: return true
  false
