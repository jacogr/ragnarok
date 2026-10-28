# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_absent_account_outcomes_arc_release"}

## Real metadata absence and signed block authority prove identity before credit, zero execution and exact source lifetime.
import std/assertions
import std/envvars
import std/syncio
import ../../../src/state/accumulation_absent as state_accumulation_absent
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_service as state_accumulation_service
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_operands as state_accumulation_operands
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/header as codec_header
import ../../../src/codec/work_digest as codec_work_digest
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_privileges as codec_state_privileges
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_workqueues as codec_state_workqueues
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/c2_records as codec_c2_records
import ../../support/state_accumulation_batch_context
import ../../support/state_accumulation_provision_integration
import ../../support/state_report_admission_context
import ../../support/testing_arc_evidence
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc inputs(target: uint32, protected = false): PreparedAccumulationInputs =
  ## Huge offered gas and repeated maximum amounts are valid input fields; the absent branch must never sum balances.
  let operands = batchInputSet(false).invocationOperands.value
  prepareAccumulationInputs(operands,
    [DeferredTransfer(source: ServiceIndex(1), destination: ServiceIndex(target),
      amount: TransferBalance(high(uint64)), destinationSupervisor: protected),
     DeferredTransfer(source: ServiceIndex(2), destination: ServiceIndex(target),
      amount: TransferBalance(high(uint64)), destinationSupervisor: protected)],
    [AlwaysAccumulate(service: ServiceIndex(target), gas: PrivilegeGas(high(uint64)))],
    AccumulationInputConfig(inputs: ElementLimit(2), allowances: ElementLimit(1),
        services: ElementLimit(1))).value
proc state(): StateStore =
  ## A present account and unrelated chapter distinguish real absence from a default or empty state.
  newStateStore([serviceMetadataEntry(ServiceIndex(42), ServiceMetadata(balance: AccountBalance(10)),
    ByteLimit(ServiceMetadataBytes)).value,
    StateEntry(key: chapterKey(StateChapter(250)), value: @[9'u8, 8])], integrationStoreLimits()).value
proc projections(): AbsentAccumulation =
  ## Exact owners and zero effects survive extreme signed/unsigned domains without code lookup, credit or hashing.
  result = default(AbsentAccumulation)
  for target in [0'u32, 99'u32, high(uint32)]:
    for protected in [false, true]:
      let source = inputs(target, protected)
      var caller = state()
      let prior = caller.snapshot.value
      failHash(1)
      let absent = finishAbsentAccumulation(source, InvocationServiceIndex(0), prior, HeaderSlot(
          high(uint32))).value
      let info = absent.absentInfo.value
      assert uint32(info.service) == target and uint32(info.slot) == high(uint32)
      assert uint64(info.offeredGas) == high(uint64) and uint64(info.gasUsed) == 0
      assert info.incomingTransfers == 2 and info.operands == 0
      assert info.modifiedAccounts == 0 and info.transfers == 0 and info.provisions == 0 and
          not info.hasYield
      assert sameStateSnapshot(absent.absentState.value, prior), "absent state is exact input identity, never a precredited replacement"
      assert sameAccumulationInputs(absent.absentInputs.value, source) and uint64(
          absent.absentIndex.value) == 0
      let key = chapterServiceKey(StateChapter(255), ServiceIndex(target))
      assert absent.absentState.value.lookup(key).error == StateStoreError.MissingKey
      assert absent.absentState.value.lookup(chapterKey(StateChapter(250))).value.bytes == @[9'u8, 8]
      var copied = info
      copied.gasUsed = Gas(123)
      assert uint64(absent.absentInfo.value.gasUsed) == 0, "copied observations cannot change actual no-execution facts"
      assert hashCalls() == 0, "no hashing or incoming amount arithmetic is performed by absence certification"
      failHash(0)
      assert caller.apply([StateWrite(key: chapterKey(StateChapter(250)), kind: StateWriteKind.Put,
        value: @[7'u8])]).error == StateStoreError.None
      assert absent.absentState.value.lookup(chapterKey(StateChapter(250))).value.bytes == @[9'u8,
          8], "caller replacement cannot mutate retained identity"
      result = absent # Retain after caller/source construction scope releases.
proc boundaries() =
  ## Present metadata must follow ordinary service preparation, even when malformed; other sources retain exact typed refusal.
  let source = inputs(99)
  let prior = state().snapshot.value
  assert finishAbsentAccumulation(default(PreparedAccumulationInputs), InvocationServiceIndex(0), prior,
    HeaderSlot(0)).error == AccumulationAbsentError.InvalidInputs
  for index in [1'u64, high(uint64)]:
    assert finishAbsentAccumulation(source, InvocationServiceIndex(index), prior, HeaderSlot(
        0)).error ==
      AccumulationAbsentError.InvalidIndex, "full-width ordinal refusal precedes state lookup"
  assert finishAbsentAccumulation(source, InvocationServiceIndex(0), default(StateStoreSnapshot),
    HeaderSlot(0)).error == AccumulationAbsentError.InvalidState
  assert finishAbsentAccumulation(inputs(42), InvocationServiceIndex(0), prior, HeaderSlot(
      0)).error ==
    AccumulationAbsentError.AccountPresent
  let malformed = newStateStore([StateEntry(key: chapterServiceKey(StateChapter(255), ServiceIndex(99)),
    value: @[0'u8])], integrationStoreLimits()).value.snapshot.value
  assert finishAbsentAccumulation(source, InvocationServiceIndex(0), malformed, HeaderSlot(
      0)).error ==
    AccumulationAbsentError.AccountPresent, "malformed present metadata can never certify absence"
  assert prepareAccumulationService(source, InvocationServiceIndex(0), malformed, HeaderSlot(0),
    default(AccumulationServiceConfig)).error == AccumulationServiceError.MalformedAccount
  assert prepareAccumulationService(source, InvocationServiceIndex(0), prior, HeaderSlot(0),
    default(AccumulationServiceConfig)).error == AccumulationServiceError.MissingAccount, "normal service API remains a typed refusal, never a fabricated service"
  let pair = prepareAccumulationInputs(source.invocationOperands.value, [],
    [AlwaysAccumulate(service: ServiceIndex(42), gas: PrivilegeGas(0)),
     AlwaysAccumulate(service: ServiceIndex(99), gas: PrivilegeGas(1))],
    AccumulationInputConfig(allowances: ElementLimit(2), services: ElementLimit(2))).value
  let second = finishAbsentAccumulation(pair, InvocationServiceIndex(1), prior, HeaderSlot(0)).value
  assert uint32(second.absentInfo.value.service) == 99 and uint64(second.absentIndex.value) == 1,
    "retain the actual nonzero source ordinal, with genuine slot zero"
  let emptyInputs = prepareAccumulationInputs(source.invocationOperands.value, [], [], default(
      AccumulationInputConfig)).value
  assert finishAbsentAccumulation(emptyInputs, InvocationServiceIndex(0), prior, HeaderSlot(
      0)).error ==
    AccumulationAbsentError.InvalidIndex, "initialized empty inputs differ from default invalid input ownership"
  let absent = default(AbsentAccumulation)
  assert absent.absentInfo.error == AccumulationAbsentError.Uninitialized
  assert absent.absentState.error == AccumulationAbsentError.Uninitialized
  assert absent.absentInputs.error == AccumulationAbsentError.Uninitialized
  assert absent.absentIndex.error == AccumulationAbsentError.Uninitialized
  assert finishBlockAbsentAccumulation(default(BlockAccumulationRound), InvocationServiceIndex(
      0)).error ==
    AccumulationAbsentError.InvalidRound
  assert default(BlockAbsentAccumulation).absentBlockRound.error ==
      AccumulationAbsentError.Uninitialized
  assert default(BlockAbsentAccumulation).absentProjection.error ==
      AccumulationAbsentError.Uninitialized
proc roundConfig(): AccumulationRoundConfig =
  ## Keep report gas zero so a genuinely signed block selects only its unknown always-service allowance.
  AccumulationRoundConfig(blockGas: Gas(1), reportGas: Gas(0), privileges: PrivilegeConfig(
    cores: CoreCount(2), maxAlways: ElementLimit(10), maxBytes: ByteLimit(1000)),
    operands: AccumulationOperandConfig(reports: ElementLimit(10), operands: ElementLimit(100),
      services: ElementLimit(100), totalBytes: ByteLimit(1000000), totalBlobBytes: ByteLimit(
          1000000),
      operand: OperandLimits(outputBytes: ByteLimit(100000), authBytes: ByteLimit(100000),
        totalBlobBytes: ByteLimit(200000), maxBytes: ByteLimit(1000000))),
    inputs: AccumulationInputConfig(inputs: ElementLimit(100), allowances: ElementLimit(10),
        services: ElementLimit(100)))
proc queueConfig(): AccumulationQueueConfig =
  ## Retain the actual tiny signed queue profile without replacing report or block validity.
  AccumulationQueueConfig(queues: WorkQueueConfig(cores: CoreCount(2), epochSlots: EpochSlots(12),
    perSlot: ElementLimit(100), totalItems: ElementLimit(100), perDependencies: ElementLimit(100),
    totalDependencies: ElementLimit(1000), reportBytes: ByteLimit(100000), maxBytes: ByteLimit(
        1000000)),
    items: ElementLimit(100), dependencies: ElementLimit(1000))
proc boundCase(base: OwnedReport): BlockAbsentAccumulation =
  ## Only real signed admission/queue/round owners supply the absent service's parent, inputs and slot.
  let entry = privilegeStateEntry(PrivilegeState(assigners: newSeq[ServiceIndex](2),
    always: @[AlwaysAccumulate(service: ServiceIndex(99), gas: PrivilegeGas(1))]), roundConfig().privileges).value
  var options = signedBlockFixtureConfig()
  options.withAvailable = true
  options.extra = @[entry]
  let context = authored(base, options)
  let admitted = planBlockReports(context.staged, context.older, config()).value
  let queue = planBlockAccumulationQueue(admitted, queueConfig()).value
  let round = planBlockInitialAccumulation(queue, roundConfig()).value
  assert round.roundProjection.value.roundInputs.value.invocationServiceCount.value == 1,
    "the always allowance consumes the full budget, excluding report operands"
  failHash(1)
  let absent = finishBlockAbsentAccumulation(round, InvocationServiceIndex(0)).value
  let pure = absent.absentProjection.value
  assert uint32(pure.absentInfo.value.service) == 99 and uint32(pure.absentInfo.value.slot) == 2
  assert uint64(pure.absentInfo.value.offeredGas) == 1 and uint64(pure.absentInfo.value.gasUsed) == 0
  assert sameStateSnapshot(pure.absentState.value, context.original.snapshot.value), "genuine admitted parent identity"
  assert sameAccumulationInputs(pure.absentInputs.value,
      round.roundProjection.value.roundInputs.value)
  assert absent.absentBlockRound.value.roundBlockQueue.error == AccumulationRoundError.None
  assert hashCalls() == 0, "bound factory reads only genuine retained authority, never hashes or bootstraps a guest"
  failHash(0)
  absent
proc main() {.raises.} =
  ## Read the maintained prepared report fixture; every cryptographic admission remains production verification.
  let retained = projections()
  boundaries()
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index]) # Exact binary report transport.
  let bound = boundCase(decodeOwnedReport(bytes, 2).value)
  assert uint32(bound.absentProjection.value.absentInfo.value.service) == 99, "bound proof survives authoring scope release"
  let inputs = retained.absentInputs.value
  let prior = retained.absentState.value
  let slot = retained.absentInfo.value.slot
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let local = finishAbsentAccumulation(inputs, retained.absentIndex.value, prior, slot).value
    assert uint64(local.absentInfo.value.gasUsed) == 0
    let blockLocal = finishBlockAbsentAccumulation(bound.absentBlockRound.value,
        InvocationServiceIndex(0)).value
    assert uint32(blockLocal.absentProjection.value.absentInfo.value.service) ==
        99 # Pure and bound acyclic proof owners release together.
  let after = getOccupiedMem()
  assert before == after, "absent account proof owners release"
  recordArcRelease("pvm_absent_account_outcomes", 1000, before, after)
  echo "PVM absent account outcomes passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Missing fixtures, exceptions or cryptographic failures must fail the native suite.
except:
  quit(2) # Never turn an unexpected failure into an empty no-execution success.
