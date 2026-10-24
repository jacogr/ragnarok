# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Full-state paged metadata preserves complete physical identities and bounded retained-root claims.
## These codecs confer local shape/integrity only; complete graph admission and native pins are separate.
import std/assertions
import ./[paged_codec, database_identity, managed_manifest, node_records, node_repository]
import ../codec/[bounded, state_layout, state_trie]
import ../crypto/primitives

const
  FullPagedMaxRoots* = 64       ## One header page bounds retained roots independently of dataset size.
  FullPagedManifestBytes* = 192 ## Fixed CURRENT body and local checksum; never chain authority.
  HeaderMagic = "RAGNAROK-FULL-PAGED-V1\n"
  ContextHeaderMagic = "RAGNAROK-FULL-PAGED-V2\n"
  ManifestMagic = "RAGNAROK-FULL-PAGED-HEAD-V1\n"
  ContextManifestMagic = "RAGNAROK-FULL-PAGED-HEAD-V2\n"
  LeafDomain = "RAGNAROK-FULL-PAGED-LEAF-V1\n"
  PadDomain = "RAGNAROK-FULL-PAGED-PAD-V1\n"
  NodeDomain = "RAGNAROK-FULL-PAGED-NODE-V1\n"
type
  FullPagedError* {.pure.} = enum ## No failed/default result exposes checked metadata or record bytes.
    Uninitialized, None, InvalidFormat, LimitExceeded, LengthOverflow, WrongChain, WrongRoot,
    ChecksumMismatch, BackendFailure, HashMismatch
  FullPagedResult*[T] = object ## Private alternatives guard every successful payload.
    case status: FullPagedError
    of None: completed: T
    else: discard
  FullPagedDigest* = distinct array[32, byte] ## Full-format local page authentication, distinct from JAM roots.
  FullPagedRoot* = object ## Untrusted complete-root claim; graph validation must recompute all totals.
    root*: StateRoot
    entries*, nodes*, valueBytes*: uint64
  FullPagedHeader* = object ## Fixed scalar inventory contains at most 64 roots, with no resident record index.
    ready: bool
    chain: StorageChainId
    selected: StateRoot
    physical: ManagedEpoch
    ordinary: RepositoryGeneration
    shape: PagedGeometry
    count: int
    roots: array[FullPagedMaxRoots, FullPagedRoot]
  FullPagedRow* = object ## A checked complete physical address and payload-relative bounded extent.
    ready: bool
    digest: StateNodeHash
    start, size: uint64
  FullPagedIndexScan* = object ## Constant-space strictly ordered contiguous index validation.
    status: FullPagedError
    shape: PagedGeometry
    seen, ending: uint64
    previous: StateNodeHash
    done: bool
  FullPagedManifest* = object ## Checksummed exact selected artifact identity; never complete graph authority.
    ready: bool
    chain: StorageChainId
    selected: StateRoot
    physical: ManagedEpoch
    ordinary: RepositoryGeneration
    pages, extent: uint64
    contextual: bool
    tree: FullPagedDigest

func error*[T](outcome: FullPagedResult[T]): FullPagedError =
  ## Observe only the selected success/failure reason.
  outcome.status
func value*[T](outcome: FullPagedResult[T]): T {.inline,
    requires: outcome.status == FullPagedError.None.} =
  ## Extract only complete selected payloads.
  outcome.completed
func refused[T](reason: FullPagedError): FullPagedResult[T] =
  ## Failed results never retain a partial scalar or allocation.
  FullPagedResult[T](status: reason)
func codecReason(reason: PagedCodecError): FullPagedError =
  ## Shared geometry has no format identity; translate only its bounded arithmetic verdict.
  case reason
  of PagedCodecError.None: FullPagedError.None
  of PagedCodecError.LimitExceeded: FullPagedError.LimitExceeded
  of PagedCodecError.LengthOverflow: FullPagedError.LengthOverflow
  else: FullPagedError.InvalidFormat
func fullPagedGeometry*(count, payload: uint64, limits: PagedLimits,
    context = 0'u64): FullPagedResult[PagedGeometry] =
  ## Each canonical full record uses at least 72 bytes; shared geometry owns only page arithmetic.
  if count > payload div 72: return refused[PagedGeometry](FullPagedError.InvalidFormat)
  let shape = pagedGeometry(count, payload, limits, context)
  if shape.error != PagedCodecError.None: return refused[PagedGeometry](codecReason(shape.error))
  FullPagedResult[PagedGeometry](status: FullPagedError.None, completed: shape.value)
func compareFullHash*(left, right: array[32, byte]): int =
  ## Full 256-bit lexical identity must never mask the physical left-child bit.
  for index in 0..<32:
    # The first differing octet fixes total ordering without integer conversion.
    if left[index] < right[index]: return -1
    if left[index] > right[index]: return 1
  0
func number(input: openArray[byte], offset: int): uint64 =
  ## Fixed callers prove eight addressable bytes before decoding little-endian scalars.
  result = 0
  for index in 0..<8:
    # Shifts are bounded to 56 and never depend on hostile integer widths.
    result = result or (uint64(input[offset+index]) shl (8*index))
proc put(output: var openArray[byte], offset: int, value: uint64) =
  ## Fixed callers prove destination extents before little-endian encoding.
  for index in 0..<8:
    # Each octet is narrowed only after masking to its representable range.
    output[offset+index] = byte((value shr (8*index)) and 255)
func hashAt(input: openArray[byte], offset: int): array[32, byte] =
  ## All callers supply a preflighted fixed metadata or record extent.
  result = default(array[32, byte])
  for index in 0..<32: result[index] = input[offset+index] # Copy scalar identities only.
proc putHash(output: var openArray[byte], offset: int, value: array[32, byte]) =
  ## Copy one complete identity without retaining mutable source storage.
  for index in 0..<32: output[offset+index] = value[index] # The fixed destination was preflighted.
func zeros(input: openArray[byte], first, stop: int): bool =
  ## Callers preflight a half-open fixed extent; reserved bytes have exactly one representation.
  for index in first..<stop:
    if input[index] != 0: return false # Any nonzero reserved octet refuses.
  true
func magic(input: openArray[byte], expected: string): bool =
  ## Every identity starts with a canonical zero-padded 32-byte schema label.
  for index, character in expected:
    if input[index] != byte(character): return false # No alternate format or fallback.
  zeros(input, expected.len, 32)
proc putMagic(output: var openArray[byte], expected: string) =
  ## Fresh zero-filled buffers provide the canonical remainder of the 32-byte label.
  for index, character in expected: output[index] = byte(character) # Labels fit their fixed slot.
func initialized*(header: FullPagedHeader): bool =
  ## Default metadata grants no addressing or retained-root claim.
  header.ready
func geometry*(header: FullPagedHeader): PagedGeometry {.requires: header.ready.} =
  ## Return scalar-only checked geometry.
  header.shape
func chainId*(header: FullPagedHeader): StorageChainId {.requires: header.ready.} =
  ## Return the independently expected chain binding.
  header.chain
func root*(header: FullPagedHeader): StateRoot {.requires: header.ready.} =
  ## Return the selected complete root claim, pending complete graph admission.
  header.selected
func epoch*(header: FullPagedHeader): ManagedEpoch {.requires: header.ready.} =
  ## Return positive physical selection identity.
  header.physical
func generation*(header: FullPagedHeader): RepositoryGeneration {.requires: header.ready.} =
  ## Ordinary generation is independent of physical compaction epochs.
  header.ordinary
func len*(header: FullPagedHeader): int {.requires: header.ready.} =
  ## Root inventory is bounded independently from the physical record count.
  header.count
func retainedRoot*(header: FullPagedHeader, index: int): FullPagedRoot {.requires:
    header.ready and index >= 0 and index < header.count.} =
  ## Return a scalar claim, never a mutable array view.
  header.roots[index]
func initFullPagedHeader*(chain: StorageChainId, selected: StateRoot, epoch: ManagedEpoch,
    generation: RepositoryGeneration, count, payload: uint64, roots: openArray[FullPagedRoot],
    limits: PagedLimits, context = 0'u64): FullPagedResult[FullPagedHeader] =
  ## Validate bounded inventory and all scalar claims before granting format-only metadata.
  if roots.len == 0 or roots.len > FullPagedMaxRoots or uint64(epoch) == 0:
    return refused[FullPagedHeader](FullPagedError.InvalidFormat)
  let shape = fullPagedGeometry(count, payload, limits, context)
  if shape.error != FullPagedError.None: return refused[FullPagedHeader](shape.error)
  var found = false
  var header = FullPagedHeader(ready: true, chain: chain, selected: selected, physical: epoch,
    ordinary: generation, shape: shape.value, count: roots.len)
  for index, claim in roots:
    # Roots use complete scalar ordering; repeated retained claims cannot expand authority.
    if index > 0 and compareFullHash(array[32, byte](roots[index-1].root),
        array[32, byte](claim.root)) >= 0:
      return refused[FullPagedHeader](FullPagedError.InvalidFormat)
    let empty = array[32, byte](claim.root) == default(array[32, byte])
    if (empty and (claim.entries != 0 or claim.nodes != 0 or claim.valueBytes != 0)) or
        (not empty and (claim.entries == 0 or claim.nodes < claim.entries)) or claim.nodes >
            count or
        claim.valueBytes > payload:
      return refused[FullPagedHeader](FullPagedError.InvalidFormat)
    if array[32, byte](claim.root) == array[32, byte](selected): found = true
    header.roots[index] = claim
  if not found: return refused[FullPagedHeader](FullPagedError.WrongRoot)
  FullPagedResult[FullPagedHeader](status: FullPagedError.None, completed: header)
proc bytes*(header: FullPagedHeader): array[PagedPageBytes, byte] {.requires: header.ready.} =
  ## Encode the entire header page with zero padding and a fixed bounded root inventory.
  result = default(array[PagedPageBytes, byte])
  putMagic(result, if header.shape.contextBytes == 0: HeaderMagic else: ContextHeaderMagic)
  putHash(result, 32, array[32, byte](header.chain))
  put(result, 64, uint64(header.physical))
  put(result, 72, uint64(header.ordinary))
  putHash(result, 80, array[32, byte](header.selected))
  put(result, 112, header.shape.entries)
  put(result, 120, header.shape.payloadBytes)
  put(result, 128, uint64(header.count))
  put(result, 136, header.shape.contextBytes)
  for index in 0..<header.count:
    # At most 64 fixed 56-byte claims fit below the 4096-byte page boundary.
    let offset = 144+index*56
    putHash(result, offset, array[32, byte](header.roots[index].root))
    put(result, offset+32, header.roots[index].entries)
    put(result, offset+40, header.roots[index].nodes)
    put(result, offset+48, header.roots[index].valueBytes)
func decodeFullPagedHeader*(input: openArray[byte], chain: StorageChainId, root: StateRoot,
    limits: PagedLimits, contextLimit = ByteLimit(0)): FullPagedResult[FullPagedHeader] =
  ## Prove exact extent and root-count bounds before interpreting any root offset.
  if input.len != PagedPageBytes: return refused[FullPagedHeader](FullPagedError.InvalidFormat)
  let contextual = uint64(contextLimit) > 0
  let label = if contextual: ContextHeaderMagic else: HeaderMagic
  if not magic(input, label) or (not contextual and not zeros(input, 136, 144)):
    return refused[FullPagedHeader](FullPagedError.InvalidFormat)
  if hashAt(input, 32) != array[32, byte](chain):
    return refused[FullPagedHeader](FullPagedError.WrongChain)
  if hashAt(input, 80) != array[32, byte](root):
    return refused[FullPagedHeader](FullPagedError.WrongRoot)
  let context = number(input, 136)
  if contextual and context == 0:
    return refused[FullPagedHeader](FullPagedError.InvalidFormat) # V2 cannot encode the V1 absence of context.
  if contextual and context > uint64(contextLimit):
    return refused[FullPagedHeader](FullPagedError.LimitExceeded) # Context admission is separate from dataset bytes.
  let count = number(input, 128)
  if count == 0 or count > uint64(FullPagedMaxRoots):
    return refused[FullPagedHeader](FullPagedError.InvalidFormat)
  if not zeros(input, 144+int(count)*56, input.len):
    return refused[FullPagedHeader](FullPagedError.InvalidFormat)
  var roots = default(array[FullPagedMaxRoots, FullPagedRoot])
  for index in 0..<int(count):
    # Count preflight proves all four fixed fields fit the header.
    let offset = 144+index*56
    roots[index] = FullPagedRoot(root: StateRoot(hashAt(input, offset)),
      entries: number(input, offset+32), nodes: number(input, offset+40),
      valueBytes: number(input, offset+48))
  initFullPagedHeader(chain, root, ManagedEpoch(number(input, 64)),
    RepositoryGeneration(number(input, 72)), number(input, 112), number(input, 120),
    roots.toOpenArray(0, int(count)-1), limits, context)
func digest*(row: FullPagedRow): StateNodeHash {.requires: row.ready.} =
  ## A physical address always includes every hash bit.
  row.digest
func offset*(row: FullPagedRow): uint64 {.requires: row.ready.} =
  ## Payload-relative offsets are admitted independently of native file addressing.
  row.start
func byteLength*(row: FullPagedRow): uint64 {.requires: row.ready.} =
  ## Exact span bounds one record transfer.
  row.size
func initFullPagedRow*(shape: PagedGeometry, digest: StateNodeHash, offset,
    size: uint64): FullPagedResult[FullPagedRow] =
  ## Validate subtraction before arithmetic and reject the reserved empty physical identity.
  if not shape.initialized: return refused[FullPagedRow](FullPagedError.Uninitialized)
  if array[32, byte](digest) == default(array[32, byte]) or size < 72 or
      offset > shape.payloadBytes or size > shape.payloadBytes-offset:
    return refused[FullPagedRow](FullPagedError.InvalidFormat)
  FullPagedResult[FullPagedRow](status: FullPagedError.None,
    completed: FullPagedRow(ready: true, digest: digest, start: offset, size: size))
proc bytes*(row: FullPagedRow): array[PagedDescriptorBytes, byte] {.requires: row.ready.} =
  ## A row contains full hash, offset, length and sixteen canonical zero bytes.
  result = default(array[PagedDescriptorBytes, byte])
  putHash(result, 0, array[32, byte](row.digest))
  put(result, 32, row.start)
  put(result, 40, row.size)
func decodeFullPagedRow*(input: openArray[byte], shape: PagedGeometry): FullPagedResult[FullPagedRow] =
  ## Only a complete fixed descriptor can grant a bounded payload span.
  if input.len != PagedDescriptorBytes: return refused[FullPagedRow](FullPagedError.InvalidFormat)
  if not zeros(input, 48, 64): return refused[FullPagedRow](FullPagedError.InvalidFormat)
  initFullPagedRow(shape, StateNodeHash(hashAt(input, 0)), number(input, 32), number(input, 40))
func initFullPagedIndexScan*(shape: PagedGeometry): FullPagedIndexScan =
  ## Default/uninitialized geometry cannot be upgraded by feeding descriptor bytes.
  FullPagedIndexScan(status: (if shape.initialized: FullPagedError.None else:
    FullPagedError.Uninitialized), shape: shape)
proc admit*(scan: var FullPagedIndexScan, input: openArray[byte]): FullPagedResult[FullPagedRow] =
  ## Sticky first refusal prevents resuming after any malformed ordering or coverage prefix.
  if scan.status != FullPagedError.None: return refused[FullPagedRow](scan.status)
  if scan.done or scan.seen >= scan.shape.entries:
    scan.status = FullPagedError.InvalidFormat
    return refused[FullPagedRow](scan.status)
  let decoded = decodeFullPagedRow(input, scan.shape)
  if decoded.error != FullPagedError.None:
    scan.status = decoded.error
    return decoded # No partial row escapes a failed decoder.
  let row = decoded.value
  if row.start != scan.ending or (scan.seen != 0 and compareFullHash(
      array[32, byte](scan.previous), array[32, byte](row.digest)) >= 0):
    scan.status = FullPagedError.InvalidFormat
    return refused[FullPagedRow](scan.status)
  scan.previous = row.digest
  scan.ending += row.size
  inc scan.seen
  decoded
proc finish*(scan: var FullPagedIndexScan): FullPagedError =
  ## Exact cardinality and coverage are mandatory, including the empty index case.
  if scan.status != FullPagedError.None: return scan.status
  if scan.done or scan.seen != scan.shape.entries or scan.ending != scan.shape.payloadBytes:
    scan.status = FullPagedError.InvalidFormat
  scan.done = true
  scan.status
proc hashBytes(input: openArray[byte]): FullPagedResult[FullPagedDigest] =
  ## A backend failure has no fabricated checksum value.
  let hashed = blake2b256(input)
  if hashed.error != CryptoError.None: return refused[FullPagedDigest](
      FullPagedError.BackendFailure)
  FullPagedResult[FullPagedDigest](status: FullPagedError.None,
    completed: FullPagedDigest(array[32, byte](hashed.value)))
proc fullPagedLeafDigest*(shape: PagedGeometry, page: PageOrdinal,
    input: openArray[byte]): FullPagedResult[FullPagedDigest] =
  ## Page-role and extent validation precede fixed workspace hashing in the full-format domain.
  if not shape.initialized: return refused[FullPagedDigest](FullPagedError.Uninitialized)
  if input.len != PagedPageBytes or uint64(page) >= shape.dataPages:
    return refused[FullPagedDigest](FullPagedError.InvalidFormat)
  var scratch = default(array[LeafDomain.len+8+PagedPageBytes, byte])
  for index, character in LeafDomain: scratch[index] = byte(character) # Full schema domain.
  put(scratch, LeafDomain.len, uint64(page))
  for index in 0..<PagedPageBytes: scratch[LeafDomain.len+8+index] = input[index] # Fixed bounded page.
  hashBytes(scratch)
proc fullPagedPaddingDigest*(shape: PagedGeometry, page: PageOrdinal): FullPagedResult[
    FullPagedDigest] =
  ## Nonphysical tree leaves cannot authenticate a real page, even if it is all zero.
  if not shape.initialized: return refused[FullPagedDigest](FullPagedError.Uninitialized)
  if uint64(page) < shape.dataPages or uint64(page) >= shape.treeLeaves:
    return refused[FullPagedDigest](FullPagedError.InvalidFormat)
  var scratch = default(array[PadDomain.len+8, byte])
  for index, character in PadDomain: scratch[index] = byte(character) # Separate padding domain.
  put(scratch, PadDomain.len, uint64(page))
  hashBytes(scratch)
proc fullPagedNodeDigest*(left, right: FullPagedDigest): FullPagedResult[FullPagedDigest] =
  ## Ordered children have a separate full-format internal-node domain.
  var scratch = default(array[NodeDomain.len+64, byte])
  for index, character in NodeDomain: scratch[index] = byte(character) # No cross-schema digest reuse.
  putHash(scratch, NodeDomain.len, array[32, byte](left))
  putHash(scratch, NodeDomain.len+32, array[32, byte](right))
  hashBytes(scratch)
proc encodeFullPagedManifest*(header: FullPagedHeader,
    tree: FullPagedDigest): FullPagedResult[FullPagedManifest] =
  ## Local metadata selects exact full bytes; complete graph authority remains separate.
  if not header.ready: return refused[FullPagedManifest](FullPagedError.Uninitialized)
  FullPagedResult[FullPagedManifest](status: FullPagedError.None,
    completed: FullPagedManifest(ready: true, contextual: header.shape.contextBytes > 0,
      chain: header.chain, selected: header.selected,
      physical: header.physical, ordinary: header.ordinary, pages: header.shape.dataPages,
      extent: header.shape.byteLength, tree: tree))
proc bytes*(manifest: FullPagedManifest): FullPagedResult[array[FullPagedManifestBytes, byte]] =
  ## Hash only the fixed manifest prefix and propagate provider refusal before returning bytes.
  if not manifest.ready: return refused[array[FullPagedManifestBytes, byte]](
      FullPagedError.Uninitialized)
  var output = default(array[FullPagedManifestBytes, byte])
  putMagic(output, if manifest.contextual: ContextManifestMagic else: ManifestMagic)
  putHash(output, 32, array[32, byte](manifest.chain))
  putHash(output, 64, array[32, byte](manifest.selected))
  put(output, 96, uint64(manifest.physical))
  put(output, 104, uint64(manifest.ordinary))
  put(output, 112, manifest.pages)
  put(output, 120, manifest.extent)
  putHash(output, 128, array[32, byte](manifest.tree))
  let sum = hashBytes(output.toOpenArray(0, 159))
  if sum.error != FullPagedError.None: return refused[array[FullPagedManifestBytes, byte]](sum.error)
  putHash(output, 160, array[32, byte](sum.value))
  FullPagedResult[array[FullPagedManifestBytes, byte]](status: FullPagedError.None,
      completed: output)
func root*(manifest: FullPagedManifest): StateRoot {.requires: manifest.ready.} =
  ## Passive selected posterior root becomes usable only after its owning native graph and application context are checked.
  manifest.selected
func pageRoot*(manifest: FullPagedManifest): FullPagedDigest {.requires: manifest.ready.} =
  ## Capture local page authority before any subsequent random read.
  manifest.tree
func epoch*(manifest: FullPagedManifest): ManagedEpoch {.requires: manifest.ready.} =
  ## Read only the admitted positive selection epoch.
  manifest.physical
func byteLength*(manifest: FullPagedManifest): uint64 {.requires: manifest.ready.} =
  ## A native reader must additionally check actual held identity and EOF.
  manifest.extent
proc decodeFullPagedManifest*(input: openArray[byte], header: FullPagedHeader): FullPagedResult[
    FullPagedManifest] =
  ## Exact schema and every header binding precede checksum adoption; no light manifest is accepted.
  if not header.ready: return refused[FullPagedManifest](FullPagedError.Uninitialized)
  if input.len != FullPagedManifestBytes: return refused[FullPagedManifest](
      FullPagedError.InvalidFormat)
  let label = if header.shape.contextBytes > 0: ContextManifestMagic else: ManifestMagic
  if not magic(input, label): return refused[FullPagedManifest](
      FullPagedError.InvalidFormat)
  if hashAt(input, 32) != array[32, byte](header.chain): return refused[FullPagedManifest](
      FullPagedError.WrongChain)
  if hashAt(input, 64) != array[32, byte](header.selected): return refused[FullPagedManifest](
      FullPagedError.WrongRoot)
  let samePosition = number(input, 96) == uint64(header.physical) and
    number(input, 104) == uint64(header.ordinary)
  let sameExtent = number(input, 112) == header.shape.dataPages and
    number(input, 120) == header.shape.byteLength
  if not samePosition or not sameExtent:
    return refused[FullPagedManifest](FullPagedError.InvalidFormat)
  let sum = hashBytes(input.toOpenArray(0, 159))
  if sum.error != FullPagedError.None: return refused[FullPagedManifest](sum.error)
  if array[32, byte](sum.value) != hashAt(input, 160):
    return refused[FullPagedManifest](FullPagedError.ChecksumMismatch)
  encodeFullPagedManifest(header, FullPagedDigest(hashAt(input, 128)))
proc recordHash(record: TrieRecord): FullPagedError =
  ## Exact JAM hashing preserves physical children in transport while applying protocol B masking only here.
  var encoded = default(EncodedStateNode)
  if record.kind == TrieRecordKind.Leaf:
    # Structural callers already bounded and canonicalized the raw leaf payload.
    let leaf = encodeStateLeaf(record.key, record.payload, ByteLimit(uint64(record.payload.len)))
    if leaf.error != StateLayoutError.None: return FullPagedError.BackendFailure
    encoded = leaf.value
  else:
    # Both full edges enter the canonical protocol encoder; no edge bits are discarded from transport.
    encoded = encodeStateBranch(record.left, record.right)
  let hashed = hashStateNode(encoded)
  if hashed.error != StateLayoutError.None: return FullPagedError.BackendFailure
  if array[32, byte](hashed.value) != array[32, byte](
      record.digest): return FullPagedError.HashMismatch
  FullPagedError.None
proc encodeFullPagedRecord*(record: TrieRecord, perValue: ByteLimit): FullPagedResult[seq[byte]] =
  ## Validate every unused field and allocation bound before hashing or encoding one detached record.
  if record.kind notin {TrieRecordKind.Leaf, TrieRecordKind.Branch} or
      array[32, byte](record.digest) == default(array[32, byte]):
    return refused[seq[byte]](FullPagedError.InvalidFormat)
  var size = 97
  if record.kind == TrieRecordKind.Leaf:
    # Each leaf owns one admitted value and no unused physical edges.
    if array[32, byte](record.left) != default(array[32, byte]) or
        array[32, byte](record.right) != default(array[32, byte]):
      return refused[seq[byte]](FullPagedError.InvalidFormat)
    if uint64(record.payload.len) > uint64(perValue) or record.payload.len > high(int)-72:
      return refused[seq[byte]](FullPagedError.LimitExceeded)
    size = 72+record.payload.len
  else:
    # Empty branches and unused leaf bytes have no canonical representation.
    if record.payload.len != 0 or array[31, byte](record.key) != default(array[31, byte]) or
        (array[32, byte](record.left) == default(array[32, byte]) and
          array[32, byte](record.right) == default(array[32, byte])):
      return refused[seq[byte]](FullPagedError.InvalidFormat)
  let reason = recordHash(record)
  if reason != FullPagedError.None: return refused[seq[byte]](reason)
  var output = newSeq[byte](size)
  output[0] = byte(ord(record.kind))
  putHash(output, 1, array[32, byte](record.digest))
  if record.kind == TrieRecordKind.Leaf:
    # The leaf fixed prefix is exactly 72 bytes, including its raw value length.
    let key = array[31, byte](record.key)
    for index in 0..<31: output[33+index] = key[index] # Complete serialized key.
    put(output, 64, uint64(record.payload.len))
    for index in 0..<record.payload.len: output[72+index] = record.payload[index] # Owned bounded copy.
  else:
    # Branch extent is exactly 97 bytes with no spare leaf fields.
    putHash(output, 33, array[32, byte](record.left))
    putHash(output, 65, array[32, byte](record.right))
  FullPagedResult[seq[byte]](status: FullPagedError.None, completed: output)
proc decodeFullPagedRecord*(input: openArray[byte], expected: StateNodeHash,
    perValue: ByteLimit): FullPagedResult[TrieRecord] =
  ## Exact record framing and expected complete address precede bounded allocation and node hashing.
  if input.len < 72 or input[0] > 1: return refused[TrieRecord](FullPagedError.InvalidFormat)
  if hashAt(input, 1) != array[32, byte](expected) or array[32, byte](expected) == default(array[32, byte]):
    return refused[TrieRecord](FullPagedError.HashMismatch)
  var record = TrieRecord(digest: expected)
  if input[0] == 0:
    # Subtraction-based framing refuses truncation/trailing bytes before any value allocation.
    let size = number(input, 64)
    if size != uint64(input.len-72): return refused[TrieRecord](FullPagedError.InvalidFormat)
    if size > uint64(perValue): return refused[TrieRecord](FullPagedError.LimitExceeded)
    var key = default(array[31, byte])
    for index in 0..<31: key[index] = input[33+index] # Complete MSB-routed key.
    record.key = StateKey(key)
    record.payload = newSeq[byte](int(size))
    for index in 0..<int(size): record.payload[index] = input[72+index] # One bounded owned payload.
  else:
    # Branches retain full physical identities even when JAM commits only 255 left bits.
    if input.len != 97: return refused[TrieRecord](FullPagedError.InvalidFormat)
    record.kind = TrieRecordKind.Branch
    record.left = StateNodeHash(hashAt(input, 33))
    record.right = StateNodeHash(hashAt(input, 65))
    if array[32, byte](record.left) == default(array[32, byte]) and
        array[32, byte](record.right) == default(array[32, byte]):
      return refused[TrieRecord](FullPagedError.InvalidFormat)
  let reason = recordHash(record)
  if reason != FullPagedError.None: return refused[TrieRecord](reason)
  FullPagedResult[TrieRecord](status: FullPagedError.None, completed: record)

proc decodeFullPagedSelection*(input: openArray[byte], chain: StorageChainId, root: StateRoot,
    limits: PagedLimits, contextRequired = false): FullPagedResult[FullPagedManifest] =
  ## Bound untrusted CURRENT before opening its epoch; full header/graph binding remains mandatory.
  let label = if contextRequired: ContextManifestMagic else: ManifestMagic
  if input.len != FullPagedManifestBytes or not magic(input, label):
    return refused[FullPagedManifest](FullPagedError.InvalidFormat)
  if hashAt(input, 32) != array[32, byte](chain):
    return refused[FullPagedManifest](FullPagedError.WrongChain)
  if hashAt(input, 64) != array[32, byte](root):
    return refused[FullPagedManifest](FullPagedError.WrongRoot)
  let epoch = number(input, 96)
  let pages = number(input, 112)
  let extent = number(input, 120)
  let maximum = min(uint64(limits.bytes), uint64(high(int)))
  if epoch == 0 or pages == 0: return refused[FullPagedManifest](FullPagedError.InvalidFormat)
  if pages > maximum div 4096: return refused[FullPagedManifest](FullPagedError.LimitExceeded)
  var leaves = 1'u64
  while leaves < pages:
    # Maximum signed byte extent already bounds page count, but doubling is proved independently.
    if leaves > high(uint64) div 2: return refused[FullPagedManifest](FullPagedError.LengthOverflow)
    leaves *= 2
  if leaves > high(uint64) div 2: return refused[FullPagedManifest](FullPagedError.LengthOverflow)
  let body = pages*4096
  let slots = leaves+(leaves-1)
  if slots > (maximum-body) div 32: return refused[FullPagedManifest](FullPagedError.LimitExceeded)
  if extent != body+slots*32: return refused[FullPagedManifest](FullPagedError.InvalidFormat)
  let sum = hashBytes(input.toOpenArray(0, 159))
  if sum.error != FullPagedError.None: return refused[FullPagedManifest](sum.error)
  if array[32, byte](sum.value) != hashAt(input, 160):
    return refused[FullPagedManifest](FullPagedError.ChecksumMismatch)
  FullPagedResult[FullPagedManifest](status: FullPagedError.None,
    completed: FullPagedManifest(ready: true, contextual: contextRequired, chain: chain,
      selected: root,
      physical: ManagedEpoch(epoch), ordinary: RepositoryGeneration(number(input, 104)),
      pages: pages, extent: extent, tree: FullPagedDigest(hashAt(input, 128))))
func generation*(manifest: FullPagedManifest): RepositoryGeneration {.requires: manifest.ready.} =
  ## Read ordinary full-repository generation independently of the physical epoch.
  manifest.ordinary

func initialized*(manifest: FullPagedManifest): bool =
  ## Default selection metadata cannot grant epoch addressing or reclamation authority.
  manifest.ready
