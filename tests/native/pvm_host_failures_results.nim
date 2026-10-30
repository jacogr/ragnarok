# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated guard probes for fallible callback and execution alternatives.
## Positive controls validate the selected reasons before each forbidden accessor is attempted.

import std/[assertions, cmdline]
import ../../src/pvm/[program, machine]
import ../../src/pvm/gas/gas
import ../../src/pvm/step

type
  # A caller-local enum proves that the host loop requires no dependency on concrete host modules.
  Reason = enum
    Refused

# Return one explicit local refusal after recording that the callback ran.
proc refuse(calls: var int, stopped: StepOutcome): HostResult[Reason] {.raises: [].} =
  inc calls
  hostFailure(Refused)

# Check valid alternatives in a separate call so runtime misuse probes remain runtime checks.
proc checkHost(r: HostExecutionResult[Reason]) =
  assert r.error == HostExecutionError.HostFailure and r.hostError == Refused

# Positive engine selection confirms the fixture reached the intended instruction-limit refusal.
proc checkEngine(r: HostExecutionResult[Reason]) =
  assert r.error == HostExecutionError.ExecutionFailure and r.executionError ==
      StepError.StepLimitExceeded

# Positive callback selection confirms the constructor's explicit refusal branch.
proc checkFailure(r: HostResult[Reason]) =
  assert r.kind == HostResultKind.Failure and r.failure == Refused

# Positive callback selection confirms the constructor's response branch.
proc checkResponse(r: HostResult[Reason]) =
  assert r.kind == HostResultKind.Response

let code = decodeProgram([0'u8, 0, 4, 10, 2, 50, 0, 5], CodeAddress(0),
  ProgramByteLimit(8), JumpCountLimit(0)).value
let source = captureMachine(code, captureMemory([], PageLimit(0)).value,
  MachineInfo(pc: CodeAddress(0), gas: MachineGas(100), blockCharged: true)).value
var calls = 0
let host = executeWithHost(source, calls, refuse, ExecutionStepLimit(2), HostCallLimit(1),
    GasCycleLimit(0))
checkHost(host)
assert calls == 1
let engine = executeWithHost(source, calls, refuse, ExecutionStepLimit(0), HostCallLimit(1),
    GasCycleLimit(0))
checkEngine(engine)
let failure = hostFailure(Refused)
let response = hostSuccess[Reason](default(HostResponse))
checkFailure(failure)
checkResponse(response)
case paramStr(1)
of "reply-value":
  # A local callback refusal has no response payload.
  discard failure.value
of "reply-reason":
  # A selected response has no failure reason, even when that enum's zero value exists.
  discard response.failure
of "reply-default":
  # Default callback results carry neither response nor selected refusal.
  let empty = default(HostResult[Reason])
  discard empty.value
of "host-value":
  # Local callback failure publishes no partially executed machine.
  discard host.value
of "engine-value":
  # Engine limits likewise publish no completed guest outcome.
  discard engine.value
of "host-engine":
  # Callback refusals cannot masquerade as engine errors.
  discard host.executionError
of "engine-host":
  # Engine failures cannot fabricate a caller enum reason.
  discard engine.hostError
else:
  # Default execution has no completed guest state.
  let empty = default(HostExecutionResult[Reason])
  discard empty.value
