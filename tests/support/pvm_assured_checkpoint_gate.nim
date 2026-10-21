# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real original guests reach the scalar wrapping gate after checkpointing; local refusal has no publishable successor.

import std/assertions
import ../../src/state/[assured_execution, accumulation_runner, accumulation_dispatch,
  accumulation_execution, accumulation_batch, accumulation_provisions, accumulation_outcome,
  accumulation_round, accumulation_inputs, accumulation_effects, accumulation_context, store]
import ../../src/chain/provider
import ../../src/codec/[bounded, state_layout, state_service_values]
import ../../src/pvm/[machine, step]
import ./[pvm_assured_outcomes, pvm_computed_storage_program, pvm_assured_execution,
  pvm_assured_composition, arc_evidence]

proc config(fixture: AssuredOutcomeFixture): AssuredExecutionConfig =
  ## Admit every prior real host, instruction and provenance entry without assigning protocol semantics to the disputed access.
  result = assuredExecutionConfig(fixture.queue)
  result.runner.steps = ExecutionStepLimit(28)
  result.runner.calls = HostCallLimit(5)
  result.runner.copyBytes = MemoryByteLimit(11)
  result.runner.completion.batch.selfValueBytes = ByteLimit(0)
proc refused(fixture: AssuredOutcomeFixture, policy: AssuredExecutionConfig, reason: StepError) =
  ## Require the precise local execution reason; a normalized guest panic would instead succeed and fail these assertions.
  let outcome = executeAssuredAccumulation(fixture.queue, policy)
  assert outcome.error == AssuredExecutionError.RunnerFailure
  assert outcome.runnerFailure.error == AccumulationRunnerError.DispatchFailure
  assert outcome.runnerFailure.dispatchFailure.error == AccumulationDispatchError.ExecutionFailure
  assert outcome.runnerFailure.dispatchFailure.executionError == reason
proc storage(state: StateStoreSnapshot) =
  ## Keep the genuine original committed value; neither deletion checkpoint nor later regular restoration may publish on refusal.
  let key = serviceStorageKey(ServiceIndex(42), @[11'u8], ByteLimit(1)).value
  let found = state.lookup(key)
  assert found.error == StateStoreError.None
  assert found.value.bytes == @[1'u8, 22, 23, 255, 255, 255, 255, 255, 255, 255, 255]
proc verifyCheckpointWrappingGate*(mode: ComputedStorageMode, evidenceName: string) =
  ## Verify the original successful control, exact pre-gate limits, atomic refusal and one thousand failed owned invocation releases.
  assert mode in {ComputedStorageMode.ReadCheckpointWrapLoad,
      ComputedStorageMode.ReadCheckpointWrapStore}
  let fixture = assuredOutcomeFixture(mode)
  let original = fixture.state.snapshot.value
  let oldView = fixture.view
  let first = fixture.first.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value
  assert first.outcomeInfo.value.termination == AccumulationTermination.Halt
  assert first.outcomeInfo.value.dimension == AccumulationDimension.Regular
  assert fixture.first.executionRound.value.roundProjection.value.roundInputs.value.invocationServiceAt(
    InvocationServiceIndex(0)).value.operands == 1
  storage(original)
  storage(first.outcomeContext.value.effectAccounts.value)
  let policy = config(fixture)
  refused(fixture, policy, StepError.AmbiguousAccessOrder)
  var short = policy
  short.runner.steps = ExecutionStepLimit(27)
  refused(fixture, short, StepError.StepLimitExceeded)
  for ceiling in 3..4:
    # The read and restoration must actually execute before the later scalar gate is reached.
    short = policy
    short.runner.calls = HostCallLimit(ceiling)
    refused(fixture, short, StepError.HostCallLimitExceeded)
  short = policy
  short.runner.copyBytes = MemoryByteLimit(10)
  let copy = executeAssuredAccumulation(fixture.queue, short)
  assert copy.error == AssuredExecutionError.RunnerFailure
  assert copy.runnerFailure.error == AccumulationRunnerError.DispatchFailure
  assert copy.runnerFailure.dispatchFailure.error == AccumulationDispatchError.LimitExceeded
  refused(fixture, policy, StepError.AmbiguousAccessOrder)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Each actual refused invocation retires its fetched input, checkpoint, regular restoration, CPU and memory owners.
    refused(fixture, policy, StepError.AmbiguousAccessOrder)
  let after = getOccupiedMem()
  assert before == after, "checkpoint wrapping gate ARC release"
  assert sameStateSnapshot(fixture.state.snapshot.value, original)
  assert sameChainView(fixture.view, oldView)
  storage(original)
  recordArcRelease(evidenceName, 1000, before, after)
