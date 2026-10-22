# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Derive current/prior guarantor tables only from authenticated posterior computed-report context.

import ../chain/parameters
import ../codec/[bounded, assurances, header, guarantees, state_safrole, state_layout,
    state_disputes, work_report]
import ./[computed_roster, computed_transition, computed_profile, computed_lookup, computed_recent,
  computed_state, computed_links, computed_guarantee, computed_report, block_transition,
  block_admission, guarantors, store]

type
  ComputedGuarantorError* {.pure.} = enum ## Refusals expose no partial tables or usable query payload.
    Uninitialized, None, InvalidSource, InvalidConfig, MissingState, InvalidState, LimitExceeded,
    BackendFailure, InvalidSlot, InvalidIndex, WrongAssignment, IneligibleValidator
  ComputedGuarantorLimits* = object ## Local bounded decoding policies cannot replace original chain parameters or posterior data.
    roster*: ComputedRosterLimits
    judgments*: DisputeStateConfig
    offenders*: ElementLimit
  ComputedGuarantorData = ref object ## Immutable acyclic ownership binds exact computed provenance, core and posterior tables.
    source: RosterEligibleComputedReport
    plan: GuarantorPlan
    core: CoreIndex
  ComputedGuarantors* = object ## Assignment context grants no credential verification or signing authority.
    data: nil ComputedGuarantorData
  ComputedGuarantorResult*[T] = object ## Only private completed success contains application data.
    case status: ComputedGuarantorError
    of None:
      completed: T
    else:
      discard                          # Defaults and refusals contain reasons alone.

func error*[T](outcome: ComputedGuarantorResult[T]): ComputedGuarantorError =
  ## Inspect the reason without writable successful selection.
  outcome.status
func value*[T](outcome: ComputedGuarantorResult[T]): T
    {.requires: outcome.status == ComputedGuarantorError.None.} =
  ## Preserve extraction contracts under optimized compilation.
  outcome.completed
proc computedGuarantorSource*(context: ComputedGuarantors): ComputedGuarantorResult[
    RosterEligibleComputedReport] =
  ## Retain exact original computed and authenticated population eligibility provenance.
  let data = context.data
  if data == nil: return ComputedGuarantorResult[RosterEligibleComputedReport](
      status: ComputedGuarantorError.Uninitialized)
  ComputedGuarantorResult[RosterEligibleComputedReport](status: ComputedGuarantorError.None,
      completed: data.source)
proc computedGuarantorAt*(context: ComputedGuarantors, slot: GuaranteeSlot,
    index: GuarantorIndex): ComputedGuarantorResult[GuarantorAssignment] =
  ## Check evaluation-slot freshness, selected roster position, computed core and non-null identity without new hashes.
  template fail(reason: ComputedGuarantorError) =
    return ComputedGuarantorResult[GuarantorAssignment](status: reason)
  let data = context.data
  if data == nil: fail(ComputedGuarantorError.Uninitialized)
  let selected = data.plan.guarantorAt(slot, index)
  if selected.error == GuarantorError.InvalidSlot: fail(ComputedGuarantorError.InvalidSlot)
  if selected.error == GuarantorError.InvalidIndex: fail(ComputedGuarantorError.InvalidIndex)
  if selected.error != GuarantorError.None: fail(ComputedGuarantorError.InvalidState)
  if uint64(selected.value.core) != uint64(data.core): fail(ComputedGuarantorError.WrongAssignment)
  if array[32, byte](selected.value.validator.ed25519) == array[32, byte](nullValidator().ed25519):
    fail(ComputedGuarantorError.IneligibleValidator) # Phi-null or originally null identities cannot supply an eligible key.
  ComputedGuarantorResult[GuarantorAssignment](status: ComputedGuarantorError.None,
      completed: selected.value)
proc prepareComputedGuarantors*(source: RosterEligibleComputedReport,
    limits: ComputedGuarantorLimits): ComputedGuarantorResult[ComputedGuarantors] =
  ## Preflight all original profile/decoder budgets and retain only the complete real posterior assignment plan.
  template fail(reason: ComputedGuarantorError) =
    return ComputedGuarantorResult[ComputedGuarantors](status: reason)
  if source.computedRosterSource.error != ComputedRosterError.None: fail(
      ComputedGuarantorError.InvalidSource)
  let transition = source.computedRosterSource.value
  let configured = transition.computedTransitionSource.value
  let parameters = configured.computedProfileContext.value.parameters
  let epoch = parameters.get(epochPeriod)
  let rotation = parameters.get(rotationPeriod)
  if epoch == 0 or rotation == 0 or rotation > epoch: fail(ComputedGuarantorError.InvalidConfig)
  if epoch mod rotation != 0: fail(ComputedGuarantorError.InvalidConfig) # Prove nonzero divisor before modulo or planning.
  let cores = parameters.get(coreCount) # Successful source proves 2<=cores<=341 before structural multiplication.
  let roster = ValidatorStateConfig(cores: CoreCount(cores),
    validators: ElementLimit(min(uint64(limits.roster.validators), 3*cores)),
        maxBytes: limits.roster.bytes)
  let active = source.computedRosterActive.value
  let activeSize = stateValidatorSize(ValidatorCount(validatorCount(active).value), roster)
  if activeSize.error == StateComponentError.LimitExceeded: fail(
      ComputedGuarantorError.LimitExceeded)
  if activeSize.error != StateComponentError.None: fail(ComputedGuarantorError.InvalidState)
  let staged = transition.computedTransitionStage.value.value
  var raw = default(array[3, seq[byte]])
  # Preflight every complete posterior chapter before copying any variable bytes.
  for i, chapter in [9'u8, 6, 5]:
    let read = staged.snapshot.lookup(chapterKey(StateChapter(chapter)))
    if read.error != StateStoreError.None: fail(ComputedGuarantorError.MissingState)
    let ceiling = if i == 0: limits.roster.bytes elif i == 1: ByteLimit(
        128) else: limits.judgments.maxBytes
    if uint64(read.value.byteLength) > uint64(ceiling): fail(ComputedGuarantorError.LimitExceeded)
  for i, chapter in [9'u8, 6, 5]:
    raw[i] = staged.snapshot.lookup(chapterKey(StateChapter(
        chapter))).value.bytes # Same immutable map makes the preflight stable.
  let previous = decodeStateValidators(raw[0], roster)
  let entropy = decodeStateEntropy(raw[1])
  let judgments = decodeDisputeState(raw[2], limits.judgments)
  if previous.error == StateComponentError.LimitExceeded or judgments.error ==
      DisputeStateError.LimitExceeded:
    fail(ComputedGuarantorError.LimitExceeded)
  if previous.error != StateComponentError.None or entropy.error != StateComponentError.None or
      judgments.error != DisputeStateError.None: fail(ComputedGuarantorError.InvalidState)
  let exact = previous.value.consumed == raw[0].len and entropy.value.consumed == raw[1].len
  if not exact or judgments.value.consumed != raw[2].len: fail(ComputedGuarantorError.InvalidState)
  let count = disputeStateInfo(judgments.value.snapshot).value.offenders
  if uint64(count) > uint64(limits.offenders): fail(ComputedGuarantorError.LimitExceeded)
  if count > high(int) div sizeof(OffenderKey): fail(ComputedGuarantorError.LimitExceeded)
  var offenders = newSeq[OffenderKey](count)
  for i in 0..<count:
    offenders[i] = stateOffenderAt(judgments.value.snapshot, DisputeStateIndex(
        i)).value # Canonical complete cumulative set, including earlier blocks.
  let slot = StateTime(uint32(headerInfo(staged.admitted.admittedHeader).value.unsigned.slot))
  let planned = planGuarantors(active, previous.value.value, entropy.value.value, slot, offenders,
    GuarantorConfig(roster: roster, epochSlots: EpochSlots(epoch),
      rotationSlots: GuarantorRotationSlots(rotation), offenders: limits.offenders))
  if planned.error == GuarantorError.BackendFailure: fail(ComputedGuarantorError.BackendFailure)
  if planned.error == GuarantorError.LimitExceeded: fail(ComputedGuarantorError.LimitExceeded)
  if planned.error == GuarantorError.InvalidConfig: fail(ComputedGuarantorError.InvalidConfig)
  if planned.error != GuarantorError.None: fail(ComputedGuarantorError.InvalidState)
  let state = configured.computedProfileSource.value.computedLookupSource.value.computedRecentSource.value
  let core = state.computedStateSource.value.computedLinkSource.value.computedGuaranteeReport.value.computedReportInfo.value.core
  ComputedGuarantorResult[ComputedGuarantors](status: ComputedGuarantorError.None,
    completed: ComputedGuarantors(data: ComputedGuarantorData(source: source, plan: planned.value, core: core)))
