# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict computed stopped/finalization payload and selected child-reason probes with real completed guest controls.

import std/assertions
import std/cmdline
import ../../src/state/computed_finalization as state_computed_finalization
import ../../src/state/computed_execution as state_computed_execution
import ../../src/state/accumulation_driver as state_accumulation_driver
import ../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../src/codec/bounded as codec_bounded
import ../support/pvm_computed_finalization

proc expect[T](outcome: ComputedFinalizationResult[T], reason: ComputedFinalizationError) =
  ## Confirm exact alternatives before deliberately extracting absent values or unrelated child causes.
  assert outcome.error == reason, "computed finalization runtime control"
let source = finalizationFixture()
let config = computedFinalizationConfig()
let done = finalizeComputedAccumulation(source, config)
expect(done, ComputedFinalizationError.None)
assert done.value.computedFinalizationPlan.value.finalAccumulationInfo.value.pendingReports == 0
let invalid = finalizeComputedAccumulation(default(ExecutedComputedAccumulation), config)
expect(invalid, ComputedFinalizationError.InvalidSource)
var changed = config
changed.driver.preparation.selection.executions = ElementLimit(0)
let driver = finalizeComputedAccumulation(source, changed)
expect(driver, ComputedFinalizationError.DriverFailure)
assert driver.driverFailure.error == AccumulationDriverError.SelectionFailure
changed = config
changed.outputs.rounds = ElementLimit(1)
let history = finalizeComputedAccumulation(source, changed)
expect(history, ComputedFinalizationError.FinalizationFailure)
assert history.finalizationFailure.error == AccumulationFinalizationError.OutputFailure
let missing = default(ComputedFinalizationResult[FinalizedComputedAccumulation])
case paramStr(1)
of "default": discard missing.value # Default owns no stopped history or final map.
of "source": discard invalid.value # A loose/default execution supplies no authority.
of "driver": discard driver.value # Driver refusal exposes no successful prefix.
of "finalizer": discard history.value # Output refusal exposes no final state.
of "owner": discard default(FinalizedComputedAccumulation).computedFinalizationSource.value # No original computation.
of "stopped": discard default(FinalizedComputedAccumulation).computedFinalizationStopped.value # No certified stopped variant.
of "plan": discard default(FinalizedComputedAccumulation).computedFinalizationPlan.value # No prepared C(16) successor.
of "reason-driver-default": discard missing.driverFailure # Default contains no nested driver refusal.
of "reason-driver-success": discard done.driverFailure # Complete success contains no refusal.
of "reason-driver-finalizer": discard history.driverFailure # Finalizer failure cannot masquerade as a driver refusal.
of "reason-finalizer-default": discard missing.finalizationFailure # Default contains no nested finalizer refusal.
of "reason-finalizer-success": discard done.finalizationFailure # Complete success contains no output/root refusal.
else: discard driver.finalizationFailure # Driver failure carries no unrelated finalizer payload.
