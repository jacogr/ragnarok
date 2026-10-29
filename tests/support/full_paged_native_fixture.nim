# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared native full-paged fixtures preserve independent complete-map roots and finite caller-owned producers.
import std/[assertions, syncio]
import ./full_paged_reference
import ../../src/storage/full/paged/[codec as full_paged_codec, stream as full_paged_stream,
    build as full_paged_build, store as full_paged_store]
import ../../src/storage/paged/io as paged_io
import ../../src/storage/managed/manifest as managed_manifest
import ../../src/storage/node/[repository as node_repository, records as node_records]
import ../../src/storage/durability
import ../../src/storage/file/errors as file_errors
import ../../src/codec/bounded
import ../../src/codec/state/[layout as state_layout, trie as state_trie]

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
    replayBytes: ByteLimit(1000000),
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

proc historySample*(prior, next: byte): FullPagedFixture =
  ## Two independently cross-checked complete maps share the unchanged right leaf in an exact retained union.
  assert prior != next
  let before = sample(prior)
  let after = sample(next)
  let a = leaf(0, @[prior])
  let b = leaf(0, @[next])
  let right = leaf(128, @[])
  let oldRoot = branch(a, right)
  let newRoot = branch(b, right)
  assert array[32, byte](before.header.root) == array[32, byte](oldRoot.digest)
  assert array[32, byte](after.header.root) == array[32, byte](newRoot.digest)
  fixture(@[a, b, right, oldRoot, newRoot], newRoot,
    @[claim(oldRoot, 2, 3, 1), claim(newRoot, 2, 3, 1)])
proc reposition*(source: FullPagedFixture, epoch: ManagedEpoch,
    generation: RepositoryGeneration): FullPagedFixture =
  ## Independent oracle changes only scalar physical position before rebuilding the complete local tree.
  var selected = default(TrieRecord)
  var found = false
  for record in source.records:
    # Sorted fixture inventory contains the selected complete physical root exactly once.
    if array[32, byte](record.digest) == array[32, byte](source.header.root):
      selected = record
      found = true
  assert found
  fixture(source.records, selected, source.roots, epoch, generation)
proc seedOracle*(directory: string, source: FullPagedFixture) =
  ## Real locked namespace plus independent oracle bytes supports exact-counter fixtures without claiming a publication receipt.
  var owner = default(PagedDirectory)
  assert openDirectory(owner, directory, true, true) == FileError.None
  assert owner.close == FileError.None
  var body = newString(source.io.bytes.len)
  for index in 0..<body.len: body[index] = char(source.io.bytes[index]) # Complete reference bytes.
  let raw = source.manifest.bytes.value
  var selected = newString(raw.len)
  for index in 0..<raw.len: selected[index] = char(raw[index]) # Exact fixed-width CURRENT.
  try:
    writeFile(directory & "/" & epochName(source.header.epoch).value, body)
    writeFile(directory & "/CURRENT", selected)
  except:
    assert false, "full paged oracle write failed"
