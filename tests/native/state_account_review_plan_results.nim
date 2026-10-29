# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict prepared-review payload/reason guards retain a genuine complete-source execution control.
import std/[assertions, cmdline, syncio]
import ../support/[state_inventory_context, account_review_plan_context, economic_profile_context]
import ../../src/chain/parameters
import ../../src/state/account/review/plan as account_review_plan
import ../../src/state/account/review as account_review
import ../../src/state/[inventory, economic_profile]
include ./composition_fixture
proc extract(outcome: AccountReviewPlanResult[StateAccountReviewPlan]): StateAccountReviewPlan {.noinline.} =
  ## No failed/default preparation result grants a plan.
  outcome.value
proc extract(outcome: AccountReviewExecutionResult) {.noinline.} =
  ## No failed/default execution grants a complete review.
  discard outcome.value
proc prepareAdmission(outcome: AccountReviewPlanResult[StateAccountReviewPlan]) {.noinline.} =
  ## Runtime inputs preserve the intended success-only nested-reason contract.
  discard outcome.admissionFailure
proc prepareDirectory(outcome: AccountReviewPlanResult[StateAccountReviewPlan]) {.noinline.} =
  ## Runtime inputs preserve the intended success-only nested-reason contract.
  discard outcome.directoryFailure
proc prepareFootprint(outcome: AccountReviewPlanResult[StateAccountReviewPlan]) {.noinline.} =
  ## Runtime inputs preserve the intended success-only nested-reason contract.
  discard outcome.footprintFailure
proc prepareSupervision(outcome: AccountReviewPlanResult[StateAccountReviewPlan]) {.noinline.} =
  ## Runtime inputs preserve the intended success-only nested-reason contract.
  discard outcome.supervisionFailure
proc prepareEconomics(outcome: AccountReviewPlanResult[StateAccountReviewPlan]) {.noinline.} =
  ## Runtime inputs preserve the intended success-only nested-reason contract.
  discard outcome.economicsFailure
proc executeLinkage(outcome: AccountReviewExecutionResult) {.noinline.} =
  ## Runtime inputs preserve the intended success-only nested-reason contract.
  discard outcome.linkageFailure
proc executeContent(outcome: AccountReviewExecutionResult) {.noinline.} =
  ## Runtime inputs preserve the intended success-only nested-reason contract.
  discard outcome.contentFailure
proc executeInvariant(outcome: AccountReviewExecutionResult) {.noinline.} =
  ## Runtime inputs preserve the intended success-only nested-reason contract.
  discard outcome.invariantFailure
proc executeReview(outcome: AccountReviewExecutionResult) {.noinline.} =
  ## Runtime inputs preserve the intended success-only nested-reason contract.
  discard outcome.reviewFailure
case paramStr(1)
of "default-plan": discard extract(default(AccountReviewPlanResult[StateAccountReviewPlan]))
of "profile": discard extract(planAccountReview(default(StateInventory), default(
    StateEconomicProfile), reviewPlanTestLimits))
of "default-execution": extract(default(AccountReviewExecutionResult))
of "invalid-execution": extract(executeAccountReview(default(StateAccountReviewPlan)))
of "prepare-admission": prepareAdmission(default(AccountReviewPlanResult[
    StateAccountReviewPlan])) # Wrong alternatives cannot invent a failed stage.
of "prepare-directory": prepareDirectory(default(AccountReviewPlanResult[
    StateAccountReviewPlan])) # Wrong alternatives cannot invent a failed stage.
of "prepare-footprint": prepareFootprint(default(AccountReviewPlanResult[
    StateAccountReviewPlan])) # Wrong alternatives cannot invent a failed stage.
of "prepare-supervision": prepareSupervision(default(AccountReviewPlanResult[
    StateAccountReviewPlan])) # Wrong alternatives cannot invent a failed stage.
of "prepare-economics": prepareEconomics(default(AccountReviewPlanResult[
    StateAccountReviewPlan])) # Wrong alternatives cannot invent a failed stage.
of "execute-linkage": executeLinkage(default(AccountReviewExecutionResult)) # Wrong alternatives cannot invent a failed stage.
of "execute-content": executeContent(default(AccountReviewExecutionResult)) # Wrong alternatives cannot invent a failed stage.
of "execute-invariant": executeInvariant(default(AccountReviewExecutionResult)) # Wrong alternatives cannot invent a failed stage.
of "execute-review": executeReview(default(AccountReviewExecutionResult)) # Wrong alternatives cannot invent a failed stage.
of "ok":
  let services = inventoryServices()
  let source = captureStateInventory(inventoryManifest(compositionFixture(paramStr(2)), services),
      services, inventoryCaptureLimits).value
  let profile = captureEconomicProfile(decodeParameters(economicTestWire()).value).value
  let plan = extract(planAccountReview(source, profile, reviewPlanTestLimits))
  assert plan.reviewPlanInfo.value.directory.services == 2
  assert executeAccountReview(plan).value.accountReviewInfo.value.invariants.content.bytes == 3
  echo "state-account-review-plan-results: ok"
else: quit(2) # Unknown selectors cannot satisfy intended guard evidence.
