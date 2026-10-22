# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated lifetime controls retire prepared fixtures before measuring retained repository objects.
import std/assertions
import ./[storage_growth_samples, storage_allocations]
import ../../src/storage/[node_records, node_repository]
import ../../src/codec/[state_layout, state_trie]

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

proc isolatedMemoryOwner*(count: int): NodeRepository =
  ## Return one ordinary repository; prepared changes and expected-read fixtures retire on return.
  let fixture = prepareGrowth(count, 64)
  result = newNodeRepository(growthLimits())
  discard result.publish(result.snapshot.value, fixture.seed).value
  for change in fixture.changes:
    # Each authored delta still enters the public complete-graph admission path.
    discard result.publish(result.snapshot.value, change).value

proc checkLifetimeOwner*(owner: NodeRepository, count: int): int =
  ## Validation views retire in this scope before the caller measures an explicit owner close.
  let view = owner.snapshot.value
  checkGrowthHead(view, view.commitment.root, count, 64)
  result = count

proc memoryOwnerLifetime*(count: int): LifetimeObservation =
  ## Observe the owner after fixture retirement and prove full allocator release on ordinary close.
  result = emptyLifetime()
  block:
    var owner = isolatedMemoryOwner(count)
    result.owner = occupiedStorageBytes()
    result.checks = checkLifetimeOwner(owner, count)
    assert owner.close == RepositoryError.None
    result.closed = occupiedStorageBytes()
  result.released = occupiedStorageBytes()
  assert result.owner > result.baseline, "owner not live"
  assert result.closed == result.baseline, "owner close baseline=" & $result.baseline & " closed=" &
      $result.closed & " released=" & $result.released
  assert result.released == result.baseline

proc memoryReaderLifetime*(count: int): LifetimeObservation =
  ## One immutable view keeps the exact complete map alive after its mutable owner closes.
  result = emptyLifetime()
  block:
    var owner = isolatedMemoryOwner(count)
    result.owner = occupiedStorageBytes()
    let held = owner.snapshot.value
    result.held = occupiedStorageBytes()
    checkGrowthHead(held, held.commitment.root, count, 64)
    assert owner.close == RepositoryError.None
    result.closed = occupiedStorageBytes()
    checkGrowthHead(held, held.commitment.root, count, 64)
    result.checks = count*2
    assert result.held >= result.owner and result.closed == result.held
  result.released = occupiedStorageBytes()
  assert result.closed > result.baseline and result.released == result.baseline

proc memoryReadersLifetime*(count: int): LifetimeObservation =
  ## A bounded handle vector shares one immutable graph while retaining each handle independently.
  result = emptyLifetime()
  block:
    var owner = isolatedMemoryOwner(count)
    result.owner = occupiedStorageBytes()
    var held = newSeq[RepositoryView](4096)
    for index in 0..<held.len:
      # Each public snapshot acquisition retains its own owner-bound immutable handle.
      held[index] = owner.snapshot.value
    result.held = occupiedStorageBytes()
    assert owner.close == RepositoryError.None
    result.closed = occupiedStorageBytes()
    let root = held[0].commitment.root
    checkGrowthHead(held[0], root, count, 64)
    for view in held:
      # Root and generation checks ensure every acquired handle survived actual owner retirement.
      assert array[32, byte](view.commitment.root) == array[32, byte](root)
      assert uint64(view.generation) == 65
    result.checks = count+4096
    assert result.held > result.owner and result.closed == result.held
  result.released = occupiedStorageBytes()
  assert result.released == result.baseline

proc ownedLifetimeEntries(owner: NodeRepository): seq[StateEntry] =
  ## Retire temporary validation views before returning independently owned extracted entries.
  let view = owner.snapshot.value
  result = restoreStateEntries(view, view.commitment.root, growthLimits().codec.trie).value

proc memoryExtractionLifetime*(count: int): LifetimeObservation =
  ## Extracted values remain complete after source close without retaining its physical repository graph.
  result = emptyLifetime()
  block:
    var owner = isolatedMemoryOwner(count)
    result.owner = occupiedStorageBytes()
    let entries = ownedLifetimeEntries(owner)
    result.held = occupiedStorageBytes()
    assert owner.close == RepositoryError.None
    result.closed = occupiedStorageBytes()
    checkGrowthEntries(entries, count, 64)
    result.checks = count
    assert result.held > result.owner
    assert result.closed > result.baseline and result.closed < result.held
  result.released = occupiedStorageBytes()
  assert result.released == result.baseline
