# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "validator_projection_arc_release"}

## Independent literal epoch/counter witnesses, refusal boundaries and immutable ARC ownership.

import std/[assertions, syncio]
import ../../../src/state/validator_projection
import ../../../src/codec/[bounded, header, assurances, state_safrole, state_statistics]
import ../../support/arc_evidence

# Observer refusal proves that projection never calls the hashing backend.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

# Policies cover exact small input work and two independent retained populations.
proc limits(rows = 15'u64, assurances = 3'u64, reporters = 3'u64,
    comparisons = 27'u64): ValidatorActivityLimits =
  ValidatorActivityLimits(rows: ElementLimit(rows), assurances: ElementLimit(assurances),
    reporters: ElementLimit(reporters), comparisons: ElementLimit(comparisons))

# Distinct keys deliberately differ in their last octet, not just their first.
proc key(index: int): StateEdKey =
  var bytes = default(array[32, byte])
  bytes[31] = byte(index+1)
  StateEdKey(bytes)

# Populate all six measures so retained rows cannot accidentally become zeros or swap epochs.
proc source(current = 6, previous = 9, overflow = -1,
    measure = ValidatorMeasure.Blocks, counter = high(uint32)): ActivitySnapshot =
  var state = default(ActivityState)
  state.validators[StatisticsEpoch.Current] = newSeq[ValidatorActivity](current)
  state.validators[StatisticsEpoch.Previous] = newSeq[ValidatorActivity](previous)
  state.cores = newSeq[CoreActivity](3)
  for epoch in low(StatisticsEpoch)..high(StatisticsEpoch):
    for index in 0..<state.validators[epoch].len:
      for field in low(ValidatorMeasure)..high(ValidatorMeasure):
        state.validators[epoch][index][field] = ValidatorCounter(uint32(
          1000*ord(epoch)+100*index+ord(field))) # Independent recognizable field/position values.
  if overflow >= 0:
    state.validators[StatisticsEpoch.Current][overflow][measure] = ValidatorCounter(counter)
  let config = ActivityConfig(cores: CoreCount(3), current: ValidatorCount(uint64(current)),
    previous: ValidatorCount(uint64(previous)), maxServices: ElementLimit(0), maxBytes: ByteLimit(4096))
  let wire = activityStateEntry(state, config).value.value
  decodeActivityState(wire, config).value.snapshot

# An independently decoded posterior roster can change positions/population across a rotation.
proc roster(count = 6, reverse = false, repeated = false): ValidatorStateSnapshot =
  var values = newSeq[StateValidator](count)
  for index in 0..<count:
    let identity = if repeated: 1 else: (if reverse: count-index-1 else: index)
    values[index].ed25519 = key(identity)
  let config = ValidatorStateConfig(cores: CoreCount(3), validators: ElementLimit(9),
    maxBytes: ByteLimit(4096))
  let wire = validatorEntry(ValidatorChapter.Active, values, config).value.value
  decodeStateValidators(wire, config).value.value

# Three author fields vary independently; chronology can skip multiple whole epochs.
proc observations(slot = 2'u32): ValidatorActivityObservations =
  ValidatorActivityObservations(parentSlot: StateTime(1), slot: StateTime(slot),
    epochSlots: EpochSlots(12), author: AuthorIndex(1), tickets: ActivityNatural(2),
    preimages: ActivityNatural(3), preimageBytes: ActivityNatural(17))

# Independent literal arithmetic checks all fields in both epochs, not just modified cells.
proc witnesses() =
  let parent = source()
  let posterior = roster()
  let events = observations()
  let result = projectValidatorActivity(parent, posterior, events,
    [ValidatorIndex(0), ValidatorIndex(0), ValidatorIndex(5)], [key(1), key(1), key(99)], limits())
  assert result.error == ValidatorActivityError.None, "same epoch succeeds"
  let plan = result.value
  assert not plan.validatorActivityInfo.value.rotated, "same epoch retains history"
  for epoch in low(StatisticsEpoch)..high(StatisticsEpoch):
    for index in 0..<(if epoch == StatisticsEpoch.Current: 6 else: 9):
      let row = plan.projectedValidatorAt(epoch, StatisticsValidatorIndex(uint64(index))).value
      for measure in low(ValidatorMeasure)..high(ValidatorMeasure):
        var expected = uint32(1000*ord(epoch)+100*index+ord(measure))
        if epoch == StatisticsEpoch.Current:
          if measure == ValidatorMeasure.Assurances and (index == 0 or index == 5): inc expected
          if index == 1:
            case measure
            of ValidatorMeasure.Blocks, ValidatorMeasure.Guarantees: inc expected
            of ValidatorMeasure.Tickets: expected += 2
            of ValidatorMeasure.PreimageCount: expected += 3
            of ValidatorMeasure.PreimageBytes: expected += 17
            else: discard # No assurance from the author in this witness.
        assert uint32(row[measure]) == expected, "literal same-epoch field"
  for slot in [12'u32, 48'u32, high(uint32)]:
    let rotated = projectValidatorActivity(parent, roster(9, reverse = true), observations(slot),
      [ValidatorIndex(5)], [key(0), key(99)], limits(15, 1, 2, 18)).value
    let info = rotated.validatorActivityInfo.value
    assert info.rotated and info.current == 9 and info.previous == 6, "rotate once to new population"
    for index in 0..<6:
      let row = rotated.projectedValidatorAt(StatisticsEpoch.Previous,
        StatisticsValidatorIndex(uint64(index))).value
      for measure in low(ValidatorMeasure)..high(ValidatorMeasure):
        let extra = if index == 5 and measure == ValidatorMeasure.Assurances: 1 else: 0
        assert uint32(row[measure]) == uint32(100*index+ord(measure)+extra), "assurance before rotation"
    for index in 0..<9:
      let row = rotated.projectedValidatorAt(StatisticsEpoch.Current,
        StatisticsValidatorIndex(uint64(index))).value
      let expected: ValidatorActivity = if index == 1:
        [ValidatorCounter(1), ValidatorCounter(2), ValidatorCounter(3), ValidatorCounter(17),
          ValidatorCounter(0), ValidatorCounter(0)]
        elif index == 8:
          [ValidatorCounter(0), ValidatorCounter(0), ValidatorCounter(0), ValidatorCounter(0),
            ValidatorCounter(1), ValidatorCounter(0)]
        else: default(ValidatorActivity)
      assert row == expected, "fresh current uses posterior reporter identity"
  let shrunk = projectValidatorActivity(source(9, 6), roster(), observations(12),
    [ValidatorIndex(8)], [], limits(15, 1, 0, 0)).value
  assert shrunk.validatorActivityInfo.value.current == 6, "rotation can shrink current roster"
  assert shrunk.validatorActivityInfo.value.previous == 9, "old current determines previous population"
  assert uint32(shrunk.projectedValidatorAt(StatisticsEpoch.Previous,
    StatisticsValidatorIndex(8)).value[ValidatorMeasure.Assurances]) == 806,
    "assurer belongs to old roster even beyond posterior size"
  var empty = events
  empty.tickets = ActivityNatural(0)
  empty.preimages = ActivityNatural(0)
  empty.preimageBytes = ActivityNatural(0)
  let noObservations = projectValidatorActivity(parent, posterior, empty, [], [], limits(15, 0, 0, 0)).value
  let emptyRow: ValidatorActivity = [ValidatorCounter(101), ValidatorCounter(101), ValidatorCounter(102),
    ValidatorCounter(103), ValidatorCounter(104), ValidatorCounter(105)]
  assert noObservations.projectedValidatorAt(StatisticsEpoch.Current,
    StatisticsValidatorIndex(1)).value == emptyRow, "empty observations still count the author block"
  let repeated = projectValidatorActivity(parent, roster(repeated = true), events, [],
    [key(1), key(1)], limits()).value
  for index in 0..<6:
    assert uint32(repeated.projectedValidatorAt(StatisticsEpoch.Current,
      StatisticsValidatorIndex(uint64(index))).value[ValidatorMeasure.Guarantees]) == uint32(
        100*index+5), "each matching roster position increments once"

# Exercise every fixed counter's exact endpoint and one-unit overflow, including pre-rotation assurances.
proc overflowWitnesses() =
  for measure in low(ValidatorMeasure)..high(ValidatorMeasure):
    let parent = source(overflow = 1, measure = measure)
    let after = roster()
    var events = observations()
    events.tickets = ActivityNatural(0)
    events.preimages = ActivityNatural(0)
    events.preimageBytes = ActivityNatural(0)
    if measure == ValidatorMeasure.Tickets: events.tickets = ActivityNatural(1)
    if measure == ValidatorMeasure.PreimageCount: events.preimages = ActivityNatural(1)
    if measure == ValidatorMeasure.PreimageBytes: events.preimageBytes = ActivityNatural(1)
    let near = source(overflow = 1, measure = measure, counter = high(uint32)-1)
    let endpoint = projectValidatorActivity(near, after, events,
      [ValidatorIndex(1)], [key(1)], limits()).value
    assert uint32(endpoint.projectedValidatorAt(StatisticsEpoch.Current,
      StatisticsValidatorIndex(1)).value[measure]) == high(uint32), "each counter accepts exact endpoint"
    let failed = projectValidatorActivity(parent, after, events,
      [ValidatorIndex(1)], [key(1)], limits())
    assert failed.error == ValidatorActivityError.CounterOverflow, "each E4 counter refuses wrap"
    if measure == ValidatorMeasure.Assurances:
      events.slot = StateTime(12)
      assert projectValidatorActivity(parent, after, events, [ValidatorIndex(1)], [],
        limits()).error == ValidatorActivityError.CounterOverflow, "old assurance overflows before rotation"
    else:
      events.slot = StateTime(12)
      assert projectValidatorActivity(parent, after, events, [], [key(1)],
        limits()).error == ValidatorActivityError.None, "fresh epoch discards current overflow risk"
  let parent = source()
  let after = roster()
  var events = observations()
  for measure in [ValidatorMeasure.Tickets, ValidatorMeasure.PreimageCount,
      ValidatorMeasure.PreimageBytes]:
    events = observations()
    let base = uint64(100+ord(measure))
    let exact = ActivityNatural(uint64(high(uint32))-base)
    case measure
    of ValidatorMeasure.Tickets: events.tickets = exact
    of ValidatorMeasure.PreimageCount: events.preimages = exact
    else: events.preimageBytes = exact # Only selected author-byte measure remains.
    let plan = projectValidatorActivity(parent, after, events, [], [], limits()).value
    assert uint32(plan.projectedValidatorAt(StatisticsEpoch.Current,
      StatisticsValidatorIndex(1)).value[measure]) == high(uint32), "exact E4 endpoint"
    case measure
    of ValidatorMeasure.Tickets: events.tickets = ActivityNatural(uint64(exact)+1)
    of ValidatorMeasure.PreimageCount: events.preimages = ActivityNatural(uint64(exact)+1)
    else: events.preimageBytes = ActivityNatural(high(uint64)) # Full-width addition must never wrap.
    assert projectValidatorActivity(parent, after, events, [], [],
      limits()).error == ValidatorActivityError.CounterOverflow, "oversized explicit contribution"

# Policies, default owners, chronology and nominal positions refuse without a partial owner.
proc refusals() =
  let parent = source()
  let after = roster()
  let events = observations()
  let blank = default(ValidatorActivityResult[ValidatorActivityProjection])
  assert blank.error == ValidatorActivityError.Uninitialized
  assert default(ValidatorActivityProjection).validatorActivityInfo.error ==
      ValidatorActivityError.Uninitialized
  assert default(ValidatorActivityProjection).projectedValidatorAt(StatisticsEpoch.Current,
    StatisticsValidatorIndex(0)).error == ValidatorActivityError.Uninitialized
  assert projectValidatorActivity(default(ActivitySnapshot), after, events, [], [],
    limits()).error == ValidatorActivityError.InvalidSource
  assert projectValidatorActivity(parent, default(ValidatorStateSnapshot), events, [], [],
    limits()).error == ValidatorActivityError.InvalidSource
  for slot in [0'u32, 1'u32]:
    assert projectValidatorActivity(parent, after, observations(slot), [], [],
      limits()).error == ValidatorActivityError.InvalidTime
  var invalid = events
  invalid.epochSlots = EpochSlots(0)
  assert projectValidatorActivity(parent, after, invalid, [], [],
    limits()).error == ValidatorActivityError.InvalidTime
  invalid = events
  invalid.author = AuthorIndex(high(uint16))
  assert projectValidatorActivity(parent, after, invalid, [], [],
    limits()).error == ValidatorActivityError.InvalidAuthor
  assert projectValidatorActivity(parent, roster(9), events, [], [],
    limits()).error == ValidatorActivityError.InvalidPopulation
  for index in [6'u16, high(uint16)]:
    assert projectValidatorActivity(parent, after, events, [ValidatorIndex(0), ValidatorIndex(
        index)], [],
      limits()).error == ValidatorActivityError.InvalidAssurer
  for short in [limits(14), limits(15, 0), limits(15, 1, 0), limits(15, 1, 1, 5)]:
    assert projectValidatorActivity(parent, after, events, [ValidatorIndex(0)], [key(0)],
      short).error == ValidatorActivityError.LimitExceeded
  let exact = projectValidatorActivity(parent, after, events, [ValidatorIndex(0)], [key(0)],
    limits(15, 1, 1, 6)).value
  let full = projectValidatorActivity(parent, after, events, [], [],
    limits(high(uint64), high(uint64), high(uint64), high(uint64))).value
  assert full.validatorActivityInfo.value.current == 6, "full-width policy never allocates maxima"
  invalid = events
  invalid.epochSlots = EpochSlots(high(uint64))
  assert not projectValidatorActivity(parent, after, invalid, [], [],
    limits()).value.validatorActivityInfo.value.rotated, "full-width epoch division"
  for epoch in low(StatisticsEpoch)..high(StatisticsEpoch):
    let count = if epoch == StatisticsEpoch.Current: 6'u64 else: 9'u64
    for index in [count, high(uint64)]:
      assert exact.projectedValidatorAt(epoch, StatisticsValidatorIndex(index)).error ==
          ValidatorActivityError.InvalidIndex
  assert exact.projectedValidatorAt(cast[StatisticsEpoch](255),
    StatisticsValidatorIndex(0)).error == ValidatorActivityError.InvalidEpoch

# Independent retained owners survive source scope and caller observation/copy mutations.
proc detached(): ValidatorActivityProjection =
  var reports = @[key(1)]
  var assurances = @[ValidatorIndex(1)]
  result = projectValidatorActivity(source(), roster(), observations(), assurances, reports, limits()).value
  reports[0] = key(99)
  assurances[0] = ValidatorIndex(5)

# Isolate hash-disabled success and refusal lifetimes over a measured ARC workload.
proc cycle(parent: ActivitySnapshot, after: ValidatorStateSnapshot) =
  let plan = projectValidatorActivity(parent, after, observations(12), [ValidatorIndex(0)],
    [key(1)], limits()).value
  assert plan.validatorActivityInfo.value.rotated, "cycle keeps rotation witness"
  assert projectValidatorActivity(parent, after, observations(), [], [],
    limits(0)).error == ValidatorActivityError.LimitExceeded, "cycle includes refusal"

proc main() =
  ## All protocol witnesses run with the hashing backend disabled.
  failHash(3)
  witnesses()
  overflowWitnesses()
  refusals()
  let owned = detached()
  var row = owned.projectedValidatorAt(StatisticsEpoch.Current, StatisticsValidatorIndex(1)).value
  assert uint32(row[ValidatorMeasure.Assurances]) == 106, "borrowed assurance list detached"
  assert uint32(row[ValidatorMeasure.Guarantees]) == 105, "borrowed reporter list detached"
  row[ValidatorMeasure.Guarantees] = ValidatorCounter(0)
  assert uint32(owned.projectedValidatorAt(StatisticsEpoch.Current,
    StatisticsValidatorIndex(1)).value[ValidatorMeasure.Guarantees]) == 105, "row extraction copied"
  let parent = source()
  let after = roster()
  cycle(parent, after)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(parent, after) # Every success/refusal owner dies before the next iteration.
  let occupied = getOccupiedMem()
  assert before == occupied, "validator projection ARC release"
  assert hashCalls() == 0, "projection performs no backend calls"
  failHash(0)
  recordArcRelease("validator_projection", 1000, before, occupied)
  echo "Validator activity projection passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

main()
