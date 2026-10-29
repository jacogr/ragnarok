# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_validators_arc_release"}

## Signed block observations, inherited full-map identity, codec/policy refusals and immutable validator candidates.

import std/[assertions, envvars, syncio]
import ../../../src/state/accumulation/validators as accumulation_validators
import ../../../src/state/validator/projection as validator_projection
import ../../../src/state/accumulation/[times as accumulation_times,
    statistics as accumulation_statistics, recent as accumulation_recent,
    ready as accumulation_ready, history as accumulation_history,
    finalization as accumulation_finalization, outputs as accumulation_outputs]
import ../../../src/state/accumulation/continuation/[
    execution as accumulation_continuation_execution, inputs as accumulation_continuation_inputs]
import ../../../src/state/accumulation/[continuation as accumulation_continuation,
    execution as accumulation_execution, round as accumulation_round, inputs as accumulation_inputs,
    service as accumulation_service, skip as accumulation_skip, queue as accumulation_queue]
import ../../../src/state/report/admission as report_admission
import ../../../src/state/guarantee_credentials
import "../../../src/state/block/transition" as block_transition
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/store
import ../../../src/codec/[bounded, header, owned, report_owned, guarantees, block_codec]
import ../../../src/codec/state/[safrole as state_safrole, accounts as state_accounts,
    statistics as state_statistics, outputs as state_outputs, workqueues as state_workqueues,
    history as state_history, layout as state_layout, trie as state_trie]
import ../../support/[accumulation_execution_context, report_context, arc_evidence]

# Fault injection starts only after real signatures, accumulation and complete-map construction.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

# Exact chain domains are inherited; these values bound only local resource use.
proc config(): AccumulationValidatorsConfig =
  AccumulationValidatorsConfig(chapterBytes: ByteLimit(4096), validators: ElementLimit(6),
    services: ElementLimit(1), componentBytes: ByteLimit(1024), preimages: ElementLimit(3),
    preimageBytes: ByteLimit(4), projection: ValidatorActivityLimits(rows: ElementLimit(12),
      assurances: ElementLimit(5), reporters: ElementLimit(4), comparisons: ElementLimit(24)))

# All fields differ between positions and epochs; stale per-block families are deliberately nonzero.
proc parentActivity(overflow = false, assuranceOverflow = false): StateEntry =
  var activity = default(ActivityState)
  activity.validators[StatisticsEpoch.Current] = newSeq[ValidatorActivity](6)
  activity.validators[StatisticsEpoch.Previous] = newSeq[ValidatorActivity](6)
  activity.cores = newSeq[CoreActivity](2)
  for epoch in low(StatisticsEpoch)..high(StatisticsEpoch):
    for index in 0..<6:
      for measure in low(ValidatorMeasure)..high(ValidatorMeasure):
        activity.validators[epoch][index][measure] = ValidatorCounter(uint32(
          1000*ord(epoch)+100*index+10+ord(measure)))
  if overflow: activity.validators[StatisticsEpoch.Current][0][
      ValidatorMeasure.Blocks] = ValidatorCounter(high(uint32))
  if assuranceOverflow: activity.validators[StatisticsEpoch.Current][0][
      ValidatorMeasure.Assurances] = ValidatorCounter(high(uint32))
  activity.cores[0].gas = ActivityGas(999)
  var old = ServiceStatisticsEntry(service: ServiceIndex(123))
  old.statistics.counters[ServiceMeasure.RefinementCount] = ActivityNatural(77)
  activity.services = @[old]
  activityStateEntry(activity, ActivityConfig(cores: CoreCount(2), current: ValidatorCount(6),
    previous: ValidatorCount(6), maxServices: ElementLimit(1), maxBytes: ByteLimit(4096))).value

# Exact literal body framing counts three submitted preimages and four payload bytes, including an empty blob.
proc preimageWire(): seq[byte] =
  @[3'u8, 42, 0, 0, 0, 1, 73, 99, 0, 0, 0, 0, 99, 0, 0, 0, 3, 81, 82, 83]

# History/ready/recent policies preserve the tiny signed chain's actual profile and bounded dictionaries.
proc queuePolicy(): AccumulationReadyConfig =
  AccumulationReadyConfig(items: ElementLimit(32), dependencies: ElementLimit(256),
    queues: executionQueueConfig().queues)

# Materialize a genuinely stopped two-round sequence; available work uses certified missing-code skips.
proc source(base: OwnedReport, available = false, guarantees = 0, blobs = false,
    slot = 2'u32, ticket = false, missing = false, damaged = 0, overflow = false,
    assuranceOverflow = false, shiftPending = false,
        previousReports = false): PreparedAccumulationTimes =
  var entries: seq[StateEntry] = @[]
  if not missing:
    var entry = parentActivity(overflow, assuranceOverflow)
    case damaged
    of 1: entry.value = @[] # Truncated parent activity remains committed by a genuine header.
    of 2: entry.value.add(0) # Prefix-valid activity with an unconsumed suffix.
    of 3: entry.value[0] = 5 # Wrong current population cannot define C(13) framing.
    else: discard # Canonical complete activity enters the parent unchanged.
    entries.add(entry)
  var executionOptions0 = executionFixtureConfig()
  executionOptions0.first = ExecutionEnding.Missing
  executionOptions0.second = ExecutionEnding.Missing
  executionOptions0.empty = true
  executionOptions0.signed.withAvailable = available
  executionOptions0.signed.reports = guarantees
  executionOptions0.signed.extra = entries
  executionOptions0.signed.preimageWire = (if blobs: preimageWire() else: @[])
  executionOptions0.signed.targetSlot = slot
  executionOptions0.signed.withTicket = ticket
  executionOptions0.signed.shiftPending = shiftPending
  executionOptions0.signed.guaranteeSlot = (if previousReports: 11'u32 else: 0'u32)
  let fixture = executionFixture(base, executionOptions0)
  let initial = fixture.round
  var skips: seq[SkippedAccumulation] = @[]
  for index in 0..<initial.roundProjection.value.roundInputs.value.invocationServiceCount.value:
    let service = prepareBlockAccumulationService(initial, InvocationServiceIndex(uint64(index)),
      AccumulationServiceConfig(codeLimit: ServiceCodeLimit(512), preimageBytes: ByteLimit(1024))).value
    skips.add(finishUninvokedAccumulation(service.serviceProjection.value).value) # No fabricated successful executions or gas.
  let done = completeBlockAccumulation(initial, [], skips, executionLimits()).value
  let continuation = planAccumulationContinuation(done, AccumulationContinuationLimits(
    executions: ElementLimit(2), reports: ElementLimit(4), digests: ElementLimit(4))).value
  assert not continuation.continuationInfo.value.dispatch, "one available report fully consumed initially"
  let roundConfig = executionRoundConfig()
  let inputs = prepareAccumulationContinuationInputs(continuation,
    AccumulationContinuationInputConfig(operands: roundConfig.operands,
        inputs: roundConfig.inputs)).value
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
  prepareAccumulationTimes(recent, AccumulationTimesConfig(statistics: AccumulationStatisticsLimits(
    rounds: ElementLimit(2), gasRows: ElementLimit(1), reports: ElementLimit(1),
        digests: ElementLimit(1),
    services: ElementLimit(1)), accounts: AccumulationTimesLimits(services: ElementLimit(1),
      writes: ElementLimit(1), bytes: ByteLimit(ServiceMetadataBytes)))).value

# Traverse the public immutable graph only for independent body/credential/state witnesses.
proc admission(source: PreparedAccumulationTimes): AdmittedReports =
  source.accumulationTimesStatistics.value.statisticsSource.value.finalAccumulationOutputs.value.outputsSource.value.executionRound.value.roundBlockQueue.value.accumulationAdmission.value

# Inspect every projected field against literal old counters and independent credential positions.
proc witness(source: PreparedAccumulationTimes, available, blobs, ticket, rotated: bool,
    shifted = false) =
  let prior = source.accumulationTimesState.value
  let admitted = admission(source)
  let stage = admitted.reportBlockStage.value
  let binding = stage.value.admitted
  let original = binding.admittedState.lookup(chapterKey(StateChapter(13))).value.bytes
  var reported = default(array[6, bool])
  let credentials = admitted.reportCredentials.value
  for index in 0..<credentials.verifiedGuaranteeCount.value:
    let record = credentials.verifiedGuaranteeAt(index).value
    for signer in 0..<record.credentialCount:
      let oldPosition = int(uint16(record.credentials[signer].validator))
      let position = if shifted: (oldPosition+5) mod 6 else: oldPosition
      reported[position] = true # Previous-roster signer identities map to shifted posterior positions.
  if shifted:
    var distinguishesPositions = false
    for index in 0..<6:
      if reported[index] != reported[(index+5) mod 6]: distinguishesPositions = true
    assert distinguishesPositions, "posterior key movement must change the credited position set"
  failHash(3)
  let prepared = prepareAccumulationValidators(source, config())
  assert prepared.error == AccumulationValidatorsError.None, "genuine source binds validator activity"
  let plan = prepared.value
  assert sameStateSnapshot(prior, plan.accumulationValidatorsState.value), "no C(13) publication or root rebuild"
  assert sameStateSnapshot(prior, plan.accumulationValidatorsSource.value.accumulationTimesState.value), "exact source retained"
  let observations = plan.accumulationValidatorsObservations.value
  assert uint32(observations.parentSlot) == 1, "parent C(11), not post-Safrole time"
  assert uint32(observations.slot) == uint32(binding.admittedHeader.headerInfo.value.unsigned.slot), "authenticated header slot"
  assert uint64(observations.epochSlots) == 12 and uint16(observations.author) == 0, "retained profile and author"
  assert uint64(observations.tickets) == uint64(ord(ticket)), "submitted RingVRF ticket count"
  assert uint64(observations.preimages) == uint64(if blobs: 3 else: 0), "all submitted preimages counted"
  assert uint64(observations.preimageBytes) == uint64(if blobs: 4 else: 0), "empty blob included in count only"
  let projection = plan.accumulationValidatorsProjection.value
  assert projection.validatorActivityInfo.value.rotated == rotated, "epoch decision from source slots"
  for epoch in low(StatisticsEpoch)..high(StatisticsEpoch):
    for index in 0..<6:
      let row = projection.projectedValidatorAt(epoch, StatisticsValidatorIndex(uint64(index))).value
      for measure in low(ValidatorMeasure)..high(ValidatorMeasure):
        var expected = uint32(1000*ord(epoch)+100*index+10+ord(measure))
        if rotated:
          expected = if epoch == StatisticsEpoch.Current: 0'u32 else: uint32(100*index+10+ord(measure))
        let assuranceEpoch = if rotated: StatisticsEpoch.Previous else: StatisticsEpoch.Current
        if epoch == assuranceEpoch and available and index < 5 and measure ==
            ValidatorMeasure.Assurances: inc expected
        if epoch == StatisticsEpoch.Current:
          if reported[index] and measure == ValidatorMeasure.Guarantees: inc expected
          if index == 0:
            case measure
            of ValidatorMeasure.Blocks: inc expected
            of ValidatorMeasure.Tickets: expected += uint32(ord(ticket))
            of ValidatorMeasure.PreimageCount: expected += uint32(if blobs: 3 else: 0)
            of ValidatorMeasure.PreimageBytes: expected += uint32(if blobs: 4 else: 0)
            else: discard # Other fields use assured/reporter membership above.
        assert uint32(row[measure]) == expected, "literal certified validator field"
  assert binding.admittedState.lookup(chapterKey(StateChapter(13))).value.bytes == original, "parent C(13) unchanged"
  assert prior.lookup(chapterKey(StateChapter(13))).value.bytes == original, "candidate C(13) still old until combination"
  assert hashCalls() == 0, "binding performs no hashing or re-verification"
  failHash(0)

# Check each independent resource boundary and successful retry on the identical immutable source.
proc policyWitnesses(source: PreparedAccumulationTimes) =
  failHash(3)
  for mode in 0..<9:
    var short = config()
    case mode
    of 0: short.chapterBytes = ByteLimit(2016) # Six roster entries need one prefix byte plus 6*336.
    of 1: short.validators = ElementLimit(5) # Roster failure retains its selected codec cause.
    of 2: short.services = ElementLimit(0) # Existing parent activity dictionary must be validated even though not copied.
    of 3: short.componentBytes = ByteLimit(495) # Five assurances have one count byte plus 5*99 bytes.
    of 4: short.preimages = ElementLimit(2)
    of 5: short.preimageBytes = ByteLimit(3)
    of 6: short.projection.assurances = ElementLimit(4)
    of 7: short.projection.reporters = ElementLimit(3)
    else: short.projection.comparisons = ElementLimit(23)
    let refused = prepareAccumulationValidators(source, short)
    if mode == 1:
      assert refused.error == AccumulationValidatorsError.RosterFailure, "roster policy cause selected"
      assert refused.rosterError == StateComponentError.LimitExceeded
    elif mode == 2:
      assert refused.error == AccumulationValidatorsError.ActivityFailure, "activity policy cause selected"
      assert refused.activityError == ActivityError.LimitExceeded
    elif mode == 8:
      assert refused.error == AccumulationValidatorsError.ProjectionFailure, "projection comparison cause selected"
      assert refused.projectionError == ValidatorActivityError.LimitExceeded
    else:
      assert refused.error == AccumulationValidatorsError.LimitExceeded, "independent source materialization policy"
  var exact = config()
  exact.chapterBytes = ByteLimit(2017)
  exact.componentBytes = ByteLimit(496)
  assert prepareAccumulationValidators(source, exact).error == AccumulationValidatorsError.None, "exact framed work limits"
  exact.projection.rows = ElementLimit(11)
  assert prepareAccumulationValidators(source, exact).projectionError ==
      ValidatorActivityError.LimitExceeded, "retained row policy"
  assert prepareAccumulationValidators(source, config()).error == AccumulationValidatorsError.None, "retry keeps same source usable"
  var full = config()
  full.chapterBytes = ByteLimit(high(uint64))
  full.validators = ElementLimit(high(uint64))
  full.services = ElementLimit(high(uint64))
  full.componentBytes = ByteLimit(high(uint64))
  full.preimages = ElementLimit(high(uint64))
  full.preimageBytes = ByteLimit(high(uint64))
  full.projection = ValidatorActivityLimits(rows: ElementLimit(high(uint64)),
    assurances: ElementLimit(high(uint64)), reporters: ElementLimit(high(uint64)),
    comparisons: ElementLimit(high(uint64)))
  assert prepareAccumulationValidators(source, full).error == AccumulationValidatorsError.None,
    "full-width resource maxima never become allocation requests"
  assert hashCalls() == 0, "all policy failures are read-only"
  failHash(0)

# Malformed parent data is authenticated as bytes but never treated as a default empty activity map.
proc damagedWitnesses(base: OwnedReport) =
  for mode in 0..<4:
    let bad = source(base, missing = mode == 0, damaged = mode)
    failHash(3)
    let refused = prepareAccumulationValidators(bad, config())
    case mode
    of 0: assert refused.error == AccumulationValidatorsError.MissingState, "missing C(13)"
    of 2: assert refused.error == AccumulationValidatorsError.InvalidState, "suffixed C(13)"
    else: assert refused.error == AccumulationValidatorsError.ActivityFailure, "malformed C(13)"
    assert hashCalls() == 0, "bad parent data never writes"
    failHash(0)
  let overflow = source(base, overflow = true)
  let assured = source(base, available = true, slot = 12, assuranceOverflow = true)
  for parent in [overflow, assured]:
    failHash(3)
    let refused = prepareAccumulationValidators(parent, config())
    assert refused.error == AccumulationValidatorsError.ProjectionFailure, "checked fixed counters retain typed refusal"
    assert refused.projectionError == ValidatorActivityError.CounterOverflow
    assert hashCalls() == 0, "overflow leaves source unchanged"
    failHash(0)

# Every scoped success/refusal owner dies before the next measured allocation observation.
proc cycle(source: PreparedAccumulationTimes) =
  let candidate = prepareAccumulationValidators(source, config()).value
  assert candidate.accumulationValidatorsProjection.value.validatorActivityInfo.value.current == 6
  var short = config()
  short.preimages = ElementLimit(0)
  assert prepareAccumulationValidators(source, short).error ==
      AccumulationValidatorsError.LimitExceeded

proc main() {.raises.} =
  ## Fixture loading and all signed source construction use the supported native launcher.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<wire.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  let empty = source(base)
  witness(empty, false, false, false, false)
  var zero = config()
  zero.chapterBytes = ByteLimit(2017)
  zero.componentBytes = ByteLimit(1)
  zero.preimages = ElementLimit(0)
  zero.preimageBytes = ByteLimit(0)
  zero.projection.assurances = ElementLimit(0)
  zero.projection.reporters = ElementLimit(0)
  zero.projection.comparisons = ElementLimit(0)
  assert prepareAccumulationValidators(empty, zero).error == AccumulationValidatorsError.None,
    "empty selected components fit one framing byte and zero observation budgets"
  let submitted = source(base, guarantees = 2, blobs = true)
  witness(submitted, false, true, false, false)
  assert submitted.accumulationTimesStatistics.value.statisticsInfo.value.services == 0, "new guarantees and submitted preimages differ from accumulation S"
  let available = source(base, available = true, guarantees = 2, blobs = true)
  witness(available, true, true, false, false)
  assert available.accumulationTimesInfo.value.updated == 1, "real accumulated missing-code report timestamps its service"
  let ticket = source(base, ticket = true)
  witness(ticket, false, false, true, false)
  for slot in [12'u32, 48'u32]:
    let crossed = source(base, available = true, blobs = true, slot = slot)
    witness(crossed, true, true, false, true)
  let moved = source(base, available = true, guarantees = 2, blobs = true, slot = 12,
    shiftPending = true, previousReports = true)
  witness(moved, true, true, false, true, shifted = true)
  policyWitnesses(available)
  damagedWitnesses(base)
  let defaultOwner = default(PreparedAccumulationValidators)
  assert defaultOwner.accumulationValidatorsSource.error ==
      AccumulationValidatorsError.Uninitialized
  assert defaultOwner.accumulationValidatorsObservations.error ==
      AccumulationValidatorsError.Uninitialized
  assert defaultOwner.accumulationValidatorsProjection.error ==
      AccumulationValidatorsError.Uninitialized
  assert defaultOwner.accumulationValidatorsState.error == AccumulationValidatorsError.Uninitialized
  assert prepareAccumulationValidators(default(PreparedAccumulationTimes), config()).error ==
      AccumulationValidatorsError.InvalidSource
  var detached = default(PreparedAccumulationValidators)
  block:
    let local = source(base, blobs = true)
    detached = prepareAccumulationValidators(local, config()).value
  var copied = detached.accumulationValidatorsObservations.value
  copied.slot = StateTime(99)
  assert uint32(detached.accumulationValidatorsObservations.value.slot) == 2, "derived observations copied and owner outlives source scope"
  assert detached.accumulationValidatorsProjection.value.validatorActivityInfo.value.current == 6,
    "projection survives source scope"
  assert sameStateSnapshot(detached.accumulationValidatorsState.value,
    detached.accumulationValidatorsSource.value.accumulationTimesState.value), "complete map survives source scope"
  failHash(3)
  cycle(available)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(available) # No source/signature reconstruction inside the lifetime workload.
  let after = getOccupiedMem()
  assert before == after, "bound validator candidate ARC release"
  assert hashCalls() == 0, "ARC workload remains hash-free"
  failHash(0)
  recordArcRelease("accumulation_validators", 1000, before, after)
  echo "Accumulation-bound validator activity passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fallible fixture I/O must remain a strict test failure.
except:
  quit(2)
