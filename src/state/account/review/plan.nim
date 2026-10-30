# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prepare all bounded complete account reports before content hashing; execute only frozen same-source policies.
## Prepared reports and targeted invariants grant neither trusted-root authority nor full global/STF validity.
import ../../inventory
import ../audit/plan as account_audit_plan
import ../../footprint_audit
import ../../preimage/[content as preimage_content, linkage as preimage_linkage]
import ../[invariants as account_invariants, review as account_review]
import ../../service/directory as service_directory
import ../../[supervision_table, economics_table, economic_profile]
type
  AccountReviewPlanLimits* = object ## Caller-selected independent bounds are copied into a private immutable plan.
    audit*: AccountAuditLimits
    directory*: ServiceDirectoryLimits
    supervision*: SupervisionTableLimits
    economics*: EconomicsTableLimits
  AccountReviewPlanInfo* = object ## Copied completed preparation observations describe work/coverage, not full state validity.
    audit*: AccountAuditPlanInfo
    directory*: ServiceDirectoryInfo
    supervision*: SupervisionTableInfo
    economics*: EconomicsTableInfo
  StateAccountReviewPlan* = object ## Private same-source report owners and policies cannot be substituted after preparation.
    initialized: bool
    source: StateInventory
    limits: AccountReviewPlanLimits
    footprints: CheckedAccountFootprints
    supervision: StateSupervisionTable
    economics: StateEconomicsTable
    info: AccountReviewPlanInfo
  AccountReviewPlanError* {.pure.} = enum ## Default and failed stages retain only genuine reasons, never a prepared prefix.
    Uninitialized, None, InvalidProfile, AdmissionFailure, DirectoryFailure, FootprintFailure,
      SupervisionFailure, EconomicsFailure
  AccountReviewPlanResult*[T] = object ## Private alternatives authorize extraction only after complete success.
    case status: AccountReviewPlanError
    of None:
      completed: T
    of AdmissionFailure:
      admissionReason: AccountAuditPlanResult[StateAccountAuditPlan]
    of DirectoryFailure:
      directoryReason: ServiceDirectoryResult[StateServiceDirectory]
    of FootprintFailure:
      footprintReason: FootprintAuditResult[CheckedAccountFootprints]
    of SupervisionFailure:
      supervisionReason: SupervisionTableResult[StateSupervisionTable]
    of EconomicsFailure:
      economicsReason: EconomicsTableResult[StateEconomicsTable]
    else:
      discard # No failed/default result retains a completed prefix.
  AccountReviewExecutionError* {.pure.} = enum ## Default and failed stages retain only genuine reasons, never a prepared prefix.
    Uninitialized, None, InvalidPlan, LinkageFailure, ContentFailure, InvariantFailure, ReviewFailure
  AccountReviewExecutionResult* = object ## Private alternatives authorize extraction only after complete success.
    case status: AccountReviewExecutionError
    of None:
      completed: StateAccountReview
    of LinkageFailure:
      linkageReason: PreimageLinkageResult[CheckedPreimageLinkage]
    of ContentFailure:
      contentReason: PreimageContentResult[CheckedPreimageContent]
    of InvariantFailure:
      invariantReason: AccountInvariantResult[CheckedAccountInvariants]
    of ReviewFailure:
      reviewReason: AccountReviewResult[StateAccountReview]
    else:
      discard # No failed/default result retains a completed prefix.

func error*[T](outcome: AccountReviewPlanResult[T]): AccountReviewPlanError =
  ## Read the selected immutable preparation/execution stage.
  outcome.status

func value*[T](outcome: AccountReviewPlanResult[T]): T {.inline, requires: outcome.status ==
    AccountReviewPlanError.None.} =
  ## Only complete success authorizes extraction of the prepared plan or final review.
  outcome.completed

func admissionFailure*[T](outcome: AccountReviewPlanResult[T]): AccountAuditPlanResult[
    StateAccountAuditPlan] {.inline, requires: outcome.status ==
    AccountReviewPlanError.AdmissionFailure.} =
  ## Preserve only the genuine failed admission stage, including its original guarded nested reason.
  outcome.admissionReason

func directoryFailure*[T](outcome: AccountReviewPlanResult[T]): ServiceDirectoryResult[
    StateServiceDirectory] {.inline, requires: outcome.status ==
    AccountReviewPlanError.DirectoryFailure.} =
  ## Preserve only the genuine failed directory stage, including its original guarded nested reason.
  outcome.directoryReason

func footprintFailure*[T](outcome: AccountReviewPlanResult[T]): FootprintAuditResult[
    CheckedAccountFootprints] {.inline, requires: outcome.status ==
    AccountReviewPlanError.FootprintFailure.} =
  ## Preserve only the genuine failed footprint stage, including its original guarded nested reason.
  outcome.footprintReason

func supervisionFailure*[T](outcome: AccountReviewPlanResult[T]): SupervisionTableResult[
    StateSupervisionTable] {.inline, requires: outcome.status ==
    AccountReviewPlanError.SupervisionFailure.} =
  ## Preserve only the genuine failed supervision stage, including its original guarded nested reason.
  outcome.supervisionReason

func economicsFailure*[T](outcome: AccountReviewPlanResult[T]): EconomicsTableResult[
    StateEconomicsTable] {.inline, requires: outcome.status ==
    AccountReviewPlanError.EconomicsFailure.} =
  ## Preserve only the genuine failed economics stage, including its original guarded nested reason.
  outcome.economicsReason

func error*(outcome: AccountReviewExecutionResult): AccountReviewExecutionError =
  ## Read the selected immutable preparation/execution stage.
  outcome.status

func value*(outcome: AccountReviewExecutionResult): StateAccountReview {.inline,
    requires: outcome.status == AccountReviewExecutionError.None.} =
  ## Only complete success authorizes extraction of the prepared plan or final review.
  outcome.completed

func linkageFailure*(outcome: AccountReviewExecutionResult): PreimageLinkageResult[
    CheckedPreimageLinkage] {.inline, requires: outcome.status ==
    AccountReviewExecutionError.LinkageFailure.} =
  ## Preserve only the genuine failed linkage stage, including its original guarded nested reason.
  outcome.linkageReason

func contentFailure*(outcome: AccountReviewExecutionResult): PreimageContentResult[
    CheckedPreimageContent] {.inline, requires: outcome.status ==
    AccountReviewExecutionError.ContentFailure.} =
  ## Preserve only the genuine failed content stage, including its original guarded nested reason.
  outcome.contentReason

func invariantFailure*(outcome: AccountReviewExecutionResult): AccountInvariantResult[
    CheckedAccountInvariants] {.inline, requires: outcome.status ==
    AccountReviewExecutionError.InvariantFailure.} =
  ## Preserve only the genuine failed invariant stage, including its original guarded nested reason.
  outcome.invariantReason

func reviewFailure*(outcome: AccountReviewExecutionResult): AccountReviewResult[
    StateAccountReview] {.inline, requires: outcome.status ==
    AccountReviewExecutionError.ReviewFailure.} =
  ## Preserve only the genuine failed review stage, including its original guarded nested reason.
  outcome.reviewReason

proc reviewPlanInfo*(plan: StateAccountReviewPlan): AccountReviewPlanResult[AccountReviewPlanInfo] =
  ## Default plans expose no fabricated observations; successful copies retain frozen completed facts.
  if not plan.initialized:
    return AccountReviewPlanResult[AccountReviewPlanInfo](
        status: AccountReviewPlanError.Uninitialized)
  AccountReviewPlanResult[AccountReviewPlanInfo](status: AccountReviewPlanError.None,
      completed: plan.info)

proc planAccountReview*(source: StateInventory, profile: StateEconomicProfile,
    limits: AccountReviewPlanLimits): AccountReviewPlanResult[StateAccountReviewPlan] =
  ## Admit every account content policy and complete all hash-free reports before a plan can escape.
  if profile.economicSchedule.error != EconomicProfileError.None:
    return AccountReviewPlanResult[StateAccountReviewPlan](
        status: AccountReviewPlanError.InvalidProfile) # No implicit economic policy is selected.
  let admission = planAccountAudit(source, limits.audit)
  if admission.error != AccountAuditPlanError.None:
    return AccountReviewPlanResult[StateAccountReviewPlan](
      status: AccountReviewPlanError.AdmissionFailure,
      admissionReason: admission) # Refuse without exposing earlier prepared owners or content work.
  let directory = buildStateServiceDirectory(source, limits.directory)
  if directory.error != ServiceDirectoryError.None:
    return AccountReviewPlanResult[StateAccountReviewPlan](
      status: AccountReviewPlanError.DirectoryFailure,
      directoryReason: directory) # Refuse without exposing earlier prepared owners or content work.
  let footprint = auditAccountFootprints(source, limits.audit.footprints)
  if footprint.error != FootprintAuditError.None:
    return AccountReviewPlanResult[StateAccountReviewPlan](
      status: AccountReviewPlanError.FootprintFailure,
      footprintReason: footprint) # Refuse without exposing earlier prepared owners or content work.
  let supervision = buildSupervisionTable(directory.value, limits.supervision)
  if supervision.error != SupervisionTableError.None:
    return AccountReviewPlanResult[StateAccountReviewPlan](
      status: AccountReviewPlanError.SupervisionFailure,
      supervisionReason: supervision) # Refuse without exposing earlier prepared owners or content work.
  let economics = buildEconomicsTable(footprint.value, directory.value, profile, limits.economics)
  if economics.error != EconomicsTableError.None:
    return AccountReviewPlanResult[StateAccountReviewPlan](
      status: AccountReviewPlanError.EconomicsFailure,
      economicsReason: economics) # Refuse without exposing earlier prepared owners or content work.
  let info = AccountReviewPlanInfo(audit: admission.value.accountPlanInfo.value,
    directory: directory.value.directoryInfo.value,
    supervision: supervision.value.supervisionTableInfo.value,
    economics: economics.value.economicTableInfo.value)
  AccountReviewPlanResult[StateAccountReviewPlan](status: AccountReviewPlanError.None,
    completed: StateAccountReviewPlan(initialized: true, source: source, limits: limits,
      footprints: footprint.value, supervision: supervision.value, economics: economics.value, info: info))

proc executeAccountReview*(plan: StateAccountReviewPlan): AccountReviewExecutionResult =
  ## Accept no replacement inventory, profile or policy; prepared reports already completed their bounds and arithmetic.
  if not plan.initialized:
    return AccountReviewExecutionResult(status: AccountReviewExecutionError.InvalidPlan) # A default plan grants no empty review.
  let linkage = auditPreimageLinkage(plan.source, plan.limits.audit.linkage)
  if linkage.error != PreimageLinkageError.None:
    return AccountReviewExecutionResult(status: AccountReviewExecutionError.LinkageFailure,
      linkageReason: linkage) # Preserve the actual failed predicate/join without a review prefix.
  let content = auditPreimageContent(plan.source, plan.limits.audit.content)
  if content.error != PreimageContentError.None:
    return AccountReviewExecutionResult(status: AccountReviewExecutionError.ContentFailure,
      contentReason: content) # Preserve the actual failed predicate/join without a review prefix.
  let invariant = joinAccountInvariants(plan.footprints, content.value, linkage.value)
  if invariant.error != AccountInvariantError.None:
    return AccountReviewExecutionResult(status: AccountReviewExecutionError.InvariantFailure,
      invariantReason: invariant) # Preserve the actual failed predicate/join without a review prefix.
  let review = joinAccountReview(invariant.value, plan.supervision, plan.economics)
  if review.error != AccountReviewError.None:
    return AccountReviewExecutionResult(status: AccountReviewExecutionError.ReviewFailure,
      reviewReason: review) # Preserve the actual failed predicate/join without a review prefix.
  AccountReviewExecutionResult(status: AccountReviewExecutionError.None, completed: review.value)
