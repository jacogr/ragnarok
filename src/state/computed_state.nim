# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind original computed-report execution to the exact complete map retained by block commitments.

import ./[computed_links, computed_guarantee, computed_report, block_admission, store,
  availability_specifier, export_erasure, bundle_erasure, erasure_layout, auditable_bundle,
  input_refinement, report_identity, authorized_refinement, authorization_invocation]

type
  ComputedStateError* {.pure.} = enum ## Refusals contain no partially bound report or substitute state.
    Uninitialized, None, InvalidSource, InvalidAdmission, StateMismatch
  ComputedStateData = ref object ## Immutable acyclic sharing retains exact original computation and admitted parent-state provenance.
    source: ComputedReportLinks
    admission: BoundBlock
  StateBoundComputedReport* = object ## Complete-map identity binding alone does not certify anchor ancestry or signing eligibility.
    data: nil ComputedStateData
  ComputedStateResult*[T] = object ## Only private selected success contains extractable application data.
    case status: ComputedStateError
    of None:
      completed: T
    else:
      discard # Default/refused alternatives expose their reason alone.

func error*[T](outcome: ComputedStateResult[T]): ComputedStateError =
  ## Inspect the selected reason without writable discriminator access.
  outcome.status
func value*[T](outcome: ComputedStateResult[T]): T
    {.requires: outcome.status == ComputedStateError.None.} =
  ## Optimized contracts preserve success selection on every payload path.
  outcome.completed
proc computedStateSource*(bound: StateBoundComputedReport): ComputedStateResult[
    ComputedReportLinks] =
  ## Retain the exact original transcript and computational lookup witnesses.
  let data = bound.data
  if data == nil: return ComputedStateResult[ComputedReportLinks](
      status: ComputedStateError.Uninitialized)
  ComputedStateResult[ComputedReportLinks](status: ComputedStateError.None, completed: data.source)
proc computedStateAdmission*(bound: StateBoundComputedReport): ComputedStateResult[BoundBlock] =
  ## Retain the completed block commitment binding without accepting later header replacements.
  let data = bound.data
  if data == nil: return ComputedStateResult[BoundBlock](status: ComputedStateError.Uninitialized)
  ComputedStateResult[BoundBlock](status: ComputedStateError.None, completed: data.admission)
proc computedStateSnapshot*(bound: StateBoundComputedReport): ComputedStateResult[
    StateStoreSnapshot] =
  ## Share the exact original execution version, already proven identical to the admitted parent-state owner.
  let data = bound.data
  if data == nil: return ComputedStateResult[StateStoreSnapshot](
      status: ComputedStateError.Uninitialized)
  ComputedStateResult[StateStoreSnapshot](status: ComputedStateError.None,
      completed: data.admission.admittedState)
proc bindComputedState*(source: ComputedReportLinks,
    admission: BlockAdmissionResult): ComputedStateResult[StateBoundComputedReport] =
  ## Require completed provenance on both sides and exact snapshot identity before retaining any candidate owner.
  if source.computedLinkCount.error != ComputedLinksError.None:
    return ComputedStateResult[StateBoundComputedReport](
        status: ComputedStateError.InvalidSource) # Defaults cannot stand for empty validated lookups.
  if admission.error != BlockAdmissionError.None:
    return ComputedStateResult[StateBoundComputedReport](
        status: ComputedStateError.InvalidAdmission) # No failed/unbound block can certify a map.
  let report = source.computedLinkSource.value.computedGuaranteeReport.value
  let identity = report.computedReportSource.value.availabilitySource.value.exportErasureSource.value.bundleErasureSource.value.layoutSource.value.bundleSource.value.inputRefinementIdentity.value
  let execution = identity.identitySource.value.authorizedSource.value.authorizationState.value
  let binding = admission.value
  if not sameStateSnapshot(execution, binding.admittedState):
    return ComputedStateResult[StateBoundComputedReport](
        status: ComputedStateError.StateMismatch) # Equal roots in separately constructed owners cannot replace original provenance.
  ComputedStateResult[StateBoundComputedReport](status: ComputedStateError.None,
    completed: StateBoundComputedReport(data: ComputedStateData(source: source,
        admission: binding)))
