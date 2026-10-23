# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Canonical complete namespace resource policies refuse malformed/partial input atomically and configure only the explicitly named producer fields.
import std/[assertions, syncio, envvars, cmdline, strutils]
import std/posix/posix
import ../support/[current_namespace_policy_context, accumulation_current_candidate_context, arc_evidence]
import ../../src/app/[current_download_policy, candidate, current_logical_download, options]
import ../../src/state/[logical_continuation, accumulation_effects, accumulation_current_update]
import ../../src/codec/bounded
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Lexical/schema/file policy checks never require cryptographic availability.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Missing/unknown/duplicate/overflow admission stays hash-free.
proc joined(left, right: seq[string]): seq[string] =
  ## Explicit argument copying preserves caller arrays without relying on unsupported sequence concatenation.
  result = left
  for value in right: result.add(value)
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(CurrentNamespacePolicyResult)
  if mode == "value":
    discard empty.value
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  let policy = namespacePolicyTestLimits()
  let text = encodeCurrentNamespacePolicy(policy)
  let parsed = decodeCurrentNamespacePolicy(text)
  if mode == "field":
    discard parsed.fieldName # No preceding success assertion lets this genuine successful parse reach the runtime failure guard.
    return
  assert parsed.error == CurrentDownloadPolicyError.None
  assert encodeCurrentNamespacePolicy(parsed.value) == text
  fail(1)
  let rows = text.splitLines()
  for missing in 1..<rows.high:
    # Omitting any single reviewed scalar must report its actual name, with no extracted prefix.
    var incomplete = rows[0] & "\n"
    for i in 1..<rows.high:
      if i != missing: incomplete.add(rows[i] & "\n")
    let refused = decodeCurrentNamespacePolicy(incomplete)
    assert refused.error == CurrentDownloadPolicyError.MissingField
    assert refused.fieldName == rows[missing].substr(0, rows[missing].find('=')-1)
  for value in ["", "-1", "01", "18446744073709551616", " 1", "1 "]:
    # Canonical decimal parsing refuses overflow before multiplication or field assignment.
    let malformed = text.replace("initial.requests=8", "initial.requests=" & value)
    assert decodeCurrentNamespacePolicy(malformed).error == CurrentDownloadPolicyError.InvalidNumber
  assert decodeCurrentNamespacePolicy(text & "initial.requests=1\n").error ==
      CurrentDownloadPolicyError.DuplicateField
  assert decodeCurrentNamespacePolicy(text & "unknown=1\n").error ==
      CurrentDownloadPolicyError.UnknownField
  assert decodeCurrentNamespacePolicy("ragnarok-current-logical-policy-v1\n").error ==
      CurrentDownloadPolicyError.WrongVersion
  assert decodeCurrentNamespacePolicy(repeat('x', CurrentDownloadPolicyBytes+1)).error ==
      CurrentDownloadPolicyError.LimitExceeded
  for key in ["storage.entries", "requests.entries"]:
    assert decodeCurrentNamespacePolicy(text.replace(key & "=8", key & "=0")).error ==
        CurrentDownloadPolicyError.InvalidPolicy # Mandatory source owners cannot be disabled in namespace mode.
  let wide = text.replace("continuation.scratchBytes=262144", "continuation.scratchBytes=18446744073709551615")
  assert uint64(decodeCurrentNamespacePolicy(wide).value.continuation.scratchBytes) == high(uint64)
  assert calls() == 0
  fail(0)
  var candidate = currentCandidateLimits()
  candidate.completion.execution.initial.guests.createdAccounts = ElementLimit(7)
  candidate.completion.execution.initial.guests.deletedAccounts = ElementLimit(5)
  configureCurrentNamespaces(candidate, parsed.value)
  assert uint64(candidate.storage.entries) == 8 and uint64(candidate.requests.entries) == 8
  assert uint64(candidate.completion.execution.initial.guests.requestFacts) == 8
  assert uint64(candidate.completion.execution.execution.round.guests.storageFacts.items) == 4
  assert uint64(candidate.completion.execution.initial.guests.createdAccounts) == 7 and uint64(
      candidate.completion.execution.initial.guests.deletedAccounts) == 5
  let base = @["download-current", "--with-state", "--chain", "chain.json"]
  let pair = @["--download-logical-source", "source.txt", "--download-logical-policy", "logical.txt"]
  let extra = @["--download-namespace-policy", "namespace.txt"]
  var options = default(Options)
  assert parseOptions(joined(joined(base, pair), extra), options)
  assert options.logicalDownloadEnabled and options.namespaceDownloadPolicyPath == "namespace.txt"
  for invalid in [joined(base, extra), joined(joined(joined(base, pair), extra), extra), joined(
      joined(base, pair), @["--download-namespace-policy", "a\0b"]), joined(joined(@["server",
      "--with-state"], pair), extra)]:
    assert not parseOptions(invalid, options)
    assert options.namespaceDownloadPolicyPath.len == 0 and not options.logicalDownloadEnabled
  let update = @["--download-update-logical-source"]
  assert parseOptions(joined(joined(base, pair), update), options) and
      options.updateLogicalDownloadSource
  assert not parseOptions(joined(base, update), options)
  assert not options.updateLogicalDownloadSource
  assert not parseOptions(joined(joined(joined(base, pair), update), update), options)
  assert not options.updateLogicalDownloadSource
  var path = "current-namespace-policy-file"
  discard posix.unlink(path.toCString())
  defer: discard posix.unlink(path.toCString()) # Only this test-owned file is removed after its bounded reader closes.
  assert loadCurrentNamespacePolicy(path).error == CurrentDownloadPolicyError.FileFailure
  writeFile(path, repeat('x', CurrentDownloadPolicyBytes+1))
  assert loadCurrentNamespacePolicy(path).error == CurrentDownloadPolicyError.LimitExceeded
  writeFile(path, text)
  assert encodeCurrentNamespacePolicy(loadCurrentNamespacePolicy(path).value) == text
  let disabled = initCurrentLogicalDownloadPolicy(default(CurrentLogicalDownloadPolicy),
      policy.continuation)
  assert qualifyCurrentDownload(disabled, default(PreparedCurrentChainUpdate)).error ==
      CurrentLogicalDownloadError.InvalidPolicy
  for i in 0..<25: discard decodeCurrentNamespacePolicy(
      text).value # Warm exact bounded lexical/schema retention and release.
  let before = getOccupiedMem()
  for i in 0..<1000: discard decodeCurrentNamespacePolicy(text).value
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("current_namespace_policy", 1000, before, after)
  echo "current-namespace-policy: ok"
try: main()
except: quit(2) # Invalid options, file or parser witnesses cannot impersonate a runtime guard.
