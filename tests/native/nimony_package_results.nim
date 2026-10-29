# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Package results and nominal import alternatives must reject invalid safe-code reads.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[cmdline, syncio]
import ../../src/codec/work/[package as work_package, report as work_report]
import ../../src/codec/bounded

let useDefault = paramStr(2) == "default"
let empty: seq[byte] = @[]
let config = fullPackageConfig(ByteLimit(1024))
let missingPackage = default(OwnedWorkPackage)
let missingItem = default(OwnedWorkItem)
var output = newSeq[byte](0)
let context = if useDefault: default(PackageResult[ContextRead]) else: decodeRefinementContext(empty)
let reference = if useDefault: default(PackageResult[ImportRead]) else: decodeImportReference(empty)
let commitment = if useDefault: default(PackageResult[
    CommitmentRead]) else: decodeExtrinsicCommitment(empty)
let decodedPackage = if useDefault: default(PackageResult[PackageRead]) else: decodeWorkPackage(
    empty, config)
let item = if useDefault: default(PackageResult[ItemRead]) else: decodeWorkItem(empty, config)
let packageInfo = if useDefault: default(PackageResult[PackageInfo]) else: workPackageInfo(missingPackage)
let itemInfo = if useDefault: default(PackageResult[ItemInfo]) else: workItemInfo(missingItem)
let child = if useDefault: default(PackageResult[OwnedWorkItem]) else: workItemAt(missingPackage, 0)
let imported = if useDefault: default(PackageResult[ImportReference]) else: importAt(missingItem, 0)
let committed = if useDefault: default(PackageResult[ExtrinsicCommitment]) else: extrinsicAt(
    missingItem, 0)
let contextWrite = if useDefault: default(PackageResult[int]) else: encodeRefinementContext(default(
    RefinementContext), output)
let importWrite = if useDefault: default(PackageResult[int]) else: encodeImportReference(default(
    ImportReference), output)
let commitmentWrite = if useDefault: default(PackageResult[int]) else: encodeExtrinsicCommitment(
    default(ExtrinsicCommitment), output)
let itemWrite = if useDefault: default(PackageResult[int]) else: encodeWorkItem(default(WorkItem),
    config, output)
let packageWrite = if useDefault: default(PackageResult[int]) else: encodeWorkPackage(default(
    WorkPackage), config, output)
let payload = if useDefault: default(PackageResult[int]) else: copyItemPayload(missingItem, output)
let blob = if useDefault: default(PackageResult[int]) else: copyPackageBlob(missingPackage,
    PackageBlob.Authorization, output)
let ownedItem = if useDefault: default(PackageResult[int]) else: encodeOwnedWorkItem(missingItem, output)
let ownedPackage = if useDefault: default(PackageResult[int]) else: encodeOwnedWorkPackage(
    missingPackage, output)
case paramStr(1)
of "context-value": echo context.value.value.prerequisiteCount # No default context after failed decode.
of "context-consumed": echo context.value.consumed # No incomplete fixed-context progress.
of "import-value": echo uint16(reference.value.value.index) # No fabricated import identity/index.
of "import-consumed": echo reference.value.consumed # No partial import cursor advance.
of "commitment-value": echo uint32(commitment.value.value.length) # No default commitment on failure.
of "commitment-consumed": echo commitment.value.consumed # No incomplete commitment extent.
of "package-owner": echo ord(workPackageInfo(decodedPackage.value.owner).error) # No fabricated package owner.
of "package-consumed": echo decodedPackage.value.consumed # No partial package progress.
of "item-owner": echo ord(workItemInfo(item.value.owner).error) # No fabricated retained child.
of "item-consumed": echo item.value.consumed # No partial item progress.
of "package-info": echo packageInfo.value.items # No item cardinalities from missing owners.
of "item-info": echo itemInfo.value.payloadBytes # No payload metadata from missing children.
of "child": echo ord(workItemInfo(child.value).error) # No fabricated child from failed selection.
of "selected-import": echo uint16(imported.value.index) # No manifest record from failed selection.
of "selected-commitment": echo uint32(committed.value.length) # No commitment from failed selection.
of "context-written": echo contextWrite.value # Failed context encodes have no byte extent.
of "import-written": echo importWrite.value # Failed import encodes have no byte extent.
of "commitment-written": echo commitmentWrite.value # Failed commitment encodes have no byte extent.
of "item-written": echo itemWrite.value # Failed item encodes have no byte extent.
of "package-written": echo packageWrite.value # Failed package encodes have no byte extent.
of "payload": echo payload.value # Failed payload copies have no committed byte count.
of "blob": echo blob.value # Failed blob copies have no committed byte count.
of "owned-item": echo ownedItem.value # Failed child re-emission has no byte extent.
of "owned-package": echo ownedPackage.value # Failed parent re-emission has no byte extent.
of "wrong-root":
  # A package dependency never contains a readable direct segment-root identity.
  let value = packageImport(PackageHash(), ImportIndex(0))
  echo value.root.bytes[0]
of "wrong-package":
  # Both default Root and explicitly constructed Root references lack a package identity.
  let value = if useDefault: default(ImportReference) else: rootImport(SegmentRoot(), ImportIndex(0))
  echo value.package.bytes[0]
else: quit 2 # Invalid fixture modes cannot count as protected result access.
