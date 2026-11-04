# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict whole-policy startup parsing preserves typed independent work limits and explicit PVM engines.
import std/[strutils, syncio]
import ./work_policy/types
import ../jamnp-s/[work_submission, work_duty]
import ../state/input_refinement
import ../pvm/backend
import ../lib/logging

const
  WorkPolicyBytes* = 32768 ## Independent startup input ceiling includes comments and final newline.
  WorkPolicyHeader = "ragnarok-work-policy-v1"
  WorkPolicyFields = 86    ## Eighty-five declared fields plus one bounded unknown-key diagnostic.
type
  WorkPolicyError* {.pure.} = enum ## Only complete None success carries activation policy; every failure has a bounded field diagnostic.
    Uninitialized, None, FileFailure, LimitExceeded, WrongVersion, InvalidLine,
    InvalidNumber, InvalidBackend, DuplicateField, MissingField, UnknownField, InvalidPolicy
  WorkPolicyResult* = object ## Private alternatives prevent a failed file from exposing partially configured execution limits.
    case status: WorkPolicyError
    of None: policy: WorkDispatchPolicy
    else: field: string
  WorkPolicyValues = object ## Plain local inputs grant no execution or source capability; host logging is assigned only after parsing.
    admission: WorkSubmissionLimits
    execution: InputRefinementLimits
    duty: WorkDutyLimits
    timeoutMs: uint64
  PolicyValue = object ## Extents and fixed key count are proved before appending bounded owned strings.
    name, text: string
    used: bool
  PolicyInput = object ## First selected conversion/missing error remains private through complete schema visitation.
    values: seq[PolicyValue]
    error: WorkPolicyError
    field: string
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
proc decimal(text: string, number: var uint64): bool =
  ## Canonical unsigned decimal accepts no signs, padding, spaces or wrapping multiplication.
  number = 0
  if text.len == 0 or text.len > 20: return false
  if text.len > 1 and text[0] == '0': return false
  for character in text:
    if character notin {'0'..'9'}: return false
    let digit = uint64(ord(character)-ord('0'))
    if number > (high(uint64)-digit) div 10: return false
    number = number*10+digit
  true
proc readField[T](input: var PolicyInput, name: string, field: var T) {.untyped.} =
  ## Only reviewed nominal unsigned widths and the closed backend enum can instantiate this schema.
  if input.error notin [WorkPolicyError.None, WorkPolicyError.MissingField]: return
  for index in 0..<input.values.len:
    if input.values[index].name == name:
      let text = input.values[index].text
      when T is PvmBackend:
        # A named engine is required; enum ordinals cannot silently change meaning after an engine is removed.
        if not parsePvmBackend(text, field):
          input.error = WorkPolicyError.InvalidBackend
          input.field = name
          return
      else:
        # Prove full uint64 parsing and any narrower nominal extent before assigning.
        var number = 0'u64
        if not decimal(text, number):
          input.error = WorkPolicyError.InvalidNumber
          input.field = name
          return
        when sizeof(T) == 4:
          if number > uint64(high(uint32)):
            input.error = WorkPolicyError.InvalidNumber
            input.field = name
            return
        elif sizeof(T) != 8:
          {.error: "work policy leaves require reviewed unsigned 32/64-bit domains".}
        field = T(number)
      input.values[index].used = true
      return
  if input.error == WorkPolicyError.None:
    input.error = WorkPolicyError.MissingField
    input.field = name
proc writeField[T](text: var string, name: string, field: T) {.untyped.} =
  ## Emit every declared value without synthesizing execution budgets or serializing logging pointers.
  when T is PvmBackend: text.add(name & "=" & $field & "\n")
  else: text.add(name & "=" & $uint64(field) & "\n")
proc encodeWorkPolicy*(admission: WorkSubmissionLimits, execution: InputRefinementLimits,
    duty: WorkDutyLimits, timeoutMs: range[1..120000] = 120000): string =
  ## Serialize explicit caller inputs; encoding alone does not certify usable stage semantics.
  let policy = WorkPolicyValues(admission: admission, execution: execution, duty: duty,
    timeoutMs: uint64(timeoutMs))
  result = WorkPolicyHeader & "\n"
  workPolicyFields(policy, result, writeField)
proc decodeWorkPolicy*(text: string, logging = default(LogWriter)): WorkPolicyResult =
  ## Whole-input lexical checks precede typed assignment and activation; no failed path exposes a partial policy.
  if text.len > WorkPolicyBytes: return refused(WorkPolicyError.LimitExceeded)
  var input = PolicyInput(values: @[], error: WorkPolicyError.None)
  var position, line = 0
  while position < text.len:
    let first = position
    while position < text.len and text[position] != '\n': inc position
    let extent = position-first
    if line == 0:
      if extent != WorkPolicyHeader.len: return refused(WorkPolicyError.WrongVersion)
      if text.substr(first, position-1) != WorkPolicyHeader: return refused(
          WorkPolicyError.WrongVersion)
    elif extent > 0 and text[first] != '#':
      # A complete line is bounded before copying either key or named/numeric value.
      if extent > 257: return refused(WorkPolicyError.LimitExceeded)
      var separator = -1
      for index in first..<position:
        let character = text[index]
        if character == '=':
          if separator >= 0: return refused(WorkPolicyError.InvalidLine)
          separator = index
        elif separator < 0 and character notin {'a'..'z', 'A'..'Z', '0'..'9', '.'}:
          return refused(WorkPolicyError.InvalidLine)
      if separator <= first or separator-first > 192 or separator+1 == position:
        return refused(WorkPolicyError.InvalidLine)
      if position-separator-1 > 64: return refused(WorkPolicyError.LimitExceeded)
      let name = text.substr(first, separator-1)
      for previous in input.values:
        if previous.name == name: return refused(WorkPolicyError.DuplicateField, name)
      if input.values.len == WorkPolicyFields: return refused(WorkPolicyError.LimitExceeded)
      input.values.add(PolicyValue(name: name, text: text.substr(separator+1, position-1)))
    inc line
    if position < text.len: inc position
  if line == 0: return refused(WorkPolicyError.WrongVersion)
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
