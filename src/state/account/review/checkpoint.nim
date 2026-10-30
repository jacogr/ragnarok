# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit-root unchanged checkpoint restoration produces a same-source account review under caller-selected economic parameters.
## This synchronous consumer performs no I/O/installation, root discovery or universal funding/STF acceptance.
import ../../../codec/state/[trie as state_trie, composition as state_composition]
import ../../planned/account_checkpoint as planned_account_checkpoint
import ../[invariants as account_invariants, review as account_review]
import ../../service/directory as service_directory
import ../../[footprint_audit, supervision_table, economics_table, economic_profile]

type
  AccountReviewCheckpointLimits* = object ## Each restoration/audit/report stage retains its own explicit independent policies.
    checkpoint*: PlannedAccountCheckpointLimits
    directory*: ServiceDirectoryLimits
    footprints*: FootprintAuditLimits
    supervision*: SupervisionTableLimits
    economics*: EconomicsTableLimits
  AccountReviewCheckpointError* {.pure.} = enum ## Missing policy and genuinely failed stages expose no prefix review/source.
    Uninitialized, None, InvalidProfile, CheckpointFailure, DirectoryFailure, FootprintFailure,
      SupervisionFailure, EconomicsFailure, ReviewFailure
  AccountReviewCheckpointResult* = object ## Private phase alternatives preserve original guarded errors and success authority.
    case status: AccountReviewCheckpointError
    of None:
      completed: StateAccountReview
    of CheckpointFailure:
      checkpointReason: PlannedAccountCheckpointResult
    of DirectoryFailure:
      directoryReason: ServiceDirectoryResult[StateServiceDirectory]
    of FootprintFailure:
      footprintReason: FootprintAuditResult[CheckedAccountFootprints]
    of SupervisionFailure:
      supervisionReason: SupervisionTableResult[StateSupervisionTable]
    of EconomicsFailure:
      economicsReason: EconomicsTableResult[StateEconomicsTable]
    of ReviewFailure:
      reviewReason: AccountReviewResult[StateAccountReview]
    else:
      discard

func error*(outcome: AccountReviewCheckpointResult): AccountReviewCheckpointError =
  ## Read the immutable selected stage.
  outcome.status

func value*(outcome: AccountReviewCheckpointResult): StateAccountReview {.inline,
    requires: outcome.status == AccountReviewCheckpointError.None.} =
  ## Only all completed same-source stages expose a restored account review.
  outcome.completed

func checkpointFailure*(outcome: AccountReviewCheckpointResult): PlannedAccountCheckpointResult {.inline,
    requires: outcome.status == AccountReviewCheckpointError.CheckpointFailure.} =
  ## Preserve only the genuine failed checkpoint stage and its nested checked error contracts.
  outcome.checkpointReason

func directoryFailure*(outcome: AccountReviewCheckpointResult): ServiceDirectoryResult[
    StateServiceDirectory] {.inline,

requires: outcome.status == AccountReviewCheckpointError.DirectoryFailure.} =
  ## Preserve only the genuine failed directory stage and its nested checked error contracts.
  outcome.directoryReason

func footprintFailure*(outcome: AccountReviewCheckpointResult): FootprintAuditResult[
    CheckedAccountFootprints] {.inline,

requires: outcome.status == AccountReviewCheckpointError.FootprintFailure.} =
  ## Preserve only the genuine failed footprint stage and its nested checked error contracts.
  outcome.footprintReason

func supervisionFailure*(outcome: AccountReviewCheckpointResult): SupervisionTableResult[
    StateSupervisionTable] {.inline,

requires: outcome.status == AccountReviewCheckpointError.SupervisionFailure.} =
  ## Preserve only the genuine failed supervision stage and its nested checked error contracts.
  outcome.supervisionReason

func economicsFailure*(outcome: AccountReviewCheckpointResult): EconomicsTableResult[
    StateEconomicsTable] {.inline,

requires: outcome.status == AccountReviewCheckpointError.EconomicsFailure.} =
  ## Preserve only the genuine failed economics stage and its nested checked error contracts.
  outcome.economicsReason

func reviewFailure*(outcome: AccountReviewCheckpointResult): AccountReviewResult[
    StateAccountReview] {.inline,

requires: outcome.status == AccountReviewCheckpointError.ReviewFailure.} =
  ## Preserve only the genuine failed review stage and its nested checked error contracts.
  outcome.reviewReason

proc decodeAccountReviewCheckpoint*(input: openArray[byte], expected: StateRoot,
    services: openArray[StateService], profile: StateProfile, economics: StateEconomicProfile,
    limits: AccountReviewCheckpointLimits): AccountReviewCheckpointResult =
  ## Borrow bytes/declarations only synchronously; caller root and economic configuration remain mandatory independent selections.
  if economics.economicSchedule.error != EconomicProfileError.None:
    return AccountReviewCheckpointResult(status: AccountReviewCheckpointError.InvalidProfile) # Never restore with an implicitly substituted default economic policy.
  let checkpoint = decodePlannedAccountCheckpoint(input, expected, services, profile,
      limits.checkpoint)
  if checkpoint.error != PlannedAccountCheckpointError.None:
    return AccountReviewCheckpointResult(status: AccountReviewCheckpointError.CheckpointFailure,
      checkpointReason: checkpoint) # Preserve exact root/serialization/capture/admission/semantic failures.
  let source = checkpoint.value.accountInvariantInventory.value
  let directory = buildStateServiceDirectory(source, limits.directory)
  if directory.error != ServiceDirectoryError.None:
    return AccountReviewCheckpointResult(status: AccountReviewCheckpointError.DirectoryFailure,
        directoryReason: directory) # No restored prefix directory escapes policy refusal.
  let footprints = auditAccountFootprints(source, limits.footprints)
  if footprints.error != FootprintAuditError.None:
    return AccountReviewCheckpointResult(status: AccountReviewCheckpointError.FootprintFailure,
        footprintReason: footprints) # Bounded hash-free recheck supplies reusable original-source footprint evidence.
  let supervision = buildSupervisionTable(directory.value, limits.supervision)
  if supervision.error != SupervisionTableError.None:
    return AccountReviewCheckpointResult(status: AccountReviewCheckpointError.SupervisionFailure,
        supervisionReason: supervision) # Failed whole-service tables grant no prefix decisions.
  let deposits = buildEconomicsTable(footprints.value, directory.value, economics, limits.economics)
  if deposits.error != EconomicsTableError.None:
    return AccountReviewCheckpointResult(status: AccountReviewCheckpointError.EconomicsFailure,
        economicsReason: deposits) # Undercoverage is not failure; unrepresentable thresholds remain precise refusals.
  let review = joinAccountReview(checkpoint.value, supervision.value, deposits.value)
  if review.error != AccountReviewError.None:
    return AccountReviewCheckpointResult(status: AccountReviewCheckpointError.ReviewFailure,
        reviewReason: review) # A future wiring bug cannot bypass exact logical owner equality.
  AccountReviewCheckpointResult(status: AccountReviewCheckpointError.None, completed: review.value)
