# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fixed-size paged-light metadata and digest paths, without files, resident indexes or proof authority.
## Successful codecs establish shape/integrity only. Strict proof verification and native ownership are separate.
import std/assertions
import ../database_identity
import ../managed/manifest as managed_manifest
import ../light/delta as light_delta
import ../../codec/bounded
import ../../codec/state/[layout as state_layout, trie as state_trie]
import ../../crypto/primitives

const
  PagedPageBytes* = 4096     ## Logical pages are independent of the host's virtual-memory page size.
  PagedDescriptorBytes* = 64 ## Fixed disk-search rows contain one key and one payload-relative span.
  PagedManifestBytes* = 193  ## Exact CURRENT width, including its final local integrity checksum.
  HeaderMagic = "RAGNAROK-LIGHT-PAGED-V1\n"
  ContextHeaderMagic = "RAGNAROK-LIGHT-PAGED-V2\n"
  ManifestMagic = "RAGNAROK-LIGHT-PAGED-MANIFEST-V1\n"
  ContextManifestMagic = "RAGNAROK-LIGHT-PAGED-MANIFEST-V2\n"
  LeafDomain = "RAGNAROK-LIGHT-PAGED-LEAF-V1\n"
  PadDomain = "RAGNAROK-LIGHT-PAGED-PAD-V1\n"
  NodeDomain = "RAGNAROK-LIGHT-PAGED-NODE-V1\n"

type
  PageOrdinal* = distinct uint64 ## A logical data/padding page ordinal, never a byte offset.
  PagedOffset* = distinct uint64 ## Checked physical or payload-relative bytes, never a tree slot.
  PagedDigest* = distinct array[32, byte] ## Local page integrity grants no JAM root or proof authority.
  PagedCodecError* {.pure.} = enum ## Default/failed codecs have no usable scalar or transport payload.
    Uninitialized, None, InvalidFormat, LimitExceeded, LengthOverflow, WrongChain, WrongRoot,
    ChecksumMismatch, BackendFailure
  PagedCodecResult*[T] = object ## Only a complete success carries metadata or detached bytes.
    case status: PagedCodecError
    of None: completed: T
    else: discard
  PagedLimits* = object ## Total dataset ceilings are independent of future page-pool/proof work budgets.
    entries*: ElementLimit
    bytes*: ByteLimit
  PagedGeometry* = object ## Checked addressable extents; no allocation grows with these scalar totals.
    ready: bool
    count, payload, context, indexPages, pages, leaves, slots, extent: uint64
    height: int
  PagedHeader* = object ## Checked shape bound to caller identities, not an authenticated evidence store.
    ready: bool
    chain: StorageChainId
    stateRoot: StateRoot
    physical: ManagedEpoch
    ordinary: LightDeltaSequence
    shape: PagedGeometry
  PagedManifest* = object ## Local checksummed selection metadata; never a sealed artifact capability.
    chain: StorageChainId
    stateRoot: StateRoot
    physical: ManagedEpoch
    ordinary: LightDeltaSequence
    pages, extent: uint64
    tree, integrity: PagedDigest
    contextual: bool
    ready: bool
  PagedDescriptor* = object ## One checked payload span; global ordering/coverage needs a complete index scan.
    ready: bool
    query: StateKey
    start, size: uint64
  PagedIndexScan* = object ## Constant-space first-error ordering/coverage state, with no retained caller bytes.
    status: PagedCodecError
    shape: PagedGeometry
    seen, endOffset: uint64
    previous: StateKey
    finished: bool
  PagedPathStep* = object ## One checked sibling location and its orientation in a postorder tree.
    ready: bool
    offset: PagedOffset
    left: bool
  PagedPath* = object ## Fixed-depth sibling schedule; returned scalar copies own no native resource.
    ready: bool
    steps: array[64, PagedPathStep]
    count: int
    leaf: PagedOffset
  PagedProofShape* = object ## Canonical transport framing only; nodes/value still require state-proof verification.
    ready: bool
    nodes: int
    valueSize: uint64

func error*[T](value: PagedCodecResult[T]): PagedCodecError =
  ## Inspect failure without touching an inactive payload.
  value.status
func value*[T](outcome: PagedCodecResult[T]): T {.inline,
    requires: outcome.status == PagedCodecError.None.} =
  ## Extract only the complete selected alternative.
  outcome.completed
func refused[T](reason: PagedCodecError): PagedCodecResult[T] =
  ## No failed/default result can carry partially decoded metadata.
  PagedCodecResult[T](status: reason)
func initialized*(shape: PagedGeometry): bool =
  ## Default shapes grant no addressing authority.
  shape.ready
func entries*(shape: PagedGeometry): uint64 {.requires: shape.ready.} =
  ## Read the total retained-query count without materializing descriptors.
  shape.count
func payloadBytes*(shape: PagedGeometry): uint64 {.requires: shape.ready.} =
  ## Read the exact unpadded proof transport extent.
  shape.payload
func contextBytes*(shape: PagedGeometry): uint64 {.requires: shape.ready.} =
  ## Opaque context length is independent of proof/graph payload and physical padding.
  shape.context
func contextOffset*(shape: PagedGeometry): PagedOffset {.requires: shape.ready.} =
  ## Geometry preflight bounds the subtraction and multiplication before any context address is exposed.
  let pages = shape.context div 4096+uint64(shape.context mod 4096 != 0)
  PagedOffset((shape.pages-pages)*4096)
func dataPages*(shape: PagedGeometry): uint64 {.requires: shape.ready.} =
  ## Include header, padded index, payload and optional authenticated context pages.
  shape.pages
func treeLeaves*(shape: PagedGeometry): uint64 {.requires: shape.ready.} =
  ## Read the power-of-two leaf extent, including domain-separated padding leaves.
  shape.leaves
func treeDepth*(shape: PagedGeometry): int {.requires: shape.ready.} =
  ## Read the fixed-depth traversal scratch requirement.
  shape.height
func byteLength*(shape: PagedGeometry): uint64 {.requires: shape.ready.} =
  ## Exact EOF includes every postorder digest and no trailing bytes.
  shape.extent
func payloadOffset*(shape: PagedGeometry): PagedOffset {.requires: shape.ready.} =
  ## Geometry preflight proves the padded payload-start multiplication.
  PagedOffset((1+shape.indexPages)*uint64(PagedPageBytes))
func treeOffset*(shape: PagedGeometry): PagedOffset {.requires: shape.ready.} =
  ## Geometry preflight proves the first digest's byte offset.
  PagedOffset(shape.pages*uint64(PagedPageBytes))

func pageTree(pages, maximum: uint64): PagedCodecResult[PagedGeometry] =
  ## Prove all growth, tree and native signed-offset arithmetic before evaluating it.
  if pages == 0: return refused[PagedGeometry](PagedCodecError.InvalidFormat)
  if pages > maximum div uint64(PagedPageBytes):
    return refused[PagedGeometry](PagedCodecError.LimitExceeded)
  var leaves = 1'u64
  var depth = 0
  while leaves < pages:
    # Doubling cannot wrap even for a caller-controlled page count.
    if leaves > high(uint64) div 2: return refused[PagedGeometry](PagedCodecError.LengthOverflow)
    leaves *= 2
    inc depth
  if leaves > high(uint64) div 2: return refused[PagedGeometry](PagedCodecError.LengthOverflow)
  let slots = leaves+(leaves-1)
  let body = pages*uint64(PagedPageBytes)
  if slots > (maximum-body) div 32: return refused[PagedGeometry](PagedCodecError.LimitExceeded)
  PagedCodecResult[PagedGeometry](status: PagedCodecError.None,
    completed: PagedGeometry(ready: true, pages: pages, leaves: leaves, slots: slots,
      extent: body+slots*32, height: depth))
func pagedGeometry*(count, payload: uint64, limits: PagedLimits, context = 0'u64): PagedCodecResult[
    PagedGeometry] =
  ## Separate scalar dataset ceilings from future working-set budgets; never allocate a dataset-sized object.
  if count > uint64(limits.entries): return refused[PagedGeometry](PagedCodecError.LimitExceeded)
  if (count == 0 and payload != 0) or count > payload div 41:
    return refused[PagedGeometry](PagedCodecError.InvalidFormat)
  let maximum = (if uint64(limits.bytes) < uint64(high(int)): uint64(limits.bytes) else: uint64(
      high(int)))
  if count > high(uint64) div 64: return refused[PagedGeometry](PagedCodecError.LengthOverflow)
  let indexBytes = count*64
  let indexPages = indexBytes div 4096+uint64(indexBytes mod 4096 != 0)
  let payloadPages = payload div 4096+uint64(payload mod 4096 != 0)
  if indexPages > high(uint64)-1 or payloadPages > high(uint64)-1-indexPages:
    return refused[PagedGeometry](PagedCodecError.LengthOverflow)
  let dataPages = 1+indexPages+payloadPages
  let contextPages = context div 4096+uint64(context mod 4096 != 0)
  if contextPages > high(uint64)-dataPages:
    return refused[PagedGeometry](PagedCodecError.LengthOverflow) # All section sums are checked before tree growth.
  let checked = pageTree(dataPages+contextPages, maximum)
  if checked.error != PagedCodecError.None: return checked
  var shape = checked.value
  shape.count = count
  shape.payload = payload
  shape.context = context
  shape.indexPages = indexPages
  PagedCodecResult[PagedGeometry](status: PagedCodecError.None, completed: shape)
func number(input: openArray[byte], offset: int, width = 8): uint64 =
  ## Every caller preflights its fixed-width field before this little-endian read.
  result = 0
  for index in 0..<width: result = result or (uint64(input[offset+index]) shl (index*8))
proc put(output: var openArray[byte], offset: int, value: uint64) =
  ## Callers prove the entire eight-byte destination extent.
  for index in 0..<8: output[offset+index] = byte((value shr (index*8)) and 255)
func hashAt(input: openArray[byte], offset: int): array[32, byte] =
  ## Exact header/manifest preflight proves this fixed copy.
  result = default(array[32, byte])
  for index in 0..<32: result[index] = input[offset+index]
proc putHash(output: var openArray[byte], offset: int, value: array[32, byte]) =
  ## Copy a complete scalar identity without retaining a borrowed buffer.
  for index in 0..<32: output[offset+index] = value[index]
func magicMatches(input: openArray[byte], expected: string): bool =
  ## Exact outer size precedes this schema comparison.
  for index, character in expected:
    if input[index] != byte(character): return false
  true
func identities(input: openArray[byte], offset: int, chain: StorageChainId,
    root: StateRoot): PagedCodecError =
  ## Caller-selected chain/root checks happen before any provider call.
  if hashAt(input, offset) != array[32, byte](chain): return PagedCodecError.WrongChain
  if hashAt(input, offset+32) != array[32, byte](root): return PagedCodecError.WrongRoot
  PagedCodecError.None
func initialized*(header: PagedHeader): bool =
  ## Default metadata is not usable by downstream builders.
  header.ready
func geometry*(header: PagedHeader): PagedGeometry {.requires: header.ready.} =
  ## Return only checked scalar extents.
  header.shape
func chainId*(header: PagedHeader): StorageChainId {.requires: header.ready.} =
  ## Return the independent chain binding by value.
  header.chain
func root*(header: PagedHeader): StateRoot {.requires: header.ready.} =
  ## This binding carries no trust-selection decision.
  header.stateRoot
func epoch*(header: PagedHeader): ManagedEpoch {.requires: header.ready.} =
  ## Return the positive physical file epoch.
  header.physical
func sequence*(header: PagedHeader): LightDeltaSequence {.requires: header.ready.} =
  ## Ordinary update sequence is independent of physical epoch.
  header.ordinary
func initPagedHeader*(chain: StorageChainId, root: StateRoot, epoch: ManagedEpoch,
    sequence: LightDeltaSequence, count, payload: uint64,
    limits: PagedLimits, context = 0'u64): PagedCodecResult[PagedHeader] =
  ## Prepare format metadata only; no proof-checked or sealed artifact can be manufactured here.
  if uint64(epoch) == 0: return refused[PagedHeader](PagedCodecError.InvalidFormat)
  let checked = pagedGeometry(count, payload, limits, context)
  if checked.error != PagedCodecError.None: return refused[PagedHeader](checked.error)
  PagedCodecResult[PagedHeader](status: PagedCodecError.None,
    completed: PagedHeader(ready: true, chain: chain, stateRoot: root, physical: epoch,
      ordinary: sequence, shape: checked.value))
proc bytes*(header: PagedHeader): seq[byte] {.requires: header.ready.} =
  ## Allocate one fixed detached page; later mutation cannot alter scalar metadata.
  result = newSeq[byte](PagedPageBytes)
  let label = if header.shape.context == 0: HeaderMagic else: ContextHeaderMagic
  for index, character in label: result[index] = byte(character) # One explicit physical version.
  putHash(result, 24, array[32, byte](header.chain))
  putHash(result, 56, array[32, byte](header.stateRoot))
  put(result, 88, uint64(header.physical))
  put(result, 96, uint64(header.ordinary))
  put(result, 104, header.shape.count)
  put(result, 112, header.shape.payload)
  put(result, 120, header.shape.context)
func decodePagedHeader*(input: openArray[byte], chain: StorageChainId, root: StateRoot,
    limits: PagedLimits, contextLimit = ByteLimit(0)): PagedCodecResult[PagedHeader] =
  ## Require exactly one canonical header page, independent identities and checked dataset geometry.
  if input.len != PagedPageBytes: return refused[PagedHeader](PagedCodecError.InvalidFormat)
  let contextual = uint64(contextLimit) > 0
  let label = if contextual: ContextHeaderMagic else: HeaderMagic
  if not magicMatches(input, label): return refused[PagedHeader](
      PagedCodecError.InvalidFormat)
  let bound = identities(input, 24, chain, root)
  if bound != PagedCodecError.None: return refused[PagedHeader](bound)
  let context = number(input, 120)
  if contextual and context == 0:
    return refused[PagedHeader](PagedCodecError.InvalidFormat) # V2 cannot encode the V1 absence of context.
  if contextual and context > uint64(contextLimit):
    return refused[PagedHeader](PagedCodecError.LimitExceeded) # Context admission is separate from dataset bytes.
  let padding = if contextual: 128 else: 120
  for index in padding..<PagedPageBytes:
    # Every reserved byte is canonical, including the final page byte.
    if input[index] != 0: return refused[PagedHeader](PagedCodecError.InvalidFormat)
  initPagedHeader(chain, root, ManagedEpoch(number(input, 88)),
    LightDeltaSequence(number(input, 96)), number(input, 104), number(input, 112), limits, context)
func initialized*(manifest: PagedManifest): bool =
  ## Default manifests grant no selection metadata.
  manifest.ready
func pageRoot*(manifest: PagedManifest): PagedDigest {.requires: manifest.ready.} =
  ## This local digest authenticates bytes only, never complete-state knowledge.
  manifest.tree
proc manifestPrefix(manifest: PagedManifest): seq[byte] =
  ## Fixed scalar metadata leaves a final checksum slot; private callers ensure initialization.
  result = newSeq[byte](PagedManifestBytes)
  let label = if manifest.contextual: ContextManifestMagic else: ManifestMagic
  for index, character in label: result[index] = byte(
      character) # V1 and V2 CURRENT never substitute for one another.
  putHash(result, 33, array[32, byte](manifest.chain))
  putHash(result, 65, array[32, byte](manifest.stateRoot))
  put(result, 97, uint64(manifest.physical))
  put(result, 105, uint64(manifest.ordinary))
  put(result, 113, manifest.pages)
  put(result, 121, manifest.extent)
  putHash(result, 129, array[32, byte](manifest.tree))
proc bytes*(manifest: PagedManifest): seq[byte] {.requires: manifest.ready.} =
  ## Return detached canonical CURRENT transport, with no native selection authority.
  result = manifestPrefix(manifest)
  putHash(result, 161, array[32, byte](manifest.integrity))
proc encodePagedManifest*(header: PagedHeader, tree: PagedDigest,
    limit: ByteLimit): PagedCodecResult[PagedManifest] =
  ## Encode checked metadata and caller-supplied local digest; sealing/publication remain separate.
  if not header.ready: return refused[PagedManifest](PagedCodecError.Uninitialized)
  if uint64(limit) < uint64(PagedManifestBytes): return refused[PagedManifest](
      PagedCodecError.LimitExceeded)
  var manifest = PagedManifest(ready: true, contextual: header.shape.context > 0,
    chain: header.chain, stateRoot: header.stateRoot,
    physical: header.physical, ordinary: header.ordinary, pages: header.shape.pages,
    extent: header.shape.extent, tree: tree)
  let encoded = manifestPrefix(manifest)
  let hashed = blake2b256(encoded.toOpenArray(0, 160))
  if hashed.error != CryptoError.None: return refused[PagedManifest](PagedCodecError.BackendFailure)
  manifest.integrity = PagedDigest(array[32, byte](hashed.value))
  PagedCodecResult[PagedManifest](status: PagedCodecError.None, completed: manifest)
func chainId*(manifest: PagedManifest): StorageChainId {.requires: manifest.ready.} =
  ## Read the independent expected chain after validating CURRENT's exact metadata schema.
  manifest.chain
func root*(manifest: PagedManifest): StateRoot {.requires: manifest.ready.} =
  ## Caller-supplied root binding remains independent of local integrity.
  manifest.stateRoot
func epoch*(manifest: PagedManifest): ManagedEpoch {.requires: manifest.ready.} =
  ## Select only this positive canonical epoch filename; there is no directory scan or fallback.
  manifest.physical
func sequence*(manifest: PagedManifest): LightDeltaSequence {.requires: manifest.ready.} =
  ## Read ordinary update position independently of the physical filename epoch.
  manifest.ordinary
func dataPages*(manifest: PagedManifest): uint64 {.requires: manifest.ready.} =
  ## Check file-header geometry against this previously decoded selection.
  manifest.pages
func byteLength*(manifest: PagedManifest): uint64 {.requires: manifest.ready.} =
  ## The selected exact EOF includes the complete digest tree.
  manifest.extent
proc decodePagedManifest*(input: openArray[byte], chain: StorageChainId, root: StateRoot,
    limits: PagedLimits, limit: ByteLimit, contextRequired = false): PagedCodecResult[
        PagedManifest] =
  ## Decode CURRENT before opening its epoch file; count/payload policy is checked later against its header.
  if uint64(input.len) > uint64(limit): return refused[PagedManifest](PagedCodecError.LimitExceeded)
  let label = if contextRequired: ContextManifestMagic else: ManifestMagic
  if input.len != PagedManifestBytes or not magicMatches(input, label):
    return refused[PagedManifest](PagedCodecError.InvalidFormat)
  let bound = identities(input, 33, chain, root)
  if bound != PagedCodecError.None: return refused[PagedManifest](bound)
  let epoch = number(input, 97)
  if epoch == 0: return refused[PagedManifest](PagedCodecError.InvalidFormat)
  let pages = number(input, 113)
  let extent = number(input, 121)
  let maximum = if uint64(limits.bytes) < uint64(high(int)): uint64(limits.bytes) else: uint64(high(int))
  let checked = pageTree(pages, maximum)
  if checked.error != PagedCodecError.None: return refused[PagedManifest](checked.error)
  if extent != checked.value.extent: return refused[PagedManifest](PagedCodecError.InvalidFormat)
  let hashed = blake2b256(input.toOpenArray(0, 160))
  if hashed.error != CryptoError.None: return refused[PagedManifest](PagedCodecError.BackendFailure)
  if hashAt(input, 161) != array[32, byte](hashed.value):
    return refused[PagedManifest](PagedCodecError.ChecksumMismatch)
  PagedCodecResult[PagedManifest](status: PagedCodecError.None,
    completed: PagedManifest(ready: true, contextual: contextRequired, chain: chain,
      stateRoot: root,
      physical: ManagedEpoch(epoch), ordinary: LightDeltaSequence(number(input, 105)),
      pages: pages, extent: extent, tree: PagedDigest(hashAt(input, 129)),
      integrity: PagedDigest(hashAt(input, 161))))
func validatePagedBinding*(manifest: PagedManifest, header: PagedHeader): PagedCodecError =
  ## A valid checksum/header alone grants no binding: compare every shared scalar before file admission.
  if not manifest.ready or not header.ready: return PagedCodecError.Uninitialized
  if array[32, byte](manifest.chain) != array[32, byte](
      header.chain): return PagedCodecError.WrongChain
  if array[32, byte](manifest.stateRoot) != array[32, byte](
      header.stateRoot): return PagedCodecError.WrongRoot
  if manifest.contextual != (header.shape.context > 0):
    return PagedCodecError.InvalidFormat # Header and CURRENT must select the same explicit format.
  let epochChanged = uint64(manifest.physical) != uint64(header.physical)
  let sequenceChanged = uint64(manifest.ordinary) != uint64(header.ordinary)
  if epochChanged or sequenceChanged or manifest.pages != header.shape.pages or
      manifest.extent != header.shape.extent:
    return PagedCodecError.InvalidFormat
  PagedCodecError.None
proc decodePagedManifest*(input: openArray[byte], header: PagedHeader,
    limit: ByteLimit): PagedCodecResult[PagedManifest] =
  ## Convenience for a held header; preflight shared scalar mismatch before provider work.
  if not header.ready: return refused[PagedManifest](PagedCodecError.Uninitialized)
  if uint64(input.len) > uint64(limit): return refused[PagedManifest](PagedCodecError.LimitExceeded)
  if input.len != PagedManifestBytes: return refused[PagedManifest](PagedCodecError.InvalidFormat)
  let epoch = number(input, 97)
  let sequence = number(input, 105)
  let pages = number(input, 113)
  let extent = number(input, 121)
  if epoch != uint64(header.physical) or sequence != uint64(header.ordinary) or
      pages != header.shape.pages or extent != header.shape.extent:
    return refused[PagedManifest](PagedCodecError.InvalidFormat)
  let limits = PagedLimits(entries: ElementLimit(header.shape.count), bytes: ByteLimit(
      header.shape.extent))
  decodePagedManifest(input, header.chain, header.stateRoot, limits, limit, header.shape.context > 0)
func key*(descriptor: PagedDescriptor): StateKey {.requires: descriptor.ready.} =
  ## Return the detached serialized query identity.
  descriptor.query
func offset*(descriptor: PagedDescriptor): PagedOffset {.requires: descriptor.ready.} =
  ## This is payload-relative, never a directly usable native seek position.
  PagedOffset(descriptor.start)
func byteLength*(descriptor: PagedDescriptor): uint64 {.requires: descriptor.ready.} =
  ## Return one shape-checked proof-record extent.
  descriptor.size
func initPagedDescriptor*(shape: PagedGeometry, key: StateKey, offset: PagedOffset,
    length: uint64): PagedCodecResult[PagedDescriptor] =
  ## Check exact payload containment before addition; global order/coverage is a separate scan.
  if not shape.ready: return refused[PagedDescriptor](PagedCodecError.Uninitialized)
  let start = uint64(offset)
  if length < 41 or start > shape.payload or length > shape.payload-start:
    return refused[PagedDescriptor](PagedCodecError.InvalidFormat)
  PagedCodecResult[PagedDescriptor](status: PagedCodecError.None,
    completed: PagedDescriptor(ready: true, query: key, start: start, size: length))
proc bytes*(descriptor: PagedDescriptor): seq[byte] {.requires: descriptor.ready.} =
  ## Allocate one detached fixed row; reserved bytes remain zero.
  result = newSeq[byte](PagedDescriptorBytes)
  let raw = array[31, byte](descriptor.query)
  for index in 0..<31: result[index] = raw[index]
  put(result, 31, descriptor.start)
  put(result, 39, descriptor.size)
func decodePagedDescriptor*(input: openArray[byte], shape: PagedGeometry): PagedCodecResult[
    PagedDescriptor] =
  ## Reject every partial/trailing row and nonzero reserved byte before interpreting a span.
  if not shape.ready: return refused[PagedDescriptor](PagedCodecError.Uninitialized)
  if input.len != PagedDescriptorBytes: return refused[PagedDescriptor](
      PagedCodecError.InvalidFormat)
  for index in 47..<64:
    if input[index] != 0: return refused[PagedDescriptor](PagedCodecError.InvalidFormat)
  var key = default(array[31, byte])
  for index in 0..<31: key[index] = input[index]
  initPagedDescriptor(shape, StateKey(key), PagedOffset(number(input, 31)), number(input, 39))
func initPagedIndexScan*(shape: PagedGeometry): PagedIndexScan =
  ## A default shape stays uninitialized; successful state owns only fixed-size scalars.
  if not shape.ready: return PagedIndexScan(status: PagedCodecError.Uninitialized)
  PagedIndexScan(status: PagedCodecError.None, shape: shape)
func compare(left, right: StateKey): int =
  ## Compare every serialized key byte in canonical order.
  let a = array[31, byte](left)
  let b = array[31, byte](right)
  for index in 0..<31:
    if a[index] < b[index]: return -1
    if a[index] > b[index]: return 1
  0
proc admit*(scan: var PagedIndexScan, input: openArray[byte]): PagedCodecResult[PagedDescriptor] =
  ## First failure sticks; no partial global ordering/coverage can be called complete.
  if scan.status != PagedCodecError.None: return refused[PagedDescriptor](scan.status)
  if scan.finished or scan.seen >= scan.shape.count:
    scan.status = PagedCodecError.InvalidFormat
    return refused[PagedDescriptor](scan.status)
  let decoded = decodePagedDescriptor(input, scan.shape)
  if decoded.error != PagedCodecError.None:
    scan.status = decoded.error
    return decoded
  let row = decoded.value
  if row.start != scan.endOffset or (scan.seen > 0 and compare(scan.previous, row.query) >= 0):
    scan.status = PagedCodecError.InvalidFormat
    return refused[PagedDescriptor](scan.status)
  scan.previous = row.query
  scan.endOffset = row.start+row.size
  inc scan.seen
  decoded
proc finish*(scan: var PagedIndexScan): PagedCodecError =
  ## Only an exact once-only full scan covers the declared payload, including an empty dataset.
  if scan.status != PagedCodecError.None: return scan.status
  if scan.finished or scan.seen != scan.shape.count or scan.endOffset != scan.shape.payload:
    scan.status = PagedCodecError.InvalidFormat
  scan.finished = true
  scan.status
func decodePagedProofShape*(input: openArray[byte], row: PagedDescriptor, nodeLimit: ElementLimit,
    valueLimit: ByteLimit): PagedCodecResult[PagedProofShape] =
  ## Inspect just the 41-byte record prefix before allocating nodes/value; no proof is authenticated here.
  if not row.ready: return refused[PagedProofShape](PagedCodecError.Uninitialized)
  if input.len != 41: return refused[PagedProofShape](PagedCodecError.InvalidFormat)
  let key = array[31, byte](row.query)
  for index in 0..<31:
    if input[index] != key[index]: return refused[PagedProofShape](PagedCodecError.InvalidFormat)
  let nodes = number(input, 31, 2)
  let size = number(input, 33)
  if nodes > 249: return refused[PagedProofShape](PagedCodecError.InvalidFormat)
  if nodes > uint64(nodeLimit) or size > uint64(valueLimit):
    return refused[PagedProofShape](PagedCodecError.LimitExceeded)
  let prefix = 41+nodes*64
  if size > high(uint64)-prefix: return refused[PagedProofShape](PagedCodecError.LengthOverflow)
  if prefix+size != row.size: return refused[PagedProofShape](PagedCodecError.InvalidFormat)
  PagedCodecResult[PagedProofShape](status: PagedCodecError.None,
    completed: PagedProofShape(ready: true, nodes: int(nodes), valueSize: size))
func nodes*(shape: PagedProofShape): int {.requires: shape.ready.} =
  ## The transport shape caps canonical proof nodes at 249.
  shape.nodes
func valueBytes*(shape: PagedProofShape): uint64 {.requires: shape.ready.} =
  ## Read the preflighted one-record raw-value extent.
  shape.valueSize
func pagedPath*(shape: PagedGeometry, page: PageOrdinal): PagedCodecResult[PagedPath] =
  ## Derive bottom-up sibling disk positions without a full tree/index; only real pages are queryable.
  if not shape.ready: return refused[PagedPath](PagedCodecError.Uninitialized)
  if uint64(page) >= shape.pages: return refused[PagedPath](PagedCodecError.InvalidFormat)
  var path = PagedPath(ready: true, count: shape.height)
  var width = shape.leaves
  var ordinal = uint64(page)
  var slot = shape.slots-1
  var level = shape.height
  let base = shape.pages*uint64(PagedPageBytes)
  while width > 1:
    # A subtree of width leaves has width-1 slots in each child; these subtractions cannot underflow.
    dec level
    let right = ordinal >= width div 2
    let sibling = if right: slot-width else: slot-1
    path.steps[level] = PagedPathStep(ready: true, offset: PagedOffset(base+sibling*32), left: right)
    if right:
      ordinal -= width div 2
      dec slot
    else:
      slot -= width
    width = width div 2
  path.leaf = PagedOffset(base+slot*32)
  PagedCodecResult[PagedPath](status: PagedCodecError.None, completed: path)
func len*(path: PagedPath): int {.requires: path.ready.} =
  ## Read the exact number of bottom-up sibling hashes required.
  path.count
func leafOffset*(path: PagedPath): PagedOffset {.requires: path.ready.} =
  ## Locate the actual leaf digest in canonical postorder.
  path.leaf
func step*(path: PagedPath, level: int): PagedPathStep {.requires:
    path.ready and level >= 0 and level < path.count.} =
  ## Scalar copies cannot borrow or mutate the path's private scratch.
  path.steps[level]
func offset*(step: PagedPathStep): PagedOffset {.requires: step.ready.} =
  ## Read a computed sibling's absolute file location.
  step.offset
func siblingLeft*(step: PagedPathStep): bool {.requires: step.ready.} =
  ## True means sibling/current, false means current/sibling.
  step.left
proc digest(input: openArray[byte]): PagedCodecResult[PagedDigest] =
  ## Primitive refusal exposes no fabricated default page digest.
  let hashed = blake2b256(input)
  if hashed.error != CryptoError.None: return refused[PagedDigest](PagedCodecError.BackendFailure)
  PagedCodecResult[PagedDigest](status: PagedCodecError.None,
    completed: PagedDigest(array[32, byte](hashed.value)))
proc pagedLeafDigest*(shape: PagedGeometry, page: PageOrdinal,
    input: openArray[byte]): PagedCodecResult[PagedDigest] =
  ## Charge one fixed 4,133-byte domain/page scratch buffer; reject wrong roles/extents before hashing.
  if not shape.ready: return refused[PagedDigest](PagedCodecError.Uninitialized)
  if uint64(page) >= shape.pages or input.len != PagedPageBytes:
    return refused[PagedDigest](PagedCodecError.InvalidFormat)
  var scratch = default(array[LeafDomain.len+8+PagedPageBytes, byte])
  for index, character in LeafDomain: scratch[index] = byte(character)
  put(scratch, LeafDomain.len, uint64(page))
  for index in 0..<PagedPageBytes: scratch[LeafDomain.len+8+index] = input[index]
  digest(scratch)
proc pagedPaddingDigest*(shape: PagedGeometry, page: PageOrdinal): PagedCodecResult[PagedDigest] =
  ## Padding leaves have their own domain and no physical page bytes.
  if not shape.ready: return refused[PagedDigest](PagedCodecError.Uninitialized)
  if uint64(page) < shape.pages or uint64(page) >= shape.leaves:
    return refused[PagedDigest](PagedCodecError.InvalidFormat)
  var scratch = default(array[PadDomain.len+8, byte])
  for index, character in PadDomain: scratch[index] = byte(character)
  put(scratch, PadDomain.len, uint64(page))
  digest(scratch)
proc pagedNodeDigest*(left, right: PagedDigest): PagedCodecResult[PagedDigest] =
  ## Domain-separated ordered children remain local integrity, with fixed scratch independent of dataset size.
  var scratch = default(array[NodeDomain.len+64, byte])
  for index, character in NodeDomain: scratch[index] = byte(character)
  putHash(scratch, NodeDomain.len, array[32, byte](left))
  putHash(scratch, NodeDomain.len+32, array[32, byte](right))
  digest(scratch)
proc verifyPagedPage*(shape: PagedGeometry, page: PageOrdinal, input: openArray[byte],
    siblings: openArray[PagedDigest], expected: PagedDigest): PagedCodecError =
  ## Authenticate fetched bytes to a previously captured digest root, never to a root read from this path.
  let planned = pagedPath(shape, page)
  if planned.error != PagedCodecError.None: return planned.error
  let path = planned.value
  if siblings.len != path.len: return PagedCodecError.InvalidFormat
  let leaf = pagedLeafDigest(shape, page, input)
  if leaf.error != PagedCodecError.None: return leaf.error
  var current = leaf.value
  for level in 0..<path.len:
    # Exact path length proves each sibling access; fixed orientation prevents child permutation.
    let combined = if path.steps[level].left: pagedNodeDigest(siblings[level], current) else:
      pagedNodeDigest(current, siblings[level])
    if combined.error != PagedCodecError.None: return combined.error
    current = combined.value
  if array[32, byte](current) != array[32, byte](expected): return PagedCodecError.ChecksumMismatch
  PagedCodecError.None
