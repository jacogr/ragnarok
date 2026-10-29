# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Commit to the original final ordered exports and expose GP paged-proof segments.
## This immutable source-bound component does not construct an erasure/availability certificate.

import ../../codec/[bounded, natural]
import ../../codec/work/[digest as work_digest, report as work_report]
import ../../crypto/primitives
import ../../pvm/host_fetch
import ../report/identity as report_identity
import ../authorized_refinement
import ../refinement/[digest as refinement_digest, report as refinement_report]

type
  ExportCommitmentError* {.pure.} = enum ## Default/refused results expose no partial tree or proof.
    Uninitialized, None, InvalidSource, LimitExceeded, BackendFailure, InvalidIndex
  ExportCommitmentLimits* = object ## Local budgets cover extraction count, actual allocated hash slots and hash preimage work.
    exports*, nodes*: ElementLimit
    hashBytes*: ByteLimit
  ExportPageIndex* = distinct uint64 ## Page ordinal cannot be confused with a segment, item or dictionary ordinal.
  ExportCommitmentInfo* = object ## Fixed copied commitments and resource facts contain no detachable tree storage.
    root*: SegmentRoot
    exports*: SegmentCount
    pages*, nodes*, hashBytes*: uint64
  CommitmentData = ref object ## Acyclic immutable heap retains original identity and normalized report/export provenance.
    source: ReportIdentity
    info: ExportCommitmentInfo
    capacity, depth: int
    tree: seq[SegmentRoot]
  ExportCommitment* = object ## Only completed preparation initializes an owner; empty exports remain an explicit success.
    data: nil CommitmentData
  ExportCommitmentResult*[T] = object ## Private success payloads require checked selection even in optimized builds.
    case status: ExportCommitmentError
    of None:
      completed: T
    else:
      discard # Refusals carry no root, earlier leaf prefix or caller-accessible tree.

func error*[T](outcome: ExportCommitmentResult[T]): ExportCommitmentError =
  ## Read the selected reason without permitting retagging.
  outcome.status
func value*[T](outcome: ExportCommitmentResult[T]): T
    {.requires: outcome.status == ExportCommitmentError.None.} =
  ## Extract only a complete selected result.
  outcome.completed
proc commitmentInfo*(commitment: ExportCommitment): ExportCommitmentResult[ExportCommitmentInfo] =
  ## Copy immutable aggregate facts only from a completed owner.
  let data = commitment.data
  if data == nil: return ExportCommitmentResult[ExportCommitmentInfo](
      status: ExportCommitmentError.Uninitialized)
  ExportCommitmentResult[ExportCommitmentInfo](status: ExportCommitmentError.None,
      completed: data.info)
proc commitmentSource*(commitment: ExportCommitment): ExportCommitmentResult[ReportIdentity] =
  ## Retain the exact original report identity rather than accepting a replacement source tuple.
  let data = commitment.data
  if data == nil: return ExportCommitmentResult[ReportIdentity](
      status: ExportCommitmentError.Uninitialized)
  ExportCommitmentResult[ReportIdentity](status: ExportCommitmentError.None, completed: data.source)
proc commitmentPage*(commitment: ExportCommitment, index: ExportPageIndex): ExportCommitmentResult[FetchSegment] =
  ## Copy one complete paged-proof segment; counts and sibling order follow pinned GP E(path, leaves).
  let data = commitment.data
  if data == nil: return ExportCommitmentResult[FetchSegment](
      status: ExportCommitmentError.Uninitialized)
  if uint64(index) >= data.info.pages:
    return ExportCommitmentResult[FetchSegment](status: ExportCommitmentError.InvalidIndex)
  let page = int(uint64(index)) # The page-count proof bounds this to 0..47 before narrowing/multiplication.
  let levels = max(0, data.depth-6)
  var bytes = default(array[4104, byte])
  var cursor = 0
  # Each count is encoded canonically, independent of the fixed segment's zero padding.
  template putCount(count: int) =
    block:
      let encoded = encode(JamNatural(uint64(count)))
      for position in 0..<encoded.len:
        bytes[cursor] = encoded.bytes[position]
        inc cursor
  putCount(levels)
  var node = 1
  # Trace from root toward the 64-leaf page, emitting opposite nodes in top-to-bottom order.
  for level in 0..<levels:
    let direction = (page shr (levels-level-1)) and 1
    let sibling = node*2+(1-direction)
    for octet in 0..<32:
      bytes[cursor] = data.tree[sibling].bytes[octet]
      inc cursor
    node = node*2+direction
  let first = page*64
  let count = min(64, int(uint16(data.info.exports))-first)
  putCount(count)
  # Only real segment hashes appear in partial pages; padding hashes remain tree-only.
  for leaf in 0..<count:
    for octet in 0..<32:
      bytes[cursor] = data.tree[data.capacity+first+leaf].bytes[octet]
      inc cursor
  # At most 6 siblings plus 64 leaves and two short counts occupy 2242 of 4104 bytes.
  ExportCommitmentResult[FetchSegment](status: ExportCommitmentError.None, completed: FetchSegment(bytes))
proc prepareExportCommitment*(source: ReportIdentity,
    limits: ExportCommitmentLimits): ExportCommitmentResult[ExportCommitment] =
  ## Hash only normalized final exports in package order; no public constructor accepts detached segment bytes.
  template fail(reason: ExportCommitmentError) =
    return ExportCommitmentResult[ExportCommitment](status: reason)
  if source.identityInfo.error != ReportIdentityError.None: fail(
      ExportCommitmentError.InvalidSource)
  let report = source.identitySource.value.authorizedDigests.value.digestReport.value
  let info = report.reportInfo.value
  let count = uint64(info.exports)
  # Captured report already enforces 3072; retain an explicit arithmetic bound before multiplying or narrowing.
  if count > 3072 or count > uint64(limits.exports): fail(ExportCommitmentError.LimitExceeded)
  var capacity = 1
  var depth = 0
  # With count <=3072, capacity never exceeds 4096 and depth never exceeds twelve.
  while uint64(capacity) < count:
    capacity *= 2
    inc depth
  let nodes = uint64(capacity)*2
  let hashBytes = count*4108+uint64(capacity-1)*68
  # Include heap slot zero in allocated storage policy; no extraction/hash allocation precedes either cap.
  if nodes > uint64(limits.nodes) or hashBytes > uint64(limits.hashBytes):
    fail(ExportCommitmentError.LimitExceeded)
  var tree = newSeq[SegmentRoot](int(nodes))
  var ordinal = 0
  var leafBytes = default(array[4108, byte])
  leafBytes[0] = byte('l')
  leafBytes[1] = byte('e')
  leafBytes[2] = byte('a')
  leafBytes[3] = byte('f')
  # Original final item ordering includes declared zero replacements for every non-Success result.
  for itemIndex in 0..<info.items:
    let item = report.reportItem(FetchItemIndex(uint64(itemIndex))).value
    for segmentIndex in 0..<int(uint64(item.refinedInfo.value.exports)):
      let segment = array[4104, byte](item.refinedSegment(ExportCount(uint64(segmentIndex))).value)
      for octet in 0..<4104: leafBytes[4+octet] = segment[
          octet] # Real zero segments still hash with the leaf prefix.
      let hashed = blake2b256(leafBytes)
      if hashed.error != CryptoError.None: fail(ExportCommitmentError.BackendFailure)
      tree[capacity+ordinal] = SegmentRoot(bytes: array[32, byte](hashed.value))
      inc ordinal
  var nodeBytes = default(array[68, byte])
  nodeBytes[0] = byte('n')
  nodeBytes[1] = byte('o')
  nodeBytes[2] = byte('d')
  nodeBytes[3] = byte('e')
  var node = capacity-1
  # Children already exist when their parent is hashed; absent leaves are zero hashes, never hashed zero segments.
  while node > 0:
    for octet in 0..<32:
      nodeBytes[4+octet] = tree[node*2].bytes[octet]
      nodeBytes[36+octet] = tree[node*2+1].bytes[octet]
    let hashed = blake2b256(nodeBytes)
    if hashed.error != CryptoError.None: fail(ExportCommitmentError.BackendFailure)
    tree[node] = SegmentRoot(bytes: array[32, byte](hashed.value))
    dec node
  let root = tree[1] # Copy the root before transferring private tree ownership.
  ExportCommitmentResult[ExportCommitment](status: ExportCommitmentError.None,
    completed: ExportCommitment(data: CommitmentData(source: source, capacity: capacity,
      depth: depth,
      tree: tree, info: ExportCommitmentInfo(root: root, exports: SegmentCount(uint16(count)),
        pages: (count+63) div 64, nodes: nodes, hashBytes: hashBytes))))
