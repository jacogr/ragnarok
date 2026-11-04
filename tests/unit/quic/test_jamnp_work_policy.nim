# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict complete work-policy parsing refuses malformed files and values without inferring resource ceilings or engine identities.
import std/[assertions, strutils, syncio]
import ../../../src/app/work_policy
import ../../../src/app/work_policy/types
import ../../../src/jamnp-s/[work_submission, work_duty]
import ../../../src/state/input_refinement
import ../../../src/codec/bounded
import ../../../src/pvm/backend
proc baseline(): string =
  ## Explicit local inputs select outer bounds; unused child zero budgets remain explicit numeric values rather than defaults.
  var admission = default(WorkSubmissionLimits)
  var execution = default(InputRefinementLimits)
  admission.authorization.backend = PvmBackend.Interpreted
  execution.authorization.backend = PvmBackend.Jit
  execution.refinement.refinement.invocation.backend = PvmBackend.Interpreted
  execution.refinement.refinement.invocation.inner.backend = PvmBackend.Jit
  execution.inputBytes = ByteLimit(65536)
  encodeWorkPolicy(admission, execution, WorkDutyLimits(chapterBytes: ByteLimit(1048576),
    disputeItems: ElementLimit(1023)), timeoutMs = 120000)
proc main() {.raises.} =
  ## Whole-schema refusal tests complement live dispatch with actual decoded PVM budgets in the application suite.
  let text = baseline()
  let decoded = decodeWorkPolicy(text)
  assert decoded.error == WorkPolicyError.None and decoded.value.valid
  assert decodeWorkPolicy(text & "# bounded comment\n\n").error == WorkPolicyError.None
  assert decodeWorkPolicy(text.substr(0, text.len-2)).error == WorkPolicyError.None
  assert decodeWorkPolicy("").error == WorkPolicyError.WrongVersion
  assert decodeWorkPolicy(text.replace("ragnarok-work-policy-v1",
      "ragnarok-work-policy-v2")).error == WorkPolicyError.WrongVersion
  let lines = text.splitLines()
  assert lines.len == 87 # Header, every one of 85 explicit fields and the final empty line.
  for index in 1..<lines.len-1:
    # Removing each declared leaf independently must fail; no default backend or resource budget fills the gap.
    var missing = lines
    missing.delete(index)
    let selected = decodeWorkPolicy(missing.join("\n"))
    assert selected.error == WorkPolicyError.MissingField
    let separator = lines[index].find('=')
    assert selected.fieldName == lines[index].substr(0, separator-1)
  assert decodeWorkPolicy(text & "timeoutMs=1000\n").error == WorkPolicyError.DuplicateField
  assert decodeWorkPolicy(text & "unknown=0\n").error == WorkPolicyError.UnknownField
  for value in ["-1", "+1", "00", " 1", "1 ", "1.0", "0x10", "18446744073709551616"]:
    # Canonical decimal never truncates, wraps or accepts an alternate representation.
    let selected = decodeWorkPolicy(text.replace("timeoutMs=120000", "timeoutMs=" & value))
    assert selected.error == WorkPolicyError.InvalidNumber and selected.fieldName == "timeoutMs"
  for value in ["0", "120001", "18446744073709551615"]:
    assert decodeWorkPolicy(text.replace("timeoutMs=120000", "timeoutMs=" & value)).error ==
        WorkPolicyError.InvalidPolicy
  assert decodeWorkPolicy(text.replace("execution.inputBytes=65536",
      "execution.inputBytes=0")).error == WorkPolicyError.InvalidPolicy
  for value in ["compiled", "JIT", "0", "jit "]:
    # A removed engine, changed case, enum ordinal and whitespace suffix cannot select a backend.
    assert decodeWorkPolicy(text.replace("execution.authorization.backend=jit",
      "execution.authorization.backend=" & value)).error == WorkPolicyError.InvalidBackend
  assert decodeWorkPolicy(text & "bad key=0\n").error == WorkPolicyError.InvalidLine
  assert decodeWorkPolicy(text & "broken\n").error == WorkPolicyError.InvalidLine
  assert decodeWorkPolicy(text & "bad=0=1\n").error == WorkPolicyError.InvalidLine
  assert decodeWorkPolicy(text & repeat("#", WorkPolicyBytes)).error ==
      WorkPolicyError.LimitExceeded
  assert decodeWorkPolicy(text & repeat("x", 193) & "=0\n").error == WorkPolicyError.InvalidLine
  assert decodeWorkPolicy(text & "x=" & repeat("1", 65) & "\n").error ==
      WorkPolicyError.LimitExceeded
  assert loadWorkPolicy("missing-work-policy.txt").error == WorkPolicyError.FileFailure
  writeFile("work-policy.txt", text)
  assert loadWorkPolicy("work-policy.txt").error == WorkPolicyError.None
  writeFile("work-policy.txt", repeat("x", WorkPolicyBytes+1))
  assert loadWorkPolicy("work-policy.txt").error == WorkPolicyError.LimitExceeded
  echo "JAMNP-S work policy passed"
try:
  main()
except:
  quit 2 # A local I/O exception cannot substitute for the complete parsing transcript.
