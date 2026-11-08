# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Detached audit participation plans preserve original auditor positions, local signing ordinals and explicitly known successor recipients. Only genuine private origins and actual current canonical topology supply role/routing facts.

import ./[audit_origin, topology, endpoints, assurance_store]
import ../chain/[genesis, parameters, reports]
import ../codec/[bounded, report_owned]
import ../codec/state/[safrole, consensus, layout]
import ../state/store

type
  AuditParticipationLimits* = object ## Complete topology chapter copies, decoding workspace and worst-case detached recipients are reserved before extraction.
    topology*: SafroleStateConfig
    readBytes*, workspaceBytes*, outputBytes*: ByteLimit
  AuditParticipant* = object ## Original epoch/index, authenticated identity and optional advertised endpoint remain distinct from compressed plan positions.
    epoch*: uint64
    validator*: StateValidatorIndex
    identity*: StateEdKey
    endpoint*: EndpointResult
  AuditParticipationInfo* = object ## Actual source stamp permits later successor refresh without substituting an original auditor roster or local evaluation.
    source*: genesis.BlockHash
    report*: WorkReportHash
    epoch*, currentEpoch*, retainedBytes*: uint64
    localValidators*, neighbours*, successors*: int
  RoutingMember = object ## Original position owns only public identity and projected connection metadata.
    identity: StateEdKey
    endpoint: EndpointResult
  RoutingData = ref object ## Original roster provenance has no report, execution map or key owner.
    parameters: Parameters
    report: WorkReportHash
    epoch: uint64
    local: StateEdKey
    members: seq[RoutingMember]
  AuditRoutingBasis* = object ## Only actual private origin capture creates refresh authority.
    data: nil RoutingData
  PlanData = ref object ## Only immutable fixed copied metadata survives; complete source maps, validator snapshots and private keys retire before publication.
    info: AuditParticipationInfo
    basis: AuditRoutingBasis
    local: seq[StateValidatorIndex]
    neighbours, successors: seq[AuditParticipant]
  AuditParticipationPlan* = object ## Default output grants no role, routing or local signing ordinal.
    data: nil PlanData
  AuditParticipationError* {.pure.} = enum ## Missing future topology/history is unavailable metadata, never report invalidity or finality.
    Uninitialized, None, InvalidPolicy, InvalidSource, InvalidIndex, LimitExceeded, Cancelled,
    TopologyFailure, StateFailure
  AuditParticipationResult*[T] = object ## Failed/default alternatives contain no recipient or signing-index prefix.
    case status: AuditParticipationError
    of None: completed: T
    of TopologyFailure: topologyReason: TopologyError
    of StateFailure: stateReason: StateStoreError
    else: discard # No unrelated child or partial plan survives refusal.

func error*[T](outcome: AuditParticipationResult[T]): AuditParticipationError =
  ## Observe the selected status before extracting complete detached metadata.
  outcome.status

func value*[T](outcome: AuditParticipationResult[T]): T {.requires: outcome.status ==
    AuditParticipationError.None.} =
  ## Success carries only fixed copied recipient and original-position observations.
  outcome.completed

func topologyError*[T](outcome: AuditParticipationResult[
    T]): TopologyError {.requires: outcome.status == AuditParticipationError.TopologyFailure.} =
  ## Preserve the actual bounded topology decoder refusal.
  outcome.topologyReason

func stateError*[T](outcome: AuditParticipationResult[
    T]): StateStoreError {.requires: outcome.status == AuditParticipationError.StateFailure.} =
  ## Missing complete chapters cannot become fabricated empty future sets.
  outcome.stateReason

func valid*(limits: AuditParticipationLimits): bool =
  ## Explicit independent finite ceilings precede every snapshot/recipient allocation.
  uint64(limits.topology.validators.validators) in 6'u64..1023'u64 and
    uint64(limits.topology.validators.maxBytes) in 1'u64..1024'u64*1024 and
    uint64(limits.topology.maxBytes) in 1'u64..2'u64*1024*1024 and
    uint64(limits.readBytes) in 1'u64..4'u64*1024*1024 and
    uint64(limits.workspaceBytes) in 1'u64..64'u64*1024*1024 and
    uint64(limits.outputBytes) in 1'u64..4'u64*1024*1024

func valid*(plan: AuditParticipationPlan): bool =
  ## An absent handle grants no initialized empty-duty plan.
  plan.data != nil

proc participationInfo*(plan: AuditParticipationPlan): AuditParticipationResult[
    AuditParticipationInfo] =
  ## Copy fixed source/count facts without exporting any backing sequence.
  let data = plan.data
  if data == nil: return AuditParticipationResult[AuditParticipationInfo](
      status: AuditParticipationError.Uninitialized)
  AuditParticipationResult[AuditParticipationInfo](status: AuditParticipationError.None,
      completed: data.info)

proc localValidatorAt*(plan: AuditParticipationPlan, ordinal: int): AuditParticipationResult[
    StateValidatorIndex] =
  ## Every original matching local-key position is retained, including repeated keys; current roster positions never substitute.
  let data = plan.data
  if data == nil: return AuditParticipationResult[StateValidatorIndex](
      status: AuditParticipationError.Uninitialized)
  if ordinal < 0 or ordinal >= data.local.len:
    return AuditParticipationResult[StateValidatorIndex](
        status: AuditParticipationError.InvalidIndex)
  AuditParticipationResult[StateValidatorIndex](status: AuditParticipationError.None,
      completed: data.local[ordinal])

proc participantAt*(plan: AuditParticipationPlan, successor: bool,
    ordinal: int): AuditParticipationResult[AuditParticipant] =
  ## Explicitly separate original-grid forwarding from known successor broadcast recipients.
  let data = plan.data
  if data == nil: return AuditParticipationResult[AuditParticipant](
      status: AuditParticipationError.Uninitialized)
  let count = if successor: data.successors.len else: data.neighbours.len
  if ordinal < 0 or ordinal >= count:
    return AuditParticipationResult[AuditParticipant](status: AuditParticipationError.InvalidIndex)
  AuditParticipationResult[AuditParticipant](status: AuditParticipationError.None,
    completed: if successor: data.successors[ordinal] else: data.neighbours[ordinal])

func sameKey(a, b: StateEdKey): bool =
  ## Identity equality is independent of metadata and original index.
  array[32, byte](a) == array[32, byte](b)

func nonzero(key: StateEdKey): bool =
  ## Zero/null positions stay counted but never become a remote connection or local signer.
  if sameKey(key, nullValidator().ed25519): return false
  for octet in array[32, byte](key):
    if octet != 0: return true
  false

func valid*(basis: AuditRoutingBasis): bool =
  ## Defaults grant no original roster authority.
  basis.data != nil

proc routingBasis*(plan: AuditParticipationPlan): AuditRoutingBasis =
  ## Return the immutable public routing input without exposing a mutable roster.
  let data = plan.data
  if data == nil: return default(AuditRoutingBasis)
  data.basis

proc detached*(basis: AuditRoutingBasis, bytes: ByteLimit): AuditRoutingBasis =
  ## A worker-owned copy never borrows the foreground gossip row's ARC graph.
  let data = basis.data
  if data == nil or uint64(data.members.len)*uint64(sizeof(RoutingMember)) > uint64(bytes):
    return default(AuditRoutingBasis)
  var members = newSeq[RoutingMember](data.members.len)
  for index in 0..<members.len: members[index] = data.members[index]
  AuditRoutingBasis(data: RoutingData(parameters: data.parameters, report: data.report,
      epoch: data.epoch, local: data.local, members: move(members)))

proc refreshAuditParticipation*(basis: AuditRoutingBasis, current: BlockSnapshotResult,
    limits: AuditParticipationLimits,
    control: AssuranceScanControl = default(AssuranceScanControl)): AuditParticipationResult[
        AuditParticipationPlan] =
  ## Recompute routing from exact original public metadata and trusted current topology.
  if not limits.valid: return AuditParticipationResult[AuditParticipationPlan](
      status: AuditParticipationError.InvalidPolicy)
  let original = basis.data
  if original == nil or current.error != GenesisError.None:
    return AuditParticipationResult[AuditParticipationPlan](
        status: AuditParticipationError.InvalidSource)
  if control.stopped: return AuditParticipationResult[AuditParticipationPlan](
      status: AuditParticipationError.Cancelled)
  if not original.parameters.sameParameterProfile(current.value.chainParameters):
    return AuditParticipationResult[AuditParticipationPlan](
        status: AuditParticipationError.InvalidSource)
  let count = original.members.len
  let local = original.local
  let state = current.value.stateSnapshot
  var reads = 0'u64
  for chapter in [4, 8, 9, 11]:
    # Length-only complete chapter preflight precedes every copied roster and clock decoder.
    let selected = state.lookup(chapterKey(StateChapter(chapter)))
    if selected.error != StateStoreError.None:
      return AuditParticipationResult[AuditParticipationPlan](
          status: AuditParticipationError.StateFailure, stateReason: selected.error)
    let length = uint64(selected.value.byteLength)
    if length > uint64(limits.readBytes)-reads:
      return AuditParticipationResult[AuditParticipationPlan](
          status: AuditParticipationError.LimitExceeded)
    reads += length
  let retained = 65536'u64+uint64(count)*uint64(sizeof(RoutingMember)+16)+3'u64*1023*(uint64(sizeof(
      AuditParticipant))+64)
  if retained > uint64(limits.outputBytes) or 8*reads+retained+262144 > uint64(
      limits.workspaceBytes):
    return AuditParticipationResult[AuditParticipationPlan](
        status: AuditParticipationError.LimitExceeded)
  let rawClock = state.lookup(chapterKey(StateChapter(11))).value
  if rawClock.byteLength != 4:
    return AuditParticipationResult[AuditParticipationPlan](
        status: AuditParticipationError.InvalidSource)
  let clock = decodeStateTime(rawClock.bytes)
  if clock.error != StateComponentError.None or uint64(uint32(clock.value.value)) !=
      current.value.slot:
    return AuditParticipationResult[AuditParticipationPlan](
        status: AuditParticipationError.InvalidSource)
  let topology = captureValidatorTopology(current, limits.topology)
  if topology.error != TopologyError.None:
    return AuditParticipationResult[AuditParticipationPlan](
        status: AuditParticipationError.TopologyFailure, topologyReason: topology.error)
  let projection = topology.value
  let epoch = original.epoch
  let currentEpoch = uint64(projection.slot) div uint64(projection.epochSlots)
  var width = 1
  while (width+1)*(width+1) <= count:
    # count<=1023 proves exact integer square-root products fit without floating-point rounding.
    inc width
  var rows, columns, positions, crossPositions = default(array[1023, bool])
  var validators: seq[StateValidatorIndex] = @[]
  for ordinal in 0..<count:
    # All aliases retain original signing positions while row/column masks bound later grid selection to linear work.
    if control.stopped: return AuditParticipationResult[AuditParticipationPlan](
        status: AuditParticipationError.Cancelled)
    if sameKey(original.members[ordinal].identity, local):
      validators.add(StateValidatorIndex(uint64(ordinal)))
      positions[ordinal] = true
      rows[ordinal div width] = true
      columns[ordinal mod width] = true
  var crossCandidates: seq[StateEdKey] = @[]
  for relative in low(ValidatorEpoch)..high(ValidatorEpoch):
    # The NP grid is an identity union across known epochs. Preserve original duty positions while including genuine cross-epoch same-index neighbours in both directions.
    if relative == ValidatorEpoch.Previous and currentEpoch == 0: continue
    let known = if relative == ValidatorEpoch.Previous: currentEpoch-1
      elif relative == ValidatorEpoch.Next: currentEpoch+1
      else: currentEpoch
    if known == epoch: continue
    for ordinal in 0..<projection.population(relative):
      if control.stopped: return AuditParticipationResult[AuditParticipationPlan](
          status: AuditParticipationError.Cancelled)
      let member = projection.membershipAt(relative, StateValidatorIndex(uint64(ordinal))).value
      if sameKey(member.identity, local): crossPositions[ordinal] = true
      if positions[ordinal] and nonzero(member.identity): crossCandidates.add(member.identity)
  var neighbours, successors: seq[AuditParticipant] = @[]
  for ordinal in 0..<count:
    # Recipients remain original auditors. Additional actual projected memberships can establish NP grid adjacency, never replace original duty/signing authority.
    let record = original.members[ordinal]
    if control.stopped: return AuditParticipationResult[AuditParticipationPlan](
        status: AuditParticipationError.Cancelled)
    if not nonzero(record.identity) or sameKey(record.identity, local): continue
    var adjacent = rows[ordinal div width] or columns[ordinal mod width] or crossPositions[ordinal]
    if not adjacent: adjacent = projection.neighbours(local, record.identity)
    for candidate in crossCandidates:
      # Every roster is bounded to1023 positions; the identity-union comparison product is finite before any native request is admitted.
      if sameKey(candidate, record.identity): adjacent = true
    if adjacent:
      neighbours.add(AuditParticipant(epoch: epoch, validator: StateValidatorIndex(uint64(ordinal)),
        identity: record.identity, endpoint: record.endpoint))
  for relative in low(ValidatorEpoch)..high(ValidatorEpoch):
    # Only actual current/previous or C4 pending projection is known. Future E+2 targets are refreshed when genuine later state reveals them; C7 is never guessed.
    if relative == ValidatorEpoch.Previous and currentEpoch == 0: continue
    let selectedEpoch = if relative == ValidatorEpoch.Previous: currentEpoch-1
      elif relative == ValidatorEpoch.Next: currentEpoch+1
      else: currentEpoch
    if selectedEpoch <= epoch or selectedEpoch-epoch > 2: continue
    for ordinal in 0..<projection.population(relative):
      if control.stopped: return AuditParticipationResult[AuditParticipationPlan](
          status: AuditParticipationError.Cancelled)
      let member = projection.membershipAt(relative, StateValidatorIndex(uint64(ordinal))).value
      if nonzero(member.identity) and not sameKey(member.identity, local):
        successors.add(AuditParticipant(epoch: selectedEpoch, validator: StateValidatorIndex(uint64(
            ordinal)),
          identity: member.identity, endpoint: member.endpoint))
  if control.stopped: return AuditParticipationResult[AuditParticipationPlan](
      status: AuditParticipationError.Cancelled)
  AuditParticipationResult[AuditParticipationPlan](status: AuditParticipationError.None,
    completed: AuditParticipationPlan(data: PlanData(info: AuditParticipationInfo(
      source: current.value.blockHash,
      report: original.report, epoch: epoch, currentEpoch: currentEpoch,
      retainedBytes: retained, localValidators: validators.len, neighbours: neighbours.len,
      successors: successors.len),
      basis: basis, local: move(validators), neighbours: move(neighbours), successors: move(successors))))

proc captureAuditParticipation*(origin: AuditReportOrigin, current: BlockSnapshotResult,
    local: StateEdKey, limits: AuditParticipationLimits,
    control: AssuranceScanControl = default(AssuranceScanControl)): AuditParticipationResult[
        AuditParticipationPlan] =
  ## Detach the authenticated original roster once, then use the same planner as later refreshes.
  if not limits.valid: return AuditParticipationResult[AuditParticipationPlan](
      status: AuditParticipationError.InvalidPolicy)
  if not origin.valid or current.error != GenesisError.None or not nonzero(local):
    return AuditParticipationResult[AuditParticipationPlan](
        status: AuditParticipationError.InvalidSource)
  let count = origin.auditorCount.value
  if count notin 6..1023 or sizeof(AuditParticipant) > 512:
    return AuditParticipationResult[AuditParticipationPlan](
        status: AuditParticipationError.InvalidSource)
  let bytes = uint64(count)*uint64(sizeof(RoutingMember))
  if bytes > uint64(limits.outputBytes) or bytes > uint64(limits.workspaceBytes):
    return AuditParticipationResult[AuditParticipationPlan](
        status: AuditParticipationError.LimitExceeded)
  var members = newSeq[RoutingMember](count)
  for ordinal in 0..<count:
    # Original positions remain intact even if an identity is null or repeated.
    if control.stopped: return AuditParticipationResult[AuditParticipationPlan](
        status: AuditParticipationError.Cancelled)
    let validator = origin.auditorAt(ordinal).value
    members[ordinal] = RoutingMember(identity: validator.ed25519,
        endpoint: validatorEndpoint(array[128, byte](validator.metadata)))
  let basis = AuditRoutingBasis(data: RoutingData(parameters: origin.originParameters.value,
      report: origin.originReportHash.value, epoch: origin.auditEpoch.value, local: local,
      members: move(members)))
  refreshAuditParticipation(basis, current, limits, control)
