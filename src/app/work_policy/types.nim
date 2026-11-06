# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Plain immutable bounded execution policy is independent of transport owners and startup file parsing.
import ../../jamnp-s/[work_submission, work_duty]
import ../../state/input_refinement
from ../../codec/bounded import ByteLimit, ElementLimit

type
  WorkPolicyError* {.pure.} = enum ## Only complete None success carries activation policy; every failure has a bounded field diagnostic.
    Uninitialized, None, FileFailure, LimitExceeded, WrongVersion, InvalidLine,
    InvalidNumber, InvalidBackend, DuplicateField, MissingField, UnknownField, InvalidPolicy
  WorkAcquisitionPolicy* = object ## Explicit local network ceilings are independent from source-bearing execution policy.
    ready: bool
    attempts: int
    timeout: int
    reply: ByteLimit
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

func workAcquisitionPolicy*(attempts: range[1..1023], timeoutMs: range[1..120000],
    replyBytes: ByteLimit): WorkAcquisitionPolicy =
  ## No inferred defaults enable fetching; CE148 replies must fit the existing independent sixteen-MiB transport ceiling.
  if uint64(replyBytes) < 8 or uint64(replyBytes) > 16'u64*1024*1024: return default(WorkAcquisitionPolicy)
  WorkAcquisitionPolicy(ready: true, attempts: attempts, timeout: timeoutMs, reply: replyBytes)
func valid*(policy: WorkAcquisitionPolicy): bool =
  ## Default construction cannot activate CE133 network acquisition.
  policy.ready
func attempts*(policy: WorkAcquisitionPolicy): int {.requires: policy.ready.} =
  ## Construction proves a finite protocol-population-sized peer attempt budget.
  policy.attempts
func timeoutMs*(policy: WorkAcquisitionPolicy): int {.requires: policy.ready.} =
  ## Each request receives its own explicit positive monotonic deadline inside the overall work deadline.
  policy.timeout
func replyBytes*(policy: WorkAcquisitionPolicy): ByteLimit {.requires: policy.ready.} =
  ## The caller selects a bounded retained-wire ceiling, never the remote peer.
  policy.reply
