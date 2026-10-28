# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent fixed-format witnesses, malformed input, postorder schedules and bounded scalar ownership.
# @@Verification={"arc":"storage_paged_codec_arc_release"}
import std/assertions
import std/syncio
import ../../support/testing_arc_evidence
import ../../../src/storage/paged_codec as storage_paged_codec
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/light_delta as storage_light_delta
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Maintained observer makes provider refusal and structural preflight independently observable.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Fail at each hash boundary after a known number of successful primitive calls.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count primitive invocations without replacing production codec logic.
proc hex(input: string): seq[byte] =
  ## Decode independent hexadecimal literals without production serialization helpers.
  result = newSeq[byte](input.len div 2)
  for index in 0..<result.len:
    var value = 0
    for half in 0..<2:
      # Only fixed lowercase hexadecimal literals enter this test helper.
      let c = input[index*2+half]
      let digit = if c <= '9': ord(c)-ord('0') else: ord(c)-ord('a')+10
      assert digit >= 0 and digit < 16
      value = value*16+digit
    result[index] = byte(value)
proc digestHex(input: string): PagedDigest =
  ## Turn a 32-byte independent witness into its nominal local-digest role.
  let bytes = hex(input)
  assert bytes.len == 32
  var raw = default(array[32, byte])
  for index in 0..<32: raw[index] = bytes[index]
  PagedDigest(raw)
proc prefix(input: seq[byte], size: int): seq[byte] =
  ## Copy a bounded prefix without the pinned compiler's unsupported slicing helper.
  assert size >= 0 and size <= input.len
  result = newSeq[byte](size)
  for index in 0..<size: result[index] = input[index]
proc put(input: var seq[byte], offset: int, number: uint64) =
  ## Test-only byte construction is independent of production codec writes.
  for index in 0..<8: input[offset+index] = byte((number shr (index*8)) and 255)
proc headerBytes(count, payload: uint64): seq[byte] =
  ## Independent struct witness uses explicit zero chain/root, epoch one and sequence zero.
  result = newSeq[byte](4096)
  let magic = hex("5241474e41524f4b2d4c494748542d50414745442d56310a")
  for index in 0..<magic.len: result[index] = magic[index]
  result[88] = 1
  put(result, 104, count)
  put(result, 112, payload)
proc rowBytes(first: byte, offset, length: uint64): seq[byte] =
  ## Fixed descriptors leave every remaining key and reserved octet zero.
  result = newSeq[byte](64)
  result[0] = first
  put(result, 31, offset)
  put(result, 39, length)
func policy(bytes = high(uint64), entries = high(uint64)): PagedLimits =
  ## Tests vary total dataset ceilings independently from per-record proof bounds.
  PagedLimits(entries: ElementLimit(entries), bytes: ByteLimit(bytes))
proc header(count, payload: uint64): PagedHeader =
  ## Native decoding consumes independently built bytes before any successful encoding comparison.
  decodePagedHeader(headerBytes(count, payload), default(StorageChainId), default(StateRoot),
      policy()).value
proc metadata() =
  ## Exhaust fixed-width prefixes, reserved fields, identity and byte/count/address limits.
  let source = headerBytes(2, 82)
  let checked = header(2, 82)
  let shape = checked.geometry
  assert checked.initialized and uint64(checked.epoch) == 1 and uint64(checked.sequence) == 0
  assert array[32, byte](checked.chainId) == default(array[32, byte])
  assert array[32, byte](checked.root) == default(array[32, byte])
  assert checked.bytes == source
  assert shape.entries == 2 and shape.payloadBytes == 82 and shape.dataPages == 3
  assert shape.treeLeaves == 4 and shape.treeDepth == 2 and shape.byteLength == 12512
  assert uint64(shape.payloadOffset) == 8192 and uint64(shape.treeOffset) == 12288
  assert not default(PagedGeometry).initialized and not default(PagedHeader).initialized
  assert not default(PagedManifest).initialized
  let missing = default(PagedCodecResult[PagedHeader])
  assert missing.error == PagedCodecError.Uninitialized
  for size in 0..<source.len:
    # Every proper header prefix refuses without provider work or partial metadata.
    assert decodePagedHeader(prefix(source, size), checked.chainId, checked.root, policy()).error ==
      PagedCodecError.InvalidFormat
  for index in 120..<4096:
    # Every padding byte, not just its edges, is canonical zero.
    var changed = source
    changed[index] = 1
    assert decodePagedHeader(changed, checked.chainId, checked.root, policy()).error ==
        PagedCodecError.InvalidFormat
  var changed = source
  changed.add(0)
  assert decodePagedHeader(changed, checked.chainId, checked.root, policy()).error ==
      PagedCodecError.InvalidFormat
  changed = source
  changed[0] = 0
  assert decodePagedHeader(changed, checked.chainId, checked.root, policy()).error ==
      PagedCodecError.InvalidFormat
  changed = source
  changed[24] = 1
  assert decodePagedHeader(changed, checked.chainId, checked.root, policy()).error ==
      PagedCodecError.WrongChain
  changed = source
  changed[56] = 1
  assert decodePagedHeader(changed, checked.chainId, checked.root, policy()).error ==
      PagedCodecError.WrongRoot
  changed = source
  changed[88] = 0
  assert decodePagedHeader(changed, checked.chainId, checked.root, policy()).error ==
      PagedCodecError.InvalidFormat
  assert pagedGeometry(0, 1, policy()).error == PagedCodecError.InvalidFormat
  assert pagedGeometry(1, 40, policy()).error == PagedCodecError.InvalidFormat
  assert pagedGeometry(2, 82, policy(12511)).error == PagedCodecError.LimitExceeded
  assert pagedGeometry(2, 82, policy(12512)).value.byteLength == 12512
  assert pagedGeometry(2, 82, policy(12512, 1)).error == PagedCodecError.LimitExceeded
  assert pagedGeometry(0, 0, policy(4127)).error == PagedCodecError.LimitExceeded
  assert pagedGeometry(0, 0, policy(4128)).value.byteLength == 4128
  assert pagedGeometry(1, high(uint64), policy()).error == PagedCodecError.LimitExceeded
  let overflow = high(uint64) div 64+1
  assert pagedGeometry(overflow, high(uint64), policy()).error == PagedCodecError.LengthOverflow
  let lastCount = high(uint64) div 64
  assert pagedGeometry(lastCount, high(uint64), policy()).error == PagedCodecError.LimitExceeded
  assert pagedGeometry(0, 0, policy(0)).error == PagedCodecError.LimitExceeded
  for n in [1'u64, 63, 64, 65, 127, 128, 129, 4096]:
    # An independent small arithmetic oracle crosses index and payload page boundaries.
    for size in [41*n, 4095*n, 4096*n, 4097*n]:
      let g = pagedGeometry(n, size, policy()).value
      let pages = 1+(64*n+4095) div 4096+(size+4095) div 4096
      var leaves = 1'u64
      var depth = 0
      while leaves < pages:
        leaves *= 2
        inc depth
      assert g.dataPages == pages and g.treeLeaves == leaves and g.treeDepth == depth
      assert g.byteLength == pages*4096+(2*leaves-1)*32
  resetHash(0)
  discard decodePagedHeader(source, checked.chainId, checked.root, policy(0))
  assert calls() == 0
proc descriptors() =
  ## Scan exact ordering/coverage with first-error state, and preflight one proof prefix before allocation.
  let shape = header(2, 82).geometry
  let first = rowBytes(0, 0, 41)
  let second = rowBytes(128, 41, 41)
  let row = decodePagedDescriptor(first, shape).value
  assert row.bytes == first and uint64(row.offset) == 0 and row.byteLength == 41
  assert array[31, byte](row.key) == default(array[31, byte])
  for size in 0..<64:
    assert decodePagedDescriptor(prefix(first, size), shape).error == PagedCodecError.InvalidFormat
  var changed = first
  changed.add(0)
  assert decodePagedDescriptor(changed, shape).error == PagedCodecError.InvalidFormat
  for index in 47..<64:
    changed = first
    changed[index] = 1
    assert decodePagedDescriptor(changed, shape).error == PagedCodecError.InvalidFormat
  for bad in [rowBytes(0, 0, 40), rowBytes(0, 83, 41), rowBytes(0, 42, 41),
      rowBytes(0, high(uint64), 41), rowBytes(0, 0, high(uint64))]:
    # Extent subtraction precedes addition, including maximum uint64 sentinels.
    assert decodePagedDescriptor(bad, shape).error == PagedCodecError.InvalidFormat
  assert decodePagedDescriptor(first, default(PagedGeometry)).error == PagedCodecError.Uninitialized
  var scan = initPagedIndexScan(shape)
  assert scan.admit(first).value.bytes == first
  assert scan.admit(second).value.bytes == second
  assert scan.finish == PagedCodecError.None
  assert scan.admit(first).error == PagedCodecError.InvalidFormat
  assert scan.finish == PagedCodecError.InvalidFormat
  for bad in [rowBytes(0, 41, 41), rowBytes(128, 40, 41), rowBytes(128, 0, 41)]:
    # Duplicate keys, overlapping spans and aliasing cannot complete or recover after a later good row.
    scan = initPagedIndexScan(shape)
    discard scan.admit(first).value
    assert scan.admit(bad).error == PagedCodecError.InvalidFormat
    assert scan.admit(second).error == PagedCodecError.InvalidFormat
    assert scan.finish == PagedCodecError.InvalidFormat
  scan = initPagedIndexScan(shape)
  assert scan.finish == PagedCodecError.InvalidFormat
  scan = initPagedIndexScan(shape)
  discard scan.admit(first).value
  assert scan.finish == PagedCodecError.InvalidFormat
  scan = initPagedIndexScan(header(1, 82).geometry)
  discard scan.admit(first).value
  assert scan.finish == PagedCodecError.InvalidFormat
  scan = initPagedIndexScan(header(0, 0).geometry)
  assert scan.finish == PagedCodecError.None
  assert scan.finish == PagedCodecError.InvalidFormat
  scan = default(PagedIndexScan)
  assert scan.finish == PagedCodecError.Uninitialized
  assert scan.admit(first).error == PagedCodecError.Uninitialized
  scan = initPagedIndexScan(header(2, 83).geometry)
  discard scan.admit(first).value
  assert scan.admit(rowBytes(128, 42, 41)).error == PagedCodecError.InvalidFormat
  var low = first
  var high = second
  low[30] = 1
  high[0] = 0
  high[30] = 2
  scan = initPagedIndexScan(shape)
  discard scan.admit(low).value
  discard scan.admit(high).value
  assert scan.finish == PagedCodecError.None
  low[30] = 3
  scan = initPagedIndexScan(shape)
  discard scan.admit(low).value
  assert scan.admit(high).error == PagedCodecError.InvalidFormat
  var proof = newSeq[byte](41)
  let framed = decodePagedProofShape(proof, row, ElementLimit(249), ByteLimit(0)).value
  assert framed.nodes == 0 and framed.valueBytes == 0
  for size in 0..<41:
    assert decodePagedProofShape(prefix(proof, size), row, ElementLimit(249), ByteLimit(0)).error ==
        PagedCodecError.InvalidFormat
  proof.add(0)
  assert decodePagedProofShape(proof, row, ElementLimit(249), ByteLimit(0)).error ==
      PagedCodecError.InvalidFormat
  proof = newSeq[byte](41)
  proof[0] = 1
  assert decodePagedProofShape(proof, row, ElementLimit(249), ByteLimit(0)).error ==
      PagedCodecError.InvalidFormat
  proof[0] = 0
  proof[31] = 250
  assert decodePagedProofShape(proof, row, ElementLimit(1000), ByteLimit(high(uint64))).error ==
      PagedCodecError.InvalidFormat
  proof[31] = 249
  put(proof, 33, 4097)
  let big = header(1, uint64(41+249*64+4097)).geometry
  let bigRow = initPagedDescriptor(big, default(StateKey), PagedOffset(0), big.payloadBytes).value
  assert decodePagedProofShape(proof, bigRow, ElementLimit(249), ByteLimit(4097)).value.nodes == 249
  assert decodePagedProofShape(proof, bigRow, ElementLimit(248), ByteLimit(4097)).error ==
      PagedCodecError.LimitExceeded
  assert decodePagedProofShape(proof, bigRow, ElementLimit(249), ByteLimit(4096)).error ==
      PagedCodecError.LimitExceeded
  put(proof, 33, high(uint64))
  assert decodePagedProofShape(proof, bigRow, ElementLimit(249), ByteLimit(high(uint64))).error ==
      PagedCodecError.LengthOverflow
  put(proof, 33, 4096)
  assert decodePagedProofShape(proof, bigRow, ElementLimit(249), ByteLimit(4097)).error ==
      PagedCodecError.InvalidFormat
  assert decodePagedProofShape(proof, default(PagedDescriptor), ElementLimit(249), ByteLimit(
      4097)).error == PagedCodecError.Uninitialized

# A deliberately resident TEST oracle enumerates postorder child links, unlike production's scalar navigation.
type TreeNode = object
  ## Test-only explicit child/parent and page identities permit an independent upward walk.
  left, right, parent, page: int
proc appendTree(nodes: var seq[TreeNode], first, count: int): int =
  ## Recursively emit complete child records before their parent, without production offset formulas.
  if count == 1:
    nodes.add(TreeNode(left: -1, right: -1, parent: -1, page: first))
    return nodes.len-1
  let left = appendTree(nodes, first, count div 2)
  let right = appendTree(nodes, first+count div 2, count div 2)
  let parent = nodes.len
  nodes.add(TreeNode(left: left, right: right, parent: -1, page: -1))
  nodes[left].parent = parent
  nodes[right].parent = parent
  parent
proc paths() =
  ## Enumerated postorder topology independently checks every real leaf across power-of-two boundaries.
  for pages in [1, 3, 4, 5, 7, 8, 9, 15, 16, 17, 31, 32, 33, 65, 129]:
    let shape = if pages == 1: header(0, 0).geometry else: header(1, uint64((
        pages-2)*4096)).geometry
    assert shape.dataPages == uint64(pages)
    var nodes: seq[TreeNode] = @[]
    discard appendTree(nodes, 0, int(shape.treeLeaves))
    for slot in 0..<nodes.len:
      # Independent explicit links select real page leaves, then walk parents from leaf to root.
      if nodes[slot].page >= 0 and nodes[slot].page < pages:
        let path = pagedPath(shape, PageOrdinal(nodes[slot].page)).value
        assert uint64(path.leafOffset) == shape.dataPages*4096+uint64(slot)*32
        var current = slot
        var level = 0
        while nodes[current].parent >= 0:
          let parent = nodes[current].parent
          let isRight = nodes[parent].right == current
          let sibling = if isRight: nodes[parent].left else: nodes[parent].right
          assert uint64(path.step(level).offset) == shape.dataPages*4096+uint64(sibling)*32
          assert path.step(level).siblingLeft == isRight
          current = parent
          inc level
        assert path.len == level
    assert pagedPath(shape, PageOrdinal(shape.dataPages)).error == PagedCodecError.InvalidFormat
  assert pagedPath(default(PagedGeometry), PageOrdinal(0)).error == PagedCodecError.Uninitialized

proc witness(selected: PagedHeader, golden, tree: seq[byte]) =
  ## Run the same strict codec checks against independent empty and nonempty artifact literals.
  let shape = selected.geometry
  var expectedRaw = default(array[32, byte])
  for index in 0..<32: expectedRaw[index] = tree[tree.len-32+index]
  let expected = PagedDigest(expectedRaw)
  let encoded = encodePagedManifest(selected, expected, ByteLimit(193)).value
  assert encoded.bytes == golden
  let independent = decodePagedManifest(golden, selected.chainId, selected.root, policy(),
      ByteLimit(193)).value
  assert independent.bytes == golden and independent.validatePagedBinding(selected) ==
      PagedCodecError.None
  assert uint64(independent.epoch) == 1 and uint64(independent.sequence) == 0
  assert independent.dataPages == shape.dataPages and independent.byteLength == shape.byteLength
  assert array[32, byte](independent.chainId) == array[32, byte](selected.chainId)
  assert array[32, byte](independent.root) == array[32, byte](selected.root)
  assert decodePagedManifest(golden, selected, ByteLimit(193)).value.bytes == golden
  assert array[32, byte](encoded.pageRoot) == expectedRaw
  for size in 0..<golden.len:
    # Every CURRENT truncation refuses; no partial checksum/selection is exposed.
    assert decodePagedManifest(prefix(golden, size), selected, ByteLimit(193)).error ==
        PagedCodecError.InvalidFormat
  var extra = golden
  extra.add(0)
  assert decodePagedManifest(extra, selected, ByteLimit(194)).error == PagedCodecError.InvalidFormat
  for offset in [0, 97, 105, 113, 121]:
    # Shape/selection corruption refuses before provider work.
    var changed = golden
    changed[offset] = changed[offset] xor 1
    resetHash(0)
    assert decodePagedManifest(changed, selected, ByteLimit(193)).error ==
        PagedCodecError.InvalidFormat
    assert calls() == 0
  for offset in [33, 65]:
    # Independently expected identities never come from the candidate manifest.
    var changed = golden
    changed[offset] = changed[offset] xor 1
    let reason = if offset == 33: PagedCodecError.WrongChain else: PagedCodecError.WrongRoot
    resetHash(0)
    assert decodePagedManifest(changed, selected, ByteLimit(193)).error == reason
    assert calls() == 0
  for offset in 129..<193:
    # Every page-root/checksum byte is covered by the local checksum.
    var changed = golden
    changed[offset] = changed[offset] xor 1
    assert decodePagedManifest(changed, selected, ByteLimit(193)).error ==
        PagedCodecError.ChecksumMismatch
  for ordinal in 0..<int(shape.dataPages):
    # Independent witness page bytes reproduce every leaf and bottom-up proof schedule.
    var page = newSeq[byte](4096)
    if ordinal == 0:
      page = headerBytes(shape.entries, shape.payloadBytes)
    elif ordinal == 1:
      let first = rowBytes(0, 0, 41)
      let second = rowBytes(128, 41, 41)
      for index in 0..<64:
        page[index] = first[index]
        page[64+index] = second[index]
    else:
      page[41] = 128
    let path = pagedPath(shape, PageOrdinal(ordinal)).value
    let leaf = pagedLeafDigest(shape, PageOrdinal(ordinal), page).value
    let leafSlot = int((uint64(path.leafOffset)-uint64(shape.treeOffset)) div 32)
    for index in 0..<32: assert array[32, byte](leaf)[index] == tree[leafSlot*32+index]
    var siblings = newSeq[PagedDigest](path.len)
    for level in 0..<path.len:
      let slot = int((uint64(path.step(level).offset)-uint64(shape.treeOffset)) div 32)
      var raw = default(array[32, byte])
      for index in 0..<32: raw[index] = tree[slot*32+index]
      siblings[level] = PagedDigest(raw)
    assert verifyPagedPage(shape, PageOrdinal(ordinal), page, siblings, expected) ==
        PagedCodecError.None
    for fail in 0..path.len:
      # Partial successful hash paths never yield authenticated page success after provider failure.
      failAfter(cint(fail))
      assert verifyPagedPage(shape, PageOrdinal(ordinal), page, siblings, expected) ==
          PagedCodecError.BackendFailure
      assert calls() == cint(fail+1)
    resetHash(0)
    var changedPage = page
    changedPage[4095] = changedPage[4095] xor 1
    assert verifyPagedPage(shape, PageOrdinal(ordinal), changedPage, siblings, expected) ==
        PagedCodecError.ChecksumMismatch
    var changedRoot = expectedRaw
    changedRoot[0] = changedRoot[0] xor 1
    assert verifyPagedPage(shape, PageOrdinal(ordinal), page, siblings, PagedDigest(changedRoot)) ==
        PagedCodecError.ChecksumMismatch
    for level in 0..<siblings.len:
      var changed = siblings
      var raw = array[32, byte](changed[level])
      raw[0] = raw[0] xor 1
      changed[level] = PagedDigest(raw)
      assert verifyPagedPage(shape, PageOrdinal(ordinal), page, changed, expected) ==
          PagedCodecError.ChecksumMismatch
    siblings.add(default(PagedDigest))
    resetHash(0)
    assert verifyPagedPage(shape, PageOrdinal(ordinal), page, siblings, expected) ==
        PagedCodecError.InvalidFormat
    assert calls() == 0
  resetHash(0)
  assert encodePagedManifest(selected, expected, ByteLimit(192)).error ==
      PagedCodecError.LimitExceeded
  assert encodePagedManifest(default(PagedHeader), expected, ByteLimit(193)).error ==
      PagedCodecError.Uninitialized
  assert decodePagedManifest(golden, selected, ByteLimit(192)).error ==
      PagedCodecError.LimitExceeded
  assert decodePagedManifest(golden, default(PagedHeader), ByteLimit(193)).error ==
      PagedCodecError.Uninitialized
  assert pagedLeafDigest(shape, PageOrdinal(shape.dataPages), selected.bytes).error ==
      PagedCodecError.InvalidFormat
  assert pagedLeafDigest(shape, PageOrdinal(0), []).error == PagedCodecError.InvalidFormat
  assert pagedPaddingDigest(shape, PageOrdinal(0)).error == PagedCodecError.InvalidFormat
  assert pagedPaddingDigest(shape, PageOrdinal(shape.treeLeaves)).error ==
      PagedCodecError.InvalidFormat
  assert calls() == 0
  resetHash(1)
  assert encodePagedManifest(selected, expected, ByteLimit(193)).error ==
      PagedCodecError.BackendFailure
  assert decodePagedManifest(golden, selected, ByteLimit(193)).error ==
      PagedCodecError.BackendFailure
  assert pagedLeafDigest(shape, PageOrdinal(0), selected.bytes).error ==
      PagedCodecError.BackendFailure
  assert pagedNodeDigest(expected, expected).error == PagedCodecError.BackendFailure
  resetHash(0)

proc emptyWitness() =
  ## Fixed Python hashlib/struct bytes independently anchor the canonical local format.
  let selected = header(0, 0)
  let golden = hex("5241474e41524f4b2d4c494748542d50414745442d4d414e49464553542d56310a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000010000000000000020100000000000004fc34f4e3d1af70566cfc84c0f513c2f538adeb511f93f890df921bd85d1f093d0a672190bbc37ce48e0944a04cabd5dfaca4a8ae87ca4477221f2b4ca573146")
  let tree = hex("4fc34f4e3d1af70566cfc84c0f513c2f538adeb511f93f890df921bd85d1f093")
  witness(selected, golden, tree)
proc absenceWitness() =
  ## Fixed Python hashlib/struct bytes independently anchor the canonical local format.
  let selected = header(2, 82)
  let golden = hex("5241474e41524f4b2d4c494748542d50414745442d4d414e49464553542d56310a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000300000000000000e03000000000000065c398a5724e8de74a7e253676a8fe75e490df05318f2b0e898525e0a87fb1a10b685aad6b4cb1cba9a4fc4c5dead2d70bdd31423fde37f53a4281d89d296aa6")
  let tree = hex("614cbf8089d06ebb55cd3b0af066d8a3dc3afa1a7e3ec202ddc9f1dd7fc13ac098cc43a0d72c97f4546e3d10bdb97c28df98d4d13e529ae9479ee75280286dc2b12b9c4a3c3044e50a2cbe0bde32f03d98108cf887a795b678be2b59a6281314cc395a22005a4e2d027bef45f3151a99fc33e8627e2b8e7059108fa0b4af0ee9297ad4b78ef8722ba2f6d00ad13dcfd9f075a906b22782df6dd8c9fb02f3fdd8548904791a7bbbf5cec3b728992059261a9b7de6d7e19db2dde300b29b67da0865c398a5724e8de74a7e253676a8fe75e490df05318f2b0e898525e0a87fb1a1")
  witness(selected, golden, tree)
  let shape = selected.geometry
  let pad = digestHex("297ad4b78ef8722ba2f6d00ad13dcfd9f075a906b22782df6dd8c9fb02f3fdd8")
  assert array[32, byte](pagedPaddingDigest(shape, PageOrdinal(3)).value) == array[32, byte](pad)
  resetHash(1)
  assert pagedPaddingDigest(shape, PageOrdinal(3)).error == PagedCodecError.BackendFailure
  resetHash(0)


proc cycle() =
  ## All detached fixed buffers and scalar results retire before each next ARC sample.
  let selected = header(2, 82)
  let encoded = selected.bytes
  let shape = decodePagedHeader(encoded, selected.chainId, selected.root, policy()).value.geometry
  let path = pagedPath(shape, PageOrdinal(2)).value
  assert path.len == 2
  let root = pagedLeafDigest(shape, PageOrdinal(0), encoded).value
  let manifest = encodePagedManifest(selected, root, ByteLimit(193)).value
  var transport = manifest.bytes
  let retained = manifest
  transport[0] = 0
  assert retained.bytes[0] != 0
  assert decodePagedManifest(transport, selected, ByteLimit(193)).error ==
      PagedCodecError.InvalidFormat
  assert decodePagedManifest(retained.bytes, selected, ByteLimit(193)).error == PagedCodecError.None
  var scan = initPagedIndexScan(shape)
  discard scan.admit(rowBytes(0, 0, 41)).value
  discard scan.admit(rowBytes(128, 41, 41)).value
  assert scan.finish == PagedCodecError.None
proc standaloneManifest() =
  ## CURRENT can be shape-checked before opening an epoch; exact header binding follows independently.
  let selected = header(2, 82)
  let shape = selected.geometry
  let encoded = encodePagedManifest(selected, default(PagedDigest), ByteLimit(193)).value
  let source = encoded.bytes
  for size in 0..<source.len:
    # Standalone selection parsing refuses every partial input before hashing.
    resetHash(0)
    assert decodePagedManifest(prefix(source, size), selected.chainId, selected.root, policy(),
        ByteLimit(193)).error == PagedCodecError.InvalidFormat
    assert calls() == 0
  for field in [97, 113, 121]:
    # Invalid epoch, zero pages and inconsistent exact length all fail before provider work.
    var bad = source
    put(bad, field, 0)
    resetHash(0)
    assert decodePagedManifest(bad, selected.chainId, selected.root, policy(), ByteLimit(
        193)).error == PagedCodecError.InvalidFormat
    assert calls() == 0
  var bad = source
  put(bad, 113, high(uint64))
  assert decodePagedManifest(bad, selected.chainId, selected.root, policy(), ByteLimit(
      193)).error == PagedCodecError.LimitExceeded
  assert decodePagedManifest(source, selected.chainId, selected.root, policy(12511), ByteLimit(
      193)).error == PagedCodecError.LimitExceeded
  assert decodePagedManifest(source, selected.chainId, selected.root, policy(), ByteLimit(
      192)).error == PagedCodecError.LimitExceeded
  assert calls() == 0
  bad = source
  bad.add(0)
  assert decodePagedManifest(bad, selected.chainId, selected.root, policy(), ByteLimit(
      194)).error == PagedCodecError.InvalidFormat
  for field in [0, 33, 65, 129, 192]:
    # Exact standalone parsing preserves schema, independently expected identities and checksum failures.
    bad = source
    bad[field] = bad[field] xor 1
    let reason = if field == 0: PagedCodecError.InvalidFormat
      elif field == 33: PagedCodecError.WrongChain
      elif field == 65: PagedCodecError.WrongRoot
      else: PagedCodecError.ChecksumMismatch
    assert decodePagedManifest(bad, selected.chainId, selected.root, policy(), ByteLimit(
        193)).error == reason
  assert validatePagedBinding(default(PagedManifest), selected) == PagedCodecError.Uninitialized
  assert validatePagedBinding(encoded, default(PagedHeader)) == PagedCodecError.Uninitialized
  for field in [24, 56, 88, 96, 104]:
    # Independently valid changed headers cannot borrow the old manifest's checked scalar binding.
    var bytes = selected.bytes
    bytes[field] = bytes[field] xor 3
    let c = if field == 24:
      var raw = default(array[32, byte])
      raw[0] = 3
      StorageChainId(raw)
      else: selected.chainId
    let r = if field == 56:
      var raw = default(array[32, byte])
      raw[0] = 3
      StateRoot(raw)
      else: selected.root
    if field == 104:
      # A larger count needs a matching minimum payload and changes the selected file geometry.
      put(bytes, 104, 65)
      put(bytes, 112, uint64(65*41))
    let changed = decodePagedHeader(bytes, c, r, policy()).value
    let reason = if field == 24: PagedCodecError.WrongChain
      elif field == 56: PagedCodecError.WrongRoot
      else: PagedCodecError.InvalidFormat
    assert validatePagedBinding(encoded, changed) == reason
  let maximum = initPagedHeader(selected.chainId, selected.root, ManagedEpoch(high(uint64)),
    LightDeltaSequence(high(uint64)), 2, 82, policy()).value
  let last = encodePagedManifest(maximum, default(PagedDigest), ByteLimit(193)).value
  let decoded = decodePagedManifest(last.bytes, selected.chainId, selected.root, policy(),
      ByteLimit(193)).value
  assert uint64(decoded.epoch) == high(uint64) and uint64(decoded.sequence) == high(uint64)
  assert decoded.validatePagedBinding(maximum) == PagedCodecError.None
  resetHash(1)
  assert decodePagedManifest(source, selected.chainId, selected.root, policy(), ByteLimit(
      193)).error == PagedCodecError.BackendFailure
  resetHash(0)
  let huge = pagedGeometry(1, 1'u64 shl 60, policy()).value
  assert huge.byteLength > (1'u64 shl 60) and huge.treeDepth > 40
  let path = pagedPath(huge, PageOrdinal(huge.dataPages-1)).value
  assert path.len == huge.treeDepth and uint64(path.leafOffset) < huge.byteLength
  for level in 0..<path.len:
    assert uint64(path.step(level).offset) >= uint64(huge.treeOffset)
    assert uint64(path.step(level).offset) <= huge.byteLength-32
  assert pagedPath(huge, PageOrdinal(high(uint64))).error == PagedCodecError.InvalidFormat
  assert calls() == 0

proc main() =
  ## Native checks cover the pure codec boundary; they claim no file lifetime, proof admission or memory ceiling.
  metadata()
  descriptors()
  paths()
  emptyWitness()
  absenceWitness()
  standaloneManifest()
  let before = getOccupiedMem()
  for index in 0..<1000:
    cycle()
  recordArcRelease("storage_paged_codec", 1000, before, getOccupiedMem())
  echo "PASS paged codec: independent bytes, checked geometry, index coverage, proof framing and postorder digest paths"
main()
