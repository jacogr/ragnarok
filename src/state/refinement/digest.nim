# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Derive and encode GP C work digests only from completed source-bound refinement report items.
## Public immutable owners expose copies; borrowed codec spans never escape their matching scratch pool.

import ../../codec/[bounded, natural, composite]
import ../../codec/work/[package as work_package, digest as work_digest]
import ../../crypto/primitives
import ../../pvm/host_fetch
import ./report as refinement_report

type
  RefinementDigestError* {.pure.} = enum ## Local failures never expose an encoded prefix or invented digest fields.
    Uninitialized, None, InvalidReport, LimitExceeded, InvalidIndex, NotSuccess, BackendFailure,
    EncodingFailure
  RefinementDigestLimits* = object ## Independent hashing-work and retained-encoding policies never alter protocol results.
    items*: ElementLimit
    payload*, totalPayload*, encoding*, totalEncoding*: ByteLimit
  RefinementDigestInfo* = object ## Copied fixed fields have no detachable borrowed output span or writable source authority.
    item*: FetchItemIndex
    service*: ServiceIndex
    codeHash*: CodeHash
    payloadHash*: PayloadHash
    accumulateGas*: Gas
    kind*: WorkKind
    refine*: RefineLoad
    outputBytes*, encodedBytes*: uint64
  DigestData = ref object ## Immutable item storage retains its actual final result and canonical wire bytes without cycles.
    source: RefinedWorkItem
    info: RefinementDigestInfo
    wire: seq[byte]
  RefinedDigest* = object ## A default handle has no digest; empty Success is an explicit owned selection.
    data: nil DigestData
  DigestsData = ref object ## Original report and ordered digest owners remain bound for later report assembly.
    report: RefinedPackage
    items: seq[RefinedDigest]
    encodedBytes: uint64
  RefinementDigests* = object ## This refinement projection grants no authorization or availability certificate.
    data: nil DigestsData
  RefinementDigestResult*[T] = object ## Private alternatives guard complete values under checked optimized execution.
    case status: RefinementDigestError
    of None:
      completed: T
    else:
      discard # Default and failures carry only a reason, never a partially hashed/encoded owner.
  DigestPlan = object ## Bounded private preflight facts authorize subsequent copies, hashing and exact allocation.
    source: RefinedWorkItem
    item: FetchItemIndex
    fields: WorkDigest
    payloadBytes, outputBytes, encodedBytes: int

func error*[T](outcome: RefinementDigestResult[T]): RefinementDigestError =
  ## Inspect a reason without writable discriminator access.
  outcome.status
func value*[T](outcome: RefinementDigestResult[T]): T
    {.requires: outcome.status == RefinementDigestError.None.} =
  ## Extract only a complete selected result.
  outcome.completed
proc digestCount*(digests: RefinementDigests): RefinementDigestResult[int] =
  ## Inspect only an initialized complete ordered projection.
  let data = digests.data
  if data == nil: return RefinementDigestResult[int](status: RefinementDigestError.Uninitialized)
  RefinementDigestResult[int](status: RefinementDigestError.None, completed: data.items.len)
proc digestEncodedBytes*(digests: RefinementDigests): RefinementDigestResult[uint64] =
  ## Report the exact occupied canonical encoding size, excluding sequence/container framing.
  let data = digests.data
  if data == nil: return RefinementDigestResult[uint64](status: RefinementDigestError.Uninitialized)
  RefinementDigestResult[uint64](status: RefinementDigestError.None, completed: data.encodedBytes)
proc digestReport*(digests: RefinementDigests): RefinementDigestResult[RefinedPackage] =
  ## Retain the original report, including its matching ordered export/trace selection.
  let data = digests.data
  if data == nil: return RefinementDigestResult[RefinedPackage](
      status: RefinementDigestError.Uninitialized)
  RefinementDigestResult[RefinedPackage](status: RefinementDigestError.None, completed: data.report)
proc digestAt*(digests: RefinementDigests, index: FetchItemIndex): RefinementDigestResult[
    RefinedDigest] =
  ## Check the full-width nominal index before narrowing into the bounded item sequence.
  let data = digests.data
  if data == nil: return RefinementDigestResult[RefinedDigest](
      status: RefinementDigestError.Uninitialized)
  if uint64(index) >= uint64(data.items.len):
    return RefinementDigestResult[RefinedDigest](status: RefinementDigestError.InvalidIndex)
  RefinementDigestResult[RefinedDigest](status: RefinementDigestError.None, completed: data.items[
      int(uint64(index))])
proc digestInfo*(digest: RefinedDigest): RefinementDigestResult[RefinementDigestInfo] =
  ## Copy selected fixed fields without exposing wire storage or an output span.
  let data = digest.data
  if data == nil: return RefinementDigestResult[RefinementDigestInfo](
      status: RefinementDigestError.Uninitialized)
  RefinementDigestResult[RefinementDigestInfo](status: RefinementDigestError.None,
      completed: data.info)
proc digestSource*(digest: RefinedDigest): RefinementDigestResult[RefinedWorkItem] =
  ## Extract only this digest's original immutable final item.
  let data = digest.data
  if data == nil: return RefinementDigestResult[RefinedWorkItem](
      status: RefinementDigestError.Uninitialized)
  RefinementDigestResult[RefinedWorkItem](status: RefinementDigestError.None,
      completed: data.source)
proc digestBytes*(digest: RefinedDigest): RefinementDigestResult[seq[byte]] =
  ## Return an independent complete canonical byte copy; callers may borrow/decode their own copy explicitly.
  let data = digest.data
  if data == nil: return RefinementDigestResult[seq[byte]](
      status: RefinementDigestError.Uninitialized)
  var bytes = newSeq[byte](data.wire.len)
  for index in 0..<bytes.len: bytes[index] = data.wire[
      index] # Retained canonical bytes cannot be mutated through extraction.
  RefinementDigestResult[seq[byte]](status: RefinementDigestError.None, completed: bytes)
proc digestOutput*(digest: RefinedDigest): RefinementDigestResult[seq[byte]] =
  ## Copy final Success bytes only; all work errors remain payload-free, including Oversize and BadExports.
  let data = digest.data
  if data == nil: return RefinementDigestResult[seq[byte]](
      status: RefinementDigestError.Uninitialized)
  if data.info.kind != WorkKind.Success:
    return RefinementDigestResult[seq[byte]](status: RefinementDigestError.NotSuccess)
  RefinementDigestResult[seq[byte]](status: RefinementDigestError.None,
      completed: data.source.refinedOutput.value)

proc prepareRefinementDigests*(report: RefinedPackage, limits: RefinementDigestLimits):
    RefinementDigestResult[RefinementDigests] =
  ## Preflight all source-bound sizes and metrics before payload/output copying, then hash/encode atomically.
  template fail(reason: RefinementDigestError) =
    return RefinementDigestResult[RefinementDigests](status: reason)
  let described = report.reportInfo
  if described.error != RefinementReportError.None: fail(RefinementDigestError.InvalidReport)
  let count = described.value.items
  if uint64(count) > uint64(limits.items): fail(RefinementDigestError.LimitExceeded)
  var plans = newSeqOfCap[DigestPlan](count)
  var payloadTotal = 0'u64
  var encodingTotal = 0'u64
  for index in 0..<count:
    let selected = report.reportItem(FetchItemIndex(uint64(index))).value
    let final = selected.refinedInfo.value
    let source = selected.refinedSource.value
    let declaration = source.workItemInfo.value
    let payload = uint64(declaration.payloadBytes)
    if payload > uint64(limits.payload) or payloadTotal > uint64(limits.totalPayload) or
        payload > uint64(limits.totalPayload)-payloadTotal:
      fail(RefinementDigestError.LimitExceeded) # Prove aggregate hashing work before copying even the first payload.
    payloadTotal += payload
    var extrinsicBytes = 0'u64
    for extrinsic in 0..<declaration.extrinsics:
      let size = uint64(uint32(source.extrinsicAt(extrinsic).value.length))
      if size > high(uint64)-extrinsicBytes: fail(RefinementDigestError.InvalidReport)
      extrinsicBytes += size # Full-width sum uses declared lengths, never fetched preimage bytes.
    if final.outputBytes > 49152: fail(RefinementDigestError.InvalidReport) # I bounds final Success before host-int conversion.
    let outputSize = int(final.outputBytes)
    let resultKind = if final.kind == WorkKind.Success:
      successfulWork(BlobSpan(offset: 0, length: outputSize))
    else:
      failedWork(final.kind) # C preserves all six final protocol work errors without success bytes.
    let load = RefineLoad(gasUsed: final.gasUsed, imports: ImportCount(uint64(declaration.imports)),
      exports: declaration.exports, extrinsicCount: ExtrinsicCount(uint64(declaration.extrinsics)),
      extrinsicSize: ExtrinsicBytes(extrinsicBytes))
    let work = measureWork(resultKind, outputSize, ByteLimit(final.outputBytes))
    if work.error != CompositeError.None: fail(RefinementDigestError.EncodingFailure)
    var size = 76+work.written # Work output <=49162 bytes proves fixed-prefix addition fits host int.
    for metric in [uint64(load.gasUsed), uint64(load.imports), uint64(load.extrinsicCount),
        uint64(load.extrinsicSize), uint64(load.exports)]:
      size += natural.encode(JamNatural(metric)).len # Five canonical naturals add at most 45 bytes; no allocation or overflow.
    if uint64(size) > uint64(limits.encoding) or encodingTotal > uint64(limits.totalEncoding) or
        uint64(size) > uint64(limits.totalEncoding)-encodingTotal:
      fail(RefinementDigestError.LimitExceeded) # Exact occupied size admits tight caps, including error-only digests.
    encodingTotal += uint64(size)
    plans.add(DigestPlan(source: selected, item: final.item, payloadBytes: declaration.payloadBytes,
      outputBytes: outputSize, encodedBytes: size, fields: WorkDigest(service: declaration.service,
        codeHash: declaration.codeHash, accumulateGas: declaration.accumulateGas,
        output: resultKind, refine: load)))
  var digests = newSeqOfCap[RefinedDigest](count)
  for plan in plans:
    var payload = newSeq[byte](plan.payloadBytes)
    if plan.source.refinedSource.value.copyItemPayload(payload).error != PackageError.None:
      fail(RefinementDigestError.InvalidReport) # A broken source contract cannot fabricate a payload commitment.
    let hash = blake2b256(payload)
    if hash.error != CryptoError.None: fail(RefinementDigestError.BackendFailure)
    var fields = plan.fields
    fields.payloadHash = PayloadHash(array[32, byte](hash.value))
    let output = if fields.output.kind == WorkKind.Success:
      plan.source.refinedOutput.value
    else:
      newSeq[byte]() # No raw invocation output is available for rejected final results.
    var wire = newSeq[byte](plan.encodedBytes)
    let encoded = encodeDigestBorrowed(fields, output, ByteLimit(uint64(plan.outputBytes)), wire)
    if encoded.error != CompositeError.None: fail(RefinementDigestError.EncodingFailure)
    digests.add(RefinedDigest(data: DigestData(source: plan.source, wire: wire,
      info: RefinementDigestInfo(item: plan.item, service: fields.service,
        codeHash: fields.codeHash,
        payloadHash: fields.payloadHash, accumulateGas: fields.accumulateGas,
        kind: fields.output.kind,
        refine: fields.refine, outputBytes: uint64(plan.outputBytes), encodedBytes: uint64(
            encoded.written)))))
  RefinementDigestResult[RefinementDigests](status: RefinementDigestError.None,
    completed: RefinementDigests(data: DigestsData(report: report, items: digests,
        encodedBytes: encodingTotal)))
