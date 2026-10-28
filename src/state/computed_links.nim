# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Check original lookup pairs against complete computed exporter reports without detached root authority.

import ../codec/bounded as codec_bounded
import ./computed_guarantee as state_computed_guarantee
import ./computed_report as state_computed_report
import ./availability_specifier as state_availability_specifier
import ./export_erasure as state_export_erasure
import ./bundle_erasure as state_bundle_erasure
import ./erasure_layout as state_erasure_layout
import ./auditable_bundle as state_auditable_bundle
import ./input_refinement as state_input_refinement
import ./report_identity as state_report_identity

type
  ComputedLinksError* {.pure.} = enum ## Refusals contain no accepted prefix or partially linked owner.
    Uninitialized, None, InvalidSource, InvalidShape, LimitExceeded, InvalidWitness,
    PackageMismatch, RootMismatch, InvalidIndex
  ComputedLinksData = ref object ## Immutable acyclic sharing retains the exact source transcript and each matching exporter.
    source: ComputedGuaranteeTranscript
    witnesses: array[8, ComputedWorkReport]
    count: int
  ComputedReportLinks* = object ## Completed computational correspondence is distinct from state trust or signing eligibility.
    data: nil ComputedLinksData
  ComputedLinksResult*[T] = object ## The private successful alternative alone carries extractable application data.
    case status: ComputedLinksError
    of None:
      completed: T
    else:
      discard # Default/refused alternatives retain their reason alone.

func error*[T](outcome: ComputedLinksResult[T]): ComputedLinksError =
  ## Inspect a reason without writable discriminator access.
  outcome.status
func value*[T](outcome: ComputedLinksResult[T]): T
    {.requires: outcome.status == ComputedLinksError.None.} =
  ## Preserve success selection under optimized runtime contracts.
  outcome.completed
proc computedLinkCount*(links: ComputedReportLinks): ComputedLinksResult[int] =
  ## Count completed witnesses without treating a default owner as an accepted empty relation.
  let data = links.data
  if data == nil: return ComputedLinksResult[int](status: ComputedLinksError.Uninitialized)
  ComputedLinksResult[int](status: ComputedLinksError.None, completed: data.count)
proc computedLinkSource*(links: ComputedReportLinks): ComputedLinksResult[
    ComputedGuaranteeTranscript] =
  ## Retain the original exact transcript, never a later replacement report or message.
  let data = links.data
  if data == nil: return ComputedLinksResult[ComputedGuaranteeTranscript](
      status: ComputedLinksError.Uninitialized)
  ComputedLinksResult[ComputedGuaranteeTranscript](status: ComputedLinksError.None,
      completed: data.source)
proc computedLinkWitness*(links: ComputedReportLinks,
    index: ReportLookupIndex): ComputedLinksResult[ComputedWorkReport] =
  ## Extract the immutable exporter at the source's nominal canonical lookup ordinal.
  let data = links.data
  if data == nil: return ComputedLinksResult[ComputedWorkReport](
      status: ComputedLinksError.Uninitialized)
  if uint64(index) >= uint64(data.count):
    return ComputedLinksResult[ComputedWorkReport](
        status: ComputedLinksError.InvalidIndex) # Check before narrowing.
  ComputedLinksResult[ComputedWorkReport](status: ComputedLinksError.None,
      completed: data.witnesses[int(uint64(index))])
proc prepareComputedLinks*(source: ComputedGuaranteeTranscript,
    witnesses: openArray[ComputedWorkReport], limit: ElementLimit): ComputedLinksResult[
        ComputedReportLinks] =
  ## Borrow stable handles synchronously; validate the entire relation before retaining any candidate owner.
  template fail(reason: ComputedLinksError) =
    return ComputedLinksResult[ComputedReportLinks](status: reason)
  let selected = source.computedGuaranteeReport
  if selected.error != ComputedGuaranteeError.None: fail(ComputedLinksError.InvalidSource)
  let report = selected.value
  let count = report.computedReportInfo.value.lookupCount
  if witnesses.len != count: fail(ComputedLinksError.InvalidShape) # Exact original key coverage, no unused witness.
  if uint64(count) > uint64(limit): fail(ComputedLinksError.LimitExceeded) # Before inspecting or retaining witnesses.
  let identity = report.computedReportSource.value.availabilitySource.value.exportErasureSource.value.bundleErasureSource.value.layoutSource.value.bundleSource.value.inputRefinementIdentity.value
  # The original computed report proves count in 0..8 and strictly ordered unique lookup keys.
  for ordinal in 0..<count:
    let pair = identity.identityLookupAt(ReportLookupIndex(uint64(ordinal))).value
    let witness = witnesses[ordinal].computedReportInfo
    if witness.error != ComputedReportError.None: fail(ComputedLinksError.InvalidWitness)
    if witness.value.header.packageHash.bytes != pair.packageHash.bytes:
      fail(ComputedLinksError.PackageMismatch) # Correct roots under unrelated packages cannot satisfy correspondence.
    if witness.value.header.segmentRoot.bytes != pair.segmentRoot.bytes:
      fail(ComputedLinksError.RootMismatch) # Key presence alone cannot certify the associated export root.
  var retained = default(array[8, ComputedWorkReport])
  for ordinal in 0..<count: retained[ordinal] = witnesses[ordinal] # Copy handles only after complete validation.
  ComputedLinksResult[ComputedReportLinks](status: ComputedLinksError.None,
    completed: ComputedReportLinks(data: ComputedLinksData(source: source, witnesses: retained,
        count: count)))
