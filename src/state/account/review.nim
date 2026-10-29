# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Constant-work same-source account review joins targeted invariants with complete supervisor/economic observations.
## Review success preserves each evidence scope; undercoverage does not become an unstated global invalid-state rule.
import ../inventory
import ./invariants as account_invariants
import ../service/directory as service_directory
import ../[supervision_table, economics_table, footprint_audit, economic_profile]

type
  AccountReviewInfo* = object ## Fixed completed component observations retain their original individual meanings.
    invariants*: AccountInvariantInfo
    supervision*: SupervisionTableInfo
    economics*: EconomicsTableInfo
  StateAccountReview* = object ## Private exact inputs prevent combining evidence from equal-root but different captures.
    invariants: CheckedAccountInvariants
    supervision: StateSupervisionTable
    economics: StateEconomicsTable
    info: AccountReviewInfo
  AccountReviewError* {.pure.} = enum ## Missing evidence and cross-owner substitution remain distinct without a prefix review.
    Uninitialized, None, InvalidInvariants, InvalidSupervision, InvalidEconomics, SourceMismatch
  AccountReviewResult*[T] = object ## Only complete exact-owner joins expose source-bearing review observations.
    case status: AccountReviewError
    of None:
      completed: T
    else:
      discard
func error*[T](outcome: AccountReviewResult[T]): AccountReviewError =
  ## Inspect the immutable selected alternative.
  outcome.status
func value*[T](outcome: AccountReviewResult[T]): T {.inline,
    requires: outcome.status == AccountReviewError.None.} =
  ## No failed/default join grants a completed account review or component prefix.
  outcome.completed
proc joinAccountReview*(invariants: CheckedAccountInvariants,
    supervision: StateSupervisionTable, economics: StateEconomicsTable): AccountReviewResult[
        StateAccountReview] =
  ## Join only the same initialized logical capture without allocation, payload copies, hashes or changed validity policy.
  let source = invariants.accountInvariantInventory
  if source.error != AccountInvariantError.None:
    return AccountReviewResult[StateAccountReview](
        status: AccountReviewError.InvalidInvariants) # No default targeted predicate evidence.
  let supervisors = supervision.supervisionTableDirectory
  if supervisors.error != SupervisionTableError.None:
    return AccountReviewResult[StateAccountReview](
        status: AccountReviewError.InvalidSupervision) # No default complete supervision observations.
  let deposits = economics.economicTableFootprints
  if deposits.error != EconomicsTableError.None:
    return AccountReviewResult[StateAccountReview](
        status: AccountReviewError.InvalidEconomics) # No default explicit-profile economic report.
  if not sameStateInventory(source.value, supervisors.value.directoryInventory.value) or
      not sameStateInventory(source.value, deposits.value.footprintInventory.value):
    return AccountReviewResult[StateAccountReview](
        status: AccountReviewError.SourceMismatch) # Equal roots/snapshots cannot substitute another logical capture.
  AccountReviewResult[StateAccountReview](status: AccountReviewError.None,
    completed: StateAccountReview(invariants: invariants, supervision: supervision,
      economics: economics,
      info: AccountReviewInfo(invariants: invariants.accountInvariantInfo.value,
        supervision: supervision.supervisionTableInfo.value,
        economics: economics.economicTableInfo.value)))
proc accountReviewInfo*(review: StateAccountReview): AccountReviewResult[AccountReviewInfo] =
  ## Copy or retain the original completed info evidence without exposing mutable review storage.
  if review.invariants.accountInvariantInventory.error != AccountInvariantError.None:
    return AccountReviewResult[AccountReviewInfo](
        status: AccountReviewError.Uninitialized) # Default review has no complete evidence.
  AccountReviewResult[AccountReviewInfo](status: AccountReviewError.None, completed: review.info)
proc reviewInvariants*(review: StateAccountReview): AccountReviewResult[CheckedAccountInvariants] =
  ## Copy or retain the original completed invariants evidence without exposing mutable review storage.
  if review.invariants.accountInvariantInventory.error != AccountInvariantError.None:
    return AccountReviewResult[CheckedAccountInvariants](
        status: AccountReviewError.Uninitialized) # Default review has no complete evidence.
  AccountReviewResult[CheckedAccountInvariants](status: AccountReviewError.None,
      completed: review.invariants)
proc reviewSupervision*(review: StateAccountReview): AccountReviewResult[StateSupervisionTable] =
  ## Copy or retain the original completed supervision evidence without exposing mutable review storage.
  if review.invariants.accountInvariantInventory.error != AccountInvariantError.None:
    return AccountReviewResult[StateSupervisionTable](
        status: AccountReviewError.Uninitialized) # Default review has no complete evidence.
  AccountReviewResult[StateSupervisionTable](status: AccountReviewError.None,
      completed: review.supervision)
proc reviewEconomics*(review: StateAccountReview): AccountReviewResult[StateEconomicsTable] =
  ## Copy or retain the original completed economics evidence without exposing mutable review storage.
  if review.invariants.accountInvariantInventory.error != AccountInvariantError.None:
    return AccountReviewResult[StateEconomicsTable](
        status: AccountReviewError.Uninitialized) # Default review has no complete evidence.
  AccountReviewResult[StateEconomicsTable](status: AccountReviewError.None,
      completed: review.economics)
proc reviewInventory*(review: StateAccountReview): AccountReviewResult[StateInventory] =
  ## Retain the exact original complete inventory without granting independent root trust.
  let source = review.invariants.accountInvariantInventory
  if source.error != AccountInvariantError.None:
    return AccountReviewResult[StateInventory](status: AccountReviewError.Uninitialized) # No default provenance.
  AccountReviewResult[StateInventory](status: AccountReviewError.None, completed: source.value)
proc reviewEconomicProfile*(review: StateAccountReview): AccountReviewResult[StateEconomicProfile] =
  ## Retain the exact explicitly selected configuration of the successful economic component.
  if review.invariants.accountInvariantInventory.error != AccountInvariantError.None:
    return AccountReviewResult[StateEconomicProfile](
        status: AccountReviewError.Uninitialized) # No default configuration.
  AccountReviewResult[StateEconomicProfile](status: AccountReviewError.None,
      completed: review.economics.economicTableProfile.value)
