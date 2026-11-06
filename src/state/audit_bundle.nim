# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Decode GP makebundle into package-bound authenticated extrinsics and imported leaves. This certifies input commitments only: erasure origin, historical state and report reproduction remain separate private audit prerequisites.
import ../codec/bounded
import ../codec/work/[package as work_package, report as work_report]
import ../crypto/primitives
import ../pvm/host/fetch as host_fetch
import ./extrinsic_inputs
import "./import/inputs" as import_inputs
import "./import/justification" as import_justification

type
  AuditBundleLimits* = object ## Independent whole-wire/workspace/crypto ceilings cover repeated occurrences; child package policy carries actual consensus gas ceilings.
    package*: PackageConfig
    extrinsics*, imports*, hashes*: ElementLimit
    bytes*, workspaceBytes*, hashBytes*: ByteLimit
  AuditBundleError* {.pure.} = enum ## Local refusals and genuine child failures never expose a verified prefix or a negative-judgment capability.
    Uninitialized, None, InvalidPolicy, LimitExceeded, LengthMismatch, Truncated, TrailingBytes,
    InvalidProof, InvalidLookup, PackageHashMismatch, PackageFailure, ExtrinsicFailure,
    ImportFailure, BindingFailure, HashFailure
  AuditBundleInfo* = object ## Fixed copied work accounting describes input authentication, not original erasure commitment or evaluation validity.
    packageHash*: PackageHash
    wireBytes*, packageBytes*, extrinsicBytes*, witnessBytes*, hashBytes*, workspaceBytes*: uint64
    extrinsics*, imports*, hashes*: uint64
  InputData = ref object ## One acyclic immutable owner retains only maintained package/extrinsic/import certificates.
    inputs: VerifiedImportInputs
    info: AuditBundleInfo
  DecodedAuditBundle* = object ## Default has no authenticated package, including no successful empty-input certificate.
    data: nil InputData
  AuditBundleResult*[T] = object ## Selected failure alternatives contain only their real diagnostics, never successful earlier sections.
    case status: AuditBundleError
    of None: completed: T
    of PackageFailure: packageReason: PackageError
    of ExtrinsicFailure: extrinsicReason: ExtrinsicInputsError
    of ImportFailure: importReason: ImportJustificationError
    of BindingFailure: bindingReason: ImportInputsError
    of HashFailure: hashReason: CryptoError
    else: discard # Ordinary format/policy refusals grant no child or input authority.
  ProofExtent = object ## Fixed scratch points only into the stable synchronously borrowed wire, never a returned owner.
    offset, siblings: int
func error*[T](outcome: AuditBundleResult[T]): AuditBundleError =
  ## Read the selected alternative before extracting a payload or genuine child reason.
  outcome.status
func value*[T](outcome: AuditBundleResult[T]): T {.requires: outcome.status ==
    AuditBundleError.None.} =
  ## Only whole success carries authenticated original inputs or copied accounting facts.
  outcome.completed
func packageError*[T](outcome: AuditBundleResult[T]): PackageError {.requires: outcome.status ==
    AuditBundleError.PackageFailure.} =
  ## Preserve syntax, protocol/local resource and configuration refusals distinctly for the eventual evaluator.
  outcome.packageReason
func extrinsicError*[T](outcome: AuditBundleResult[
    T]): ExtrinsicInputsError {.requires: outcome.status == AuditBundleError.ExtrinsicFailure.} =
  ## Failed exact length/hash binding cannot return a successful extrinsic table.
  outcome.extrinsicReason
func importError*[T](outcome: AuditBundleResult[T]): ImportJustificationError {.requires: outcome.status ==
    AuditBundleError.ImportFailure.} =
  ## A bad proof remains distinct from local hash/workspace/backend refusal.
  outcome.importReason
func bindingError*[T](outcome: AuditBundleResult[T]): ImportInputsError {.requires: outcome.status ==
    AuditBundleError.BindingFailure.} =
  ## Preserve exact dictionary and original-manifest correspondence failures.
  outcome.bindingReason
func hashError*[T](outcome: AuditBundleResult[T]): CryptoError {.requires: outcome.status ==
    AuditBundleError.HashFailure.} =
  ## A primitive backend failure is unavailable evaluation, never a negative report judgment.
  outcome.hashReason
func valid*(limits: AuditBundleLimits): bool =
  ## Defaults activate no decoding or crypto; physical count caps also bound temporary descriptors for zero-length repeated extrinsics.
  uint64(limits.package.refineGas) > 0 and uint64(limits.package.accumulateGas) > 0 and
    uint64(limits.package.maxBytes) > 0 and uint64(limits.package.maxBytes) <= uint64(
        MaxBundleBytes) and
    uint64(limits.bytes) > 0 and uint64(limits.bytes) <= uint64(MaxBundleBytes) and
    uint64(limits.workspaceBytes) > 0 and uint64(limits.workspaceBytes) <= 256'u64*1024*1024 and
    uint64(limits.extrinsics) <= 65536 and uint64(limits.imports) <= 3072 and
    uint64(limits.hashes) > 0 and uint64(limits.hashes) <= 1000000 and
    uint64(limits.hashBytes) > 0 and uint64(limits.hashBytes) <= 256'u64*1024*1024
proc decodedInputs*(bundle: DecodedAuditBundle): AuditBundleResult[VerifiedImportInputs] =
  ## Retain immutable original bindings; callers cannot replace their manifest, dictionary or proof bytes.
  let data = bundle.data
  if data == nil: return AuditBundleResult[VerifiedImportInputs](
      status: AuditBundleError.Uninitialized)
  AuditBundleResult[VerifiedImportInputs](status: AuditBundleError.None, completed: data.inputs)
proc decodedInfo*(bundle: DecodedAuditBundle): AuditBundleResult[AuditBundleInfo] =
  ## A default/failed decoder is not an empty authenticated bundle.
  let data = bundle.data
  if data == nil: return AuditBundleResult[AuditBundleInfo](status: AuditBundleError.Uninitialized)
  AuditBundleResult[AuditBundleInfo](status: AuditBundleError.None, completed: data.info)
proc decodeAuditBundle*(wire: openArray[byte], expected: ReportHeader,
    lookup: openArray[SegmentLookup], limits: AuditBundleLimits): AuditBundleResult[
        DecodedAuditBundle] =
  ## Preflight every section and all cryptographic work before hashing/copying raw tables. Only the package hash and declared bundle length are checked here; complete report reproduction checks the remaining specifier fields.
  template fail(reason: AuditBundleError) =
    return AuditBundleResult[DecodedAuditBundle](status: reason)
  if not limits.valid: fail(AuditBundleError.InvalidPolicy)
  if uint64(wire.len) > uint64(limits.bytes): fail(AuditBundleError.LimitExceeded)
  if uint64(wire.len) != uint64(uint32(expected.bundleLength)): fail(
      AuditBundleError.LengthMismatch)
  if lookup.len > 8: fail(AuditBundleError.InvalidLookup)
  let workspace = uint64(wire.len)*4+4'u64*1024*1024 # The physical wire cap proves multiplication/addition; extra space covers bounded zero-length row descriptors and fixed proof scratch.
  if workspace > uint64(limits.workspaceBytes): fail(AuditBundleError.LimitExceeded)
  let parsed = decodeWorkPackage(wire, limits.package)
  if parsed.error != PackageError.None:
    return AuditBundleResult[DecodedAuditBundle](status: AuditBundleError.PackageFailure,
        packageReason: parsed.error)
  let package = parsed.value.owner
  let described = package.workPackageInfo.value
  var extrinsics = 0'u64
  var imports = 0'u64
  var extrinsicBytes = 0'u64
  for item in 0..<described.items:
    # Child metadata is already owned and protocol-bounded; all local count/byte charges precede raw payload allocation.
    let selected = package.workItemAt(item).value
    let info = selected.workItemInfo.value
    if uint64(info.extrinsics) > uint64(limits.extrinsics)-extrinsics or
        uint64(info.imports) > uint64(limits.imports)-imports: fail(AuditBundleError.LimitExceeded)
    extrinsics += uint64(info.extrinsics)
    imports += uint64(info.imports)
    for ordinal in 0..<info.extrinsics:
      let length = uint64(uint32(selected.extrinsicAt(ordinal).value.length))
      if length > uint64(wire.len)-extrinsicBytes: fail(AuditBundleError.Truncated)
      extrinsicBytes += length
  var cursor = parsed.value.consumed
  if extrinsicBytes > uint64(wire.len-cursor): fail(AuditBundleError.Truncated)
  cursor += int(extrinsicBytes) # Remaining extent proves native narrowing and addition.
  let segmentStart = cursor
  let segmentBytes = imports*4104 # The whole local import count is at most3072 before multiplication.
  if segmentBytes > uint64(wire.len-cursor): fail(AuditBundleError.Truncated)
  cursor += int(segmentBytes)
  var proofs = default(array[3072, ProofExtent])
  var siblings = 0'u64
  for ordinal in 0..<int(imports):
    # A permitted path has0..12 siblings, hence exactly one canonical compact-natural count byte. No alternate-width fallback is accepted.
    if cursor == wire.len: fail(AuditBundleError.Truncated)
    let count = int(wire[cursor])
    inc cursor
    if count > 12: fail(AuditBundleError.InvalidProof)
    if count > (wire.len-cursor) div 32: fail(AuditBundleError.Truncated)
    proofs[ordinal] = ProofExtent(offset: cursor, siblings: count)
    siblings += uint64(count)
    cursor += count*32
  if cursor != wire.len: fail(AuditBundleError.TrailingBytes)
  let hashes = 1+extrinsics+imports+siblings
  let hashBytes = uint64(parsed.value.consumed)+extrinsicBytes+imports*4108+siblings*68
  if hashes > uint64(limits.hashes) or hashBytes > uint64(limits.hashBytes):
    fail(AuditBundleError.LimitExceeded) # Whole-package, every repeated preimage and every imported Merkle path are reserved before the first hash.
  let hashed = blake2b256(wire.toOpenArray(0, parsed.value.consumed-1))
  if hashed.error != CryptoError.None:
    return AuditBundleResult[DecodedAuditBundle](status: AuditBundleError.HashFailure,
        hashReason: hashed.error)
  if array[32, byte](hashed.value) != expected.packageHash.bytes: fail(
      AuditBundleError.PackageHashMismatch)
  var rows = newSeq[seq[seq[byte]]](described.items)
  cursor = parsed.value.consumed
  for item in 0..<rows.len:
    let selected = package.workItemAt(item).value
    rows[item] = newSeq[seq[byte]](selected.workItemInfo.value.extrinsics)
    for ordinal in 0..<rows[item].len:
      # Complete section preflight proves each occurrence, including empty preimages, without length discriminators in the bundle.
      let length = int(uint32(selected.extrinsicAt(ordinal).value.length))
      var bytes = newSeq[byte](length)
      for index in 0..<length: bytes[index] = wire[cursor+index]
      rows[item][ordinal] = bytes
      cursor += length
  let checkedExtrinsics = verifyExtrinsicInputs(package, rows, ExtrinsicInputsLimits(
    entries: ElementLimit(extrinsics), payloadBytes: ByteLimit(extrinsicBytes),
        hashBytes: ByteLimit(extrinsicBytes)))
  if checkedExtrinsics.error != ExtrinsicInputsError.None:
    return AuditBundleResult[DecodedAuditBundle](status: AuditBundleError.ExtrinsicFailure,
        extrinsicReason: checkedExtrinsics.error)
  var leaves = newSeq[seq[VerifiedImport]](described.items)
  cursor = segmentStart
  var occurrence = 0
  for item in 0..<leaves.len:
    let selected = package.workItemAt(item).value
    leaves[item] = newSeq[VerifiedImport](selected.workItemInfo.value.imports)
    for ordinal in 0..<leaves[item].len:
      # Resolve only the original manifest's direct root or exact report lookup key; the maintained binder later checks the complete dictionary key set/order.
      let reference = selected.importAt(ordinal).value
      var root = default(SegmentRoot)
      case reference.kind
      of ImportKind.Root: root = reference.root
      of ImportKind.Package:
        var found = false
        for pair in lookup:
          if pair.packageHash.bytes == reference.package.bytes:
            if found: fail(AuditBundleError.InvalidLookup)
            root = pair.segmentRoot
            found = true
        if not found: fail(AuditBundleError.InvalidLookup)
      var segment = default(array[4104, byte])
      for index in 0..<segment.len: segment[index] = wire[cursor+index]
      cursor += segment.len
      let extent = proofs[occurrence]
      var path = newSeq[SegmentRoot](extent.siblings)
      for level in 0..<path.len:
        for octet in 0..<32: path[level].bytes[octet] = wire[extent.offset+level*32+octet]
      let verified = verifyImportSegment(root, reference.index, FetchSegment(segment), path,
        ImportJustificationLimits(siblings: ElementLimit(12), payloadBytes: ByteLimit(4488),
            hashBytes: ByteLimit(4924)))
      if verified.error != ImportJustificationError.None:
        return AuditBundleResult[DecodedAuditBundle](status: AuditBundleError.ImportFailure,
            importReason: verified.error)
      leaves[item][ordinal] = verified.value
      inc occurrence
  let witnessBytes = segmentBytes+siblings*32
  let bound = bindImportInputs(checkedExtrinsics.value, leaves, lookup,
    ImportInputsLimits(entries: ElementLimit(imports), witnessBytes: ByteLimit(witnessBytes)))
  if bound.error != ImportInputsError.None:
    return AuditBundleResult[DecodedAuditBundle](status: AuditBundleError.BindingFailure,
        bindingReason: bound.error)
  AuditBundleResult[DecodedAuditBundle](status: AuditBundleError.None,
    completed: DecodedAuditBundle(data: InputData(inputs: bound.value,
      info: AuditBundleInfo(packageHash: expected.packageHash, wireBytes: uint64(wire.len),
        packageBytes: uint64(parsed.value.consumed), extrinsicBytes: extrinsicBytes,
        witnessBytes: witnessBytes, hashBytes: hashBytes, workspaceBytes: workspace,
        extrinsics: extrinsics, imports: imports, hashes: hashes))))
