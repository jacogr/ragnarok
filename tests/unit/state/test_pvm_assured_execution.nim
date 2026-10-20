# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_assured_execution_arc_release"}

## Genuine assured inputs execute together under original gas while complete source and selected storage authority survive.

import std/[assertions, syncio]
import ../../../src/state/[assured_execution, assured_queue, computed_assurances,
  accumulation_execution, accumulation_round, accumulation_inputs, accumulation_queue,
  accumulation_runner, accumulation_batch, accumulation_provisions, accumulation_outcome,
  accumulation_effects, accumulation_context, accumulation_dispatch, report_admission,
  block_transition, block_admission, store]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, work_digest, state_accounts, state_service_values, state_layout,
  composite, c2_records, report_owned]
import ../../../src/pvm/step
import ../../support/[pvm_assured_execution, arc_evidence]

proc expect[T](outcome: AssuredExecutionResult[T], reason: AssuredExecutionError) =
  ## Keep unexpected originating phase diagnostics actionable without accepting another alternative.
  if outcome.error != reason:
    echo "expected ", reason, " got ", outcome.error
    if outcome.error == AssuredExecutionError.RoundFailure: echo "round ",
        outcome.roundFailure.error
    if outcome.error == AssuredExecutionError.RunnerFailure:
      let runner = outcome.runnerFailure
      echo "runner ", runner.error
      if runner.error == AccumulationRunnerError.ContextFailure: echo "context ",
          runner.contextError
      if runner.error == AccumulationRunnerError.DispatchFailure: echo "dispatch ",
          runner.dispatchFailure.error
      if runner.error == AccumulationRunnerError.CompletionFailure: echo "completion ",
          runner.completionFailure.error
  assert outcome.error == reason, "assured execution reason"
proc metadata(state: StateStoreSnapshot): ServiceMetadata =
  ## Decode the exact account rather than inferring storage effects from equal roots.
  decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      42))).value.bytes, ByteLimit(89)).value.metadata
proc storage(state: StateStoreSnapshot) =
  ## Independently check guest bytes and the existing single-key footprint.
  let key = serviceStorageKey(ServiceIndex(42), @[11'u8], ByteLimit(1)).value
  assert state.lookup(key).value.bytes == @[21'u8, 22, 23]
  assert uint32(metadata(state).storageItems) == 1 and uint64(metadata(state).storageBytes) == 38
let source = assuredExecutionFixture()
let config = assuredExecutionConfig(source)
let original = source.assuredQueueAdmission.value.reportBlockStage.value.value.admitted.admittedState
storage(original)
assert uint32(metadata(original).lastAccumulation) == 2
let outcome = executeAssuredAccumulation(source, config)
expect(outcome, AssuredExecutionError.None)
let done = outcome.value
let completed = done.assuredExecutionCompleted.value
let info = completed.executionInfo.value
assert info.services == 1 and info.batch.executions == 1 and info.batch.skipped == 0
assert info.batch.completeInputs and info.batch.selfWrites == 1 and info.batch.selfValueBytes == 3
assert info.batch.assignmentWrites == 0 and info.batch.stagingWrites == 0
assert info.batch.createdAccounts == 0 and info.batch.deletedAccounts == 0
assert uint64(info.round.prefix) == 2 and uint64(info.round.reportGas) == 20000
assert uint64(info.round.budget) == 1000000 and uint64(info.round.allowanceGas) == 0
assert uint64(info.gasUsed) > 0 and uint64(info.gasUsed) < 20000
let inputs = completed.executionRound.value.roundProjection.value.roundInputs.value
assert inputs.invocationServiceCount.value == 1
let service = inputs.invocationServiceAt(InvocationServiceIndex(0)).value
assert uint32(service.service) == 42 and service.operands == 2 and service.transfers == 0 and
    uint64(service.gas) == 20000
for index in 0..<2:
  assert inputs.invocationInputAt(InvocationServiceIndex(0), InvocationInputIndex(uint64(
      index))).value.kind ==
      AccumulationKind.Operand # Both distinct reports reach the same actual service invocation.
for index in 0..<2:
  let input = inputs.invocationInputAt(InvocationServiceIndex(0), InvocationInputIndex(uint64(
      index))).value.operand.operandInfo.value
  let report = source.assuredQueuePlan.value.accumulationProjection.value.accumulationAt(
      AccumulationIndex(uint64(index))).value.ownedReportInfo.value
  assert input.packageHash.bytes == report.header.packageHash.bytes # Preserve original priority order and both distinct package identities in actual invocation inputs.
let terminal = completed.executionBatch.value.batchOutcomeAt(AccumulationProvisionSourceIndex(0)).value
assert terminal.outcomeInfo.value.termination == AccumulationTermination.Halt
assert not terminal.outcomeInfo.value.hasYield
assert terminal.outcomeInfo.value.transfers == 0 and terminal.outcomeInfo.value.provisions == 0
let selected = terminal.outcomeContext.value.effectAccounts.value
storage(selected)
assert uint64(metadata(selected).balance) == 50
assert uint32(metadata(selected).lastAccumulation) == 2, "timestamp belongs to later finalization"
assert array[32, byte](metadata(selected).codeHash) == array[32, byte](metadata(original).codeHash)
let usage = completed.executionGasAt(InvocationServiceIndex(0)).value
assert uint32(usage.service) == 42 and uint64(usage.gasUsed) == uint64(info.gasUsed)
let retained = completed.executionRound.value.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedState
assert sameStateSnapshot(retained, original)
assert sameStateSnapshot(done.assuredExecutionSource.value.assuredQueueAdmission.value.reportBlockStage.value.value.admitted.admittedState, original)
for field in low(Parameter)..high(Parameter):
  assert done.assuredExecutionParameters.value.get(field) ==
      source.assuredQueueParameters.value.get(
      field) # Whole original parameter authority survives execution unchanged.
let emptySource = assuredExecutionFixture(votes = 6)
let empty = executeAssuredAccumulation(emptySource, assuredExecutionConfig(emptySource))
expect(empty, AssuredExecutionError.None)
let emptyInfo = empty.value.assuredExecutionCompleted.value.executionInfo.value
assert emptyInfo.services == 0 and emptyInfo.batch.executions == 0 and
    emptyInfo.batch.completeInputs
assert uint64(emptyInfo.gasUsed) == 0 and uint64(emptyInfo.round.prefix) == 0
expect(executeAssuredAccumulation(default(AssuredAccumulationQueue), config),
    AssuredExecutionError.InvalidSource)
var short = config
short.round.reportGas = Gas(99999)
expect(executeAssuredAccumulation(source, short), AssuredExecutionError.ProfileMismatch)
short = config
short.round.blockGas = Gas(999999)
expect(executeAssuredAccumulation(source, short), AssuredExecutionError.ProfileMismatch)
short = config
short.round.operands.reports = ElementLimit(1)
let roundLimit = executeAssuredAccumulation(source, short)
expect(roundLimit, AssuredExecutionError.RoundFailure)
assert roundLimit.roundFailure.error == AccumulationRoundError.LimitExceeded
short = config
short.round.privileges.cores = typeof(short.round.privileges.cores)(2)
let domains = executeAssuredAccumulation(source, short)
expect(domains, AssuredExecutionError.RoundFailure)
assert domains.roundFailure.error == AccumulationRoundError.InvalidConfig
short = config
short.runner.completion.services = ElementLimit(0)
let services = executeAssuredAccumulation(source, short)
expect(services, AssuredExecutionError.RunnerFailure)
assert services.runnerFailure.error == AccumulationRunnerError.LimitExceeded
short = config
short.runner.contexts.validators = typeof(short.runner.contexts.validators)(8)
let badParameters = executeAssuredAccumulation(source, short)
expect(badParameters, AssuredExecutionError.RunnerFailure)
assert badParameters.runnerFailure.error == AccumulationRunnerError.InvalidParameters
short = config
short.runner.fetch.items = ElementLimit(1)
let fetch = executeAssuredAccumulation(source, short)
expect(fetch, AssuredExecutionError.RunnerFailure)
assert fetch.runnerFailure.error == AccumulationRunnerError.DispatchFailure
assert fetch.runnerFailure.dispatchFailure.error == AccumulationDispatchError.LimitExceeded
short = config
short.runner.steps = typeof(short.runner.steps)(0)
let steps = executeAssuredAccumulation(source, short)
expect(steps, AssuredExecutionError.RunnerFailure)
assert steps.runnerFailure.error == AccumulationRunnerError.DispatchFailure
assert steps.runnerFailure.dispatchFailure.executionError == StepError.StepLimitExceeded
for policy in 0..<3:
  short = config
  case policy
  of 0: short.runner.accountWriteKeys = ElementLimit(
      0) # A root-identical guest write still requires provenance before completion.
  of 1: short.runner.completion.batch.selfWrites = ElementLimit(
      0) # The copied unique key remains independently bounded.
  else: short.runner.completion.batch.selfValueBytes = ByteLimit(
      2) # Three real final bytes exceed this limit by one.
  let effects = executeAssuredAccumulation(source, short)
  expect(effects, AssuredExecutionError.RunnerFailure)
  assert effects.runnerFailure.error == AccumulationRunnerError.CompletionFailure
  assert effects.runnerFailure.completionFailure.error == AccumulationExecutionError.BatchFailure
  let expected = if policy == 0: AccumulationBatchError.UnsupportedAccountEffects else: AccumulationBatchError.LimitExceeded
  assert effects.runnerFailure.completionFailure.batchFailure.error == expected
  assert sameStateSnapshot(source.assuredQueueAdmission.value.reportBlockStage.value.value.admitted.admittedState, original)
  storage(original)
expect(default(ExecutedAssuredAccumulation).assuredExecutionSource,
    AssuredExecutionError.Uninitialized)
expect(default(ExecutedAssuredAccumulation).assuredExecutionCompleted,
    AssuredExecutionError.Uninitialized)
expect(default(ExecutedAssuredAccumulation).assuredExecutionParameters,
    AssuredExecutionError.Uninitialized)
var copied = done.assuredExecutionCompleted.value
copied = default(CompletedBlockAccumulation)
var copiedParams = done.assuredExecutionParameters.value
copiedParams = default(Parameters)
assert done.assuredExecutionCompleted.value.executionInfo.value.batch.executions == 1
assert done.assuredExecutionParameters.value == source.assuredQueueParameters.value
proc detached(): ExecutedAssuredAccumulation =
  ## Retain source, actual round and complete engine owner after all caller fixture/policy handles retire.
  let source = assuredExecutionFixture()
  executeAssuredAccumulation(source, assuredExecutionConfig(source)).value
let held = detached()
storage(held.assuredExecutionCompleted.value.executionBatch.value.batchOutcomeAt(
    AccumulationProvisionSourceIndex(0)).value.outcomeContext.value.effectAccounts.value)
proc cycle(source: AssuredAccumulationQueue, config: AssuredExecutionConfig) =
  ## Release real successful execution and a late completion refusal after all guest work has run.
  let done = executeAssuredAccumulation(source, config).value
  discard done.assuredExecutionSource.value
  discard done.assuredExecutionCompleted.value.executionInfo.value
  var short = config
  short.runner.completion.batch.selfValueBytes = ByteLimit(2)
  expect(executeAssuredAccumulation(source, short), AssuredExecutionError.RunnerFailure)
cycle(source, config)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(source, config) # Both reports feed actual guest execution and all failed effects retire each cycle.
let after = getOccupiedMem()
assert before == after, "assured execution ARC release"
recordArcRelease("pvm_assured_execution", 1000, before, after)
echo "PVM assured execution passed"
echo "ARC_RELEASE cycles=1000 unchanged"
