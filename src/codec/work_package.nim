# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 C.2 work-package inputs; see spec/work-package.md for policy and ownership.
##
## Exposes refinement contexts, explicit import alternatives, work-item/package codecs and
## retained item/blob access.

import std/assertions
import ./[natural, bounded, composite, work_digest, work_report]

type
  # Refinement context reuses the nominal anchor/root/slot domains already used in reports.
  RefinementContext* = object
    anchor*: BlockHash
    anchorSlot*: AnchorSlot
    stateRoot*: StateRoot
    accumulationRoot*: AccumulationRoot
    lookupAnchor*: BlockHash
    lookupSlot*: LookupSlot
    lookupStateRoot*: LookupStateRoot
    prerequisites*: array[8, PackageHash]
    prerequisiteCount*: int
  # Segment indices occupy fifteen bits; the remaining E2 bit selects reference identity kind.
  ImportIndex* = distinct uint16
  # Root references need no lookup; package references contribute to the dependency budget.
  ImportKind* {.pure.} = enum
    Root, Package
  # The tagged identity prevents a package hash from being silently used as a segment root.
  ImportReference* = object
    index*: ImportIndex
    case referenceKind: ImportKind
    of Root:
      rootIdentity: SegmentRoot    # A direct export-tree commitment requires no package lookup.
    of Package:
      packageIdentity: PackageHash # A dependency needs resolution to an export-tree commitment.
                                   # Extrinsic input identity is distinct from code/package hashes of the same width.
  ExtrinsicHash* = distinct array[32, byte]
  # Extrinsic input byte count uses fixed E4, independently from sequence counts.
  ExtrinsicLength* = distinct uint32
  # Complete owned fixed commitment fields; preimage availability and hashing are external.
  ExtrinsicCommitment* = object
    hash*: ExtrinsicHash
    length*: ExtrinsicLength
  # The service hosting authorization code is distinct from each work item's destination service.
  AuthorizerHost* = distinct uint32
  # Stable borrowed encoding sources; payload/import/extrinsic sequences cannot change during the call.
  WorkItem* = object
    service*: ServiceIndex
    codeHash*: CodeHash
    refineGas*, accumulateGas*: Gas
    exports*: ExportCount
    payload*: seq[byte]
    imports*: seq[ImportReference]
    extrinsics*: seq[ExtrinsicCommitment]
  # Package encoding sources retain context by value but borrow all nested sequences synchronously.
  WorkPackage* = object
    host*: AuthorizerHost
    codeHash*: CodeHash
    context*: RefinementContext
    authorization*, configuration*: seq[byte]
    items*: seq[WorkItem]
  # Gas ceilings are explicit chain parameters; maxBytes bounds serialized prefix storage separately.
  PackageConfig* = object
    refineGas*, accumulateGas*: Gas
    maxBytes*: ByteLimit
  # Default/failed branches expose only a reason, never a partial record or consumed progress.
  PackageError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, Truncated, NonCanonical, LimitExceeded,
    OutputTooSmall, AliasedBuffers, InvalidOwner, InvalidIndex
  # Application values exist exclusively after selecting the successful branch.
  PackageResult*[T] = object
    case status: PackageError
    of None:
      completed: T # Success alone authorizes access to the complete value.
    else:
      discard      # A failed/default result has no payload or progress.
                   # Fully owned context metadata and exact successful prefix length.
  ContextRead* = object
    value*: RefinementContext
    consumed*: int
  # Fixed records report their exact successful wire consumption without borrowed coordinates.
  ImportRead* = object
    value*: ImportReference
    consumed*: int
  # Fixed commitment decoding is independently available outside a complete work item.
  CommitmentRead* = object
    value*: ExtrinsicCommitment
    consumed*: int
  # Copied item metadata contains lengths rather than detachable payload/import spans.
  ItemInfo* = object
    service*: ServiceIndex
    codeHash*: CodeHash
    refineGas*, accumulateGas*: Gas
    exports*: ExportCount
    payloadBytes*, imports*, extrinsics*, consumed*: int
  # Copied package metadata contains a complete fixed context and owned scalar fields.
  PackageInfo* = object
    host*: AuthorizerHost
    codeHash*: CodeHash
    context*: RefinementContext
    authorizationBytes*, configurationBytes*, items*, consumed*: int
  # Owner-bound package blob selection cannot address arbitrary offsets.
  PackageBlob* {.pure.} = enum
    Authorization, Configuration
  # Only private scan/capture code can associate byte coordinates with immutable snapshot storage.
  ItemLayout = object
    info: ItemInfo
    start, payload, imports, extrinsics: int
  # Fixed sixteen-entry metadata bounds parsing independently from attacker counts.
  Layout = object
    info: PackageInfo
    authorization, configuration: int
    items: array[16, ItemLayout]
  # Private acyclic ARC owner retains exact bytes and their matching validated metadata.
  PackageData = ref object
    wire: seq[byte]
    layout: Layout
  # The package handle exports no mutable wire sequence or detached metadata offsets.
  OwnedWorkPackage* = object
    data: nil PackageData
  # An item retains its complete parent snapshot; the index is private and cannot be rebound by callers.
  OwnedWorkItem* = object
    data: nil PackageData
    index: int
  # Success binds exact package consumption to its immutable owner.
  PackageRead* = object
    owner*: OwnedWorkPackage
    consumed*: int
  # Success binds exact standalone item consumption to its immutable owner.
  ItemRead* = object
    owner*: OwnedWorkItem
    consumed*: int
  # Aggregate counters are private, bounded before addition and discarded on any failure.
  Budget = object
    imports, exports, extrinsics, bundleBytes: int
    refineGas, accumulateGas: uint64
    dependencies: array[8, PackageHash]
    dependencyCount, dependencyLimit: int

const
  # GP checkextractsize/segmentfootprint constants; these are not serialized-byte limits.
  MaxBundleBytes* = 13_791_360
  SegmentFootprint* = 4488

# Read a generic outcome without exposing its private discriminator for mutation.
func error*[T](value: PackageResult[T]): PackageError = value.status
# Only complete operations expose application values, retained owners or progress.
func value*[T](value: PackageResult[T]): T {.inline, requires: value.status == PackageError.None.} =
  value.completed
# Read the selected nominal import role without allowing safe-code retagging.
func kind*(value: ImportReference): ImportKind = value.referenceKind
# Direct-root access requires the corresponding selected identity domain; returned bytes are copied.
func root*(value: ImportReference): SegmentRoot {.inline, requires: value.referenceKind ==
    ImportKind.Root.} =
  value.rootIdentity
# Package-reference access requires a dependency identity; returned bytes are independent copies.
func package*(value: ImportReference): PackageHash {.inline, requires: value.referenceKind ==
    ImportKind.Package.} =
  value.packageIdentity
# Construct a direct-root source; the encoder still validates the supplied fifteen-bit index domain.
func rootImport*(root: SegmentRoot, index: ImportIndex): ImportReference =
  ImportReference(referenceKind: ImportKind.Root, rootIdentity: root, index: index)
# Construct a package dependency source without implicitly converting a segment-root identity.
func packageImport*(package: PackageHash, index: ImportIndex): ImportReference =
  ImportReference(referenceKind: ImportKind.Package, packageIdentity: package, index: index)

# Construct the published full-profile gas ceilings while retaining an explicit caller byte budget.
proc fullPackageConfig*(maxBytes: ByteLimit): PackageConfig {.raises: [].} =
  PackageConfig(refineGas: Gas(5_000_000_000'u64), accumulateGas: Gas(10_000_000),
      maxBytes: maxBytes)

# Zero gas ceilings cannot admit even a zero-gas package under the strict normative inequalities.
proc validConfig(config: PackageConfig): bool {.raises: [].} =
  uint64(config.refineGas) > 0 and uint64(config.accumulateGas) > 0

# Read previously extent-checked E2/E4/E8 scalar octets without a narrowing conversion.
proc scalar(input: openArray[byte], start, width: int): uint64 {.raises: [].} =
  result = 0
  # Every shift stays within the declared eight-byte maximum.
  for i in 0..<width: result = result or (uint64(input[start+i]) shl (8*i))

# Copy fixed identity encodings into owned arrays after their enclosing extent is proved.
proc fixed[N: static[int]](input: openArray[byte], start: int): array[N, byte] {.raises: [].} =
  result = default(array[N, byte])
  # No input pointer escapes this exact-byte value copy.
  for i in 0..<N: result[i] = input[start+i]

# Compare package identities lexicographically for canonical prerequisite ordering.
proc less(a, b: PackageHash): bool {.raises: [].} =
  # The first unequal octet decides ordering; equal complete identities are duplicates.
  for i in 0..<32:
    # Equal prefixes require another byte.
    if a.bytes[i] != b.bytes[i]:
      return a.bytes[i] < b.bytes[i]
  false

# Prove remaining-input extent by division before multiplying an attacker-selected count.
proc extent(input: openArray[byte], cursor, count, stride: int,
    limit: ByteLimit): PackageError {.raises: [].} =
  # Private cursors always remain within the original input, including its one-past endpoint.
  if count > (input.len-cursor) div stride:
    return PackageError.Truncated
  # The product now fits input/host arithmetic, but may still exceed caller resource policy.
  if uint64(cursor+count*stride) > uint64(limit):
    return PackageError.LimitExceeded
  PackageError.None

# Read a bounded canonical natural, keeping partial cursor updates private on failure.
proc number(input: openArray[byte], cursor: var int, ceiling: int,
    limit: ByteLimit): PackageResult[int] {.raises: [].} =
  let parsed = natural.decode(input.toOpenArray(cursor, input.high))
  # Incomplete and overlong encodings remain distinct typed failures.
  if not parsed.ok:
    return PackageResult[int](status: if parsed.error == natural.truncated: PackageError.Truncated
      else: PackageError.NonCanonical) # Multiple encodings of one count are forbidden.
  cursor += int(parsed.consumed)
  # Both prefix cost and unsigned count are bounded before host narrowing.
  if uint64(cursor) > uint64(limit) or uint64(parsed.value) > uint64(ceiling):
    return PackageResult[int](status: PackageError.LimitExceeded)
  PackageResult[int](status: PackageError.None, completed: int(uint64(parsed.value)))

# Validate canonical prerequisite sets before exposing or serializing a context.
proc contextSize(value: RefinementContext): PackageResult[int] {.raises: [].} =
  # The fixed array must not be indexed using an invalid active count.
  if value.prerequisiteCount < 0 or value.prerequisiteCount > 8:
    return PackageResult[int](status: PackageError.LimitExceeded)
  # Sorted unique prerequisites use the same nominal hash domain as work reports.
  for i in 1..<value.prerequisiteCount:
    if not less(value.prerequisites[i-1], value.prerequisites[i]):
      return PackageResult[int](status: PackageError.NonCanonical) # Duplicate/reversed hashes cannot be normalized silently.
  PackageResult[int](status: PackageError.None, completed: 169+32*value.prerequisiteCount)

# Decode a complete fixed context plus bounded prerequisites without input-derived allocation.
proc decodeRefinementContext*(input: openArray[byte]): PackageResult[ContextRead] {.raises: [].} =
  # The complete seven-field fixed prefix must exist before reading any scalar or root.
  if input.len < 168:
    return PackageResult[ContextRead](status: PackageError.Truncated)
  var value: RefinementContext = default(RefinementContext)
  value.anchor = BlockHash(bytes: fixed[32](input, 0))
  value.anchorSlot = AnchorSlot(scalar(input, 32, 4))
  value.stateRoot = StateRoot(bytes: fixed[32](input, 36))
  value.accumulationRoot = AccumulationRoot(bytes: fixed[32](input, 68))
  value.lookupAnchor = BlockHash(bytes: fixed[32](input, 100))
  value.lookupSlot = LookupSlot(scalar(input, 132, 4))
  value.lookupStateRoot = LookupStateRoot(bytes: fixed[32](input, 136))
  var cursor = 168
  let count = number(input, cursor, 8, ByteLimit(high(uint64)))
  # Count framing fails before any prerequisite storage is inspected.
  if count.error != PackageError.None:
    return PackageResult[ContextRead](status: count.error)
  let checked = extent(input, cursor, count.value, 32, ByteLimit(high(uint64)))
  # Every hash must be backed by input before copying fixed prerequisite metadata.
  if checked != PackageError.None:
    return PackageResult[ContextRead](status: checked)
  value.prerequisiteCount = count.value
  # A fixed eight-slot array owns exact prerequisite bytes without retaining input storage.
  for i in 0..<count.value:
    value.prerequisites[i] = PackageHash(bytes: fixed[32](input, cursor))
    cursor += 32
  let measured = contextSize(value)
  # Duplicate or descending prerequisites never publish a successful context.
  if measured.error != PackageError.None:
    return PackageResult[ContextRead](status: measured.error)
  PackageResult[ContextRead](status: PackageError.None, completed: ContextRead(value: value,
      consumed: cursor))

# Write a previously measured scalar; every caller proves destination capacity and exact field width.
proc putScalar(value: uint64, width: int, output: var openArray[byte], cursor: var int) {.raises: [].} =
  # E2/E4/E8 fields are always little-endian, independent of compact count encoding.
  for i in 0..<width:
    output[cursor] = byte((value shr (8*i)) and 255)
    inc cursor

# Commit previously validated exact bytes into a proved destination extent.
proc put(bytes: openArray[byte], output: var openArray[byte], cursor: var int) {.raises: [].} =
  # No write occurs through this helper until the complete operation passes preflight.
  for octet in bytes:
    output[cursor] = octet
    inc cursor

# Commit only the active canonical prefix of a bounded general natural count.
proc putNumber(value: int, output: var openArray[byte], cursor: var int) {.raises: [].} =
  let encoded = natural.encode(JamNatural(value))
  put(encoded.bytes.toOpenArray(0, int(encoded.len)-1), output, cursor)

# Compare address distances without computing potentially overflowing end addresses.
proc overlaps(a: pointer, an: int, b: pointer, bn: int): bool {.raises: [].} =
  # Empty ranges borrow no accessible element address.
  if an == 0 or bn == 0:
    return false
  let left = cast[uint](a)
  let right = cast[uint](b)
  if left <= right: right-left < uint(an) # Measure using the lower source's extent.
  else: left-right < uint(bn) # Reverse the relevant extent for a lower destination.

# Commit a context after independent source validation and whole-operation alias/capacity checks.
proc putContext(value: RefinementContext, output: var openArray[byte], cursor: var int) {.raises: [].} =
  put(value.anchor.bytes, output, cursor)
  putScalar(uint32(value.anchorSlot), 4, output, cursor)
  put(value.stateRoot.bytes, output, cursor)
  put(value.accumulationRoot.bytes, output, cursor)
  put(value.lookupAnchor.bytes, output, cursor)
  putScalar(uint32(value.lookupSlot), 4, output, cursor)
  put(value.lookupStateRoot.bytes, output, cursor)
  putNumber(value.prerequisiteCount, output, cursor)
  # Preserve caller-supplied canonical order rather than sorting identities during encoding.
  for i in 0..<value.prerequisiteCount: put(value.prerequisites[i].bytes, output, cursor)

# Encode standalone context atomically; fixed source storage must remain disjoint from written output.
proc encodeRefinementContext*(value: RefinementContext, output: var openArray[byte]): PackageResult[
    int] {.raises: [].} =
  let measured = contextSize(value)
  # Source errors precede destination sizing and cannot alter caller sentinels.
  if measured.error != PackageError.None:
    return measured
  # Require the whole prefix.
  if output.len < measured.value:
    return PackageResult[int](status: PackageError.OutputTooSmall)
  if overlaps(unsafeAddr value, sizeof(value), addr output[0], measured.value):
    return PackageResult[int](status: PackageError.AliasedBuffers) # Source arrays must survive all writes.
  var cursor = 0
  putContext(value, output, cursor)
  measured

# Decode either legal packed-bit import alternative; the fifteen-bit index has no additional tag byte.
proc decodeImportReference*(input: openArray[byte]): PackageResult[ImportRead] {.raises: [].} =
  # Identity and packed E2 selector/index are one fixed 34-byte record.
  if input.len < 34:
    return PackageResult[ImportRead](status: PackageError.Truncated)
  let packed = uint16(scalar(input, 32, 2))
  let index = ImportIndex(packed and 0x7fff)
  # The high bit changes identity domain rather than offsetting the segment index itself.
  if (packed and 0x8000) == 0:
    return PackageResult[ImportRead](status: PackageError.None, completed: ImportRead(consumed: 34,
      value: rootImport(SegmentRoot(bytes: fixed[32](input, 0)), index)))
  else:
    # Package references require dependency resolution during later guaranteeing/state validation.
    return PackageResult[ImportRead](status: PackageError.None, completed: ImportRead(consumed: 34,
      value: packageImport(PackageHash(bytes: fixed[32](input, 0)), index)))

# Write a preflighted import using its nominal selected identity and packed E2 selector.
proc putImport(value: ImportReference, output: var openArray[byte], cursor: var int) {.raises: [].} =
  case value.kind
  of ImportKind.Root:
    put(value.root.bytes, output, cursor) # Clear selector retains the direct segment-root identity.
    putScalar(uint16(value.index), 2, output, cursor)
  of ImportKind.Package:
    put(value.package.bytes, output, cursor) # Set selector retains the exporting package identity.
    putScalar(uint16(value.index) or 0x8000, 2, output, cursor)

# Atomically encode one fixed import; typed indices still require their fifteen-bit wire domain.
proc encodeImportReference*(value: ImportReference, output: var openArray[byte]): PackageResult[
    int] {.raises: [].} =
  # Validate before any source alias or capacity can authorize a write.
  if uint16(value.index) > 32767:
    return PackageResult[int](status: PackageError.LimitExceeded)
  # Both identity and E2 must fit.
  if output.len < 34:
    return PackageResult[int](status: PackageError.OutputTooSmall)
  if overlaps(unsafeAddr value, sizeof(value), addr output[0], 34):
    return PackageResult[int](status: PackageError.AliasedBuffers) # Reject overlapping fixed source metadata.
  var cursor = 0
  putImport(value, output, cursor)
  PackageResult[int](status: PackageError.None, completed: cursor)

# Decode an opaque input-data hash plus its fixed E4 advertised preimage length.
proc decodeExtrinsicCommitment*(input: openArray[byte]): PackageResult[CommitmentRead] {.raises: [].} =
  # The complete fixed record precedes any hash or length access.
  if input.len < 36:
    return PackageResult[CommitmentRead](status: PackageError.Truncated)
  PackageResult[CommitmentRead](status: PackageError.None, completed: CommitmentRead(consumed: 36,
    value: ExtrinsicCommitment(hash: ExtrinsicHash(fixed[32](input, 0)), length: ExtrinsicLength(
        scalar(input, 32, 4)))))

# Write one previously validated fixed input commitment without checking preimage availability.
proc putCommitment(value: ExtrinsicCommitment, output: var openArray[byte],
    cursor: var int) {.raises: [].} =
  put(array[32, byte](value.hash), output, cursor)
  putScalar(uint32(value.length), 4, output, cursor)

# Encode one complete fixed commitment atomically; per-package footprint accounting occurs in item composition.
proc encodeExtrinsicCommitment*(value: ExtrinsicCommitment, output: var openArray[
    byte]): PackageResult[int] {.raises: [].} =
  # Both fixed fields must fit before examining destination addresses.
  if output.len < 36:
    return PackageResult[int](status: PackageError.OutputTooSmall)
  if overlaps(unsafeAddr value, sizeof(value), addr output[0], 36):
    return PackageResult[int](status: PackageError.AliasedBuffers) # Fixed source bytes remain stable through commit.
  var cursor = 0
  putCommitment(value, output, cursor)
  PackageResult[int](status: PackageError.None, completed: cursor)

# Add nonnegative resources by subtraction before addition, preserving strict gas ceilings without overflow.
proc charge(state: var Budget, imports, exports, extrinsics, bytes: int, refineGas,
    accumulateGas: uint64, config: PackageConfig): PackageError {.raises: [].} =
  # Subtract each bounded count before addition; excessive input never changes the counters.
  if imports > 3072-state.imports or exports > 3072-state.exports:
    return PackageError.LimitExceeded
  # Extrinsic occurrence counts share one package-wide 128-entry budget.
  if extrinsics > 128-state.extrinsics:
    return PackageError.LimitExceeded
  # Advertised/inline bytes must fit the remaining auditable-bundle footprint.
  if bytes > MaxBundleBytes-state.bundleBytes:
    return PackageError.LimitExceeded
  # Strict E8 gas ceilings are compared by remaining budget before any uint64 sum can wrap.
  if refineGas >= uint64(config.refineGas)-state.refineGas:
    return PackageError.LimitExceeded
  # Accumulation gas has its own independent strict package-wide ceiling.
  if accumulateGas >= uint64(config.accumulateGas)-state.accumulateGas:
    return PackageError.LimitExceeded
  state.imports += imports
  state.exports += exports
  state.extrinsics += extrinsics
  state.bundleBytes += bytes
  state.refineGas += refineGas
  state.accumulateGas += accumulateGas
  PackageError.None

# Count distinct package references once across all items, separately from explicit prerequisite count.
proc dependency(state: var Budget, reference: ImportReference): PackageError {.raises: [].} =
  # Direct segment roots do not require a package lookup and consume no dependency slots.
  if reference.kind == ImportKind.Root:
    return PackageError.None
  # Repeated package references, including different segment indices, share one lookup entry.
  for i in 0..<state.dependencyCount:
    # Already counted.
    if reference.package.bytes == state.dependencies[i].bytes:
      return PackageError.None
  # Bound the fixed array first.
  if state.dependencyCount >= state.dependencyLimit:
    return PackageError.LimitExceeded
  state.dependencies[state.dependencyCount] = reference.package
  inc state.dependencyCount
  PackageError.None

# Scan one item into fixed private metadata without allocating payload/import/extrinsic collections.
proc scanItem(input: openArray[byte], cursor: var int, config: PackageConfig,
    state: var Budget): PackageResult[ItemLayout] {.raises: [].} =
  var layout: ItemLayout = default(ItemLayout)
  layout.start = cursor
  let checked = extent(input, cursor, 1, 54, config.maxBytes)
  # E4 service/hash/E8 gas/E8 gas/E2 exports must all exist before scalar interpretation.
  if checked != PackageError.None:
    return PackageResult[ItemLayout](status: checked)
  layout.info.service = ServiceIndex(scalar(input, cursor, 4))
  layout.info.codeHash = CodeHash(fixed[32](input, cursor+4))
  layout.info.refineGas = Gas(scalar(input, cursor+36, 8))
  layout.info.accumulateGas = Gas(scalar(input, cursor+44, 8))
  let exports = int(scalar(input, cursor+52, 2))
  layout.info.exports = ExportCount(exports)
  cursor += 54
  let payload = number(input, cursor, MaxBundleBytes, config.maxBytes)
  # Canonical payload length and complete borrowed payload precede later manifest fields.
  if payload.error != PackageError.None:
    return PackageResult[ItemLayout](status: payload.error)
  let payloadExtent = extent(input, cursor, payload.value, 1, config.maxBytes)
  # No partial payload spans escape.
  if payloadExtent != PackageError.None:
    return PackageResult[ItemLayout](status: payloadExtent)
  layout.payload = cursor
  layout.info.payloadBytes = payload.value
  cursor += payload.value
  let imports = number(input, cursor, 3072, config.maxBytes)
  # Import count bounds multiplication and iteration independently from the remaining input.
  if imports.error != PackageError.None:
    return PackageResult[ItemLayout](status: imports.error)
  let importExtent = extent(input, cursor, imports.value, 34, config.maxBytes)
  # Require complete records.
  if importExtent != PackageError.None:
    return PackageResult[ItemLayout](status: importExtent)
  layout.imports = cursor
  layout.info.imports = imports.value
  # Identity selectors are interpreted only within the previously proved complete manifest extent.
  for i in 0..<imports.value:
    let reference = decodeImportReference(input.toOpenArray(cursor, cursor+33))
    assert reference.error == PackageError.None
    let added = dependency(state, reference.value.value)
    # Distinct dependencies are globally bounded.
    if added != PackageError.None:
      return PackageResult[ItemLayout](status: added)
    cursor += 34
  let extrinsics = number(input, cursor, 128, config.maxBytes)
  # The fixed extrinsic section needs a bounded canonical count and complete backing bytes.
  if extrinsics.error != PackageError.None:
    return PackageResult[ItemLayout](status: extrinsics.error)
  let xtExtent = extent(input, cursor, extrinsics.value, 36, config.maxBytes)
  # Reject incomplete commitment tails.
  if xtExtent != PackageError.None:
    return PackageResult[ItemLayout](status: xtExtent)
  layout.extrinsics = cursor
  layout.info.extrinsics = extrinsics.value
  let charged = charge(state, imports.value, exports, extrinsics.value, payload.value,
      uint64(layout.info.refineGas), uint64(layout.info.accumulateGas), config)
  # Source-independent aggregate limits apply before adding any declared preimage costs.
  if charged != PackageError.None:
    return PackageResult[ItemLayout](status: charged)
  let segmentCost = charge(state, 0, 0, 0, imports.value*SegmentFootprint, 0, 0, config)
  # Counted segments include proof footprint.
  if segmentCost != PackageError.None:
    return PackageResult[ItemLayout](status: segmentCost)
  # Advertised E4 lengths contribute their full value even though data preimages are supplied elsewhere.
  for i in 0..<extrinsics.value:
    let length = scalar(input, cursor+32, 4)
    if length > uint64(MaxBundleBytes-state.bundleBytes):
      return PackageResult[ItemLayout](status: PackageError.LimitExceeded) # Compare unsigned before narrowing E4 on 32-bit hosts.
    state.bundleBytes += int(length)
    cursor += 36
  layout.info.consumed = cursor-layout.start
  PackageResult[ItemLayout](status: PackageError.None, completed: layout)

# Validate every typed item field and aggregate cost before capacity checks or serialization.
proc measureItem(value: WorkItem, config: PackageConfig, state: var Budget): PackageResult[
    int] {.raises: [].} =
  # These ceilings prove all later host arithmetic and loops before reading nested sources.
  if value.payload.len > MaxBundleBytes or value.imports.len > 3072 or value.extrinsics.len > 128 or
      uint64(value.exports) > 3072:
    return PackageResult[int](status: PackageError.LimitExceeded)
  # Preserve import order and duplicates: these are sequences, not canonical sets.
  for reference in value.imports:
    # Enforce fifteen-bit source indices.
    if uint16(reference.index) > 32767:
      return PackageResult[int](status: PackageError.LimitExceeded)
    let added = dependency(state, reference)
    # Count distinct package dependencies globally.
    if added != PackageError.None:
      return PackageResult[int](status: added)
  let charged = charge(state, value.imports.len, int(uint64(value.exports)), value.extrinsics.len,
      value.payload.len, uint64(value.refineGas), uint64(value.accumulateGas), config)
  # Strict aggregate gas/count/byte limits precede writes.
  if charged != PackageError.None:
    return PackageResult[int](status: charged)
  let segmentCost = charge(state, 0, 0, 0, value.imports.len*SegmentFootprint, 0, 0, config)
  # Each import includes its proof footprint.
  if segmentCost != PackageError.None:
    return PackageResult[int](status: segmentCost)
  # Every declared preimage length consumes bundle budget, even for repeated identical commitments.
  for commitment in value.extrinsics:
    let length = uint64(uint32(commitment.length))
    if length > uint64(MaxBundleBytes-state.bundleBytes):
      return PackageResult[int](status: PackageError.LimitExceeded) # Bound before conversion/addition.
    state.bundleBytes += int(length)
  let required = 54+int(natural.encode(JamNatural(value.payload.len)).len)+value.payload.len +
      int(natural.encode(JamNatural(value.imports.len)).len)+34*value.imports.len +
      int(natural.encode(JamNatural(value.extrinsics.len)).len)+36*value.extrinsics.len
  PackageResult[int](status: PackageError.None, completed: required)

# Commit an item only after every source, aggregate, capacity and alias check for the whole operation.
proc putItem(value: WorkItem, output: var openArray[byte], cursor: var int) {.raises: [].} =
  putScalar(uint32(value.service), 4, output, cursor)
  put(array[32, byte](value.codeHash), output, cursor)
  putScalar(uint64(value.refineGas), 8, output, cursor)
  putScalar(uint64(value.accumulateGas), 8, output, cursor)
  putScalar(uint64(value.exports), 2, output, cursor)
  putNumber(value.payload.len, output, cursor)
  put(value.payload, output, cursor)
  putNumber(value.imports.len, output, cursor)
  # Manifest order is semantically significant and is retained exactly.
  for reference in value.imports: putImport(reference, output, cursor)
  putNumber(value.extrinsics.len, output, cursor)
  # No hashing, preimage lookup or sequence reordering occurs during commit.
  for commitment in value.extrinsics: putCommitment(commitment, output, cursor)

# Reject overlap against the entire destination, including later nested sources and earlier output fields.
proc itemAlias(value: WorkItem, output: var openArray[byte], required: int): bool {.raises: [].} =
  # Every source sequence was bounded during measureItem before its byte extent is computed.
  template aliases(items: untyped): bool =
    items.len > 0 and overlaps(unsafeAddr items[0], items.len*sizeof(items[0]), addr output[0], required)
  overlaps(unsafeAddr value, sizeof(value), addr output[0], required) or
    aliases(value.payload) or aliases(value.imports) or aliases(value.extrinsics)

# Encode a standalone item with the same aggregate policy as a one-item package, without auth/context costs.
proc encodeWorkItem*(value: WorkItem, config: PackageConfig, output: var openArray[
    byte]): PackageResult[int] {.raises: [].} =
  # Caller gas domains must admit at least a zero-gas item before source traversal.
  if not validConfig(config):
    return PackageResult[int](status: PackageError.InvalidConfig)
  var state = Budget(dependencyLimit: 8)
  let measured = measureItem(value, config, state)
  # Full source preflight always precedes output capacity.
  if measured.error != PackageError.None:
    return measured
  # Wire storage is separate policy.
  if uint64(measured.value) > uint64(config.maxBytes):
    return PackageResult[int](status: PackageError.LimitExceeded)
  # Require complete output.
  if output.len < measured.value:
    return PackageResult[int](status: PackageError.OutputTooSmall)
  # Include every nested source.
  if itemAlias(value, output, measured.value):
    return PackageResult[int](status: PackageError.AliasedBuffers)
  var cursor = 0
  putItem(value, output, cursor)
  assert cursor == measured.value
  measured

# Capture only validated bytes; no caller pointer or mutable sequence remains in the immutable owner.
proc capture(input: openArray[byte], layout: Layout): PackageData {.raises: [].} =
  result = PackageData(layout: layout, wire: newSeq[byte](layout.info.consumed))
  # Copy the consumed prefix, excluding unrelated trailing bytes.
  for i in 0..<result.wire.len: result.wire[i] = input[i]

# Decode standalone items without allocating before every manifest and aggregate policy has passed.
proc decodeWorkItem*(input: openArray[byte], config: PackageConfig): PackageResult[
    ItemRead] {.raises: [].} =
  # Reject default caller domains first.
  if not validConfig(config):
    return PackageResult[ItemRead](status: PackageError.InvalidConfig)
  var cursor = 0
  var state = Budget(dependencyLimit: 8)
  let scanned = scanItem(input, cursor, config, state)
  # No partial ownership escapes.
  if scanned.error != PackageError.None:
    return PackageResult[ItemRead](status: scanned.error)
  var layout: Layout = default(Layout)
  layout.items[0] = scanned.value
  layout.info.items = 1
  layout.info.consumed = cursor
  PackageResult[ItemRead](status: PackageError.None,
    completed: ItemRead(owner: OwnedWorkItem(data: capture(input, layout), index: 0),
        consumed: cursor))

# Encode a package only after all nested item resources, dependencies and sources pass preflight.
proc encodeWorkPackage*(value: WorkPackage, config: PackageConfig, output: var openArray[
    byte]): PackageResult[int] {.raises: [].} =
  # Validate chain gas domains first.
  if not validConfig(config):
    return PackageResult[int](status: PackageError.InvalidConfig)
  let context = contextSize(value.context)
  # No context normalization or partial writes.
  if context.error != PackageError.None:
    return context
  # Bound the nonempty item sequence before traversing any nested sources.
  if value.items.len < 1 or value.items.len > 16:
    return PackageResult[int](status: PackageError.LimitExceeded)
  # Each blob length must be bounded before adding the shared authorization footprint.
  if value.authorization.len > MaxBundleBytes or value.configuration.len > MaxBundleBytes:
    return PackageResult[int](status: PackageError.LimitExceeded)
  var state = Budget(dependencyLimit: 8-value.context.prerequisiteCount)
  let authCost = charge(state, 0, 0, 0, value.authorization.len+value.configuration.len, 0, 0, config)
  # Auth blobs share the auditable-bundle budget.
  if authCost != PackageError.None:
    return PackageResult[int](status: authCost)
  var required = 36+context.value+1
  required += int(natural.encode(JamNatural(value.authorization.len)).len)+value.authorization.len
  required += int(natural.encode(JamNatural(value.configuration.len)).len)+value.configuration.len
  # Late invalid items must not authorize writes of an earlier valid package prefix.
  for item in value.items:
    let measured = measureItem(item, config, state)
    # Aggregate counters include every earlier item.
    if measured.error != PackageError.None:
      return measured
    required += measured.value
  # Independent wire resource ceiling.
  if uint64(required) > uint64(config.maxBytes):
    return PackageResult[int](status: PackageError.LimitExceeded)
  # Whole package capacity precedes address access.
  if output.len < required:
    return PackageResult[int](status: PackageError.OutputTooSmall)
  # Outer descriptors, item records and both authorization blobs must survive the entire commit.
  template aliases(items: untyped): bool =
    items.len > 0 and overlaps(unsafeAddr items[0], items.len*sizeof(items[0]), addr output[0], required)
  let outerAlias = overlaps(unsafeAddr value, sizeof(value), addr output[0], required)
  # Reject the outer fixed context/descriptors independently of nested sequence storage.
  if outerAlias:
    return PackageResult[int](status: PackageError.AliasedBuffers)
  # Item records contain fixed fields and the nested sequence descriptors used during commit.
  if aliases(value.items):
    return PackageResult[int](status: PackageError.AliasedBuffers)
  # Either borrowed authorization blob must be disjoint from the whole destination.
  if aliases(value.authorization) or aliases(value.configuration):
    return PackageResult[int](status: PackageError.AliasedBuffers)
  # Check each child's sources against the whole destination, not merely that child's output slice.
  for item in value.items:
    # Reject cross-item overlap.
    if itemAlias(item, output, required):
      return PackageResult[int](status: PackageError.AliasedBuffers)
  var cursor = 0
  putScalar(uint32(value.host), 4, output, cursor)
  put(array[32, byte](value.codeHash), output, cursor)
  putContext(value.context, output, cursor)
  putNumber(value.authorization.len, output, cursor)
  put(value.authorization, output, cursor)
  putNumber(value.configuration.len, output, cursor)
  put(value.configuration, output, cursor)
  putNumber(value.items.len, output, cursor)
  # Preflight proved all nested item fields before this first package write.
  for item in value.items: putItem(item, output, cursor)
  assert cursor == required
  PackageResult[int](status: PackageError.None, completed: required)

# Scan/capture the complete package; standalone and embedded items share exactly one structural policy.
proc decodeWorkPackage*(input: openArray[byte], config: PackageConfig): PackageResult[
    PackageRead] {.raises: [].} =
  # Configuration cannot be inferred from bytes.
  if not validConfig(config):
    return PackageResult[PackageRead](status: PackageError.InvalidConfig)
  var layout: Layout = default(Layout)
  var cursor = 0
  let prefix = extent(input, cursor, 1, 36, config.maxBytes)
  # Prove host and authorization-code hash first.
  if prefix != PackageError.None:
    return PackageResult[PackageRead](status: prefix)
  layout.info.host = AuthorizerHost(scalar(input, 0, 4))
  layout.info.codeHash = CodeHash(fixed[32](input, 4))
  cursor = 36
  let context = decodeRefinementContext(input.toOpenArray(cursor, input.high))
  # Malformed contexts never authorize a package.
  if context.error != PackageError.None:
    return PackageResult[PackageRead](status: context.error)
  layout.info.context = context.value.value
  cursor += context.value.consumed
  # A complete context consumes serialized-byte budget before any later auth count is inspected.
  if uint64(cursor) > uint64(config.maxBytes):
    return PackageResult[PackageRead](status: PackageError.LimitExceeded)
  var state = Budget(dependencyLimit: 8-layout.info.context.prerequisiteCount)
  # Both authorization blobs contribute to one package-wide footprint budget before any item scan.
  for field in [PackageBlob.Authorization, PackageBlob.Configuration]:
    let length = number(input, cursor, MaxBundleBytes, config.maxBytes)
    # Bound canonical byte lengths before narrowing.
    if length.error != PackageError.None:
      return PackageResult[PackageRead](status: length.error)
    let blobExtent = extent(input, cursor, length.value, 1, config.maxBytes)
    # Complete blob bytes must be present.
    if blobExtent != PackageError.None:
      return PackageResult[PackageRead](status: blobExtent)
    case field
    of PackageBlob.Authorization:
      layout.authorization = cursor # Metadata is private and remains bound to captured bytes.
      layout.info.authorizationBytes = length.value
    of PackageBlob.Configuration:
      layout.configuration = cursor # This alternative selects a different exact owner-bound blob.
      layout.info.configurationBytes = length.value
    let charged = charge(state, 0, 0, 0, length.value, 0, 0, config)
    # Shared bundle budget includes both blobs.
    if charged != PackageError.None:
      return PackageResult[PackageRead](status: charged)
    cursor += length.value
  let count = number(input, cursor, 16, config.maxBytes)
  # No attacker-derived item allocation.
  if count.error != PackageError.None:
    return PackageResult[PackageRead](status: count.error)
  # Packages require at least one item.
  if count.value == 0:
    return PackageResult[PackageRead](status: PackageError.LimitExceeded)
  layout.info.items = count.value
  # A fixed sixteen-entry layout records only complete validated item metadata.
  for i in 0..<count.value:
    let item = scanItem(input, cursor, config, state)
    # Late manifest errors discard the whole scan.
    if item.error != PackageError.None:
      return PackageResult[PackageRead](status: item.error)
    layout.items[i] = item.value
  layout.info.consumed = cursor
  PackageResult[PackageRead](status: PackageError.None,
    completed: PackageRead(owner: OwnedWorkPackage(data: capture(input, layout)), consumed: cursor))

# Select private retained item coordinates only through their original parent snapshot.
proc selected(owner: OwnedWorkItem): PackageResult[ItemLayout] {.raises: [].} =
  # Defaults carry no validated bytes.
  let data = owner.data
  if data == nil:
    return PackageResult[ItemLayout](status: PackageError.InvalidOwner)
  if owner.index < 0 or owner.index >= data.layout.info.items:
    return PackageResult[ItemLayout](status: PackageError.InvalidIndex) # Defensive guard for private handle invariants.
  PackageResult[ItemLayout](status: PackageError.None, completed: data.layout.items[owner.index])

# Copy fixed package metadata; callers cannot modify retained context or sequence storage.
proc workPackageInfo*(owner: OwnedWorkPackage): PackageResult[PackageInfo] {.raises: [].} =
  # Reject uninitialized owners.
  let data = owner.data
  if data == nil:
    return PackageResult[PackageInfo](status: PackageError.InvalidOwner)
  PackageResult[PackageInfo](status: PackageError.None, completed: data.layout.info)

# Retain an owner-bound child handle without copying/exposing wire or detached spans.
proc workItemAt*(owner: OwnedWorkPackage, index: int): PackageResult[OwnedWorkItem] {.raises: [].} =
  # Default owners do not describe empty packages.
  let data = owner.data
  if data == nil:
    return PackageResult[OwnedWorkItem](status: PackageError.InvalidOwner)
  if index < 0 or index >= data.layout.info.items:
    return PackageResult[OwnedWorkItem](status: PackageError.InvalidIndex) # Signed bounds precede metadata selection.
  PackageResult[OwnedWorkItem](status: PackageError.None, completed: OwnedWorkItem(data: data, index: index))

# Copy item scalar metadata/lengths without allowing callers to rebind its private coordinates.
proc workItemInfo*(owner: OwnedWorkItem): PackageResult[ItemInfo] {.raises: [].} =
  let item = selected(owner)
  # No partial metadata on invalid handles.
  if item.error != PackageError.None:
    return PackageResult[ItemInfo](status: item.error)
  PackageResult[ItemInfo](status: PackageError.None, completed: item.value.info)

# Copy one exact import value from its retained item's manifest.
proc importAt*(owner: OwnedWorkItem, index: int): PackageResult[ImportReference] {.raises: [].} =
  # Retain the exact backing snapshot independently of nested selector calls.
  let data = owner.data
  if data == nil: return PackageResult[ImportReference](status: PackageError.InvalidOwner)
  let item = selected(owner)
  # Select the owner before offsets.
  if item.error != PackageError.None:
    return PackageResult[ImportReference](status: item.error)
  if index < 0 or index >= item.value.info.imports:
    return PackageResult[ImportReference](status: PackageError.InvalidIndex) # Never narrow or multiply an invalid index.
  let start = item.value.imports+34*index
  let parsed = decodeImportReference(data.wire.toOpenArray(start, start+33))
  assert parsed.error == PackageError.None
  PackageResult[ImportReference](status: PackageError.None, completed: parsed.value.value)

# Copy a fixed input commitment through the same parent-bound item identity.
proc extrinsicAt*(owner: OwnedWorkItem, index: int): PackageResult[ExtrinsicCommitment] {.raises: [].} =
  # Retain the exact backing snapshot independently of nested selector calls.
  let data = owner.data
  if data == nil: return PackageResult[ExtrinsicCommitment](status: PackageError.InvalidOwner)
  let item = selected(owner)
  # Invalid handles carry no bytes.
  if item.error != PackageError.None:
    return PackageResult[ExtrinsicCommitment](status: item.error)
  if index < 0 or index >= item.value.info.extrinsics:
    return PackageResult[ExtrinsicCommitment](status: PackageError.InvalidIndex) # Bounds precede address arithmetic.
  let start = item.value.extrinsics+36*index
  let parsed = decodeExtrinsicCommitment(data.wire.toOpenArray(start, start+35))
  assert parsed.error == PackageError.None
  PackageResult[ExtrinsicCommitment](status: PackageError.None, completed: parsed.value.value)

# Copy one prevalidated private byte interval atomically; offsets never cross the public boundary.
proc copy(data: PackageData, start, length: int, output: var openArray[byte]): PackageResult[
    int] {.raises: [].} =
  # Complete destination before any write.
  if output.len < length:
    return PackageResult[int](status: PackageError.OutputTooSmall)
  if length > 0 and overlaps(unsafeAddr data.wire[0], data.wire.len, addr output[0], length):
    return PackageResult[int](status: PackageError.AliasedBuffers) # Protect immutable retained storage even from foreign fabricated buffers.
  # Empty blobs touch no source/destination addresses; nonempty intervals were proved during scan.
  for i in 0..<length: output[i] = data.wire[start+i]
  PackageResult[int](status: PackageError.None, completed: length)

# Copy the item's payload, selected only by the matching retained owner.
proc copyItemPayload*(owner: OwnedWorkItem, output: var openArray[byte]): PackageResult[
    int] {.raises: [].} =
  # Retain the exact backing snapshot independently of nested selector calls.
  let data = owner.data
  if data == nil: return PackageResult[int](status: PackageError.InvalidOwner)
  let item = selected(owner)
  # No default payload for invalid owners.
  if item.error != PackageError.None:
    return PackageResult[int](status: item.error)
  copy(data, item.value.payload, item.value.info.payloadBytes, output)

# Copy authorization/configuration bytes without exporting a mutable snapshot or arbitrary span.
proc copyPackageBlob*(owner: OwnedWorkPackage, field: PackageBlob, output: var openArray[
    byte]): PackageResult[int] {.raises: [].} =
  # Default handles cannot authorize extraction.
  let data = owner.data
  if data == nil:
    return PackageResult[int](status: PackageError.InvalidOwner)
  case field
  of PackageBlob.Authorization:
    copy(data, data.layout.authorization, data.layout.info.authorizationBytes,
        output) # Exact auth-token interval.
  of PackageBlob.Configuration:
    copy(data, data.layout.configuration, data.layout.info.configurationBytes,
        output) # Exact code-configuration interval.

# Re-emit one retained item atomically, independently of the parent package handle's lifetime.
proc encodeOwnedWorkItem*(owner: OwnedWorkItem, output: var openArray[byte]): PackageResult[
    int] {.raises: [].} =
  # Retain the exact backing snapshot independently of nested selector calls.
  let data = owner.data
  if data == nil: return PackageResult[int](status: PackageError.InvalidOwner)
  let item = selected(owner)
  # Reject invalid handles before extraction.
  if item.error != PackageError.None:
    return PackageResult[int](status: item.error)
  copy(data, item.value.start, item.value.info.consumed, output)

# Re-emit the complete immutable package prefix while preserving unrelated destination suffix bytes.
proc encodeOwnedWorkPackage*(owner: OwnedWorkPackage, output: var openArray[byte]): PackageResult[
    int] {.raises: [].} =
  # No fabricated empty package for defaults.
  let data = owner.data
  if data == nil:
    return PackageResult[int](status: PackageError.InvalidOwner)
  copy(data, 0, data.layout.info.consumed, output)
