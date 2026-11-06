# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Source-free CE141 timing and author plans retain exact complete-parent identity, original C8 assurer duties and current/pending-C4 author routing without signing or possession authority.
import ./[assurance_duty, assurance_record, topology]
import ../chain/[genesis, parameters]
import ../codec/[assurances, bounded]
import ../codec/state/[safrole, consensus]
import ../codec/work/report

type
  AssuranceWindow* = object ## Detached timing is a host observation, revalidated against source parameters before author planning.
    targetSlot*: StateTime
    prepareAt*, sendAt*, closeAt*: AssuranceTime
    slotSeconds*: uint64
  AssuranceScheduleLimits* = object ## Canonical duty and C4/C8/C9 decoding have independent bounds; planned output covers all three source-free roster vectors.
    duty*: AssuranceDutyLimits
    topology*: SafroleStateConfig
    plannedBytes*: ByteLimit
  AssuranceScheduleError* {.pure.} = enum ## A failure/default cannot expose a prepared author set or requested assurance selection.
    Uninitialized, None, Unavailable, InvalidPolicy, InvalidSource, InvalidTime, InvalidIndex,
    LimitExceeded, DutyFailure, TopologyFailure
  AssuranceScheduleInfo* = object ## Copied source/role/window facts grant no private key, signature, possession or actual peer membership.
    duty*: AssuranceDutyInfo
    window*: AssuranceWindow
    authorEpoch*: ValidatorEpoch
    authors*: int
  ScheduleData = ref object ## Immutable copied public rosters contain no canonical map, namespace pointer or secret owner.
    info: AssuranceScheduleInfo
    authors: ValidatorTopology
    selection: AssuranceBits
  AssuranceSchedule* = object ## Only complete parent and temporal-role qualification creates a plan.
    data: nil ScheduleData
  AssuranceScheduleResult*[T] = object ## Actual failed canonical or topology children remain selected without a successful prefix.
    case status: AssuranceScheduleError
    of None: completed: T
    of DutyFailure: dutyReason: AssuranceDutyResult[AssuranceDuty]
    of TopologyFailure: topologyReason: TopologyError
    else: discard # Simple refusal contains no source, signature or unrelated child result.
func error*[T](outcome: AssuranceScheduleResult[T]): AssuranceScheduleError =
  ## Inspect the selected branch before any guarded payload or child access.
  outcome.status
func value*[T](outcome: AssuranceScheduleResult[T]): T {.requires: outcome.status ==
    AssuranceScheduleError.None.} =
  ## Only whole success grants detached timing, public routing or selection observations.
  outcome.completed
func dutyError*[T](outcome: AssuranceScheduleResult[T]): AssuranceDutyResult[
    AssuranceDuty] {.requires: outcome.status == AssuranceScheduleError.DutyFailure.} =
  ## Preserve the actual original-parent duty refusal.
  outcome.dutyReason
func topologyError*[T](outcome: AssuranceScheduleResult[
    T]): TopologyError {.requires: outcome.status == AssuranceScheduleError.TopologyFailure.} =
  ## Preserve the exact bounded public-roster decoder refusal.
  outcome.topologyReason
func refused[T](reason: AssuranceScheduleError): AssuranceScheduleResult[T] {.requires: reason notin
    [AssuranceScheduleError.None, AssuranceScheduleError.DutyFailure,
    AssuranceScheduleError.TopologyFailure].} =
  ## Failed/simple constructors cannot manufacture accepted plan storage or a missing typed child.
  AssuranceScheduleResult[T](status: reason)
func valid*(plan: AssuranceSchedule): bool =
  ## Defaults contain no temporal or source authority.
  plan.data != nil
func valid*(limits: AssuranceScheduleLimits): bool =
  ## Finite independent defaults never activate public roster copying or infer a chain profile.
  uint64(limits.plannedBytes) >= 4096 and uint64(limits.plannedBytes) <= 4'u64*1024*1024 and
    uint64(limits.topology.validators.validators) > 0 and uint64(
        limits.topology.validators.validators) <= 1023 and
    uint64(limits.topology.maxBytes) > 0 and uint64(limits.topology.maxBytes) <= 4'u64*1024*1024 and
    uint64(limits.topology.validators.maxBytes) > 0 and uint64(
        limits.topology.validators.maxBytes) <= 4'u64*1024*1024 and
    uint64(limits.duty.chapterBytes) > 0 and uint64(limits.duty.readBytes) > 0 and
    uint64(limits.duty.reports) > 0 and uint64(limits.duty.requests) > 0
func assuranceWindow*(now: AssuranceTime, slotSeconds: uint64): AssuranceScheduleResult[
    AssuranceWindow] =
  ## The upcoming slot has a finite preparation interval; uint32 slot and multiplication bounds precede all time arithmetic.
  if slotSeconds < 3: return refused[AssuranceWindow](AssuranceScheduleError.InvalidPolicy)
  let clock = uint64(now)
  let target = clock div slotSeconds+1
  if target > uint64(high(uint32)) or target > high(uint64) div slotSeconds:
    return refused[AssuranceWindow](AssuranceScheduleError.InvalidTime)
  let close = target*slotSeconds
  let prepare = if close > 4: close-4 else: 0'u64
  if clock < prepare: return refused[AssuranceWindow](AssuranceScheduleError.Unavailable)
  AssuranceScheduleResult[AssuranceWindow](status: AssuranceScheduleError.None,
    completed: AssuranceWindow(targetSlot: StateTime(uint32(target)), prepareAt: AssuranceTime(
        prepare),
      sendAt: AssuranceTime(close-2), closeAt: AssuranceTime(close), slotSeconds: slotSeconds))
proc scheduleInfo*(plan: AssuranceSchedule): AssuranceScheduleResult[AssuranceScheduleInfo] =
  ## Return only fixed copied facts; no mutable roster or canonical source escapes.
  let data = plan.data
  if data == nil: return refused[AssuranceScheduleInfo](AssuranceScheduleError.Uninitialized)
  AssuranceScheduleResult[AssuranceScheduleInfo](status: AssuranceScheduleError.None,
      completed: data.info)
proc scheduleSelection*(plan: AssuranceSchedule): AssuranceScheduleResult[AssuranceBits] =
  ## Requested pending-core bits are hints only; the private signer must independently restore every selected original local coordinate.
  let data = plan.data
  if data == nil: return refused[AssuranceBits](AssuranceScheduleError.Uninitialized)
  AssuranceScheduleResult[AssuranceBits](status: AssuranceScheduleError.None,
      completed: data.selection)
proc scheduleTarget*(plan: AssuranceSchedule, ordinal: int): AssuranceScheduleResult[Membership] =
  ## Preserve original author ordinals and routing, including null/unreachable positions for bounded host refusal.
  let data = plan.data
  if data == nil: return refused[Membership](AssuranceScheduleError.Uninitialized)
  if ordinal < 0 or ordinal >= data.info.authors: return refused[Membership](
      AssuranceScheduleError.InvalidIndex)
  let found = data.authors.membershipAt(data.info.authorEpoch, StateValidatorIndex(uint64(ordinal)))
  if found.error != TopologyError.None: return refused[Membership](
      AssuranceScheduleError.InvalidIndex)
  AssuranceScheduleResult[Membership](status: AssuranceScheduleError.None, completed: found.value)
proc matches*(plan: AssuranceSchedule, source: BlockSnapshotResult): bool =
  ## Same-header/different-map parents cannot revive an old routing or signing selection.
  let data = plan.data
  if data == nil or source.error != GenesisError.None: return false
  array[32, byte](data.info.duty.anchor) == array[32, byte](source.value.blockHash) and
    array[32, byte](data.info.duty.root) == array[32, byte](source.value.stateRoot)
proc captureAssuranceSchedule*(source: BlockSnapshotResult, local: StateEdKey,
    window: AssuranceWindow, limits: AssuranceScheduleLimits): AssuranceScheduleResult[
        AssuranceSchedule] =
  ## Full duty, exact source timing and known current/pending author keysets precede any accepted public plan; C7 staging never substitutes for next authors.
  if not limits.valid: return refused[AssuranceSchedule](AssuranceScheduleError.InvalidPolicy)
  if source.error != GenesisError.None: return refused[AssuranceSchedule](
      AssuranceScheduleError.InvalidSource)
  let captured = captureAssuranceDuty(source, local, limits.duty)
  if captured.error != AssuranceDutyError.None:
    return AssuranceScheduleResult[AssuranceSchedule](status: AssuranceScheduleError.DutyFailure,
        dutyReason: captured)
  let duty = captured.value
  let info = duty.dutyInfo.value
  let period = info.slotSeconds
  let target = uint64(uint32(window.targetSlot))
  let epoch = source.value.chainParameters.get(epochPeriod)
  if period < 3 or window.slotSeconds != period or target == 0 or target > high(uint64) div period:
    return refused[AssuranceSchedule](AssuranceScheduleError.InvalidTime)
  if epoch == 0 or epoch > uint64(high(uint32)) or epoch > high(uint64) div period:
    return refused[AssuranceSchedule](AssuranceScheduleError.InvalidTime)
  let close = target*period
  let prepare = if close > 4: close-4 else: 0'u64
  if uint64(window.closeAt) != close or uint64(window.sendAt) != close-2 or uint64(
      window.prepareAt) != prepare:
    return refused[AssuranceSchedule](AssuranceScheduleError.InvalidTime)
  let sourceEpoch = uint64(uint32(info.slot)) div epoch
  let due = uint64(window.sendAt)
  let assurerEpoch = if due >= 4: (due-4) div (epoch*period) else: 0'u64
  if uint64(uint32(info.slot)) >= target or sourceEpoch != assurerEpoch:
    return refused[AssuranceSchedule](AssuranceScheduleError.InvalidTime)
  let targetEpoch = target div epoch
  var authors = ValidatorEpoch.Current
  if targetEpoch == sourceEpoch+1: authors = ValidatorEpoch.Next
  elif targetEpoch != sourceEpoch: return refused[AssuranceSchedule](
      AssuranceScheduleError.InvalidTime)
  if sizeof(Membership) > 128: return refused[AssuranceSchedule](
      AssuranceScheduleError.LimitExceeded)
  let required = 4096'u64+uint64(limits.topology.validators.validators)*3*128
  if required > uint64(limits.plannedBytes): return refused[AssuranceSchedule](
      AssuranceScheduleError.LimitExceeded)
  let projected = captureValidatorTopology(source, limits.topology)
  if projected.error != TopologyError.None:
    return AssuranceScheduleResult[AssuranceSchedule](
        status: AssuranceScheduleError.TopologyFailure, topologyReason: projected.error)
  var selection = default(AssuranceBits)
  for core in 0..<int(uint64(info.cores)):
    # Only actual pending original cores are requested; these bits remain no evidence that any file or proof exists.
    if duty.assignment(CoreIndex(core)).value.present:
      selection.bytes[core div 8] = selection.bytes[core div 8] or byte(1 shl (core mod 8))
  AssuranceScheduleResult[AssuranceSchedule](status: AssuranceScheduleError.None,
    completed: AssuranceSchedule(data: ScheduleData(info: AssuranceScheduleInfo(duty: info,
      window: window, authorEpoch: authors, authors: projected.value.population(authors)),
      authors: projected.value, selection: selection)))
