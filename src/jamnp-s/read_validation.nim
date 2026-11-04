# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded CE128/129/136/143 content checks and exact CE142 bare-FIN acknowledgments.
## Checked blocks remain structural/query-bound inputs for GP admission; partial state never becomes a full map here.
import std/assertions
import ./read_stream
import ../chain/[genesis, parameters, reports]
import ../codec/[bounded, header, assurances, tickets, composite, block_codec, natural]
import ../codec/state/[layout, trie, service_values]
import ../state/range_proof
import ../crypto/primitives

type
  ReadVerificationError* {.pure.} = enum ## Failed/default results contain no accepted response prefix.
    Uninitialized, None, InvalidRequest, InvalidConfig, InvalidFormat, NoSource,
    IdentityMismatch, LimitExceeded, HashMismatch, InvalidSequence, StateFailure,
    BlockFailure, ReportFailure, BackendFailure
  ReadVerificationResult*[T] = object ## Private success and genuine child failure alternatives preserve their actual meaning.
    case status: ReadVerificationError
    of None: completed: T
    of StateFailure: stateReason: RangeProofError
    of BlockFailure: blockReason: FrameResult[BlockRead]
    of ReportFailure: reportReason: OwnershipError
    else: discard # No source, body or cursor exists in ordinary failure/default alternatives.
  ReadSource* = object ## Detached fixed metadata is captured from one explicit full-state snapshot, never a peer root.
    available: bool
    hash: BlockHash
    posterior: StateRoot
    cores: CoreCount
    population: ValidatorCount
    epoch: EpochSlots
  ReadVerificationLimits* = object ## Local work/byte policies are distinct from the request's protocol maximum.
    wireBytes*: ByteLimit
    blocks*: ElementLimit
    frame*: FrameConfig
    map*: StateTrieLimits
  CheckedKind {.pure.} = enum ## Dense internal payload tags remain separate from sparse protocol selector numbers.
    Blocks, State, Report, Preimage, Acknowledgment
  ReplyData = ref object ## Immutable response ownership contains no native stream, canonical map or selected-state alias.
    request: ReadRequest
    case kind: CheckedKind
    of Blocks:
      blocks: seq[OwnedBlock]
      hashes: seq[BlockHash]
    of State: page: VerifiedStateRange
    of Report: report: OwnedReport
    of Acknowledgment: discard # A transport acknowledgment grants no content, request-state or inclusion authority.
    of Preimage:
      blob: seq[byte]
      hash: ServicePreimageHash
  CheckedReadReply* = object ## Strength is explicit by kind: linked structural blocks, authenticated state page, or full-hash preimage.
    data: nil ReplyData
  FrameParts = object ## Private checked offsets never escape independently of the synchronous input owner.
    firstStart, firstStop, secondStart, secondStop: int
func error*[T](outcome: ReadVerificationResult[T]): ReadVerificationError =
  ## Only the private result tag is unconditionally readable.
  outcome.status
func value*[T](outcome: ReadVerificationResult[T]): T {.requires: outcome.status ==
    ReadVerificationError.None.} =
  ## Extract only a complete source or checked response after successful selection.
  outcome.completed
func stateError*[T](outcome: ReadVerificationResult[
    T]): RangeProofError {.requires: outcome.status == ReadVerificationError.StateFailure.} =
  ## Read the actual failed state verifier's reason, not a fabricated default cause.
  outcome.stateReason
proc blockFailure*[T](outcome: ReadVerificationResult[T]): FrameResult[
    BlockRead] {.requires: outcome.status == ReadVerificationError.BlockFailure.} =
  ## Preserve precise component/limit errors from the actual failed block codec.
  outcome.blockReason
func reportError*[T](outcome: ReadVerificationResult[
    T]): OwnershipError {.requires: outcome.status == ReadVerificationError.ReportFailure.} =
  ## Preserve only the actual failed complete report decoder's cause, never an earlier decoded prefix.
  outcome.reportReason
func valid*(source: ReadSource): bool =
  ## A default source never supplies a state root or decoding profile.
  source.available
func blockHash*(source: ReadSource): BlockHash {.requires: source.available.} =
  ## The hash remains bound to its independently captured posterior root.
  source.hash
func stateRoot*(source: ReadSource): StateRoot {.requires: source.available.} =
  ## This is the complete selected snapshot's posterior commitment, never a root carried by response bytes.
  source.posterior
proc captureReadSource*(saved: BlockSnapshotResult): ReadVerificationResult[ReadSource] =
  ## Copy fixed context in a staging activation; no map/header ARC alias survives into CPU verification.
  if saved.error != GenesisError.None: return ReadVerificationResult[ReadSource](
      status: ReadVerificationError.NoSource)
  let snapshot = saved.value
  if snapshot.fuzzSeedOnly: return ReadVerificationResult[ReadSource](
      status: ReadVerificationError.NoSource)
  let profile = snapshot.chainParameters
  if not profile.valid: return ReadVerificationResult[ReadSource](
      status: ReadVerificationError.InvalidConfig)
  ReadVerificationResult[ReadSource](status: ReadVerificationError.None, completed: ReadSource(
    available: true, hash: snapshot.blockHash, posterior: snapshot.stateRoot,
    cores: snapshot.cores, population: snapshot.activeValidators, epoch: EpochSlots(profile.get(epochPeriod))))
func valid*(reply: CheckedReadReply): bool =
  ## Default checked replies grant neither decoded blocks nor authenticated content.
  reply.data != nil
proc checkedData(reply: CheckedReadReply): ReplyData {.requires: reply.valid.} =
  ## Refine one stable private immutable owner before success-only extraction.
  let data = reply.data
  assert data != nil
  data
proc kind*(reply: CheckedReadReply): ReadKind {.requires: reply.valid.} =
  ## The kind identifies the checks performed and the remaining downstream authority boundary.
  case reply.checkedData.kind
  of CheckedKind.Blocks: ReadKind.Blocks
  of CheckedKind.Report: ReadKind.Report
  of CheckedKind.State: ReadKind.State
  of CheckedKind.Preimage: ReadKind.Preimage
  of CheckedKind.Acknowledgment: ReadKind.PreimageAnnouncement
proc request*(reply: CheckedReadReply): ReadRequest {.requires: reply.valid.} =
  ## Retain the exact query whose count, direction, range or content identity was checked.
  reply.checkedData.request
proc blockCount*(reply: CheckedReadReply): int {.requires: reply.valid and reply.kind ==
    ReadKind.Blocks.} =
  ## Structural blocks still require ordinary GP execution/consensus admission before adoption.
  reply.checkedData.blocks.len
proc blockAt*(reply: CheckedReadReply, index: int): OwnedBlock {.requires: reply.valid and
    reply.kind == ReadKind.Blocks and index >= 0 and index < reply.blockCount.} =
  ## Return an immutable exact decoded block, without claiming a state transition certificate.
  reply.checkedData.blocks[index]
proc hashAt*(reply: CheckedReadReply, index: int): BlockHash {.requires: reply.valid and
    reply.kind == ReadKind.Blocks and index >= 0 and index < reply.blockCount.} =
  ## Sealed-header hashes bind the sequence to the requested anchor and parent links.
  reply.checkedData.hashes[index]
proc workReport*(reply: CheckedReadReply): OwnedReport {.requires: reply.valid and reply.kind ==
    ReadKind.Report.} =
  ## Full-hash-bound complete report ownership grants no guarantee, judgment, execution or availability certificate.
  reply.checkedData.report
proc statePage*(reply: CheckedReadReply): VerifiedStateRange {.requires: reply.valid and
    reply.kind == ReadKind.State.} =
  ## A verified partial page is distinct from a complete StateStore snapshot.
  reply.checkedData.page
proc preimageHash*(reply: CheckedReadReply): ServicePreimageHash {.requires: reply.valid and
    reply.kind == ReadKind.Preimage.} =
  ## This full digest was checked over the entire returned blob.
  reply.checkedData.hash
proc preimageByteLength*(reply: CheckedReadReply): int {.requires: reply.valid and reply.kind ==
    ReadKind.Preimage.} =
  ## Length observation avoids a blob copy during bounded offer/cache admission.
  reply.checkedData.blob.len
proc preimageBytes*(reply: CheckedReadReply): seq[byte] {.requires: reply.valid and reply.kind ==
    ReadKind.Preimage.} =
  ## Copy immutable verified content; no mutable response storage escapes.
  let data = reply.checkedData
  result = @[]
  for index in 0..<data.blob.len: result.add(data.blob[index])
func e4(input: openArray[byte], offset: int): uint64 {.requires: offset >= 0 and offset <=
    input.len and input.len-offset >= 4.} =
  ## Widen before shifts; callers prove four complete bytes before decoding a length or maximum.
  result = 0
  for index in 0..<4: result = result or (uint64(input[offset+index]) shl (index*8))
func hash(input: openArray[byte]): array[32, byte] {.requires: input.len >= 32.} =
  ## Fixed request extents were admitted by ReadRequest before any content identity extraction.
  result = default(array[32, byte])
  for index in 0..<32: result[index] = input[index]
func key(input: openArray[byte], offset: int): StateKey {.requires: offset >= 0 and offset <=
    input.len and input.len-offset >= 31.} =
  ## Serialized state identities are exactly31 bytes, without a reconstructed final key byte.
  var copied = default(array[31, byte])
  for index in 0..<31: copied[index] = input[offset+index]
  StateKey(copied)
proc copyBytes(input: openArray[byte], first, stop: int): seq[byte] {.requires: first >= 0 and
    stop >= first and stop <= input.len.} =
  ## Capture only an already bounded exact extent after all arithmetic checks.
  result = newSeq[byte](stop-first)
  for index in 0..<result.len: result[index] = input[first+index]
proc parts(wire: openArray[byte], count: int): ReadVerificationResult[FrameParts] =
  ## Parse exactly one/two E4 messages with no suffix; all offsets remain bounded by the caller's hard wire ceiling.
  if wire.len < 4: return ReadVerificationResult[FrameParts](
      status: ReadVerificationError.InvalidFormat)
  let first = e4(wire, 0)
  if first > uint64(wire.len-4): return ReadVerificationResult[FrameParts](
      status: ReadVerificationError.InvalidFormat)
  let stop = 4+int(first)
  if count == 1:
    if stop != wire.len: return ReadVerificationResult[FrameParts](
        status: ReadVerificationError.InvalidFormat)
    return ReadVerificationResult[FrameParts](status: ReadVerificationError.None,
        completed: FrameParts(firstStart: 4, firstStop: stop))
  if wire.len-stop < 4: return ReadVerificationResult[FrameParts](
      status: ReadVerificationError.InvalidFormat)
  let second = e4(wire, stop)
  if second != uint64(wire.len-stop-4): return ReadVerificationResult[FrameParts](
      status: ReadVerificationError.InvalidFormat)
  ReadVerificationResult[FrameParts](status: ReadVerificationError.None, completed: FrameParts(
    firstStart: 4, firstStop: stop, secondStart: stop+4, secondStop: wire.len))
proc checkState(request: ReadRequest, wire: openArray[byte], source: ReadSource,
    limits: ReadVerificationLimits): ReadVerificationResult[CheckedReadReply] =
  ## Decode exact bare node/pair sequences, then authenticate every covered subtree against caller trust.
  let payload = request.payload
  if not source.available: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.NoSource)
  if hash(payload) != array[32, byte](source.hash): return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.IdentityMismatch)
  if not validRangeLimits(limits.map): return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.InvalidConfig)
  let frames = parts(wire, 2)
  if frames.error != ReadVerificationError.None: return ReadVerificationResult[CheckedReadReply](
      status: frames.error)
  let span = frames.value
  let nodeBytes = span.firstStop-span.firstStart
  if nodeBytes mod 64 != 0: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.InvalidFormat)
  if nodeBytes div 64 > 512: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.LimitExceeded)
  var nodes = newSeq[EncodedStateNode](nodeBytes div 64)
  for index in 0..<nodes.len:
    var encoded = default(array[64, byte])
    for offset in 0..<64: encoded[offset] = wire[span.firstStart+index*64+offset]
    nodes[index] = EncodedStateNode(encoded)
  var entries: seq[StateEntry] = @[]
  var offset = span.secondStart
  var valueBytes = 0'u64
  while offset < span.secondStop:
    if uint64(entries.len) >= uint64(limits.map.items): return ReadVerificationResult[
        CheckedReadReply](status: ReadVerificationError.LimitExceeded)
    if span.secondStop-offset < 32: return ReadVerificationResult[CheckedReadReply](
        status: ReadVerificationError.InvalidFormat)
    let identity = key(wire, offset)
    offset += 31
    let length = natural.decode(wire.toOpenArray(offset, span.secondStop-1))
    if not length.ok: return ReadVerificationResult[CheckedReadReply](
        status: ReadVerificationError.InvalidFormat)
    if int(length.consumed) > span.secondStop-offset: return ReadVerificationResult[
        CheckedReadReply](status: ReadVerificationError.InvalidFormat)
    offset += int(length.consumed)
    let size = uint64(length.value)
    if size > uint64(span.secondStop-offset): return ReadVerificationResult[CheckedReadReply](
        status: ReadVerificationError.InvalidFormat)
    if size > uint64(limits.map.perValue): return ReadVerificationResult[CheckedReadReply](
        status: ReadVerificationError.LimitExceeded)
    if size > uint64(limits.map.totalValueBytes)-valueBytes: return ReadVerificationResult[
        CheckedReadReply](status: ReadVerificationError.LimitExceeded)
    let stop = offset+int(size)
    entries.add(StateEntry(key: identity, value: copyBytes(wire, offset, stop)))
    valueBytes += size
    offset = stop # Every record consumes at least a key and one natural byte, including empty values.
  if uint64(wire.len) > e4(payload, 94) and entries.len != 1:
    return ReadVerificationResult[CheckedReadReply](status: ReadVerificationError.LimitExceeded)
  let checked = verifyStateRange(entries, nodes, source.posterior, key(payload, 32), key(payload,
      63), limits.map)
  if checked.error != RangeProofError.None:
    return ReadVerificationResult[CheckedReadReply](status: ReadVerificationError.StateFailure,
        stateReason: checked.error)
  ReadVerificationResult[CheckedReadReply](status: ReadVerificationError.None,
    completed: CheckedReadReply(
    data: ReplyData(kind: CheckedKind.State, request: request, page: checked.value)))
proc checkPreimage(request: ReadRequest, wire: openArray[byte]): ReadVerificationResult[
    CheckedReadReply] =
  ## Match the full requested hash, including empty blobs; transport identity alone supplies no content authority.
  let frames = parts(wire, 1)
  if frames.error != ReadVerificationError.None: return ReadVerificationResult[CheckedReadReply](
      status: frames.error)
  let span = frames.value
  let digest = if span.firstStart == span.firstStop: blake2b256([])
    else: blake2b256(wire.toOpenArray(span.firstStart, span.firstStop-1))
  if digest.error != CryptoError.None: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.BackendFailure)
  let expected = hash(request.payload)
  if array[32, byte](digest.value) != expected: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.HashMismatch)
  ReadVerificationResult[CheckedReadReply](status: ReadVerificationError.None,
    completed: CheckedReadReply(
    data: ReplyData(kind: CheckedKind.Preimage, request: request, hash: ServicePreimageHash(
        expected), blob: copyBytes(wire, span.firstStart, span.firstStop))))
proc checkReport(request: ReadRequest, wire: openArray[byte],
    source: ReadSource): ReadVerificationResult[CheckedReadReply] =
  ## Hash the exact one-message body and validate the complete canonical report under the local core profile.
  if not source.available: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.NoSource)
  if uint64(source.cores) < 2 or uint64(source.cores) > 341:
    return ReadVerificationResult[CheckedReadReply](status: ReadVerificationError.InvalidConfig)
  let frames = parts(wire, 1)
  if frames.error != ReadVerificationError.None: return ReadVerificationResult[CheckedReadReply](
      status: frames.error)
  let span = frames.value
  if span.firstStart == span.firstStop: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.InvalidFormat)
  let digest = blake2b256(wire.toOpenArray(span.firstStart, span.firstStop-1))
  if digest.error != CryptoError.None: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.BackendFailure)
  if array[32, byte](digest.value) != hash(request.payload):
    return ReadVerificationResult[CheckedReadReply](status: ReadVerificationError.HashMismatch)
  let parsed = decodeOwnedReport(wire.toOpenArray(span.firstStart, span.firstStop-1), uint64(source.cores))
  if parsed.error != OwnershipError.None: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.ReportFailure, reportReason: parsed.error)
  let metadata = ownedReportInfo(parsed.value)
  if metadata.error != OwnershipError.None: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.ReportFailure, reportReason: metadata.error)
  if metadata.value.consumed != span.firstStop-span.firstStart: return ReadVerificationResult[
      CheckedReadReply](status: ReadVerificationError.InvalidFormat)
  ReadVerificationResult[CheckedReadReply](status: ReadVerificationError.None,
    completed: CheckedReadReply(data: ReplyData(kind: CheckedKind.Report, request: request,
        report: parsed.value)))
proc checkBlocks(request: ReadRequest, wire: openArray[byte], source: ReadSource,
    limits: ReadVerificationLimits): ReadVerificationResult[CheckedReadReply] =
  ## Capture every exact GP block and bind hashes/slots/links/count to the query; ordinary execution/consensus remains downstream.
  if not source.available: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.NoSource)
  if uint64(limits.frame.cores) != uint64(source.cores): return ReadVerificationResult[
      CheckedReadReply](status: ReadVerificationError.InvalidConfig)
  if uint64(limits.frame.epochSlots) != uint64(source.epoch): return ReadVerificationResult[
      CheckedReadReply](status: ReadVerificationError.InvalidConfig)
  if uint64(limits.frame.validators) < uint64(source.population): return ReadVerificationResult[
      CheckedReadReply](status: ReadVerificationError.InvalidConfig)
  if uint64(limits.frame.validators) > 1023: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.InvalidConfig)
  if uint64(limits.frame.ticketLimit) > 65535: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.InvalidConfig)
  if uint64(limits.frame.preimages.items) > 16384: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.InvalidConfig)
  if uint64(limits.frame.preimages.perBlob) > uint64(
      limits.wireBytes): return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.InvalidConfig)
  if uint64(limits.frame.preimages.totalBlobBytes) > uint64(
      limits.wireBytes): return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.InvalidConfig)
  if uint64(limits.frame.maxBytes) == 0: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.InvalidConfig)
  if uint64(limits.blocks) > 64: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.InvalidConfig)
  let payload = request.payload
  let direction = payload[32]
  if direction > 1: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.InvalidRequest)
  let maximum = e4(payload, 33)
  let frames = parts(wire, 1)
  if frames.error != ReadVerificationError.None: return ReadVerificationResult[CheckedReadReply](
      status: frames.error)
  let span = frames.value
  var blocks: seq[OwnedBlock] = @[]
  var hashes: seq[BlockHash] = @[]
  var expected = hash(payload)
  var previousSlot = 0'u32
  var offset = span.firstStart
  while offset < span.firstStop:
    if uint64(blocks.len) >= maximum: return ReadVerificationResult[CheckedReadReply](
        status: ReadVerificationError.InvalidSequence)
    if uint64(blocks.len) >= uint64(limits.blocks): return ReadVerificationResult[CheckedReadReply](
        status: ReadVerificationError.LimitExceeded)
    var frame = limits.frame
    frame.maxBytes = ByteLimit(min(uint64(frame.maxBytes), uint64(span.firstStop-offset)))
    let parsed = decodeBlock(wire.toOpenArray(offset, span.firstStop-1), frame)
    if parsed.error != FrameError.None:
      return ReadVerificationResult[CheckedReadReply](status: ReadVerificationError.BlockFailure,
          blockReason: parsed)
    let consumed = parsed.value.consumed
    if consumed <= 0 or consumed > span.firstStop-offset: return ReadVerificationResult[
        CheckedReadReply](status: ReadVerificationError.InvalidFormat)
    let head = inspectHeader(wire.toOpenArray(offset, offset+consumed-1), HeaderConfig(
      cores: frame.cores, authorValidators: frame.validators, epochSlots: frame.epochSlots,
      maxBytes: frame.maxBytes))
    if head.error != HeaderError.None: return ReadVerificationResult[CheckedReadReply](
        status: ReadVerificationError.InvalidFormat)
    let info = head.value
    if info.consumed <= 0 or info.consumed > consumed: return ReadVerificationResult[
        CheckedReadReply](status: ReadVerificationError.InvalidFormat)
    let digest = blake2b256(wire.toOpenArray(offset, offset+info.consumed-1))
    if digest.error != CryptoError.None: return ReadVerificationResult[CheckedReadReply](
        status: ReadVerificationError.BackendFailure)
    let actual = array[32, byte](digest.value)
    let parent = array[32, byte](info.unsigned.parent)
    let slot = uint32(info.unsigned.slot)
    if direction == 0:
      if parent != expected: return ReadVerificationResult[CheckedReadReply](
          status: ReadVerificationError.InvalidSequence)
      if blocks.len > 0 and slot <= previousSlot: return ReadVerificationResult[CheckedReadReply](
          status: ReadVerificationError.InvalidSequence)
      expected = actual
    else:
      if actual != expected: return ReadVerificationResult[CheckedReadReply](
          status: ReadVerificationError.HashMismatch)
      if blocks.len > 0 and slot >= previousSlot: return ReadVerificationResult[CheckedReadReply](
          status: ReadVerificationError.InvalidSequence)
      expected = parent
    previousSlot = slot
    blocks.add(parsed.value.owner)
    hashes.add(BlockHash(actual))
    offset += consumed
  if direction == 1 and maximum > 0 and blocks.len == 0:
    return ReadVerificationResult[CheckedReadReply](status: ReadVerificationError.InvalidSequence)
  ReadVerificationResult[CheckedReadReply](status: ReadVerificationError.None,
    completed: CheckedReadReply(
    data: ReplyData(kind: CheckedKind.Blocks, request: request, blocks: blocks, hashes: hashes)))
proc verifyReadReply*(request: ReadRequest, wire: openArray[byte], source: ReadSource,
    limits: ReadVerificationLimits): ReadVerificationResult[CheckedReadReply] =
  ## Verify all supplied bytes atomically; no earlier block/page/blob survives a later failure.
  if not request.valid: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.InvalidRequest)
  let minimum = request.minimumReplyBytes
  if uint64(limits.wireBytes) < minimum: return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.InvalidConfig)
  if uint64(limits.wireBytes) > uint64(MaxReadReplyBytes): return ReadVerificationResult[
      CheckedReadReply](status: ReadVerificationError.InvalidConfig)
  if uint64(wire.len) > uint64(limits.wireBytes): return ReadVerificationResult[CheckedReadReply](
      status: ReadVerificationError.LimitExceeded)
  case request.kind
  of ReadKind.Blocks: checkBlocks(request, wire, source, limits)
  of ReadKind.Report: checkReport(request, wire, source)
  of ReadKind.State: checkState(request, wire, source, limits)
  of ReadKind.Preimage: checkPreimage(request, wire)
  of ReadKind.PreimageAnnouncement:
    if wire.len != 0: ReadVerificationResult[CheckedReadReply](
        status: ReadVerificationError.InvalidFormat)
    else: ReadVerificationResult[CheckedReadReply](status: ReadVerificationError.None,
      completed: CheckedReadReply(data: ReplyData(kind: CheckedKind.Acknowledgment,
          request: request)))
