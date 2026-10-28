# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent full-paged test byte/tree oracle and resident callback fault controls.
import std/assertions
import std/algorithm
import ../../src/storage/full_paged_codec as storage_full_paged_codec
import ../../src/storage/full_paged_stream as storage_full_paged_stream
import ../../src/storage/paged_codec as storage_paged_codec
import ../../src/storage/paged_stream as storage_paged_stream
import ../../src/storage/node_records as storage_node_records
import ../../src/storage/node_repository as storage_node_repository
import ../../src/storage/managed_manifest as storage_managed_manifest
import ../../src/storage/database_identity as storage_database_identity
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_trie as codec_state_trie
import ../../src/crypto/primitives as crypto_primitives

type
  FullPagedTestIO* = ref object ## Resident byte transport is a test oracle only; production retains no such owner.
    bytes*: seq[byte]
    calls*, failAt*: int
    growAt*: int
  FullPagedFixture* = object ## Test fixture retains bytes/records only outside production callback lifetimes.
    io*: FullPagedTestIO
    header*: FullPagedHeader
    manifest*: FullPagedManifest
    records*: seq[TrieRecord]
proc clone*(input: seq[byte]): seq[byte] =
  ## Detach mutable forensic fixtures before each corruption/fault injection.
  result = newSeq[byte](input.len)
  for index in 0..<input.len: result[index] = input[index] # Independent owned bytes.
func key*(first: byte): StateKey =
  ## FullPagedFixture routing differs in the first serialized MSB, leaving the remaining 240 bits zero.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)
proc leaf*(first: byte, value: seq[byte]): TrieRecord =
  ## Expected physical addresses use the independent pinned JAM node primitives.
  let encoded = encodeStateLeaf(key(first), value, ByteLimit(10000))
  assert encoded.error == StateLayoutError.None
  let digest = hashStateNode(encoded.value)
  assert digest.error == StateLayoutError.None
  TrieRecord(kind: TrieRecordKind.Leaf, digest: digest.value, key: key(first), payload: value)
proc branch*(left, right: TrieRecord): TrieRecord =
  ## Full physical edges are independently hashed to form valid, possibly topologically invalid, roots.
  let digest = hashStateNode(encodeStateBranch(left.digest, right.digest))
  assert digest.error == StateLayoutError.None
  TrieRecord(kind: TrieRecordKind.Branch, digest: digest.value, left: left.digest,
      right: right.digest)
func policy*(cache = 1): FullPagedStreamLimits =
  ## Generous finite quotas support exact-count replays without unlimited sentinel values.
  FullPagedStreamLimits(dataset: PagedLimits(entries: ElementLimit(1000), bytes: ByteLimit(
      1000000)),
    trie: StateTrieLimits(items: ElementLimit(1000), nodes: TrieNodeLimit(1000),
      perValue: ByteLimit(10000), totalValueBytes: ByteLimit(100000)),
    roots: ElementLimit(64), cachePages: ElementLimit(cache), workingBytes: ByteLimit(5000000),
    scratchBytes: ByteLimit(2000), work: FullPagedWorkLimits(ioCalls: ElementLimit(1000000),
      hashes: ElementLimit(1000000), visits: ElementLimit(10000), readBytes: ByteLimit(100000000),
      writeBytes: ByteLimit(1000000)))
proc input*(io: FullPagedTestIO): PagedInput =
  ## Synchronous callbacks neither retain output buffers nor let real failures look like short success.
  proc read(offset: PagedOffset, output: var openArray[byte]): bool {.closure.} =
    ## A failed exact read may not grant any prefix authority.
    inc io.calls
    if io.calls == io.failAt: return false
    let start = uint64(offset)
    if start > uint64(io.bytes.len) or uint64(output.len) > uint64(io.bytes.len)-start: return false
    for index in 0..<output.len: output[index] = io.bytes[int(start)+index] # Bounded copy.
    true
  proc extent(output: var uint64): bool {.closure.} =
    ## Late actual EOF change must defeat a completed graph or absence lookup.
    inc io.calls
    if io.calls == io.failAt: return false
    if io.calls == io.growAt: io.bytes.add(0)
    output = uint64(io.bytes.len)
    true
  PagedInput(read: read, extent: extent)
proc scratch*(io: FullPagedTestIO): FullPagedScratch =
  ## Private test scratch permits byte-addressed flags without sharing source storage.
  proc write(offset: PagedOffset, bytes: openArray[byte]): bool {.closure.} =
    ## Every actual write participates in deterministic refusal injection.
    inc io.calls
    if io.calls == io.failAt: return false
    let start = uint64(offset)
    if start > uint64(io.bytes.len) or uint64(bytes.len) > uint64(io.bytes.len)-start: return false
    for index in 0..<bytes.len: io.bytes[int(start)+index] = bytes[index] # Exact bounded replacement.
    true
  FullPagedScratch(input: io.input, write: write)
proc little*(value: uint64): seq[byte] =
  ## Independent reference scalar encoding is not a call to the production full codec.
  result = newSeq[byte](8)
  for index in 0..<8: result[index] = byte((value shr (index*8)) and 255) # Canonical LE.
proc append*(output: var seq[byte], input: openArray[byte]) =
  ## Test-only materialization intentionally keeps a complete oracle artifact outside production code.
  for octet in input: output.add(octet) # Exact reference concatenation.
proc domain*(name: string): seq[byte] =
  ## Reference labels are explicit normative bytes, including their terminating newline.
  result = @[]
  for character in name: result.add(byte(character)) # ASCII-only fixture label.
proc digest*(input: seq[byte]): array[32, byte] =
  ## Independent primitive invocation verifies the production full-format hash schedule.
  let outcome = blake2b256(input)
  assert outcome.error == CryptoError.None
  array[32, byte](outcome.value)
proc tree*(bytes: var seq[byte], pages, start, width: int): array[32, byte] =
  ## Independent resident oracle emits the canonical postorder tree for real/padding leaves.
  if width == 1:
    # Actual full pages and nonphysical padding leaves have distinct explicit domains.
    var body = domain(if start < pages: "RAGNAROK-FULL-PAGED-LEAF-V1\n" else:
      "RAGNAROK-FULL-PAGED-PAD-V1\n")
    body.append(little(uint64(start)))
    if start < pages: body.append(bytes.toOpenArray(start*4096, (start+1)*4096-1))
    result = digest(body)
  else:
    # Recursion is a test oracle, not the bounded production traversal or its digest helpers.
    let left = tree(bytes, pages, start, width div 2)
    let right = tree(bytes, pages, start+width div 2, width div 2)
    var body = domain("RAGNAROK-FULL-PAGED-NODE-V1\n")
    body.append(left)
    body.append(right)
    result = digest(body)
  bytes.append(result)
proc fixture*(records: seq[TrieRecord], selected: TrieRecord, roots: seq[FullPagedRoot],
    epoch = ManagedEpoch(1), generation = RepositoryGeneration(0)): FullPagedFixture =
  ## Canonical record ordering plus independent tree construction can seal hostile but locally valid graphs.
  var sorted = records
  sorted.sort(proc(a, b: TrieRecord): int = compareFullHash(array[32, byte](a.digest),
    array[32, byte](b.digest)))
  var claims = roots
  claims.sort(proc(a, b: FullPagedRoot): int = compareFullHash(array[32, byte](a.root),
    array[32, byte](b.root)))
  var payload = 0'u64
  for record in sorted: payload += uint64(encodeFullPagedRecord(record, ByteLimit(
      10000)).value.len) # Test extent.
  let made = initFullPagedHeader(default(StorageChainId), StateRoot(array[32, byte](
      selected.digest)),
    epoch, generation, uint64(sorted.len), payload, claims, policy().dataset)
  assert made.error == FullPagedError.None
  let header = made.value
  var bytes: seq[byte] = @[]
  bytes.append(header.bytes)
  var offset = 0'u64
  for record in sorted:
    # Fixed index rows are byte-oracle checked by the preceding codec suite.
    let size = uint64(encodeFullPagedRecord(record, ByteLimit(10000)).value.len)
    bytes.append(initFullPagedRow(header.geometry, record.digest, offset, size).value.bytes)
    offset += size
  while bytes.len < int(uint64(header.geometry.payloadOffset)): bytes.add(0) # Canonical index padding.
  for record in sorted: bytes.append(encodeFullPagedRecord(record, ByteLimit(10000)).value) # Canonical records.
  while bytes.len < int(uint64(header.geometry.treeOffset)): bytes.add(0) # Canonical payload padding.
  let root = tree(bytes, int(header.geometry.dataPages), 0, int(header.geometry.treeLeaves))
  assert uint64(bytes.len) == header.geometry.byteLength
  FullPagedFixture(io: FullPagedTestIO(bytes: bytes), header: header,
    manifest: encodeFullPagedManifest(header, FullPagedDigest(root)).value, records: sorted)
proc claim*(record: TrieRecord, entries, nodes, values: uint64): FullPagedRoot =
  ## Claims are detached untrusted totals; production must recompute each field.
  FullPagedRoot(root: StateRoot(array[32, byte](record.digest)), entries: entries,
    nodes: nodes, valueBytes: values)
proc check*(fixture: FullPagedFixture, limits: FullPagedStreamLimits): FullPagedStreamResult[
    CheckedFullPagedArtifact] =
  ## Fresh dirty scratch proves admission explicitly initializes both membership tables.
  let scratch = FullPagedTestIO(bytes: newSeq[byte](fixture.records.len*2))
  for index in 0..<scratch.bytes.len: scratch.bytes[index] = 255 # Existing scratch grants no visited authority.
  validateFullPaged(fixture.io.input, scratch.scratch, fixture.header, fixture.manifest, limits)
