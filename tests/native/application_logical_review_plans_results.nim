# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen original logical review admission remains hash-free, immutable and reusable after content failures, source retirement and managed shutdown.
import std/[assertions, syncio, cmdline, envvars]
import std/posix/posix
import ../../src/app/services
import ../../src/app/logical/review as logical_review
import "../../src/app/current/block/input" as current_block_input
import ../../src/app/current/handoff as current_handoff
import ../../src/state/current/[review as current_review, state as current_state,
    globals as current_globals, profile as current_profile, logical as current_logical]
import ../../src/state/account/review as account_review
import ../../src/state/account/review/plan as account_review_plan
import ../../src/state/[economic_profile, inventory]
import ../../src/state/preimage/content as preimage_content
import ../../src/codec/bounded
import ../support/[collected_native_context, collected_supplied_context,
    collected_logical_services_context, managed_supplied_context, current_logical_review_context, arc_evidence]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Inject only a primitive failure after genuine native source qualification has finished.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Hash-free planning is observed independently of later content execution.
proc escapedPlan(): LogicalReviewPlan {.raises.} =
  ## All fixture/source activation aliases retire; only the immutable admitted plan retains original logical provenance.
  let fixture = collectedNativeFixture()
  let logical = suppliedNativeState(fixture)
  planLogicalReview(logical, logicalReviewTestLimits()).value
proc cycle(plan: LogicalReviewPlan) =
  ## Retire each fully executed content report before the next source-bound retry.
  let pair = executeLogicalReview(plan).value
  assert pair.logicalCurrentReview.value.currentAccountReview.value.accountReviewInfo.value.invariants.content.preimages == 6
proc main() {.raises.} =
  ## A strict negative mode can fail only at the new selected preparation-reason guard.
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  if mode == "preparation":
    let result = default(LogicalReviewResult[LogicalReviewPlan])
    discard result.preparationFailure
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Strict controls run at the repository root; unit fixture bindings stay explicit.
  let fixture = collectedNativeFixture()
  var owner = default(Services)
  var input = default(CurrentBlockInput)
  var path = "application-logical-review-plans-chain.json"
  discard startLogicalServices(owner, fixture.fixture, path)
  defer:
    owner.close()
    discard posix.unlink(path.toCString())
  let logical = collectManagedSupplied(owner, input, fixture.fixture)
  var limits = logicalReviewTestLimits()
  fail(1)
  let prepared = owner.planLogicalReview(logical, limits)
  assert prepared.error == LogicalReviewError.None and calls() == 0
  let plan = prepared.value
  let copied = plan
  assert plan.logicalReviewPlanInfo.value.audit.contentBytes > 0
  assert plan.logicalReviewPlanInfo.value.directory.services == 2
  limits.audit.planning = ElementLimit(0)
  let refused = owner.planLogicalReview(logical, limits)
  assert refused.error == LogicalReviewError.PreparationFailure
  assert refused.preparationFailure.error == CurrentReviewError.PreparationFailure and calls() == 0
  let failed = owner.executeLogicalReview(plan)
  assert failed.error == LogicalReviewError.ReviewFailure
  assert failed.reviewFailure.error == CurrentReviewError.ExecutionFailure
  assert failed.reviewFailure.executionFailure.contentFailure.error ==
      PreimageContentError.BackendFailure
  fail(0)
  let pair = owner.executeLogicalReview(copied).value
  let report = pair.logicalCurrentReview.value.currentAccountReview.value
  let original = logical.currentLogicalSource.value
  let rates = captureEconomicProfile(original.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedParameters.value).value
  assert sameStateInventory(report.reviewInventory.value, original.currentStateInventory.value)
  assert sameEconomicProfile(report.reviewEconomicProfile.value, rates)
  assert sameStateInventory(plan.logicalReviewPlanSource.value.currentLogicalSource.value.currentStateInventory.value,
    original.currentStateInventory.value)
  let empty = default(LogicalReviewPlan)
  assert executeLogicalReview(empty).error == LogicalReviewError.InvalidPlan
  assert empty.logicalReviewPlanSource.error == LogicalReviewError.InvalidPlan
  assert empty.logicalReviewPlanInfo.error == LogicalReviewError.InvalidPlan
  let invalid = default(CurrentReviewPlan)
  assert executeCurrentReview(invalid).error == CurrentReviewError.InvalidPlan
  assert invalid.currentReviewPlanInfo.error == CurrentReviewError.InvalidPlan
  assert owner.enqueueCurrentAccumulation(logical.currentLogicalUpdate.value) ==
      CurrentHandoffAdmission.None
  owner.tick(0)
  assert owner.takeCurrentAccumulation.error == CurrentHandoffError.None
  owner.close()
  assert owner.executeLogicalReview(plan).error == LogicalReviewError.None
  let escaped = escapedPlan()
  for i in 0..<25: cycle(escaped)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(escaped)
  let after = getOccupiedMem()
  assert before == after and calls() > 0
  recordArcRelease("application_logical_review_plans", 1000, before, after)
  echo "application-logical-review-plans: ok"
try:
  main()
except:
  quit(2) # Ordinary setup and content failures cannot impersonate strict assertion rejection.
