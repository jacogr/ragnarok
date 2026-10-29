# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete full-state graph admission and authenticated reads use fixed traversal state and disk scratch.
## Synchronous callbacks are borrowed; checked metadata owns no file, producer, graph or scratch buffer.
import std/assertions
import ./codec as full_paged_codec
import ../../paged/[codec as paged_codec, stream as paged_stream]
import ../../node/records as node_records
import ../../../codec/bounded
import ../../../codec/state/[layout as state_layout, trie as state_trie]
import ../../../crypto/primitives

const FullPagedFixedBytes* = 4194304'u64 ## Conservative logical workspace, distinct from measured RSS.
type
  FullPagedWrite* = proc(offset: PagedOffset, input: openArray[byte]): bool {.closure.}
    ## Write the complete scratch window or refuse; caller owns a private exact-sized scratch file.
  FullPagedEntryVisitor* = proc(ordinal: uint64, key: StateKey, value: openArray[
      byte]): bool {.closure.}
    ## Borrow each sorted complete-root value only during this synchronous call; false refuses the whole stream.
  FullPagedScratch* = object ## Disposable trusted private IO, never a selected-state or graph authority.
    input*: PagedInput
    write*: nil FullPagedWrite
  FullPagedWorkLimits* = object ## Finite operation budgets count source and scratch IO together.
    ioCalls*, hashes*, visits*: ElementLimit
    readBytes*, writeBytes*: ByteLimit
  FullPagedStreamLimits* = object ## Dataset, history, per-root, scratch and resident limits are independent.
    dataset*: PagedLimits
    trie*: StateTrieLimits
    roots*, cachePages*: ElementLimit
    workingBytes*, scratchBytes*: ByteLimit
    contextBytes*: ByteLimit ## Zero selects V1; a positive finite cap requires authenticated V2 context.
    work*: FullPagedWorkLimits
  FullPagedStreamError* {.pure.} = enum ## Missing physical nodes never become protocol-level absence.
    Uninitialized, None, CodecFailure, LimitExceeded, UnsupportedPolicy, IOFailure,
    ChangedInput, MissingNode, InvalidGraph, CountMismatch, UnreachableRecord, UnknownRoot, VisitorRefused
  FullPagedStreamResult*[T] = object ## Failed/default alternatives have no checked graph or partial value.
    case status: FullPagedStreamError
    of None: completed: T
    of CodecFailure: cause: FullPagedError
    else: discard
  FullPagedCounts* = object ## Passive complete-operation work counts confer no graph authority.
    ready: bool
    io, hashes, visits, read, written: uint64
  CheckedFullPagedArtifact* = object ## Complete root-union admission, bound to exact local page integrity.
    ready: bool
    header: FullPagedHeader
    selected: FullPagedManifest
    policy: FullPagedStreamLimits
    used: FullPagedCounts
    stream: FullPagedDigest
  FullPagedLookup* = object ## An owned value is distinct from checked protocol absence.
    present: bool
    payload: seq[byte]
  FullPagedContext* = object ## Owned immutable opaque V2 context retains neither native pins nor source callbacks.
    ready: bool
    selected: FullPagedManifest
    payload: seq[byte]
    used: FullPagedCounts
  Work = object ## Sticky first-error state; no callbacks or allocations live in this owner.
    status: FullPagedStreamError
    cause: FullPagedError
    limits: FullPagedStreamLimits
    used: FullPagedCounts
  Counter {.pure.} = enum ## Named channels prevent aliasing a mutable owner and its nested fields.
    IO, Hash, Visit, Read, Write
  PageCache = object ## Zero/one-cache policy uses one fixed transient buffer in both modes.
    ready: bool
    ordinal: uint64
    bytes: array[PagedPageBytes, byte]
  GraphCounts = object ## Per-root totals never infer completeness from stored claims.
    entries, nodes, values: uint64

func error*[T](outcome: FullPagedStreamResult[T]): FullPagedStreamError =
  ## Inspect only the selected outcome.
  outcome.status
func value*[T](outcome: FullPagedStreamResult[T]): T {.inline,
    requires: outcome.status == FullPagedStreamError.None.} =
  ## Extract only a complete graph/lookup result.
  outcome.completed
func codecError*[T](outcome: FullPagedStreamResult[T]): FullPagedError {.requires:
    outcome.status == FullPagedStreamError.CodecFailure.} =
  ## Preserve selected format/provider diagnostics without exposing inactive fields.
  outcome.cause
func initialized*(checked: CheckedFullPagedArtifact): bool =
  ## Default checked metadata has no graph authority.
  checked.ready
func header*(checked: CheckedFullPagedArtifact): FullPagedHeader {.requires: checked.ready.} =
  ## Return complete admitted scalar claims only.
  checked.header
func manifest*(checked: CheckedFullPagedArtifact): FullPagedManifest {.requires: checked.ready.} =
  ## Native owners still supply immutable inode/pin/durability authority separately.
  checked.selected
func fingerprint*(checked: CheckedFullPagedArtifact): FullPagedDigest {.requires: checked.ready.} =
  ## Bind exact canonical physical records independently of equal protocol roots or local page layout.
  checked.stream
func limits*(checked: CheckedFullPagedArtifact): FullPagedStreamLimits {.requires: checked.ready.} =
  ## Return detached inherited scalar policies without permitting mutation of admitted authority.
  checked.policy
func counts*(checked: CheckedFullPagedArtifact): FullPagedCounts {.requires: checked.ready.} =
  ## Copy passive actual counters from successful complete admission.
  checked.used
func ioCalls*(counts: FullPagedCounts): uint64 {.requires: counts.ready.} =
  ## Includes source and scratch reads, writes and extent checks.
  counts.io
func hashes*(counts: FullPagedCounts): uint64 {.requires: counts.ready.} =
  ## Count local page/digest and canonical record hash operations.
  counts.hashes
func visits*(counts: FullPagedCounts): uint64 {.requires: counts.ready.} =
  ## Count complete-root physical graph visits, including shared records in separate roots.
  counts.visits
func readBytes*(counts: FullPagedCounts): uint64 {.requires: counts.ready.} =
  ## Account every requested source and scratch octet before dispatch.
  counts.read
func writeBytes*(counts: FullPagedCounts): uint64 {.requires: counts.ready.} =
  ## Account every scratch write before dispatch.
  counts.written
func present*(lookup: FullPagedLookup): bool =
  ## A successful terminal miss is protocol absence in a completely admitted graph.
  lookup.present
proc bytes*(lookup: FullPagedLookup): seq[byte] {.requires: lookup.present.} =
  ## Returned mutable value bytes are independently owned by the caller.
  result = newSeq[byte](lookup.payload.len)
  for index in 0..<lookup.payload.len: result[index] = lookup.payload[index] # Detach mutable output.
proc fail(work: var Work, reason: FullPagedStreamError) =
  ## Preserve the first failure across recursive traversal and cleanup.
  if work.status == FullPagedStreamError.None: work.status = reason
proc codec(work: var Work, reason: FullPagedError): bool =
  ## Only the first codec refusal selects its diagnostic.
  if reason != FullPagedError.None and work.status == FullPagedStreamError.None:
    work.status = FullPagedStreamError.CodecFailure
    work.cause = reason
  reason == FullPagedError.None and work.status == FullPagedStreamError.None
func refused[T](work: Work): FullPagedStreamResult[T] =
  ## Failed operations contain only a reason and an optional selected codec cause.
  if work.status == FullPagedStreamError.CodecFailure:
    return FullPagedStreamResult[T](status: FullPagedStreamError.CodecFailure, cause: work.cause)
  FullPagedStreamResult[T](status: work.status)
proc increment(used: var uint64, amount, maximum: uint64): bool =
  ## Prove additions before evaluating wrapping native integer arithmetic.
  if used > maximum or amount > maximum-used: return false
  used += amount
  true
proc charge(work: var Work, channel: Counter, amount: uint64): bool =
  ## Quota refusal always occurs before callback dispatch or cryptography.
  if work.status != FullPagedStreamError.None: return false
  let limits = work.limits.work
  let admitted = case channel
    of Counter.IO: increment(work.used.io, amount, uint64(limits.ioCalls))
    of Counter.Hash: increment(work.used.hashes, amount, uint64(limits.hashes))
    of Counter.Visit: increment(work.used.visits, amount, uint64(limits.visits))
    of Counter.Read: increment(work.used.read, amount, uint64(limits.readBytes))
    of Counter.Write: increment(work.used.written, amount, uint64(limits.writeBytes))
  if not admitted: work.fail(FullPagedStreamError.LimitExceeded)
  admitted
func initWork(limits: FullPagedStreamLimits): Work =
  ## Four admitted record/value transports plus fixed traversal/page scratch bound all resident work.
  result = Work(status: FullPagedStreamError.None, limits: limits, used: FullPagedCounts(ready: true))
  let available = uint64(limits.workingBytes)
  if available < FullPagedFixedBytes or uint64(limits.trie.perValue) > (
      available-FullPagedFixedBytes) div 4:
    result.status = FullPagedStreamError.LimitExceeded
  elif uint64(limits.cachePages) > 1:
    result.status = FullPagedStreamError.UnsupportedPolicy
func validateFullPagedContextSize*(size: uint64, limit: ByteLimit): FullPagedStreamError =
  ## Physical context presence selects V1/V2 explicitly, independently of total dataset and working quotas.
  if (size == 0) != (uint64(limit) == 0):
    return FullPagedStreamError.UnsupportedPolicy # No implicit format fallback or migration.
  if size > uint64(limit): return FullPagedStreamError.LimitExceeded # Subtraction-free independent size admission.
  FullPagedStreamError.None
func validateFullPagedPolicy*(limits: FullPagedStreamLimits): FullPagedStreamError =
  ## Native callers can reject unsupported resident/cache policies before allocating disk workspace.
  initWork(limits).status
proc readExact(io: PagedInput, offset: uint64, output: var openArray[byte], work: var Work): bool =
  ## No buffer or callback escapes synchronous complete-window reads.
  let callback = io.read
  if callback == nil:
    work.fail(FullPagedStreamError.Uninitialized)
    return false
  if not work.charge(Counter.IO, 1) or not work.charge(Counter.Read, uint64(
      output.len)): return false
  if not callback(PagedOffset(offset), output): work.fail(FullPagedStreamError.IOFailure)
  work.status == FullPagedStreamError.None
proc checkExtent(io: PagedInput, expected: uint64, work: var Work): bool =
  ## Real EOF and native held-version checks belong to the borrowed IO implementation.
  let callback = io.extent
  if callback == nil:
    work.fail(FullPagedStreamError.Uninitialized)
    return false
  if not work.charge(Counter.IO, 1): return false
  var actual = 0'u64
  if not callback(actual): work.fail(FullPagedStreamError.IOFailure)
  elif actual != expected: work.fail(FullPagedStreamError.ChangedInput)
  work.status == FullPagedStreamError.None
proc writeScratch(scratch: FullPagedScratch, offset: uint64, input: openArray[byte],
    work: var Work): bool =
  ## Scratch writes cannot mutate the source; callbacks are trusted private-workspace operations.
  let callback = scratch.write
  if callback == nil:
    work.fail(FullPagedStreamError.Uninitialized)
    return false
  if not work.charge(Counter.IO, 1) or not work.charge(Counter.Write, uint64(
      input.len)): return false
  if not callback(PagedOffset(offset), input): work.fail(FullPagedStreamError.IOFailure)
  work.status == FullPagedStreamError.None
proc zero(scratch: FullPagedScratch, offset, size: uint64, work: var Work): bool =
  ## Fixed zero windows initialize and reset membership without dataset-sized resident bitmaps.
  var buffer = default(array[4096, byte])
  var cursor = 0'u64
  while cursor < size:
    # Bounded subtraction controls final partial scratch writes.
    let count = int(min(size-cursor, 4096'u64))
    if not scratch.writeScratch(offset+cursor, buffer.toOpenArray(0, count-1), work): return false
    cursor += uint64(count)
  work.status == FullPagedStreamError.None
proc page(io: PagedInput, header: FullPagedHeader, selected: FullPagedManifest, ordinal: uint64,
    cache: var PageCache, work: var Work): bool =
  ## Authenticate one data page against captured full-format integrity before exposing any bytes.
  if work.status != FullPagedStreamError.None: return false
  if uint64(work.limits.cachePages) == 1 and cache.ready and cache.ordinal == ordinal: return true
  cache.ready = false
  let shape = header.geometry
  let planned = pagedPath(shape, PageOrdinal(ordinal))
  if planned.error != PagedCodecError.None:
    work.fail(FullPagedStreamError.InvalidGraph)
    return false
  if not io.readExact(ordinal*4096, cache.bytes, work): return false
  if not work.charge(Counter.Hash, 1): return false
  let leaf = fullPagedLeafDigest(shape, PageOrdinal(ordinal), cache.bytes)
  if not work.codec(leaf.error): return false
  var current = leaf.value
  let path = planned.value
  for level in 0..<path.len:
    # Address schedules are arithmetic-only and bounded to at most 63 digest siblings.
    var raw = default(array[32, byte])
    let step = path.step(level)
    if not io.readExact(uint64(step.offset), raw, work): return false
    if not work.charge(Counter.Hash, 1): return false
    let sibling = FullPagedDigest(raw)
    let joined = if step.siblingLeft: fullPagedNodeDigest(sibling, current) else:
      fullPagedNodeDigest(current, sibling)
    if not work.codec(joined.error): return false
    current = joined.value
  if array[32, byte](current) != array[32, byte](selected.pageRoot):
    discard work.codec(FullPagedError.ChecksumMismatch)
    return false
  cache.ready = true
  cache.ordinal = ordinal
  true
proc range(io: PagedInput, header: FullPagedHeader, selected: FullPagedManifest, offset: uint64,
    output: var openArray[byte], cache: var PageCache, work: var Work): bool =
  ## Every requested extent remains within real data pages and can cross page boundaries safely.
  let bound = uint64(header.geometry.treeOffset)
  if offset > bound or uint64(output.len) > bound-offset:
    work.fail(FullPagedStreamError.InvalidGraph)
    return false
  var filled = 0
  while filled < output.len:
    # Exact remaining bytes and one authenticated page bound each copied window.
    let cursor = offset+uint64(filled)
    let within = int(cursor mod 4096)
    let count = min(output.len-filled, 4096-within)
    if not io.page(header, selected, cursor div 4096, cache, work): return false
    for index in 0..<count: output[filled+index] = cache.bytes[within+index] # Bounded complete copy.
    filled += count
  true
proc row(io: PagedInput, header: FullPagedHeader, selected: FullPagedManifest, ordinal: uint64,
    cache: var PageCache, work: var Work): FullPagedRow =
  ## Ordinal bounds precede fixed-row address multiplication.
  if ordinal >= header.geometry.entries:
    work.fail(FullPagedStreamError.InvalidGraph)
    return default(FullPagedRow)
  var raw = default(array[64, byte])
  if not io.range(header, selected, 4096+ordinal*64, raw, cache, work): return default(FullPagedRow)
  let decoded = decodeFullPagedRow(raw, header.geometry)
  if not work.codec(decoded.error): return default(FullPagedRow)
  decoded.value
proc position(io: PagedInput, header: FullPagedHeader, selected: FullPagedManifest,
    digest: StateNodeHash, cache: var PageCache, work: var Work): uint64 =
  ## Disk binary search uses full physical addresses; count is the private missing sentinel.
  var first = 0'u64
  var stop = header.geometry.entries
  while first < stop and work.status == FullPagedStreamError.None:
    # Difference-based midpoint never overflows the admitted ordinal interval.
    let middle = first+(stop-first) div 2
    let found = io.row(header, selected, middle, cache, work)
    if work.status != FullPagedStreamError.None: return header.geometry.entries
    let order = compareFullHash(array[32, byte](found.digest), array[32, byte](digest))
    if order < 0: first = middle+1
    elif order > 0: stop = middle
    else: return middle
  header.geometry.entries
proc fingerprint(previous: FullPagedDigest, bytes: seq[byte], work: var Work): FullPagedDigest =
  ## Complete canonical record bytes extend a fixed-width chain in the exact sorted index order.
  result = default(FullPagedDigest)
  if not work.charge(Counter.Hash, 1): return
  if bytes.len > high(int)-32:
    work.fail(FullPagedStreamError.LimitExceeded)
    return
  var input = newSeq[byte](32+bytes.len)
  let prior = array[32, byte](previous)
  for index in 0..<32: input[index] = prior[index] # Prior fixed-width digest.
  for index in 0..<bytes.len: input[32+index] = bytes[index] # One already bounded physical record.
  let hashed = blake2b256(input)
  if hashed.error != CryptoError.None:
    discard work.codec(FullPagedError.BackendFailure)
    return
  result = FullPagedDigest(array[32, byte](hashed.value))
proc record(io: PagedInput, header: FullPagedHeader, selected: FullPagedManifest,
    ordinal: uint64, cache: var PageCache, work: var Work,
    stream: var FullPagedDigest, bindStream: bool): TrieRecord =
  ## One bounded raw record and one decoded value coexist; no complete-record table is retained.
  let found = io.row(header, selected, ordinal, cache, work)
  if work.status != FullPagedStreamError.None: return default(TrieRecord)
  let size = found.byteLength
  let valueLimit = uint64(work.limits.trie.perValue)
  if size > uint64(high(int)) or (size != 97 and (size < 72 or size-72 > valueLimit)):
    work.fail(FullPagedStreamError.LimitExceeded)
    return default(TrieRecord)
  var raw = newSeq[byte](int(size))
  if not io.range(header, selected, uint64(header.geometry.payloadOffset)+found.offset,
      raw, cache, work): return default(TrieRecord)
  if bindStream:
    # Admission records the actual authenticated transport, not a re-encoding of logical state.
    stream = fingerprint(stream, raw, work)
  let hashCount = (if size > 104: 2'u64 else: 1'u64)
  if not work.charge(Counter.Hash, hashCount): return default(TrieRecord)
  let decoded = decodeFullPagedRecord(raw, found.digest, work.limits.trie.perValue)
  if not work.codec(decoded.error): return default(TrieRecord)
  decoded.value
proc record(io: PagedInput, header: FullPagedHeader, selected: FullPagedManifest,
    ordinal: uint64, cache: var PageCache, work: var Work): TrieRecord =
  ## Graph/path reads validate individual records without extending the complete stream fingerprint.
  var ignored = default(FullPagedDigest)
  io.record(header, selected, ordinal, cache, work, ignored, false)
proc tree(io: PagedInput, shape: PagedGeometry, start, width: uint64, cursor: var uint64,
    work: var Work): FullPagedDigest =
  ## Fixed-depth postorder recursion checks every stored digest, including nonphysical padding leaves.
  if work.status != FullPagedStreamError.None: return default(FullPagedDigest)
  var calculated = default(FullPagedDigest)
  if width == 1:
    # Exactly one real page or a domain-separated nonphysical padding leaf contributes.
    if start < shape.dataPages:
      var raw = default(array[4096, byte])
      if not io.readExact(start*4096, raw, work): return calculated
      if not work.charge(Counter.Hash, 1): return calculated
      let hashed = fullPagedLeafDigest(shape, PageOrdinal(start), raw)
      if not work.codec(hashed.error): return calculated
      calculated = hashed.value
    else:
      if not work.charge(Counter.Hash, 1): return calculated
      let hashed = fullPagedPaddingDigest(shape, PageOrdinal(start))
      if not work.codec(hashed.error): return calculated
      calculated = hashed.value
  else:
    # Geometry bounds tree height and all start/width arithmetic before traversal begins.
    let left = io.tree(shape, start, width div 2, cursor, work)
    let right = io.tree(shape, start+width div 2, width div 2, cursor, work)
    if not work.charge(Counter.Hash, 1): return calculated
    let hashed = fullPagedNodeDigest(left, right)
    if not work.codec(hashed.error): return calculated
    calculated = hashed.value
  var stored = default(array[32, byte])
  if not io.readExact(cursor, stored, work): return calculated
  if stored != array[32, byte](calculated): discard work.codec(FullPagedError.ChecksumMismatch)
  cursor += 32
  calculated
proc graph(io: PagedInput, scratch: FullPagedScratch, header: FullPagedHeader,
    selected: FullPagedManifest, digest: StateNodeHash, depth: int, prefix: array[31, byte],
    counts: var GraphCounts, cache: var PageCache, work: var Work) =
  ## Complete full-root traversal validates every edge, routed leaf and root-specific visited membership.
  if work.status != FullPagedStreamError.None: return
  if array[32, byte](digest) == default(array[32, byte]): return
  if not work.charge(Counter.Visit, 1): return
  let index = io.position(header, selected, digest, cache, work)
  if work.status != FullPagedStreamError.None: return
  if index == header.geometry.entries:
    work.fail(FullPagedStreamError.MissingNode)
    return
  var flag = default(array[1, byte])
  if not scratch.input.readExact(index, flag, work): return
  if flag[0] != 0:
    work.fail(FullPagedStreamError.InvalidGraph)
    return
  flag[0] = 1
  if not scratch.writeScratch(index, flag, work): return
  if not scratch.writeScratch(header.geometry.entries+index, flag, work): return
  if counts.nodes >= uint64(work.limits.trie.nodes):
    work.fail(FullPagedStreamError.LimitExceeded)
    return
  inc counts.nodes
  let current = io.record(header, selected, index, cache, work)
  if work.status != FullPagedStreamError.None: return
  if current.kind == TrieRecordKind.Leaf:
    # Every routed high bit is checked, with depth 248 still inside the complete serialized key.
    let key = array[31, byte](current.key)
    for bit in 0..<depth:
      let mask = byte(128 shr (bit mod 8))
      if (key[bit div 8] and mask) != (prefix[bit div 8] and mask):
        work.fail(FullPagedStreamError.InvalidGraph)
        return
    let size = uint64(current.payload.len)
    if counts.entries >= uint64(work.limits.trie.items) or
        size > uint64(work.limits.trie.totalValueBytes)-counts.values:
      work.fail(FullPagedStreamError.LimitExceeded)
      return
    inc counts.entries
    counts.values += size
  else:
    # Branches cannot route beyond the last serialized key bit; singleton subtrees must collapse.
    if depth >= 248:
      work.fail(FullPagedStreamError.InvalidGraph)
      return
    let before = counts.entries
    io.graph(scratch, header, selected, current.left, depth+1, prefix, counts, cache, work)
    var rightPrefix = prefix
    rightPrefix[depth div 8] = rightPrefix[depth div 8] or byte(128 shr (depth mod 8))
    io.graph(scratch, header, selected, current.right, depth+1, rightPrefix, counts, cache, work)
    if counts.entries-before < 2: work.fail(FullPagedStreamError.InvalidGraph)
proc padding(io: PagedInput, header: FullPagedHeader, selected: FullPagedManifest,
    first, stop: uint64, cache: var PageCache, work: var Work): bool =
  ## Canonical zero suffixes exclude hidden bytes outside index/payload framing even with valid page hashes.
  var cursor = first
  while cursor < stop:
    # Padding is less than one page per section, and never requires a resident section buffer.
    if not io.page(header, selected, cursor div 4096, cache, work): return false
    let stopInPage = min(stop-cursor, 4096-(cursor mod 4096))
    for index in 0..<int(stopInPage):
      # One authenticated page supplies this entire zero suffix, even in zero-cache mode.
      if cache.bytes[int(cursor mod 4096)+index] != 0:
        discard work.codec(FullPagedError.InvalidFormat)
        return false
    cursor += stopInPage
  work.status == FullPagedStreamError.None
proc validateFullPaged*(io: PagedInput, scratch: FullPagedScratch, header: FullPagedHeader,
    selected: FullPagedManifest, limits: FullPagedStreamLimits): FullPagedStreamResult[
        CheckedFullPagedArtifact] =
  ## Full admission rechecks physical bytes, complete graphs and exact root union before retaining metadata.
  var work = initWork(limits)
  if not header.initialized:
    work.fail(FullPagedStreamError.Uninitialized)
    return refused[CheckedFullPagedArtifact](work)
  let shape = header.geometry
  let contextPolicy = validateFullPagedContextSize(shape.contextBytes, limits.contextBytes)
  if contextPolicy != FullPagedStreamError.None:
    work.fail(contextPolicy) # Context mode and byte budget are independent of full graph membership.
    return refused[CheckedFullPagedArtifact](work)
  if uint64(header.len) > uint64(limits.roots) or shape.entries > uint64(limits.dataset.entries) or
      shape.byteLength > uint64(limits.dataset.bytes) or shape.entries > uint64(
          limits.scratchBytes) div 2:
    work.fail(FullPagedStreamError.LimitExceeded)
  if work.status != FullPagedStreamError.None: return refused[CheckedFullPagedArtifact](work)
  if not work.charge(Counter.Hash, 1): return refused[CheckedFullPagedArtifact](work)
  let encoded = selected.bytes
  if not work.codec(encoded.error): return refused[CheckedFullPagedArtifact](work)
  if not work.charge(Counter.Hash, 1): return refused[CheckedFullPagedArtifact](work)
  let binding = decodeFullPagedManifest(encoded.value, header)
  if not work.codec(binding.error): return refused[CheckedFullPagedArtifact](work)
  if not io.checkExtent(shape.byteLength, work): return refused[CheckedFullPagedArtifact](work)
  if not scratch.input.checkExtent(shape.entries*2, work): return refused[CheckedFullPagedArtifact](work)
  var rawHeader = default(array[4096, byte])
  if not io.readExact(0, rawHeader, work): return refused[CheckedFullPagedArtifact](work)
  if rawHeader != header.bytes:
    work.fail(FullPagedStreamError.ChangedInput)
    return refused[CheckedFullPagedArtifact](work)
  var cursor = uint64(shape.treeOffset)
  let root = io.tree(shape, 0, shape.treeLeaves, cursor, work)
  if work.status != FullPagedStreamError.None: return refused[CheckedFullPagedArtifact](work)
  if cursor != shape.byteLength or array[32, byte](root) != array[32, byte](selected.pageRoot):
    discard work.codec(FullPagedError.ChecksumMismatch)
    return refused[CheckedFullPagedArtifact](work)
  var cache = default(PageCache)
  var scan = initFullPagedIndexScan(shape)
  var stream = default(FullPagedDigest)
  for ordinal in 0'u64..<shape.entries:
    # Read every record before traversing so an unreachable malformed record cannot hide behind graph failures.
    var raw = default(array[64, byte])
    if not io.range(header, selected, 4096+ordinal*64, raw, cache, work): return refused[
        CheckedFullPagedArtifact](work)
    let admitted = scan.admit(raw)
    if not work.codec(admitted.error): return refused[CheckedFullPagedArtifact](work)
    discard io.record(header, selected, ordinal, cache, work, stream, true)
    if work.status != FullPagedStreamError.None: return refused[CheckedFullPagedArtifact](work)
  if not work.codec(scan.finish): return refused[CheckedFullPagedArtifact](work)
  if not io.padding(header, selected, 4096+shape.entries*64, uint64(shape.payloadOffset),
      cache, work): return refused[CheckedFullPagedArtifact](work)
  if not io.padding(header, selected, uint64(shape.payloadOffset)+shape.payloadBytes,
      uint64(shape.contextOffset), cache, work): return refused[CheckedFullPagedArtifact](work)
  if not io.padding(header, selected, uint64(shape.contextOffset)+shape.contextBytes,
      uint64(shape.treeOffset), cache, work): return refused[CheckedFullPagedArtifact](work)
  if not scratch.zero(0, shape.entries*2, work): return refused[CheckedFullPagedArtifact](work)
  for index in 0..<header.len:
    # Per-root visitation resets independently; retained-union membership survives all roots.
    if index != 0 and not scratch.zero(0, shape.entries, work): return refused[
        CheckedFullPagedArtifact](work)
    let claim = header.retainedRoot(index)
    var counts = default(GraphCounts)
    io.graph(scratch, header, selected, StateNodeHash(array[32, byte](claim.root)), 0,
      default(array[31, byte]), counts, cache, work)
    if work.status != FullPagedStreamError.None: return refused[CheckedFullPagedArtifact](work)
    if counts.entries != claim.entries or counts.nodes != claim.nodes or counts.values !=
        claim.valueBytes:
      work.fail(FullPagedStreamError.CountMismatch)
      return refused[CheckedFullPagedArtifact](work)
  for ordinal in 0'u64..<shape.entries:
    # An exact compact union contains every reachable record and no unclaimed historical garbage.
    var flag = default(array[1, byte])
    if not scratch.input.readExact(shape.entries+ordinal, flag, work): return refused[
        CheckedFullPagedArtifact](work)
    if flag[0] != 1:
      work.fail(FullPagedStreamError.UnreachableRecord)
      return refused[CheckedFullPagedArtifact](work)
  if not io.checkExtent(shape.byteLength, work): return refused[CheckedFullPagedArtifact](work)
  if not scratch.input.checkExtent(shape.entries*2, work): return refused[CheckedFullPagedArtifact](work)
  FullPagedStreamResult[CheckedFullPagedArtifact](status: FullPagedStreamError.None,
    completed: CheckedFullPagedArtifact(ready: true, header: header, selected: selected,
      policy: limits, used: work.used, stream: stream))
proc lookupFullPaged*(io: PagedInput, checked: CheckedFullPagedArtifact, root: StateRoot,
    key: StateKey): FullPagedStreamResult[FullPagedLookup] =
  ## Only an admitted retained root permits an owned lookup or authenticated protocol absence.
  if not checked.ready: return FullPagedStreamResult[FullPagedLookup](
      status: FullPagedStreamError.Uninitialized)
  var work = initWork(checked.policy)
  let header = checked.header
  var retained = false
  for index in 0..<header.len:
    # No caller-substituted same-header root gains graph authority.
    if array[32, byte](root) == array[32, byte](header.retainedRoot(index).root): retained = true
  if not retained:
    work.fail(FullPagedStreamError.UnknownRoot)
    return refused[FullPagedLookup](work)
  if not io.checkExtent(header.geometry.byteLength, work): return refused[FullPagedLookup](work)
  var cache = default(PageCache)
  var digest = StateNodeHash(array[32, byte](root))
  var depth = 0
  var lookup = FullPagedLookup(present: false)
  let query = array[31, byte](key)
  while array[32, byte](digest) != default(array[32, byte]):
    # The originally checked topology bounds this path, while current reads stay page-authenticated.
    if not work.charge(Counter.Visit, 1): return refused[FullPagedLookup](work)
    let index = io.position(header, checked.selected, digest, cache, work)
    if work.status != FullPagedStreamError.None: return refused[FullPagedLookup](work)
    if index == header.geometry.entries:
      work.fail(FullPagedStreamError.MissingNode)
      return refused[FullPagedLookup](work)
    let current = io.record(header, checked.selected, index, cache, work)
    if work.status != FullPagedStreamError.None: return refused[FullPagedLookup](work)
    if current.kind == TrieRecordKind.Leaf:
      # Complete key equality establishes presence; a different valid terminal key establishes absence.
      lookup = FullPagedLookup(present: array[31, byte](current.key) == query)
      if lookup.present: lookup.payload = current.payload
      digest = default(StateNodeHash)
    else:
      if depth >= 248:
        work.fail(FullPagedStreamError.InvalidGraph)
        return refused[FullPagedLookup](work)
      let right = (query[depth div 8] and byte(128 shr (depth mod 8))) != 0
      digest = (if right: current.right else: current.left)
      inc depth
  if not io.checkExtent(header.geometry.byteLength, work): return refused[FullPagedLookup](work)
  FullPagedStreamResult[FullPagedLookup](status: FullPagedStreamError.None, completed: lookup)

proc fetchFullPagedPage*(io: PagedInput, checked: CheckedFullPagedArtifact,
    ordinal: PageOrdinal): FullPagedStreamResult[array[PagedPageBytes, byte]] =
  ## Copy one captured-root-authenticated page; no native owner, cache slot or callback escapes.
  if not checked.ready:
    return FullPagedStreamResult[array[PagedPageBytes, byte]](
        status: FullPagedStreamError.Uninitialized)
  var work = initWork(checked.policy)
  let shape = checked.header.geometry
  if uint64(ordinal) >= shape.dataPages:
    work.fail(FullPagedStreamError.InvalidGraph)
    return refused[array[PagedPageBytes, byte]](work)
  if not io.checkExtent(shape.byteLength, work): return refused[array[PagedPageBytes, byte]](work)
  var cache = default(PageCache)
  if not io.page(checked.header, checked.selected, uint64(ordinal), cache, work):
    return refused[array[PagedPageBytes, byte]](work)
  if not io.checkExtent(shape.byteLength, work): return refused[array[PagedPageBytes, byte]](work)
  FullPagedStreamResult[array[PagedPageBytes, byte]](status: FullPagedStreamError.None,
    completed: cache.bytes)

proc streamBudget(inherited, requested: FullPagedWorkLimits): FullPagedWorkLimits =
  ## Per-call ceilings can only tighten captured admission policy; dataset/trie/workspace limits remain inherited.
  FullPagedWorkLimits(ioCalls: ElementLimit(min(uint64(inherited.ioCalls), uint64(
      requested.ioCalls))),
    hashes: ElementLimit(min(uint64(inherited.hashes), uint64(requested.hashes))),
    visits: ElementLimit(min(uint64(inherited.visits), uint64(requested.visits))),
    readBytes: ByteLimit(min(uint64(inherited.readBytes), uint64(requested.readBytes))),
    writeBytes: ByteLimit(min(uint64(inherited.writeBytes), uint64(requested.writeBytes))))
proc entries(io: PagedInput, header: FullPagedHeader, selected: FullPagedManifest,
    digest: StateNodeHash, depth: int, prefix: array[31, byte], counts: var GraphCounts,
    visitor: FullPagedEntryVisitor, cache: var PageCache, work: var Work) =
  ## Captured complete graph authority permits a readonly fixed-depth walk without another visited table or resident index.
  if work.status != FullPagedStreamError.None: return
  if array[32, byte](digest) == default(array[32, byte]): return
  if not work.charge(Counter.Visit, 1): return
  let position = io.position(header, selected, digest, cache, work)
  if work.status != FullPagedStreamError.None: return
  if position == header.geometry.entries:
    work.fail(FullPagedStreamError.MissingNode)
    return
  if counts.nodes >= uint64(work.limits.trie.nodes):
    work.fail(FullPagedStreamError.LimitExceeded)
    return
  inc counts.nodes
  let current = io.record(header, selected, position, cache, work)
  if work.status != FullPagedStreamError.None: return
  if current.kind == TrieRecordKind.Leaf:
    # Recheck the complete routed prefix before lending any value, including depth248 terminal leaves.
    let key = array[31, byte](current.key)
    for bit in 0..<depth:
      let mask = byte(128 shr (bit mod 8))
      if (key[bit div 8] and mask) != (prefix[bit div 8] and mask):
        work.fail(FullPagedStreamError.InvalidGraph)
        return
    let size = uint64(current.payload.len)
    if counts.entries >= uint64(work.limits.trie.items):
      work.fail(FullPagedStreamError.LimitExceeded)
      return
    if size > uint64(work.limits.trie.totalValueBytes)-counts.values:
      work.fail(FullPagedStreamError.LimitExceeded)
      return
    let ordinal = counts.entries
    inc counts.entries
    counts.values += size
    if not visitor(ordinal, current.key, current.payload):
      work.fail(FullPagedStreamError.VisitorRefused)
  else:
    # Left-before-right traversal yields strict serialized key order; captured topology excludes repetition/cycles.
    if depth >= 248:
      work.fail(FullPagedStreamError.InvalidGraph)
      return
    let before = counts.entries
    io.entries(header, selected, current.left, depth+1, prefix, counts, visitor, cache, work)
    var right = prefix
    right[depth div 8] = right[depth div 8] or byte(128 shr (depth mod 8))
    io.entries(header, selected, current.right, depth+1, right, counts, visitor, cache, work)
    if work.status == FullPagedStreamError.None and counts.entries-before < 2:
      work.fail(FullPagedStreamError.InvalidGraph)
proc streamFullPagedEntries*(io: PagedInput, checked: CheckedFullPagedArtifact,
    root: StateRoot, visitor: nil FullPagedEntryVisitor,
    budget: FullPagedWorkLimits): FullPagedStreamResult[FullPagedCounts] =
  ## No callback/native owner escapes; only complete success exposes counters, never a successful delivered prefix.
  if not checked.ready or visitor == nil:
    return FullPagedStreamResult[FullPagedCounts](status: FullPagedStreamError.Uninitialized)
  var policy = checked.policy
  policy.work = streamBudget(policy.work, budget)
  var work = initWork(policy)
  if work.status != FullPagedStreamError.None: return refused[FullPagedCounts](work)
  let header = checked.header
  var claim = default(FullPagedRoot)
  var found = false
  for index in 0..<header.len:
    # Root selection is an independent caller argument, never an inferred complete state from partial data.
    let retained = header.retainedRoot(index)
    if array[32, byte](retained.root) == array[32, byte](root):
      claim = retained
      found = true
  if not found:
    work.fail(FullPagedStreamError.UnknownRoot)
    return refused[FullPagedCounts](work)
  if not io.checkExtent(header.geometry.byteLength, work): return refused[FullPagedCounts](work)
  var cache = default(PageCache)
  var counts = default(GraphCounts)
  io.entries(header, checked.selected, StateNodeHash(array[32, byte](root)), 0,
    default(array[31, byte]), counts, visitor, cache, work)
  if work.status != FullPagedStreamError.None: return refused[FullPagedCounts](work)
  if counts.entries != claim.entries or counts.nodes != claim.nodes or counts.values !=
      claim.valueBytes:
    work.fail(FullPagedStreamError.CountMismatch)
    return refused[FullPagedCounts](work)
  if not io.checkExtent(header.geometry.byteLength, work): return refused[FullPagedCounts](work)
  FullPagedStreamResult[FullPagedCounts](status: FullPagedStreamError.None, completed: work.used)

func initialized*(context: FullPagedContext): bool =
  ## A default capture confers no authenticated opaque context authority.
  context.ready
func manifest*(context: FullPagedContext): FullPagedManifest {.requires: context.ready.} =
  ## Bind detached context to its exact captured header/page-tree selection rather than a root-only match.
  context.selected
proc bytes*(context: FullPagedContext): seq[byte] {.requires: context.ready.} =
  ## Return a detached mutable transport copy; private captured bytes remain immutable after native close.
  result = newSeq[byte](context.payload.len)
  for index in 0..<result.len: result[index] = context.payload[index] # Copy every octet without exposing backing.
func byteLength*(context: FullPagedContext): int {.requires: context.ready.} =
  ## Exact successful retained bytes permit consumer preflight without transport allocation.
  context.payload.len
func counts*(context: FullPagedContext): FullPagedCounts {.requires: context.ready.} =
  ## Report only complete successful source IO and authentication work.
  context.used
proc readFullPagedContext*(io: PagedInput, checked: CheckedFullPagedArtifact,
    budget: FullPagedWorkLimits): FullPagedStreamResult[FullPagedContext] =
  ## Capture opaque V2 bytes privately after bounded authenticated reads; application interpretation/trust stays separate.
  if not checked.ready:
    return FullPagedStreamResult[FullPagedContext](status: FullPagedStreamError.Uninitialized)
  var policy = checked.policy
  policy.work = streamBudget(policy.work, budget)
  var work = initWork(policy)
  let shape = checked.header.geometry
  if shape.contextBytes == 0:
    work.fail(FullPagedStreamError.UnsupportedPolicy) # V1 has no context; never fabricate an empty application head.
    return refused[FullPagedContext](work)
  let size = shape.contextBytes
  let available = uint64(policy.workingBytes)
  if available < FullPagedFixedBytes or size > (available-FullPagedFixedBytes) div 4 or size >
      uint64(high(int)):
    work.fail(FullPagedStreamError.LimitExceeded) # Reserve four context transports, matching the conservative full-value copy contract.
  if size > uint64(policy.work.readBytes) or uint64(policy.work.ioCalls) < 2 or uint64(
      policy.work.hashes) == 0:
    work.fail(FullPagedStreamError.LimitExceeded) # Obvious per-call refusal precedes source dispatch and owned allocation.
  if work.status != FullPagedStreamError.None: return refused[FullPagedContext](work)
  if not io.checkExtent(shape.byteLength, work): return refused[FullPagedContext](work)
  var payload = newSeq[byte](int(size))
  var cache = default(PageCache)
  if not io.range(checked.header, checked.selected, uint64(shape.contextOffset), payload, cache, work):
    return refused[FullPagedContext](work) # No successfully copied prefix escapes a later authentication/IO refusal.
  if not io.checkExtent(shape.byteLength, work): return refused[FullPagedContext](work)
  FullPagedStreamResult[FullPagedContext](status: FullPagedStreamError.None,
    completed: FullPagedContext(ready: true, selected: checked.selected, payload: payload,
        used: work.used))
