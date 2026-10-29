# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Translate only explicitly recognized consensus import refusals; unknown/resource/context failures close locally.
import ../candidate
import "../../state/block/transition" as block_transition
import "../../state/block/admission" as block_admission
import ../../state/disputes
import ../../state/safrole/transition as safrole_transition
import ../../state/ticket/admission as ticket_admission
import ../../state/safrole/[authentication as safrole_authentication, markers as safrole_markers]
import ../../state/availability
import ../../state/report/[admission as report_admission, policy as report_policy,
    packages as report_packages, assignments as report_assignments, anchors as report_anchors]
import ../../state/guarantee_credentials
import ../../crypto/assurance_context
proc consensusReportFailure[T](failure: ReportAdmissionResult[T]): bool =
  ## A missing lookup ancestor is a local context failure, not evidence that the block violates consensus.
  case failure.error
  of ReportAdmissionError.CredentialFailure:
    failure.credentialError.error in {GuaranteeCredentialError.InactiveCore,
      GuaranteeCredentialError.WrongErasureShards, GuaranteeCredentialError.WrongAssignment,
      GuaranteeCredentialError.InvalidSignature}
  of ReportAdmissionError.PolicyFailure:
    failure.policyError in {ReportPolicyError.Unauthorized, ReportPolicyError.UnknownService,
      ReportPolicyError.WrongCodeHash, ReportPolicyError.InsufficientGas,
      ReportPolicyError.ReportGasExceeded}
  of ReportAdmissionError.AnchorFailure:
    failure.anchorError in {ReportAnchorError.InvalidRecentAnchor, ReportAnchorError.LookupTooOld,
      ReportAnchorError.WrongLookupState}
  of ReportAdmissionError.PackageFailure:
    failure.packageError in {ReportPackageError.DuplicatePackage,
      ReportPackageError.MissingDependency,
      ReportPackageError.InvalidSegmentRoot}
  of ReportAdmissionError.AssignmentFailure:
    failure.assignmentError in {ReportAssignmentError.InactiveCore,
        ReportAssignmentError.OccupiedCore}
  else: false # Structural context, budgets, backend and unclassified refusals cannot manufacture an Error reply.
proc consensusBlockFailure(failure: BlockTransitionResult): bool =
  ## Each whitelist names protocol comparisons on the incoming block, excluding parent-state/configuration failures.
  case failure.error
  of BlockTransitionError.AdmissionFailure:
    failure.admissionError in {BlockAdmissionError.InvalidSlot,
      BlockAdmissionError.InvalidParentHash,
      BlockAdmissionError.InvalidStateRoot, BlockAdmissionError.InvalidExtrinsicHash}
  of BlockTransitionError.DisputesFailure:
    failure.disputesError in {DisputesError.InvalidEpoch, DisputesError.InvalidQuorum,
      DisputesError.InvalidSplit, DisputesError.AlreadyJudged, DisputesError.InvalidKey,
      DisputesError.InvalidSignature, DisputesError.InvalidEvidence, DisputesError.MissingFault,
      DisputesError.InvalidMarker, DisputesError.InvalidIndex}
  of BlockTransitionError.SafroleFailure:
    let safrole = failure.safroleError
    case safrole.error
    of SafroleTransitionError.InvalidSlot: true # Incoming slots must advance within the current epoch rules.
    of SafroleTransitionError.AdmissionFailure:
      safrole.admissionError in {TicketAdmissionError.InvalidSlot,
        TicketAdmissionError.UnexpectedTicket,
        TicketAdmissionError.InvalidAttempt, TicketAdmissionError.InvalidProof,
        TicketAdmissionError.BadOrder,
        TicketAdmissionError.Duplicate, TicketAdmissionError.NotRetained}
    of SafroleTransitionError.MarkerFailure:
      safrole.markerError in {SafroleMarkerError.InvalidEpochMarker,
          SafroleMarkerError.InvalidWinnersMarker}
    of SafroleTransitionError.AuthenticationFailure:
      safrole.authenticationError in {SafroleAuthError.InvalidSlot, SafroleAuthError.InvalidAuthor,
        SafroleAuthError.InvalidSeal, SafroleAuthError.InvalidTicket,
        SafroleAuthError.InvalidEntropy}
    else: false # Rotation/schedule/state/publication/resource failures remain local until precisely classified.
  of BlockTransitionError.AvailabilityFailure:
    let assurance = failure.availabilityError
    if assurance.error == AvailabilityTransitionError.ContextFailure:
      assurance.contextError in {AssuranceContextError.InvalidValidator,
        AssuranceContextError.NonCanonical,
        AssuranceContextError.WrongParent, AssuranceContextError.InvalidSignature}
    else:
      assurance.error in {AvailabilityTransitionError.InvalidSlot,
        AvailabilityTransitionError.InvalidIndex,
        AvailabilityTransitionError.UnassignedCore}
  else: false # Defaults and success are never rejections.
proc consensusFuzzRejection*(failure: CurrentCandidateResult): bool =
  ## Conservative classification of genuine failed candidates grants no authority from disconnected enum values.
  case failure.error
  of CurrentCandidateError.PrefixFailure:
    let prefix = failure.prefixFailure
    case prefix.error
    of ApplicationCandidateError.BlockFailure: consensusBlockFailure(prefix.blockFailure)
    of ApplicationCandidateError.ReportFailure: consensusReportFailure(prefix.reportFailure)
    else: false # Missing heads, changed profile, state forks and all other prefixes are local failures.
  of CurrentCandidateError.ReportFailure: consensusReportFailure(failure.reportFailure)
  else: false # Execution, storage, resource and unclassified failures close rather than impersonate consensus rejection.

proc localFuzzCandidateReason*(failure: CurrentCandidateResult): string =
  ## Keep actual missing lookup evidence observable locally without exposing a forged consensus Error.
  if failure.error == CurrentCandidateError.ReportFailure:
    let reports = failure.reportFailure
    if reports.error == ReportAdmissionError.AnchorFailure: return $reports.anchorError
    return $reports.error
  $failure.error
