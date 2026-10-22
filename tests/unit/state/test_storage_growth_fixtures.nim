# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently check sustained fixture revisions, generation256 wrap and complete retained maps.
import std/[assertions, syncio]
import ../../support/storage_growth_samples
import ../../../src/storage/[node_repository, full_state_trie]
import ../../../src/codec/state_layout

for hot in [false, true]:
  # Hot keys revisit256 identities; sweep keys advance across the full map.
  for count in [1024, 8192]:
    # Both map sizes exercise exactly the same bounded four-key updates and independently authored maps.
    for publications in [64, 256]:
      let fixture = prepareGrowth(count, publications, hot)
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
