# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Verify GP constant-depth leaf inclusion and retain immutable root/index/segment/proof ownership.
## Inclusion alone grants no root freshness, package correspondence or prior-execution certificate.

import ../codec/bounded as codec_bounded
import ../codec/natural as codec_natural
import ../codec/work_package as codec_work_package
import ../codec/work_report as codec_work_report
import ../pvm/host_fetch as pvm_host_fetch
import ../crypto/primitives as crypto_primitives

type
  ImportJustificationError* {.pure.} = enum ## Refusals carry no partially authenticated segment or proof bytes.
    Uninitialized, None, InvalidProof, InvalidIndex, LimitExceeded, RootMismatch, BackendFailure
  ImportJustificationLimits* = object ## Local policies bound sibling count, retained variable payload and exact hash preimages.
    siblings*: ElementLimit
    payloadBytes*, hashBytes*: ByteLimit
  VerifiedImportInfo* = object ## Fixed copied facts bind the leaf ordinal to its explicitly supplied root.
    root*: SegmentRoot
    index*: ImportIndex
    siblings*: int
    payloadBytes*, hashBytes*: uint64
  ImportData = ref object ## Acyclic immutable ownership retains complete copied proof/leaf bytes after caller inputs retire.
    info: VerifiedImportInfo
    segment: FetchSegment
    path: seq[SegmentRoot]
  VerifiedImport* = object ## Default has no verified leaf; zero data requires an actual successful proof.
    data: nil ImportData
  ImportJustificationResult*[T] = object ## Private alternatives enforce checked success selection in optimized builds.
    case status: ImportJustificationError
    of None:
      completed: T
    else:
      discard # Failure cannot expose a prefix, an invented root or an unverified payload.

func error*[T](outcome: ImportJustificationResult[T]): ImportJustificationError =
  ## Inspect the reason without a writable discriminator.
  outcome.status
func value*[T](outcome: ImportJustificationResult[T]): T
    {.requires: outcome.status == ImportJustificationError.None.} =
  ## Extract only a completely selected successful value.
  outcome.completed
proc verifiedImportInfo*(verified: VerifiedImport): ImportJustificationResult[VerifiedImportInfo] =
  ## Copy nominal identity/geometry facts without exposing proof authority for rebinding.
  let data = verified.data
  if data == nil: return ImportJustificationResult[VerifiedImportInfo](
      status: ImportJustificationError.Uninitialized)
  ImportJustificationResult[VerifiedImportInfo](status: ImportJustificationError.None,
      completed: data.info)
proc verifiedImportSegment*(verified: VerifiedImport): ImportJustificationResult[FetchSegment] =
  ## Return a fixed value copy; caller mutation cannot modify the verified leaf.
  let data = verified.data
  if data == nil: return ImportJustificationResult[FetchSegment](
      status: ImportJustificationError.Uninitialized)
  ImportJustificationResult[FetchSegment](status: ImportJustificationError.None,
      completed: data.segment)
proc verifiedImportPath*(verified: VerifiedImport): ImportJustificationResult[seq[SegmentRoot]] =
  ## Return independent root-to-leaf siblings, retaining no borrowed sequence descriptor.
  let data = verified.data
  if data == nil: return ImportJustificationResult[seq[SegmentRoot]](
      status: ImportJustificationError.Uninitialized)
  var path = newSeq[SegmentRoot](data.path.len)
  for index in 0..<path.len: path[index] = data.path[
      index] # Fixed hashes copy by value without writable aliasing.
  ImportJustificationResult[seq[SegmentRoot]](status: ImportJustificationError.None,
      completed: path)
proc verifiedImportProof*(verified: VerifiedImport): ImportJustificationResult[seq[byte]] =
  ## Encode the complete canonical length-prefixed path used in an auditable bundle, without extra segment framing.
  let data = verified.data
  if data == nil: return ImportJustificationResult[seq[byte]](
      status: ImportJustificationError.Uninitialized)
  let prefix = encode(JamNatural(uint64(data.path.len)))
  var wire = newSeq[byte](prefix.len+data.path.len*32) # At most 385 bytes after the constructor's twelve-sibling proof.
  for index in 0..<prefix.len: wire[index] = prefix.bytes[index]
  for index in 0..<data.path.len:
    for octet in 0..<32: wire[prefix.len+index*32+octet] = data.path[index].bytes[octet]
  ImportJustificationResult[seq[byte]](status: ImportJustificationError.None, completed: wire)
proc verifyImportSegment*(root: SegmentRoot, index: ImportIndex, segment: FetchSegment,
    path: openArray[SegmentRoot], limits: ImportJustificationLimits): ImportJustificationResult[
        VerifiedImport] =
  ## Borrow stable siblings synchronously; validate geometry and local work before allocation or hashing.
  template fail(reason: ImportJustificationError) =
    return ImportJustificationResult[VerifiedImport](status: reason)
  if path.len > 12: fail(ImportJustificationError.InvalidProof) # No valid 3072-export package has a deeper constant-depth tree.
  let ordinal = uint64(uint16(index))
  if ordinal >= 3072 or ordinal >= (1'u64 shl path.len):
    fail(ImportJustificationError.InvalidIndex) # Prove the full ordinal without masking the import selector bit or narrowing.
  let payloadBytes = 4104'u64+uint64(path.len)*32
  let hashBytes = 4108'u64+uint64(path.len)*68
  if uint64(path.len) > uint64(limits.siblings) or payloadBytes > uint64(limits.payloadBytes) or
      hashBytes > uint64(limits.hashBytes):
    fail(ImportJustificationError.LimitExceeded) # Fixed metadata is separate; these caps cover retained leaf/path payload and hash work.
  var leafBytes = default(array[4108, byte])
  leafBytes[0] = byte('l')
  leafBytes[1] = byte('e')
  leafBytes[2] = byte('a')
  leafBytes[3] = byte('f')
  let bytes = array[4104, byte](segment)
  for octet in 0..<4104: leafBytes[4+octet] = bytes[octet]
  let leaf = blake2b256(leafBytes)
  if leaf.error != CryptoError.None: fail(ImportJustificationError.BackendFailure)
  var current = array[32, byte](leaf.value)
  var nodeBytes = default(array[68, byte])
  nodeBytes[0] = byte('n')
  nodeBytes[1] = byte('o')
  nodeBytes[2] = byte('d')
  nodeBytes[3] = byte('e')
  var position = path.len
  # T stores siblings root-first; reconstruction starts with the final sibling and the least significant index bit.
  while position > 0:
    dec position
    let right = ((ordinal shr (path.len-position-1)) and 1) == 1
    for octet in 0..<32:
      nodeBytes[4+octet] = if right: path[position].bytes[octet] else: current[octet]
      nodeBytes[36+octet] = if right: current[octet] else: path[position].bytes[octet]
    let hashed = blake2b256(nodeBytes)
    if hashed.error != CryptoError.None: fail(ImportJustificationError.BackendFailure)
    current = array[32, byte](hashed.value)
  if current != root.bytes: fail(ImportJustificationError.RootMismatch) # No caller-owned bytes are retained on cryptographic failure.
  var copied = newSeq[SegmentRoot](path.len)
  for offset in 0..<path.len: copied[offset] = path[
      offset] # Capture only the complete verified witness, never its borrowed descriptor.
  ImportJustificationResult[VerifiedImport](status: ImportJustificationError.None,
    completed: VerifiedImport(data: ImportData(segment: segment, path: copied,
      info: VerifiedImportInfo(root: root, index: index, siblings: path.len,
        payloadBytes: payloadBytes, hashBytes: hashBytes))))
