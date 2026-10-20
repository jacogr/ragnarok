# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized probes reject refused owners, wrong-stage reason access and protocol-error byte extraction.

import std/[assertions, cmdline]
import ../../src/state/[refinement_outcome, refinement_bootstrap, refinement_dispatch]
import ../../src/pvm/[machine, step, refinement_exports, output]
import ../../src/codec/composite
import ../support/pvm_refinement_outcome

proc run(source: PreparedRefinementBootstrap, cap = refinementLimits()): RefinementInvocationResult[
    RefinementInvocation] =
  ## Exercise the genuine runner rather than constructing synthetic tagged results or terminal machines.
  runRefinementInvocation(source, [], refinementInputs(), ExportOffset(7), cap)
proc checkSuccess(outcome: RefinementInvocationResult[RefinementInvocation]) =
  ## Selected success exposes only normalized data and its exact bootstrap source.
  assert outcome.error == RefinementInvocationError.None
proc checkStage(outcome: RefinementInvocationResult[RefinementInvocation],
    expected: RefinementInvocationError) =
  ## Hide positive alternative knowledge from misuse call sites while confirming the intended refusal first.
  assert outcome.error == expected

let halt = @[50'u8, 0]
let source = refinementFixture([halt])
let success = run(source)
checkSuccess(success)
let missing = default(RefinementInvocationResult[RefinementInvocation])
let refused = run(default(PreparedRefinementBootstrap))
checkStage(refused, RefinementInvocationError.InvalidBootstrap)
let capture = runRefinementInvocation(source, [], default(RefinementInputs), ExportOffset(7),
    refinementLimits())
checkStage(capture, RefinementInvocationError.BootstrapFailure)
let host = run(refinementFixture([@[10'u8, 9], halt]))
checkStage(host, RefinementInvocationError.HostFailure)
var limited = refinementLimits()
limited.steps = ExecutionStepLimit(0)
let engine = run(source, limited)
checkStage(engine, RefinementInvocationError.ExecutionFailure)
limited = refinementLimits()
limited.output = OutputByteLimit(0)
let outputRefusal = run(source, limited)
checkStage(outputRefusal, RefinementInvocationError.LimitExceeded)
let protocol = run(refinementFixture([halt], missing = true)).value
assert protocol.refinementInfo.value.kind == WorkKind.Bad
case paramStr(1)
of "default": discard missing.value # Default results have no selected owner.
of "refused": discard refused.value # Missing bootstrap never becomes protocol BAD.
of "capture": discard capture.value # Input capture failure carries no partial execution.
of "host": discard host.value # Unsupported host cannot become protocol panic.
of "engine": discard engine.value # Local instruction budget cannot become guest OOG.
of "output": discard outputRefusal.value # Output policy cannot expose truncated bytes.
of "wrong-bootstrap": discard engine.bootstrapError # Engine failure cannot fabricate a capture reason.
of "wrong-host": discard capture.hostError # Capture failure cannot fabricate a callback reason.
of "wrong-engine": discard host.executionError # Host failure cannot fabricate an engine reason.
of "success-bootstrap": discard success.bootstrapError # Success has no capture refusal.
of "success-host": discard success.hostError # Success has no callback refusal.
of "success-engine": discard success.executionError # Success has no engine refusal.
of "protocol-output": discard protocol.refinementOutput.value # BAD contains no successful empty byte blob.
else:
  let empty = default(RefinementInvocation)
  discard empty.refinementInfo.value # Default owners cannot fabricate normalized gas or source metadata.
