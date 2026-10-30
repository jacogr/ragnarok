# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authenticate complete ordered extrinsic tables against their original owned package manifest.
## Immutable package-bound bytes certify commitments, not availability, state freshness or execution.

import ../codec/bounded
import ../codec/work/package as work_package
import ../crypto/primitives
import ../pvm/host/fetch as host_fetch

type
  ExtrinsicInputsError* {.pure.} = enum ## Refusals retain no partially authenticated table.
    Uninitialized, None, InvalidPackage, InvalidShape, LengthMismatch, HashMismatch,
    LimitExceeded, BackendFailure, InvalidIndex
  ExtrinsicInputIndex* = distinct uint64 ## Ordinal within one item is distinct from the work-item ordinal.
  ExtrinsicInputsLimits* = object ## Independent local caps cover every occurrence, including repeated and empty inputs.
    entries*: ElementLimit
    payloadBytes*, hashBytes*: ByteLimit
  ExtrinsicInputsInfo* = object ## Copied accounting facts grant no authority to substitute a package or input table.
    items*, entries*: int
    payloadBytes*, hashBytes*: uint64
  ExtrinsicData = ref object ## Acyclic immutable storage owns deep copies and the exact original package.
    package: OwnedWorkPackage
    info: ExtrinsicInputsInfo
    rows: seq[seq[seq[byte]]]
  VerifiedExtrinsics* = object ## Defaults have no authenticated inputs, including no empty-table certificate.
    data: nil ExtrinsicData
  ExtrinsicInputsResult*[T] = object ## Private alternatives guard successful extraction in optimized builds.
    case status: ExtrinsicInputsError
    of None:
      completed: T
    else:
      discard # A refused candidate cannot expose a verified prefix.

func error*[T](outcome: ExtrinsicInputsResult[T]): ExtrinsicInputsError =
  ## Inspect the reason without a writable tag.
  outcome.status

func value*[T](outcome: ExtrinsicInputsResult[T]): T
    {.requires: outcome.status == ExtrinsicInputsError.None.} =
  ## Extract only a complete successful alternative.
  outcome.completed

proc extrinsicInputsInfo*(verified: VerifiedExtrinsics): ExtrinsicInputsResult[
    ExtrinsicInputsInfo] =
  ## Copy fixed geometry and accounting without exposing retained mutable storage.
  let data = verified.data
  if data == nil: return ExtrinsicInputsResult[ExtrinsicInputsInfo](
      status: ExtrinsicInputsError.Uninitialized)
  ExtrinsicInputsResult[ExtrinsicInputsInfo](status: ExtrinsicInputsError.None,
      completed: data.info)

proc extrinsicInputsPackage*(verified: VerifiedExtrinsics): ExtrinsicInputsResult[
    OwnedWorkPackage] =
  ## Retain the original manifest; a later consumer must derive its package from this owner.
  let data = verified.data
  if data == nil: return ExtrinsicInputsResult[OwnedWorkPackage](
      status: ExtrinsicInputsError.Uninitialized)
  ExtrinsicInputsResult[OwnedWorkPackage](status: ExtrinsicInputsError.None,
      completed: data.package)

proc extrinsicInput*(verified: VerifiedExtrinsics, item: FetchItemIndex,
    index: ExtrinsicInputIndex): ExtrinsicInputsResult[seq[byte]] =
  ## Check full-width ordinals before narrowing, then return an independent byte copy.
  let data = verified.data
  if data == nil: return ExtrinsicInputsResult[seq[byte]](
      status: ExtrinsicInputsError.Uninitialized)
  if uint64(item) >= uint64(data.rows.len):
    return ExtrinsicInputsResult[seq[byte]](status: ExtrinsicInputsError.InvalidIndex)
  if uint64(index) >= uint64(data.rows[int(uint64(item))].len):
    return ExtrinsicInputsResult[seq[byte]](status: ExtrinsicInputsError.InvalidIndex)
  let source = data.rows[int(uint64(item))][int(uint64(index))]
  var copied = newSeq[byte](source.len)
  for offset in 0..<source.len: copied[offset] = source[offset] # No borrowed descriptor escapes.
  ExtrinsicInputsResult[seq[byte]](status: ExtrinsicInputsError.None, completed: copied)

proc verifyExtrinsicInputs*(package: OwnedWorkPackage, rows: openArray[seq[seq[byte]]],
    limits: ExtrinsicInputsLimits): ExtrinsicInputsResult[VerifiedExtrinsics] =
  ## Borrow stable tables synchronously; preflight all geometry and budgets before hashing or copying.
  template fail(reason: ExtrinsicInputsError) =
    return ExtrinsicInputsResult[VerifiedExtrinsics](status: reason)
  let described = package.workPackageInfo
  if described.error != PackageError.None: fail(ExtrinsicInputsError.InvalidPackage)
  if rows.len != described.value.items: fail(ExtrinsicInputsError.InvalidShape)
  var info = ExtrinsicInputsInfo(items: rows.len)
  # Owned manifests bound the complete package to sixteen items, 128 extrinsics and the bundle byte ceiling.
  for item in 0..<rows.len:
    let selected = package.workItemAt(item).value
    if rows[item].len != selected.workItemInfo.value.extrinsics:
      fail(ExtrinsicInputsError.InvalidShape) # Preserve empty rows, order and duplicate occurrences.
    for index in 0..<rows[item].len:
      let expected = selected.extrinsicAt(index).value
      if uint64(rows[item][index].len) != uint64(expected.length):
        fail(ExtrinsicInputsError.LengthMismatch) # Equality to bounded manifest sizes proves accumulation cannot wrap.
      inc info.entries
      info.payloadBytes += uint64(rows[item][index].len)
  info.hashBytes = info.payloadBytes # Raw bytes only; no domain, length prefix or terminator is hashed.
  if uint64(info.entries) > uint64(limits.entries):
    fail(ExtrinsicInputsError.LimitExceeded) # Empty inputs still cost one hash invocation per occurrence.
  if info.payloadBytes > uint64(limits.payloadBytes):
    fail(ExtrinsicInputsError.LimitExceeded) # Copying policy is independent of hashing policy.
  if info.hashBytes > uint64(limits.hashBytes):
    fail(ExtrinsicInputsError.LimitExceeded) # Check before the first cryptographic call.
  # Authenticate the entire table before allocating retained rows; any backend or equality failure drops all authority.
  for item in 0..<rows.len:
    let selected = package.workItemAt(item).value
    for index in 0..<rows[item].len:
      let hashed = blake2b256(rows[item][index])
      if hashed.error != CryptoError.None: fail(ExtrinsicInputsError.BackendFailure)
      if array[32, byte](hashed.value) != array[32, byte](selected.extrinsicAt(index).value.hash):
        fail(ExtrinsicInputsError.HashMismatch)
  var copied = newSeq[seq[seq[byte]]](rows.len)
  # Deep-copy each level only after every commitment has passed; caller tables must remain stable during this call.
  for item in 0..<rows.len:
    copied[item] = newSeq[seq[byte]](rows[item].len)
    for index in 0..<rows[item].len:
      copied[item][index] = newSeq[byte](rows[item][index].len)
      for offset in 0..<rows[item][index].len: copied[item][index][offset] = rows[item][index][offset]
  ExtrinsicInputsResult[VerifiedExtrinsics](status: ExtrinsicInputsError.None,
    completed: VerifiedExtrinsics(data: ExtrinsicData(package: package, info: info, rows: copied)))
