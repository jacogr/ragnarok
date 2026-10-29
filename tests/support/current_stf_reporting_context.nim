# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared reporting corpus resource policy and exact nested failure projection; no executable entry point.
import std/assertions
import ./current_consecutive_context
import ../../src/app/[chain, candidate]
import ../../src/codec/bounded
import ../../src/state/report/admission as report_admission
import ../../src/state/guarantee_credentials
import "../../src/state/block/transition" as block_transition
import ../../src/state/availability

proc reportingLimits*(): CurrentCandidateLimits =
  ## Six distinct reporters/assurers and two available reports have explicit resource ceilings.
  result = currentConsecutiveLimits()
  result.completion.composition.validators.projection.assurances = ElementLimit(6)
  result.completion.composition.validators.projection.reporters = ElementLimit(6)
  result.completion.composition.validators.projection.comparisons = ElementLimit(36)
  result.completion.composition.activity.available = ElementLimit(2)
  result.completion.composition.activity.assurances = ElementLimit(6)

proc reportingReason*(outcome: CurrentCandidateResult): string =
  ## Only selected typed failures grant their exact report or availability reason.
  var failure = default(ReportAdmissionResult[AdmittedReports])
  if outcome.error == CurrentCandidateError.PrefixFailure:
    let prefix = outcome.prefixFailure
    if prefix.error == ApplicationCandidateError.BlockFailure:
      let blockFailure = prefix.blockFailure
      if blockFailure.error == BlockTransitionError.AvailabilityFailure:
        let availability = blockFailure.availabilityError
        if availability.error == AvailabilityTransitionError.ContextFailure:
          return "assurance/" & $availability.contextError
        return "availability/" & $availability.error
      return "block/" & $blockFailure.error
    assert prefix.error == ApplicationCandidateError.ReportFailure
    failure = prefix.reportFailure
  elif outcome.error == CurrentCandidateError.ReportFailure:
    failure = outcome.reportFailure
  else:
    return $outcome.error # Unexpected completion/preparation failures must not match a protocol refusal.
  case failure.error
  of ReportAdmissionError.CredentialFailure:
    if failure.credentialError.error == GuaranteeCredentialError.AssignmentFailure:
      "credential/" & $failure.credentialError.assignmentError
    else:
      "credential/" & $failure.credentialError.error # Exact nested slot failure remains distinguishable from signature/assignment mismatch.
  of ReportAdmissionError.PolicyFailure: "policy/" & $failure.policyError
  of ReportAdmissionError.AnchorFailure: "anchor/" & $failure.anchorError
  of ReportAdmissionError.PackageFailure: "package/" & $failure.packageError
  of ReportAdmissionError.AssignmentFailure: "assignment/" & $failure.assignmentError
  else: "report/" & $failure.error # No unclassified failure masquerades as a successful empty batch.

