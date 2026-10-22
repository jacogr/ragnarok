# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_validator_statistics_arc_release"}

## Current signed terminal observations preserve every literal validator counter, epoch/reporter rule and failure boundary.

import std/[assertions, envvars, syncio]
import ../../../src/state/[accumulation_current_validators, accumulation_validators,
  validator_projection, accumulation_current_recent, accumulation_recent,
  accumulation_current_ready, accumulation_ready, accumulation_current_finalization,
  accumulation_current_accounts, accumulation_current_statistics, accumulation_current_driver,
  accumulation_current_sequence, accumulation_current_round, accumulation_block_guests,
  accumulation_round, accumulation_queue, report_admission, guarantee_credentials,
  block_transition, block_admission, store]
import ../../../src/codec/[bounded, header, owned, report_owned, guarantees, block_codec,
  state_safrole, state_accounts, state_statistics, state_outputs, state_workqueues, state_history,
  state_layout, state_trie]
import ../../support/[accumulation_execution_context, accumulation_current_round_context,
  accumulation_current_driver_context, accumulation_current_finalization_context,
  report_context, arc_evidence]

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
        previousReports = false): PreparedCurrentAccumulationRecent =
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
  let completed = runCurrentBlockAccumulationSequence(fixture.round, currentRoundParameters(),
    currentSequenceDriverLimits()).value
  let accounts = currentFinalizationAccounts(completed)
  let finalized = prepareCurrentAccumulationFinalization(accounts, currentFinalizationConfig()).value
  let ready = prepareCurrentAccumulationReady(finalized, queuePolicy()).value
  prepareCurrentAccumulationRecent(ready, AccumulationRecentConfig(headerBytes: ByteLimit(4096),
    outputs: OutputLogConfig(items: ElementLimit(0), maxBytes: ByteLimit(1)),
    history: HistoryConfig(cores: CoreCount(2), blocks: ElementLimit(8), perBlock: ElementLimit(2),
      totalPackages: ElementLimit(16), peaks: ElementLimit(10), maxBytes: ByteLimit(4096)))).value

proc sourceAccounts(source: PreparedCurrentAccumulationRecent): PreparedCurrentAccumulationAccounts =
  ## Retain exact current timestamp/statistics ownership for independent fixture observations.
  source.currentRecentSource.value.currentReadySource.value.currentFinalizationAccounts.value

# Traverse the public immutable graph only for independent body/credential/state witnesses.
proc admission(source: PreparedCurrentAccumulationRecent): AdmittedReports =
  sourceAccounts(source).currentAccountsSource.value.currentStatisticsSource.value.completedSequenceSource.value.currentSequenceInitial.value.currentRoundGuests.value.guestRound.value.roundBlockQueue.value.accumulationAdmission.value

# Inspect every projected field against literal old counters and independent credential positions.
proc witness(source: PreparedCurrentAccumulationRecent, available, blobs, ticket, rotated: bool,
    shifted = false) =
  let prior = source.currentRecentState.value
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
  let prepared = prepareCurrentAccumulationValidators(source, config())
  assert prepared.error == CurrentAccumulationValidatorsError.None, "genuine source binds validator activity"
  let plan = prepared.value
  assert sameStateSnapshot(prior, plan.currentValidatorsState.value), "no C(13) publication or root rebuild"
  assert sameStateSnapshot(prior, plan.currentValidatorsSource.value.currentRecentState.value), "exact source retained"
  let observations = plan.currentValidatorsObservations.value
  assert uint32(observations.parentSlot) == 1, "parent C(11), not post-Safrole time"
  assert uint32(observations.slot) == uint32(binding.admittedHeader.headerInfo.value.unsigned.slot), "authenticated header slot"
  assert uint64(observations.epochSlots) == 12 and uint16(observations.author) == 0, "retained profile and author"
  assert uint64(observations.tickets) == uint64(ord(ticket)), "submitted RingVRF ticket count"
  assert uint64(observations.preimages) == uint64(if blobs: 3 else: 0), "all submitted preimages counted"
  assert uint64(observations.preimageBytes) == uint64(if blobs: 4 else: 0), "empty blob included in count only"
  let projection = plan.currentValidatorsProjection.value
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
proc policyWitnesses(source: PreparedCurrentAccumulationRecent) =
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
    let refused = prepareCurrentAccumulationValidators(source, short)
    if mode == 1:
      assert refused.error == CurrentAccumulationValidatorsError.RosterFailure, "roster policy cause selected"
      assert refused.rosterError == StateComponentError.LimitExceeded
    elif mode == 2:
      assert refused.error == CurrentAccumulationValidatorsError.ActivityFailure, "activity policy cause selected"
      assert refused.activityError == ActivityError.LimitExceeded
    elif mode == 8:
      assert refused.error == CurrentAccumulationValidatorsError.ProjectionFailure, "projection comparison cause selected"
      assert refused.projectionError == ValidatorActivityError.LimitExceeded
    else:
      assert refused.error == CurrentAccumulationValidatorsError.LimitExceeded, "independent source materialization policy"
  var exact = config()
  exact.chapterBytes = ByteLimit(2017)
  exact.componentBytes = ByteLimit(496)
  assert prepareCurrentAccumulationValidators(source, exact).error ==
      CurrentAccumulationValidatorsError.None, "exact framed work limits"
  exact.projection.rows = ElementLimit(11)
  assert prepareCurrentAccumulationValidators(source, exact).projectionError ==
      ValidatorActivityError.LimitExceeded, "retained row policy"
  assert prepareCurrentAccumulationValidators(source, config()).error ==
      CurrentAccumulationValidatorsError.None, "retry keeps same source usable"
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
  assert prepareCurrentAccumulationValidators(source, full).error ==
      CurrentAccumulationValidatorsError.None,
    "full-width resource maxima never become allocation requests"
  assert hashCalls() == 0, "all policy failures are read-only"
  failHash(0)

# Malformed parent data is authenticated as bytes but never treated as a default empty activity map.
proc damagedWitnesses(base: OwnedReport) =
  for mode in 0..<4:
    let bad = source(base, missing = mode == 0, damaged = mode)
    failHash(3)
    let refused = prepareCurrentAccumulationValidators(bad, config())
    case mode
    of 0: assert refused.error == CurrentAccumulationValidatorsError.MissingState, "missing C(13)"
    of 2: assert refused.error == CurrentAccumulationValidatorsError.InvalidState, "suffixed C(13)"
    else: assert refused.error == CurrentAccumulationValidatorsError.ActivityFailure, "malformed C(13)"
    assert hashCalls() == 0, "bad parent data never writes"
    failHash(0)
  let overflow = source(base, overflow = true)
  let assured = source(base, available = true, slot = 12, assuranceOverflow = true)
  for parent in [overflow, assured]:
    failHash(3)
    let refused = prepareCurrentAccumulationValidators(parent, config())
    assert refused.error == CurrentAccumulationValidatorsError.ProjectionFailure, "checked fixed counters retain typed refusal"
    assert refused.projectionError == ValidatorActivityError.CounterOverflow
    assert hashCalls() == 0, "overflow leaves source unchanged"
    failHash(0)

# Every scoped success/refusal owner dies before the next measured allocation observation.
proc cycle(source: PreparedCurrentAccumulationRecent) =
  let candidate = prepareCurrentAccumulationValidators(source, config()).value
  assert candidate.currentValidatorsProjection.value.validatorActivityInfo.value.current == 6
  var short = config()
  short.preimages = ElementLimit(0)
  assert prepareCurrentAccumulationValidators(source, short).error ==
      CurrentAccumulationValidatorsError.LimitExceeded

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
  assert prepareCurrentAccumulationValidators(empty, zero).error ==
      CurrentAccumulationValidatorsError.None,
    "empty selected components fit one framing byte and zero observation budgets"
  let submitted = source(base, guarantees = 2, blobs = true)
  witness(submitted, false, true, false, false)
  assert sourceAccounts(submitted).currentAccountsSource.value.currentStatisticsInfo.value.services ==
      0, "new guarantees and submitted preimages differ from accumulation S"
  let available = source(base, available = true, guarantees = 2, blobs = true)
  witness(available, true, true, false, false)
  assert sourceAccounts(available).currentAccountsInfo.value.updates == 1, "real accumulated missing-code report timestamps its service"
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
  let defaultOwner = default(PreparedCurrentAccumulationValidators)
  assert defaultOwner.currentValidatorsSource.error ==
      CurrentAccumulationValidatorsError.Uninitialized
  assert defaultOwner.currentValidatorsObservations.error ==
      CurrentAccumulationValidatorsError.Uninitialized
  assert defaultOwner.currentValidatorsProjection.error ==
      CurrentAccumulationValidatorsError.Uninitialized
  assert defaultOwner.currentValidatorsState.error ==
      CurrentAccumulationValidatorsError.Uninitialized
  let invalid = prepareCurrentAccumulationValidators(default(PreparedCurrentAccumulationRecent),
      config())
  assert invalid.error == CurrentAccumulationValidatorsError.InvalidSource
  var detached = default(PreparedCurrentAccumulationValidators)
  block:
    let local = source(base, blobs = true)
    detached = prepareCurrentAccumulationValidators(local, config()).value
  var copied = detached.currentValidatorsObservations.value
  copied.slot = StateTime(99)
  assert uint32(detached.currentValidatorsObservations.value.slot) == 2, "derived observations copied and owner outlives source scope"
  assert detached.currentValidatorsProjection.value.validatorActivityInfo.value.current == 6,
    "projection survives source scope"
  assert sameStateSnapshot(detached.currentValidatorsState.value,
    detached.currentValidatorsSource.value.currentRecentState.value), "complete map survives source scope"
  failHash(3)
  cycle(available)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(available) # No source/signature reconstruction inside the lifetime workload.
  let after = getOccupiedMem()
  assert before == after, "bound validator candidate ARC release"
  assert hashCalls() == 0, "ARC workload remains hash-free"
  failHash(0)
  recordArcRelease("pvm_current_validator_statistics", 1000, before, after)
  echo "PVM current validator statistics passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fallible fixture I/O must remain a strict test failure.
except:
  quit(2)
