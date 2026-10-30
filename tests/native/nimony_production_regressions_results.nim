# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group":"failure_driver"}

## Minimal compiler regressions and result-contract premises, qualified with and without ThinLTO.
## References: spec/compiler-issues.md NIM-001/NIM-003 and the October 21 #2737 reproduction.
import std/[assertions, cmdline, syncio]
import ../support/probe_cases
import ./pvm_step_results

# @@ProbeCases
type VerificationProbe = enum
  vpPointer = "pointer-refinement"
  vpMove = "sequence-move"
  vpSlice = "sequence-slice"
  vpStepDefault = "step-default"
  vpStepInvalid = "step-invalid"
  vpStepLimit = "step-limit"
  vpStepScan = "step-scan-limit"
  vpStepUnsupported = "step-unsupported"

type RegressionOwner = object ## Scalar-only exclusive ownership mirrors the original sequence-copy defect.
  token: int
proc `=copy`(target: var RegressionOwner, source: RegressionOwner) {.error.}
  ## The positive move control must not silently fall back to a copy.
proc `=dup`(source: RegressionOwner): RegressionOwner {.error.}
  ## Derived sequence duplication remains unavailable.
proc transfer(): seq[RegressionOwner] =
  ## A legal explicit transfer must retain the actual payload under production optimization.
  var owner: seq[RegressionOwner] = @[]
  owner.add RegressionOwner(token: 7)
  result = move(owner)
proc touch(value: var int) =
  ## Mutating a pointee cannot invalidate the pointer's presence proof.
  inc value
proc receive(input: nil ptr int) =
  ## The original inferred-local second mutable call is the compiler regression witness.
  if input == nil: return
  let receiver = input
  touch(receiver[])
  touch(receiver[])

let selected = selectProbe[VerificationProbe](paramStr(1))
case selected
of vpPointer:
  # NIM-003: both mutable calls must execute through the guarded inferred pointer.
  var value = 1
  receive(addr value)
  assert value == 3
  receive(nil)
  assert value == 3
of vpMove:
  # #2737: the checked negative-copy regressions retain an independent successful move control.
  let owner = transfer()
  assert owner.len == 1 and owner[0].token == 7
of vpSlice:
  # NIM-001: instantiate the original sequence slice and verify independent mutation.
  let source = @[1, 2, 3]
  var copy = source[0..0]
  assert copy == @[1]
  copy[0] = 9
  assert source == @[1, 2, 3]
of vpStepDefault, vpStepInvalid, vpStepLimit, vpStepScan, vpStepUnsupported:
  # Preserve runtime-selected arguments instead of constant-folding the intended invalid extraction.
  var origin = paramStr(1)
  if selected == vpStepScan: origin = "scan_limit"
  else: origin = origin[5..^1]
  runFailureProbe(origin)
# A returned negative case must not be confused with a deliberately rejected result read.
echo "CONTRACT_COMPILER_OK " & $selected
