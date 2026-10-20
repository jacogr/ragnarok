# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine signed sources and actual assign execution prove original-pool/incoming-use/posterior-queue binding.

import std/assertions
import ../../src/state/[block_authorization, block_preimages, accumulation_finalization,
  accumulation_outputs, accumulation_batch, accumulation_context, accumulation_effects,
  accumulation_dispatch,
  accumulation_execution, accumulation_round,
  accumulation_continuation,
  accumulation_continuation_inputs, accumulation_continuation_execution, authorization, store]
import ../../src/codec/[bounded, assurances, report_owned, state_authorization, state_outputs,
    state_layout, state_trie]
import ../../src/pvm/machine
import ../../src/chain/parameters
import ./[report_context, block_activity_context, accumulation_execution_context,
  pvm_accumulation_context, pvm_accumulation_program]

type AuthorizationFixture* = object ## Authored original entries and genuine terminal owner support independent complete-map expectations.
  finalized*: PreparedFinalAccumulation
  entries*: seq[StateEntry]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
proc blockAuthorizationPolicy*(): BlockAuthorizationConfig =
  ## Input queue capture bounds all 160 hashes separately from incoming guarantee descriptors.
  BlockAuthorizationConfig(guarantees: ElementLimit(2), authorization: AuthorizationConfig(
    cores: CoreCount(2), maxHashes: ElementLimit(160), maxBytes: ByteLimit(5120)))
proc assignProgram(): seq[byte] =
  ## The full 2560-byte queue is read from mapped zero-padded RW memory; slot two has independently varied literal bytes.
  var payload = newSeq[byte](96)
  for index in 64..<96: payload[index] = byte(index-63)
  result = @[0'u8]
  let code = guestEnvelope([registerImmediate(7, 0), registerImmediate(8, 196608),
    registerImmediate(9, 42), @[10'u8, 16], @[50'u8, 0]], writable = payload)
  for octet in code: result.add(octet)
proc assignParameters(): Parameters =
  ## Real assign validates both chain core count and the pinned eighty-member queue length.
  var bytes = encodeParameters(pvmParameters())
  bytes[24] = 2
  bytes[25] = 0
  bytes[82] = 80
  bytes[83] = 0
  decodeParameters(bytes).value
proc checkAssignPublicationGate*(base: OwnedReport) =
  ## Actual assign changes its private selected queue; the current batch boundary must refuse broader effects rather than lose them.
  let fixture = executionFixture(blockTemplate(base), firstProgram = assignProgram(),
    incomingReports = 1, assigner = 42, refinementGas = 11, extra = @[blockPrior()])
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
  assert refused.batchFailure.error == AccumulationBatchError.UnsupportedAccountEffects
  assert sameStateSnapshot(fixture.state.snapshot.value,
      prior) # No partial queue/account successor escapes the existing explicit gate.
proc authorizationFixture*(base: OwnedReport, guarantees, copies: int,
    empty = false): AuthorizationFixture =
  ## Execute one genuine initial round, then certify the stopped continuation without replaying any effects.
  let fixture = executionFixture(blockTemplate(base), empty = empty,
    incomingReports = guarantees, poolCopies = copies, refinementGas = 11, extra = @[blockPrior()])
  var runs: seq[AccumulationDispatchResult] = @[]
  if not empty:
    runs.add(executionGuest(fixture, 0))
    runs.add(executionGuest(fixture, 1)) # Both services execute maintained ordinary halt paths.
  let completed = completeBlockAccumulation(fixture.round, runs, [], executionLimits()).value
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
proc checkBlockAuthorization*(source: PublishedBlockPreimages, original: openArray[StateEntry],
    guarantees, copies: int): PublishedBlockAuthorization =
  ## Literal whole C(1) expectations distinguish incoming guaranteed cores from accumulated work and use actual posterior C(2).
  let prior = source.publishedPreimageState.value
  let poolKey = chapterKey(StateChapter(1))
  let queueKey = chapterKey(StateChapter(2))
  let originalPools = decodeAuthorization(AuthorizationKind.Pools,
    prior.lookup(poolKey).value.bytes, blockAuthorizationPolicy().authorization).value.snapshot
  let authorizer = originalPools.authorizerAt(AuthorizationCoreIndex(0), AuthorizationIndex(0)).value
  var expected: seq[byte] = @[]
  for core in 0..<2:
    let retained = min(7, copies-(if core < guarantees: 1 else: 0))
    expected.add(byte(retained+1)) # Each tiny count is one canonical natural octet.
    for occurrence in 0..<retained:
      for octet in authorizer.bytes: expected.add(octet)
    for index in 0..<32: expected.add(0'u8) # These completed sources retain their original all-zero posterior queues.
  var parentQueue: seq[byte] = @[]
  for record in original:
    if array[31, byte](record.key) == array[31, byte](queueKey): parentQueue = record.value
  let queues = prior.lookup(queueKey).value.bytes
  assert parentQueue.len == 5120 and queues.len == 5120
  assert queues == parentQueue # Broader assign effects remain explicitly gated before this completed source can be constructed.
  failHash(3)
  let plan = prepareBlockAuthorization(source, blockAuthorizationPolicy()).value
  let info = plan.blockAuthorizationInfo.value
  assert info.cores == 2 and info.guarantees == guarantees and uint32(info.slot) == 2
  assert plan.blockAuthorizationEntry.value.value == expected
  assert sameStateSnapshot(plan.blockAuthorizationPrior.value, prior)
  assert sameStateSnapshot(plan.blockAuthorizationSource.value.publishedPreimageState.value, prior)
  var exact = blockAuthorizationPolicy()
  exact.guarantees = ElementLimit(uint64(guarantees))
  assert prepareBlockAuthorization(source, exact).error == BlockAuthorizationError.None
  if guarantees > 0:
    var short = exact
    short.guarantees = ElementLimit(uint64(guarantees-1))
    assert prepareBlockAuthorization(source, short).error == BlockAuthorizationError.LimitExceeded
  var short = exact
  short.authorization.maxBytes = ByteLimit(5119)
  assert prepareBlockAuthorization(source, short).error == BlockAuthorizationError.LimitExceeded
  short = exact
  short.authorization.maxHashes = ElementLimit(159)
  let refused = prepareBlockAuthorization(source, short)
  assert refused.error == BlockAuthorizationError.CodecFailure and refused.codecError ==
      AuthorizationError.LimitExceeded
  short = exact
  short.authorization.cores = CoreCount(3)
  assert prepareBlockAuthorization(source, short).error == BlockAuthorizationError.InvalidConfig
  assert hashCalls() == 0 # Preparation, including bounded decoding and pool planning, has no hash or state write work.
  failHash(0)
  var wide = exact
  wide.guarantees = ElementLimit(high(uint64))
  wide.authorization.maxBytes = ByteLimit(high(uint64))
  wide.authorization.maxHashes = ElementLimit(high(uint64))
  assert prepareBlockAuthorization(source, wide).value.blockAuthorizationEntry.value.value == expected
  var copied = plan.blockAuthorizationEntry.value
  copied.value[0] = 0
  assert plan.blockAuthorizationEntry.value.value == expected
  var observed = plan.blockAuthorizationInfo.value
  observed.guarantees = 999
  assert plan.blockAuthorizationInfo.value.guarantees == guarantees
  var entries: seq[StateEntry] = @[]
  for record in original: entries.add(StateEntry(key: record.key, value: prior.lookup(
      record.key).value.bytes))
  let log = chapterKey(StateChapter(16))
  entries.add(StateEntry(key: log, value: prior.lookup(log).value.bytes))
  assert entries.len == prior.commitment.entries
  var foreign = newStateStore(entries, report_context.limits()).value
  failHash(3)
  assert advanceBlockAuthorization(foreign, plan).error == BlockAuthorizationError.ForeignState
  var invalid = default(StateStore)
  assert advanceBlockAuthorization(invalid, plan).error == BlockAuthorizationError.InvalidState
  assert hashCalls() == 0
  failHash(0)
  for successful in [0, 2]:
    var caller = forkStateStore(prior).value
    hashAfter(cint(successful))
    let refused = advanceBlockAuthorization(caller, plan)
    assert refused.error == BlockAuthorizationError.StateFailure and refused.stateError ==
        StateStoreError.BackendFailure
    failHash(0)
    assert sameStateSnapshot(caller.snapshot.value, prior)
  for index in 0..<entries.len:
    if array[31, byte](entries[index].key) == array[31, byte](poolKey): entries[
        index].value = expected
  let wanted = stateTrieRoot(entries, report_context.limits().trie).value
  let published = publishBlockAuthorization(plan).value
  let posterior = published.publishedAuthorizationState.value
  assert array[32, byte](posterior.commitment.root) == array[32, byte](wanted.root)
  assert posterior.commitment.entries == entries.len
  for record in entries: assert posterior.lookup(record.key).value.bytes == record.value
  var caller = forkStateStore(prior).value
  let advanced = advanceBlockAuthorization(caller, plan).value
  assert sameStateSnapshot(caller.snapshot.value, advanced.publishedAuthorizationState.value)
  failHash(3)
  assert advanceBlockAuthorization(caller, plan).error == BlockAuthorizationError.ForeignState
  assert hashCalls() == 0
  failHash(0)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareBlockAuthorization(source, exact).value
    let committed = publishBlockAuthorization(local).value
    assert committed.publishedAuthorizationState.value.lookup(poolKey).value.bytes == expected
  assert before == getOccupiedMem() # Source handles, decoded queues, planning scratch and complete successors retire each cycle.
  assert sameStateSnapshot(source.publishedPreimageState.value, prior)
  assert publishBlockAuthorization(default(PreparedBlockAuthorization)).error ==
      BlockAuthorizationError.InvalidSource
  assert prepareBlockAuthorization(default(PublishedBlockPreimages), exact).error ==
      BlockAuthorizationError.InvalidSource
  published
