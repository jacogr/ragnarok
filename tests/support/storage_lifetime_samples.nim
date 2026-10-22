# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated lifetime controls retire prepared fixtures before measuring retained repository objects.
import std/assertions
import ./[storage_growth_samples, storage_allocations]
import ../../src/storage/node_records
import ../../src/codec/state_layout

type LifetimeObservation* = object
  ## Only scalar counters escape; no graph, fixture or extracted value can survive accidentally.
  baseline*, fixture*, owner*, held*, closed*, released*, checks*: int

proc emptyLifetime*(): LifetimeObservation =
  ## Missing ownership stages stay explicit instead of acquiring invented zero-byte observations.
  result = LifetimeObservation(baseline: occupiedStorageBytes(), fixture: -1, owner: -1,
    held: -1, closed: -1, released: -1, checks: 0)

proc fixtureScope(count: int): tuple[occupied, checks: int] =
  ## Count every prepared root identity and final read address while the fixture remains owned here.
  let fixture = prepareGrowth(count, 64)
  assert fixture.changes.len == 64 and fixture.roots.len == 65 and fixture.reads.len == count
  for index, change in fixture.changes:
    # Prepared root continuity is checked independently of any backend publication.
    assert array[32, byte](change.root) == array[32, byte](fixture.roots[index+1])
  result = (occupied: occupiedStorageBytes(), checks: count+64)

proc fixtureLifetime*(count: int): LifetimeObservation =
  ## Scope exit releases every prepared graph; allocator equality proves actual fixture retirement.
  result = emptyLifetime()
  let observed = fixtureScope(count)
  result.fixture = observed.occupied
  result.checks = observed.checks
  result.released = occupiedStorageBytes()
  assert result.fixture > result.baseline and result.released == result.baseline
