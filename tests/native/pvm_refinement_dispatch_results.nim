# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized misuse probes reject default/refused preparation, execution and wrong engine-error extraction.

import std/[assertions, cmdline]
import ../../src/state/[refinement_dispatch, store]
import ../../src/pvm/[machine, gas, step, host_fetch, refinement_exports]
import ../../src/chain/parameters
import ../../src/codec/work_package

proc checkPrepared(outcome: RefinementDispatchResult[PreparedRefinementExecution]) =
  ## Confirm the local invalid-machine alternative before attempting forbidden extraction.
  assert outcome.error == RefinementDispatchError.InvalidMachine
proc checkRun(outcome: RefinementDispatchResult[RefinementOutcome]) =
  ## Confirm missing preparation remains a local refusal rather than a successful empty guest result.
  assert outcome.error == RefinementDispatchError.InvalidContext

let missingPreparation = default(RefinementDispatchResult[PreparedRefinementExecution])
let missingRun = default(RefinementDispatchResult[RefinementOutcome])
let refusedPreparation = prepareRefinementExecution(default(Machine), default(StateStoreSnapshot),
  default(OwnedWorkPackage), FetchItemIndex(0), default(Parameters), [], default(RefinementInputs),
  default(RefinementHeapBounds), ExportOffset(0), default(RefinementCaptureLimits))
checkPrepared(refusedPreparation)
let refusedRun = executeRefinement(default(PreparedRefinementExecution), MemoryByteLimit(0),
  default(ExportLimits), ExecutionStepLimit(0), HostCallLimit(0), GasCycleLimit(0))
checkRun(refusedRun)
case paramStr(1)
of "prepared-default":
  discard missingPreparation.value # Default capture has no owner.
of "prepared-refused":
  discard refusedPreparation.value # Failed capture has no partly prepared owner.
of "run-default":
  discard missingRun.value # Default execution has no CPU or exports.
of "run-refused":
  discard refusedRun.value # Local refusal has no partial progress.
of "engine-default":
  discard missingRun.executionError # Default cannot fabricate an engine reason.
else:
  discard refusedRun.executionError # Local context failure is not engine failure.
