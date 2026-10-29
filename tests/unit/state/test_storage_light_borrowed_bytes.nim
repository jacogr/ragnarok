# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable light-image borrows allocate no payload copy, while mutable extraction remains independent and scoped.
# @@Verification={"arc":"storage_light_borrowed_bytes_arc_release"}
import std/[assertions, syncio]
import ../../support/arc_evidence
import ../../../src/storage/light/[snapshot as light_snapshot, state_cache as light_state_cache]
import ../../../src/storage/[state_proof, database_identity]
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
proc key(first: byte): StateKey =
  ## Two fixed query identities retain authenticated empty-root absence in a nonempty canonical image.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)
proc image(): PreparedLightSnapshot =
  ## The independently selected empty complete root supports two negative lookups without invented partial roots.
  let policy = LightSnapshotLimits(bytes: ByteLimit(8192), cache: LightCacheLimits(
    items: ElementLimit(4), writes: ElementLimit(2)))
  prepareLightSnapshot(default(StorageChainId), default(StateRoot),
    [LightStateProof(key: key(128)), LightStateProof(key: key(0))], policy).value
proc occupied(input: openArray[byte], expected: int): int =
  ## Sample live heap inside the borrowed consumer, after validating actual dynamic image bytes.
  assert input.len == expected and input[0] == byte('R')
  getOccupiedMem()
proc copied(): seq[byte] =
  ## An owning return copies the read-only borrow before the local prepared owner retires.
  let local = image()
  local.encodedBytes
proc cycle(snapshot: PreparedLightSnapshot) =
  ## Scoped views retain no extra allocation; independent mutable sequences never alter encoded bytes or cache readers.
  let expected = snapshot.byteLength
  let before = getOccupiedMem()
  let during = occupied(snapshot.encodedBytes, expected)
  assert during == before
  let retained = snapshot.cache
  var independent = snapshot.encodedBytes
  assert independent.len == expected
  independent[0] = 0
  assert snapshot.encodedBytes[0] == byte('R')
  var detached = snapshot.bytes
  detached[1] = 0
  assert snapshot.encodedBytes[1] == byte('A')
  assert retained.len == 2 and retained.lookup(key(0)).value.kind == StateLookupKind.Absent
  assert retained.lookup(key(128)).value.kind == StateLookupKind.Absent
  let edited = snapshot.forget([key(128)]).value
  assert edited.cache.len == 1 and snapshot.cache.len == 2
  assert snapshot.encodedBytes.len == expected and edited.encodedBytes.len < expected
proc main() =
  ## Exact retirement covers copied extraction, immutable views, retained readers and image edits across1,000 cycles.
  let snapshot = image()
  assert snapshot.byteLength == 210
  var owned = copied()
  assert owned.len == 210 and owned[0] == byte('R')
  owned[0] = 0
  assert snapshot.encodedBytes[0] == byte('R')
  for iteration in 0..<10: cycle(snapshot)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(snapshot)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_light_borrowed_bytes", 1000, before, after)
main()
echo "PASS storage light borrowed bytes: allocation-free views, independent extraction and owner-scoped lifetimes"
