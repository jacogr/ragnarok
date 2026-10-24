# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently resealed complete physical graphs distinguish graph authority from page/record integrity.
# @@Verification={"arc":"storage_full_paged_graph_arc_release"}
import std/[assertions, syncio, algorithm]
import ../../support/arc_evidence
import ../../../src/storage/[full_paged_codec, full_paged_stream, paged_codec, paged_stream,
  node_records, node_repository, managed_manifest, database_identity]
import ../../../src/codec/[bounded, state_layout, state_trie]
import ../../../src/crypto/primitives

type
  IO = ref object ## Resident byte transport is a test oracle only; production retains no such owner.
    bytes: seq[byte]
    calls, failAt: int
    growAt: int
  Fixture = object ## Test fixture retains bytes/records only outside production callback lifetimes.
    io: IO
    header: FullPagedHeader
    manifest: FullPagedManifest
    records: seq[TrieRecord]
proc clone(input: seq[byte]): seq[byte] =
  ## Detach mutable forensic fixtures before each corruption/fault injection.
  result = newSeq[byte](input.len)
  for index in 0..<input.len: result[index] = input[index] # Independent owned bytes.
func key(first: byte): StateKey =
  ## Fixture routing differs in the first serialized MSB, leaving the remaining 240 bits zero.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)
proc leaf(first: byte, value: seq[byte]): TrieRecord =
  ## Expected physical addresses use the independent pinned JAM node primitives.
  let encoded = encodeStateLeaf(key(first), value, ByteLimit(10000))
  assert encoded.error == StateLayoutError.None
  let digest = hashStateNode(encoded.value)
  assert digest.error == StateLayoutError.None
  TrieRecord(kind: TrieRecordKind.Leaf, digest: digest.value, key: key(first), payload: value)
proc branch(left, right: TrieRecord): TrieRecord =
  ## Full physical edges are independently hashed to form valid, possibly topologically invalid, roots.
  let digest = hashStateNode(encodeStateBranch(left.digest, right.digest))
  assert digest.error == StateLayoutError.None
  TrieRecord(kind: TrieRecordKind.Branch, digest: digest.value, left: left.digest,
      right: right.digest)
func policy(cache = 1): FullPagedStreamLimits =
  ## Generous finite quotas support exact-count replays without unlimited sentinel values.
  FullPagedStreamLimits(dataset: PagedLimits(entries: ElementLimit(1000), bytes: ByteLimit(
      1000000)),
    trie: StateTrieLimits(items: ElementLimit(1000), nodes: TrieNodeLimit(1000),
      perValue: ByteLimit(10000), totalValueBytes: ByteLimit(100000)),
    roots: ElementLimit(64), cachePages: ElementLimit(cache), workingBytes: ByteLimit(5000000),
    scratchBytes: ByteLimit(2000), work: FullPagedWorkLimits(ioCalls: ElementLimit(1000000),
      hashes: ElementLimit(1000000), visits: ElementLimit(10000), readBytes: ByteLimit(100000000),
      writeBytes: ByteLimit(1000000)))
proc input(io: IO): PagedInput =
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
proc scratch(io: IO): FullPagedScratch =
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
proc little(value: uint64): seq[byte] =
  ## Independent reference scalar encoding is not a call to the production full codec.
  result = newSeq[byte](8)
  for index in 0..<8: result[index] = byte((value shr (index*8)) and 255) # Canonical LE.
proc append(output: var seq[byte], input: openArray[byte]) =
  ## Test-only materialization intentionally keeps a complete oracle artifact outside production code.
  for octet in input: output.add(octet) # Exact reference concatenation.
proc domain(name: string): seq[byte] =
  ## Reference labels are explicit normative bytes, including their terminating newline.
  result = @[]
  for character in name: result.add(byte(character)) # ASCII-only fixture label.
proc digest(input: seq[byte]): array[32, byte] =
  ## Independent primitive invocation verifies the production full-format hash schedule.
  let outcome = blake2b256(input)
  assert outcome.error == CryptoError.None
  array[32, byte](outcome.value)
proc tree(bytes: var seq[byte], pages, start, width: int): array[32, byte] =
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
proc fixture(records: seq[TrieRecord], selected: TrieRecord, roots: seq[FullPagedRoot]): Fixture =
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
    ManagedEpoch(1), RepositoryGeneration(0), uint64(sorted.len), payload, claims, policy().dataset)
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
  Fixture(io: IO(bytes: bytes), header: header,
    manifest: encodeFullPagedManifest(header, FullPagedDigest(root)).value, records: sorted)
proc claim(record: TrieRecord, entries, nodes, values: uint64): FullPagedRoot =
  ## Claims are detached untrusted totals; production must recompute each field.
  FullPagedRoot(root: StateRoot(array[32, byte](record.digest)), entries: entries,
    nodes: nodes, valueBytes: values)
proc check(fixture: Fixture, limits: FullPagedStreamLimits): FullPagedStreamResult[
    CheckedFullPagedArtifact] =
  ## Fresh dirty scratch proves admission explicitly initializes both membership tables.
  let scratch = IO(bytes: newSeq[byte](fixture.records.len*2))
  for index in 0..<scratch.bytes.len: scratch.bytes[index] = 255 # Existing scratch grants no visited authority.
  validateFullPaged(fixture.io.input, scratch.scratch, fixture.header, fixture.manifest, limits)
let left = leaf(0, @[1'u8, 2, 3])
let right = leaf(128, @[])
let parent = branch(left, right)
let ordinary = fixture(@[left, right, parent], parent, @[claim(parent, 2, 3, 3)])

block positive:
  # Both page policies establish complete-root authority and distinguish empty presence from absence.
  for cache in 0..1:
    let admitted = ordinary.check(policy(cache))
    assert admitted.error == FullPagedStreamError.None
    let checked = admitted.value
    let root = StateRoot(array[32, byte](parent.digest))
    let found = lookupFullPaged(ordinary.io.input, checked, root, key(0))
    assert found.error == FullPagedStreamError.None and found.value.present
    assert found.value.bytes == @[1'u8, 2, 3]
    let empty = lookupFullPaged(ordinary.io.input, checked, root, key(128))
    assert empty.error == FullPagedStreamError.None and empty.value.present and
        empty.value.bytes.len == 0
    let absent = lookupFullPaged(ordinary.io.input, checked, root, key(64))
    assert absent.error == FullPagedStreamError.None and not absent.value.present
    assert lookupFullPaged(ordinary.io.input, checked, StateRoot(default(array[32, byte])),
      key(0)).error == FullPagedStreamError.UnknownRoot
    var detached = found.value.bytes
    detached[0] = 99
    assert lookupFullPaged(ordinary.io.input, checked, root, key(0)).value.bytes[0] == 1

block emptyRoot:
  # A complete empty graph has no records, no values and a genuinely empty disk scratch extent.
  let empty = fixture(@[], default(TrieRecord), @[FullPagedRoot()])
  let admitted = empty.check(policy())
  assert admitted.error == FullPagedStreamError.None
  let absent = lookupFullPaged(empty.io.input, admitted.value, default(StateRoot), key(0))
  assert absent.error == FullPagedStreamError.None and not absent.value.present

block longValue:
  # One bounded long leaf crosses physical pages without retaining any whole-dataset record table.
  var payload = newSeq[byte](4097)
  for index in 0..<payload.len: payload[index] = byte(index mod 251)
  let record = leaf(0, payload)
  let full = fixture(@[record], record, @[claim(record, 1, 1, 4097)])
  let admitted = full.check(policy())
  assert admitted.error == FullPagedStreamError.None
  assert lookupFullPaged(full.io.input, admitted.value, full.header.root, key(0)).value.bytes == payload
  var short = policy()
  short.trie.perValue = ByteLimit(4096)
  assert full.check(short).error == FullPagedStreamError.LimitExceeded

block graphAuthority:
  # Every hostile graph below has valid record hashes and a fully rebuilt local digest tree.
  let reversed = branch(right, left)
  assert fixture(@[left, right, reversed], reversed, @[claim(reversed, 2, 3, 3)]).
    check(policy()).error == FullPagedStreamError.InvalidGraph
  let repeated = branch(left, left)
  assert fixture(@[left, repeated], repeated, @[claim(repeated, 2, 2, 6)]).
    check(policy()).error == FullPagedStreamError.InvalidGraph
  assert fixture(@[parent, right], parent, @[claim(parent, 1, 2, 0)]).
    check(policy()).error == FullPagedStreamError.MissingNode
  let extra = leaf(64, @[9'u8])
  assert fixture(@[left, right, parent, extra], parent, @[claim(parent, 2, 3, 3)]).
    check(policy()).error == FullPagedStreamError.UnreachableRecord
  assert fixture(@[left, right, parent], parent, @[claim(parent, 1, 3, 3)]).
    check(policy()).error == FullPagedStreamError.CountMismatch
  let shared = fixture(@[left, right, parent], parent, @[claim(parent, 2, 3, 3), claim(left, 1, 1, 3)])
  assert shared.check(policy()).error == FullPagedStreamError.None
  let sharedChecked = shared.check(policy()).value
  assert lookupFullPaged(shared.io.input, sharedChecked, StateRoot(array[32, byte](left.digest)),
    key(0)).value.bytes == @[1'u8, 2, 3]
  var aliasLeft = array[32, byte](left.digest)
  aliasLeft[0] = aliasLeft[0] xor 128
  var alias = parent
  alias.left = StateNodeHash(aliasLeft)
  assert fixture(@[left, right, alias], alias, @[claim(alias, 2, 3, 3)]).
    check(policy()).error == FullPagedStreamError.MissingNode

block quotas:
  # Exact observed work succeeds; lowering each independently exercised counter refuses before dispatch.
  let observed = ordinary.check(policy()).value.counts
  var exact = policy()
  exact.work.ioCalls = ElementLimit(observed.ioCalls)
  exact.work.hashes = ElementLimit(observed.hashes)
  exact.work.visits = ElementLimit(observed.visits)
  exact.work.readBytes = ByteLimit(observed.readBytes)
  exact.work.writeBytes = ByteLimit(observed.writeBytes)
  assert ordinary.check(exact).error == FullPagedStreamError.None
  for channel in 0..4:
    # Every operation channel is independently finite, including scratch reads and resets.
    var short = exact
    case channel
    of 0: short.work.ioCalls = ElementLimit(observed.ioCalls-1)
    of 1: short.work.hashes = ElementLimit(observed.hashes-1)
    of 2: short.work.visits = ElementLimit(observed.visits-1)
    of 3: short.work.readBytes = ByteLimit(observed.readBytes-1)
    else: short.work.writeBytes = ByteLimit(observed.writeBytes-1)
    assert ordinary.check(short).error == FullPagedStreamError.LimitExceeded
  var exactScratch = policy()
  exactScratch.scratchBytes = ByteLimit(ordinary.header.geometry.entries*2)
  assert ordinary.check(exactScratch).error == FullPagedStreamError.None, "exact2N scratch allowance"
  var shortScratch = policy()
  shortScratch.scratchBytes = ByteLimit(5)
  assert ordinary.check(shortScratch).error == FullPagedStreamError.LimitExceeded
  var cache = policy(2)
  assert ordinary.check(cache).error == FullPagedStreamError.UnsupportedPolicy

block ioFailures:
  # Enumerate every actual callback boundary in independent source and scratch owners.
  let source = IO(bytes: clone(ordinary.io.bytes))
  let temporary = IO(bytes: newSeq[byte](6))
  assert validateFullPaged(source.input, temporary.scratch, ordinary.header, ordinary.manifest,
    policy()).error == FullPagedStreamError.None
  let sourceCalls = source.calls
  let scratchCalls = temporary.calls
  for index in 1..sourceCalls:
    # Exact reads and pre/post EOF checks cannot fail open.
    let failed = IO(bytes: clone(ordinary.io.bytes), failAt: index)
    assert validateFullPaged(failed.input, IO(bytes: newSeq[byte](6)).scratch, ordinary.header,
      ordinary.manifest, policy()).error == FullPagedStreamError.IOFailure
  for index in 1..scratchCalls:
    # Scratch is a resource with its own real failure channel, including reset and final EOF.
    let failed = IO(bytes: newSeq[byte](6), failAt: index)
    assert validateFullPaged(IO(bytes: clone(ordinary.io.bytes)).input, failed.scratch,
      ordinary.header, ordinary.manifest, policy()).error == FullPagedStreamError.IOFailure
  let grown = IO(bytes: clone(ordinary.io.bytes), growAt: sourceCalls)
  assert validateFullPaged(grown.input, IO(bytes: newSeq[byte](6)).scratch, ordinary.header,
    ordinary.manifest, policy()).error == FullPagedStreamError.ChangedInput

block retirement:
  # Repeated complete admission and owned lookup values leave no retained graph/index or callback cycles.
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let checked = ordinary.check(policy())
    assert checked.error == FullPagedStreamError.None
    assert lookupFullPaged(ordinary.io.input, checked.value, ordinary.header.root,
      key(0)).value.bytes.len == 3
  let after = getOccupiedMem()
  assert after == before
  recordArcRelease("storage_full_paged_graph", 1000, before, after)
echo "storage full paged graph PASS"
