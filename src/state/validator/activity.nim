# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Apply old-epoch assurances, rotate epoch statistics, and credit original-block author/reporter activity.
## Raw projections certify no provenance; opaque preparation derives every context from one admitted block.

import ../../codec/[bounded, composite, owned]
import ../../codec/state/[statistics as state_statistics, safrole as state_safrole,
    layout as state_layout]
import ../../codec/[block_codec, header, assurances, tickets]
import ../report/admission as report_admission
import ../guarantee_credentials
import "../block/transition" as block_transition
import "../block/admission" as block_admission
import ../store

type
  ValidatorActivityConfig* = object ## Independent population, comparison-work and capture ceilings.
    validators*, services*, tickets*, preimages*, assurances*, reporters*,
      reporterWork*: ElementLimit
    rosterBytes*, statisticsBytes*, preimageFrameBytes*, preimageBytes*, assuranceBytes*: ByteLimit
  ValidatorActivityContext* = object ## Explicit raw block summary has no admission or epoch provenance certificate.
    previousTime*, target*: StateTime
    epochSlots*: EpochSlots
    author*: StatisticsValidatorIndex
    tickets*: ActivityNatural
  ValidatorActivityInfo* = object ## Copied output populations and actual inspected input families.
    validators*: array[StatisticsEpoch, int]
    rolled*: bool
    tickets*: uint64
    preimages*, assurances*, reporters*: int
  ValidatorActivityProjection* = object ## Caller-owned epoch rows cannot substitute for an admitted source.
    info*: ValidatorActivityInfo
    values*: array[StatisticsEpoch, seq[ValidatorActivity]]
  ValidatorActivityError* {.pure.} = enum ## Defaults and failures expose only reasons, never output prefixes.
    Uninitialized,  ## Default result or owner.
    None,           ## Complete selected success.
    InvalidSource,  ## No genuine admitted-report source.
    MissingState,   ## Required complete-map chapter is absent.
    InvalidState,   ## Source chapter is malformed, inexact or inconsistent with its roster.
    InvalidInput,   ## Default/wrong-schema raw owner or invalid assurer index.
    InvalidConfig,  ## Zero epoch length.
    InvalidSlot,    ## Target time is not strictly later.
    InvalidIndex,   ## Author or extraction ordinal lies outside the selected population.
    InvalidTag,     ## Forged epoch selector.
    LimitExceeded,  ## Inspected work/capture/output exceeds local policy.
    CounterOverflow ## Mathematical counter cannot fit the fixed E4 representation.
  ActivityData = ref object # Acyclic private storage retains one exact source and independent immutable epoch rows.
    source: AdmittedReports
    info: ValidatorActivityInfo
    values: array[StatisticsEpoch, seq[ValidatorActivity]]
  PreparedValidatorActivity* = object ## Epoch metrics establish source provenance, not complete block validity or C(13).
    data: nil ActivityData
  ValidatorActivityResult*[T] = object ## Only the selected success alternative contains application data.
    case status: ValidatorActivityError
    of None:
      completed: T # Payload/discriminator cannot be forged or retagged externally.
    else:
      discard      # Failed projection never exposes partially incremented rows.

func error*[T](outcome: ValidatorActivityResult[T]): ValidatorActivityError =
  ## Inspect the immutable selected reason.
  outcome.status
func value*[T](outcome: ValidatorActivityResult[T]): T {.inline,
    requires: outcome.status == ValidatorActivityError.None.} =
  ## Extract only complete success in checked optimized builds.
  outcome.completed
func populations(current, previous, active, preimages, assurances, reporters: int,
    tickets: uint64, config: ValidatorActivityConfig): bool =
  ## Bound each typed population and reporter-key comparisons before copying or allocating.
  uint64(current) <= uint64(config.validators) and uint64(previous) <= uint64(config.validators) and
    uint64(active) <= uint64(config.validators) and tickets <= uint64(config.tickets) and
    uint64(preimages) <= uint64(config.preimages) and
    uint64(assurances) <= uint64(config.assurances) and assurances <= high(int) div sizeof(
        Assurance) and
    uint64(reporters) <= uint64(config.reporters) and reporters <= high(int) div sizeof(
        StateEdKey) and
    uint64(reporters) <= uint64(config.reporterWork) div uint64(active)
proc add(target: var ValidatorCounter, amount: uint64): bool =
  ## Prove the E4 sum in a wider domain before changing private scratch.
  if amount > uint64(high(uint32))-uint64(uint32(target)): return false # Never wrap or clamp a natural statistic.
  target = ValidatorCounter(uint32(uint64(uint32(target))+amount))
  true

proc projectValidatorActivity*(prior: ActivitySnapshot, active: ValidatorStateSnapshot,
    context: ValidatorActivityContext, preimages: OwnedFrame, assurances: openArray[Assurance],
    reporters: openArray[StateEdKey], config: ValidatorActivityConfig): ValidatorActivityResult[
        ValidatorActivityProjection] =
  ## Borrow stable raw owners; assurance indices refer to the old current epoch, reporter keys to posterior active keys.
  template fail(reason: ValidatorActivityError) =
    ## Discard all private scratch on refusal.
    return ValidatorActivityResult[ValidatorActivityProjection](status: reason)
  let before = prior.activityInfo
  let roster = active.validatorCount
  let provided = preimages.ownedInfo
  if before.error != ActivityError.None or roster.error != StateComponentError.None or
      provided.error != OwnershipError.None or provided.value.kind != OwnedKind.Preimages:
    fail(ValidatorActivityError.InvalidInput) # A default owner cannot masquerade as an empty valid input.
  if uint64(context.epochSlots) == 0: fail(ValidatorActivityError.InvalidConfig)
  if uint32(context.target) <= uint32(context.previousTime): fail(
      ValidatorActivityError.InvalidSlot)
  let current = before.value.validators[StatisticsEpoch.Current]
  let previous = before.value.validators[StatisticsEpoch.Previous]
  let count = roster.value
  let rolled = uint64(uint32(context.target)) div uint64(context.epochSlots) !=
    uint64(uint32(context.previousTime)) div uint64(context.epochSlots)
  if not rolled and current != count: fail(ValidatorActivityError.InvalidState)
  if uint64(context.author) >= uint64(count): fail(ValidatorActivityError.InvalidIndex)
  if not populations(current, previous, count, provided.value.blobCount, assurances.len,
      reporters.len, uint64(context.tickets), config) or
      uint64(provided.value.consumed) > uint64(config.preimageFrameBytes):
    fail(ValidatorActivityError.LimitExceeded) # Caps precede descriptor and output work.
  var bytes = 0'u64
  for index in 0..<provided.value.blobCount:
    let size = uint64(preimages.ownedBlobLength(index).value)
    if size > uint64(config.preimageBytes)-bytes: fail(ValidatorActivityError.LimitExceeded)
    bytes += size # Count even unneeded and repeated original preimages without copying payload bytes.
  for assurance in assurances:
    if uint64(uint16(assurance.validator)) >= uint64(current):
      fail(ValidatorActivityError.InvalidInput) # Availability votes use the old active index domain.
  var old = newSeq[ValidatorActivity](current)
  for index in 0..<current:
    old[index] = prior.validatorActivityAt(StatisticsEpoch.Current, StatisticsValidatorIndex(uint64(index))).value
  var seen = newSeq[bool](current)
  for assurance in assurances:
    let index = int(uint16(assurance.validator))
    if not seen[index]:
      if not add(old[index][ValidatorMeasure.Assurances], 1): fail(
          ValidatorActivityError.CounterOverflow)
      seen[index] = true # The equation uses existence, even if the unverified raw input repeats an assurer.
  var rows = default(array[StatisticsEpoch, seq[ValidatorActivity]])
  if rolled:
    rows[StatisticsEpoch.Previous] = old
    rows[StatisticsEpoch.Current] = newSeq[ValidatorActivity](
        count) # Any epoch jump rotates once to the updated old accumulator.
  else:
    rows[StatisticsEpoch.Current] = old
    rows[StatisticsEpoch.Previous] = newSeq[ValidatorActivity](previous)
    for index in 0..<previous:
      rows[StatisticsEpoch.Previous][index] = prior.validatorActivityAt(StatisticsEpoch.Previous,
        StatisticsValidatorIndex(uint64(index))).value # Same-epoch previous counters remain byte-for-byte equivalent.
  let author = int(uint64(context.author))
  if not add(rows[StatisticsEpoch.Current][author][ValidatorMeasure.Blocks], 1) or
      not add(rows[StatisticsEpoch.Current][author][ValidatorMeasure.Tickets], uint64(
          context.tickets)) or
      not add(rows[StatisticsEpoch.Current][author][ValidatorMeasure.PreimageCount], uint64(
          provided.value.blobCount)) or
      not add(rows[StatisticsEpoch.Current][author][ValidatorMeasure.PreimageBytes], bytes):
    fail(ValidatorActivityError.CounterOverflow) # Author credits follow rotation and count the original signed extrinsics.
  for index in 0..<count:
    let key = array[32, byte](active.validatorAt(StateValidatorIndex(uint64(index))).value.ed25519)
    for reporter in reporters:
      if key == array[32, byte](reporter):
        if not add(rows[StatisticsEpoch.Current][index][ValidatorMeasure.Guarantees], 1):
          fail(ValidatorActivityError.CounterOverflow)
        break # Membership in the reporter set credits once, never once per guarantee or repeated key.
  ValidatorActivityResult[ValidatorActivityProjection](status: ValidatorActivityError.None,
    completed: ValidatorActivityProjection(values: rows, info: ValidatorActivityInfo(
      validators: [count, (if rolled: current else: previous)], rolled: rolled,
      tickets: uint64(context.tickets), preimages: provided.value.blobCount,
      assurances: assurances.len, reporters: reporters.len)))

proc validatorActivityInfo*(plan: PreparedValidatorActivity): ValidatorActivityResult[
    ValidatorActivityInfo] =
  ## Copy observed populations and epoch disposition.
  let data = plan.data
  if data == nil: return ValidatorActivityResult[ValidatorActivityInfo](
      status: ValidatorActivityError.Uninitialized)
  ValidatorActivityResult[ValidatorActivityInfo](status: ValidatorActivityError.None,
      completed: data.info)
proc validatorActivitySource*(plan: PreparedValidatorActivity): ValidatorActivityResult[
    AdmittedReports] =
  ## Retain the exact signed source graph independently of caller handles.
  let data = plan.data
  if data == nil: return ValidatorActivityResult[AdmittedReports](
      status: ValidatorActivityError.Uninitialized)
  ValidatorActivityResult[AdmittedReports](status: ValidatorActivityError.None,
      completed: data.source)
proc validatorActivityAt*(plan: PreparedValidatorActivity, epoch: StatisticsEpoch,
    index: StatisticsValidatorIndex): ValidatorActivityResult[ValidatorActivity] =
  ## Copy a fixed row after validating the nominal epoch and full-width ordinal.
  let data = plan.data
  if data == nil: return ValidatorActivityResult[ValidatorActivity](
      status: ValidatorActivityError.Uninitialized)
  if ord(epoch) > ord(StatisticsEpoch.Previous):
    return ValidatorActivityResult[ValidatorActivity](status: ValidatorActivityError.InvalidTag)
  if uint64(index) >= uint64(data.values[epoch].len):
    return ValidatorActivityResult[ValidatorActivity](status: ValidatorActivityError.InvalidIndex)
  ValidatorActivityResult[ValidatorActivity](status: ValidatorActivityError.None,
    completed: data.values[epoch][int(uint64(index))])

proc prepareValidatorActivity*(source: AdmittedReports,
    config: ValidatorActivityConfig): ValidatorActivityResult[PreparedValidatorActivity] =
  ## Read parent statistics/time/rosters, posterior keys and exact original extrinsics from one admission certificate.
  template fail(reason: ValidatorActivityError) =
    ## Fail without publishing a state candidate or retaining a partial source prefix.
    return ValidatorActivityResult[PreparedValidatorActivity](status: reason)
  let staged = source.reportBlockStage
  if staged.error != ReportAdmissionError.None: fail(ValidatorActivityError.InvalidSource)
  let stage = staged.value
  let frame = stage.blockTransitionProfile
  let parent = stage.value.admitted.admittedState
  let header = stage.value.admitted.admittedHeader.headerInfo.value.unsigned
  var rosters = default(array[3, ValidatorStateSnapshot])
  for index in 0..<3:
    let snapshot = if index == 2: stage.value.snapshot else: parent # Only posterior active keys receive reporter credit.
    let chapter = if index == 1: 9'u8 else: 8'u8
    let raw = snapshot.lookup(chapterKey(StateChapter(chapter)))
    if raw.error != StateStoreError.None: fail(ValidatorActivityError.MissingState)
    if uint64(raw.value.byteLength) > uint64(config.rosterBytes): fail(
        ValidatorActivityError.LimitExceeded)
    let parsed = decodeStateValidators(raw.value.bytes, ValidatorStateConfig(cores: frame.cores,
      validators: config.validators, maxBytes: config.rosterBytes))
    if parsed.error == StateComponentError.LimitExceeded: fail(ValidatorActivityError.LimitExceeded)
    if parsed.error != StateComponentError.None or parsed.value.consumed != raw.value.byteLength:
      fail(ValidatorActivityError.InvalidState) # Exact chapter framing precedes C(13) roster-shape interpretation.
    rosters[index] = parsed.value.value
  let statistics = parent.lookup(chapterKey(StateChapter(13)))
  let time = parent.lookup(chapterKey(StateChapter(11)))
  if statistics.error != StateStoreError.None or time.error != StateStoreError.None:
    fail(ValidatorActivityError.MissingState)
  if uint64(statistics.value.byteLength) > uint64(config.statisticsBytes): fail(
      ValidatorActivityError.LimitExceeded)
  let oldTime = decodeStateTime(time.value.bytes)
  if oldTime.error != StateComponentError.None or oldTime.value.consumed != time.value.byteLength:
    fail(ValidatorActivityError.InvalidState)
  # Prior service rows have an independent item ceiling even though this layer updates only validator fields.
  let prior = decodeActivityState(statistics.value.bytes, ActivityConfig(cores: frame.cores,
    current: ValidatorCount(uint64(rosters[0].validatorCount.value)),
    previous: ValidatorCount(uint64(rosters[1].validatorCount.value)),
    maxServices: config.services,
        maxBytes: config.statisticsBytes))
  if prior.error in {ActivityError.LimitExceeded, ActivityError.LengthOverflow}:
    fail(ValidatorActivityError.LimitExceeded) # Prior service/capture policy is a local refusal, not malformed state.
  if prior.error != ActivityError.None or prior.value.consumed != statistics.value.byteLength:
    fail(ValidatorActivityError.InvalidState)
  let extrinsic = stage.value.admitted.admittedBlock.blockExtrinsic.value
  let provided = extrinsic.extrinsicPreimages.value
  let votes = extrinsic.extrinsicAssurances.value
  let preimages = provided.componentInfo.value
  let assurances = votes.componentInfo.value
  let tickets = extrinsic.extrinsicTickets.value.componentInfo.value.records
  let credentials = source.reportCredentials.value
  let reporters = credentials.verifiedReporterCount.value
  if not populations(rosters[0].validatorCount.value, rosters[1].validatorCount.value,
      rosters[2].validatorCount.value, preimages.records, assurances.records, reporters, uint64(
          tickets), config) or
      uint64(preimages.consumed) > uint64(config.preimageFrameBytes) or
      uint64(assurances.consumed) > uint64(config.assuranceBytes):
    fail(ValidatorActivityError.LimitExceeded) # Descriptor, encoded and comparison budgets precede materialization.
  var keys = newSeq[StateEdKey](reporters)
  for index in 0..<keys.len: keys[index] = credentials.verifiedReporterAt(index).value
  let context = ValidatorActivityContext(previousTime: oldTime.value.value,
    target: StateTime(uint32(header.slot)), epochSlots: frame.epochSlots,
    author: StatisticsValidatorIndex(uint16(header.author)), tickets: ActivityNatural(uint64(tickets)))
  let projected = projectValidatorActivity(prior.value.snapshot, rosters[2], context,
    provided.readPreimages.value, votes.readAssurances.value, keys, config)
  if projected.error != ValidatorActivityError.None: fail(projected.error)
  ValidatorActivityResult[PreparedValidatorActivity](status: ValidatorActivityError.None,
    completed: PreparedValidatorActivity(data: ActivityData(source: source,
      info: projected.value.info, values: projected.value.values)))
