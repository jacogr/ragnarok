# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Admit included computed reports through the maintained state checks under their original semantic policies.

import ../chain/parameters
import ../codec/[header, state_safrole]
import ./[computed_inclusion, computed_batch, computed_envelope, computed_credentials,
  computed_guarantors, computed_roster, computed_transition, computed_profile, computed_lookup,
  report_admission, guarantee_credentials]

type
  ComputedAdmissionError* {.pure.} = enum ## Only the selected child failure carries its original precise refusal.
    Uninitialized, None, InvalidSource, ProfileMismatch, LimitExceeded, AdmissionFailure, EvidenceMismatch
  ComputedAdmissionData = ref object ## Immutable acyclic provenance retains exact inclusion and complete implemented admission.
    source: IncludedComputedGuarantees
    admitted: AdmittedReports
  AdmittedComputedReports* = object ## This is implemented report admission, not a published successor or full STF certificate.
    data: nil ComputedAdmissionData
  ComputedAdmissionResult*[T] = object ## Failed/default alternatives carry no partially admitted report prefix.
    case status: ComputedAdmissionError
    of None:
      completed: T
    of AdmissionFailure:
      admissionReason: ReportAdmissionResult[AdmittedReports]
    else:
      discard # Ordinary refusals carry reasons alone.

func error*[T](outcome: ComputedAdmissionResult[T]): ComputedAdmissionError =
  ## Observe selection without writable discriminator access.
  outcome.status
func value*[T](outcome: ComputedAdmissionResult[T]): T
    {.requires: outcome.status == ComputedAdmissionError.None.} =
  ## Guard complete successful extraction in optimized builds.
  outcome.completed
func admissionError*[T](outcome: ComputedAdmissionResult[T]): ReportAdmissionResult[AdmittedReports]
    {.requires: outcome.status == ComputedAdmissionError.AdmissionFailure.} =
  ## Preserve the original selected report-stage refusal and its nested diagnostics.
  outcome.admissionReason
proc computedAdmissionSource*(admitted: AdmittedComputedReports): ComputedAdmissionResult[
    IncludedComputedGuarantees] =
  ## Share the original included computations and exact authenticated candidate.
  let data = admitted.data
  if data == nil: return ComputedAdmissionResult[IncludedComputedGuarantees](
      status: ComputedAdmissionError.Uninitialized)
  ComputedAdmissionResult[IncludedComputedGuarantees](status: ComputedAdmissionError.None,
      completed: data.source)
proc computedAdmissionReports*(admitted: AdmittedComputedReports): ComputedAdmissionResult[
    AdmittedReports] =
  ## Share only a completed maintained report-admission certificate, never caller-supplied observation tuples.
  let data = admitted.data
  if data == nil: return ComputedAdmissionResult[AdmittedReports](
      status: ComputedAdmissionError.Uninitialized)
  ComputedAdmissionResult[AdmittedReports](status: ComputedAdmissionError.None,
      completed: data.admitted)
proc admitComputedReports*(source: IncludedComputedGuarantees,
    config: ReportAdmissionConfig): ComputedAdmissionResult[AdmittedComputedReports] =
  ## Bind semantic knobs and retained ancestry before running the existing full implemented report plan.
  template fail(reason: ComputedAdmissionError) =
    return ComputedAdmissionResult[AdmittedComputedReports](status: reason)
  let selected = source.computedInclusionSource
  if selected.error != ComputedInclusionError.None: fail(ComputedAdmissionError.InvalidSource)
  let batch = selected.value
  let first = batch.computedBatchSourceAt(ComputedBatchIndex(0)).value
  let configured = first.computedEnvelopeSource.value.computedCredentialSource.value.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value
  let parameters = configured.computedProfileContext.value.parameters
  let sameGas = uint64(config.policy.reportGas) == parameters.get(maxAccumulateGas)
  let sameRotation = uint64(config.credentials.assignments.rotationSlots) == parameters.get(rotationPeriod)
  let sameLookup = uint64(config.anchors.lookupAge) == parameters.get(maxLookupAnchorAge)
  if not sameGas or not sameRotation or not sameLookup: fail(ComputedAdmissionError.ProfileMismatch)
  let lookup = configured.computedProfileSource.value
  let count = lookup.computedLookupInfo.value.headers # Successful source includes parent and a matched older anchor.
  if uint64(count) > uint64(config.ancestors.headers): fail(ComputedAdmissionError.LimitExceeded)
  var older = newSeq[OwnedHeader](count-1)
  for i in 1..<count:
    older[i-1] = lookup.computedLookupHeader(ComputedAncestorIndex(uint64(
        i))).value # Parent is already retained by the candidate admission.
  let outcome = planBlockReports(source.computedInclusionStage.value, older, config)
  if outcome.error != ReportAdmissionError.None:
    return ComputedAdmissionResult[AdmittedComputedReports](
      status: ComputedAdmissionError.AdmissionFailure,
      admissionReason: outcome) # Preserve all exact nested policy, package and credential causes.
  let verified = outcome.value.reportCredentials.value
  let facts = batch.computedBatchInfo.value
  if verified.verifiedGuaranteeCount.value != facts.guarantees or
      verified.verifiedReporterCount.value != facts.reporters: fail(
          ComputedAdmissionError.EvidenceMismatch)
  for i in 0..<facts.reporters:
    let actual = array[32, byte](verified.verifiedReporterAt(i).value)
    let expected = array[32, byte](batch.computedBatchReporterAt(ComputedBatchReporterIndex(uint64(i))).value)
    if actual != expected: fail(ComputedAdmissionError.EvidenceMismatch) # Full actual identities must agree, not merely cardinalities.
  ComputedAdmissionResult[AdmittedComputedReports](status: ComputedAdmissionError.None,
    completed: AdmittedComputedReports(data: ComputedAdmissionData(source: source,
        admitted: outcome.value)))
