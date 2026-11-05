# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Source-free original-export proof trees authenticate retained systematic shards against their genuine signed segment root.
import ./availability_proof
import ../codec/bounded
from ../codec/work/report import SegmentRoot, SegmentCount
from "../state/export/commitment" import ExportSegmentIndex
import ../crypto/primitives
from ../pvm/host/fetch import FetchSegment

type
  GuarantorSegmentError* {.pure.} = enum ## Failure carries no tree or accepted leaf prefix.
    Uninitialized, None, InvalidSource, InvalidIndex, LimitExceeded, RootMismatch, SourceFailure, BackendFailure
  GuarantorSegmentInfo* = object ## Fixed dimensions and complete computation accounting do not confer canonical or signing authority.
    root*: SegmentRoot
    exports*: SegmentCount
    depth*, retainedBytes*, workspaceBytes*, hashes*, hashBytes*: uint64
  SegmentTreeData = ref object ## Immutable tree and source-free bytes share one acyclic lifetime without original refinement/state ownership.
    source: GuarantorAvailability
    info: GuarantorSegmentInfo
    capacity: int
    tree: seq[SegmentRoot]
  GuarantorSegmentTree* = object ## Only complete root-checked construction can mint this proof owner.
    data: nil SegmentTreeData
  GuarantorSegmentResult*[T] = object ## Private selected children retain genuine source/backend refusals without successful prefixes.
    case status: GuarantorSegmentError
    of None: completed: T
    of SourceFailure: sourceReason: AvailabilityTransferResult[FetchSegment]
    of BackendFailure: cryptoReason: CryptoError
    else: discard # A failed/default result exposes no completed tree.
func error*[T](outcome: GuarantorSegmentResult[T]): GuarantorSegmentError =
  ## Select success only after reading this immutable reason.
  outcome.status
func value*[T](outcome: GuarantorSegmentResult[T]): T {.requires: outcome.status ==
    GuarantorSegmentError.None.} =
  ## Only full success carries fixed accounting or an authenticated proof owner/path.
  outcome.completed
func sourceError*[T](outcome: GuarantorSegmentResult[T]): AvailabilityTransferResult[
    FetchSegment] {.requires: outcome.status == GuarantorSegmentError.SourceFailure.} =
  ## Return only a genuine failed systematic-export extraction.
  outcome.sourceReason
func cryptoError*[T](outcome: GuarantorSegmentResult[T]): CryptoError {.requires: outcome.status ==
    GuarantorSegmentError.BackendFailure.} =
  ## Backend detail exists only after an actual failed maintained hash call.
  outcome.cryptoReason
proc guarantorSegmentPlan*(source: GuarantorAvailability): GuarantorSegmentResult[
    GuarantorSegmentInfo] =
  ## Bound every count/product and charge complete work before tree allocation or source extraction.
  let described = source.guarantorInfo
  if described.error != AvailabilityTransferError.None:
    return GuarantorSegmentResult[GuarantorSegmentInfo](status: GuarantorSegmentError.InvalidSource)
  let expected = described.value.specifier
  let count = uint64(uint16(expected.segmentCount))
  if count > 3072: return GuarantorSegmentResult[GuarantorSegmentInfo](
      status: GuarantorSegmentError.InvalidSource)
  var capacity = 1'u64
  var depth = 0'u64
  while capacity < count:
    capacity *= 2 # Count <=3072 proves capacity <=4096 before doubling or narrowing.
    inc depth
  GuarantorSegmentResult[GuarantorSegmentInfo](status: GuarantorSegmentError.None,
    completed: GuarantorSegmentInfo(root: expected.segmentRoot, exports: expected.segmentCount,
      depth: depth, retainedBytes: capacity*2*32, workspaceBytes: 3'u64*4104+4108+68,
      hashes: count+capacity-1, hashBytes: count*4108+(capacity-1)*68))
proc prepareGuarantorSegments*(source: GuarantorAvailability,
    limits: AvailabilityMerkleLimits): GuarantorSegmentResult[GuarantorSegmentTree] =
  ## Canonical GP leaf/node domains and zero-hash padding must reproduce the signed export root before any proof can escape.
  let planned = source.guarantorSegmentPlan
  if planned.error != GuarantorSegmentError.None:
    return GuarantorSegmentResult[GuarantorSegmentTree](status: GuarantorSegmentError.InvalidSource)
  let info = planned.value
  if info.retainedBytes+info.workspaceBytes > uint64(limits.bytes) or info.hashes > uint64(
      limits.hashes) or info.hashBytes > uint64(limits.hashBytes):
    return GuarantorSegmentResult[GuarantorSegmentTree](status: GuarantorSegmentError.LimitExceeded)
  let capacity = int(info.retainedBytes div 64)
  let count = int(uint16(info.exports))
  var tree = newSeq[SegmentRoot](capacity*2)
  var leaf = default(array[4108, byte])
  leaf[0] = byte('l')
  leaf[1] = byte('e')
  leaf[2] = byte('a')
  leaf[3] = byte('f')
  for index in 0..<count:
    # Each actual normalized export comes from all required systematic shards of this same immutable availability root.
    let extracted = source.guarantorSegment(ExportSegmentIndex(uint64(index)))
    if extracted.error != AvailabilityTransferError.None:
      return GuarantorSegmentResult[GuarantorSegmentTree](
        status: GuarantorSegmentError.SourceFailure,
        sourceReason: extracted)
    let segment = array[4104, byte](extracted.value)
    for position in 0..<4104: leaf[4+position] = segment[position]
    let hashed = blake2b256(leaf)
    if hashed.error != CryptoError.None:
      return GuarantorSegmentResult[GuarantorSegmentTree](
        status: GuarantorSegmentError.BackendFailure,
        cryptoReason: hashed.error)
    tree[capacity+index] = SegmentRoot(bytes: array[32, byte](hashed.value))
  var nodeBytes = default(array[68, byte])
  nodeBytes[0] = byte('n')
  nodeBytes[1] = byte('o')
  nodeBytes[2] = byte('d')
  nodeBytes[3] = byte('e')
  var node = capacity-1
  while node > 0:
    # Missing leaves remain zero hashes, matching the original computed GP constant-depth commitment exactly.
    for octet in 0..<32:
      nodeBytes[4+octet] = tree[node*2].bytes[octet]
      nodeBytes[36+octet] = tree[node*2+1].bytes[octet]
    let hashed = blake2b256(nodeBytes)
    if hashed.error != CryptoError.None:
      return GuarantorSegmentResult[GuarantorSegmentTree](
        status: GuarantorSegmentError.BackendFailure,
        cryptoReason: hashed.error)
    tree[node] = SegmentRoot(bytes: array[32, byte](hashed.value))
    dec node
  if tree[1].bytes != info.root.bytes:
    return GuarantorSegmentResult[GuarantorSegmentTree](status: GuarantorSegmentError.RootMismatch)
  GuarantorSegmentResult[GuarantorSegmentTree](status: GuarantorSegmentError.None,
    completed: GuarantorSegmentTree(data: SegmentTreeData(source: source, info: info,
      capacity: capacity, tree: tree)))
proc guarantorSegmentPath*(owner: GuarantorSegmentTree,
    index: ExportSegmentIndex): GuarantorSegmentResult[seq[SegmentRoot]] =
  ## Emit the same root-first opposite-child hashes as the genuine original export commitment.
  let data = owner.data
  if data == nil: return GuarantorSegmentResult[seq[SegmentRoot]](
      status: GuarantorSegmentError.Uninitialized)
  if uint64(index) >= uint64(uint16(data.info.exports)):
    return GuarantorSegmentResult[seq[SegmentRoot]](status: GuarantorSegmentError.InvalidIndex)
  var path = newSeq[SegmentRoot](int(data.info.depth))
  var node = 1
  for level in 0..<path.len:
    let direction = (int(uint64(index)) shr (path.len-level-1)) and 1
    path[level] = data.tree[node*2+1-direction]
    node = node*2+direction
  GuarantorSegmentResult[seq[SegmentRoot]](status: GuarantorSegmentError.None, completed: path)
