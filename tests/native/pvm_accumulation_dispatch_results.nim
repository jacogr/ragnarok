# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and failed dispatch results cannot reveal CPU snapshots or unselected engine reasons.

import std/cmdline
import ../../src/state/[accumulation_machine, accumulation_dispatch]
import ../../src/pvm/[machine, host_fetch, step, gas]
import ../support/pvm_accumulation_context
var outcome = executeAccumulationMachine(default(PreparedAccumulationMachine), pvmParameters(),
  default(FetchAccumulationLimits), MemoryByteLimit(0), ExecutionStepLimit(0), HostCallLimit(0),
  GasCycleLimit(0))
if paramStr(1) == "default":
  outcome = default(AccumulationDispatchResult) # Select the runtime default-access probe.
case paramStr(1)
of "default":
  discard outcome.value # No fabricated default CPU.
of "engine":
  discard outcome.executionError # A preparation refusal has no selected engine reason.
else:
  discard outcome.value # Invalid preparation exposes no partial execution snapshot.
