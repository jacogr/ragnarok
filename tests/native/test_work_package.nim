## Focused checked owner lifetimes, complete-output atomicity, alias and context/report consistency tests.
import ../../src/[work_package, work_report, work_digest, composite, bounded]

# Test-only success selection always checks the result branch before accessing a value.
proc checked[T](parsed: PackageResult[T]): T =
  doAssert parsed.error == PackageError.None
  parsed.value

# Small fixed identities and sequences make lifetime/alias failures independent from published fixtures.
proc item(): WorkItem =
  WorkItem(service: ServiceIndex(7), refineGas: Gas(1), accumulateGas: Gas(1), exports: ExportCount(2),
    payload: @[1'u8, 2, 3], imports: @[ImportReference(kind: ImportKind.Package,
      package: PackageHash(), index: ImportIndex(32767))],
    extrinsics: @[ExtrinsicCommitment(length: ExtrinsicLength(16))])

# Every package has two independent item sources, preserving real nested-allocation boundaries.
proc package(): WorkPackage =
  WorkPackage(host: AuthorizerHost(42), authorization: @[7'u8, 8], configuration: @[9'u8], items: @[
      item(), item()])

let config = fullPackageConfig(ByteLimit(32*1024*1024))
var output: array[2048, byte]
var value = package()
let written = checked(encodeWorkPackage(value, config, output))
let parsed = checked(decodeWorkPackage(output.toOpenArray(0, written-1), config))
doAssert parsed.consumed == written and checked(workPackageInfo(parsed.owner)).items == 2
# Mutating the complete original input and all typed source fields cannot affect the captured parent/child.
for i in 0..<output.len: output[i] = 0
value.items[1].payload[0] = 99
let child = checked(workItemAt(parsed.owner, 1))
var payload: array[3, byte]
doAssert checked(copyItemPayload(child, payload)) == 3 and payload == [1'u8, 2, 3]

# Return only the child from a nested scope; its private parent reference must preserve the snapshot under ARC.
proc retainChild(config: PackageConfig): OwnedWorkItem =
  var buffer: array[2048, byte]
  let count = checked(encodeWorkPackage(package(), config, buffer))
  var parent = checked(decodeWorkPackage(buffer.toOpenArray(0, count-1), config)).owner
  result = checked(workItemAt(parent, 1))
  parent = OwnedWorkPackage()
  # Destroy the caller's byte contents before its stack storage/lifetime ends.
  for i in 0..<buffer.len: buffer[i] = 0

let orphan = retainChild(config)
doAssert uint32(checked(workItemInfo(orphan)).service) == 7
doAssert checked(copyItemPayload(orphan, payload)) == 3 and payload == [1'u8, 2, 3]
let reference = checked(importAt(orphan, 0))
doAssert reference.kind == ImportKind.Package and uint16(reference.index) == 32767
doAssert uint32(checked(extrinsicAt(orphan, 0)).length) == 16
var childWire: array[1024, byte]
# Retained item re-emission must leave every unused destination suffix byte unchanged.
for i in 0..<childWire.len: childWire[i] = 0xA5
let childBytes = checked(encodeOwnedWorkItem(orphan, childWire))
doAssert checked(decodeWorkItem(childWire.toOpenArray(0, childBytes-1), config)).consumed == childBytes
for i in childBytes..<childWire.len: doAssert childWire[i] == 0xA5 # Exact owner prefix only.
# Default parent/child handles expose no fabricated zero-length records or extraction privileges.
var absent: OwnedWorkPackage
var absentItem: OwnedWorkItem
doAssert workPackageInfo(absent).error == PackageError.InvalidOwner
doAssert workItemAt(absent, 0).error == PackageError.InvalidOwner
doAssert copyPackageBlob(absent, PackageBlob.Authorization, output).error ==
    PackageError.InvalidOwner
doAssert encodeOwnedWorkPackage(absent, output).error == PackageError.InvalidOwner
doAssert workItemInfo(absentItem).error == PackageError.InvalidOwner
doAssert importAt(absentItem, 0).error == PackageError.InvalidOwner
doAssert extrinsicAt(absentItem, 0).error == PackageError.InvalidOwner
doAssert copyItemPayload(absentItem, output).error == PackageError.InvalidOwner
doAssert encodeOwnedWorkItem(absentItem, output).error == PackageError.InvalidOwner
# A malformed last item must leave earlier package fields and the entire destination unchanged.
value = package()
value.items[1].imports[0].index = ImportIndex(32768)
for i in 0..<output.len: output[i] = 0xA5
let failed = encodeWorkPackage(value, config, output)
doAssert failed.error == PackageError.LimitExceeded
for octet in output: doAssert octet == 0xA5 # Full output remains unchanged on late source failure.
var empty: seq[byte]
doAssert encodeWorkPackage(value, config, empty).error == PackageError.LimitExceeded
# Every immutable extraction/re-emission path checks complete capacity before writing.
doAssert copyItemPayload(orphan, output.toOpenArray(0, 1)).error == PackageError.OutputTooSmall
doAssert copyPackageBlob(parsed.owner, PackageBlob.Authorization, empty).error ==
    PackageError.OutputTooSmall
doAssert encodeOwnedWorkItem(orphan, empty).error == PackageError.OutputTooSmall
doAssert encodeOwnedWorkPackage(parsed.owner, empty).error == PackageError.OutputTooSmall
for octet in output: doAssert octet == 0xA5 # Earlier short-destination failures cannot touch suffix capacity.
# Empty authorization/configuration blobs copy zero bytes without requiring a destination address.
value = package(); value.authorization.setLen(0); value.configuration.setLen(0)
let zeroCount = checked(encodeWorkPackage(value, config, output))
let zeroOwner = checked(decodeWorkPackage(output.toOpenArray(0, zeroCount-1), config)).owner
doAssert checked(copyPackageBlob(zeroOwner, PackageBlob.Authorization, empty)) == 0
# A late payload aliases the destination's beginning: whole-package checks must run before its host/context writes.
value = package()
value.items[1].payload = newSeq[byte](2048)
value.items[1].payload.setLen(3)
let latePayload = cast[ptr UncheckedArray[byte]](addr value.items[1].payload[0])
doAssert encodeWorkPackage(value, config, latePayload.toOpenArray(0, written-1)).error ==
    PackageError.AliasedBuffers
# The same whole-destination rule applies to both authorization blobs' genuine spare backing allocation.
value = package(); value.authorization = newSeq[byte](2048); value.authorization.setLen(2)
let authorization = cast[ptr UncheckedArray[byte]](addr value.authorization[0])
doAssert encodeWorkPackage(value, config, authorization.toOpenArray(0, written-1)).error ==
    PackageError.AliasedBuffers
value = package(); value.configuration = newSeq[byte](2048); value.configuration.setLen(1)
let configuration = cast[ptr UncheckedArray[byte]](addr value.configuration[0])
doAssert encodeWorkPackage(value, config, configuration.toOpenArray(0, written-1)).error ==
    PackageError.AliasedBuffers
# Large fixed import records provide real backing bytes for a standalone item's whole encoded extent.
var single = item()
single.imports = newSeq[ImportReference](128)
var largeOutput = newSeq[byte](128*34+1024)
let itemCount = checked(encodeWorkItem(single, config, largeOutput))
doAssert sizeof(ImportReference)*single.imports.len >= itemCount
let importBytes = cast[ptr UncheckedArray[byte]](addr single.imports[0])
doAssert encodeWorkItem(single, config, importBytes.toOpenArray(0, itemCount-1)).error ==
    PackageError.AliasedBuffers
# Extra genuine commitment backing capacity includes the enclosing item's fixed fields/count prefixes.
single = item(); single.imports.setLen(0)
single.extrinsics = newSeq[ExtrinsicCommitment](132); single.extrinsics.setLen(128)
let xtCount = checked(encodeWorkItem(single, config, largeOutput))
let commitmentBytes = cast[ptr UncheckedArray[byte]](addr single.extrinsics[0])
doAssert encodeWorkItem(single, config, commitmentBytes.toOpenArray(0, xtCount-1)).error ==
    PackageError.AliasedBuffers
# Standalone item descriptors are source storage even without any nested sequence elements.
var bare: WorkItem
let bareBytes = cast[ptr UncheckedArray[byte]](addr bare)
doAssert sizeof(bare) >= 57
doAssert encodeWorkItem(bare, config, bareBytes.toOpenArray(0, 56)).error ==
    PackageError.AliasedBuffers
# The outer package context/descriptors and fixed item records must also survive all output writes.
value = package()
doAssert sizeof(value) >= written
let packageBytes = cast[ptr UncheckedArray[byte]](addr value)
doAssert encodeWorkPackage(value, config, packageBytes.toOpenArray(0, written-1)).error ==
    PackageError.AliasedBuffers
value = WorkPackage(items: newSeq[WorkItem](16))
let outerCount = checked(encodeWorkPackage(value, config, output))
doAssert sizeof(WorkItem)*value.items.len >= outerCount
let outerBytes = cast[ptr UncheckedArray[byte]](addr value.items[0])
doAssert encodeWorkPackage(value, config, outerBytes.toOpenArray(0, outerCount-1)).error ==
    PackageError.AliasedBuffers
# Context/header scalar domains already match reports; compare their fixed bytes without introducing report behavior changes.
var context = RefinementContext(anchorSlot: AnchorSlot(0x12345678), lookupSlot: LookupSlot(0x87654321))
context.lookupStateRoot.bytes[0] = 91
var header = ReportHeader(erasureShards: ErasureShards(6), anchor: context.anchor,
    anchorSlot: context.anchorSlot,
  stateRoot: context.stateRoot, accumulationRoot: context.accumulationRoot,
      lookupAnchor: context.lookupAnchor,
  lookupSlot: context.lookupSlot, lookupStateRoot: context.lookupStateRoot)
var headerBytes: array[272, byte]
doAssert encodeReportHeader(header, headerBytes).error == CompositeError.None
var contextBytes: array[425, byte]
doAssert checked(encodeRefinementContext(context, contextBytes)) == 169
for i in 0..<168: doAssert contextBytes[i] == headerBytes[
    104+i] # Same fixed refinement context wire inside reports.
context.prerequisiteCount = -1
doAssert encodeRefinementContext(context, contextBytes).error == PackageError.LimitExceeded
# Fixed-source context/import/commitment encoders reject legal whole-record physical overlaps before writing.
context = RefinementContext()
let contextAlias = cast[ptr UncheckedArray[byte]](addr context)
doAssert sizeof(context) >= 169
doAssert encodeRefinementContext(context, contextAlias.toOpenArray(0, 168)).error ==
    PackageError.AliasedBuffers
var importValue: ImportReference
let importAlias = cast[ptr UncheckedArray[byte]](addr importValue)
doAssert sizeof(importValue) >= 34
doAssert encodeImportReference(importValue, importAlias.toOpenArray(0, 33)).error ==
    PackageError.AliasedBuffers
var commitment: ExtrinsicCommitment
let commitmentAlias = cast[ptr UncheckedArray[byte]](addr commitment)
doAssert encodeExtrinsicCommitment(commitment, commitmentAlias.toOpenArray(0, 35)).error ==
    PackageError.AliasedBuffers
# Runtime field guards protect both failed results and the wrong nominal import identity alternative.
var guarded = false
try:
  discard decodeWorkPackage(@[255'u8], config).value.consumed
except FieldDefect:
  guarded = true # Failed decode progress cannot be read as a default successful package.
doAssert guarded
var alternativeGuarded = false
try:
  discard reference.root
except FieldDefect:
  alternativeGuarded = true # A package dependency cannot be read as a direct segment root.
doAssert alternativeGuarded
var defaultResult: PackageResult[int]
doAssert defaultResult.error == PackageError.Uninitialized

echo "Nim work-package family: retained child lifetimes, atomicity, aliases and guarded alternatives passed"
