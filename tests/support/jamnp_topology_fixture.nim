# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Structural complete-map topology fixtures, with explicit chain clocks and parent commitments.
import std/assertions
import ../../src/chain/[genesis, parameters]
import ../../src/codec/[bounded, header, assurances]
import ../../src/codec/state/[safrole, consensus, layout, trie]

proc topologySettings*(cores = 4, duration = 12): Parameters =
  ## Four cores permit independently sized 6/9/12-member rosters.
  let decoded = decodeParametersHex("ffffffffffffffff020000000000000003000000000000000400050000000c0000000700000000000000080000000000000009000000000000000a000000000000000b000c000d000e000f000000100011001200130014001500160000001700000018000000190000001a0000001b0000001c0000000a000000")
  assert decoded.ok
  var wire = encodeParameters(decoded.value)
  wire[24] = byte(cores mod 256)
  wire[25] = byte(cores div 256)
  for index in 0..<4:
    wire[30+index] = byte((uint32(duration) shr (index*8)) and 255) # Explicit fetch E4 epoch field.
  let selected = decodeParameters(wire)
  assert selected.ok
  selected.value
proc topologyLimits*(cores = 4, duration = 12): SafroleStateConfig =
  ## Exact chain dimensions with finite per-chapter budgets.
  SafroleStateConfig(validators: ValidatorStateConfig(cores: CoreCount(uint64(cores)),
      validators: ElementLimit(uint64(cores)*3),
    maxBytes: ByteLimit(uint64(cores)*1008+9)), epochSlots: EpochSlots(uint64(duration)),
        maxAccumulator: ElementLimit(12), maxBytes: ByteLimit(1024*1024))
proc topologyKey*(id: int): StateEdKey =
  ## Two bytes distinguish fixture identities without relying on production key projection.
  var raw = default(array[32, byte])
  raw[0] = byte(id mod 256)
  raw[1] = byte(id div 256)
  StateEdKey(raw)
proc topologyRecords*(epoch, count: int): seq[StateValidator] =
  ## Keep roles distinct by default; individual tests deliberately introduce aliases/nulls.
  result = newSeq[StateValidator](count)
  for index in 0..<count:
    var metadata = default(array[128, byte])
    metadata[15] = 1
    metadata[16] = 55
    result[index] = StateValidator(ed25519: topologyKey(20+epoch*40+index),
        metadata: StateValidatorMetadata(metadata))
proc topologyChapter(roster: seq[StateValidator], which: ValidatorChapter): StateEntry =
  ## Encode trusted structural fixtures synchronously.
  let encoded = validatorEntry(which, roster, topologyLimits().validators)
  assert encoded.error == StateComponentError.None
  encoded.value
proc topologyCaptured*(rosters: array[3, seq[StateValidator]], omit = false,
    suffix = false, cores = 4, duration = 12, atSlot = 7'u32,
    parent: BlockSnapshotResult = unavailableGenesis()): BlockSnapshotResult =
  ## A complete-map fixture has exact slot/header binding; no consensus certification is implied.
  let pending = safroleStateEntry(SafroleState(pending: rosters[2],
    schedule: keySchedule(newSeq[StateBsKey](duration))), topologyLimits(cores, duration))
  assert pending.error == StateComponentError.None
  var entries = @[pending.value, topologyChapter(rosters[1], ValidatorChapter.Active),
    StateEntry(key: chapterKey(StateChapter(11)), value: @[7'u8, 0, 0, 0]),
    StateEntry(key: chapterKey(StateChapter(7)), value: @[255'u8])] # Invalid staging must not be used as next.
  if suffix: entries[0].value.add(0) # C(4) remains structurally prefix-decodable, but projection must reject it.
  if not omit: entries.add(topologyChapter(rosters[0], ValidatorChapter.Previous))
  var wire = newSeq[byte](297)
  # Slot/header exactness is independent of the projection under test.
  for index in 0..<4:
    wire[96+index] = byte((atSlot shr (index*8)) and 255)
    entries[2].value[index] = wire[96+index]
  if parent.error == GenesisError.None:
    let identity = array[32, byte](parent.value.blockHash)
    let root = array[32, byte](parent.value.stateRoot)
    for index in 0..<32:
      wire[index] = identity[index] # Exact sealed parent identity, never a peer hint.
      wire[32+index] = root[index]
  captureBlockSnapshot(wire, entries, topologySettings(cores, duration))
