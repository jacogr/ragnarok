# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded source-free CE137 plans preserve canonical descriptors, original assurer coordinates and actual current/prior-epoch guarantor identities without allocating the Cartesian request product.

import ./[assurance_duty, availability_proof]
import ../chain/genesis
import ../codec/[bounded, assurances, guarantees, report_owned]
import ../codec/work/report
import ../codec/state/[safrole, availability]
import ../state/availability/specifier
import ../state/erasure/words

type
  AssuranceFetchLimits* = object ## Canonical input reads and conservative owned-output storage are independently explicit.
    duty*: AssuranceDutyLimits
    plannedBytes*: ByteLimit
  AssuranceFetchInfo* = object ## Copied source/identity counts grant neither shard possession nor a private signing capability.
    duty*: AssuranceDutyInfo
    plannedBytes*: uint64
    targets*: int
  AssuranceFetchCore* = object ## One exact pending core retains its six-field descriptor and number of actual credential targets.
    core*: CoreIndex
    specifier*: AvailabilitySpecifier
    targets*: int
  AssuranceFetchTarget* = object ## Original guarantor ordinal and copied public validator routing data never carry canonical map ownership.
    validatorIndex*: GuarantorIndex
    validator*: StateValidator
  AssuranceFetchRequest* = object ## Original local index and exact canonical request stay distinct from compressed plan-row ordinals.
    core*: CoreIndex
    localOrdinal*: int
    validator*: ValidatorIndex
    request*: AvailabilityRequest
  CorePlan = object ## Bounded fixed values include no report, state snapshot or private-key aliases.
    info: AssuranceFetchCore
    offset: uint16
    targets: array[3, AssuranceFetchTarget]
  FetchData = ref object ## Immutable source-free ownership contains per-core rows and original local indices separately.
    info: AssuranceFetchInfo
    cores: seq[CorePlan]
    locals: seq[ValidatorIndex]
  AssuranceFetchPlan* = object ## Only complete canonical qualification constructs a non-default plan.
    data: nil FetchData
  AssuranceFetchError* {.pure.} = enum ## Failure/default carries no accepted source, request prefix or partial target list.
    Uninitialized, None, InvalidPolicy, LimitExceeded, InvalidIndex, InvalidState, DutyFailure, TargetFailure
  AssuranceFetchResult*[T] = object ## Each real selected canonical/target lookup refusal retains its guarded child alone.
    case status: AssuranceFetchError
    of None: completed: T
    of DutyFailure: dutyReason: AssuranceDutyResult[AssuranceDuty]
    of TargetFailure: targetReason: AssuranceDutyResult[StateValidator]
    else: discard # Simple/default refusals cannot leak partially allocated plan storage.

func error*[T](outcome: AssuranceFetchResult[T]): AssuranceFetchError =
  ## Inspect the private status before extracting complete data or the actual child failure.
  outcome.status

func value*[T](outcome: AssuranceFetchResult[T]): T {.requires: outcome.status ==
    AssuranceFetchError.None.} =
  ## Only complete source qualification exposes a plan or fixed copied metadata.
  outcome.completed

func dutyError*[T](outcome: AssuranceFetchResult[T]): AssuranceDutyResult[
    AssuranceDuty] {.requires: outcome.status == AssuranceFetchError.DutyFailure.} =
  ## Preserve actual source, whole-chapter, identity and geometry refusals.
  outcome.dutyReason

func targetError*[T](outcome: AssuranceFetchResult[T]): AssuranceDutyResult[
    StateValidator] {.requires: outcome.status == AssuranceFetchError.TargetFailure.} =
  ## Unavailable historical epochs and invalid actual credential positions cannot manufacture a target.
  outcome.targetReason

func refused[T](reason: AssuranceFetchError): AssuranceFetchResult[T] {.requires: reason notin {
    AssuranceFetchError.None, AssuranceFetchError.DutyFailure,
    AssuranceFetchError.TargetFailure}.} =
  ## No simple refusal owns a successful child or partially accepted output.
  AssuranceFetchResult[T](status: reason)

func valid*(limits: AssuranceFetchLimits): bool =
  ## Default policy cannot guess source or output budgets; the maximum comfortably covers every fixed GP core row.
  uint64(limits.plannedBytes) > 0 and uint64(limits.plannedBytes) <= 4'u64*1024*1024 and
    uint64(limits.duty.chapterBytes) > 0 and uint64(limits.duty.readBytes) > 0 and
    uint64(limits.duty.reports) > 0 and uint64(limits.duty.requests) > 0

func valid*(plan: AssuranceFetchPlan): bool =
  ## A default cannot authorize a request or expose even empty successful metadata.
  plan.data != nil

proc fetchInfo*(plan: AssuranceFetchPlan): AssuranceFetchResult[AssuranceFetchInfo] =
  ## Read fixed copied source facts without borrowing any private sequences.
  let data = plan.data
  if data == nil: return refused[AssuranceFetchInfo](AssuranceFetchError.Uninitialized)
  AssuranceFetchResult[AssuranceFetchInfo](status: AssuranceFetchError.None, completed: data.info)

proc matches*(plan: AssuranceFetchPlan, source: BlockSnapshotResult): bool =
  ## An identical sealed header with a different complete map still revokes this request plan.
  let data = plan.data
  if data == nil or source.error != GenesisError.None: return false
  array[32, byte](data.info.duty.anchor) == array[32, byte](source.value.blockHash) and
    array[32, byte](data.info.duty.root) == array[32, byte](source.value.stateRoot)

proc coreAt*(plan: AssuranceFetchPlan, ordinal: int): AssuranceFetchResult[AssuranceFetchCore] =
  ## Return a fixed original core/descriptor copy, never a mutable row or compressed core coordinate.
  let data = plan.data
  if data == nil: return refused[AssuranceFetchCore](AssuranceFetchError.Uninitialized)
  if ordinal < 0 or ordinal >= data.cores.len: return refused[AssuranceFetchCore](
      AssuranceFetchError.InvalidIndex)
  AssuranceFetchResult[AssuranceFetchCore](status: AssuranceFetchError.None, completed: data.cores[ordinal].info)

proc targetAt*(plan: AssuranceFetchPlan, coreOrdinal, ordinal: int): AssuranceFetchResult[
    AssuranceFetchTarget] =
  ## Original credential positions remain attached to independently copied routing records, including repeated keys with different metadata.
  let data = plan.data
  if data == nil: return refused[AssuranceFetchTarget](AssuranceFetchError.Uninitialized)
  if coreOrdinal < 0 or coreOrdinal >= data.cores.len: return refused[AssuranceFetchTarget](
      AssuranceFetchError.InvalidIndex)
  if ordinal < 0 or ordinal >= data.cores[coreOrdinal].info.targets: return refused[
      AssuranceFetchTarget](AssuranceFetchError.InvalidIndex)
  AssuranceFetchResult[AssuranceFetchTarget](status: AssuranceFetchError.None,
      completed: data.cores[coreOrdinal].targets[ordinal])

proc requestAt*(plan: AssuranceFetchPlan, coreOrdinal, localOrdinal: int): AssuranceFetchResult[
    AssuranceFetchRequest] =
  ## Derive one O(1) original-index coordinate on demand; no request-product graph or mutable expected descriptor escapes.
  let data = plan.data
  if data == nil: return refused[AssuranceFetchRequest](AssuranceFetchError.Uninitialized)
  if coreOrdinal < 0 or coreOrdinal >= data.cores.len or localOrdinal < 0 or localOrdinal >=
      data.locals.len:
    return refused[AssuranceFetchRequest](AssuranceFetchError.InvalidIndex)
  let row = data.cores[coreOrdinal]
  let local = data.locals[localOrdinal]
  let shard = (uint64(row.offset)+uint64(uint16(local))) mod uint64(data.info.duty.validators)
  AssuranceFetchResult[AssuranceFetchRequest](status: AssuranceFetchError.None,
    completed: AssuranceFetchRequest(core: row.info.core, localOrdinal: localOrdinal,
      validator: local,
      request: AvailabilityRequest(kind: AvailabilityTransferKind.Distribution,
        root: row.info.specifier.erasureRoot, shard: ErasureShardIndex(shard))))

proc captureAssuranceFetch*(source: BlockSnapshotResult, local: StateEdKey,
    limits: AssuranceFetchLimits): AssuranceFetchResult[AssuranceFetchPlan] =
  ## Complete canonical input qualification and whole owned-output admission precede plan allocation; no successful prefix survives a later target refusal.
  if not limits.valid: return refused[AssuranceFetchPlan](AssuranceFetchError.InvalidPolicy)
  let captured = captureAssuranceDuty(source, local, limits.duty)
  if captured.error != AssuranceDutyError.None:
    return AssuranceFetchResult[AssuranceFetchPlan](status: AssuranceFetchError.DutyFailure,
        dutyReason: captured)
  let duty = captured.value
  let facts = duty.dutyInfo.value
  if facts.assignments < 0 or facts.assignments > 341 or facts.localIndices < 1 or
      facts.localIndices > 1023 or sizeof(CorePlan) > 4096:
    return refused[AssuranceFetchPlan](AssuranceFetchError.InvalidState)
  let required = 4096'u64+uint64(facts.assignments)*(uint64(sizeof(CorePlan))+64)+uint64(
      facts.localIndices)*16
  if required > uint64(limits.plannedBytes): return refused[AssuranceFetchPlan](
      AssuranceFetchError.LimitExceeded)
  var locals = newSeq[ValidatorIndex](facts.localIndices)
  for ordinal in 0..<locals.len:
    # Preserve every repeated local key's actual original index without compressing null predecessors.
    locals[ordinal] = duty.localIndex(ordinal).value
  var cores = newSeq[CorePlan](facts.assignments)
  var used = 0
  var targets = 0
  for core in 0..<int(uint64(facts.cores)):
    # Only actual pending original cores create rows; their order is stable and independent of peer traffic.
    let assignment = duty.assignment(CoreIndex(core)).value
    if not assignment.present: continue
    let header = assignment.guarantee.report.ownedReportInfo.value.header
    let specifier = AvailabilitySpecifier(packageHash: header.packageHash,
      bundleLength: header.bundleLength,
      erasureRoot: header.erasureRoot, erasureShards: header.erasureShards,
      segmentRoot: header.segmentRoot, segmentCount: header.segmentCount)
    let first = duty.shardRequest(CoreIndex(core), 0).value
    let population = uint64(facts.validators)
    let offset = (uint64(first.shard)+population-uint64(uint16(locals[0]))) mod population
    var row = CorePlan(info: AssuranceFetchCore(core: CoreIndex(core), specifier: specifier),
        offset: uint16(offset))
    if assignment.guarantee.credentialCount < 2 or assignment.guarantee.credentialCount > 3:
      return refused[AssuranceFetchPlan](AssuranceFetchError.InvalidState)
    for ordinal in 0..<assignment.guarantee.credentialCount:
      # Credential lookup uses its evaluation epoch and exact original C8/C9 position; null targets never become dial identities.
      let selected = duty.guarantorAt(CoreIndex(core), ordinal)
      if selected.error != AssuranceDutyError.None:
        return AssuranceFetchResult[AssuranceFetchPlan](status: AssuranceFetchError.TargetFailure,
            targetReason: selected)
      let key = array[32, byte](selected.value.ed25519)
      if key == default(array[32, byte]) or key == array[32, byte](nullValidator().ed25519): continue
      if row.info.targets >= row.targets.len: return refused[AssuranceFetchPlan](
          AssuranceFetchError.InvalidState)
      row.targets[row.info.targets] = AssuranceFetchTarget(
          validatorIndex: assignment.guarantee.credentials[ordinal].validator,
        validator: selected.value)
      inc row.info.targets
      inc targets
    if used >= cores.len: return refused[AssuranceFetchPlan](AssuranceFetchError.InvalidState)
    cores[used] = row
    inc used
  if used != cores.len: return refused[AssuranceFetchPlan](AssuranceFetchError.InvalidState)
  AssuranceFetchResult[AssuranceFetchPlan](status: AssuranceFetchError.None,
    completed: AssuranceFetchPlan(data: FetchData(info: AssuranceFetchInfo(duty: facts,
      plannedBytes: required, targets: targets), cores: move(cores), locals: move(locals))))
