# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared native full-paged fixtures preserve independent complete-map roots and finite caller-owned producers.
import std/assertions
import ./full_paged_reference
import ../../src/storage/[full_paged_codec, full_paged_stream, full_paged_build,
  full_paged_store, node_records, durability, file_errors]
import ../../src/codec/[bounded, state_layout, state_trie]

proc producer*(records: seq[TrieRecord]): FullPagedProducer =
  ## Caller-owned fixture records are retained only outside each synchronous producer operation.
  proc next(pass: int, ordinal: uint64, output: var TrieRecord): FullPagedProducerStep {.closure.} =
    ## Explicit ordinal/end handling never infers graph completeness from the producer's claims.
    if ordinal >= uint64(records.len): return FullPagedProducerStep.End
    output = records[int(ordinal)]
    FullPagedProducerStep.Item
  next
func config*(fixture: FullPagedFixture): FullPagedNativeConfig =
  ## Independent expected root and finite construction/admission policies never derive from CURRENT.
  FullPagedNativeConfig(chain: fixture.header.chainId, root: fixture.header.root, limits: policy(),
    construction: FullPagedConstructionLimits(producerCalls: ElementLimit(10000),
      ioCalls: ElementLimit(10000), hashes: ElementLimit(10000), readBytes: ByteLimit(1000000),
      writeBytes: ByteLimit(1000000)))
proc roots*(fixture: FullPagedFixture): seq[FullPagedRoot] =
  ## Test-only inventory copy supplies bounded scalar untrusted root claims.
  result = @[]
  for index in 0..<fixture.header.len: result.add(fixture.header.retainedRoot(index)) # At most64 claims.
proc seed*(writer: var FullPagedWriter, directory: string, fixture: FullPagedFixture) =
  ## Only successful file-and-directory-synchronized initialization supplies a durable baseline.
  let initialized = initializeFullPagedWriter(writer, directory, fixture.config, fixture.roots,
    fixture.records.producer, fixture.header.geometry.entries, fixture.header.geometry.payloadBytes)
  assert initialized.error == FullPagedNativeError.None
  assert initialized.value.durability == StorageDurability.FileAndDirectorySynced
  assert initialized.value.writerUsable and initialized.value.retirementError == FileError.None
proc prepare*(writer: var FullPagedWriter, candidate: var FullPagedCandidate,
    fixture: FullPagedFixture) =
  ## Normal source-bound complete replacement includes all new root-union bytes and per-root counts.
  let prepared = prepareFullPagedReplacement(writer, candidate, fixture.header.root, fixture.roots,
    fixture.records.producer, fixture.header.geometry.entries, fixture.header.geometry.payloadBytes)
  assert prepared.error == FullPagedNativeError.None
  assert prepared.value == StorageDurability.FileAndDirectorySynced
proc sample*(value: byte): FullPagedFixture =
  ## Independent complete graphs differ in one value and retain a present-empty right leaf.
  let left = leaf(0, @[value])
  let right = leaf(128, @[])
  let root = branch(left, right)
  let expected = stateTrieRoot(@[StateEntry(key: key(0), value: @[value]),
    StateEntry(key: key(128), value: @[])], policy().trie)
  assert expected.error == StateTrieError.None
  assert array[32, byte](expected.value.root) == array[32, byte](root.digest)
  fixture(@[left, right, root], root, @[claim(root, 2, 3, 1)])
