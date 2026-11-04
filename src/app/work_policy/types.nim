# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Plain immutable bounded execution policy is independent of transport owners and startup file parsing.
import ../../jamnp-s/[work_submission, work_duty]
import ../../state/input_refinement
from ../../codec/bounded import ByteLimit, ElementLimit

type
  WorkDispatchPolicy* = object ## Explicit finite child policies never come from builder wire or inferred execution defaults.
    ready: bool
    admission: WorkSubmissionLimits
    execution: InputRefinementLimits
    duty: WorkDutyLimits
    timeout: int
func workDispatchPolicy*(admission: WorkSubmissionLimits, execution: InputRefinementLimits,
    duty: WorkDutyLimits, timeoutMs: range[1..120000] = 120000): WorkDispatchPolicy =
  ## Positive independent ceilings make activation intentional; children retain their own validation.
  ## Any supplied logging handle must outlive the host and its joined CPU work, as for the underlying execution policies.
  if uint64(execution.inputBytes) == 0 or uint64(duty.chapterBytes) == 0 or
      uint64(duty.disputeItems) == 0: return default(WorkDispatchPolicy)
  WorkDispatchPolicy(ready: true, admission: admission, execution: execution,
    duty: duty, timeout: timeoutMs)
func valid*(policy: WorkDispatchPolicy): bool =
  ## A default policy never enables native work selectors.
  policy.ready
func admissionLimits*(policy: WorkDispatchPolicy): WorkSubmissionLimits {.requires: policy.ready.} =
  ## Copy explicit child resource values; any logging borrow still needs its original owner to remain alive.
  policy.admission
func executionLimits*(policy: WorkDispatchPolicy): InputRefinementLimits {.requires: policy.ready.} =
  ## Execution ceilings cannot be rebound inside an already configured dispatcher.
  policy.execution
func dutyLimits*(policy: WorkDispatchPolicy): WorkDutyLimits {.requires: policy.ready.} =
  ## Canonical chapter/dispute ceilings are independent from execution limits.
  policy.duty
func timeoutMs*(policy: WorkDispatchPolicy): int {.requires: policy.ready.} =
  ## Construction proved a positive maximum of 120 seconds before any host clock arithmetic.
  policy.timeout
