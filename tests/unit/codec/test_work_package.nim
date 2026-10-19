# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Focused checked owner lifetimes, complete-output atomicity, alias and context/report
## consistency tests.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

# @@Verification={"arc": "package_arc_release"}

import ../../support/arc_evidence
import std/[assertions, syncio]
import ../../../src/codec/[work_package, work_report, work_digest, composite, bounded]

# Test-only success selection always checks the result branch before accessing a value.
proc checked[T](parsed: PackageResult[T]): T =
  assert parsed.error == PackageError.None
  parsed.value

# Small fixed identities and sequences make lifetime/alias failures independent from published fixtures.
proc item(): WorkItem =
  WorkItem(service: ServiceIndex(7), refineGas: Gas(1), accumulateGas: Gas(1), exports: ExportCount(2),
    payload: @[1'u8, 2, 3], imports: @[packageImport(PackageHash(), ImportIndex(32767))],
    extrinsics: @[ExtrinsicCommitment(length: ExtrinsicLength(16))])

# Every package has two independent item sources, preserving real nested-allocation boundaries.
proc package(): WorkPackage =
  WorkPackage(host: AuthorizerHost(42), authorization: @[7'u8, 8], configuration: @[9'u8], items: @[
      item(), item()])

let config = fullPackageConfig(ByteLimit(32*1024*1024))
var output: array[2048, byte] = default(array[2048, byte])
var value = package()
let written = checked(encodeWorkPackage(value, config, output))
let parsed = checked(decodeWorkPackage(output.toOpenArray(0, written-1), config))
assert parsed.consumed == written and checked(workPackageInfo(parsed.owner)).items == 2
# Mutating the complete original input and all typed source fields cannot affect the captured parent/child.
for i in 0..<output.len: output[i] = 0
value.items[1].payload[0] = 99
let child = checked(workItemAt(parsed.owner, 1))
var payload: array[3, byte] = default(array[3, byte])
assert checked(copyItemPayload(child, payload)) == 3 and payload == [1'u8, 2, 3]

# Return only the child from a nested scope; its private parent reference must preserve the snapshot under ARC.
proc retainChild(config: PackageConfig): OwnedWorkItem =
  var buffer: array[2048, byte] = default(array[2048, byte])
  let count = checked(encodeWorkPackage(package(), config, buffer))
  var parent = checked(decodeWorkPackage(buffer.toOpenArray(0, count-1), config)).owner
  result = checked(workItemAt(parent, 1))
  parent = OwnedWorkPackage()
  # Destroy the caller's byte contents before its stack storage/lifetime ends.
  for i in 0..<buffer.len: buffer[i] = 0

let orphan = retainChild(config)
assert uint32(checked(workItemInfo(orphan)).service) == 7
assert checked(copyItemPayload(orphan, payload)) == 3 and payload == [1'u8, 2, 3]
let reference = checked(importAt(orphan, 0))
assert reference.kind == ImportKind.Package and uint16(reference.index) == 32767
assert uint32(checked(extrinsicAt(orphan, 0)).length) == 16
var childWire: array[1024, byte] = default(array[1024, byte])
# Retained item re-emission must leave every unused destination suffix byte unchanged.
for i in 0..<childWire.len: childWire[i] = 0xA5
let childBytes = checked(encodeOwnedWorkItem(orphan, childWire))
assert checked(decodeWorkItem(childWire.toOpenArray(0, childBytes-1), config)).consumed == childBytes
for i in childBytes..<childWire.len: assert childWire[i] == 0xA5 # Exact owner prefix only.
# Default parent/child handles expose no fabricated zero-length records or extraction privileges.
var absent: OwnedWorkPackage = default(OwnedWorkPackage)
var absentItem: OwnedWorkItem = default(OwnedWorkItem)
assert workPackageInfo(absent).error == PackageError.InvalidOwner
assert workItemAt(absent, 0).error == PackageError.InvalidOwner
assert copyPackageBlob(absent, PackageBlob.Authorization, output).error ==
    PackageError.InvalidOwner
assert encodeOwnedWorkPackage(absent, output).error == PackageError.InvalidOwner
assert workItemInfo(absentItem).error == PackageError.InvalidOwner
assert importAt(absentItem, 0).error == PackageError.InvalidOwner
assert extrinsicAt(absentItem, 0).error == PackageError.InvalidOwner
assert copyItemPayload(absentItem, output).error == PackageError.InvalidOwner
assert encodeOwnedWorkItem(absentItem, output).error == PackageError.InvalidOwner
# A malformed last item must leave earlier package fields and the entire destination unchanged.
value = package()
value.items[1].imports[0].index = ImportIndex(32768)
for i in 0..<output.len: output[i] = 0xA5
let failed = encodeWorkPackage(value, config, output)
assert failed.error == PackageError.LimitExceeded
for octet in output: assert octet == 0xA5 # Full output remains unchanged on late source failure.
var empty: seq[byte] = default(seq[byte])
assert encodeWorkPackage(value, config, empty).error == PackageError.LimitExceeded
# Every immutable extraction/re-emission path checks complete capacity before writing.
assert copyItemPayload(orphan, output.toOpenArray(0, 1)).error == PackageError.OutputTooSmall
assert copyPackageBlob(parsed.owner, PackageBlob.Authorization, empty).error ==
    PackageError.OutputTooSmall
assert encodeOwnedWorkItem(orphan, empty).error == PackageError.OutputTooSmall
assert encodeOwnedWorkPackage(parsed.owner, empty).error == PackageError.OutputTooSmall
for octet in output: assert octet == 0xA5 # Earlier short-destination failures cannot touch suffix capacity.
# Empty authorization/configuration blobs copy zero bytes without requiring a destination address.
value = package(); value.authorization.setLen(0); value.configuration.setLen(0)
let zeroCount = checked(encodeWorkPackage(value, config, output))
let zeroOwner = checked(decodeWorkPackage(output.toOpenArray(0, zeroCount-1), config)).owner
assert checked(copyPackageBlob(zeroOwner, PackageBlob.Authorization, empty)) == 0
# A late payload aliases the destination's beginning: whole-package checks must run before its host/context writes.
value = package()
value.items[1].payload = newSeq[byte](2048)
value.items[1].payload.setLen(3)
let latePayload = cast[ptr array[2048, byte]](addr value.items[1].payload[0])
assert encodeWorkPackage(value, config, latePayload[].toOpenArray(0, written-1)).error ==
    PackageError.AliasedBuffers
# The same whole-destination rule applies to both authorization blobs' genuine spare backing allocation.
value = package(); value.authorization = newSeq[byte](2048); value.authorization.setLen(2)
let authorization = cast[ptr array[2048, byte]](addr value.authorization[0])
assert encodeWorkPackage(value, config, authorization[].toOpenArray(0, written-1)).error ==
    PackageError.AliasedBuffers
value = package(); value.configuration = newSeq[byte](2048); value.configuration.setLen(1)
let configuration = cast[ptr array[2048, byte]](addr value.configuration[0])
assert encodeWorkPackage(value, config, configuration[].toOpenArray(0, written-1)).error ==
    PackageError.AliasedBuffers
# Large fixed import records provide real backing bytes for a standalone item's whole encoded extent.
var single = item()
single.imports = newSeq[ImportReference](128)
var largeOutput = newSeq[byte](128*34+1024)
let itemCount = checked(encodeWorkItem(single, config, largeOutput))
assert sizeof(ImportReference)*single.imports.len >= itemCount
let importBytes = cast[ptr array[128*sizeof(ImportReference), byte]](addr single.imports[0])
assert encodeWorkItem(single, config, importBytes[].toOpenArray(0, itemCount-1)).error ==
    PackageError.AliasedBuffers
# Extra genuine commitment backing capacity includes the enclosing item's fixed fields/count prefixes.
single = item(); single.imports.setLen(0)
single.extrinsics = newSeq[ExtrinsicCommitment](132); single.extrinsics.setLen(128)
let xtCount = checked(encodeWorkItem(single, config, largeOutput))
let commitmentBytes = cast[ptr array[132*sizeof(ExtrinsicCommitment), byte]](addr single.extrinsics[0])
assert encodeWorkItem(single, config, commitmentBytes[].toOpenArray(0, xtCount-1)).error ==
    PackageError.AliasedBuffers
# Standalone item descriptors are source storage even without any nested sequence elements.
var bare: WorkItem = default(WorkItem)
let bareBytes = cast[ptr array[sizeof(WorkItem), byte]](addr bare)
assert sizeof(bare) >= 57
assert encodeWorkItem(bare, config, bareBytes[].toOpenArray(0, 56)).error ==
    PackageError.AliasedBuffers
# The outer package context/descriptors and fixed item records must also survive all output writes.
value = package()
assert sizeof(value) >= written
let packageBytes = cast[ptr array[sizeof(WorkPackage), byte]](addr value)
assert encodeWorkPackage(value, config, packageBytes[].toOpenArray(0, written-1)).error ==
    PackageError.AliasedBuffers
value = WorkPackage(items: newSeq[WorkItem](16))
let outerCount = checked(encodeWorkPackage(value, config, output))
assert sizeof(WorkItem)*value.items.len >= outerCount
let outerBytes = cast[ptr array[16*sizeof(WorkItem), byte]](addr value.items[0])
assert encodeWorkPackage(value, config, outerBytes[].toOpenArray(0, outerCount-1)).error ==
    PackageError.AliasedBuffers
# Context/header scalar domains already match reports; compare their fixed bytes without introducing report behavior changes.
var context = RefinementContext(anchorSlot: AnchorSlot(0x12345678), lookupSlot: LookupSlot(0x87654321))
context.lookupStateRoot.bytes[0] = 91
var header = ReportHeader(erasureShards: ErasureShards(6), anchor: context.anchor,
    anchorSlot: context.anchorSlot,
  stateRoot: context.stateRoot, accumulationRoot: context.accumulationRoot,
      lookupAnchor: context.lookupAnchor,
  lookupSlot: context.lookupSlot, lookupStateRoot: context.lookupStateRoot)
var headerBytes: array[272, byte] = default(array[272, byte])
assert encodeReportHeader(header, headerBytes).error == CompositeError.None
var contextBytes: array[425, byte] = default(array[425, byte])
assert checked(encodeRefinementContext(context, contextBytes)) == 169
for i in 0..<168: assert contextBytes[i] == headerBytes[
    104+i] # Same fixed refinement context wire inside reports.
context.prerequisiteCount = -1
assert encodeRefinementContext(context, contextBytes).error == PackageError.LimitExceeded
# Fixed-source context/import/commitment encoders reject legal whole-record physical overlaps before writing.
context = RefinementContext()
let contextAlias = cast[ptr array[sizeof(RefinementContext), byte]](addr context)
assert sizeof(context) >= 169
assert encodeRefinementContext(context, contextAlias[].toOpenArray(0, 168)).error ==
    PackageError.AliasedBuffers
var importValue: ImportReference = default(ImportReference)
let importAlias = cast[ptr array[sizeof(ImportReference), byte]](addr importValue)
assert sizeof(importValue) >= 34
assert encodeImportReference(importValue, importAlias[].toOpenArray(0, 33)).error ==
    PackageError.AliasedBuffers
var commitment: ExtrinsicCommitment = default(ExtrinsicCommitment)
let commitmentAlias = cast[ptr array[sizeof(ExtrinsicCommitment), byte]](addr commitment)
assert encodeExtrinsicCommitment(commitment, commitmentAlias[].toOpenArray(0, 35)).error ==
    PackageError.AliasedBuffers
# Failed results and wrong import alternatives are checked in independent exact-contract subprocesses.
assert decodeWorkPackage(@[255'u8], config).error == PackageError.Truncated
var defaultResult: PackageResult[int] = default(PackageResult[int])
assert defaultResult.error == PackageError.Uninitialized

# Import getters return copied nominal identities and keep default Root behavior explicit.
let defaultImport = default(ImportReference)
assert defaultImport.kind == ImportKind.Root and defaultImport.root.bytes == default(array[32, byte])
var rootIdentity = defaultImport.root
rootIdentity.bytes[0] = 91
assert defaultImport.root.bytes[0] == 0
var packageIdentity = reference.package
packageIdentity.bytes[0] = 91
assert reference.package.bytes[0] == 0

# Capture equal-sized snapshots whose payloads, context and manifest identities differ visibly.
proc captureParent(marker: byte): OwnedWorkPackage =
  var source = package()
  source.authorization[0] = marker
  source.configuration[0] = marker
  source.context.anchorSlot = AnchorSlot(uint32(marker))
  var identity = default(array[32, byte])
  identity[0] = marker
  # Both items deliberately share one dependency identity, preserving the original budget semantics.
  for entry in source.items.mitems:
    entry.payload[0] = marker
    entry.imports[0] = packageImport(PackageHash(bytes: identity), ImportIndex(32767))
    entry.extrinsics[0].hash = ExtrinsicHash(identity)
  var wire = default(array[2048, byte])
  let count = checked(encodeWorkPackage(source, config, wire))
  let captured = checked(decodeWorkPackage(wire.toOpenArray(0, count-1), config)).owner
  # Original sequences and stack wire storage must no longer influence the retained parent.
  source.items[1].payload[0] = marker xor 255
  source.authorization[0] = marker xor 255
  for octet in wire.mitems: octet = 0
  captured

# A retained alias keeps the original snapshot alive while the original handle is overwritten.
proc escapedChild(marker: byte): OwnedWorkItem =
  var original = captureParent(marker)
  let retained = original
  original = captureParent(marker xor 255)
  assert uint32(checked(workPackageInfo(original)).context.anchorSlot) == uint32(marker xor 255)
  var blob = default(array[2, byte])
  assert checked(copyPackageBlob(retained, PackageBlob.Authorization, blob)) == 2 and blob[0] == marker
  assert checked(copyPackageBlob(retained, PackageBlob.Configuration, blob)) == 1 and blob[0] == marker
  checked(workItemAt(retained, 1))

# Each isolated cycle exercises orphaned child metadata, manifests, extraction and exact re-emission.
proc releaseCycle(marker: byte) =
  let child = escapedChild(marker)
  var payload = default(array[3, byte])
  assert checked(copyItemPayload(child, payload)) == 3 and payload == [marker, byte(2), byte(3)]
  let info = checked(workItemInfo(child))
  assert info.imports == 1 and info.extrinsics == 1 and uint32(info.service) == 7
  let imported = checked(importAt(child, 0))
  assert imported.kind == ImportKind.Package and imported.package.bytes[0] == marker
  let committed = checked(extrinsicAt(child, 0))
  assert array[32, byte](committed.hash)[0] == marker
  var wire = default(array[1024, byte])
  let count = checked(encodeOwnedWorkItem(child, wire))
  assert count == info.consumed
  let captured = checked(decodeWorkItem(wire.toOpenArray(0, count-1), config))
  assert checked(copyItemPayload(captured.owner, payload)) == 3 and payload[0] == marker

# Warm up public allocator accounting before observing independent ARC scopes.
for i in 0..<100: releaseCycle(byte(i mod 256))
let beforeRelease = getOccupiedMem()
# Every return drops temporary parent aliases, orphan children, copied buffers and manifest sources.
for i in 0..<1000: releaseCycle(byte(i mod 256))
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Retain numeric observations without platform-specific heap sizes in expected output.
recordArcRelease("work_package", 1000, beforeRelease, afterRelease)
echo "PACKAGE_ARC_RELEASE cycles=1000 unchanged"
echo "Work-package family: retained replacements, orphan children, atomicity, aliases and ARC release passed"
