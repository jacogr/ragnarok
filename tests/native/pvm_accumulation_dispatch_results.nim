# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and failed dispatch results cannot reveal CPU snapshots or unselected engine reasons.

import std/cmdline
import ../../src/state/accumulation_machine as state_accumulation_machine
import ../../src/state/accumulation_dispatch as state_accumulation_dispatch
import ../../src/pvm/machine as pvm_machine
import ../../src/pvm/host_fetch as pvm_host_fetch
import ../../src/pvm/step as pvm_step
import ../../src/pvm/gas as pvm_gas
import ../support/pvm_accumulation_context
var outcome = executeAccumulationMachine(default(PreparedAccumulationMachine), pvmParameters(),
  default(FetchAccumulationLimits), MemoryByteLimit(0), ExecutionStepLimit(0), HostCallLimit(0),
  GasCycleLimit(0), pvmContextConfig())
if paramStr(1) == "default" or paramStr(1) == "default-effects":
  outcome = default(AccumulationDispatchResult) # Select the runtime default-access probe.
case paramStr(1)
of "default":
  discard outcome.value # No fabricated default CPU.
of "default-effects", "failed-effects":
  discard outcome.effects # Neither default nor preparation refusal may reveal implication owners.
of "engine":
  discard outcome.executionError # A preparation refusal has no selected engine reason.
else:
  discard outcome.value # Invalid preparation exposes no partial execution snapshot.
