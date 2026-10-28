# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized guards reject failed authorization payloads and unrelated stage details after genuine positive controls.

import std/assertions
import std/cmdline
import ../../src/state/authorization_invocation as state_authorization_invocation
import ../../src/state/refinement_lookup as state_refinement_lookup
import ../../src/codec/bounded as codec_bounded
import ../../src/pvm/initialize as pvm_initialize
import ../../src/pvm/host_fetch as pvm_host_fetch
import ../../src/pvm/step as pvm_step
import ../../src/pvm/output as pvm_output
import ../../src/pvm/machine as pvm_machine
import ../support/pvm_authorization_invoke
import ../support/pvm_refinement_outcome

proc check(outcome: AuthorizationInvocationResult[AuthorizationInvocation],
    reason: AuthorizationInvocationError) =
  ## Confirm actual alternatives without specializing the deliberate contract misuse below.
  assert outcome.error == reason
let code = [refinementImmediate(7, 196608), refinementImmediate(8, 3), @[50'u8, 0]]
let fixture = authorizationFixture(code)
let success = authorizationRun(fixture)
check(success, AuthorizationInvocationError.None)
assert success.value.authorizationTrace.value == @[21'u8, 22, 23]
let missing = default(AuthorizationInvocationResult[AuthorizationInvocation])
check(missing, AuthorizationInvocationError.Uninitialized)
var cap = authorizationLimits()
cap.output = OutputByteLimit(2)
let refused = authorizationRun(fixture, cap)
check(refused, AuthorizationInvocationError.LimitExceeded)
let lookup = authorizationRun(authorizationFixture(code, malformedState = true))
check(lookup, AuthorizationInvocationError.LookupFailure)
assert lookup.lookupError == HistoricalLookupError.MalformedState
let initialization = authorizationRun(authorizationFixture(code, overrideBytes = @[0'u8, 1]))
check(initialization, AuthorizationInvocationError.InitializationFailure)
assert initialization.initializationError == InitializationError.InvalidEnvelope
cap = authorizationLimits()
cap.encoding = FetchEncodingLimit(0)
let fetch = authorizationRun(fixture, cap)
check(fetch, AuthorizationInvocationError.FetchFailure)
assert fetch.fetchError == FetchError.LimitExceeded
cap = authorizationLimits()
cap.steps = ExecutionStepLimit(0)
let engine = authorizationRun(fixture, cap)
check(engine, AuthorizationInvocationError.ExecutionFailure)
assert engine.executionError == StepError.StepLimitExceeded
let fetchCode = [refinementImmediate(7, 196608), refinementImmediate(8, 0), refinementImmediate(9, 2),
  refinementImmediate(10, 8), @[10'u8, 2], @[50'u8, 0]]
cap = authorizationLimits()
cap.copy = MemoryByteLimit(1)
let host = authorizationRun(authorizationFixture(fetchCode), cap)
check(host, AuthorizationInvocationError.HostFailure)
assert host.hostError == AuthorizationHostError.LimitExceeded
case paramStr(1)
of "default": discard missing.value # Default contains no completed invocation.
of "refused": discard refused.value # A late output refusal cannot publish partial trace or gas.
of "lookup": discard lookup.value # Historical refusal has no protocol BAD owner.
of "initialization": discard initialization.value # Invalid code cannot fabricate a completed invocation.
of "fetch": discard fetch.value # Environment capture refusal has no partial CPU or trace.
of "host": discard host.value # Local copy refusal cannot publish earlier guest progress.
of "engine": discard engine.value # Local execution limits cannot become protocol OOG.
of "success-lookup": discard success.lookupError # Successful work has no lookup refusal detail.
of "success-initialization": discard success.initializationError # Successful work has no initialization refusal.
of "success-fetch": discard success.fetchError # Successful work has no environment-capture refusal.
of "success-host": discard success.hostError # Successful work has no host refusal.
of "success-engine": discard success.executionError # Successful work has no local engine refusal.
of "wrong-host": discard engine.hostError # Distinct failure stages cannot reinterpret reasons.
of "wrong-engine": discard host.executionError # Host refusal cannot fabricate StepError.
of "owner": discard default(AuthorizationInvocation).authorizationInfo.value # Default owner has no copied metadata.
else:
  let bad = authorizationRun(authorizationFixture(code, missing = true)).value
  discard bad.authorizationTrace.value # BAD is a completed protocol result without success bytes.
