# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Signed report-only activity fixtures retain original full-map entries and actual stopped accumulation provenance.

import std/assertions
import ../../src/state/[accumulation_validators, validator_projection, accumulation_times,
  accumulation_statistics, accumulation_recent, accumulation_ready, accumulation_history,
  accumulation_finalization, accumulation_outputs, accumulation_continuation_execution,
  accumulation_continuation_inputs, accumulation_continuation, accumulation_execution,
  accumulation_round, accumulation_inputs, accumulation_service, accumulation_skip,
  accumulation_dispatch,
  accumulation_effects]
import ../../src/codec/[bounded, composite, header, report_owned, work_digest, state_statistics,
  state_outputs, state_workqueues, state_history, state_trie, state_authorization]
import ./[accumulation_execution_context, accumulation_provision_integration,
  accumulation_batch_context, pvm_accumulation_provision]

type
  ActivityFixture* = object ## Original serialized keys support independent full-map reconstruction around the one C(13) write.
    source*: PreparedAccumulationValidators
    entries*: seq[StateEntry]

proc activityValidatorConfig*(): AccumulationValidatorsConfig =
  ## Six-validator parent and posterior populations; all submitted observations are finite and independent.
  AccumulationValidatorsConfig(chapterBytes: ByteLimit(4096), validators: ElementLimit(6),
    services: ElementLimit(1), componentBytes: ByteLimit(1024), preimages: ElementLimit(3),
    preimageBytes: ByteLimit(4), projection: ValidatorActivityLimits(rows: ElementLimit(12),
      assurances: ElementLimit(5), reporters: ElementLimit(4), comparisons: ElementLimit(24)))

proc activityParentEntry*(): StateEntry =
  ## Seed every validator field and stale core/service statistics before signing the original parent.
  var activity = default(ActivityState)
  activity.validators[StatisticsEpoch.Current] = newSeq[ValidatorActivity](6)
  activity.validators[StatisticsEpoch.Previous] = newSeq[ValidatorActivity](6)
  activity.cores = newSeq[CoreActivity](2)
  for epoch in low(StatisticsEpoch)..high(StatisticsEpoch):
    for index in 0..<6:
      for measure in low(ValidatorMeasure)..high(ValidatorMeasure):
        activity.validators[epoch][index][measure] = ValidatorCounter(uint32(
          1000*ord(epoch)+100*index+10+ord(measure)))
  activity.cores[0].gas = ActivityGas(999)
  var old = ServiceStatisticsEntry(service: ServiceIndex(123))
  old.statistics.counters[ServiceMeasure.RefinementCount] = ActivityNatural(77)
  activity.services = @[old]
  activityStateEntry(activity, ActivityConfig(cores: CoreCount(2), current: ValidatorCount(6),
    previous: ValidatorCount(6), maxServices: ElementLimit(1), maxBytes: ByteLimit(4096))).value

# Tiny profile domains mirror the genuine report admission chain without overriding any production certificate.
proc queuePolicy(): AccumulationReadyConfig =
  AccumulationReadyConfig(items: ElementLimit(32), dependencies: ElementLimit(256),
    queues: executionQueueConfig().queues)

proc activityFixture*(base: OwnedReport, available = false, guarantees = 0, blobs = false,
    requested = true, missingLast = false, disordered = false, slot = 2'u32,
    hugeRefinement = false, executed = false, provided = false, parentPools: seq[AuthorizerRow] = @[],
    authorizationQueue: seq[byte] = @[], omitAuthorizationQueue = false,
    withDispute = false, withTicket = false, shiftPending = false,
    storeWrites = 1000'u64): ActivityFixture =
  ## Actual parent commitments, signatures, availability, skipped executions and C(3/14/15/16)/timestamps precede activity.
  var entries = @[activityParentEntry()]
  var body: seq[byte] = @[]
  if blobs:
    body = if disordered: @[3'u8, 42, 0, 0, 0, 1, 73, 99, 0, 0, 0, 3, 81, 82, 83, 99, 0, 0, 0, 0]
      else: @[3'u8, 42, 0, 0, 0, 1, 73, 99, 0, 0, 0, 0, 99, 0, 0, 0, 3, 81, 82, 83]
    if requested:
      entries.add(integrationRequest(42, @[73'u8]))
      entries.add(integrationRequest(99, @[]))
      if not missingLast: entries.add(integrationRequest(99, @[81'u8, 82,
          83])) # A late unsolicited blob cannot expose partial activity.
  let loads = if hugeRefinement: newSeq[RefineLoad]() else:
    @[RefineLoad(gasUsed: Gas(11), imports: ImportCount(2),
        extrinsicCount: work_digest.ExtrinsicCount(3), extrinsicSize: work_digest.ExtrinsicBytes(5),
            exports: ExportCount(7)),
      RefineLoad(gasUsed: Gas(13), imports: ImportCount(17),
          extrinsicCount: work_digest.ExtrinsicCount(19),
        extrinsicSize: work_digest.ExtrinsicBytes(23), exports: ExportCount(29))]
  var program: seq[byte] = @[]
  if provided:
    program = @[0'u8]
    for octet in batchEnvelope(BatchEnding.Halt): program.add(octet) # Real provides precede lookup integration.
    entries.add(integrationRequest(99, @[81'u8])) # The guest's second provision is independent of the lookup blob.
  let ending = if executed or provided: ExecutionEnding.Halt else: ExecutionEnding.Missing
  let fixture = executionFixture(base, first = ending,
    second = ending, empty = not (executed or provided), firstProgram = program,
    report = available, incomingReports = guarantees,
    extra = entries, preimageWire = body, targetSlot = slot, refinement = loads,
    parentPools = parentPools, authorizationQueue = authorizationQueue,
    omitAuthorizationQueue = omitAuthorizationQueue, withDispute = withDispute,
    withTicket = withTicket, shiftPending = shiftPending, storeWrites = storeWrites)
  let initial = fixture.round
  var skips: seq[SkippedAccumulation] = @[]
  var runs: seq[AccumulationDispatchResult] = @[]
  for index in 0..<initial.roundProjection.value.roundInputs.value.invocationServiceCount.value:
    if executed or provided:
      let policy = if provided and index == 0: provisionPolicy(items = 2, perBlob = 1, total = 2)
        else: default(AccumulationProvisionLimits) # Only the providing guest receives provision capture capacity.
      runs.add(executionGuest(fixture, uint64(index), slot = HeaderSlot(slot),
          provisions = policy)) # Real tiny guests contribute actual nonzero S gas.
    else:
      let service = prepareBlockAccumulationService(initial, InvocationServiceIndex(uint64(index)),
        AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024))).value
      skips.add(finishUninvokedAccumulation(service.serviceProjection.value).value) # Missing code supplies certified N without invented gas.
  let done = completeBlockAccumulation(initial, runs, skips, executionLimits()).value
  let continuation = planAccumulationContinuation(done, AccumulationContinuationLimits(
    executions: ElementLimit(2), reports: ElementLimit(4), digests: ElementLimit(4))).value
  assert not continuation.continuationInfo.value.dispatch, "fixture reaches a genuine stopped second round"
  let policy = executionRoundConfig()
  let inputs = prepareAccumulationContinuationInputs(continuation,
    AccumulationContinuationInputConfig(operands: policy.operands, inputs: policy.inputs)).value
  let terminal = completeAccumulationContinuation(inputs, [], [], executionLimits()).value
  let finalized = prepareFinalAccumulation(terminal, AccumulationOutputHistoryLimits(
    rounds: ElementLimit(2), executions: ElementLimit(2), log: OutputLogConfig(
      items: ElementLimit(0), maxBytes: ByteLimit(1)))).value
  let history = prepareAccumulationHistory(finalized, AccumulationHistoryConfig(
    reports: ElementLimit(1), queues: queuePolicy().queues)).value
  let ready = prepareAccumulationReady(history, queuePolicy()).value
  let recent = prepareAccumulationRecent(ready, AccumulationRecentConfig(headerBytes: ByteLimit(4096),
    outputs: OutputLogConfig(items: ElementLimit(0), maxBytes: ByteLimit(1)),
    history: HistoryConfig(cores: CoreCount(2), blocks: ElementLimit(8), perBlock: ElementLimit(2),
      totalPackages: ElementLimit(16), peaks: ElementLimit(10), maxBytes: ByteLimit(4096)))).value
  let times = prepareAccumulationTimes(recent, AccumulationTimesConfig(
    statistics: AccumulationStatisticsLimits(
    rounds: ElementLimit(2), gasRows: ElementLimit(2), reports: ElementLimit(1),
        digests: ElementLimit(1),
    services: ElementLimit(2)), accounts: AccumulationTimesLimits(services: ElementLimit(2),
      writes: ElementLimit(2), bytes: ByteLimit(178)))).value
  ActivityFixture(source: prepareAccumulationValidators(times, activityValidatorConfig()).value,
    entries: fixture.entries)
