# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual provide-local failures cannot expose a charged CPU or partially accumulated implication pair.

import std/[assertions, cmdline]
import ../../src/state/accumulation_dispatch
import ../../src/pvm/[machine, step]
import ../support/pvm_accumulation_provision

## Inject backend refusal only after the complete guest/source fixture exists.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc checkReason(outcome: AccumulationDispatchResult, expected: AccumulationDispatchError) =
  ## Confirm the real alternative in a separate procedure so intentional misuse remains a runtime contract probe.
  assert outcome.error == expected, "actual provide alternative: " & $outcome.error
proc checkOog(outcome: AccumulationDispatchResult) =
  ## A completed unsigned OOG remains a valid owner with zero gas and no local engine-failure reason.
  checkReason(outcome, AccumulationDispatchError.None)
  assert outcome.value.exit == StepExit.OutOfGas and uint64(machineInfo(
      outcome.value.machine).value.gas) == 0
let argument = paramStr(1)
let call = ProvisionGuestCall(id: 28, r7: high(uint64), r8: 65536, r9: 3)
var source = provisionMachine([call])
let positive = runProvision(source)
assert positive.error == AccumulationDispatchError.None and positive.value.exit == StepExit.Halt, "genuine provide control completes before fault injection"
if argument == "oog-reason":
  source = provisionMachine([ProvisionGuestCall(id: 28, r9: high(uint64))], credit = high(
      uint64)) # A wide unaffordable current charge is protocol OOG, not a failed local result.
if argument == "malformed":
  source = provisionMachine([call], history = @[4'u8]) # Canonical query rejects an impossible request count.
if argument == "backend":
  failHash(1) # Guest reaches the payload hash only after successful memory validation.
var outcome = runProvision(source)
if argument == "local":
  outcome = runProvision(source, provisionPolicy(items = 0)) # No capacity for the requested pair.
case argument
of "backend":
  checkReason(outcome, AccumulationDispatchError.BackendFailure)
  discard outcome.effects
of "oog-reason":
  checkOog(outcome)
  discard outcome.executionError
of "malformed":
  checkReason(outcome, AccumulationDispatchError.MalformedState)
  discard outcome.value
else:
  checkReason(outcome, AccumulationDispatchError.LimitExceeded)
  discard outcome.value
