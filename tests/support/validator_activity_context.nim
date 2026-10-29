# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent epoch arrays and genuinely signed report-admission sources exercise validator counter ordering.

import std/assertions
import ../../src/state/validator/activity as validator_activity
import ../../src/state/report/admission as report_admission
import ../../src/state/guarantee_credentials
import "../../src/state/block/transition" as block_transition
import "../../src/state/block/admission" as block_admission
import ../../src/state/store
import ../../src/codec/[bounded, composite, owned]
import ../../src/codec/state/[statistics as state_statistics, safrole as state_safrole,
    layout as state_layout, trie as state_trie]
import ../../src/codec/[assurances, tickets, report_owned, block_codec, header]
import ./report_admission_context

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc validatorPolicy*(): ValidatorActivityConfig =
  ## Bound original extrinsic populations, source captures and explicit posterior-key comparison work.
  ValidatorActivityConfig(validators: ElementLimit(9), services: ElementLimit(0),
      tickets: ElementLimit(3),
    preimages: ElementLimit(3), assurances: ElementLimit(6), reporters: ElementLimit(9),
        reporterWork: ElementLimit(81),
    rosterBytes: ByteLimit(4096), statisticsBytes: ByteLimit(4096), preimageFrameBytes: ByteLimit(19),
    preimageBytes: ByteLimit(3), assuranceBytes: ByteLimit(4096))
proc preimageWire(): seq[byte] =
  ## Literal three records include an empty blob and repeated service identity, totaling three payload octets.
  @[3'u8, 42, 0, 0, 0, 0, 42, 0, 0, 0, 2, 1, 2, 77, 0, 0, 0, 1, 3]
proc provided(): OwnedFrame =
  ## Capture authored preimage framing independently of production statistics logic.
  decodeOwnedPreimages(preimageWire(), PreimageLimits(items: ElementLimit(3), perBlob: ByteLimit(2),
    totalBlobBytes: ByteLimit(3))).value
proc statisticsPolicy(cores, current, previous: int): ActivityConfig =
  ## Supply independent current/previous roster cardinalities to the existing unchanged codec.
  ActivityConfig(cores: CoreCount(cores), current: ValidatorCount(current),
      previous: ValidatorCount(previous),
    maxServices: ElementLimit(0), maxBytes: ByteLimit(4096))
proc seeded(cores = 3, current = 6, previous = 9): ActivityState =
  ## Distinct literal families make accidental reset, epoch swap and positional attribution observable.
  result = ActivityState(cores: newSeq[CoreActivity](cores))
  for epoch in low(StatisticsEpoch)..high(StatisticsEpoch):
    let count = if epoch == StatisticsEpoch.Current: current else: previous
    result.validators[epoch] = newSeq[ValidatorActivity](count)
    for index in 0..<count:
      for measure in low(ValidatorMeasure)..high(ValidatorMeasure):
        result.validators[epoch][index][measure] = ValidatorCounter(uint32(100*(ord(
            epoch)+1)+10*index+ord(measure)))
proc captured(state: ActivityState): ActivitySnapshot =
  ## Canonical encoding captures independently authored rows, never a production-projected expected value.
  let policy = statisticsPolicy(state.cores.len, state.validators[StatisticsEpoch.Current].len,
    state.validators[StatisticsEpoch.Previous].len)
  let encoded = activityStateEntry(state, policy).value
  decodeActivityState(encoded.value, policy).value.snapshot
proc active(count = 6): ValidatorStateSnapshot =
  ## Stable nontrivial key identities permit reporter membership by key instead of credential ordinal.
  var values = newSeq[StateValidator](count)
  for index in 0..<count:
    var key = default(array[32, byte])
    key[0] = byte(index+11)
    values[index].ed25519 = StateEdKey(key)
  let policy = ValidatorStateConfig(cores: CoreCount(3), validators: ElementLimit(9),
      maxBytes: ByteLimit(4096))
  let encoded = validatorEntry(ValidatorChapter.Active, values, policy).value
  decodeStateValidators(encoded.value, policy).value.value
proc sameValidator(left, right: ValidatorActivity) =
  ## Compare all six fixed E4 counters without depending on array equality for nominal values.
  for measure in low(ValidatorMeasure)..high(ValidatorMeasure):
    assert uint32(left[measure]) == uint32(right[measure])
proc context(target = 2'u32, author = 2'u64): ValidatorActivityContext =
  ## Original block summary deliberately credits three tickets and preimages to one author.
  ValidatorActivityContext(previousTime: StateTime(1), target: StateTime(target),
      epochSlots: EpochSlots(12),
    author: StatisticsValidatorIndex(author), tickets: ActivityNatural(3))

proc checkValidatorProjection*() =
  ## Literal same/boundary/skipped/resized epochs distinguish old assurance increments from new block activity.
  let initial = seeded()
  let prior = captured(initial)
  let roster = active()
  let bigger = active(9)
  let preimages = provided()
  let empty = decodeOwnedPreimages(@[0'u8], PreimageLimits()).value
  let wrong = decodeOwnedBytes(@[0'u8], ByteLimit(1)).value
  let votes = [Assurance(validator: ValidatorIndex(0)), Assurance(validator: ValidatorIndex(0)),
    Assurance(validator: ValidatorIndex(5))]
  let reporters = [roster.validatorAt(StateValidatorIndex(2)).value.ed25519,
    roster.validatorAt(StateValidatorIndex(2)).value.ed25519,
    roster.validatorAt(StateValidatorIndex(4)).value.ed25519, default(StateEdKey)]
  failHash(3)
  for mode in 0..<4:
    let summary = context(if mode == 0: 2'u32 elif mode == 1: 12'u32 else: 36'u32)
    let selected = if mode == 3: bigger else: roster
    let count = if mode == 3: 9 else: 6
    let result = projectValidatorActivity(prior, selected, summary, preimages, votes, reporters,
        validatorPolicy()).value
    assert result.info.rolled == (mode != 0)
    assert result.info.validators == [count, (if mode == 0: 9 else: 6)]
    assert result.info.preimages == 3 and result.info.assurances == 3 and result.info.reporters == 4
    for epoch in low(StatisticsEpoch)..high(StatisticsEpoch):
      for index in 0..<result.values[epoch].len:
        var expected = default(ValidatorActivity)
        if mode == 0:
          expected = initial.validators[epoch][index] # Same epoch retains both prior populations.
        elif epoch == StatisticsEpoch.Previous:
          expected = initial.validators[StatisticsEpoch.Current][index] # Rotate once even over skipped epochs.
        if (mode == 0 and epoch == StatisticsEpoch.Current) or (mode != 0 and epoch ==
            StatisticsEpoch.Previous):
          if index == 0 or index == 5:
            expected[ValidatorMeasure.Assurances] = ValidatorCounter(uint32(expected[
                ValidatorMeasure.Assurances])+1)
        if epoch == StatisticsEpoch.Current:
          if index == 2:
            for measure, amount in [1'u32, 3, 3, 3]:
              expected[ValidatorMeasure(measure)] = ValidatorCounter(uint32(expected[
                  ValidatorMeasure(measure)])+amount)
          if index == 2 or index == 4:
            expected[ValidatorMeasure.Guarantees] = ValidatorCounter(uint32(expected[
                ValidatorMeasure.Guarantees])+1)
        sameValidator(result.values[epoch][index], expected)
  failHash(0)
  for measure in low(ValidatorMeasure)..high(ValidatorMeasure):
    var state = initial
    let index = if measure == ValidatorMeasure.Assurances: 0 else: 2
    state.validators[StatisticsEpoch.Current][index][measure] = ValidatorCounter(high(uint32))
    let maximum = captured(state)
    failHash(3)
    assert projectValidatorActivity(maximum, roster, context(), preimages, votes, reporters,
        validatorPolicy()).error == ValidatorActivityError.CounterOverflow
    if measure == ValidatorMeasure.Assurances:
      assert projectValidatorActivity(maximum, roster, context(12), preimages, votes, reporters,
          validatorPolicy()).error == ValidatorActivityError.CounterOverflow
    failHash(0)
  failHash(3)
  for mode in 0..<8:
    var policy = validatorPolicy()
    case mode
    of 0: policy.validators = ElementLimit(8) # Previous population is independently nine.
    of 1: policy.tickets = ElementLimit(2) # Original ticket introductions are bounded even without copying proofs.
    of 2: policy.preimages = ElementLimit(2) # Empty blobs still count as records.
    of 3: policy.assurances = ElementLimit(2) # Repeated raw records still consume inspected work.
    of 4: policy.reporters = ElementLimit(3) # Reporter set scanning has an independent bound.
    of 5: policy.reporterWork = ElementLimit(23) # Six active keys times four raw reporter keys require 24 comparisons.
    of 6: policy.preimageFrameBytes = ByteLimit(18) # Full encoded capture has nineteen bytes.
    else: policy.preimageBytes = ByteLimit(2) # Aggregate payload size is exactly three bytes.
    assert projectValidatorActivity(prior, roster, context(), preimages, votes, reporters,
        policy).error == ValidatorActivityError.LimitExceeded
  var exact = validatorPolicy()
  exact.reporterWork = ElementLimit(24)
  assert projectValidatorActivity(prior, roster, context(), preimages, votes, reporters,
      exact).error == ValidatorActivityError.None
  var wide = validatorPolicy()
  wide.validators = ElementLimit(high(uint64))
  wide.tickets = ElementLimit(high(uint64))
  wide.preimages = ElementLimit(high(uint64))
  wide.assurances = ElementLimit(high(uint64))
  wide.reporters = ElementLimit(high(uint64))
  wide.reporterWork = ElementLimit(high(uint64))
  wide.preimageFrameBytes = ByteLimit(high(uint64))
  wide.preimageBytes = ByteLimit(high(uint64))
  assert projectValidatorActivity(prior, roster, context(), preimages, votes, reporters,
      wide).error == ValidatorActivityError.None
  for frame in [default(OwnedFrame), wrong]:
    assert projectValidatorActivity(prior, roster, context(), frame, votes, reporters,
        exact).error == ValidatorActivityError.InvalidInput
  assert projectValidatorActivity(default(ActivitySnapshot), roster, context(), empty, [], [],
      exact).error == ValidatorActivityError.InvalidInput
  assert projectValidatorActivity(prior, default(ValidatorStateSnapshot), context(), empty, [], [],
      exact).error == ValidatorActivityError.InvalidInput
  assert projectValidatorActivity(prior, bigger, context(), empty, [], [], exact).error ==
      ValidatorActivityError.InvalidState
  assert projectValidatorActivity(prior, roster, context(author = high(uint64)), empty, [], [],
      exact).error == ValidatorActivityError.InvalidIndex
  assert projectValidatorActivity(prior, bigger, context(12), empty, [Assurance(
      validator: ValidatorIndex(6))], [], exact).error == ValidatorActivityError.InvalidInput
  var bad = context()
  bad.epochSlots = EpochSlots(0)
  assert projectValidatorActivity(prior, roster, bad, empty, [], [], exact).error ==
      ValidatorActivityError.InvalidConfig
  bad = context(1)
  assert projectValidatorActivity(prior, roster, bad, empty, [], [], exact).error ==
      ValidatorActivityError.InvalidSlot
  assert hashCalls() == 0
  failHash(0)

proc checkValidatorSource*(base: OwnedReport) =
  ## Every source family comes from an honestly signed child and its exact parent C(13), not detached caller metrics.
  let initial = seeded(cores = 2, previous = 6)
  let entry = activityStateEntry(initial, statisticsPolicy(2, 6, 6)).value
  var retained = PreparedValidatorActivity()
  for available in [false, true]:
    var signedOptions0 = signedBlockFixtureConfig()
    signedOptions0.withAvailable = available
    signedOptions0.extra = @[entry]
    signedOptions0.preimageWire = preimageWire()
    let child = authored(base, signedOptions0)
    let source = planBlockReports(child.staged, child.older, config()).value
    let author = int(uint16(child.staged.value.admitted.admittedHeader.headerInfo.value.unsigned.author))
    let credentials = source.reportCredentials.value
    let activeBytes = child.staged.value.snapshot.lookup(chapterKey(StateChapter(8))).value.bytes
    let roster = decodeStateValidators(activeBytes, ValidatorStateConfig(cores: CoreCount(2),
      validators: ElementLimit(6), maxBytes: ByteLimit(4096))).value.value
    failHash(3)
    let plan = prepareValidatorActivity(source, validatorPolicy()).value
    assert not plan.validatorActivityInfo.value.rolled
    assert plan.validatorActivityInfo.value.preimages == 3 and
        plan.validatorActivityInfo.value.tickets == 0
    assert plan.validatorActivityInfo.value.assurances == (if available: 5 else: 0)
    assert plan.validatorActivityInfo.value.reporters == credentials.verifiedReporterCount.value
    for epoch in low(StatisticsEpoch)..high(StatisticsEpoch):
      for index in 0..<6:
        var expected = initial.validators[epoch][index]
        if epoch == StatisticsEpoch.Current:
          if index == author:
            expected[ValidatorMeasure.Blocks] = ValidatorCounter(uint32(expected[
                ValidatorMeasure.Blocks])+1)
            expected[ValidatorMeasure.PreimageCount] = ValidatorCounter(uint32(expected[
                ValidatorMeasure.PreimageCount])+3)
            expected[ValidatorMeasure.PreimageBytes] = ValidatorCounter(uint32(expected[
                ValidatorMeasure.PreimageBytes])+3)
          if available and index < 5:
            expected[ValidatorMeasure.Assurances] = ValidatorCounter(uint32(expected[
                ValidatorMeasure.Assurances])+1)
          let key = array[32, byte](roster.validatorAt(StateValidatorIndex(uint64(
              index))).value.ed25519)
          for ordinal in 0..<credentials.verifiedReporterCount.value:
            if key == array[32, byte](credentials.verifiedReporterAt(ordinal).value):
              expected[ValidatorMeasure.Guarantees] = ValidatorCounter(uint32(expected[
                  ValidatorMeasure.Guarantees])+1)
              break # A set member earns one increment independently of how many reports it signed.
        sameValidator(plan.validatorActivityAt(epoch, StatisticsValidatorIndex(uint64(
            index))).value, expected)
    var copied = plan.validatorActivityAt(StatisticsEpoch.Current, StatisticsValidatorIndex(0)).value
    copied[ValidatorMeasure.Blocks] = ValidatorCounter(0)
    assert uint32(plan.validatorActivityAt(StatisticsEpoch.Current, StatisticsValidatorIndex(
        0)).value[ValidatorMeasure.Blocks]) != 0
    assert plan.validatorActivityAt(StatisticsEpoch.Current, StatisticsValidatorIndex(high(
        uint64))).error == ValidatorActivityError.InvalidIndex
    assert plan.validatorActivityAt(cast[StatisticsEpoch](255'u8), StatisticsValidatorIndex(
        0)).error == ValidatorActivityError.InvalidTag
    for mode in 0..<5:
      var short = validatorPolicy()
      case mode
      of 0: short.rosterBytes = ByteLimit(0) # Parent/posterior rosters have their own capture ceiling.
      of 1: short.statisticsBytes = ByteLimit(0) # Prior full statistics bytes are checked before parsing.
      of 2: short.preimageFrameBytes = ByteLimit(18) # Original component includes all nineteen encoded bytes.
      of 3: short.assuranceBytes = ByteLimit(0) # Even an empty assurance component consumes its count byte.
      else: short.reporterWork = ElementLimit(0) # Verified reporter matching must still obey work policy.
      assert prepareValidatorActivity(source, short).error == ValidatorActivityError.LimitExceeded
    assert sameStateSnapshot(plan.validatorActivitySource.value.reportBlockStage.value.value.admitted.admittedState,
      child.staged.value.admitted.admittedState) # The complete parent map remains the exact retained source.
    let before = getOccupiedMem()
    for iteration in 0..<1000:
      let local = prepareValidatorActivity(source, validatorPolicy()).value
      assert local.validatorActivityInfo.value.preimages == 3
    assert before == getOccupiedMem() # Captured C(13), three roster owners, votes and result rows retire each cycle.
    assert hashCalls() == 0
    retained = plan
    failHash(0)
  assert retained.validatorActivitySource.value.reportCredentials.value.verifiedGuaranteeCount.value == 2
  assert retained.validatorActivityInfo.value.assurances ==
      5 # Source survives release of all local child handles.
  for mode in 0..<3:
    var entries: seq[StateEntry] = @[]
    if mode != 0:
      var damaged = entry
      if mode == 1: damaged.value.add(0) # Exact statistics chapters reject a suffix.
      else: damaged.value = @[0'u8] # Malformed counts are never a default empty state.
      entries.add(damaged)
    var signedOptions1 = signedBlockFixtureConfig()
    signedOptions1.extra = entries
    let child = authored(base, signedOptions1)
    let source = planBlockReports(child.staged, child.older, config()).value
    assert prepareValidatorActivity(source, validatorPolicy()).error == (if mode ==
        0: ValidatorActivityError.MissingState else: ValidatorActivityError.InvalidState)
  var oldServices = initial
  oldServices.services = @[ServiceStatisticsEntry(service: ServiceIndex(42))]
  var encoding = statisticsPolicy(2, 6, 6)
  encoding.maxServices = ElementLimit(1)
  let serviceEntry = activityStateEntry(oldServices, encoding).value
  var signedOptions2 = signedBlockFixtureConfig()
  signedOptions2.extra = @[serviceEntry]
  let servicesChild = authored(base, signedOptions2)
  let servicesSource = planBlockReports(servicesChild.staged, servicesChild.older, config()).value
  assert prepareValidatorActivity(servicesSource, validatorPolicy()).error ==
      ValidatorActivityError.LimitExceeded
  var oneService = validatorPolicy()
  oneService.services = ElementLimit(1)
  assert prepareValidatorActivity(servicesSource, oneService).error == ValidatorActivityError.None
  assert prepareValidatorActivity(default(AdmittedReports), validatorPolicy()).error ==
      ValidatorActivityError.InvalidSource
