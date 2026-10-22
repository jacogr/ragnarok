# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Indexed admission preserves every full physical address, empty prefix interval and held revision.
import std/[assertions, syncio]
import ../../support/storage_growth_samples
import ../../../src/storage/[node_repository, node_records, full_state_trie]
import ../../../src/codec/[state_layout, state_trie]

proc checkRecords(view: RepositoryView, records: openArray[TrieRecord]) =
  ## Exact independently prepared records detect prefix-only equality or a range belonging to another owner.
  for expected in records:
    let observed = view.lookupNode(expected.digest).value
    assert array[32, byte](observed.digest) == array[32, byte](expected.digest)
    assert observed.kind == expected.kind and observed.payload == expected.payload
    assert array[31, byte](observed.key) == array[31, byte](expected.key)
    assert array[32, byte](observed.left) == array[32, byte](expected.left)
    assert array[32, byte](observed.right) == array[32, byte](expected.right)
let fixture = prepareGrowth(1024, 64)
var repository = newNodeRepository(growthLimits())
for prefix in 0..255:
  # Every first-byte interval is empty in a newly initialized repository, including both endpoints.
  var raw = default(array[32, byte])
  raw[0] = byte(prefix)
  assert repository.snapshot.value.lookupNode(StateNodeHash(raw)).error ==
      RepositoryError.MissingNode
discard repository.publish(repository.snapshot.value, fixture.seed).value
let held = repository.snapshot.value
checkRecords(held, fixture.seed.records)
for prefix in 0..255:
  # A same-prefix miss must compare the complete address; the independent seed inventory decides absence.
  var raw = default(array[32, byte])
  raw[0] = byte(prefix)
  var present = false
  for record in fixture.seed.records:
    if array[32, byte](record.digest) == raw: present = true
  if not present:
    assert held.lookupNode(StateNodeHash(raw)).error == RepositoryError.MissingNode
for change in fixture.changes:
  # Successors retain prior cells while their own sorted search intervals change independently.
  discard repository.publish(repository.snapshot.value, change).value
  checkRecords(repository.snapshot.value, change.records)
checkGrowthHead(repository.snapshot.value, fixture.roots[64], 1024, 64)
assert repository.close == RepositoryError.None
checkRecords(held, fixture.seed.records)
checkGrowthHead(held, fixture.roots[0], 1024, 0)
echo "PASS storage prefix directory"
