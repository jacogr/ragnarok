# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete-state roster projection checked against an independent pairwise grid oracle.

import std/[assertions, syncio]
import ../../support/jamnp_topology_fixture
import ../../../src/jamnp-s/[topology, endpoints]
import ../../../src/chain/[genesis, parameters]
import ../../../src/codec/[bounded, header, assurances]
import ../../../src/codec/state/[safrole, consensus, layout, trie]

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

var rosters = [topologyRecords(0, 6), topologyRecords(1, 9), topologyRecords(2, 12)]
rosters[0][4] = nullValidator()
rosters[2][10].ed25519 = rosters[0][1].ed25519 # A repeated identity retains both distinct positions.
rosters[1][7].ed25519 = rosters[1][0].ed25519 # Preserve duplicates within one epoch too.
rosters[1][2].metadata = default(StateValidatorMetadata) # Unavailable route does not erase membership.
let source = topologyCaptured(rosters)
assert source.error == GenesisError.None
let projected = captureValidatorTopology(source, topologyLimits())
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
assert not owner.contains(topologyKey(999)) and not owner.neighbours(topologyKey(999), topologyKey(20))
assert owner.membershipAt(ValidatorEpoch.Current, StateValidatorIndex(high(uint64))).error ==
    TopologyError.InvalidIndex
assert default(ValidatorTopology).membershipAt(ValidatorEpoch.Current, StateValidatorIndex(
    0)).error == TopologyError.Uninitialized
assert not default(ValidatorTopology).contains(topologyKey(20))
assert captureValidatorTopology(unavailableGenesis(), topologyLimits()).error ==
    TopologyError.Uninitialized
assert captureValidatorTopology(topologyCaptured(rosters, omit = true), topologyLimits()).error ==
    TopologyError.MissingState
assert captureValidatorTopology(topologyCaptured(rosters, suffix = true), topologyLimits()).error ==
    TopologyError.InvalidState
var limited = topologyLimits()
limited.maxBytes = ByteLimit(1)
assert captureValidatorTopology(source, limited).error == TopologyError.LimitExceeded
var mismatch = topologyLimits()
mismatch.epochSlots = EpochSlots(13)
assert captureValidatorTopology(source, mismatch).error == TopologyError.InvalidConfig
rosters[2][0].ed25519 = topologyKey(999) # Caller-owned fixture mutation cannot alter captured storage.
assert not owner.contains(topologyKey(999))
# The maximum pinned roster reaches the last scratch-mask position and a non-square final row.
let maximum = [topologyRecords(0, 6), topologyRecords(1, 9), topologyRecords(2, 1023)]
let large = captureValidatorTopology(topologyCaptured(maximum, cores = 341), topologyLimits(341))
assert large.error == TopologyError.None
assert large.value.population(ValidatorEpoch.Next) == 1023
assert large.value.membershipAt(ValidatorEpoch.Next, StateValidatorIndex(1022)).error ==
    TopologyError.None
assert large.value.neighbours(topologyKey(1122), topologyKey(1091)) # Same column at width31.
assert not large.value.neighbours(topologyKey(1122), topologyKey(1090)) # Different row/column, unique to next.
echo "jamnp topology: unequal rosters, aliases, nulls, exact chapters and grid oracle passed"
