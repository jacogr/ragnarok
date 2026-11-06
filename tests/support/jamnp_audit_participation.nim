# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal original-grid coordinates and actual separately decoded pending successor keys test source-free participation planning without inventing future validator sets or current signing ordinals.
import std/assertions
import ../../src/jamnp-s/[audit_participation, audit_origin, audit_context, assurance_store]
import ../../src/codec/bounded
import ../../src/codec/state/[safrole, layout]
import ../../src/chain/[genesis, provider, parameters]
import ../../src/state/store
import ./[jamnp_audit_context, jamnp_topology_fixture]
proc participationLimits*(): AuditParticipationLimits =
  ## All actual source chapters, maximum detached recipients and transient decoding have independent explicit ceilings.
  AuditParticipationLimits(topology: topologyLimits(3, 12), readBytes: ByteLimit(4000000),
    workspaceBytes: ByteLimit(64000000), outputBytes: ByteLimit(4000000))
proc stopParticipation(raw: nil pointer): bool {.nimcall, raises: [].} =
  ## Cancellation cannot publish local indices or a neighbour prefix.
  true
type RolePosition = object ## Test-only pairwise reference keeps every actual role position, including aliases across epochs.
  epoch: uint64
  ordinal, population: int
  key: StateEdKey
proc referenceNeighbours(fixture: AuditContextFixture, origin: AuditReportOrigin,
    local: StateEdKey): seq[int] =
  ## Independently enumerate original/C8/C4 positions and compare every matching identity pair using the literal NP grid rules, rather than production masks/topology-neighbour helpers.
  let current = fixture.view.bestBlock.value
  let epoch = current.slot div current.chainParameters.get(epochPeriod)
  let original = origin.auditEpoch.value
  var roles: seq[RolePosition] = @[]
  let count = origin.auditorCount.value
  for ordinal in 0..<count:
    roles.add(RolePosition(epoch: original, ordinal: ordinal, population: count,
      key: origin.auditorAt(ordinal).value.ed25519))
  for chapter in [8, 9]:
    # Epoch-zero C9 cannot supply a fictitious epoch minus one in the independent oracle either.
    if chapter == 9 and epoch == 0: continue
    let bytes = current.stateSnapshot.lookup(chapterKey(StateChapter(chapter))).value.bytes
    let roster = decodeStateValidators(bytes, participationLimits().topology.validators).value.value
    let total = roster.validatorCount.value
    let selectedEpoch = if chapter == 8: epoch else: epoch-1
    for ordinal in 0..<total:
      roles.add(RolePosition(epoch: selectedEpoch, ordinal: ordinal, population: total,
        key: roster.validatorAt(StateValidatorIndex(uint64(ordinal))).value.ed25519))
  let bytes = current.stateSnapshot.lookup(chapterKey(StateChapter(4))).value.bytes
  let pending = decodeSafroleState(bytes, participationLimits().topology).value.snapshot
  let total = pending.safroleInfo.value.validators
  for ordinal in 0..<total:
    roles.add(RolePosition(epoch: epoch+1, ordinal: ordinal, population: total,
      key: pending.pendingValidatorAt(StateValidatorIndex(uint64(ordinal))).value.ed25519))
  result = @[]
  for ordinal in 0..<count:
    # The recipient is still an original auditor even if a second actual epoch membership establishes its physical grid adjacency.
    let candidate = origin.auditorAt(ordinal).value.ed25519
    if array[32, byte](candidate) == array[32, byte](local): continue
    if array[32, byte](candidate) == array[32, byte](nullValidator().ed25519): continue
    var adjacent = false
    for left in roles:
      if array[32, byte](left.key) != array[32, byte](local): continue
      for right in roles:
        if array[32, byte](right.key) != array[32, byte](candidate): continue
        if left.epoch != right.epoch:
          if left.ordinal == right.ordinal: adjacent = true
        else:
          assert left.population == right.population
          var width = 1
          while (width+1)*(width+1) <= left.population: inc width
          if left.ordinal div width == right.ordinal div width or left.ordinal mod width ==
              right.ordinal mod width: adjacent = true
    if adjacent: result.add(ordinal)
proc auditParticipationChecks*(fixture: AuditContextFixture) =
  ## Original N9 auditor ordinal one has literal three-by-three neighbours0/2/4/7; actual C4 supplies the only presently known successor epoch.
  let origin = captureAuditOrigin(fixture.view, fixture.blockHash, auditLimits(), auditOriginLimits()).value.reportAt(0).value
  let context = origin.originContext.value
  let local = context.auditorAt(1).value.ed25519
  let checked = captureAuditParticipation(origin, fixture.view.bestBlock, local,
      participationLimits())
  assert checked.error == AuditParticipationError.None
  let plan = checked.value
  let info = plan.participationInfo.value
  assert info.localValidators == 1 and info.epoch == 0 and
      info.currentEpoch == 0
  assert uint64(plan.localValidatorAt(0).value) == 1
  assert plan.localValidatorAt(1).error == AuditParticipationError.InvalidIndex
  let expectedNeighbours = referenceNeighbours(fixture, origin, local)
  assert info.neighbours == expectedNeighbours.len
  for index in [0, 2, 4, 7]:
    # The independently fixed original-grid row/column neighbours remain required even when genuine cross-epoch roles add further recipients.
    var present = false
    for actual in expectedNeighbours:
      if actual == index: present = true
    assert present
  for ordinal, index in expectedNeighbours:
    let peer = plan.participantAt(false, ordinal).value
    assert uint64(peer.validator) == uint64(index) and peer.epoch == 0
    assert array[32, byte](peer.identity) == array[32, byte](context.auditorAt(index).value.ed25519)
  let value = fixture.view.bestBlock.value.stateSnapshot.lookup(chapterKey(StateChapter(4))).value
  let pending = decodeSafroleState(value.bytes, participationLimits().topology).value.snapshot
  let count = pending.safroleInfo.value.validators
  var expected = 0
  for index in 0..<count:
    # Derive actual future membership independently from the canonical C4 decoder, without treating unrelated C7 as a future roster.
    let record = pending.pendingValidatorAt(StateValidatorIndex(uint64(index))).value
    if array[32, byte](record.ed25519) == array[32, byte](local): continue
    if array[32, byte](record.ed25519) == array[32, byte](nullValidator().ed25519): continue
    let peer = plan.participantAt(true, expected).value
    assert peer.epoch == 1 and uint64(peer.validator) == uint64(index)
    assert array[32, byte](peer.identity) == array[32, byte](record.ed25519)
    inc expected
  assert info.successors == expected
  assert plan.participantAt(false, info.neighbours).error == AuditParticipationError.InvalidIndex
  var key = default(array[32, byte])
  key[0] = 250
  let absent = captureAuditParticipation(origin, fixture.view.bestBlock, StateEdKey(key),
      participationLimits()).value
  assert absent.participationInfo.value.localValidators == 0 and
      absent.participationInfo.value.neighbours == 0
  let missing = captureAuditParticipation(origin, unavailableGenesis(), local, participationLimits())
  assert missing.error == AuditParticipationError.InvalidSource
  assert captureAuditParticipation(origin, fixture.view.bestBlock, local, default(
      AuditParticipationLimits)).error == AuditParticipationError.InvalidPolicy
  var limited = participationLimits()
  limited.readBytes = ByteLimit(1)
  assert captureAuditParticipation(origin, fixture.view.bestBlock, local, limited).error ==
      AuditParticipationError.LimitExceeded
  limited = participationLimits()
  limited.outputBytes = ByteLimit(1)
  assert captureAuditParticipation(origin, fixture.view.bestBlock, local, limited).error ==
      AuditParticipationError.LimitExceeded
  assert captureAuditParticipation(origin, fixture.view.bestBlock, local, participationLimits(),
      assuranceScanControl(stopParticipation, nil)).error == AuditParticipationError.Cancelled
