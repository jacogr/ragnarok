# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine signed sources and actual assign execution prove original-pool/incoming-use/posterior-queue binding.

import std/assertions
import ../../src/state/accumulation/[authorization as accumulation_authorization,
    preimages as accumulation_preimages, activity as accumulation_activity,
    validators as accumulation_validators, times as accumulation_times,
    statistics as accumulation_statistics, consensus as accumulation_consensus,
    finalization as accumulation_finalization, outputs as accumulation_outputs,
    batch as accumulation_batch, context as accumulation_context, effects as accumulation_effects,
    dispatch as accumulation_dispatch, execution as accumulation_execution,
    round as accumulation_round, continuation as accumulation_continuation]
import ../../src/state/accumulation/continuation/[inputs as accumulation_continuation_inputs,
    execution as accumulation_continuation_execution]
import ../../src/state/[authorization, store]
import ../../src/codec/[bounded, assurances, report_owned]
import ../../src/codec/state/[authorization as state_authorization, outputs as state_outputs,
    layout as state_layout, trie as state_trie]
import ../../src/pvm/machine
import ../../src/chain/parameters
import ./[report_context, block_activity_context, accumulation_execution_context,
  pvm_accumulation_context, pvm_accumulation_program]

type AuthorizationFixture* = object ## Authored original entries and genuine terminal owner support independent complete-map expectations.
  finalized*: PreparedFinalAccumulation
  entries*: seq[StateEntry]
proc assignProgram(): seq[byte] =
  ## The full 2560-byte queue is read from mapped zero-padded RW memory; slot two has independently varied literal bytes.
  var payload = newSeq[byte](96)
  for index in 64..<96: payload[index] = byte(index-63)
  result = @[0'u8]
  let code = guestEnvelope([registerImmediate(7, 0), registerImmediate(8, 196608),
    registerImmediate(9, 42), @[10'u8, 17], @[50'u8, 0]], writable = payload)
  for octet in code: result.add(octet)
proc managerProgram(): seq[byte] =
  ## The signed manager guest hands off its role and removes both original allowances without changing queues.
  let code = guestEnvelope([registerImmediate(7, 99), registerImmediate(8, 196608),
    registerImmediate(9, 17), registerImmediate(10, 23), registerImmediate(11, 196608),
    registerImmediate(12, 0), @[10'u8, 16], @[50'u8, 0]],
    writable = @[42'u8, 0, 0, 0, 99, 0, 0, 0])
  result = @[0'u8]
  for octet in code: result.add(octet) # Stored service code retains the empty metadata prefix.
proc assignParameters(): Parameters =
  ## Real assign validates both chain core count and the pinned eighty-member queue length.
  var bytes = encodeParameters(pvmParameters())
  bytes[24] = 2
  bytes[25] = 0
  bytes[82] = 80
  bytes[83] = 0
  decodeParameters(bytes).value
proc checkAssignPublication*(base: OwnedReport) =
  ## Real assign requires explicit batch quotas and publishes its queue with the selected assigner while preserving original source state.
  var executionOptions0 = executionFixtureConfig()
  executionOptions0.firstProgram = assignProgram()
  executionOptions0.signed.reports = 1
  executionOptions0.assigner = 42
  executionOptions0.signed.refinementGas = 11
  executionOptions0.signed.extra = @[blockPrior()]
  let fixture = executionFixture(blockTemplate(base), executionOptions0)
  let prior = fixture.state.snapshot.value
  let first = executionGuest(fixture, 0, parameters = assignParameters(),
      copyLimit = MemoryByteLimit(2560))
  assert first.error == AccumulationDispatchError.None
  let selected = first.effects.effectContext(AccumulationDimension.Regular).value.effectAccounts.value
  let queue = selected.lookup(chapterKey(StateChapter(2))).value.bytes
  assert queue != prior.lookup(chapterKey(StateChapter(2))).value.bytes
  for index in 0..<queue.len:
    assert queue[index] == (if index >= 64 and index < 96: byte(index-63) else: 0'u8)
  let second = executionGuest(fixture, 1)
  let refused = completeBlockAccumulation(fixture.round, [first, second], [], executionLimits())
  assert refused.error == AccumulationExecutionError.BatchFailure
  assert refused.batchFailure.error == AccumulationBatchError.LimitExceeded
  var enabled = executionLimits()
  enabled.batch.assignCores = ElementLimit(2)
  enabled.batch.assignBytes = ByteLimit(10000)
  let completed = completeBlockAccumulation(fixture.round, [first, second], [], enabled).value
  var published = fixture.state
  let snapshot = applyAccumulationBatch(published, completed.executionBatch.value).value
  assert snapshot.lookup(chapterKey(StateChapter(2))).value.bytes == queue
  assert sameStateSnapshot(fixture.state.snapshot.value,
      prior) # Private publication never mutates the original signed source.
proc authorizationFixture*(base: OwnedReport, guarantees, copies: int,
    empty = false, assigned = false, managed = false): AuthorizationFixture =
  ## Execute one genuine initial round, then certify the stopped continuation without replaying any effects.
  let program = if assigned: assignProgram() elif managed: managerProgram() else: newSeq[byte]()
  var executionOptions1 = executionFixtureConfig()
  executionOptions1.empty = empty
  executionOptions1.firstProgram = program
  executionOptions1.signed.reports = guarantees
  executionOptions1.signed.poolCopies = copies
  executionOptions1.signed.refinementGas = 11
  executionOptions1.assigner = 42
  executionOptions1.manager = (if managed: 42'u32 else: 0'u32)
  executionOptions1.signed.extra = @[blockPrior()]
  let fixture = executionFixture(blockTemplate(base), executionOptions1)
  var runs: seq[AccumulationDispatchResult] = @[]
  if not empty:
    let params = if assigned or managed: assignParameters() else: pvmParameters()
    runs.add(executionGuest(fixture, 0, parameters = params, copyLimit = MemoryByteLimit(
        if assigned: 2560'u64 else: 32'u64)))
    runs.add(executionGuest(fixture, 1)) # Both services execute maintained ordinary halt paths.
  var enabled = executionLimits()
  if assigned or managed:
    enabled.batch.assignCores = ElementLimit(2)
    enabled.batch.assignBytes = ByteLimit(10000) # The signed source includes its original always-accumulate dictionary.
  if managed:
    enabled.batch.managerEntries = ElementLimit(2)
    enabled.batch.managerBytes = ByteLimit(66) # Original two-entry C(12) plus selected empty-dictionary C(12).
  let completed = completeBlockAccumulation(fixture.round, runs, [], enabled).value
  let continuation = planAccumulationContinuation(completed,
    AccumulationContinuationLimits(executions: ElementLimit(2), reports: ElementLimit(4),
        digests: ElementLimit(8))).value
  let config = executionRoundConfig()
  let context = prepareAccumulationContinuationInputs(continuation,
    AccumulationContinuationInputConfig(operands: config.operands, inputs: config.inputs)).value
  assert not context.continuationPlan.value.continuationInfo.value.dispatch
  let stopped = completeAccumulationContinuation(context, [], [], executionLimits()).value
  let finalized = prepareFinalAccumulation(stopped, AccumulationOutputHistoryLimits(
    rounds: ElementLimit(2), executions: ElementLimit(2), log: OutputLogConfig(items: ElementLimit(
        0), maxBytes: ByteLimit(1)))).value
  AuthorizationFixture(finalized: finalized, entries: fixture.entries)
proc checkBlockAuthorization*(source: PreparedAccumulationConsensus,
    guarantees, copies: int, assigned = false, managed = false) =
  ## Literal C(1) expectations distinguish original guaranteed uses from actual posterior assign/manager effects.
  let plan = source.accumulationConsensusSource.value
  let state = source.accumulationConsensusState.value
  let info = plan.accumulationAuthorizationInfo.value
  assert info.guarantees == guarantees and uint32(info.slot) == 2
  let poolKey = chapterKey(StateChapter(1))
  let queueKey = chapterKey(StateChapter(2))
  let original = plan.accumulationAuthorizationSource.value.accumulationPreimagesSource.value.accumulationActivitySource.value.accumulationValidatorsSource.value.accumulationTimesStatistics.value.statisticsSource.value.finalAccumulationParent.value
  let pools = decodeAuthorization(AuthorizationKind.Pools, original.lookup(poolKey).value.bytes,
    AuthorizationConfig(cores: CoreCount(2), maxHashes: ElementLimit(160), maxBytes: ByteLimit(
        10000))).value.snapshot
  let authorizer = pools.authorizerAt(AuthorizationCoreIndex(0), AuthorizationIndex(0)).value
  var expected: seq[byte] = @[]
  for core in 0..<2:
    let retained = min(7, copies-(if core < guarantees: 1 else: 0))
    expected.add(byte(retained+1))
    for occurrence in 0..<retained:
      for octet in authorizer.bytes: expected.add(octet) # Each duplicate remains in original order.
    for index in 0..<32:
      expected.add(if assigned and core == 0: byte(index+1) else: 0'u8) # Literal slot-two assign payload.
  assert state.lookup(poolKey).value.bytes == expected
  assert plan.accumulationAuthorizationEntry.value.value == expected
  let queues = state.lookup(queueKey).value.bytes
  assert queues.len == 5120
  if assigned:
    for index in 0..<queues.len:
      assert queues[index] == (if index >= 64 and index < 96: byte(index-63) else: 0'u8)
  else:
    assert queues == original.lookup(queueKey).value.bytes # No selected assign preserves the original queue.
  if managed:
    assert state.lookup(chapterKey(StateChapter(12))).value.bytes ==
      @[99'u8, 0, 0, 0, 42, 0, 0, 0, 99, 0, 0, 0, 17, 0, 0, 0, 23, 0, 0, 0, 0]
