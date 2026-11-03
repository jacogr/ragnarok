# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete-state roster projection checked against an independent pairwise grid oracle.
import std/[assertions, syncio]
import ../../../src/jamnp-s/[topology, endpoints]
import ../../../src/chain/[genesis, parameters]
import ../../../src/codec/[bounded, header, assurances]
import ../../../src/codec/state/[safrole, consensus, layout, trie]

proc settings(cores = 4): Parameters =
  ## Four cores permit independently sized 6/9/12-member rosters.
  let decoded = decodeParametersHex("ffffffffffffffff020000000000000003000000000000000400050000000c0000000700000000000000080000000000000009000000000000000a000000000000000b000c000d000e000f000000100011001200130014001500160000001700000018000000190000001a0000001b0000001c0000000a000000")
  assert decoded.ok
  var wire = encodeParameters(decoded.value)
  wire[24] = byte(cores mod 256)
  wire[25] = byte(cores div 256)
  let selected = decodeParameters(wire)
  assert selected.ok
  selected.value
proc policy(cores = 4): SafroleStateConfig =
  ## Exact chain dimensions with finite per-chapter budgets.
  SafroleStateConfig(validators: ValidatorStateConfig(cores: CoreCount(uint64(cores)),
      validators: ElementLimit(uint64(cores)*3),
    maxBytes: ByteLimit(uint64(cores)*1008+9)), epochSlots: EpochSlots(12),
        maxAccumulator: ElementLimit(12), maxBytes: ByteLimit(1024*1024))
proc key(id: int): StateEdKey =
  ## Two bytes distinguish fixture identities without relying on production key projection.
  var raw = default(array[32, byte])
  raw[0] = byte(id mod 256)
  raw[1] = byte(id div 256)
  StateEdKey(raw)
proc records(epoch, count: int): seq[StateValidator] =
  ## Keep roles distinct by default; individual tests deliberately introduce aliases/nulls.
  result = newSeq[StateValidator](count)
  for index in 0..<count:
    var metadata = default(array[128, byte])
    metadata[15] = 1
    metadata[16] = 55
    result[index] = StateValidator(ed25519: key(20+epoch*40+index),
        metadata: StateValidatorMetadata(metadata))
proc chapter(roster: seq[StateValidator], which: ValidatorChapter): StateEntry =
  ## Encode trusted structural fixtures synchronously.
  let encoded = validatorEntry(which, roster, policy().validators)
  assert encoded.error == StateComponentError.None
  encoded.value
proc captured(rosters: array[3, seq[StateValidator]], omit = false,
    suffix = false, cores = 4): BlockSnapshotResult =
  ## A complete-map fixture has exact slot/header binding; no consensus certification is implied.
  let pending = safroleStateEntry(SafroleState(pending: rosters[2],
    schedule: keySchedule(newSeq[StateBsKey](12))), policy(cores))
  assert pending.error == StateComponentError.None
  var entries = @[pending.value, chapter(rosters[1], ValidatorChapter.Active),
    StateEntry(key: chapterKey(StateChapter(11)), value: @[7'u8, 0, 0, 0]),
    StateEntry(key: chapterKey(StateChapter(7)), value: @[255'u8])] # Invalid staging must not be used as next.
  if suffix: entries[0].value.add(0) # C(4) remains structurally prefix-decodable, but projection must reject it.
  if not omit: entries.add(chapter(rosters[0], ValidatorChapter.Previous))
  var wire = newSeq[byte](297)
  wire[96] = 7
  captureBlockSnapshot(wire, entries, settings(cores))
proc same(left, right: StateEdKey): bool =
  ## Independent test identity comparison.
  array[32, byte](left) == array[32, byte](right)
proc oracle(rosters: array[3, seq[StateValidator]], left, right: StateEdKey): bool =
  ## Deliberately quadratic reference uses literal widths for these independently sized grids.
  if same(left, right) or same(left, nullValidator().ed25519) or same(right, nullValidator().ed25519): return false
  let widths = [2, 3, 3]
  for a in 0..<3:
    for i, first in rosters[a]:
      if same(first.ed25519, left):
        for b in 0..<3:
          for j, second in rosters[b]:
            if same(second.ed25519, right):
              if a != b and i == j: return true # Cross-epoch relation is ordinal equality.
              if a == b and (i div widths[a] == j div widths[a] or i mod widths[a] == j mod widths[
                  a]): return true
  false

var rosters = [records(0, 6), records(1, 9), records(2, 12)]
rosters[0][4] = nullValidator()
rosters[2][10].ed25519 = rosters[0][1].ed25519 # A repeated identity retains both distinct positions.
rosters[1][7].ed25519 = rosters[1][0].ed25519 # Preserve duplicates within one epoch too.
rosters[1][2].metadata = default(StateValidatorMetadata) # Unavailable route does not erase membership.
let source = captured(rosters)
assert source.error == GenesisError.None
let projected = captureValidatorTopology(source, policy())
assert projected.error == TopologyError.None
let owner = projected.value
assert owner.ready and owner.slot == 7 and owner.epochSlots == 12
assert array[32, byte](owner.sourceBlock) == array[32, byte](source.value.blockHash)
for epoch in low(ValidatorEpoch)..high(ValidatorEpoch):
  assert owner.population(epoch) == rosters[ord(epoch)].len
  for index, record in rosters[ord(epoch)]:
    let member = owner.membershipAt(epoch, StateValidatorIndex(uint64(index)))
    assert member.error == TopologyError.None and same(member.value.identity, record.ed25519)
    assert owner.contains(record.ed25519) == not same(record.ed25519, nullValidator().ed25519)
    for other in rosters:
      for second in other:
        assert owner.neighbours(record.ed25519, second.ed25519) == oracle(rosters, record.ed25519,
            second.ed25519)
assert owner.membershipAt(ValidatorEpoch.Current, StateValidatorIndex(2)).value.endpoint.error ==
    EndpointError.Unavailable
assert owner.membershipAt(ValidatorEpoch.Next, StateValidatorIndex(0)).value.endpoint.error ==
    EndpointError.None
assert not owner.contains(key(999)) and not owner.neighbours(key(999), key(20))
assert owner.membershipAt(ValidatorEpoch.Current, StateValidatorIndex(high(uint64))).error ==
    TopologyError.InvalidIndex
assert default(ValidatorTopology).membershipAt(ValidatorEpoch.Current, StateValidatorIndex(
    0)).error == TopologyError.Uninitialized
assert not default(ValidatorTopology).contains(key(20))
assert captureValidatorTopology(unavailableGenesis(), policy()).error ==
    TopologyError.Uninitialized
assert captureValidatorTopology(captured(rosters, omit = true), policy()).error ==
    TopologyError.MissingState
assert captureValidatorTopology(captured(rosters, suffix = true), policy()).error ==
    TopologyError.InvalidState
var limited = policy()
limited.maxBytes = ByteLimit(1)
assert captureValidatorTopology(source, limited).error == TopologyError.LimitExceeded
var mismatch = policy()
mismatch.epochSlots = EpochSlots(13)
assert captureValidatorTopology(source, mismatch).error == TopologyError.InvalidConfig
rosters[2][0].ed25519 = key(999) # Caller-owned fixture mutation cannot alter captured storage.
assert not owner.contains(key(999))
# The maximum pinned roster reaches the last scratch-mask position and a non-square final row.
let maximum = [records(0, 6), records(1, 9), records(2, 1023)]
let large = captureValidatorTopology(captured(maximum, cores = 341), policy(341))
assert large.error == TopologyError.None
assert large.value.population(ValidatorEpoch.Next) == 1023
assert large.value.membershipAt(ValidatorEpoch.Next, StateValidatorIndex(1022)).error ==
    TopologyError.None
assert large.value.neighbours(key(1122), key(1091)) # Same column at width31.
assert not large.value.neighbours(key(1122), key(1090)) # Different row/column, unique to next.
echo "jamnp topology: unequal rosters, aliases, nulls, exact chapters and grid oracle passed"
