# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent V2 context-page geometry and byte oracles preserve exact explicit V1 selection.
# @@Verification={"arc":"storage_paged_context_codec_arc_release"}
import std/[assertions, syncio]
import ../../support/arc_evidence
import ../../../src/storage/[paged_codec, full_paged_codec, paged_stream, full_paged_stream,
  full_paged_build, database_identity, managed_manifest, light_delta, node_repository, node_records, light_state_cache]
import ../../../src/codec/[bounded, state_layout, state_trie]
import ../../../src/crypto/primitives
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Observe provider dispatch independently of structural header and policy preflight.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Invalid format/size must refuse before invoking cryptography.
func policy(): PagedLimits =
  ## These explicit finite data ceilings include context pages and their complete postorder tree.
  PagedLimits(entries: ElementLimit(10000), bytes: ByteLimit(10000000))
func identity(first: byte): array[32, byte] =
  ## Complete independent scalar identities differ at their first serialized octet.
  result = default(array[32, byte])
  result[0] = first
proc put(bytes: var openArray[byte], offset: int, value: uint64) =
  ## Known fixture offsets provide eight addressable octets for the independent E8 equation.
  for index in 0..<8: bytes[offset+index] = byte((value shr (index*8)) and 255) # Fixed shifts and masks.
proc putHash(bytes: var openArray[byte], offset: int, value: array[32, byte]) =
  ## Independent expected transport copies exactly one complete fixed-width identity.
  for index in 0..<32: bytes[offset+index] = value[index] # No production writer participates.
proc label(bytes: var openArray[byte], value: string) =
  ## Explicit literal labels and initially zero output give the one canonical physical version.
  for index, character in value: bytes[index] = byte(character) # Every test literal fits its fixed slot.
proc owned(input: openArray[byte]): seq[byte] =
  ## Mutation tests require independent transport rather than mutable aliases of opaque metadata.
  result = newSeq[byte](input.len)
  for index in 0..<input.len: result[index] = input[index] # Each source remains unchanged.
proc full(context: uint64): FullPagedHeader =
  ## One nonempty scalar claim suffices for codec shape; it grants no complete-graph authority.
  let made = initFullPagedHeader(StorageChainId(identity(7)), StateRoot(identity(2)),
    ManagedEpoch(3), RepositoryGeneration(4), 1, 72,
    [FullPagedRoot(root: StateRoot(identity(2)), entries: 1, nodes: 1)], policy(), context)
  assert made.error == FullPagedError.None
  made.value
proc light(context: uint64): PagedHeader =
  ## One framed query proof requires at least41 payload bytes independently of its opaque context.
  initPagedHeader(StorageChainId(identity(7)), StateRoot(identity(2)), ManagedEpoch(3),
    LightDeltaSequence(4), 1, 41, policy(), context).value
proc geometry() =
  ## Small independent integer equations cover empty graphs, page boundaries and exact physical ceilings.
  for context in [0'u64, 1, 4095, 4096, 4097, 12289]:
    # Context starts after separately padded payload; empty graphs still authenticate context pages.
    for records in [0'u64, 1, 65]:
      let payload = records*72
      let index = (records*64+4095) div 4096
      let data = 1+index+(payload+4095) div 4096
      let pages = data+(context+4095) div 4096
      var leaves = 1'u64
      while leaves < pages: leaves *= 2 # All fixture values are small and independently bounded.
      let extent = pages*4096+(leaves*2-1)*32
      let made = pagedGeometry(records, payload, policy(), context)
      assert made.error == PagedCodecError.None
      let shape = made.value
      assert shape.contextBytes == context and uint64(shape.contextOffset) == data*4096
      assert shape.dataPages == pages and uint64(shape.treeOffset) == pages*4096
      assert shape.byteLength == extent and shape.treeLeaves == leaves
      var exact = policy()
      exact.bytes = ByteLimit(extent)
      assert pagedGeometry(records, payload, exact, context).error == PagedCodecError.None
      exact.bytes = ByteLimit(extent-1)
      assert pagedGeometry(records, payload, exact, context).error == PagedCodecError.LimitExceeded
  assert pagedGeometry(0, 1, policy(), 4096).error == PagedCodecError.InvalidFormat
  assert pagedGeometry(0, 0, policy(), high(uint64)).error != PagedCodecError.None
  assert pagedGeometry(high(uint64), high(uint64), policy(), 1).error != PagedCodecError.None
proc fullBytes() =
  ## Fixed offsets independently encode all4096 bytes including root claims and final reserved padding.
  let header = full(4097)
  var expected = newSeq[byte](4096)
  label(expected, "RAGNAROK-FULL-PAGED-V2\n")
  putHash(expected, 32, identity(7))
  put(expected, 64, 3)
  put(expected, 72, 4)
  putHash(expected, 80, identity(2))
  put(expected, 112, 1)
  put(expected, 120, 72)
  put(expected, 128, 1)
  put(expected, 136, 4097)
  putHash(expected, 144, identity(2))
  put(expected, 176, 1)
  put(expected, 184, 1)
  assert owned(header.bytes) == expected
  let decoded = decodeFullPagedHeader(expected, header.chainId, header.root, policy(), ByteLimit(4097))
  assert decoded.error == FullPagedError.None and decoded.value.bytes == header.bytes
  assert decodeFullPagedHeader(expected, header.chainId, header.root, policy()).error ==
      FullPagedError.InvalidFormat
  assert decodeFullPagedHeader(full(0).bytes, header.chainId, header.root, policy(), ByteLimit(
      4097)).error == FullPagedError.InvalidFormat
  resetHash(0)
  assert decodeFullPagedHeader(expected, header.chainId, header.root, policy(), ByteLimit(
      4096)).error == FullPagedError.LimitExceeded
  assert hashCalls() == 0
  for index in [22, 200, 4095]:
    # Noncanonical label padding, unused root bytes and final-page bytes cannot hide context.
    var malformed = owned(expected)
    malformed[index] = 1
    assert decodeFullPagedHeader(malformed, header.chainId, header.root, policy(), ByteLimit(
        4097)).error == FullPagedError.InvalidFormat
  for length in 0..<4096:
    # All truncation boundaries fail on extent before any field can be interpreted.
    var truncated = newSeq[byte](length)
    assert decodeFullPagedHeader(truncated, header.chainId, header.root, policy(), ByteLimit(
        4097)).error == FullPagedError.InvalidFormat
  var zero = owned(expected)
  put(zero, 136, 0)
  assert decodeFullPagedHeader(zero, header.chainId, header.root, policy(), ByteLimit(
      4097)).error == FullPagedError.InvalidFormat
  var manifest = newSeq[byte](FullPagedManifestBytes)
  label(manifest, "RAGNAROK-FULL-PAGED-HEAD-V2\n")
  putHash(manifest, 32, identity(7))
  putHash(manifest, 64, identity(2))
  put(manifest, 96, 3)
  put(manifest, 104, 4)
  put(manifest, 112, 5)
  put(manifest, 120, 20960)
  putHash(manifest, 128, identity(9))
  putHash(manifest, 160, array[32, byte](blake2b256(manifest.toOpenArray(0, 159)).value))
  let selected = encodeFullPagedManifest(header, FullPagedDigest(identity(9))).value
  assert owned(selected.bytes.value) == manifest
  assert decodeFullPagedManifest(manifest, header).error == FullPagedError.None
  assert decodeFullPagedSelection(manifest, header.chainId, header.root, policy(), true).error ==
      FullPagedError.None
  assert decodeFullPagedSelection(manifest, header.chainId, header.root, policy()).error ==
      FullPagedError.InvalidFormat
  assert decodeFullPagedManifest(manifest, full(0)).error == FullPagedError.InvalidFormat
proc lightBytes() =
  ## Light V2 retains its own distinct root/proof schema and the193-byte CURRENT layout.
  let header = light(4097)
  var expected = newSeq[byte](4096)
  label(expected, "RAGNAROK-LIGHT-PAGED-V2\n")
  putHash(expected, 24, identity(7))
  putHash(expected, 56, identity(2))
  put(expected, 88, 3)
  put(expected, 96, 4)
  put(expected, 104, 1)
  put(expected, 112, 41)
  put(expected, 120, 4097)
  assert header.bytes == expected
  assert decodePagedHeader(expected, header.chainId, header.root, policy(), ByteLimit(
      4097)).value.bytes == expected
  assert decodePagedHeader(expected, header.chainId, header.root, policy()).error ==
      PagedCodecError.InvalidFormat
  assert decodePagedHeader(light(0).bytes, header.chainId, header.root, policy(), ByteLimit(
      4097)).error == PagedCodecError.InvalidFormat
  resetHash(0)
  assert decodePagedHeader(expected, header.chainId, header.root, policy(), ByteLimit(
      4096)).error == PagedCodecError.LimitExceeded
  assert hashCalls() == 0
  for index in [23, 128, 4095]:
    # Version-label, context-section and final header padding all have one representation.
    var malformed = owned(expected)
    malformed[index] = 1
    assert decodePagedHeader(malformed, header.chainId, header.root, policy(), ByteLimit(
        4097)).error == PagedCodecError.InvalidFormat
  var zero = owned(expected)
  put(zero, 120, 0)
  assert decodePagedHeader(zero, header.chainId, header.root, policy(), ByteLimit(4097)).error ==
      PagedCodecError.InvalidFormat
  put(zero, 120, high(uint64))
  assert decodePagedHeader(zero, header.chainId, header.root, policy(), ByteLimit(4097)).error ==
      PagedCodecError.LimitExceeded
  var manifest = newSeq[byte](PagedManifestBytes)
  label(manifest, "RAGNAROK-LIGHT-PAGED-MANIFEST-V2\n")
  putHash(manifest, 33, identity(7))
  putHash(manifest, 65, identity(2))
  put(manifest, 97, 3)
  put(manifest, 105, 4)
  put(manifest, 113, 5)
  put(manifest, 121, 20960)
  putHash(manifest, 129, identity(9))
  putHash(manifest, 161, array[32, byte](blake2b256(manifest.toOpenArray(0, 160)).value))
  let selected = encodePagedManifest(header, PagedDigest(identity(9)), ByteLimit(
      PagedManifestBytes)).value
  assert selected.bytes == manifest
  assert decodePagedManifest(manifest, header, ByteLimit(PagedManifestBytes)).error ==
      PagedCodecError.None
  assert decodePagedManifest(manifest, header.chainId, header.root, policy(), ByteLimit(
      PagedManifestBytes), true).error == PagedCodecError.None
  assert decodePagedManifest(manifest, header.chainId, header.root, policy(), ByteLimit(
      PagedManifestBytes)).error == PagedCodecError.InvalidFormat
  assert validatePagedBinding(selected, light(0)) == PagedCodecError.InvalidFormat
proc unsupported() =
  ## V2 metadata alone must not enable silent zero-filled native context or partial graph admission.
  var calls = 0
  proc producer(pass: int, ordinal: uint64, record: var TrieRecord): FullPagedProducerStep {.closure.} =
    ## Any dispatch here would precede required native context support and violate structural preflight.
    inc calls
    FullPagedProducerStep.End
  let header = full(1)
  assert buildFullPaged(default(PagedOutput), default(FullPagedScratch), producer, header,
    default(FullPagedBuildLimits)).error == FullPagedBuildError.UnsupportedPolicy
  var limits = default(FullPagedStreamLimits)
  limits.workingBytes = ByteLimit(FullPagedFixedBytes)
  let manifest = encodeFullPagedManifest(header, FullPagedDigest(identity(9))).value
  assert validateFullPaged(default(PagedInput), default(FullPagedScratch), header, manifest,
    limits).error == FullPagedStreamError.UnsupportedPolicy
  proc next(pass: int, ordinal: uint64, record: var LightStateProof): PagedProducerStep {.closure.} =
    ## Light evidence cannot be requested before native context transport is supported.
    inc calls
    PagedProducerStep.End
  proc read(offset: PagedOffset, output: var openArray[byte]): bool {.closure.} =
    ## Any source dispatch during structural refusal would violate the native gate.
    inc calls
    false
  proc extent(output: var uint64): bool {.closure.} =
    ## Even an EOF observation remains forbidden before unsupported V2 authoring refuses.
    inc calls
    false
  proc append(input: openArray[byte]): bool {.closure.} =
    ## Unsupported context must not leave a silently zero-filled forensic artifact.
    inc calls
    false
  let output = PagedOutput(source: PagedInput(read: read, extent: extent), append: append)
  let lightLimits = PagedStreamLimits(workingBytes: ByteLimit(100000))
  assert buildPagedArtifact(output, next, light(1), lightLimits).error ==
      PagedStreamError.UnsupportedPolicy
  assert calls == 0
proc cycle() =
  ## Every temporary header, expected buffer and manifest retires before the warmed ARC sample.
  let header = light(4097)
  let decoded = decodePagedHeader(header.bytes, header.chainId, header.root, policy(), ByteLimit(4097))
  assert decoded.error == PagedCodecError.None
  assert decodeFullPagedHeader(full(4097).bytes, header.chainId, header.root, policy(), ByteLimit(
      4097)).error == FullPagedError.None
proc main() =
  ## Keep all checked assertions active while qualifying the two explicit physical format families.
  geometry()
  fullBytes()
  lightBytes()
  unsupported()
  cycle()
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle() # No opaque owner may retain encoded transport between calls.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_paged_context_codec", 1000, before, after)
  echo "storage paged context codec PASS"
main()
