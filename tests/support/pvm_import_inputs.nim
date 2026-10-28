# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Construct genuine verified extrinsics and independent proof owners before binding package imports.

import std/assertions
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/work_package as codec_work_package
import ../../src/codec/work_report as codec_work_report
import ../../src/state/extrinsic_inputs as state_extrinsic_inputs
import ../../src/state/import_inputs as state_import_inputs
import ../../src/state/import_justification as state_import_justification
import ./pvm_extrinsic_inputs
import ./pvm_import_justification
import ./pvm_import_vectors

proc inputLimits*(): ImportInputsLimits =
  ## Admit the protocol maximum with separately counted logical leaf/proof bytes.
  ImportInputsLimits(entries: ElementLimit(3072), witnessBytes: ByteLimit(3072*4488))
proc inputKey*(first: byte): PackageHash =
  ## Fixed distinct keys make dictionary ordering explicit in tests.
  result = PackageHash()
  result.bytes[0] = first
proc inputPair*(first: byte): SegmentLookup =
  ## Explicit caller-provided package/root correspondence is deliberately not a root freshness certificate.
  SegmentLookup(packageHash: inputKey(first), segmentRoot: SegmentRoot(bytes: ThreeRoot))
proc inputProof*(index: int): VerifiedImport =
  ## Verify frozen independent three-leaf paths before using these immutable owners as inputs.
  let paths = [ThreePath0, ThreePath1, ThreePath2]
  verifyImportSegment(SegmentRoot(bytes: ThreeRoot), ImportIndex(uint16(index)),
    importSegment(byte(index+1)), importPath(paths[index]), importLimits()).value
proc inputSource*(imports: openArray[seq[ImportReference]], prerequisites = 0): VerifiedExtrinsics =
  ## Commit imports before verifying each item's independent literal abc preimage; retire temporary package bytes on return.
  var source = WorkPackage(context: RefinementContext(prerequisiteCount: prerequisites))
  for index in 0..<prerequisites: source.context.prerequisites[index] = inputKey(byte(100+index))
  var rows: seq[seq[seq[byte]]] = @[]
  for references in imports:
    source.items.add(WorkItem(imports: references, extrinsics: @[
        AbcExtrinsic])) # Every item owns a real extrinsic commitment.
    rows.add(@[@[97'u8, 98, 99]])
  var wire = newSeq[byte](120000)
  let config = fullPackageConfig(ByteLimit(120000))
  let encoded = encodeWorkPackage(source, config, wire)
  assert encoded.error == PackageError.None, "import input fixture package encoding, prerequisites=" &
      $prerequisites & ", items=" & $imports.len & ", error=" & $ord(encoded.error)
  let package = decodeWorkPackage(wire.toOpenArray(0, encoded.value-1), config).value.owner
  verifyExtrinsicInputs(package, rows, extrinsicLimits()).value
