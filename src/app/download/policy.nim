# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict complete v1 download policies preserve all nominal stage budgets without inferred defaults.
## Text/file decoding is bounded and atomic; successful plain policy snapshots own no callback resources.

import std/[strutils, syncio]
import "../../jamnp-s/block/download/loop" as block_download_loop

const
  DownloadPolicyBytes* = 65536 ## Hard startup input cap, independent of block and state resource policies.
  PolicyValues = 314
  PolicyHeader = "ragnarok-download-policy-v1"

type
  DownloadPolicyError* {.pure.} = enum ## Failure alternatives contain only a reason and bounded field diagnostic.
    Uninitialized, None, FileFailure, LimitExceeded, WrongVersion, InvalidLine,
    InvalidNumber, DuplicateField, MissingField, UnknownField, InvalidPolicy
  DownloadPolicyResult* = object ## Private successful alternative prevents partial/default policy extraction.
    case status: DownloadPolicyError
    of None:
      policy: DownloadLoopLimits
    else:
      field: string # A failed field name is diagnostic text, never a successful child policy.
  PolicyValue = object ## At most 314 bounded keys/numbers are retained before schema assignment.
    name: string
    number: uint64
    used: bool
  PolicyInput = object ## First-error state keeps generic leaf assignment atomic to the public boundary.
    values: seq[PolicyValue]
    error: DownloadPolicyError
    field: string

include ./policy/fields

func error*(outcome: DownloadPolicyResult): DownloadPolicyError =
  ## Defaults/refusals never authorize startup or policy extraction.
  outcome.status
func value*(outcome: DownloadPolicyResult): DownloadLoopLimits {.requires:
    outcome.status == DownloadPolicyError.None.} =
  ## Copy only a complete policy; stage semantics remain the existing stages' responsibility.
  outcome.policy
func fieldName*(outcome: DownloadPolicyResult): string {.requires:
    outcome.status != DownloadPolicyError.None.} =
  ## Explain only an actual failure without exposing partial numeric configuration.
  outcome.field
proc refused(reason: DownloadPolicyError, field = ""): DownloadPolicyResult =
  ## Construct a payload-free failed/default alternative.
  DownloadPolicyResult(status: reason, field: field)

proc decimal(text: string, number: var uint64): bool =
  ## Parse canonical uint64 decimal with pre-multiply bounds, never using zero as a failure sentinel.
  number = 0
  if text.len == 0 or text.len > 20 or (text.len > 1 and text[0] == '0'): return false
  for character in text:
    if character notin {'0'..'9'}: return false # Refuse signs, spaces, exponent forms and non-ASCII numerals.
    let digit = uint64(ord(character) - ord('0'))
    if number > (high(uint64) - digit) div 10: return false # Prove multiply and addition before wrapping is possible.
    number = number * 10 + digit
  true

proc readField[T](input: var PolicyInput, name: string, field: var T) {.untyped.} =
  ## The explicit schema instantiates only unsigned 32/64-bit scalars and their nominal wrappers.
  if input.error notin [DownloadPolicyError.None, DownloadPolicyError.MissingField]: return # Keep the first selected error and no public partial policy.
  for index in 0..<input.values.len:
    if input.values[index].name == name:
      let number = input.values[index].number
      when sizeof(T) == 4:
        if number > uint64(high(uint32)):
          input.error = DownloadPolicyError.InvalidNumber
          input.field = name
          return # Validate all narrow nominal conversions before casting.
      elif sizeof(T) != 8:
        {.error: "v1 policy leaves require reviewed unsigned 32/64-bit domains".}
      field = T(number)
      input.values[index].used = true
      return # One unique key supplies exactly one declared field.
  if input.error == DownloadPolicyError.None:
    input.error = DownloadPolicyError.MissingField
    input.field = name # Continue marking known fields so unknown-key diagnostics remain exact.

proc writeField[T](text: var string, name: string, field: T) {.untyped.} =
  ## Complete fixed schema bounds output extent; unsigned conversion preserves every supported domain width.
  text.add(name & "=" & $uint64(field) & "\n")

proc encodeDownloadPolicy*(policy: DownloadLoopLimits): string =
  ## Emit every explicit v1 value; this serializer provides no defaults or semantic-policy certification.
  result = PolicyHeader & "\n"
  policyFields(policy, result, writeField)

proc decodeDownloadPolicy*(text: string): DownloadPolicyResult =
  ## Bounded lexical preflight precedes private typed assignment; no failed parse publishes a prefix.
  if text.len > DownloadPolicyBytes: return refused(DownloadPolicyError.LimitExceeded)
  var input = PolicyInput(error: DownloadPolicyError.None, values: @[])
  var position, line = 0
  while position < text.len:
    let first = position
    while position < text.len and text[position] != '\n': inc position # Input cap bounds the complete scan.
    let extent = position - first
    if line == 0:
      if extent != PolicyHeader.len or text.substr(first, position - 1) !=
          PolicyHeader: return refused(DownloadPolicyError.WrongVersion)
    elif extent > 0 and text[first] != '#':
      if extent > 214: return refused(DownloadPolicyError.LimitExceeded) # Key <=192, '=', decimal <=20, all before copying.
      var separator = -1
      for index in first..<position:
        let character = text[index]
        if character == '=':
          if separator >= 0: return refused(DownloadPolicyError.InvalidLine)
          separator = index
        elif separator < 0 and character notin {'a'..'z', 'A'..'Z', '0'..'9', '.'}:
          return refused(DownloadPolicyError.InvalidLine) # Exact ASCII keys have no escapes or whitespace aliases.
      if separator <= first or separator - first > 192: return refused(
          DownloadPolicyError.InvalidLine)
      let name = text.substr(first, separator - 1)
      var number = 0'u64
      if separator + 1 == position or not decimal(text.substr(separator + 1, position - 1), number):
        return refused(DownloadPolicyError.InvalidNumber, name)
      for previous in input.values:
        if previous.name == name: return refused(DownloadPolicyError.DuplicateField,
            name) # Bound duplicate work before appending.
      if input.values.len == PolicyValues: return refused(DownloadPolicyError.LimitExceeded)
      input.values.add(PolicyValue(name: name, number: number, used: false))
    inc line
    if position < text.len: inc position # Skip only a proven present LF; final newline is optional.
  if line == 0: return refused(DownloadPolicyError.WrongVersion)
  var policy = default(DownloadLoopLimits)
  policyFields(policy, input, readField)
  if input.error notin [DownloadPolicyError.None, DownloadPolicyError.MissingField]:
    return refused(input.error, input.field) # A typed conversion failure precedes unrelated unset fields.
  for entry in input.values:
    if not entry.used: return refused(DownloadPolicyError.UnknownField,
        entry.name) # No extension/typo silently changes caller intent.
  if input.error != DownloadPolicyError.None: return refused(input.error, input.field)
  let schedule = policy.schedule
  let stream = policy.stream
  if uint64(schedule.peers) == 0 or uint64(schedule.peers) > 16 or schedule.attempts == 0 or
      uint64(schedule.retryDelay) == 0 or uint64(policy.input.blockBytes) == 0 or
      uint64(stream.readBytes) == 0 or uint64(stream.readBytes) > 4096 or
      uint64(stream.writeBytes) == 0 or uint64(stream.writeBytes) > 42 or
      uint64(stream.timeout) == 0 or uint64(policy.attemptTimeout) == 0:
    return refused(DownloadPolicyError.InvalidPolicy) # Reject unusable outer dispatcher bounds before any startup/native work.
  DownloadPolicyResult(status: DownloadPolicyError.None, policy: policy)

proc loadDownloadPolicy*(path: string): DownloadPolicyResult {.raises.} =
  ## Read at most cap+1 bytes through public string bulk-write APIs, including files that grow during the read.
  var file: File = nil
  if path.len == 0 or not open(file, path, fmRead): return refused(DownloadPolicyError.FileFailure)
  defer: close(file) # Every parse/size/I/O return ends the native file borrow.
  var text = newString(DownloadPolicyBytes + 1)
  let buffer = text.beginStore(text.len)
  let count = readBuffer(file, cast[pointer](buffer), text.len)
  text.endStore()
  if count < 0: return refused(DownloadPolicyError.FileFailure)
  if count > DownloadPolicyBytes: return refused(DownloadPolicyError.LimitExceeded)
  text.setLen(count)
  decodeDownloadPolicy(text)
