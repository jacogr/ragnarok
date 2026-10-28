# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Assemble GP makebundle only from the exact verified inputs retained by completed execution.
## This immutable wire owner certifies neither root/state freshness nor erasure-coded availability.

import ../codec/bounded as codec_bounded
import ../codec/work_package as codec_work_package
import ../codec/work_report as codec_work_report
import ../pvm/host_fetch as pvm_host_fetch
import ./input_refinement as state_input_refinement
import ./import_inputs as state_import_inputs
import ./extrinsic_inputs as state_extrinsic_inputs
import ./import_justification as state_import_justification
import ./report_identity as state_report_identity

type
  AuditableBundleError* {.pure.} = enum ## Refusals contain only reasons, never a serialized successful prefix.
    Uninitialized, None, InvalidSource, LimitExceeded, LengthOverflow, EncodingFailure
  AuditableBundleInfo* = object ## Fixed copied section lengths describe the exact retained wire and original package identity.
    length*: BundleLength
    packageHash*: PackageHash
    packageBytes*, extrinsicBytes*, segmentBytes*, proofBytes*: uint64
  BundleData = ref object ## Acyclic immutable storage retains the exact original executed input provenance beside its bytes.
    source: InputRefinement
    info: AuditableBundleInfo
    wire: seq[byte]
  AuditableBundle* = object ## Defaults have no bundle, including no successful empty-byte certificate.
    data: nil BundleData
  AuditableBundleResult*[T] = object ## Private alternatives enforce successful selection in checked optimized builds.
    case status: AuditableBundleError
    of None:
      completed: T
    else:
      discard # No partially assembled bytes or detached identity escape on refusal.

func error*[T](outcome: AuditableBundleResult[T]): AuditableBundleError =
  ## Inspect only the selected reason, with no writable discriminator.
  outcome.status
func value*[T](outcome: AuditableBundleResult[T]): T
    {.requires: outcome.status == AuditableBundleError.None.} =
  ## Extract only a fully completed successful value.
  outcome.completed
proc bundleInfo*(bundle: AuditableBundle): AuditableBundleResult[AuditableBundleInfo] =
  ## Copy nominal identity and section extents without exposing retained byte storage.
  let data = bundle.data
  if data == nil: return AuditableBundleResult[AuditableBundleInfo](
      status: AuditableBundleError.Uninitialized)
  AuditableBundleResult[AuditableBundleInfo](status: AuditableBundleError.None,
      completed: data.info)
proc bundleSource*(bundle: AuditableBundle): AuditableBundleResult[InputRefinement] =
  ## Retain the original completed execution; callers cannot substitute later inputs or report identity.
  let data = bundle.data
  if data == nil: return AuditableBundleResult[InputRefinement](
      status: AuditableBundleError.Uninitialized)
  AuditableBundleResult[InputRefinement](status: AuditableBundleError.None, completed: data.source)
proc bundleBytes*(bundle: AuditableBundle): AuditableBundleResult[seq[byte]] =
  ## Return an independent complete wire copy; no writable descriptor aliases private bytes.
  let data = bundle.data
  if data == nil: return AuditableBundleResult[seq[byte]](
      status: AuditableBundleError.Uninitialized)
  var copied = newSeq[byte](data.wire.len)
  for index in 0..<copied.len: copied[index] = data.wire[index] # Scalar bytes copy by value.
  AuditableBundleResult[seq[byte]](status: AuditableBundleError.None, completed: copied)
proc charge(total: var uint64, amount: uint64, limit: ByteLimit): AuditableBundleError =
  ## Preserve a bounded total on refusal; prove E4/native and local representability before adding.
  let ceiling = min(uint64(high(uint32)), uint64(high(int)))
  if amount > ceiling-total: return AuditableBundleError.LengthOverflow
  if amount > uint64(limit)-total: return AuditableBundleError.LimitExceeded
  total += amount # Every earlier successful charge proves total lies within both ceilings.
  AuditableBundleError.None
proc prepareAuditableBundle*(source: InputRefinement, limit: ByteLimit): AuditableBundleResult[
    AuditableBundle] =
  ## Derive all bytes from original executed sources; preflight complete wire extents before copying any payload.
  template fail(reason: AuditableBundleError) =
    return AuditableBundleResult[AuditableBundle](status: reason)
  let captured = source.inputRefinementSource
  if captured.error != InputRefinementError.None: fail(AuditableBundleError.InvalidSource)
  let inputs = captured.value
  let described = inputs.importInputsInfo.value
  let extrinsics = inputs.importInputsExtrinsics.value
  let package = extrinsics.extrinsicInputsPackage.value
  let packageInfo = package.workPackageInfo.value
  let segmentBytes = uint64(described.entries)*4104 # Private original manifest bounds entries to 3072 before multiplication.
  let proofBytes = described.witnessBytes-segmentBytes+uint64(
      described.entries) # Verified sibling counts 0..12 have one-byte natural prefixes.
  let info = AuditableBundleInfo(packageHash: source.inputRefinementIdentity.value.identityInfo.value.packageHash,
    packageBytes: uint64(packageInfo.consumed), extrinsicBytes: extrinsics.extrinsicInputsInfo.value.payloadBytes,
    segmentBytes: segmentBytes, proofBytes: proofBytes)
  var total = 0'u64
  # All four sections must fit before any payload extraction; fixed metadata contains no variable allocations.
  for amount in [info.packageBytes, info.extrinsicBytes, info.segmentBytes, info.proofBytes]:
    let reason = charge(total, amount, limit)
    if reason != AuditableBundleError.None: fail(reason)
  var wire = newSeq[byte](int(total))
  let encoded = package.encodeOwnedWorkPackage(wire.toOpenArray(0, packageInfo.consumed-1))
  if encoded.error != PackageError.None: fail(AuditableBundleError.EncodingFailure)
  if encoded.value != packageInfo.consumed: fail(AuditableBundleError.EncodingFailure)
  var cursor = packageInfo.consumed
  # GP serializes all extrinsics before any imported segment, without row/count/length prefixes.
  for item in 0..<described.items:
    let selected = package.workItemAt(item).value.workItemInfo.value
    for index in 0..<selected.extrinsics:
      let bytes = extrinsics.extrinsicInput(FetchItemIndex(uint64(item)), ExtrinsicInputIndex(
          uint64(index))).value
      for octet in bytes:
        wire[cursor] = octet # Full section preflight proves each increment remains within the destination.
        inc cursor
  # Imported leaves are fixed-width raw bytes; copies retain their original manifest order and duplicates.
  for item in 0..<described.items:
    let selected = package.workItemAt(item).value.workItemInfo.value
    for index in 0..<selected.imports:
      let segment = inputs.importInput(FetchItemIndex(uint64(item)), ImportInputIndex(uint64(index))).value
      for octet in array[4104, byte](segment.verifiedImportSegment.value):
        wire[cursor] = octet
        inc cursor
  # Only paths carry a discriminator; all root-to-leaf paths follow the entire segment section.
  for item in 0..<described.items:
    let selected = package.workItemAt(item).value.workItemInfo.value
    for index in 0..<selected.imports:
      let segment = inputs.importInput(FetchItemIndex(uint64(item)), ImportInputIndex(uint64(index))).value
      for octet in segment.verifiedImportProof.value:
        wire[cursor] = octet
        inc cursor
  if cursor != wire.len: fail(AuditableBundleError.EncodingFailure) # Never publish an incomplete private buffer.
  var completedInfo = info
  completedInfo.length = BundleLength(uint32(total)) # The preflight proves both E4 narrowing and native allocation width.
  AuditableBundleResult[AuditableBundle](status: AuditableBundleError.None,
    completed: AuditableBundle(data: BundleData(source: source, info: completedInfo, wire: wire)))
