# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prepared complete reports move every report refusal before content work while retaining exact owners and guarded errors.
# @@Verification={"arc": "state_account_review_plan_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[state_inventory_context, account_review_plan_context,
    economic_profile_context, arc_evidence]
import ../../../src/chain/parameters
import ../../../src/state/account/review/plan as account_review_plan
import ../../../src/state/account/review as account_review
import ../../../src/state/inventory
import ../../../src/state/account/audit/plan as account_audit_plan
import ../../../src/state/footprint_audit
import ../../../src/state/service/directory as service_directory
import ../../../src/state/[supervision_table, economics_table, economic_profile]
import ../../../src/state/preimage/[content as preimage_content, linkage as preimage_linkage]
import ../../../src/codec/bounded
import ../../../src/codec/state/[accounts as state_accounts, requests as state_requests]
include ../../native/composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset counters and refuse hashing while checking preparation and report/resource failures.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe only account content work after complete source construction.
proc cycle(source: StateInventory, profile: StateEconomicProfile) =
  ## Retire a complete prepared-report and executed-review graph on every cycle.
  let plan = planAccountReview(source, profile, reviewPlanTestLimits).value
  assert executeAccountReview(plan).value.accountReviewInfo.value.invariants.content.bytes == 3
proc main() {.raises.} =
  ## Build genuine complete sources before disabling the backend; fixed reports need no content hash.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var services = inventoryServices()
  services[0].metadata.balance = AccountBalance(100)
  let source = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  var incorrect = services
  incorrect[0].metadata.storageItems = AccountStorageItems(4)
  let badFootprint = captureStateInventory(inventoryManifest(fixture, incorrect), incorrect,
      inventoryCaptureLimits).value
  incorrect = inventoryServices()
  incorrect[0].preimages[0].value = @[byte(98), 98, 99]
  let badContent = captureStateInventory(inventoryManifest(fixture, incorrect), incorrect,
      inventoryCaptureLimits).value
  incorrect = inventoryServices()
  incorrect[0].requests[0].length = RequestLength(2)
  incorrect[0].metadata.storageBytes = AccountStorageBytes(120)
  let badLinkage = captureStateInventory(inventoryManifest(fixture, incorrect), incorrect,
      inventoryCaptureLimits).value
  let profile = captureEconomicProfile(decodeParameters(economicTestWire()).value).value
  let overflow = captureEconomicProfile(decodeParameters(economicTestWire(0, 0, high(
      uint64))).value).value
  fail(1)
  assert default(StateAccountReviewPlan).reviewPlanInfo.error ==
      AccountReviewPlanError.Uninitialized
  assert executeAccountReview(default(StateAccountReviewPlan)).error ==
      AccountReviewExecutionError.InvalidPlan
  assert planAccountReview(source, default(StateEconomicProfile), reviewPlanTestLimits).error ==
      AccountReviewPlanError.InvalidProfile
  let invalid = planAccountReview(default(StateInventory), profile, reviewPlanTestLimits)
  assert invalid.error == AccountReviewPlanError.AdmissionFailure
  assert invalid.admissionFailure.error == AccountAuditPlanError.InvalidSource
  let footprint = planAccountReview(badFootprint, profile, reviewPlanTestLimits)
  assert footprint.error == AccountReviewPlanError.FootprintFailure
  assert footprint.footprintFailure.error == FootprintAuditError.ItemsMismatch
  for phase in 0..<4:
    var short = reviewPlanTestLimits
    case phase
    of 0: short.audit.planning = ElementLimit(0)
    of 1: short.directory.bytes = ByteLimit(0)
    of 2: short.supervision.bytes = ByteLimit(0)
    else: short.economics.bytes = ByteLimit(0)
    let refused = planAccountReview(source, profile, short)
    case phase
    of 0:
      assert refused.error == AccountReviewPlanError.AdmissionFailure
      assert refused.admissionFailure.error == AccountAuditPlanError.LimitExceeded
    of 1:
      assert refused.error == AccountReviewPlanError.DirectoryFailure
      assert refused.directoryFailure.error == ServiceDirectoryError.LimitExceeded
    of 2:
      assert refused.error == AccountReviewPlanError.SupervisionFailure
      assert refused.supervisionFailure.error == SupervisionTableError.LimitExceeded
    else:
      assert refused.error == AccountReviewPlanError.EconomicsFailure
      assert refused.economicsFailure.error == EconomicsTableError.LimitExceeded
    assert calls() == 0
  let arithmetic = planAccountReview(source, overflow, reviewPlanTestLimits)
  assert arithmetic.error == AccountReviewPlanError.EconomicsFailure
  assert arithmetic.economicsFailure.error == EconomicsTableError.ObservationFailure
  var limits = reviewPlanTestLimits
  let plan = planAccountReview(source, profile, limits).value
  let copied = plan
  limits.audit.content.preimages = ElementLimit(0)
  assert plan.reviewPlanInfo.value.economics.uncovered == 1
  assert copied.reviewPlanInfo.value.audit.contentBytes == 3
  assert calls() == 0
  let linkagePlan = planAccountReview(badLinkage, profile, reviewPlanTestLimits).value
  let linkage = executeAccountReview(linkagePlan)
  assert linkage.error == AccountReviewExecutionError.LinkageFailure
  assert linkage.linkageFailure.error == PreimageLinkageError.MissingRequest and calls() == 0
  let contentPlan = planAccountReview(badContent, profile, reviewPlanTestLimits).value
  fail(0)
  let content = executeAccountReview(contentPlan)
  assert content.error == AccountReviewExecutionError.ContentFailure
  assert content.contentFailure.error == PreimageContentError.HashMismatch and calls() == 1
  fail(1)
  let backend = executeAccountReview(plan)
  assert backend.error == AccountReviewExecutionError.ContentFailure
  assert backend.contentFailure.error == PreimageContentError.BackendFailure
  fail(0)
  let result = executeAccountReview(copied)
  assert result.error == AccountReviewExecutionError.None and calls() == 1
  assert sameStateInventory(result.value.reviewInventory.value, source)
  assert sameEconomicProfile(result.value.reviewEconomicProfile.value, profile)
  assert result.value.accountReviewInfo.value.economics.uncovered == 1
  for i in 0..<25: cycle(source, profile)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source, profile)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_account_review_plan", 1000, before, after)
  echo "state-account-review-plan: ok"
try:
  main()
except:
  quit(2) # Setup failure cannot qualify refusal or retired-owner evidence.
