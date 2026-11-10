# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict complete work-policy parsing refuses malformed files and values without inferring resource ceilings or engine identities.

import std/[assertions, strutils, syncio]
import ../../../src/app/work_policy
import ../../../src/app/[node_work_policy, work_exchange, work_distribution]
import ../../../src/app/work_policy/types
import ../../../src/jamnp-s/[work_submission, work_duty, work_sharing, work_recovery]
import ../../../src/state/input_refinement
import ../../../src/codec/bounded
import ../../../src/pvm/backend
import ../../support/jamnp_node_work_policy
import ../../support/[jamnp_guarantee_fixture, jamnp_work_fixture, jamnp_work_report_fixture,
  jamnp_work_recovery_fixture, pvm_input_refinement]

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

proc guarantor() {.raises.} =
  ## Complete v2 is explicit opt-in; every missing leaf fails, and legacy/default policies cannot load a signer or activate signed controllers.
  assert not default(NodeWorkPolicy).valid and not default(NodeWorkPolicy).guaranteeing
  let legacy = decodeNodeWorkPolicy(baseline())
  assert legacy.error == WorkPolicyError.None and legacy.value.valid
  assert not legacy.value.guaranteeing and legacy.value.dispatchPolicy.valid
  let text = encodeGuarantorPolicy(guarantorSettings())
  let decoded = decodeNodeWorkPolicy(text)
  assert decoded.error == WorkPolicyError.None, $decoded.error
  assert decoded.value.guaranteeing and decoded.value.exchangePolicy.valid
  assert decoded.value.distributionPolicy.valid and decoded.value.acquisitionPolicy.valid
  assert decoded.value.recoveryPolicy.valid
  let lines = text.splitLines()
  for index in 1..<lines.len-1:
    # Removing every declared signing/storage/serving/recovery leaf independently cannot produce partial activation.
    var missing = lines
    missing.delete(index)
    let selected = decodeNodeWorkPolicy(missing.join("\n"))
    assert selected.error == WorkPolicyError.MissingField
    let separator = lines[index].find('=')
    assert selected.fieldName == lines[index].substr(0, separator-1)
  assert decodeNodeWorkPolicy("\n").error == WorkPolicyError.WrongVersion
  assert decodeNodeWorkPolicy(text.replace("ragnarok-work-policy-v2",
      "ragnarok-work-policy-v3")).error == WorkPolicyError.WrongVersion
  assert decodeNodeWorkPolicy(text & "storage.entries=1\n").error == WorkPolicyError.DuplicateField
  assert decodeNodeWorkPolicy(text & "unknown=1\n").error == WorkPolicyError.UnknownField
  for key in ["storage.entries", "sharing.retention.bytes", "serving.wireBytes", "deliveryEntries",
      "acquisitionAttempts"]:
    let prefix = key & "="
    var changed: seq[string] = @[]
    for line in lines:
      if line.startsWith(prefix): changed.add(prefix & "0")
      else: changed.add(line)
    assert decodeNodeWorkPolicy(changed.join("\n")).error == WorkPolicyError.InvalidPolicy
  for value in ["-1", "00", "18446744073709551616"]:
    let invalid = text.replace("graceMs=2000", "graceMs=" & value)
    assert decodeNodeWorkPolicy(invalid).error == WorkPolicyError.InvalidNumber
  assert decodeNodeWorkPolicy(text.replace("exchangeTimeoutMs=120000",
      "exchangeTimeoutMs=2000")).error == WorkPolicyError.InvalidPolicy
  assert decodeNodeWorkPolicy(text & repeat("#", WorkPolicyBytes)).error ==
      WorkPolicyError.LimitExceeded
  writeFile("guarantor.policy", text)
  assert loadNodeWorkPolicy("guarantor.policy").error == WorkPolicyError.None
  assert loadNodeWorkPolicy("absent-guarantor.policy").error == WorkPolicyError.FileFailure

proc main() {.raises.} =
  ## Whole-schema refusal tests complement live dispatch with actual decoded PVM budgets in the application suite.
  guarantor()
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
