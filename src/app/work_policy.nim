# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict whole-policy startup parsing preserves typed independent work limits and explicit PVM engines.

import std/[strutils, syncio]
import ./work_policy/types
export WorkPolicyError
import ../jamnp-s/[work_submission, work_duty]
import ../state/input_refinement
import ../pvm/backend
import ../lib/logging

const
  WorkPolicyBytes* = 32768 ## Independent startup input ceiling includes comments and final newline.
  WorkPolicyHeader = "ragnarok-work-policy-v1"
  WorkPolicyFields = 86    ## Eighty-five declared fields plus one bounded unknown-key diagnostic.

type
  WorkPolicyResult* = object ## Private alternatives prevent a failed file from exposing partially configured execution limits.
    case status: WorkPolicyError
    of None: policy: WorkDispatchPolicy
    else: field: string
  WorkPolicyValues = object ## Plain local inputs grant no execution or source capability; host logging is assigned only after parsing.
    admission: WorkSubmissionLimits
    execution: InputRefinementLimits
    duty: WorkDutyLimits
    timeoutMs: uint64
include ./work_policy/parser
include ./work_policy/fields

func error*(outcome: WorkPolicyResult): WorkPolicyError =
  ## Inspect failure without selecting activation data.
  outcome.status

func value*(outcome: WorkPolicyResult): WorkDispatchPolicy {.requires: outcome.status ==
    WorkPolicyError.None.} =
  ## Only a completely parsed explicit file can activate the dispatcher.
  outcome.policy

func fieldName*(outcome: WorkPolicyResult): string {.requires: outcome.status !=
    WorkPolicyError.None.} =
  ## Bounded diagnostics identify the genuine failed field, never secret file contents.
  outcome.field

func refused(reason: WorkPolicyError, field = ""): WorkPolicyResult =
  ## Failed/default alternatives contain neither a policy nor a successful parsed prefix.
  WorkPolicyResult(status: reason, field: field)

proc encodeWorkPolicy*(admission: WorkSubmissionLimits, execution: InputRefinementLimits,
    duty: WorkDutyLimits, timeoutMs: range[1..120000] = 120000): string =
  ## Serialize explicit caller inputs; encoding alone does not certify usable stage semantics.
  let policy = WorkPolicyValues(admission: admission, execution: execution, duty: duty,
    timeoutMs: uint64(timeoutMs))
  result = WorkPolicyHeader & "\n"
  workPolicyFields(policy, result, writeField)

proc decodeWorkPolicy*(text: string, logging = default(LogWriter)): WorkPolicyResult =
  ## Whole-input lexical checks precede typed assignment and activation; no failed path exposes a partial policy.
  var input = parsePolicyInput(text, WorkPolicyHeader, WorkPolicyBytes, WorkPolicyFields)
  if input.error != WorkPolicyError.None: return refused(input.error, input.field)
  var values = default(WorkPolicyValues)
  workPolicyFields(values, input, readField)
  if input.error notin [WorkPolicyError.None, WorkPolicyError.MissingField]:
    return refused(input.error, input.field)
  for entry in input.values:
    if not entry.used: return refused(WorkPolicyError.UnknownField, entry.name)
  if input.error != WorkPolicyError.None: return refused(input.error, input.field)
  let timeout = values.timeoutMs
  if timeout < 1 or timeout > 120000: return refused(WorkPolicyError.InvalidPolicy, "timeoutMs")
  values.admission.authorization.logging = logging
  values.execution.authorization.logging = logging
  values.execution.refinement.refinement.invocation.logging = logging
  let policy = workDispatchPolicy(values.admission, values.execution, values.duty,
    range[1..120000](int(timeout)))
  if not policy.valid: return refused(WorkPolicyError.InvalidPolicy)
  WorkPolicyResult(status: WorkPolicyError.None, policy: policy)

proc loadWorkPolicy*(path: string, logging = default(LogWriter)): WorkPolicyResult {.raises.} =
  ## Read cap+1 bytes, including growth during reads, and close before any parsed policy can escape.
  try:
    var file: File = nil
    if path.len == 0 or not open(file, path, fmRead): return refused(WorkPolicyError.FileFailure)
    defer: close(file)
    var text = newString(WorkPolicyBytes+1)
    let buffer = text.beginStore(text.len)
    let count = readBuffer(file, cast[pointer](buffer), text.len)
    text.endStore()
    if count < 0: return refused(WorkPolicyError.FileFailure)
    if count > WorkPolicyBytes: return refused(WorkPolicyError.LimitExceeded)
    text.setLen(count)
    return decodeWorkPolicy(text, logging)
  except:
    return refused(WorkPolicyError.FileFailure) # Local I/O exceptions never select a partial activation policy.
