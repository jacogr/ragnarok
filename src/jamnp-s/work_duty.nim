# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Derive current-source guarantor eligibility from actual GP rosters, entropy, offenders and local observed time.
## Detached success records assignment facts only; callers supply a complete canonical source, never a partial light map.
import ../codec/[bounded, assurances, guarantees]
import ../codec/state/[safrole, disputes as state_disputes, layout as state_layout,
    trie as state_trie]
from ../codec/work/report import CoreIndex, ErasureShards
from ../codec/header import EpochSlots
import ../chain/parameters
import ../state/[store, guarantors]

type
  WorkDutyError* {.pure.} = enum ## Refusals contain no source, assignment prefix or fabricated credential authority.
    Uninitialized, None, InvalidPolicy, InvalidIdentity, InvalidCore, InvalidTime,
    UncertainEpoch, NotAssigned, LimitExceeded, InvalidState, StateFailure,
    ComponentFailure, DisputeFailure, AssignmentFailure
  WorkDutyLimits* = object ## Canonical state chapters and cumulative dispute sets have explicit independent local ceilings.
    chapterBytes*: ByteLimit
    disputeItems*: ElementLimit
  WorkRecipient* = object ## A host-observed local identity/time is immutable input, never derived from the builder's wire.
    ready: bool
    local: StateEdKey
    now: StateTime
  WorkDuty* = object ## Fixed copied success contains no canonical ARC alias, signer, signature or inclusion certificate.
    ready: bool
    local: StateEdKey
    core: CoreIndex
    sourceTime, observed: StateTime
    sourceRoot: StateRoot
    epoch, rotation: uint64
    shards: ErasureShards
  WorkDutyResult*[T] = object ## Private selected children preserve exact genuine causes without exposing accepted prefixes.
    case status: WorkDutyError
    of None: completed: T
    of InvalidState: invalidChapter: StateChapter
    of StateFailure:
      stateChapter: StateChapter
      stateReason: StateStoreError
    of ComponentFailure:
      componentChapter: StateChapter
      componentReason: StateComponentError
    of DisputeFailure: disputeReason: DisputeStateError
    of AssignmentFailure: assignmentReason: GuarantorError
    else: discard # Simple default/local refusals carry only their reason.
func error*[T](outcome: WorkDutyResult[T]): WorkDutyError =
  ## Inspect a reason without writable result alternatives.
  outcome.status
func value*[T](outcome: WorkDutyResult[T]): T {.requires: outcome.status == WorkDutyError.None.} =
  ## Extract only genuine complete eligibility facts.
  outcome.completed
func stateError*[T](outcome: WorkDutyResult[T]): StateStoreError {.requires: outcome.status ==
    WorkDutyError.StateFailure.} =
  ## Only an actual failed original-state lookup exposes a store cause.
  outcome.stateReason
func componentError*[T](outcome: WorkDutyResult[T]): StateComponentError {.requires: outcome.status ==
    WorkDutyError.ComponentFailure.} =
  ## Preserve the actual time/entropy/roster decoder's refusal.
  outcome.componentReason
func disputeError*[T](outcome: WorkDutyResult[T]): DisputeStateError {.requires: outcome.status ==
    WorkDutyError.DisputeFailure.} =
  ## C(5) decoding has its own genuine failure domain.
  outcome.disputeReason
func assignmentError*[T](outcome: WorkDutyResult[T]): GuarantorError {.requires: outcome.status ==
    WorkDutyError.AssignmentFailure.} =
  ## Preserve a failed GP assignment planner without inventing an eligible validator.
  outcome.assignmentReason
func chapter*[T](outcome: WorkDutyResult[T]): StateChapter {.requires: outcome.status in {
    WorkDutyError.InvalidState, WorkDutyError.StateFailure, WorkDutyError.ComponentFailure}.} =
  ## A real selected chapter failure is distinct from any service or validator ordinal.
  case outcome.status
  of WorkDutyError.InvalidState: outcome.invalidChapter
  of WorkDutyError.StateFailure: outcome.stateChapter
  else: outcome.componentChapter
func valid*(recipient: WorkRecipient): bool =
  ## Defaults and vacant identities never request network guarantor authority.
  recipient.ready
func workRecipient*(local: StateEdKey, now: StateTime): WorkRecipient =
  ## Copy the authenticated local identity and host's clock observation; never accept a zero key or the GP null-validator sentinel.
  let bytes = array[32, byte](local)
  if bytes == default(array[32, byte]): return default(WorkRecipient)
  let vacant = nullValidator().ed25519
  if bytes == array[32, byte](vacant): return default(WorkRecipient)
  WorkRecipient(ready: true, local: local, now: now)
func valid*(duty: WorkDuty): bool =
  ## A default record cannot certify assignment, including core zero.
  duty.ready
func localIdentity*(duty: WorkDuty): StateEdKey {.requires: duty.ready.} =
  ## This exact copied identity occupied the requested core in the original source's actual assignment.
  duty.local
func core*(duty: WorkDuty): CoreIndex {.requires: duty.ready.} =
  ## The nominal core remains inseparable from source/time and identity.
  duty.core
func observedTime*(duty: WorkDuty): StateTime {.requires: duty.ready.} =
  ## Assignment was checked at this host observation, not at a builder-provided timestamp.
  duty.observed
func sourceTime*(duty: WorkDuty): StateTime {.requires: duty.ready.} =
  ## Original C(11) time explains refused unknown-epoch observations.
  duty.sourceTime
func sourceRoot*(duty: WorkDuty): StateRoot {.requires: duty.ready.} =
  ## The copied commitment identifies the supplied complete source; no partial-light conversion occurs here.
  duty.sourceRoot
func epochDuration*(duty: WorkDuty): uint64 {.requires: duty.ready.} =
  ## Runtime expiry can inspect fixed geometry without touching the selected-state graph.
  duty.epoch
func rotationDuration*(duty: WorkDuty): uint64 {.requires: duty.ready.} =
  ## A current-source duty record has explicit positive rotation geometry.
  duty.rotation
func shardCount*(duty: WorkDuty): ErasureShards {.requires: duty.ready.} =
  ## Actual current source roster population differs from configured core capacity; inclusion eligibility remains a separate check.
  duty.shards
func activeAt*(duty: WorkDuty, now: StateTime): bool =
  ## Fixed metadata can refuse backwards/changed-rotation observations during any canonical worker lease.
  if not duty.ready: return false
  let observed = uint64(uint32(duty.observed))
  let actual = uint64(uint32(now))
  if actual < observed: return false
  actual div duty.rotation == observed div duty.rotation
proc readChapter(source: StateStoreSnapshot, chapter: StateChapter, limit: ByteLimit,
    bytes: var seq[byte], failure: var WorkDutyResult[WorkDuty]): bool =
  ## Validate the original stored extent before copying, preserving only actual failed store causes.
  let entry = source.lookup(chapterKey(chapter))
  if entry.error != StateStoreError.None:
    failure = WorkDutyResult[WorkDuty](status: WorkDutyError.StateFailure, stateChapter: chapter,
      stateReason: entry.error)
    return false
  if uint64(entry.value.byteLength) > uint64(limit):
    failure = WorkDutyResult[WorkDuty](status: WorkDutyError.LimitExceeded)
    return false
  bytes = entry.value.bytes
  true
proc captureWorkDuty*(source: StateStoreSnapshot, parameters: Parameters,
    recipient: WorkRecipient, core: CoreIndex, limits: WorkDutyLimits): WorkDutyResult[WorkDuty] =
  ## Execute under the managed CPU graph lease; all source/decoder/planner aliases retire before the fixed result escapes.
  template fail(reason: WorkDutyError) =
    return WorkDutyResult[WorkDuty](status: reason)
  result = default(WorkDutyResult[WorkDuty])
  if not recipient.ready: fail(WorkDutyError.InvalidIdentity)
  if not parameters.valid: fail(WorkDutyError.InvalidPolicy)
  let cores = parameters.get(coreCount)
  let epoch = parameters.get(epochPeriod)
  let rotation = parameters.get(rotationPeriod)
  if cores < 2 or cores > 341 or epoch == 0 or rotation == 0 or rotation > epoch:
    fail(WorkDutyError.InvalidPolicy)
  if epoch mod rotation != 0: fail(WorkDutyError.InvalidPolicy)
  if uint64(core) >= cores: fail(WorkDutyError.InvalidCore)
  var timeBytes, entropyBytes, activeBytes, previousBytes, disputeBytes: seq[byte] = @[]
  if not readChapter(source, StateChapter(11), limits.chapterBytes, timeBytes, result): return
  let clock = decodeStateTime(timeBytes)
  if clock.error != StateComponentError.None:
    return WorkDutyResult[WorkDuty](status: WorkDutyError.ComponentFailure,
      componentChapter: StateChapter(11), componentReason: clock.error)
  if clock.value.consumed != timeBytes.len: return WorkDutyResult[WorkDuty](
    status: WorkDutyError.InvalidState, invalidChapter: StateChapter(11))
  let observed = uint64(uint32(recipient.now))
  let actual = uint64(uint32(clock.value.value))
  if observed < actual: fail(WorkDutyError.InvalidTime)
  if observed div epoch != actual div epoch: fail(WorkDutyError.UncertainEpoch)
  if not readChapter(source, StateChapter(6), limits.chapterBytes, entropyBytes, result): return
  let entropy = decodeStateEntropy(entropyBytes)
  if entropy.error != StateComponentError.None:
    return WorkDutyResult[WorkDuty](status: WorkDutyError.ComponentFailure,
      componentChapter: StateChapter(6), componentReason: entropy.error)
  if entropy.value.consumed != entropyBytes.len: return WorkDutyResult[WorkDuty](
    status: WorkDutyError.InvalidState, invalidChapter: StateChapter(6))
  let rosterConfig = ValidatorStateConfig(cores: CoreCount(cores), validators: ElementLimit(1023),
    maxBytes: limits.chapterBytes)
  if not readChapter(source, StateChapter(8), limits.chapterBytes, activeBytes, result): return
  let active = decodeStateValidators(activeBytes, rosterConfig)
  if active.error != StateComponentError.None:
    return WorkDutyResult[WorkDuty](status: WorkDutyError.ComponentFailure,
      componentChapter: StateChapter(8), componentReason: active.error)
  if active.value.consumed != activeBytes.len: return WorkDutyResult[WorkDuty](
    status: WorkDutyError.InvalidState, invalidChapter: StateChapter(8))
  if not readChapter(source, StateChapter(9), limits.chapterBytes, previousBytes, result): return
  let previous = decodeStateValidators(previousBytes, rosterConfig)
  if previous.error != StateComponentError.None:
    return WorkDutyResult[WorkDuty](status: WorkDutyError.ComponentFailure,
      componentChapter: StateChapter(9), componentReason: previous.error)
  if previous.value.consumed != previousBytes.len: return WorkDutyResult[WorkDuty](
    status: WorkDutyError.InvalidState, invalidChapter: StateChapter(9))
  if not readChapter(source, StateChapter(5), limits.chapterBytes, disputeBytes, result): return
  let disputes = decodeDisputeState(disputeBytes, DisputeStateConfig(perSet: limits.disputeItems,
    totalItems: limits.disputeItems, maxBytes: limits.chapterBytes))
  if disputes.error != DisputeStateError.None:
    return WorkDutyResult[WorkDuty](status: WorkDutyError.DisputeFailure,
        disputeReason: disputes.error)
  if disputes.value.consumed != disputeBytes.len: return WorkDutyResult[WorkDuty](
    status: WorkDutyError.InvalidState, invalidChapter: StateChapter(5))
  let count = disputes.value.snapshot.disputeStateInfo.value.offenders
  var offenders = newSeq[OffenderKey](count)
  for index in 0..<count:
    # Canonical C(5) decoding preserves sorted unique identities and proves every extraction ordinal.
    offenders[index] = disputes.value.snapshot.stateOffenderAt(DisputeStateIndex(index)).value
  let planned = planGuarantors(active.value.value, previous.value.value, entropy.value.value,
    recipient.now, offenders, GuarantorConfig(roster: rosterConfig, epochSlots: EpochSlots(epoch),
      rotationSlots: GuarantorRotationSlots(rotation), offenders: limits.disputeItems))
  if planned.error != GuarantorError.None: return WorkDutyResult[WorkDuty](
    status: WorkDutyError.AssignmentFailure, assignmentReason: planned.error)
  let population = active.value.value.validatorCount.value
  if population < 6 or population > 1023:
    return WorkDutyResult[WorkDuty](status: WorkDutyError.InvalidState,
        invalidChapter: StateChapter(8))
  for index in 0..<population:
    # Only the actual posterior assignment may select the local identity; offenders have already become null records.
    let selected = planned.value.guarantorAt(GuaranteeSlot(uint32(recipient.now)), GuarantorIndex(
        uint16(index)))
    if selected.error != GuarantorError.None: return WorkDutyResult[WorkDuty](
      status: WorkDutyError.AssignmentFailure, assignmentReason: selected.error)
    let matches = array[32, byte](selected.value.validator.ed25519) == array[32, byte](
        recipient.local)
    if matches and uint64(selected.value.core) == uint64(core):
      return WorkDutyResult[WorkDuty](status: WorkDutyError.None,
        completed: WorkDuty(ready: true, local: recipient.local, core: core,
          sourceTime: clock.value.value, observed: recipient.now,
          sourceRoot: source.commitment.root,
          epoch: epoch, rotation: rotation, shards: ErasureShards(uint16(population))))
  fail(WorkDutyError.NotAssigned)
