# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict composed successor result guards with genuine success and selected driver/finalizer/composition refusals.

import std/[assertions, cmdline]
import ../../src/state/[assured_composition, assured_execution, accumulation_consensus,
  accumulation_driver, accumulation_finalization, accumulation_completion]
import ../../src/codec/bounded
import ../support/pvm_assured_composition

proc expect[T](outcome: AssuredCompositionResult[T], reason: AssuredCompositionError) =
  ## Check exact alternatives without statically contradicting deliberately unsafe later extraction.
  assert outcome.error == reason, "assured composition runtime control"
let source = assuredCompositionFixture()
let config = assuredCompositionConfig()
let done = composeAssuredState(source, config)
expect(done, AssuredCompositionError.None)
assert done.value.assuredCompositionPlan.value.accumulationConsensusInfo.value.chapters == 7
let invalid = composeAssuredState(default(ExecutedAssuredAccumulation), config)
expect(invalid, AssuredCompositionError.InvalidSource)
var changed = config
changed.driver.preparation.selection.executions = ElementLimit(0)
let driver = composeAssuredState(source, changed)
expect(driver, AssuredCompositionError.DriverFailure)
assert driver.driverFailure.error == AccumulationDriverError.SelectionFailure
changed = config
changed.outputs.rounds = ElementLimit(1)
let finalization = composeAssuredState(source, changed)
expect(finalization, AssuredCompositionError.FinalizationFailure)
assert finalization.finalizationFailure.error == AccumulationFinalizationError.OutputFailure
changed = config
changed.composition.consensus.chapterBytes = ByteLimit(0)
let composition = composeAssuredState(source, changed)
expect(composition, AssuredCompositionError.CompositionFailure)
assert composition.compositionFailure.error == AccumulationCompletionError.ConsensusFailure
let missing = default(AssuredCompositionResult[ComposedAssuredState])
case paramStr(1)
of "default": discard missing.value # Only complete success or its selected refused phase permits extraction.
of "source": discard invalid.value # Only complete success or its selected refused phase permits extraction.
of "driver": discard driver.value # Only complete success or its selected refused phase permits extraction.
of "finalization": discard finalization.value # Only complete success or its selected refused phase permits extraction.
of "composition": discard composition.value # Only complete success or its selected refused phase permits extraction.
of "owner": discard default(ComposedAssuredState).assuredCompositionSource.value # Only complete success or its selected refused phase permits extraction.
of "stopped": discard default(ComposedAssuredState).assuredCompositionStopped.value # Only complete success or its selected refused phase permits extraction.
of "final": discard default(ComposedAssuredState).assuredCompositionFinal.value # Only complete success or its selected refused phase permits extraction.
of "plan": discard default(ComposedAssuredState).assuredCompositionPlan.value # Only complete success or its selected refused phase permits extraction.
of "parameters": discard default(ComposedAssuredState).assuredCompositionParameters.value # Only complete success or its selected refused phase permits extraction.
of "driverFailure-default": discard missing.driverFailure # Only complete success or its selected refused phase permits extraction.
of "driverFailure-success": discard done.driverFailure # Only complete success or its selected refused phase permits extraction.
of "driverFailure-source": discard invalid.driverFailure # Only complete success or its selected refused phase permits extraction.
of "driverFailure-finalization": discard finalization.driverFailure # Only complete success or its selected refused phase permits extraction.
of "driverFailure-composition": discard composition.driverFailure # Only complete success or its selected refused phase permits extraction.
of "finalizationFailure-default": discard missing.finalizationFailure # Only complete success or its selected refused phase permits extraction.
of "finalizationFailure-success": discard done.finalizationFailure # Only complete success or its selected refused phase permits extraction.
of "finalizationFailure-source": discard invalid.finalizationFailure # Only complete success or its selected refused phase permits extraction.
of "finalizationFailure-driver": discard driver.finalizationFailure # Only complete success or its selected refused phase permits extraction.
of "finalizationFailure-composition": discard composition.finalizationFailure # Only complete success or its selected refused phase permits extraction.
of "compositionFailure-default": discard missing.compositionFailure # Only complete success or its selected refused phase permits extraction.
of "compositionFailure-success": discard done.compositionFailure # Only complete success or its selected refused phase permits extraction.
of "compositionFailure-source": discard invalid.compositionFailure # Only complete success or its selected refused phase permits extraction.
of "compositionFailure-driver": discard driver.compositionFailure # Only complete success or its selected refused phase permits extraction.
of "compositionFailure-finalization": discard finalization.compositionFailure # Only complete success or its selected refused phase permits extraction.
else: discard invalid.value # Unknown modes never become passing controls.
