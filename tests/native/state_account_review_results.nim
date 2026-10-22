# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic review payload guards retain a real same-source component join as the positive control.
import std/[assertions, cmdline, syncio]
import ../support/[state_inventory_context, account_review_context]
import ../../src/state/[account_review, account_invariants, supervision_table, economics_table]
include composition_fixture
proc extract(outcome: AccountReviewResult[StateAccountReview]): StateAccountReview {.noinline.} =
  ## Defaults and failed joins grant no composite source-bearing review.
  outcome.value
case paramStr(1)
of "default": discard extract(default(AccountReviewResult[StateAccountReview])) # No default review.
of "invalid": discard extract(joinAccountReview(default(CheckedAccountInvariants), default(
    StateSupervisionTable), default(StateEconomicsTable))) # Actual missing evidence.
of "ok":
  let source = accountReviewEvidence(compositionFixture(paramStr(2)), inventoryServices())
  let review = extract(joinAccountReview(source.invariants, source.supervision, source.economics))
  assert review.accountReviewInfo.value.invariants.content.bytes == 3
  echo "state-account-review-results: ok"
else: quit(2) # Unknown selectors cannot pass controls.
