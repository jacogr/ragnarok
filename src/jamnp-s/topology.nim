# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable JAMNP-S roster/grid projection from a complete block snapshot. The caller selects
## canonical state; structural snapshot capture alone proves neither consensus nor finality.

import std/assertions
import ../chain/[genesis, parameters]
import ../codec/[bounded, header]
import ../codec/state/[safrole, consensus, layout]
import ../state/store
import ./endpoints

type
  ValidatorEpoch* {.pure.} = enum ## Relative epoch; pending means C(4), never staging C(7).
    Previous, Current, Next
  TopologyError* {.pure.} = enum ## No refused projection exposes partial membership.
    Uninitialized, None, InvalidConfig, MissingState, InvalidState, LimitExceeded, InvalidIndex
  Membership* = object ## Fixed copied identity/routing facts; no mutable roster storage escapes.
    key: StateEdKey
    route: EndpointResult
  TopologyData = ref object ## Private immutable acyclic storage retains all ordinal positions, including null slots.
    rosters: array[ValidatorEpoch, seq[Membership]]
    source: BlockHash
    atSlot: uint32
    epochLength: uint32
  ValidatorTopology* = object ## A shared immutable handle; defaults carry no membership authority.
    data: nil TopologyData
  TopologyResult*[T] = object ## Access only a selected success; default/error alternatives have no payload.
    case status: TopologyError
    of None: completed: T
    else: discard # Failure cannot masquerade as an empty validator union.

func error*[T](outcome: TopologyResult[T]): TopologyError =
  ## Inspect the reason before extraction.
  outcome.status

func value*[T](outcome: TopologyResult[T]): T {.requires: outcome.status == TopologyError.None.} =
  ## Return only completed immutable data or fixed facts.
  outcome.completed

func identity*(membership: Membership): StateEdKey =
  ## Copy the exact Ed25519 identity; metadata never authenticates it.
  membership.key

func endpoint*(membership: Membership): EndpointResult =
  ## Preserve unavailable advertised routing independently from membership.
  membership.route

func ready*(topology: ValidatorTopology): bool =
  ## Defaults are explicitly unavailable.
  topology.data != nil

func sourceBlock*(topology: ValidatorTopology): BlockHash {.requires: topology.ready.} =
  ## Bind the projection to the exact selected block.
  let data = topology.data
  assert data != nil # Bind the retained owner before reading immutable data.
  data.source

func slot*(topology: ValidatorTopology): uint32 {.requires: topology.ready.} =
  ## Return the source clock, without inventing epoch transition authority.
  let data = topology.data
  assert data != nil # Bind the retained owner before reading immutable data.
  data.atSlot

func epochSlots*(topology: ValidatorTopology): uint32 {.requires: topology.ready.} =
  ## Return the source chain's validated epoch length.
  let data = topology.data
  assert data != nil # Bind the retained owner before reading immutable data.
  data.epochLength

func population*(topology: ValidatorTopology, epoch: ValidatorEpoch): int {.requires: topology.ready.} =
  ## Count ordinal positions, including null validators and repeated keys.
  let data = topology.data
  assert data != nil # Bind the retained owner before reading immutable data.
  data.rosters[epoch].len

proc membershipAt*(topology: ValidatorTopology, epoch: ValidatorEpoch,
    index: StateValidatorIndex): TopologyResult[Membership] =
  ## A checked ordinal returns a fixed copy bound to this projection during extraction.
  let data = topology.data
  if data == nil: return TopologyResult[Membership](status: TopologyError.Uninitialized)
  if uint64(index) >= uint64(data.rosters[epoch].len):
    return TopologyResult[Membership](status: TopologyError.InvalidIndex) # Narrow only within the retained roster.
  TopologyResult[Membership](status: TopologyError.None, completed: data.rosters[epoch][int(uint64(index))])

func sameKey(left, right: StateEdKey): bool =
  ## Compare identity bytes without confusing them with Bandersnatch or metadata.
  array[32, byte](left) == array[32, byte](right)

func participant(key: StateEdKey): bool =
  ## The current pinned null Ed25519 encoding denotes a vacant ordinal.
  not sameKey(key, nullValidator().ed25519)

proc contains*(topology: ValidatorTopology, key: StateEdKey): bool =
  ## Membership is the union of all three epochs; no endpoint is required for authority.
  let data = topology.data
  if data == nil or not participant(key): return false
  for epoch in low(ValidatorEpoch)..high(ValidatorEpoch):
    # Index traversal does not lend mutable storage reached through the shared owner.
    for index in 0..<data.rosters[epoch].len:
      if sameKey(data.rosters[epoch][index].key, key): return true # Keep searching only until one real membership matches.
  false

func gridWidth(count: int): int =
  ## Exact integer floor(sqrt(V)); rosters are codec-bounded to 6..1023.
  result = 1
  while (result+1)*(result+1) <= count: inc result # Products are below 1024 here.

proc neighbours*(topology: ValidatorTopology, left, right: StateEdKey): bool =
  ## Compute the identity union in linear roster work, retaining every alias/ordinal.
  let data = topology.data
  if data == nil or sameKey(left, right) or not participant(left) or not participant(
      right): return false
  var positions = default(array[ValidatorEpoch, array[1023, bool]])
  var rows, columns = default(array[ValidatorEpoch, array[1023, bool]])
  for epoch in low(ValidatorEpoch)..high(ValidatorEpoch):
    let width = gridWidth(data.rosters[epoch].len)
    # Record only the first identity's positions; aliases remain independent slots.
    for index in 0..<data.rosters[epoch].len:
      if sameKey(data.rosters[epoch][index].key, left):
        positions[epoch][index] = true # Cross-epoch comparisons preserve the exact ordinal.
        rows[epoch][index div width] = true
        columns[epoch][index mod width] = true
  for epoch in low(ValidatorEpoch)..high(ValidatorEpoch):
    let width = gridWidth(data.rosters[epoch].len)
    # Test the second identity against row/column masks and other-epoch ordinals.
    for index in 0..<data.rosters[epoch].len:
      if sameKey(data.rosters[epoch][index].key, right):
        if rows[epoch][index div width] or columns[epoch][index mod width]: return true
        for other in low(ValidatorEpoch)..high(ValidatorEpoch):
          if other != epoch and positions[other][index]: return true # Equal indices connect different epochs.
  false

func codecError(reason: StateComponentError): TopologyError =
  ## Preserve caller policy refusal separately from malformed exact state.
  case reason
  of StateComponentError.InvalidConfig: TopologyError.InvalidConfig # Configuration is not a wire defect.
  of StateComponentError.LimitExceeded: TopologyError.LimitExceeded # Keep explicit local work ceilings observable.
  else: TopologyError.InvalidState # Other structural failures grant no membership.

proc project(record: StateValidator): Membership =
  ## Copy only networking facts; no key validation or routing fallback is fabricated.
  Membership(key: record.ed25519, route: validatorEndpoint(array[128, byte](record.metadata)))

proc captureValidatorTopology*(source: BlockSnapshotResult,
    policy: SafroleStateConfig): TopologyResult[ValidatorTopology] =
  ## Decode exact C(4)/C(8)/C(9) under explicit bounded policy; C(7) is irrelevant.
  if source.error != GenesisError.None:
    return TopologyResult[ValidatorTopology](status: TopologyError.Uninitialized)
  let snapshot = source.value
  let parameters = snapshot.chainParameters
  let cores = parameters.get(coreCount)
  let duration = parameters.get(epochPeriod)
  if cores < 2 or cores > 341 or duration == 0 or duration > uint64(high(uint32)) or
      uint64(policy.validators.cores) != cores or uint64(policy.epochSlots) != duration or
      uint64(policy.validators.validators) > 1023:
    return TopologyResult[ValidatorTopology](status: TopologyError.InvalidConfig) # No mixed chain or unbounded ordinal space.
  var raw = default(array[3, seq[byte]])
  for index, chapter in [4, 8, 9]:
    let found = snapshot.stateSnapshot.lookup(chapterKey(StateChapter(chapter)))
    if found.error != StateStoreError.None:
      return TopologyResult[ValidatorTopology](status: TopologyError.MissingState) # No partial authority from remaining epochs.
    let bound = if index == 0: uint64(policy.maxBytes) else: uint64(policy.validators.maxBytes)
    if uint64(found.value.byteLength) > bound:
      return TopologyResult[ValidatorTopology](status: TopologyError.LimitExceeded) # Check before copying owner bytes.
    raw[index] = found.value.bytes
  let pending = decodeSafroleState(raw[0], policy)
  if pending.error != StateComponentError.None:
    return TopologyResult[ValidatorTopology](status: codecError(pending.error))
  if pending.value.consumed != raw[0].len:
    return TopologyResult[ValidatorTopology](status: TopologyError.InvalidState) # Chapter values must be exact, not valid prefixes.
  var data = TopologyData(source: snapshot.blockHash, atSlot: snapshot.slot, epochLength: uint32(duration))
  let info = safroleInfo(pending.value.snapshot)
  if info.error != StateComponentError.None:
    return TopologyResult[ValidatorTopology](status: codecError(info.error))
  data.rosters[ValidatorEpoch.Next] = newSeq[Membership](info.value.validators)
  for index in 0..<info.value.validators:
    let record = pendingValidatorAt(pending.value.snapshot, StateValidatorIndex(uint64(index)))
    if record.error != StateComponentError.None:
      return TopologyResult[ValidatorTopology](status: codecError(record.error))
    data.rosters[ValidatorEpoch.Next][index] = project(record.value) # Preserve pending order and aliases.
  for index, epoch in [ValidatorEpoch.Current, ValidatorEpoch.Previous]:
    let decoded = decodeStateValidators(raw[index+1], policy.validators)
    if decoded.error != StateComponentError.None:
      return TopologyResult[ValidatorTopology](status: codecError(decoded.error))
    if decoded.value.consumed != raw[index+1].len:
      return TopologyResult[ValidatorTopology](status: TopologyError.InvalidState) # Refuse hidden trailing records.
    let count = validatorCount(decoded.value.value)
    if count.error != StateComponentError.None:
      return TopologyResult[ValidatorTopology](status: codecError(count.error))
    data.rosters[epoch] = newSeq[Membership](count.value)
    for ordinal in 0..<count.value:
      let record = validatorAt(decoded.value.value, StateValidatorIndex(uint64(ordinal)))
      if record.error != StateComponentError.None:
        return TopologyResult[ValidatorTopology](status: codecError(record.error))
      data.rosters[epoch][ordinal] = project(record.value) # Never sort or deduplicate a roster.
  TopologyResult[ValidatorTopology](status: TopologyError.None, completed: ValidatorTopology(data: data))
