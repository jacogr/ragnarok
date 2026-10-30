# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict complete current v1 download policies preserve all nominal stage budgets without inferred defaults.
## Text/file decoding is bounded and atomic; successful plain policy snapshots own no callback resources.

import std/[strutils, syncio]
import "../../../jamnp-s/current/block/download/loop" as current_block_download_loop
import ../logical/startup as current_logical_startup
import ../../candidate
import ../../../codec/bounded
import ../../../state/logical_continuation
import ../../../state/accumulation/[effects as accumulation_effects,
    storage_history as accumulation_storage_history]
import ../../../state/request_identity_history
import ../../../state/service/identity_history as service_identity_history

const
  CurrentDownloadPolicyBytes* = 65536 ## Hard startup input cap, independent of block and state resource policies.
  PolicyValues = 389
  PolicyHeader = "ragnarok-current-download-policy-v1"
  LogicalPolicyHeader = "ragnarok-current-logical-policy-v1"
  NamespacePolicyHeader = "ragnarok-current-namespace-policy-v1"

type
  CurrentDownloadPolicyError* {.pure.} = enum ## Failure alternatives contain only a reason and bounded field diagnostic.
    Uninitialized, None, FileFailure, LimitExceeded, WrongVersion, InvalidLine,
    InvalidNumber, DuplicateField, MissingField, UnknownField, InvalidPolicy
  CurrentDownloadPolicyResult* = object ## Private successful alternative prevents partial/default policy extraction.
    case status: CurrentDownloadPolicyError
    of None:
      policy: CurrentDownloadLoopLimits
    else:
      field: string # A failed field name is diagnostic text, never a successful child policy.
  CurrentLogicalPolicyResult* = object ## Complete explicit logical resource policy is extracted only after strict whole-schema parsing.
    case status: CurrentDownloadPolicyError
    of None:
      policy: CurrentLogicalStartupLimits
    else:
      field: string
  NamespaceHostLimits* = object ## Only new raw-storage/request identity retention policies supplement the existing full execution configuration.
    storage*: AccumulationStorageFactLimits
    requests*: ElementLimit
  CurrentNamespacePolicy* = object ## Explicit continuation and producer capture are independent from startup source qualification and existing execution/store policies.
    continuation*: LogicalContinuationLimits
    initial*, round*: NamespaceHostLimits
    storage*: StorageHistoryLimits
    requests*: RequestIdentityHistoryLimits
    services*: ServiceIdentityHistoryLimits
  CurrentNamespacePolicyResult* = object ## Whole-schema failure exposes only the bounded offending field, never partial numeric policies.
    case status: CurrentDownloadPolicyError
    of None: policy: CurrentNamespacePolicy
    else: field: string
  PolicyValue = object ## At most 389 bounded keys/numbers are retained before schema assignment.
    name: string
    number: uint64
    used: bool
  PolicyInput = object ## First-error state keeps generic leaf assignment atomic to the public boundary.
    values: seq[PolicyValue]
    error: CurrentDownloadPolicyError
    field: string

include ./policy/fields
include ../logical/policy_fields
include ../namespace_policy_fields

func error*(outcome: CurrentDownloadPolicyResult): CurrentDownloadPolicyError =
  ## Defaults/refusals never authorize startup or policy extraction.
  outcome.status

func value*(outcome: CurrentDownloadPolicyResult): CurrentDownloadLoopLimits {.requires:
    outcome.status == CurrentDownloadPolicyError.None.} =
  ## Copy only a complete policy; stage semantics remain the existing stages' responsibility.
  outcome.policy

func fieldName*(outcome: CurrentDownloadPolicyResult): string {.requires:
    outcome.status != CurrentDownloadPolicyError.None.} =
  ## Explain only an actual failure without exposing partial numeric configuration.
  outcome.field

proc refused(reason: CurrentDownloadPolicyError, field = ""): CurrentDownloadPolicyResult =
  ## Construct a payload-free failed/default alternative.
  CurrentDownloadPolicyResult(status: reason, field: field)

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
  if input.error notin [CurrentDownloadPolicyError.None,
      CurrentDownloadPolicyError.MissingField]: return # Keep the first selected error and no public partial policy.
  for index in 0..<input.values.len:
    if input.values[index].name == name:
      let number = input.values[index].number
      when T is bool:
        if number > 1:
          input.error = CurrentDownloadPolicyError.InvalidNumber
          input.field = name
          return # Discovery opt-in accepts only an explicit canonical zero or one.
        field = number == 1
      else:
        when sizeof(T) == 4:
          if number > uint64(high(uint32)):
            input.error = CurrentDownloadPolicyError.InvalidNumber
            input.field = name
            return # Check every narrow nominal conversion before assignment.
        elif sizeof(T) != 8:
          {.error: "current v1 policy leaves require reviewed boolean or unsigned 32/64-bit domains".}
        field = T(number)
      input.values[index].used = true
      return # One unique key supplies exactly one declared field.
  if input.error == CurrentDownloadPolicyError.None:
    input.error = CurrentDownloadPolicyError.MissingField
    input.field = name # Continue marking known fields so unknown-key diagnostics remain exact.

proc writeField[T](text: var string, name: string, field: T) {.untyped.} =
  ## Complete fixed schema bounds output extent; unsigned conversion preserves every supported domain width.
  when T is bool:
    text.add(name & "=" & (if field: "1" else: "0") & "\n")
  else:
    text.add(name & "=" & $uint64(field) & "\n") # Only the reviewed nominal unsigned leaf widths reach this branch.

proc encodeCurrentDownloadPolicy*(policy: CurrentDownloadLoopLimits): string =
  ## Emit every explicit v1 value; this serializer provides no defaults or semantic-policy certification.
  result = PolicyHeader & "\n"
  currentPolicyFields(policy, result, writeField)

proc scanPolicy(text, header: string): PolicyInput =
  ## Bounded lexical preflight precedes private typed assignment; no failed parse publishes a prefix.
  if text.len > CurrentDownloadPolicyBytes: return PolicyInput(
      error: CurrentDownloadPolicyError.LimitExceeded)
  var input = PolicyInput(error: CurrentDownloadPolicyError.None, values: @[])
  var position, line = 0
  while position < text.len:
    let first = position
    while position < text.len and text[position] != '\n': inc position # Input cap bounds the complete scan.
    let extent = position - first
    if line == 0:
      if extent != header.len or text.substr(first, position - 1) !=
          header: return PolicyInput(error: CurrentDownloadPolicyError.WrongVersion)
    elif extent > 0 and text[first] != '#':
      if extent > 214: return PolicyInput(error: CurrentDownloadPolicyError.LimitExceeded) # Key <=192, '=', decimal <=20, all before copying.
      var separator = -1
      for index in first..<position:
        let character = text[index]
        if character == '=':
          if separator >= 0: return PolicyInput(error: CurrentDownloadPolicyError.InvalidLine)
          separator = index
        elif separator < 0 and character notin {'a'..'z', 'A'..'Z', '0'..'9', '.'}:
          return PolicyInput(error: CurrentDownloadPolicyError.InvalidLine) # Exact ASCII keys have no escapes or whitespace aliases.
      if separator <= first or separator - first > 192: return PolicyInput(error:
        CurrentDownloadPolicyError.InvalidLine)
      let name = text.substr(first, separator - 1)
      var number = 0'u64
      if separator + 1 == position or not decimal(text.substr(separator + 1, position - 1), number):
        return PolicyInput(error: CurrentDownloadPolicyError.InvalidNumber, field: name)
      for previous in input.values:
        if previous.name == name:
          let reason = CurrentDownloadPolicyError.DuplicateField
          return PolicyInput(error: reason, field: name) # Duplicate preflight precedes retaining another scalar row.
      if input.values.len == PolicyValues: return PolicyInput(
          error: CurrentDownloadPolicyError.LimitExceeded)
      input.values.add(PolicyValue(name: name, number: number, used: false))
    inc line
    if position < text.len: inc position # Skip only a proven present LF; final newline is optional.
  if line == 0: return PolicyInput(error: CurrentDownloadPolicyError.WrongVersion)
  input

proc decodeCurrentDownloadPolicy*(text: string): CurrentDownloadPolicyResult =
  ## Shared strict lexical parsing precedes the original complete v1 schema and outer policy validation.
  var input = scanPolicy(text, PolicyHeader)
  if input.error != CurrentDownloadPolicyError.None: return refused(input.error, input.field)
  var policy = default(CurrentDownloadLoopLimits)
  currentPolicyFields(policy, input, readField)
  if input.error notin [CurrentDownloadPolicyError.None, CurrentDownloadPolicyError.MissingField]:
    return refused(input.error, input.field) # A typed conversion failure precedes unrelated unset fields.
  for entry in input.values:
    if not entry.used: return refused(CurrentDownloadPolicyError.UnknownField,
        entry.name) # No extension/typo silently changes caller intent.
  if input.error != CurrentDownloadPolicyError.None: return refused(input.error, input.field)
  let schedule = policy.schedule
  let stream = policy.stream
  if uint64(schedule.peers) == 0 or uint64(schedule.peers) > 16 or schedule.attempts == 0 or
      uint64(schedule.retryDelay) == 0 or uint64(policy.input.blockBytes) == 0 or
      uint64(stream.readBytes) == 0 or uint64(stream.readBytes) > 4096 or
      uint64(stream.writeBytes) == 0 or uint64(stream.writeBytes) > 42 or
      uint64(stream.timeout) == 0 or uint64(policy.attemptTimeout) == 0:
    return refused(CurrentDownloadPolicyError.InvalidPolicy) # Reject unusable outer dispatcher bounds before any startup/native work.
  CurrentDownloadPolicyResult(status: CurrentDownloadPolicyError.None, policy: policy)

proc readPolicyFile(path: string, text: var string): CurrentDownloadPolicyError {.raises.} =
  ## Read at most cap+1 bytes through public string bulk-write APIs, including files that grow during the read.
  var file: File = nil
  if path.len == 0 or not open(file, path, fmRead): return CurrentDownloadPolicyError.FileFailure
  defer: close(file) # Every parse/size/I/O return ends the native file borrow.
  text = newString(CurrentDownloadPolicyBytes + 1)
  let buffer = text.beginStore(text.len)
  let count = readBuffer(file, cast[pointer](buffer), text.len)
  text.endStore()
  if count < 0: return CurrentDownloadPolicyError.FileFailure
  if count > CurrentDownloadPolicyBytes: return CurrentDownloadPolicyError.LimitExceeded
  text.setLen(count)
  CurrentDownloadPolicyError.None

proc loadCurrentDownloadPolicy*(path: string): CurrentDownloadPolicyResult {.raises.} =
  ## Reuse the exact bounded transport reader; a failed file never reaches schema assignment.
  var text = ""
  let reason = readPolicyFile(path, text)
  if reason != CurrentDownloadPolicyError.None: return refused(reason)
  decodeCurrentDownloadPolicy(text)

func error*(outcome: CurrentLogicalPolicyResult): CurrentDownloadPolicyError =
  ## Default and failed logical policy results have no usable budgets.
  outcome.status

func value*(outcome: CurrentLogicalPolicyResult): CurrentLogicalStartupLimits {.inline,
    requires: outcome.status == CurrentDownloadPolicyError.None.} =
  ## Return only a complete explicit policy snapshot; startup and State stages still enforce each budget.
  outcome.policy

func fieldName*(outcome: CurrentLogicalPolicyResult): string {.inline,
    requires: outcome.status != CurrentDownloadPolicyError.None.} =
  ## Inspect the bounded actual failed field without exposing a successful prefix.
  outcome.field

proc logicalRefused(reason: CurrentDownloadPolicyError, field = ""): CurrentLogicalPolicyResult =
  ## Construct only the failed alternative of the logical policy result.
  CurrentLogicalPolicyResult(status: reason, field: field)

proc encodeCurrentLogicalPolicy*(policy: CurrentLogicalStartupLimits): string =
  ## Emit every required logical resource leaf without selecting any resource defaults.
  result = LogicalPolicyHeader & "\n"
  currentLogicalPolicyFields(policy, result, writeField)

proc decodeCurrentLogicalPolicy*(text: string): CurrentLogicalPolicyResult =
  ## Reuse the original canonical lexical scanner, then require the entire independent logical schema.
  var input = scanPolicy(text, LogicalPolicyHeader)
  if input.error != CurrentDownloadPolicyError.None: return logicalRefused(input.error, input.field)
  var policy = default(CurrentLogicalStartupLimits)
  currentLogicalPolicyFields(policy, input, readField)
  if input.error notin [CurrentDownloadPolicyError.None, CurrentDownloadPolicyError.MissingField]:
    return logicalRefused(input.error, input.field)
  for entry in input.values:
    if not entry.used: return logicalRefused(CurrentDownloadPolicyError.UnknownField, entry.name)
  if input.error != CurrentDownloadPolicyError.None: return logicalRefused(input.error, input.field)
  CurrentLogicalPolicyResult(status: CurrentDownloadPolicyError.None, policy: policy)

proc loadCurrentLogicalPolicy*(path: string): CurrentLogicalPolicyResult {.raises.} =
  ## Complete bounded file snapshot is decoded atomically; extra/growing input refuses before startup.
  var text = ""
  let reason = readPolicyFile(path, text)
  if reason != CurrentDownloadPolicyError.None: return logicalRefused(reason)
  decodeCurrentLogicalPolicy(text)

func error*(outcome: CurrentNamespacePolicyResult): CurrentDownloadPolicyError =
  ## Defaults/refusals never grant namespace capture or continuation policies.
  outcome.status

func value*(outcome: CurrentNamespacePolicyResult): CurrentNamespacePolicy {.inline,
    requires: outcome.status == CurrentDownloadPolicyError.None.} =
  ## Extract only the entire explicit reviewed resource schema.
  outcome.policy

func fieldName*(outcome: CurrentNamespacePolicyResult): string {.inline,
    requires: outcome.status != CurrentDownloadPolicyError.None.} =
  ## Expose only an actual bounded refusal diagnostic.
  outcome.field

proc namespaceRefused(reason: CurrentDownloadPolicyError,
    field = ""): CurrentNamespacePolicyResult =
  ## Construct no partial configuration on any failed parser branch.
  CurrentNamespacePolicyResult(status: reason, field: field)

proc encodeCurrentNamespacePolicy*(policy: CurrentNamespacePolicy): string =
  ## Serialize every reviewed namespace leaf under one distinct explicit opt-in version.
  result = NamespacePolicyHeader & "\n"
  currentNamespacePolicyFields(policy, result, writeField)

proc decodeCurrentNamespacePolicy*(text: string): CurrentNamespacePolicyResult =
  ## Reuse canonical bounded lexical admission, require every leaf and refuse unknown/duplicate/overflow input before publication.
  var input = scanPolicy(text, NamespacePolicyHeader)
  if input.error != CurrentDownloadPolicyError.None: return namespaceRefused(input.error, input.field)
  var policy = default(CurrentNamespacePolicy)
  currentNamespacePolicyFields(policy, input, readField)
  if input.error notin [CurrentDownloadPolicyError.None, CurrentDownloadPolicyError.MissingField]:
    return namespaceRefused(input.error, input.field)
  for entry in input.values:
    if not entry.used: return namespaceRefused(CurrentDownloadPolicyError.UnknownField, entry.name)
  if input.error != CurrentDownloadPolicyError.None: return namespaceRefused(input.error, input.field)
  if uint64(policy.storage.entries) == 0 or uint64(policy.requests.entries) == 0:
    return namespaceRefused(CurrentDownloadPolicyError.InvalidPolicy,
        "storage.entries/requests.entries") # Namespace mode cannot ever qualify with its mandatory history owners disabled.
  CurrentNamespacePolicyResult(status: CurrentDownloadPolicyError.None, policy: policy)

proc loadCurrentNamespacePolicy*(path: string): CurrentNamespacePolicyResult {.raises.} =
  ## Bounded independent policy-file capture precedes Services, databases and outgoing transport.
  var text = ""
  let reason = readPolicyFile(path, text)
  if reason != CurrentDownloadPolicyError.None: return namespaceRefused(reason)
  decodeCurrentNamespacePolicy(text)

proc configureCurrentNamespaces*(candidate: var CurrentCandidateLimits,
    policy: CurrentNamespacePolicy) =
  ## Change only explicitly supplied namespace capture/retention fields; existing execution, account membership and store ceilings remain independently configured.
  candidate.storage = policy.storage
  candidate.requests = policy.requests
  candidate.serviceIdentities = policy.services
  candidate.completion.execution.initial.guests.storageFacts = policy.initial.storage
  candidate.completion.execution.initial.guests.requestFacts = policy.initial.requests
  candidate.completion.execution.execution.round.guests.storageFacts = policy.round.storage
  candidate.completion.execution.execution.round.guests.requestFacts = policy.round.requests
