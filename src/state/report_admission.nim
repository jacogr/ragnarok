# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 reporting_assurance.tex: bind every implemented report check to one completed block stage.
## Pure planning retains authenticated staged context; publication and accumulation remain separate increments.
import ../codec/[block_codec, header, bounded, guarantees, assurances, state_safrole,
  state_disputes, state_history, state_layout, state_availability]
import ./[store, block_transition, block_admission, guarantee_credentials, report_policy,
  report_anchors, report_packages, report_assignments, availability, history]

type
  ## Explicit chain/resource policies for credentials, parent state, ancestors and complete C(10) candidates.
  ReportAdmissionConfig* = object
    credentials*: GuaranteeCredentialConfig
    policy*: ReportPolicyConfig
    anchors*: ReportAnchorConfig
    ancestors*: AncestorConfig
    packages*: ReportPackageConfig
    judgments*: DisputeStateConfig
  ## No default/refused alternative carries a certificate, assignment candidate or staged map.
  ReportAdmissionError* {.pure.} = enum
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
  ## Opaque complete report-stage plan; this is neither a published block nor full JAM execution.
  AdmittedReports* = object
    data: nil AdmissionData
  ## Exact child failures are available only from their selected alternative; ordinary errors carry reason alone.
  ReportAdmissionResult*[T] = object
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

## Observe status without granting discriminator mutation.
func error*[T](outcome: ReportAdmissionResult[T]): ReportAdmissionError = outcome.status
## Extract only completely selected success under the supported checked-build contract.
func value*[T](outcome: ReportAdmissionResult[T]): T {.inline,
    requires: outcome.status == ReportAdmissionError.None.} = outcome.completed
## Inspect the original credential refusal, including its codec/assignment subreason.
func credentialError*[T](outcome: ReportAdmissionResult[T]): GuaranteeCredentialResult[
    VerifiedGuaranteeCredentials] {.inline,
    requires: outcome.status == ReportAdmissionError.CredentialFailure.} = outcome.credentialReason
## Inspect the selected parent authorization/service/gas failure.
func policyError*[T](outcome: ReportAdmissionResult[T]): ReportPolicyError {.inline,
    requires: outcome.status == ReportAdmissionError.PolicyFailure.} = outcome.policyReason
## Inspect the selected parent-history correction failure.
func historyError*[T](outcome: ReportAdmissionResult[T]): HistoryTransitionError {.inline,
    requires: outcome.status == ReportAdmissionError.HistoryFailure.} = outcome.historyReason
## Inspect the selected recent/lookup ancestor failure.
func anchorError*[T](outcome: ReportAdmissionResult[T]): ReportAnchorError {.inline,
    requires: outcome.status == ReportAdmissionError.AnchorFailure.} = outcome.anchorReason
## Inspect the selected prior-pipeline/dependency/root failure.
func packageError*[T](outcome: ReportAdmissionResult[T]): ReportPackageError {.inline,
    requires: outcome.status == ReportAdmissionError.PackageFailure.} = outcome.packageReason
## Inspect the selected post-assurance vacancy/encoding failure.
func assignmentError*[T](outcome: ReportAdmissionResult[T]): ReportAssignmentError {.inline,
    requires: outcome.status == ReportAdmissionError.AssignmentFailure.} = outcome.assignmentReason

## Retain the exact complete block-stage result; no mutable working-store handle is exported.
proc reportBlockStage*(owner: AdmittedReports): ReportAdmissionResult[BlockTransitionResult] =
  let data = owner.data
  if data == nil:
    return ReportAdmissionResult[BlockTransitionResult](
        status: ReportAdmissionError.Uninitialized) # No invented admitted stage.
  ReportAdmissionResult[BlockTransitionResult](status: ReportAdmissionError.None,
      completed: data.staged)

## Retain only the credentials reverified from this block's exact guarantee extrinsic and posterior context.
proc reportCredentials*(owner: AdmittedReports): ReportAdmissionResult[
    VerifiedGuaranteeCredentials] =
  let data = owner.data
  if data == nil:
    return ReportAdmissionResult[VerifiedGuaranteeCredentials](
        status: ReportAdmissionError.Uninitialized) # No default verified empty batch.
  ReportAdmissionResult[VerifiedGuaranteeCredentials](status: ReportAdmissionError.None,
      completed: data.credentials)

## Retain the proposed immutable C(10) plan; its existing byte accessor returns a detached copy.
proc reportAssignments*(owner: AdmittedReports): ReportAdmissionResult[ReportAssignmentPlan] =
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

## Accept only the coordinator's private successful result, never a detached public BlockTransition value.
## Parent policy/pipeline/history come from admission; rosters/entropy/offenders/C(10) come from its completed stage.
## No caller-supplied reports, clock, corrected history, signatures or independently minted certificates are accepted.
proc planBlockReports*(staged: BlockTransitionResult, older: openArray[OwnedHeader],
    config: ReportAdmissionConfig): ReportAdmissionResult[AdmittedReports] =
  template fail(reason: ReportAdmissionError) =
    return ReportAdmissionResult[AdmittedReports](status: reason)
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
    return ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.CredentialFailure,
      credentialReason: credentials) # Keep exact nested signature/assignment/structure refusal.
  let policy = checkReportPolicy(credentials.value, parent, config.policy)
  if policy.error != ReportPolicyError.None:
    return ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.PolicyFailure,
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
    return ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.HistoryFailure,
      historyReason: corrected.error) # Only the newest parent's state root is corrected, with no append.
  let recent = checkRecentReportAnchors(policy.value, corrected.value.value, slot, config.anchors)
  if recent.error != ReportAnchorError.None:
    return ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.AnchorFailure,
      anchorReason: recent.error) # Corrected history and candidate time are derived, not externally supplied.
  let anchored = checkReportLookupAnchors(recent.value, binding.admittedParent, older,
      config.ancestors)
  if anchored.error != ReportAnchorError.None:
    return ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.AnchorFailure,
      anchorReason: anchored.error) # Caller may supply older headers but cannot replace the actual parent endpoint.
  let packages = checkReportPackages(recent.value, config.packages)
  if packages.error != ReportPackageError.None:
    return ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.PackageFailure,
      packageReason: packages.error) # Existing packages deliberately come from parent C(10)/C(14)/C(15).
  let planned = planReportAssignments(credentials.value, step.availability.assuredAssignments,
    config.packages.availability)
  if planned.error != ReportAssignmentError.None:
    return ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.AssignmentFailure,
      assignmentReason: planned.error) # Vacancy deliberately uses actual post-assurance C(10).
  ReportAdmissionResult[AdmittedReports](status: ReportAdmissionError.None,
    completed: AdmittedReports(data: AdmissionData(staged: staged, credentials: credentials.value,
      anchors: anchored.value, packages: packages.value, assignments: planned.value)))
