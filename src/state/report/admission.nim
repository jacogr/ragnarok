# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 reporting_assurance.tex: bind every implemented report check to one completed block
## stage. Pure planning retains authenticated staged context; report_transition owns atomic
## publication.
##
## Exposes planBlockReports and retained block-stage, credential and assignment access with
## typed per-stage failures.

import ../../codec/[block_codec, header, bounded, guarantees, assurances]
import ../../codec/state/[safrole as state_safrole, disputes as state_disputes,
    history as state_history, layout as state_layout, availability as state_availability]
import ../fuzz/ancestry as fuzz_ancestry
import ../[ancestor_context, store]
import "../block/transition" as block_transition
import "../block/admission" as block_admission
import ../guarantee_credentials
import ./[policy as report_policy, anchors as report_anchors, packages as report_packages,
    assignments as report_assignments]
import ../[availability, history]

type
  ReportAdmissionConfig* = object ## Explicit chain/resource policies for credentials, parent state, ancestors and complete C(10) candidates.
    credentials*: GuaranteeCredentialConfig
    policy*: ReportPolicyConfig
    anchors*: ReportAnchorConfig
    ancestors*: AncestorConfig
    packages*: ReportPackageConfig
    judgments*: DisputeStateConfig
  ReportAdmissionError* {.pure.} = enum ## No default/refused alternative carries a certificate, assignment candidate or staged map.
    Uninitialized, None, InvalidTransition, InvalidConfig, MissingState, InvalidState,
    LimitExceeded, CredentialFailure, PolicyFailure, HistoryFailure, AnchorFailure,
    PackageFailure, AssignmentFailure
  ## Acyclic owner retains the coordinator result and every completed check over its own reports/context.
  AdmissionData = ref object
    staged: BlockTransitionResult
    credentials: VerifiedGuaranteeCredentials
    anchors: AnchoredReports
    packages: PackageCheckedReports
    assignments: ReportAssignmentPlan
  AdmittedReports* = object ## Opaque complete report-stage plan; this is neither a published block nor full JAM execution.
    data: nil AdmissionData
  PreparedReportData = ref object ## Block-bound credentials and recent checks survive bounded context acquisition.
    staged: BlockTransitionResult
    credentials: VerifiedGuaranteeCredentials
    recent: RecentAnchoredReports
    config: ReportAdmissionConfig
  PreparedReportAdmission* = object ## Successful preparation grants no assignment, publication or lookup certificate.
    data: nil PreparedReportData
  ReportAdmissionResult*[T] = object ## Exact child failures are available only from their selected alternative; ordinary errors carry reason alone.
    case status: ReportAdmissionError
    of None:
      completed: T
    of CredentialFailure:
      credentialReason: GuaranteeCredentialResult[VerifiedGuaranteeCredentials]
    of PolicyFailure:
      policyReason: ReportPolicyError
    of HistoryFailure:
      historyReason: HistoryTransitionError
    of AnchorFailure:
      anchorReason: ReportAnchorError
    of PackageFailure:
      packageReason: ReportPackageError
    of AssignmentFailure:
      assignmentReason: ReportAssignmentError
    else:
      discard # Failed stages never retain an accepted prefix or a proposed write.

func error*[T](outcome: ReportAdmissionResult[T]): ReportAdmissionError =
  ## Observe status without granting discriminator mutation.
  outcome.status
func value*[T](outcome: ReportAdmissionResult[T]): T {.inline,
    requires: outcome.status == ReportAdmissionError.None.} =
  ## Extract only completely selected success under the supported checked-build contract.
  outcome.completed
func credentialError*[T](outcome: ReportAdmissionResult[T]): GuaranteeCredentialResult[
    VerifiedGuaranteeCredentials] {.inline,
    requires: outcome.status == ReportAdmissionError.CredentialFailure.} =
  ## Inspect the original credential refusal, including its codec/assignment subreason.
  outcome.credentialReason
func policyError*[T](outcome: ReportAdmissionResult[T]): ReportPolicyError {.inline,
    requires: outcome.status == ReportAdmissionError.PolicyFailure.} =
  ## Inspect the selected parent authorization/service/gas failure.
  outcome.policyReason
func historyError*[T](outcome: ReportAdmissionResult[T]): HistoryTransitionError {.inline,
    requires: outcome.status == ReportAdmissionError.HistoryFailure.} =
  ## Inspect the selected parent-history correction failure.
  outcome.historyReason
func anchorError*[T](outcome: ReportAdmissionResult[T]): ReportAnchorError {.inline,
    requires: outcome.status == ReportAdmissionError.AnchorFailure.} =
  ## Inspect the selected recent/lookup ancestor failure.
  outcome.anchorReason
func packageError*[T](outcome: ReportAdmissionResult[T]): ReportPackageError {.inline,
    requires: outcome.status == ReportAdmissionError.PackageFailure.} =
  ## Inspect the selected prior-pipeline/dependency/root failure.
  outcome.packageReason
func assignmentError*[T](outcome: ReportAdmissionResult[T]): ReportAssignmentError {.inline,
    requires: outcome.status == ReportAdmissionError.AssignmentFailure.} =
  ## Inspect the selected post-assurance vacancy/encoding failure.
  outcome.assignmentReason

proc reportBlockStage*(owner: AdmittedReports): ReportAdmissionResult[BlockTransitionResult] =
  ## Retain the exact complete block-stage result; no mutable working-store handle is exported.
  let data = owner.data
  if data == nil:
    return ReportAdmissionResult[BlockTransitionResult](
        status: ReportAdmissionError.Uninitialized) # No invented admitted stage.
  ReportAdmissionResult[BlockTransitionResult](status: ReportAdmissionError.None,
      completed: data.staged)

proc reportCredentials*(owner: AdmittedReports): ReportAdmissionResult[
    VerifiedGuaranteeCredentials] =
  ## Retain only the credentials reverified from this block's exact guarantee extrinsic and posterior context.
  let data = owner.data
  if data == nil:
    return ReportAdmissionResult[VerifiedGuaranteeCredentials](
        status: ReportAdmissionError.Uninitialized) # No default verified empty batch.
  ReportAdmissionResult[VerifiedGuaranteeCredentials](status: ReportAdmissionError.None,
      completed: data.credentials)

proc reportAssignments*(owner: AdmittedReports): ReportAdmissionResult[ReportAssignmentPlan] =
  ## Retain the proposed immutable C(10) plan; its existing byte accessor returns a detached copy.
  let data = owner.data
  if data == nil:
    return ReportAdmissionResult[ReportAssignmentPlan](
        status: ReportAdmissionError.Uninitialized) # No disconnected assignment table.
  ReportAdmissionResult[ReportAssignmentPlan](status: ReportAdmissionError.None,
      completed: data.assignments)

## Bound required state before allocating its detached bytes; missing is never interpreted as an empty chapter.
proc chapter(source: StateStoreSnapshot, number: byte, limit: ByteLimit): ReportAdmissionResult[seq[byte]] =
  let found = source.lookup(chapterKey(StateChapter(number)))
  if found.error == StateStoreError.MissingKey:
    return ReportAdmissionResult[seq[byte]](status: ReportAdmissionError.MissingState) # Required explicit chapter absent.
  if found.error != StateStoreError.None:
    return ReportAdmissionResult[seq[byte]](status: ReportAdmissionError.InvalidState) # No default map.
  if uint64(found.value.byteLength) > uint64(limit):
    return ReportAdmissionResult[seq[byte]](status: ReportAdmissionError.LimitExceeded) # Check before copying retained bytes.
  ReportAdmissionResult[seq[byte]](status: ReportAdmissionError.None, completed: found.value.bytes)

proc prepareBlockReports*(staged: BlockTransitionResult,
    config: ReportAdmissionConfig): ReportAdmissionResult[PreparedReportAdmission] =
  ## Accept only the coordinator's private successful result, never a detached public BlockTransition value.
  ## Parent policy/pipeline/history come from admission; rosters/entropy/offenders/C(10) come from its completed stage.
  ## No caller-supplied reports, clock, corrected history, signatures or independently minted certificates are accepted.
  template fail(reason: ReportAdmissionError) =
    return ReportAdmissionResult[PreparedReportAdmission](status: reason)
  if staged.error != BlockTransitionError.None:
    fail(ReportAdmissionError.InvalidTransition) # Defaults and earlier refusals cannot reach report checks.
  let frame = staged.blockTransitionProfile
  let roster = config.credentials.assignments.roster
  let cores = uint64(frame.cores)
  let population = uint64(frame.validators)
  let sameCores = uint64(roster.cores) == cores and uint64(config.policy.pools.cores) == cores and
    uint64(config.anchors.history.cores) == cores and uint64(
        config.packages.availability.guarantee.cores) == cores and
    uint64(config.packages.queues.cores) == cores and uint64(config.ancestors.header.cores) == cores
  let samePopulation = uint64(roster.validators) == population and
    uint64(config.packages.availability.guarantee.validators) == population and
    uint64(config.ancestors.header.authorValidators) == population
  let sameEpoch = uint64(config.credentials.assignments.epochSlots) == uint64(frame.epochSlots) and
    uint64(config.packages.queues.epochSlots) == uint64(frame.epochSlots) and
    uint64(config.ancestors.header.epochSlots) == uint64(frame.epochSlots)
  if not sameCores or not samePopulation or not sameEpoch:
    fail(ReportAdmissionError.InvalidConfig) # One authenticated block cannot be reinterpreted under another chain profile.
  let step = staged.value
  let binding = step.admitted
  let parent = binding.admittedState
  let slot = StateTime(uint32(headerInfo(binding.admittedHeader).value.unsigned.slot))
  var raw = default(array[4, seq[byte]])
  # All posterior context is read from the same completed immutable map, before any report publication.
  for i, number in [8'u8, 9, 6, 5]:
    let limit = if i < 2: roster.maxBytes elif i == 2: ByteLimit(
        128) else: config.judgments.maxBytes
    let read = chapter(step.snapshot, number, limit)
    if read.error != ReportAdmissionError.None:
      fail(read.error) # No partial context survives a missing or oversized chapter.
    raw[i] = read.value
  let active = decodeStateValidators(raw[0], roster)
  let previous = decodeStateValidators(raw[1], roster)
  let entropy = decodeStateEntropy(raw[2])
  let judgments = decodeDisputeState(raw[3], config.judgments)
  if active.error != StateComponentError.None or previous.error != StateComponentError.None or
      entropy.error != StateComponentError.None or judgments.error != DisputeStateError.None:
    fail(ReportAdmissionError.InvalidState) # No unselected payload extraction.
  let exactRosters = active.value.consumed == raw[0].len and previous.value.consumed == raw[1].len
  let exactContext = entropy.value.consumed == raw[2].len and judgments.value.consumed == raw[3].len
  if not exactRosters or not exactContext:
    fail(ReportAdmissionError.InvalidState) # Suffixes are invalid state, never an alternate representation.
  let count = disputeStateInfo(judgments.value.snapshot).value.offenders
  if uint64(count) > uint64(config.credentials.assignments.offenders):
    fail(ReportAdmissionError.LimitExceeded) # Bound offender descriptor allocation under credential policy.
  var offenders = newSeq[OffenderKey](count)
  # Retain canonical cumulative offenders, not merely this block's newly added markers.
  for i in 0..<count:
    offenders[i] = stateOffenderAt(judgments.value.snapshot, DisputeStateIndex(i)).value
  let values = readGuarantees(extrinsicGuarantees(blockExtrinsic(
      binding.admittedBlock).value).value).value
  var guarantees = newSeq[Guarantee](values.count)
  # Only this admitted block's complete guarantees enter verification.
  for i in 0..<guarantees.len: guarantees[i] = guaranteeAt(values.owner, i).value
  let credentials = verifyGuaranteeCredentials(guarantees, active.value.value, previous.value.value,
    entropy.value.value, slot, offenders, config.credentials)
  if credentials.error != GuaranteeCredentialError.None:
    return ReportAdmissionResult[PreparedReportAdmission](
      status: ReportAdmissionError.CredentialFailure,
      credentialReason: credentials) # Keep exact nested signature/assignment/structure refusal.
  let policy = checkReportPolicy(credentials.value, parent, config.policy)
  if policy.error != ReportPolicyError.None:
    return ReportAdmissionResult[PreparedReportAdmission](
      status: ReportAdmissionError.PolicyFailure,
      policyReason: policy.error) # Read parent pools and services, never a loose/staged substitute.
  let historyBytes = chapter(parent, 3, config.anchors.history.maxBytes)
  if historyBytes.error != ReportAdmissionError.None: fail(historyBytes.error) # Missing is not genesis history.
  let decoded = decodeHistoryState(historyBytes.value, config.anchors.history)
  if decoded.error != HistoryError.None:
    fail(ReportAdmissionError.InvalidState) # No partial corrected history.
  if decoded.value.consumed != historyBytes.value.len:
    fail(ReportAdmissionError.InvalidState) # Exact C(3) bytes only.
  let corrected = correctHistoryParent(decoded.value.snapshot,
    HistoryStateRoot(array[32, byte](parent.commitment.root)), config.anchors.history)
  if corrected.error != HistoryTransitionError.None:
    return ReportAdmissionResult[PreparedReportAdmission](
      status: ReportAdmissionError.HistoryFailure,
      historyReason: corrected.error) # Only the newest parent's state root is corrected, with no append.
  let recent = checkRecentReportAnchors(policy.value, corrected.value.value, slot, config.anchors)
  if recent.error != ReportAnchorError.None:
    return ReportAdmissionResult[PreparedReportAdmission](
      status: ReportAdmissionError.AnchorFailure,
      anchorReason: recent.error) # Corrected history and candidate time are derived, not externally supplied.
  ReportAdmissionResult[PreparedReportAdmission](status: ReportAdmissionError.None,
    completed: PreparedReportAdmission(data: PreparedReportData(staged: staged,
      credentials: credentials.value, recent: recent.value, config: config)))

proc completeAnchoredReports(prepared: PreparedReportAdmission,
    anchored: ReportAnchorResult[AnchoredReports]): ReportAdmissionResult[AdmittedReports] =
  ## Share package/vacancy completion while preserving the exact anchor owner and its domain.
  let data = prepared.data
  if data == nil: return ReportAdmissionResult[AdmittedReports](
      status: ReportAdmissionError.InvalidTransition)
  if anchored.error != ReportAnchorError.None:
    return ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.AnchorFailure,
      anchorReason: anchored.error)
  let packages = checkReportPackages(data.recent, data.config.packages)
  if packages.error != ReportPackageError.None:
    return ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.PackageFailure,
      packageReason: packages.error) # Existing packages deliberately come from parent C(10)/C(14)/C(15).
  let planned = planReportAssignments(data.credentials,
    data.staged.value.availability.assuredAssignments,
    data.config.packages.availability)
  if planned.error != ReportAssignmentError.None:
    return ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.AssignmentFailure,
      assignmentReason: planned.error) # Vacancy deliberately uses actual post-assurance C(10).
  ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.None,
    completed: AdmittedReports(data: AdmissionData(staged: data.staged,
      credentials: data.credentials,
      anchors: anchored.value, packages: packages.value, assignments: planned.value)))

proc completeBlockReports*(prepared: PreparedReportAdmission,
    older: openArray[OwnedHeader]): ReportAdmissionResult[AdmittedReports] =
  ## Ordinary completion still requires the full authenticated contiguous ancestor sequence.
  let data = prepared.data
  if data == nil: return ReportAdmissionResult[AdmittedReports](
      status: ReportAdmissionError.InvalidTransition)
  completeAnchoredReports(prepared, checkReportLookupAnchors(data.recent,
    data.staged.value.admitted.admittedParent, older, data.config.ancestors))
proc completeFuzzBlockReports*(prepared: PreparedReportAdmission,
    context: FuzzAncestry): ReportAdmissionResult[AdmittedReports] =
  ## Alternate initial membership is explicitly retained as fuzz-only authority in every completed owner.
  let data = prepared.data
  if data == nil: return ReportAdmissionResult[AdmittedReports](
      status: ReportAdmissionError.InvalidTransition)
  completeAnchoredReports(prepared, checkFuzzReportLookupAnchors(data.recent,
    data.staged.value.admitted.admittedParent, context, data.config.ancestors))
proc requiresFuzzView*(owner: AdmittedReports): bool =
  ## Downstream chain producers inspect the original immutable anchor domain before publishing.
  let data = owner.data
  data != nil and data.anchors.requiresFuzzView

proc reportPreparationFailure*(prepared: ReportAdmissionResult[
    PreparedReportAdmission]): ReportAdmissionResult[AdmittedReports] =
  ## Preserve selected nested refusal exactly; this private bridge cannot convert success into a partial certificate.
  case prepared.error
  of ReportAdmissionError.CredentialFailure:
    ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.CredentialFailure,
        credentialReason: prepared.credentialError)
  of ReportAdmissionError.PolicyFailure:
    ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.PolicyFailure,
        policyReason: prepared.policyError)
  of ReportAdmissionError.HistoryFailure:
    ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.HistoryFailure,
        historyReason: prepared.historyError)
  of ReportAdmissionError.AnchorFailure:
    ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.AnchorFailure,
        anchorReason: prepared.anchorError)
  of ReportAdmissionError.PackageFailure:
    ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.PackageFailure,
        packageReason: prepared.packageError)
  of ReportAdmissionError.AssignmentFailure:
    ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.AssignmentFailure,
        assignmentReason: prepared.assignmentError)
  of ReportAdmissionError.None:
    ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.InvalidTransition) # A successful prefix needs explicit completion.
  else:
    ReportAdmissionResult[AdmittedReports](status: prepared.error)

proc planBlockReports*(staged: BlockTransitionResult, older: openArray[OwnedHeader],
    config: ReportAdmissionConfig): ReportAdmissionResult[AdmittedReports] =
  ## Compatibility coordinator preserves exact full admission and failure ordering through the two explicit stages.
  let prepared = prepareBlockReports(staged, config)
  if prepared.error != ReportAdmissionError.None: return reportPreparationFailure(prepared)
  completeBlockReports(prepared.value, older)

proc planPreparedReportLookupDemand*(prepared: PreparedReportAdmission,
    older: openArray[OwnedHeader]): ReportAdmissionResult[ReportLookupDemand] =
  ## Bind discovery to the actual admitted parent and original policy; callers supply only an older suffix.
  let data = prepared.data
  if data == nil:
    return ReportAdmissionResult[ReportLookupDemand](status: ReportAdmissionError.InvalidTransition)
  let packages = checkReportPackages(data.recent, data.config.packages)
  if packages.error != ReportPackageError.None:
    return ReportAdmissionResult[ReportLookupDemand](status: ReportAdmissionError.PackageFailure,
      packageReason: packages.error) # Known invalid dependencies/duplicates must not cause network acquisition.
  let assignments = planReportAssignments(data.credentials,
    data.staged.value.availability.assuredAssignments,
    data.config.packages.availability)
  if assignments.error != ReportAssignmentError.None:
    return ReportAdmissionResult[ReportLookupDemand](status: ReportAdmissionError.AssignmentFailure,
      assignmentReason: assignments.error) # Occupied post-assurance cores cannot be repaired by fetching older headers.
  let limits = data.config.ancestors
  let context = captureAncestorContext(data.staged.value.admitted.admittedParent, older,
    AncestorContextLimits(header: limits.header, headers: limits.headers,
        maxBytes: limits.maxBytes))
  if context.error != AncestorContextError.None:
    var reason = ReportAnchorError.InvalidHeader
    case context.error
    of AncestorContextError.LimitExceeded: reason = ReportAnchorError.LimitExceeded # Preserve independent resource refusals.
    of AncestorContextError.BrokenAncestry: reason = ReportAnchorError.BrokenAncestry # A supplied gap is never repaired by remote extension.
    of AncestorContextError.BackendFailure: reason = ReportAnchorError.BackendFailure # No fabricated digest or fallback.
    else: discard # Invalid/default header alternatives carry no context.
    return ReportAdmissionResult[ReportLookupDemand](status: ReportAdmissionError.AnchorFailure,
        anchorReason: reason)
  let demand = planReportLookupDemand(data.recent, context.value)
  if demand.error != ReportAnchorError.None:
    return ReportAdmissionResult[ReportLookupDemand](status: ReportAdmissionError.AnchorFailure,
        anchorReason: demand.error)
  ReportAdmissionResult[ReportLookupDemand](status: ReportAdmissionError.None,
      completed: demand.value)
