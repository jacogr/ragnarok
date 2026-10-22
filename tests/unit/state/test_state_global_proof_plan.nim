# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Generic plans normalize requested identities without granting root or complete-state authority.
import std/[assertions, syncio]
import ../../../src/state/proof_plan
import ../../../src/codec/[bounded, state_layout]
proc same(left, right: StateKey): bool =
  ## Compare fixed copied identities independently of internal plan layout.
  array[31, byte](left) == array[31, byte](right)
proc main() =
  ## Check unordered capture, caller independence, exact union budgets and default/empty distinction.
  let first = chapterKey(StateChapter(1))
  let second = chapterKey(StateChapter(2))
  let third = chapterKey(StateChapter(3))
  var input = @[third, first, second]
  let captured = captureStateProofPlan(input, ElementLimit(3))
  assert captured.error == ProofPlanError.None
  let plan = captured.value
  input[0] = chapterKey(StateChapter(15))
  assert plan.valid and plan.len == 3
  assert same(plan.keyAt(0).value, first) and same(plan.keyAt(2).value, third)
  var count = 0
  for key in plan:
    assert same(key, plan.keyAt(count).value)
    inc count
  assert count == 3
  assert plan.keyAt(-1).error == ProofPlanError.InvalidIndex
  assert plan.keyAt(3).error == ProofPlanError.InvalidIndex
  assert captureStateProofPlan([first, first], ElementLimit(2)).error == ProofPlanError.InvalidInput
  assert captureStateProofPlan([first, second], ElementLimit(1)).error ==
      ProofPlanError.LimitExceeded
  let right = captureStateProofPlan([third, second], ElementLimit(2)).value
  let left = captureStateProofPlan([first, second], ElementLimit(2)).value
  assert mergeStateProofPlans(left, right, ElementLimit(2)).error == ProofPlanError.LimitExceeded
  let merged = mergeStateProofPlans(left, right, ElementLimit(3)).value
  assert merged.len == 3 and same(merged.keyAt(2).value, third)
  assert mergeStateProofPlans(left, left, ElementLimit(2)).value.len == 2
  let missing = default(StateProofPlan)
  assert not missing.valid and missing.len == 0
  assert missing.keyAt(0).error == ProofPlanError.Uninitialized
  assert mergeStateProofPlans(missing, left, ElementLimit(4)).error == ProofPlanError.Uninitialized
  let empty = captureStateProofPlan([], ElementLimit(0)).value
  assert empty.valid and empty.len == 0
  assert mergeStateProofPlans(empty, left, ElementLimit(2)).value.len == 2
  echo "state-global-proof-plan: ok"
main()
