# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit three-core policies separate bounded decoding capacity from actual six/nine-validator chapter populations.
import std/assertions
import ../../src/app/candidate as app_candidate
import ../../src/chain/parameters as chain_parameters
import ../../src/chain/genesis as chain_genesis
import ../../src/chain/provider as chain_provider
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_safrole as codec_state_safrole
import ../../src/codec/composite as codec_composite
import ../../src/codec/assurances as codec_assurances
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_consensus as codec_state_consensus
import ../../src/codec/state_authorization as codec_state_authorization
import ../../src/codec/state_availability as codec_state_availability
import ../../src/codec/state_statistics as codec_state_statistics
import ../../src/codec/state_privileges as codec_state_privileges
import ../../src/codec/state_disputes as codec_state_disputes
import ../../src/codec/report_owned as codec_report_owned
import ../../src/state/store as state_store
import ../../src/crypto/primitives as crypto_primitives
import ../../src/bandersnatch/bandersnatch as bandersnatch_bandersnatch
import ./state_current_stf_epoch_context as epoch
import ./state_current_consecutive_context
import ./state_accumulation_current_chain_context

proc populationParameters*(): Parameters =
  ## Preserve the frozen execution tuple except the full E2 core-count field at offset24.
  var wire = encodeParameters(currentChainSettings())
  wire[24] = 3
  wire[25] = 0
  decodeParameters(wire).value

proc populationLimits*(): CurrentCandidateLimits =
  ## One coherent ceiling-nine profile accepts independently shaped active, previous, pending and staging rosters.
  result = currentConsecutiveLimits()
  let roster = ValidatorStateConfig(cores: CoreCount(3), validators: ElementLimit(9),
      maxBytes: ByteLimit(4096))
  result.reporting.admission.frame.cores = CoreCount(3)
  result.reporting.admission.frame.validators = ValidatorCount(9)
  result.reporting.safrole.state.validators = roster
  result.reporting.disputes.rosters = roster
  result.reporting.disputes.availability.guarantee.cores = CoreCount(3)
  result.reporting.disputes.availability.guarantee.validators = ValidatorCount(9)
  result.reporting.disputes.availability.maxPresent = ElementLimit(3)
  result.reporting.availability.rosters = roster
  result.reporting.availability.assignments = result.reporting.disputes.availability
  result.reporting.reports.credentials.assignments.roster = roster
  result.reporting.reports.policy.pools.cores = CoreCount(3)
  result.reporting.reports.policy.pools.maxHashes = ElementLimit(240)
  result.reporting.reports.policy.pools.maxBytes = ByteLimit(7680)
  result.reporting.reports.anchors.history.cores = CoreCount(3)
  result.reporting.reports.ancestors.header.cores = CoreCount(3)
  result.reporting.reports.ancestors.header.authorValidators = ValidatorCount(9)
  result.reporting.reports.packages.availability = result.reporting.disputes.availability
  result.reporting.reports.packages.queues.cores = CoreCount(3)
  result.queue.queues.cores = CoreCount(3)
  result.round.privileges.cores = CoreCount(3)
  result.completion.execution.initial.guests.contexts.validators = ValidatorCount(9)
  result.completion.execution.initial.guests.contexts.queues.cores = CoreCount(3)
  result.completion.execution.initial.guests.contexts.queues.maxHashes = ElementLimit(240)
  result.completion.execution.initial.guests.contexts.queues.maxBytes = ByteLimit(7680)
  result.completion.execution.initial.guests.contexts.staging = roster
  result.completion.execution.initial.guests.contexts.privileges.cores = CoreCount(3)
  result.completion.execution.initial.globals.roles.privileges.cores = CoreCount(3)
  result.completion.execution.initial.globals.queues = result.completion.execution.initial.guests.contexts.queues
  result.completion.execution.initial.globals.staging = roster
  result.completion.execution.execution.round = result.completion.execution.initial
  result.completion.composition.finalization.history.queues.cores = CoreCount(3)
  result.completion.composition.ready.queues.cores = CoreCount(3)
  result.completion.composition.recent.history.cores = CoreCount(3)
  result.completion.composition.validators.validators = ElementLimit(9)
  result.completion.composition.validators.chapterBytes = ByteLimit(8192)
  result.completion.composition.validators.projection.rows = ElementLimit(18)
  result.completion.composition.authorization.inputHashes = ElementLimit(240)
  result.completion.composition.authorization.inputBytes = ByteLimit(7680)
  result.completion.composition.authorization.outputHashes = ElementLimit(24)
  result.completion.composition.authorization.outputBytes = ByteLimit(771)

proc populationOriginal*(base: OwnedReport): BlockSnapshot =
  ## Author all profile-dependent chapters before any tested child; the prior fixture source remains untouched.
  let prior = epoch.original(base)
  let limits = populationLimits()
  let policy = limits.reporting.safrole.state
  var records = newSeq[StateValidator](9)
  for index in 0..<9:
    var seed = default(array[32, byte])
    seed[0] = byte(index+11)
    let ed = importSeed(seed).value
    records[index].ed25519 = StateEdKey(array[32, byte](publicKey(ed).value))
    records[index].bandersnatch = StateBsKey(array[32, byte](publicKey(epoch.key(index+1)).value))
    var bls = default(array[144, byte])
    var metadata = default(array[128, byte])
    for at in 0..<144: bls[at] = byte(index+1)
    for at in 0..<128: metadata[at] = byte(20+index)
    records[index].bls = StateBlsKey(bls)
    records[index].metadata = StateValidatorMetadata(metadata)
  var active, staging, pending, previous: seq[StateValidator] = @[]
  for index in 0..<6:
    active.add(records[index])
    staging.add(records[5-index])
  for index in 0..<9:
    pending.add(records[(index+1) mod 9])
    previous.add(records[(index+2) mod 9])
  let setup = newSetup(9).value
  let root = StateRingRoot(array[144, byte](commitRing(setup, epoch.members(pending)).value))
  close(setup)
  var schedule = newSeq[StateBsKey](12)
  for index in 0..<12: schedule[index] = active[index mod 6].bandersnatch
  var entries = @[safroleStateEntry(SafroleState(pending: pending, root: root,
      schedule: keySchedule(schedule), accumulator: @[]), policy).value]
  entries.add(validatorEntry(ValidatorChapter.Active, active, policy.validators).value)
  entries.add(validatorEntry(ValidatorChapter.Previous, previous, policy.validators).value)
  entries.add(validatorEntry(ValidatorChapter.Staging, staging, policy.validators).value)
  let authorization = limits.completion.execution.initial.guests.contexts.queues
  entries.add(authorizationEntry(AuthorizationKind.Pools, @[newSeq[AuthorizerHash](1),
      newSeq[AuthorizerHash](1), newSeq[AuthorizerHash](1)], authorization).value)
  entries.add(authorizationEntry(AuthorizationKind.Queues, @[newSeq[AuthorizerHash](80),
      newSeq[AuthorizerHash](80), newSeq[AuthorizerHash](80)], authorization).value)
  entries.add(availabilityStateEntry(newSeq[AvailabilityAssignment](3),
      limits.reporting.disputes.availability).value)
  entries.add(privilegeStateEntry(PrivilegeState(assigners: newSeq[ServiceIndex](3)),
      limits.round.privileges).value)
  var activity = ActivityState(cores: newSeq[CoreActivity](3))
  activity.validators[StatisticsEpoch.Current] = newSeq[ValidatorActivity](6)
  activity.validators[StatisticsEpoch.Previous] = newSeq[ValidatorActivity](9)
  for period in low(StatisticsEpoch)..high(StatisticsEpoch):
    for index in 0..<activity.validators[period].len:
      for measure in low(ValidatorMeasure)..high(ValidatorMeasure):
        activity.validators[period][index][measure] = ValidatorCounter(uint32(1000*ord(
            period)+100*index+10+ord(measure)))
  entries.add(activityStateEntry(activity, ActivityConfig(cores: CoreCount(3),
      current: ValidatorCount(6), previous: ValidatorCount(9), maxServices: ElementLimit(0),
          maxBytes: ByteLimit(4096))).value)
  var judgments = DisputeState()
  judgments.reports[JudgmentSet.Bad] = @[default(DisputeHash)]
  entries.add(disputeStateEntry(judgments, limits.reporting.disputes.state).value)
  var state = forkStateStore(prior.stateSnapshot).value
  var writes: seq[StateWrite] = @[]
  for entry in entries: writes.add(StateWrite(key: entry.key, kind: StateWriteKind.Put,
      value: entry.value))
  assert state.apply(writes).error == StateStoreError.None
  captureBlockSnapshot(currentChainBytes(prior.header), state.snapshot.value, populationParameters()).value
