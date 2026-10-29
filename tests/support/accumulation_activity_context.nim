# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Signed report-only activity fixtures retain original full-map entries and actual stopped accumulation provenance.

import std/assertions
import ./service_namespace_seed
import ../../src/state/accumulation/validators as accumulation_validators
import ../../src/state/validator/projection as validator_projection
import ../../src/state/accumulation/[times as accumulation_times,
    statistics as accumulation_statistics, recent as accumulation_recent,
    ready as accumulation_ready, history as accumulation_history,
    finalization as accumulation_finalization, outputs as accumulation_outputs]
import ../../src/state/accumulation/continuation/[execution as accumulation_continuation_execution,
    inputs as accumulation_continuation_inputs]
import ../../src/state/accumulation/[continuation as accumulation_continuation,
    execution as accumulation_execution, round as accumulation_round, inputs as accumulation_inputs,
    service as accumulation_service, skip as accumulation_skip, dispatch as accumulation_dispatch,
    effects as accumulation_effects]
import ../../src/codec/[bounded, composite, header, report_owned]
import ../../src/codec/work/digest as work_digest
import ../../src/codec/state/[statistics as state_statistics, outputs as state_outputs,
    workqueues as state_workqueues, history as state_history, trie as state_trie,
    authorization as state_authorization]
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

proc activityOptions*(available = false, guarantees = 0, blobs = false,
    requested = true, missingLast = false, disordered = false, slot = 2'u32,
    hugeRefinement = false, executed = false, provided = false, parentPools: seq[AuthorizerRow] = @[],
    authorizationQueue: seq[byte] = @[], omitAuthorizationQueue = false,
    withDispute = false, withTicket = false, shiftPending = false,
    storeWrites = 1000'u64, completeState = false, serviceNamespaces: seq[ServiceNamespaceSeed] = @[]): ExecutionFixtureConfig =
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
  var executionOptions0 = executionFixtureConfig()
  executionOptions0.first = ending
  executionOptions0.second = ending
  executionOptions0.empty = not (executed or provided)
  executionOptions0.firstProgram = program
  executionOptions0.signed.withAvailable = available
  executionOptions0.signed.reports = guarantees
  executionOptions0.signed.extra = entries
  executionOptions0.signed.preimageWire = body
  executionOptions0.signed.targetSlot = slot
  executionOptions0.signed.refinement = loads
  executionOptions0.signed.parentPools = parentPools
  executionOptions0.authorizationQueue = authorizationQueue
  executionOptions0.omitAuthorizationQueue = omitAuthorizationQueue
  executionOptions0.signed.withDispute = withDispute
  executionOptions0.signed.withTicket = withTicket
  executionOptions0.signed.shiftPending = shiftPending
  executionOptions0.signed.storeWrites = storeWrites
  executionOptions0.signed.completeState = completeState
  executionOptions0.signed.serviceNamespaces = serviceNamespaces
  executionOptions0

proc activityFixture*(base: OwnedReport, available = false, guarantees = 0, blobs = false,
    requested = true, missingLast = false, disordered = false, slot = 2'u32,
    hugeRefinement = false, executed = false, provided = false, parentPools: seq[AuthorizerRow] = @[],
    authorizationQueue: seq[byte] = @[], omitAuthorizationQueue = false,
    withDispute = false, withTicket = false, shiftPending = false,
    storeWrites = 1000'u64): ActivityFixture =
  ## Reuse identical authored signed inputs while preserving the established legacy completion witnesses.
  let fixture = executionFixture(base, activityOptions(available = available,
      guarantees = guarantees, blobs = blobs, requested = requested, missingLast = missingLast,
      disordered = disordered, slot = slot, hugeRefinement = hugeRefinement, executed = executed,
      provided = provided, parentPools = parentPools, authorizationQueue = authorizationQueue,
      omitAuthorizationQueue = omitAuthorizationQueue, withDispute = withDispute,
      withTicket = withTicket, shiftPending = shiftPending, storeWrites = storeWrites))
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
      writes: ElementLimit(2), bytes: ByteLimit(210)))).value
  ActivityFixture(source: prepareAccumulationValidators(times, activityValidatorConfig()).value,
    entries: fixture.entries)
