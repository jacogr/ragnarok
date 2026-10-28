# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Existing targeted review composes with genuine refreshed logical provenance without cross-capture joins or replacing original Parameters.
# @@Verification={"arc":"state_current_logical_review_composition_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_current_repeated_logical_context
import ../../support/state_current_namespace_refresh_context
import ../../support/state_current_logical_review_context
import ../../support/testing_arc_evidence
import ../../../src/state/current_logical_refresh as state_current_logical_refresh
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/current_state as state_current_state
import ../../../src/state/current_review as state_current_review
import ../../../src/state/current_globals as state_current_globals
import ../../../src/state/current_profile as state_current_profile
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../../src/state/inventory as state_inventory
import ../../../src/state/manifest as state_manifest
import ../../../src/state/store as state_store
import ../../../src/state/account_review_plan as state_account_review_plan
import ../../../src/state/account_review as state_account_review
import ../../../src/state/account_audit_plan as state_account_audit_plan
import ../../../src/state/account_audit as state_account_audit
import ../../../src/state/account_invariants as state_account_invariants
import ../../../src/state/preimage_content as state_preimage_content
import ../../../src/state/economic_profile as state_economic_profile
import ../../../src/state/economics_table as state_economics_table
import ../../../src/chain/parameters as chain_parameters
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Actual source/full refresh completes before isolated review planning, predicate hashing and joins.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Resource refusals and exact-owner joins must precede all content work.
proc cycle(logical: CurrentLogicalState) =
  ## Retire only the existing review reports/predicates and same-current source aliases; no new public certificate or validity rule is introduced.
  let pair = composeLogicalReview(logical)
  assert pair.reviewed.currentAccountReview.value.accountReviewInfo.value.invariants.content.preimages == 6
proc main() {.raises.} =
  ## A real completed source advances to its next signed/current child before targeted review is composed at the host-idle handoff scope.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let fixture = repeatedLogicalFixture(decodeOwnedReport(bytes, 2).value)
  let logical = executeCurrentLogicalRefresh(namespaceRefreshStages(fixture.logical,
      fixture.next).complete).value
  let source = logical.currentLogicalSource.value
  let first = source.currentStateInventory.value
  let second = logical.currentLogicalInventory.value.suppliedInventory.value
  assert not sameStateInventory(first, second)
  assert sameStateSnapshot(first.inventorySource.value.manifestSource.value,
      second.inventorySource.value.manifestSource.value)
  fail(1)
  for phase in 0..<4:
    var limits = logicalReviewTestLimits()
    case phase
    of 0: limits.audit.planning = ElementLimit(0) # Audit work refusal precedes any content primitive.
    of 1: limits.directory.services = ElementLimit(1) # Complete original metadata directory needs both services.
    of 2: limits.supervision.services = ElementLimit(
        1) # Supervisor observations retain their original complete-source policy.
    else: limits.economics.services = ElementLimit(
        1) # Economic undercoverage is not substituted for resource admission.
    let refused = reviewCurrentState(source, limits)
    let expected = [AccountReviewPlanError.AdmissionFailure,
        AccountReviewPlanError.DirectoryFailure, AccountReviewPlanError.SupervisionFailure,
        AccountReviewPlanError.EconomicsFailure]
    assert refused.error == CurrentReviewError.PreparationFailure and
        refused.preparationFailure.error == expected[phase]
  assert calls() == 0
  let backend = reviewCurrentState(source, logicalReviewTestLimits())
  assert backend.error == CurrentReviewError.ExecutionFailure and
      backend.executionFailure.contentFailure.error == PreimageContentError.BackendFailure
  assert calls() == 1
  fail(0)
  let pair = composeLogicalReview(logical)
  assert calls() == 6
  let reviewed = pair.reviewed.currentAccountReview.value
  assert sameStateInventory(reviewed.reviewInventory.value, first)
  assert not sameStateInventory(reviewed.reviewInventory.value, second)
  let original = source.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedParameters.value
  assert sameEconomicProfile(reviewed.reviewEconomicProfile.value, captureEconomicProfile(
      original).value)
  let retained = pair.reviewed.reviewedCurrentSource.value.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedUpdate.value
  assert sameStateSnapshot(retained.currentUpdateState, fixture.next.currentUpdateState)
  assert sameChainView(retained.currentUpdateView, fixture.next.currentUpdateView)
  let alternativeAudit = executeAccountAudit(planAccountAudit(second, logicalReviewTestLimits().audit).value).value
  fail(1)
  let mixed = joinAccountReview(alternativeAudit, reviewed.reviewSupervision.value,
      reviewed.reviewEconomics.value)
  assert mixed.error == AccountReviewError.SourceMismatch and calls() ==
      0 # Equal physical roots cannot turn compact2 predicates into compact1 evidence.
  fail(0)
  var wire = original.encodeParameters
  wire[8] = 1 # A separate explicit byte price demonstrates undercoverage as observation, never replacement of original zero-deposit execution parameters.
  let alternative = captureEconomicProfile(decodeParameters(wire).value).value
  let observed = executeAccountReview(planAccountReview(first, alternative, logicalReviewTestLimits()).value).value
  assert observed.accountReviewInfo.value.economics.uncovered == 1
  assert reviewed.accountReviewInfo.value.economics.covered == 2 and
      reviewed.accountReviewInfo.value.economics.uncovered == 0
  assert not sameEconomicProfile(observed.reviewEconomicProfile.value,
      reviewed.reviewEconomicProfile.value)
  for i in 0..<25: cycle(logical)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(logical)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_current_logical_review_composition", 1000, before, finalBytes)
  echo "state-current-logical-review-composition: ok"
try:
  main()
except:
  quit(2) # Genuine current provenance, original parameters and exact same-inventory predicate scopes must remain distinct and consistent.
