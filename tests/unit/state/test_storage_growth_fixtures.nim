# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently check sustained fixture revisions, generation256 wrap and complete retained maps.
import std/[assertions, syncio]
import ../../support/storage_growth_samples
import ../../../src/storage/node/repository as node_repository
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/codec/state/layout as state_layout

for hot in [false, true]:
  # Hot keys revisit256 identities; sweep keys advance across the full map.
  for count in [1024, 8192, 32768]:
    if hot and count == 32768:
      continue # The largest benchmark uses only the explicitly bounded sweep trajectories.
    # Both map sizes exercise exactly the same bounded four-key updates and independently authored maps.
    for publications in [64, 256]:
      let fixture = prepareGrowth(count, publications, hot)
      assert fixture.reads.len == count
      assert fixture.changes.len == publications and fixture.roots.len == publications+1
      var owner = newNodeRepository(growthLimits())
      discard owner.publish(owner.snapshot.value, fixture.seed).value
      let seed = owner.snapshot.value
      for change in fixture.changes:
        discard owner.publish(owner.snapshot.value, change).value
      let view = owner.snapshot.value
      assert uint64(view.generation) == uint64(publications+1)
      assert array[32, byte](view.commitment.root) == array[32, byte](fixture.roots[publications])
      checkGrowth(view, fixture.roots[0], count, 0, hot)
      checkGrowth(view, fixture.roots[publications], count, publications, hot)
      assert owner.close == RepositoryError.None
      checkGrowth(seed, fixture.roots[0], count, 0,
          hot) # Retained seed ownership survives later writes and close.
assert growthValue(0, 0) != growthValue(0, 256)
assert growthRevision(1023, 1024, 256) == 256
assert growthRevision(1024, 8192, 256) == 0
assert growthRevision(0, 1024, 256, true) == 193
assert growthRevision(256, 1024, 256, true) == 0
echo "PASS storage growth fixtures"
