# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent fixed-offset metadata and physical-record witnesses exercise full paging's format boundary.
import std/[assertions, syncio]
import ../../../src/storage/full/paged/codec as full_paged_codec
import ../../../src/storage/paged/codec as paged_codec
import ../../../src/storage/database_identity
import ../../../src/storage/managed/manifest as managed_manifest
import ../../../src/storage/node/[records as node_records, repository as node_repository]
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Primitive fault injection never substitutes format or graph-validation logic.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Prove shape/policy refusal happens before cryptographic backend work.
func policy(): PagedLimits =
  ## Explicit finite dataset ceiling admits small fixtures without sentinel unlimited values.
  PagedLimits(entries: ElementLimit(10000), bytes: ByteLimit(10000000))
func identity(first: byte): array[32, byte] =
  ## Independent complete scalar fixtures differ in their first byte.
  result = default(array[32, byte])
  result[0] = first
proc put(bytes: var openArray[byte], offset: int, value: uint64) =
  ## Independent oracle writes known eight-byte fields without production encoding helpers.
  for index in 0..<8: bytes[offset+index] = byte((value shr (8*index)) and 255) # Bounded LE.
proc leaf(first: byte, payload: seq[byte]): TrieRecord =
  ## Derive independent JAM addresses directly from the pinned state-layout primitives.
  var key = default(array[31, byte])
  key[0] = first
  let encoded = encodeStateLeaf(StateKey(key), payload, ByteLimit(10000))
  assert encoded.error == StateLayoutError.None
  let hashed = hashStateNode(encoded.value)
  assert hashed.error == StateLayoutError.None
  TrieRecord(kind: TrieRecordKind.Leaf, digest: hashed.value, key: StateKey(key), payload: payload)
proc header(): FullPagedHeader =
  ## Two sorted scalar claims include empty history and a nonempty selected root.
  let made = initFullPagedHeader(StorageChainId(identity(7)), StateRoot(identity(2)),
    ManagedEpoch(1), RepositoryGeneration(0), 2, 170,
    [FullPagedRoot(root: StateRoot(default(array[32, byte]))),
      FullPagedRoot(root: StateRoot(identity(2)), entries: 1, nodes: 1, valueBytes: 1)], policy())
  assert made.error == FullPagedError.None
  made.value

block headerOracle:
  # Check every byte against an independently laid out fixed page, then mutate every reserved byte.
  let selected = header()
  let encoded = selected.bytes
  var expected = default(array[4096, byte])
  const label = "RAGNAROK-FULL-PAGED-V1\n"
  for index, character in label: expected[index] = byte(character) # Full-only schema.
  expected[32] = 7
  put(expected, 64, 1)
  expected[80] = 2
  put(expected, 112, 2)
  put(expected, 120, 170)
  put(expected, 128, 2)
  expected[200] = 2
  put(expected, 232, 1)
  put(expected, 240, 1)
  put(expected, 248, 1)
  assert encoded == expected
  let decoded = decodeFullPagedHeader(expected, selected.chainId, selected.root, policy())
  assert decoded.error == FullPagedError.None
  assert decoded.value.bytes == expected
  assert decoded.value.len == 2
  assert uint64(decoded.value.generation) == 0
  for index in 0..<expected.len:
    # Truncation at every byte must fail without accessing absent fixed fields.
    assert decodeFullPagedHeader(expected.toOpenArray(0, index-1), selected.chainId,
      selected.root, policy()).error == FullPagedError.InvalidFormat
  for index in 256..<4096:
    # Every trailing reserved octet is canonical, not just a sampled sentinel.
    var corrupt = expected
    corrupt[index] = 1
    assert decodeFullPagedHeader(corrupt, selected.chainId, selected.root,
      policy()).error == FullPagedError.InvalidFormat
  assert decodeFullPagedHeader(expected, StorageChainId(identity(8)), selected.root,
    policy()).error == FullPagedError.WrongChain
  assert decodeFullPagedHeader(expected, selected.chainId, StateRoot(identity(3)),
    policy()).error == FullPagedError.WrongRoot
  var corrupt = expected
  put(corrupt, 128, high(uint64))
  assert decodeFullPagedHeader(corrupt, selected.chainId, selected.root,
    policy()).error == FullPagedError.InvalidFormat

block inventoryAndGeometry:
  # Bounded root inventory and selected membership refuse malformed metadata independently of graph checks.
  let empty = FullPagedRoot(root: StateRoot(default(array[32, byte])))
  assert initFullPagedHeader(StorageChainId(identity(7)), empty.root, ManagedEpoch(1),
    RepositoryGeneration(0), 0, 0, [empty], policy()).error == FullPagedError.None
  assert initFullPagedHeader(StorageChainId(identity(7)), empty.root, ManagedEpoch(0),
    RepositoryGeneration(0), 0, 0, [empty], policy()).error == FullPagedError.InvalidFormat
  assert initFullPagedHeader(StorageChainId(identity(7)), empty.root, ManagedEpoch(1),
    RepositoryGeneration(0), 0, 0, [empty, empty], policy()).error == FullPagedError.InvalidFormat
  assert initFullPagedHeader(StorageChainId(identity(7)), StateRoot(identity(1)), ManagedEpoch(1),
    RepositoryGeneration(0), 0, 0, [empty], policy()).error == FullPagedError.WrongRoot
  assert fullPagedGeometry(1, 71, policy()).error == FullPagedError.InvalidFormat
  assert fullPagedGeometry(1, 72, policy()).error == FullPagedError.None
  let minimum = fullPagedGeometry(0, 0, policy()).value
  assert minimum.byteLength == 4128
  assert fullPagedGeometry(0, 0, PagedLimits(entries: ElementLimit(0),
    bytes: ByteLimit(4127))).error == FullPagedError.LimitExceeded
  assert fullPagedGeometry(high(uint64), high(uint64), policy()).error != FullPagedError.None

block indexOracle:
  # Exact complete hashes and contiguous spans are checked with fixed memory, including sticky failure.
  let shape = header().geometry
  let first = initFullPagedRow(shape, StateNodeHash(identity(1)), 0, 73).value
  let second = initFullPagedRow(shape, StateNodeHash(identity(2)), 73, 97).value
  var oracle = default(array[64, byte])
  oracle[0] = 1
  put(oracle, 40, 73)
  assert first.bytes == oracle
  var scan = initFullPagedIndexScan(shape)
  assert scan.admit(first.bytes).error == FullPagedError.None
  assert scan.admit(second.bytes).error == FullPagedError.None
  assert scan.finish == FullPagedError.None
  assert scan.admit(second.bytes).error == FullPagedError.InvalidFormat
  var duplicate = initFullPagedIndexScan(shape)
  assert duplicate.admit(first.bytes).error == FullPagedError.None
  assert duplicate.admit(first.bytes).error == FullPagedError.InvalidFormat
  assert duplicate.admit(second.bytes).error == FullPagedError.InvalidFormat
  assert duplicate.finish == FullPagedError.InvalidFormat
  var short = initFullPagedIndexScan(shape)
  assert short.admit(first.bytes).error == FullPagedError.None
  assert short.finish == FullPagedError.InvalidFormat
  var reserved = first.bytes
  reserved[63] = 1
  assert decodeFullPagedRow(reserved, shape).error == FullPagedError.InvalidFormat
  assert initFullPagedRow(shape, StateNodeHash(identity(1)), high(uint64),
    72).error == FullPagedError.InvalidFormat

block manifestAndDomains:
  # Full schema/domain separation prevents a valid light page or selection from becoming a full artifact.
  let selected = header()
  let page = selected.bytes
  let full = fullPagedLeafDigest(selected.geometry, PageOrdinal(0), page)
  let light = pagedLeafDigest(selected.geometry, PageOrdinal(0), page)
  assert full.error == FullPagedError.None and light.error == PagedCodecError.None
  assert array[32, byte](full.value) != array[32, byte](light.value)
  let manifest = encodeFullPagedManifest(selected, full.value).value
  let encoded = manifest.bytes
  assert encoded.error == FullPagedError.None
  assert decodeFullPagedManifest(encoded.value, selected).error == FullPagedError.None
  for index in 0..<FullPagedManifestBytes:
    # Every changed metadata/checksum octet refuses against the exact header binding.
    var corrupt = encoded.value
    corrupt[index] = corrupt[index] xor 1
    assert decodeFullPagedManifest(corrupt, selected).error != FullPagedError.None
  assert fullPagedLeafDigest(selected.geometry, PageOrdinal(selected.geometry.dataPages),
    page).error == FullPagedError.InvalidFormat
  assert fullPagedPaddingDigest(selected.geometry, PageOrdinal(0)).error ==
      FullPagedError.InvalidFormat
  resetHash(1)
  assert manifest.bytes.error == FullPagedError.BackendFailure
  resetHash(0)

block records:
  # Empty and long leaf records round-trip under independent exact JAM addresses and one-short value quotas.
  for payload in [newSeq[byte](0), newSeq[byte](4097)]:
    let record = leaf(0, payload)
    let encoded = encodeFullPagedRecord(record, ByteLimit(4097))
    assert encoded.error == FullPagedError.None
    assert encoded.value.len == 72+payload.len
    let decoded = decodeFullPagedRecord(encoded.value, record.digest, ByteLimit(4097))
    assert decoded.error == FullPagedError.None
    assert decoded.value.payload == payload
    for length in 0..<encoded.value.len:
      # Every proper prefix refuses; expected digest alone cannot authorize incomplete raw values.
      assert decodeFullPagedRecord(encoded.value.toOpenArray(0, length-1), record.digest,
        ByteLimit(4097)).error != FullPagedError.None
    if payload.len > 0:
      # Policy refusal is observable before any attempt to hash the over-budget value.
      resetHash(0)
      assert decodeFullPagedRecord(encoded.value, record.digest, ByteLimit(4096)).error ==
          FullPagedError.LimitExceeded
      assert hashCalls() == 0
    var changed = encoded.value
    changed[33] = changed[33] xor 1
    assert decodeFullPagedRecord(changed, record.digest, ByteLimit(4097)).error ==
        FullPagedError.HashMismatch
  let a = leaf(0, @[1'u8])
  let b = leaf(128, @[])
  let branchHash = hashStateNode(encodeStateBranch(a.digest, b.digest))
  assert branchHash.error == StateLayoutError.None
  let branch = TrieRecord(kind: TrieRecordKind.Branch, digest: branchHash.value, left: a.digest,
      right: b.digest)
  var flipped = array[32, byte](a.digest)
  flipped[0] = flipped[0] xor 128
  let alias = TrieRecord(kind: TrieRecordKind.Branch, digest: branch.digest,
    left: StateNodeHash(flipped), right: b.digest)
  let aliasBytes = encodeFullPagedRecord(alias, ByteLimit(0))
  assert aliasBytes.error == FullPagedError.None
  assert array[32, byte](decodeFullPagedRecord(aliasBytes.value, branch.digest,
    ByteLimit(0)).value.left) == flipped
  # JAM permits equal B hashes for the masked bit, but physical transport must retain the distinction.
  let encoded = encodeFullPagedRecord(branch, ByteLimit(0))
  assert encoded.error == FullPagedError.None and encoded.value.len == 97
  assert encoded.value != aliasBytes.value
  let decoded = decodeFullPagedRecord(encoded.value, branch.digest, ByteLimit(0))
  assert decoded.error == FullPagedError.None
  assert array[32, byte](decoded.value.left) == array[32, byte](a.digest)
  assert array[32, byte](decoded.value.right) == array[32, byte](b.digest)
  var spare = branch
  spare.payload = @[1'u8]
  resetHash(0)
  assert encodeFullPagedRecord(spare, ByteLimit(1)).error == FullPagedError.InvalidFormat
  assert hashCalls() == 0

echo "storage full paged codec PASS"
