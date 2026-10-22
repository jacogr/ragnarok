# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Same-source review joins preserve targeted validity and economic observation scopes without accepting equal-root substitutions.
# @@Verification={"arc": "state_account_review_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[state_inventory_context, account_review_context, arc_evidence]
import ../../../src/state/[account_review, account_invariants, supervision_table, economics_table,
    inventory, economic_profile]
import ../../../src/codec/state_accounts
include ../../native/composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse hashing after constructing real component evidence.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Review joining is fixed retained-owner work without rehashing.
proc cycle(source: AccountReviewTestEvidence) =
  ## Retire one complete review and component/source extractions each cycle.
  let review = joinAccountReview(source.invariants, source.supervision, source.economics).value
  assert review.accountReviewInfo.value.economics.uncovered == 1
proc main() {.raises.} =
  ## Equal complete sources intentionally produce different capture owners while undercoverage remains a valid observation.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var services = inventoryServices()
  services[0].metadata.balance = AccountBalance(100)
  let source = accountReviewEvidence(fixture, services)
  let other = accountReviewEvidence(fixture, services)
  fail(1)
  let result = joinAccountReview(source.invariants, source.supervision, source.economics)
  assert result.error == AccountReviewError.None
  let review = result.value
  assert review.accountReviewInfo.value.invariants.content.bytes == 3
  assert review.accountReviewInfo.value.supervision.services == 2
  assert review.accountReviewInfo.value.economics.uncovered == 1
  assert sameStateInventory(review.reviewInventory.value,
      source.invariants.accountInvariantInventory.value)
  assert review.reviewInvariants.value.accountInvariantInfo.value.content.preimages == 1
  assert review.reviewSupervision.value.supervisionTableInfo.value.services == 2
  assert review.reviewEconomics.value.economicTableInfo.value.covered == 1
  assert sameEconomicProfile(review.reviewEconomicProfile.value,
      source.economics.economicTableProfile.value)
  assert joinAccountReview(default(CheckedAccountInvariants), source.supervision,
      source.economics).error == AccountReviewError.InvalidInvariants
  assert joinAccountReview(source.invariants, default(StateSupervisionTable),
      source.economics).error == AccountReviewError.InvalidSupervision
  assert joinAccountReview(source.invariants, source.supervision, default(
      StateEconomicsTable)).error == AccountReviewError.InvalidEconomics
  assert joinAccountReview(source.invariants, other.supervision, source.economics).error ==
      AccountReviewError.SourceMismatch
  assert joinAccountReview(source.invariants, source.supervision, other.economics).error ==
      AccountReviewError.SourceMismatch
  assert default(StateAccountReview).accountReviewInfo.error == AccountReviewError.Uninitialized
  assert default(StateAccountReview).reviewInventory.error == AccountReviewError.Uninitialized
  assert default(StateAccountReview).reviewEconomicProfile.error == AccountReviewError.Uninitialized
  assert default(StateAccountReview).reviewInvariants.error == AccountReviewError.Uninitialized
  assert default(StateAccountReview).reviewSupervision.error == AccountReviewError.Uninitialized
  assert default(StateAccountReview).reviewEconomics.error == AccountReviewError.Uninitialized
  var copied = review.accountReviewInfo.value
  copied.economics.uncovered = 0
  assert review.accountReviewInfo.value.economics.uncovered == 1
  assert calls() == 0
  for i in 0..<25: cycle(source) # Warm all composite retained-owner copies before measuring retirements.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source) # Component owner graphs do not accumulate through repeated review/extraction.
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_account_review", 1000, before, finalBytes)
  fail(0)
  echo "state-account-review: ok"
try:
  main()
except:
  quit(2) # Fixture errors cannot qualify source-bound review evidence.
