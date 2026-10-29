# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current review preserves original full parameters, exact inventory and stage/resource reasons on real signed successors.
# @@Verification={"arc": "state_current_review_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_checkpoint_context, current_state_context,
    accumulation_current_chain_context, account_review_plan_context, arc_evidence]
import ../../../src/state/current/[review as current_review, state as current_state,
    globals as current_globals, profile as current_profile]
import ../../../src/state/inventory
import ../../../src/state/account/review as account_review
import ../../../src/state/economic_profile
import ../../../src/state/account/review/plan as account_review_plan
import ../../../src/codec/[bounded, report_owned]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Disable hashing only after complete source qualification.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Empty authored child namespaces need no content hashes during review.
proc verify(source: CurrentStateSerialization) =
  ## The reviewed profile must preserve all original parameters, not just the three selected rates.
  let original = captureEconomicProfile(source.currentStateGlobals.value.qualifiedCurrentProfile.value.derivedParameters.value).value
  fail(1)
  let checked = reviewCurrentState(source, reviewPlanTestLimits)
  assert checked.error == CurrentReviewError.None
  let review = checked.value.currentAccountReview.value
  assert sameStateInventory(review.reviewInventory.value, source.currentStateInventory.value)
  assert sameStateInventory(checked.value.reviewedCurrentSource.value.currentStateInventory.value,
      source.currentStateInventory.value)
  assert sameEconomicProfile(review.reviewEconomicProfile.value, original)
  let info = review.accountReviewInfo.value
  assert info.invariants.footprints.services == 2 and info.invariants.content.preimages == 0
  assert info.economics.services == 2 and info.economics.covered+info.economics.uncovered == 2
  for phase in 0..<4:
    var short = reviewPlanTestLimits
    case phase
    of 0: short.audit.planning = ElementLimit(0)
    of 1: short.directory.services = ElementLimit(1)
    of 2: short.supervision.services = ElementLimit(1)
    else: short.economics.services = ElementLimit(1)
    let refused = reviewCurrentState(source, short)
    assert refused.error == CurrentReviewError.PreparationFailure
    let expected = [AccountReviewPlanError.AdmissionFailure,
        AccountReviewPlanError.DirectoryFailure, AccountReviewPlanError.SupervisionFailure,
        AccountReviewPlanError.EconomicsFailure]
    assert refused.preparationFailure.error == expected[phase]
  assert calls() == 0
  fail(0)
proc cycle(source: CurrentStateSerialization) =
  ## Retire all reports and original owner aliases after one complete targeted review.
  let review = reviewCurrentState(source, reviewPlanTestLimits).value
  assert review.currentAccountReview.value.accountReviewInfo.value.economics.services == 2
proc main() {.raises.} =
  ## Genuine ordinary/disputed/ticketed/epoch inputs qualify before observer resets and ARC measurements.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let source = currentQualifiedState(currentCheckpointPrepared(currentChainFixture(base,
      available = true, completeState = true)))
  verify(source)
  verify(currentQualifiedState(currentCheckpointPrepared(currentChainFixture(base, available = true,
      disputed = true, completeState = true))))
  verify(currentQualifiedState(currentCheckpointPrepared(currentChainFixture(base, available = true,
      ticket = true, completeState = true))))
  verify(currentQualifiedState(currentCheckpointPrepared(currentChainFixture(base, available = true,
      rotated = true, completeState = true))))
  assert reviewCurrentState(default(CurrentStateSerialization), reviewPlanTestLimits).error ==
      CurrentReviewError.InvalidState
  assert default(ReviewedCurrentState).reviewedCurrentSource.error ==
      CurrentReviewError.Uninitialized
  assert default(ReviewedCurrentState).currentAccountReview.error ==
      CurrentReviewError.Uninitialized
  fail(1)
  for i in 0..<25: cycle(source)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes and calls() == 0
  recordArcRelease("state_current_review", 1000, before, finalBytes)
  fail(0)
  echo "state-current-review: ok"
try:
  main()
except:
  quit(2) # Setup/authentication failures cannot qualify downstream review evidence.
