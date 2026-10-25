# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Replay-bound full-state artifact construction uses one record, fixed pages and a bounded digest stack.
## Successful construction includes complete graph admission; borrowed producer/output/scratch never escape.
import std/assertions
import ./[full_paged_codec, full_paged_stream, paged_codec, paged_stream, node_records, managed_manifest]
import ../codec/bounded
import ../crypto/primitives

type
  FullPagedProducerStep* {.pure.} = enum ## Explicit end is distinct from unavailable producer data.
    Failed, Item, End
  FullPagedProducer* = proc(pass: int, ordinal: uint64,
      record: var TrieRecord): FullPagedProducerStep {.closure.}
    ## Supply the identical sorted canonical physical stream in two synchronous passes.
  FullPagedBuildLimits* = object ## Construction budgets are separate from final full-admission work budgets.
    admission*: FullPagedStreamLimits
    producerCalls*, ioCalls*, hashes*: ElementLimit
    readBytes*, writeBytes*: ByteLimit
  FullPagedCompactionLimits* = object ## Source-page and target-tree work share these finite construction counters.
    ioCalls*, hashes*: ElementLimit
    readBytes*, writeBytes*: ByteLimit
  FullPagedBuildError* {.pure.} = enum ## Failed authoring preserves only forensic bytes and a selected cause.
    Uninitialized, None, LimitExceeded, IOFailure, ProducerFailure, ChangedInput, CodecFailure,
      GraphFailure, UnsupportedPolicy
  FullPagedBuildReceipt* = object ## Successful authoring retains only checked scalar metadata and passive work counts.
    checked: CheckedFullPagedArtifact
    calls, io, hashes, read, written: uint64
  FullPagedBuildResult* = object ## No unsuccessful builder result carries even a partial checked artifact.
    case status: FullPagedBuildError
    of None: completed: FullPagedBuildReceipt
    of CodecFailure: codecCause: FullPagedError
    of GraphFailure:
      graphCause: FullPagedStreamError
      graphCodec: FullPagedError
    else: discard
  Build = object ## First-error construction state owns one page; no source callback is retained.
    status: FullPagedBuildError
    codecCause: FullPagedError
    limits: FullPagedBuildLimits
    calls, io, hashes, read, written: uint64
    page: array[4096, byte]
    filled: int
  Channel {.pure.} = enum ## Independent finite counters are charged before dispatch.
    Producer, IO, Hash, Read, Write
func error*(outcome: FullPagedBuildResult): FullPagedBuildError =
  ## Inspect only the selected authoring outcome.
  outcome.status
func value*(outcome: FullPagedBuildResult): FullPagedBuildReceipt {.requires:
    outcome.status == FullPagedBuildError.None.} =
  ## Extract complete checked metadata only after final graph admission succeeds.
  outcome.completed
func checked*(receipt: FullPagedBuildReceipt): CheckedFullPagedArtifact =
  ## Default receipts expose only default uninitialized metadata, never graph authority.
  receipt.checked
func producerCalls*(receipt: FullPagedBuildReceipt): uint64 =
  ## Passive counters grant no producer replay or native selection authority.
  receipt.calls
func ioCalls*(receipt: FullPagedBuildReceipt): uint64 =
  ## Include output append, construction reads and exact extent checks.
  receipt.io
func hashes*(receipt: FullPagedBuildReceipt): uint64 =
  ## Include record, replay fingerprint and full local digest operations during construction.
  receipt.hashes
func readBytes*(receipt: FullPagedBuildReceipt): uint64 =
  ## Count exact construction reads separately from final graph admission.
  receipt.read
func writeBytes*(receipt: FullPagedBuildReceipt): uint64 =
  ## Count every appended byte through the final stored tree root.
  receipt.written
func codecError*(outcome: FullPagedBuildResult): FullPagedError {.requires:
    outcome.status == FullPagedBuildError.CodecFailure.} =
  ## Selected codec refusal never reads inactive graph diagnostics.
  outcome.codecCause
func graphError*(outcome: FullPagedBuildResult): FullPagedStreamError {.requires:
    outcome.status == FullPagedBuildError.GraphFailure.} =
  ## Failed complete admission supplies no partially checked artifact.
  outcome.graphCause
func graphCodecError*(outcome: FullPagedBuildResult): FullPagedError {.requires:
    outcome.status == FullPagedBuildError.GraphFailure.} =
  ## Non-codec graph failures preserve Uninitialized here without conferring any authority.
  outcome.graphCodec
proc fail(work: var Build, reason: FullPagedBuildError) =
  ## Later cleanup or counter refusals cannot erase the first failure.
  if work.status == FullPagedBuildError.None: work.status = reason
proc increment(used: var uint64, amount, limit: uint64): bool =
  ## Subtraction proves native wrapping addition safe before evaluation.
  if used > limit or amount > limit-used: return false
  used += amount
  true
proc charge(work: var Build, channel: Channel, amount: uint64): bool =
  ## No callback or hash begins after a policy refusal.
  if work.status != FullPagedBuildError.None: return false
  let limits = work.limits
  let admitted = case channel
    of Channel.Producer: increment(work.calls, amount, uint64(limits.producerCalls))
    of Channel.IO: increment(work.io, amount, uint64(limits.ioCalls))
    of Channel.Hash: increment(work.hashes, amount, uint64(limits.hashes))
    of Channel.Read: increment(work.read, amount, uint64(limits.readBytes))
    of Channel.Write: increment(work.written, amount, uint64(limits.writeBytes))
  if not admitted: work.fail(FullPagedBuildError.LimitExceeded)
  admitted
proc codec(work: var Build, reason: FullPagedError): bool =
  ## Preserve exact selected shape/hash/provider failures.
  if reason != FullPagedError.None and work.status == FullPagedBuildError.None:
    work.status = FullPagedBuildError.CodecFailure
    work.codecCause = reason
  work.status == FullPagedBuildError.None
func refused(work: Build): FullPagedBuildResult =
  ## A forensic prefix is never a successful construction result.
  if work.status == FullPagedBuildError.CodecFailure:
    return FullPagedBuildResult(status: FullPagedBuildError.CodecFailure,
        codecCause: work.codecCause)
  FullPagedBuildResult(status: work.status)
proc appendRaw(output: PagedOutput, bytes: openArray[byte], work: var Build): bool =
  ## Positive completion means every input byte appended; caller callbacks own partial-write uncertainty.
  let callback = output.append
  if callback == nil:
    work.fail(FullPagedBuildError.Uninitialized)
    return false
  if not work.charge(Channel.IO, 1) or not work.charge(Channel.Write, uint64(
      bytes.len)): return false
  if not callback(bytes): work.fail(FullPagedBuildError.IOFailure)
  work.status == FullPagedBuildError.None
proc flush(output: PagedOutput, work: var Build): bool =
  ## Canonical zero padding fills only the final suffix of one page, then retires its contents.
  if work.filled == 0: return work.status == FullPagedBuildError.None
  for index in work.filled..<4096: work.page[index] = 0 # Explicit zero padding, never stale preceding data.
  if not output.appendRaw(work.page, work): return false
  work.filled = 0
  true
proc appendPaged(output: PagedOutput, bytes: openArray[byte], work: var Build): bool =
  ## Stream arbitrary bounded records through one page without a dataset-sized payload buffer.
  var cursor = 0
  while cursor < bytes.len:
    # The page's actual remaining capacity bounds both input/output windows.
    let count = min(bytes.len-cursor, 4096-work.filled)
    for index in 0..<count: work.page[work.filled+index] = bytes[cursor+index] # Bounded copy.
    work.filled += count
    cursor += count
    if work.filled == 4096 and not output.flush(work): return false
  work.status == FullPagedBuildError.None
proc checkExtent(input: PagedInput, expected: uint64, work: var Build): bool =
  ## Construction requires an initially empty real output and an exact final artifact EOF.
  let callback = input.extent
  if callback == nil:
    work.fail(FullPagedBuildError.Uninitialized)
    return false
  if not work.charge(Channel.IO, 1): return false
  var actual = 0'u64
  if not callback(actual): work.fail(FullPagedBuildError.IOFailure)
  elif actual != expected: work.fail(FullPagedBuildError.ChangedInput)
  work.status == FullPagedBuildError.None
proc emitTree(output: PagedOutput, shape: PagedGeometry, first, width: uint64,
    work: var Build): FullPagedDigest =
  ## Postorder generation rereads only completed body pages; recursion is bounded by checked geometry.
  result = default(FullPagedDigest)
  if work.status != FullPagedBuildError.None: return
  if width == 1:
    # Padding leaves have no physical body bytes and their own full-format domain.
    if first < shape.dataPages:
      let callback = output.source.read
      if callback == nil:
        work.fail(FullPagedBuildError.Uninitialized)
        return
      if not work.charge(Channel.IO, 1) or not work.charge(Channel.Read, 4096): return
      var raw = default(array[4096, byte])
      if not callback(PagedOffset(first*4096), raw):
        work.fail(FullPagedBuildError.IOFailure)
        return
      if not work.charge(Channel.Hash, 1): return
      let hashed = fullPagedLeafDigest(shape, PageOrdinal(first), raw)
      if not work.codec(hashed.error): return
      result = hashed.value
    else:
      if not work.charge(Channel.Hash, 1): return
      let hashed = fullPagedPaddingDigest(shape, PageOrdinal(first))
      if not work.codec(hashed.error): return
      result = hashed.value
  else:
    # Every subtree emits its children before its own full-domain ordered digest.
    let left = output.emitTree(shape, first, width div 2, work)
    let right = output.emitTree(shape, first+width div 2, width div 2, work)
    if not work.charge(Channel.Hash, 1): return
    let hashed = fullPagedNodeDigest(left, right)
    if not work.codec(hashed.error): return
    result = hashed.value
  discard output.appendRaw(array[32, byte](result), work)
proc fingerprint(previous: FullPagedDigest, bytes: seq[byte], work: var Build): FullPagedDigest =
  ## Replay binds complete canonical physical bytes, including the masked physical-left bit.
  result = default(FullPagedDigest)
  if not work.charge(Channel.Hash, 1): return
  if bytes.len > high(int)-32:
    work.fail(FullPagedBuildError.LimitExceeded)
    return
  var raw = newSeq[byte](32+bytes.len)
  let prior = array[32, byte](previous)
  for index in 0..<32: raw[index] = prior[index] # Prior fixed-width chain.
  for index in 0..<bytes.len: raw[32+index] = bytes[index] # One bounded canonical record.
  let hashed = blake2b256(raw)
  if hashed.error != CryptoError.None:
    discard work.codec(FullPagedError.BackendFailure)
    return
  result = FullPagedDigest(array[32, byte](hashed.value))
proc buildFullPaged*(output: PagedOutput, scratch: FullPagedScratch,
    producer: nil FullPagedProducer, header: FullPagedHeader,
    limits: FullPagedBuildLimits, context: openArray[byte] = []): FullPagedBuildResult =
  ## Two identical bounded passes construct immutable bytes, followed by complete graph admission.
  var work = Build(status: FullPagedBuildError.None, limits: limits)
  let callback = producer
  if callback == nil or not header.initialized:
    return FullPagedBuildResult(status: FullPagedBuildError.Uninitialized)
  let shape = header.geometry
  let contextPolicy = validateFullPagedContextSize(shape.contextBytes,
      limits.admission.contextBytes)
  if contextPolicy == FullPagedStreamError.UnsupportedPolicy:
    return FullPagedBuildResult(status: FullPagedBuildError.UnsupportedPolicy) # Physical context mode is explicit.
  if contextPolicy != FullPagedStreamError.None:
    return FullPagedBuildResult(status: FullPagedBuildError.LimitExceeded) # Independent opaque byte cap.
  if uint64(context.len) != shape.contextBytes:
    return FullPagedBuildResult(status: FullPagedBuildError.CodecFailure,
        codecCause: FullPagedError.InvalidFormat) # Exact borrowed stable context is mandatory before source dispatch.
  let available = uint64(limits.admission.workingBytes)
  if available < FullPagedFixedBytes or
      uint64(limits.admission.trie.perValue) > (available-FullPagedFixedBytes) div 4:
    return FullPagedBuildResult(status: FullPagedBuildError.LimitExceeded)
  let writeLimit = uint64(limits.writeBytes)
  let datasetLimit = uint64(limits.admission.dataset.bytes)
  let recordLimit = uint64(limits.admission.dataset.entries)
  let rootsLimit = uint64(limits.admission.roots)
  let scratchLimit = uint64(limits.admission.scratchBytes) div 2
  if shape.byteLength > writeLimit or shape.byteLength > datasetLimit or
      shape.entries > recordLimit or uint64(header.len) > rootsLimit or shape.entries > scratchLimit:
    return FullPagedBuildResult(status: FullPagedBuildError.LimitExceeded)
  if uint64(limits.admission.cachePages) > 1:
    return FullPagedBuildResult(status: FullPagedBuildError.GraphFailure,
      graphCause: FullPagedStreamError.UnsupportedPolicy, graphCodec: FullPagedError.Uninitialized)
  if shape.entries >= high(uint64) div 2 or
      (shape.entries+1)*2 > uint64(limits.producerCalls):
    return FullPagedBuildResult(status: FullPagedBuildError.LimitExceeded)
  if not scratch.input.checkExtent(shape.entries*2, work): return work.refused
  if not output.source.checkExtent(0, work): return work.refused
  if not output.appendRaw(header.bytes, work): return work.refused
  var expected = default(FullPagedDigest)
  for pass in 0..1:
    # First pass writes only index rows; second pass must reproduce every full canonical record byte.
    var scan = initFullPagedIndexScan(shape)
    var offset = 0'u64
    var observed = default(FullPagedDigest)
    for ordinal in 0'u64..<shape.entries:
      # Fresh detached output prevents a producer from accidentally reusing the preceding record.
      if not work.charge(Channel.Producer, 1): return work.refused
      var record = default(TrieRecord)
      if callback(pass, ordinal, record) != FullPagedProducerStep.Item:
        work.fail(FullPagedBuildError.ProducerFailure)
        return work.refused
      let count = (if record.payload.len > 32: 2'u64 else: 1'u64)
      if not work.charge(Channel.Hash, count): return work.refused
      let encoded = encodeFullPagedRecord(record, limits.admission.trie.perValue)
      if not work.codec(encoded.error): return work.refused
      let wire = encoded.value
      let row = initFullPagedRow(shape, record.digest, offset, uint64(wire.len))
      if not work.codec(row.error): return work.refused
      let admitted = scan.admit(row.value.bytes)
      if not work.codec(admitted.error): return work.refused
      observed = fingerprint(observed, wire, work)
      if work.status != FullPagedBuildError.None: return work.refused
      if pass == 0:
        # Canonical index bytes can stream before payload replay begins.
        if not output.appendPaged(row.value.bytes, work): return work.refused
      else:
        if not output.appendPaged(wire, work): return work.refused
      offset += uint64(wire.len)
    if not work.codec(scan.finish): return work.refused
    if not work.charge(Channel.Producer, 1): return work.refused
    var final = default(TrieRecord)
    if callback(pass, shape.entries, final) != FullPagedProducerStep.End:
      work.fail(FullPagedBuildError.ProducerFailure)
      return work.refused
    if not output.flush(work): return work.refused
    if pass == 0: expected = observed
    elif array[32, byte](observed) != array[32, byte](expected):
      # Equal JAM roots do not authorize changed physical child identities on the second pass.
      work.fail(FullPagedBuildError.ChangedInput)
      return work.refused
  if shape.contextBytes > 0:
    # Only V2 writes a separate context section; V1 retains its exact previous IO schedule.
    if not output.source.checkExtent(uint64(shape.contextOffset), work): return work.refused
    if not output.appendPaged(context, work): return work.refused
    if not output.flush(work): return work.refused
  if not output.source.checkExtent(uint64(shape.treeOffset), work): return work.refused
  let root = output.emitTree(shape, 0, shape.treeLeaves, work)
  if work.status != FullPagedBuildError.None: return work.refused
  if not output.source.checkExtent(shape.byteLength, work): return work.refused
  let manifest = encodeFullPagedManifest(header, root)
  if not work.codec(manifest.error): return work.refused
  let admitted = validateFullPaged(output.source, scratch, header, manifest.value, limits.admission)
  if admitted.error != FullPagedStreamError.None:
    let reason = if admitted.error == FullPagedStreamError.CodecFailure: admitted.codecError else:
      FullPagedError.Uninitialized
    return FullPagedBuildResult(status: FullPagedBuildError.GraphFailure,
      graphCause: admitted.error, graphCodec: reason)
  if array[32, byte](admitted.value.fingerprint) != array[32, byte](expected):
    return FullPagedBuildResult(status: FullPagedBuildError.ChangedInput)
  FullPagedBuildResult(status: FullPagedBuildError.None,
    completed: FullPagedBuildReceipt(checked: admitted.value, calls: work.calls, io: work.io,
      hashes: work.hashes, read: work.read, written: work.written))

proc compactFullPaged*(output: PagedOutput, source: PagedInput, scratch: FullPagedScratch,
    checked: CheckedFullPagedArtifact, target: FullPagedHeader,
    limits: FullPagedCompactionLimits): FullPagedBuildResult =
  ## Exact source-derived physical rewrite changes only epoch and local digests; no caller producer or history replacement exists.
  if not checked.initialized or not target.initialized:
    return FullPagedBuildResult(status: FullPagedBuildError.Uninitialized)
  let original = checked.header
  if uint64(original.epoch) == high(uint64):
    return FullPagedBuildResult(status: FullPagedBuildError.LimitExceeded)
  if uint64(target.epoch) != uint64(original.epoch)+1:
    return FullPagedBuildResult(status: FullPagedBuildError.ChangedInput)
  let prior = original.bytes
  let next = target.bytes
  for index in 0..<PagedPageBytes:
    # All canonical header bytes except the positive physical epoch must remain exactly identical.
    if (index < 64 or index >= 72) and prior[index] != next[index]:
      return FullPagedBuildResult(status: FullPagedBuildError.ChangedInput)
  let inherited = checked.limits
  var work = Build(status: FullPagedBuildError.None,
    limits: FullPagedBuildLimits(admission: inherited, ioCalls: limits.ioCalls,
      hashes: limits.hashes, readBytes: limits.readBytes, writeBytes: limits.writeBytes))
  let shape = original.geometry
  if shape.byteLength > uint64(limits.writeBytes):
    return FullPagedBuildResult(status: FullPagedBuildError.LimitExceeded)
  if not scratch.input.checkExtent(shape.entries*2, work): return work.refused
  if not source.checkExtent(shape.byteLength, work): return work.refused
  if not output.source.checkExtent(0, work): return work.refused
  for ordinal in 0'u64..<shape.dataPages:
    # Full authenticated source pages retain exact index/payload padding and every complete physical child bit.
    let depth = uint64(shape.treeDepth)
    if not work.charge(Channel.IO, depth+3): return work.refused
    if not work.charge(Channel.Hash, depth+1): return work.refused
    if not work.charge(Channel.Read, 4096+depth*32): return work.refused
    let fetched = fetchFullPagedPage(source, checked, PageOrdinal(ordinal))
    if work.status != FullPagedBuildError.None: return work.refused
    if fetched.error != FullPagedStreamError.None:
      let reason = if fetched.error == FullPagedStreamError.CodecFailure: fetched.codecError else:
        FullPagedError.Uninitialized
      return FullPagedBuildResult(status: FullPagedBuildError.GraphFailure,
        graphCause: fetched.error, graphCodec: reason)
    if ordinal == 0:
      # Source header still binds the captured checked position before any target byte is appended.
      if fetched.value != prior: return FullPagedBuildResult(
          status: FullPagedBuildError.ChangedInput)
      if not output.appendRaw(next, work): return work.refused
    else:
      if not output.appendRaw(fetched.value, work): return work.refused
  if not source.checkExtent(shape.byteLength, work): return work.refused
  if not output.source.checkExtent(uint64(shape.treeOffset), work): return work.refused
  let root = output.emitTree(shape, 0, shape.treeLeaves, work)
  if work.status != FullPagedBuildError.None: return work.refused
  if not output.source.checkExtent(shape.byteLength, work): return work.refused
  let selected = encodeFullPagedManifest(target, root)
  if not work.codec(selected.error): return work.refused
  let admitted = validateFullPaged(output.source, scratch, target, selected.value, inherited)
  if admitted.error != FullPagedStreamError.None:
    let reason = if admitted.error == FullPagedStreamError.CodecFailure: admitted.codecError else:
      FullPagedError.Uninitialized
    return FullPagedBuildResult(status: FullPagedBuildError.GraphFailure,
      graphCause: admitted.error, graphCodec: reason)
  if array[32, byte](admitted.value.fingerprint) != array[32, byte](checked.fingerprint):
    return FullPagedBuildResult(status: FullPagedBuildError.ChangedInput)
  FullPagedBuildResult(status: FullPagedBuildError.None,
    completed: FullPagedBuildReceipt(checked: admitted.value, io: work.io,
      hashes: work.hashes, read: work.read, written: work.written))
