# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete selected-parent assignment plans preserve every actual TLS-key roster position before CE137 acquisition or assurance possession checks.
import ../chain/[genesis, parameters]
import ../codec/[bounded, assurances, guarantees, report_owned, owned]
import ../codec/work/report
import ../codec/state/[availability, safrole, layout, trie]
import ../state/store
import ../state/availability/specifier
import ../state/erasure/[layout as erasure_layout, words]
import ./availability_proof

type
  AssuranceDutyLimits* = object ## Separate complete chapter, aggregate copied input, pending-report and whole-request ceilings are explicit startup policy.
    chapterBytes*, readBytes*: ByteLimit
    reports*, requests*: ElementLimit
  AssuranceDutyError* {.pure.} = enum ## Failure cannot expose an accepted prefix, source plan or possession authority.
    Uninitialized, None, InvalidSource, InvalidPolicy, InvalidIdentity, NotValidator,
    LimitExceeded, InvalidState, InvalidIndex, StateFailure, ComponentFailure,
    AvailabilityFailure, GeometryFailure
  AssuranceDutyInfo* = object ## Copied anchor/root and actual parent geometry grant no signature or durable possession by themselves.
    anchor*: genesis.BlockHash
    root*: trie.StateRoot
    slot*: StateTime
    local*: StateEdKey
    cores*: CoreCount
    validators*: ValidatorCount
    assignments*, localIndices*, requests*: int
    slotSeconds*: uint64
  DutyData = ref object ## Immutable decoded chapters retain neither a mutable ChainView nor a full execution graph.
    info: AssuranceDutyInfo
    assignments: AvailabilitySnapshot
    local: seq[uint16]
    thresholds: array[341, uint64]
  AssuranceDuty* = object ## Only complete canonical chapter capture constructs this bounded acquisition plan.
    data: nil DutyData
  AssuranceDutyResult*[T] = object ## Selected actual child diagnostics preserve failures without publishing any plan prefix.
    case status: AssuranceDutyError
    of None: completed: T
    of StateFailure: stateReason: StateStoreError
    of ComponentFailure: componentReason: StateComponentError
    of AvailabilityFailure: availabilityReason: AvailabilityError
    of GeometryFailure: geometryReason: ErasureLayoutError
    else: discard # Simple/default failures own no successful value or unrelated child reason.
func error*[T](outcome: AssuranceDutyResult[T]): AssuranceDutyError =
  ## Inspect the immutable selected alternative before accessing a plan or child cause.
  outcome.status
func value*[T](outcome: AssuranceDutyResult[T]): T {.requires: outcome.status ==
    AssuranceDutyError.None.} =
  ## Failed/default results expose neither assignment facts nor a fabricated successful request.
  outcome.completed
func stateError*[T](outcome: AssuranceDutyResult[T]): StateStoreError {.requires: outcome.status ==
    AssuranceDutyError.StateFailure.} =
  ## Preserve only the actual failed canonical chapter lookup.
  outcome.stateReason
func componentError*[T](outcome: AssuranceDutyResult[
    T]): StateComponentError {.requires: outcome.status == AssuranceDutyError.ComponentFailure.} =
  ## Preserve only an actual roster/time codec refusal.
  outcome.componentReason
func availabilityError*[T](outcome: AssuranceDutyResult[
    T]): AvailabilityError {.requires: outcome.status == AssuranceDutyError.AvailabilityFailure.} =
  ## Preserve only the actual pending-assignment codec refusal.
  outcome.availabilityReason
func geometryError*[T](outcome: AssuranceDutyResult[
    T]): ErasureLayoutError {.requires: outcome.status == AssuranceDutyError.GeometryFailure.} =
  ## Preserve only the actual source report's failed erasure layout.
  outcome.geometryReason
func refused[T](reason: AssuranceDutyError): AssuranceDutyResult[T] {.requires: reason notin {
    AssuranceDutyError.None, AssuranceDutyError.StateFailure, AssuranceDutyError.ComponentFailure,
    AssuranceDutyError.AvailabilityFailure, AssuranceDutyError.GeometryFailure}.} =
  ## Simple errors carry no accepted prefix or unrelated child diagnostic.
  AssuranceDutyResult[T](status: reason)
func valid*(duty: AssuranceDuty): bool =
  ## A default handle cannot authorize even an empty bitfield plan.
  duty.data != nil
proc dutyInfo*(duty: AssuranceDuty): AssuranceDutyResult[AssuranceDutyInfo] =
  ## Read detached source metadata without exporting decoded chapter storage.
  let data = duty.data
  if data == nil: return refused[AssuranceDutyInfo](AssuranceDutyError.Uninitialized)
  AssuranceDutyResult[AssuranceDutyInfo](status: AssuranceDutyError.None, completed: data.info)
proc matches*(duty: AssuranceDuty, source: BlockSnapshotResult): bool =
  ## A new head or a different complete posterior state revokes the captured plan before signing.
  let data = duty.data
  if data == nil or source.error != GenesisError.None: return false
  let head = source.value
  array[32, byte](data.info.anchor) == array[32, byte](head.blockHash) and array[32, byte](
      data.info.root) == array[32, byte](head.stateRoot)
proc localIndex*(duty: AssuranceDuty, ordinal: int): AssuranceDutyResult[ValidatorIndex] =
  ## Repeated identities retain every original index; no shuffled/compressed ordinal replaces them.
  let data = duty.data
  if data == nil: return refused[ValidatorIndex](AssuranceDutyError.Uninitialized)
  if ordinal < 0 or ordinal >= data.local.len: return refused[ValidatorIndex](
      AssuranceDutyError.InvalidIndex)
  AssuranceDutyResult[ValidatorIndex](status: AssuranceDutyError.None, completed: ValidatorIndex(
      data.local[ordinal]))
proc assignment*(duty: AssuranceDuty, core: CoreIndex): AssuranceDutyResult[
    AvailabilityAssignment] =
  ## Return only the selected parent's actual immutable assignment, never a caller-created descriptor.
  let data = duty.data
  if data == nil: return refused[AvailabilityAssignment](AssuranceDutyError.Uninitialized)
  if uint64(core) >= uint64(data.info.cores): return refused[AvailabilityAssignment](
      AssuranceDutyError.InvalidIndex)
  AssuranceDutyResult[AvailabilityAssignment](status: AssuranceDutyError.None,
    completed: data.assignments.availabilityAt(AssignmentCoreIndex(uint64(core))).value)
proc shardRequest*(duty: AssuranceDuty, core: CoreIndex, ordinal: int): AssuranceDutyResult[
    AvailabilityRequest] =
  ## CE137 coordinates come from canonical report geometry and each original local index, not from a peer or request payload.
  let data = duty.data
  if data == nil: return refused[AvailabilityRequest](AssuranceDutyError.Uninitialized)
  if uint64(core) >= uint64(data.info.cores) or ordinal < 0 or ordinal >= data.local.len:
    return refused[AvailabilityRequest](AssuranceDutyError.InvalidIndex)
  let selected = data.assignments.availabilityAt(AssignmentCoreIndex(uint64(core))).value
  if not selected.present: return refused[AvailabilityRequest](AssuranceDutyError.InvalidIndex)
  let facts = selected.guarantee.report.ownedReportInfo.value
  let position = (uint64(core)*data.thresholds[int(uint64(core))]+uint64(data.local[
      ordinal])) mod uint64(data.info.validators)
  AssuranceDutyResult[AvailabilityRequest](status: AssuranceDutyError.None,
    completed: AvailabilityRequest(kind: AvailabilityTransferKind.Distribution,
      root: facts.header.erasureRoot, shard: ErasureShardIndex(position)))
proc captureAssuranceDuty*(source: BlockSnapshotResult, local: StateEdKey,
    limits: AssuranceDutyLimits): AssuranceDutyResult[AssuranceDuty] =
  ## Complete parent C8/C9/C10/C11 preflight precedes chapter copies, decoded owners and whole-request plan publication.
  template fail(reason: AssuranceDutyError) =
    return refused[AssuranceDuty](reason)
  if source.error != GenesisError.None: fail(AssuranceDutyError.InvalidSource)
  if array[32, byte](local) == default(array[32, byte]): fail(AssuranceDutyError.InvalidIdentity)
  if array[32, byte](local) == array[32, byte](nullValidator().ed25519): fail(
      AssuranceDutyError.InvalidIdentity)
  if uint64(limits.chapterBytes) == 0 or uint64(limits.readBytes) == 0 or uint64(limits.reports) ==
      0 or uint64(limits.requests) == 0:
    fail(AssuranceDutyError.InvalidPolicy)
  let head = source.value
  let profile = head.chainParameters
  let cores = profile.get(coreCount)
  let period = profile.get(slotPeriodSec)
  if cores < 2 or cores > 341 or period == 0: fail(AssuranceDutyError.InvalidSource)
  let state = head.stateSnapshot
  var total = 0'u64
  for chapter in [StateChapter(8), StateChapter(9), StateChapter(10), StateChapter(11)]:
    # Whole stored extents are charged before copying or decoding even the first chapter.
    let entry = state.lookup(chapterKey(chapter))
    if entry.error != StateStoreError.None: return AssuranceDutyResult[AssuranceDuty](
        status: AssuranceDutyError.StateFailure, stateReason: entry.error)
    let size = uint64(entry.value.byteLength)
    if size > uint64(limits.chapterBytes) or size > uint64(limits.readBytes)-total: fail(
        AssuranceDutyError.LimitExceeded)
    total += size
  let clockBytes = state.lookup(chapterKey(StateChapter(11))).value.bytes
  let clock = decodeStateTime(clockBytes)
  if clock.error != StateComponentError.None: return AssuranceDutyResult[AssuranceDuty](
      status: AssuranceDutyError.ComponentFailure, componentReason: clock.error)
  if clock.value.consumed != clockBytes.len or uint32(clock.value.value) != head.slot: fail(
      AssuranceDutyError.InvalidState)
  let rosterPolicy = ValidatorStateConfig(cores: CoreCount(cores), validators: ElementLimit(1023),
      maxBytes: limits.chapterBytes)
  let activeBytes = state.lookup(chapterKey(StateChapter(8))).value.bytes
  let active = decodeStateValidators(activeBytes, rosterPolicy)
  if active.error != StateComponentError.None: return AssuranceDutyResult[AssuranceDuty](
      status: AssuranceDutyError.ComponentFailure, componentReason: active.error)
  if active.value.consumed != activeBytes.len: fail(AssuranceDutyError.InvalidState)
  let count = active.value.value.validatorCount.value
  if count < 6 or count > 1023: fail(AssuranceDutyError.InvalidState)
  let previousBytes = state.lookup(chapterKey(StateChapter(9))).value.bytes
  let previous = decodeStateValidators(previousBytes, rosterPolicy)
  if previous.error != StateComponentError.None: return AssuranceDutyResult[AssuranceDuty](
      status: AssuranceDutyError.ComponentFailure, componentReason: previous.error)
  if previous.value.consumed != previousBytes.len: fail(AssuranceDutyError.InvalidState)
  let credentialCount = max(count, previous.value.value.validatorCount.value)
  let wire = state.lookup(chapterKey(StateChapter(10))).value.bytes
  let policy = AvailabilityConfig(guarantee: GuaranteeConfig(cores: CoreCount(cores),
      validators: ValidatorCount(uint64(credentialCount)), maxBytes: limits.chapterBytes),
      maxPresent: limits.reports, maxBytes: limits.chapterBytes)
  let assignments = decodeAvailabilityState(wire, policy)
  if assignments.error != AvailabilityError.None: return AssuranceDutyResult[AssuranceDuty](
      status: AssuranceDutyError.AvailabilityFailure, availabilityReason: assignments.error)
  if assignments.value.consumed != wire.len: fail(AssuranceDutyError.InvalidState)
  var indices: seq[uint16] = @[]
  for index in 0..<count:
    # Null/offender positions stay in the geometry; only the actual nonzero TLS key matches a local duty.
    let record = active.value.value.validatorAt(StateValidatorIndex(uint64(index))).value
    if array[32, byte](record.ed25519) == array[32, byte](local): indices.add(uint16(index))
  if indices.len == 0: fail(AssuranceDutyError.NotValidator)
  var thresholds = default(array[341, uint64])
  var present = 0
  for core in 0..<int(cores):
    # Complete source reports must agree with their position, actual parent population and registration clock.
    let selected = assignments.value.snapshot.availabilityAt(AssignmentCoreIndex(core)).value
    if selected.present:
      let report = selected.guarantee.report.ownedReportInfo
      if report.error != OwnershipError.None: fail(AssuranceDutyError.InvalidState)
      let facts = report.value
      if uint64(facts.core) != uint64(core) or uint16(facts.header.erasureShards) != uint16(
          count): fail(AssuranceDutyError.InvalidState)
      if uint32(selected.registered) > head.slot or uint32(selected.guarantee.slot) > uint32(
          selected.registered): fail(AssuranceDutyError.InvalidState)
      if uint32(facts.header.bundleLength) == 0 or uint32(facts.header.bundleLength) > uint32(
          MaxAvailabilityBundleBytes) or uint16(facts.header.segmentCount) > 3072: fail(
          AssuranceDutyError.InvalidState)
      let geometry = erasureGeometry(facts.header.bundleLength, facts.header.erasureShards)
      if geometry.error != ErasureLayoutError.None: return AssuranceDutyResult[AssuranceDuty](
          status: AssuranceDutyError.GeometryFailure, geometryReason: geometry.error)
      thresholds[core] = geometry.value.originalShards
      inc present
  let requests = uint64(present)*uint64(indices.len) # Both factors are bounded by 341 and 1023 before multiplication.
  if requests > uint64(limits.requests): fail(AssuranceDutyError.LimitExceeded)
  AssuranceDutyResult[AssuranceDuty](status: AssuranceDutyError.None,
    completed: AssuranceDuty(data: DutyData(info: AssuranceDutyInfo(anchor: head.blockHash,
      root: head.stateRoot, slot: StateTime(head.slot), local: local, cores: CoreCount(cores),
      validators: ValidatorCount(uint64(count)), assignments: present, localIndices: indices.len,
      requests: int(requests), slotSeconds: period), assignments: assignments.value.snapshot,
      local: indices, thresholds: thresholds)))
