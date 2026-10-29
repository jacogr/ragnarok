# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Build small owned manifests from explicitly supplied independent hash commitments.

import std/assertions
import ../../src/codec/bounded
import ../../src/codec/work/package as work_package
import ../../src/state/extrinsic_inputs

proc extrinsicLimits*(): ExtrinsicInputsLimits =
  ## Finite local policies independently bound occurrences, copying and hashing.
  ExtrinsicInputsLimits(entries: ElementLimit(128), payloadBytes: ByteLimit(4096),
      hashBytes: ByteLimit(4096))
proc extrinsicPackage*(rows: openArray[seq[ExtrinsicCommitment]]): OwnedWorkPackage =
  ## Capture canonical bytes before verification; zero gas and empty payloads isolate external commitments.
  var source = WorkPackage()
  for row in rows: source.items.add(WorkItem(extrinsics: row)) # Retain item and commitment order.
  var wire = newSeq[byte](8192)
  let config = fullPackageConfig(ByteLimit(8192))
  let encoded = encodeWorkPackage(source, config, wire)
  assert encoded.error == PackageError.None
  decodeWorkPackage(wire.toOpenArray(0, encoded.value-1), config).value.owner

const EmptyExtrinsic* = ExtrinsicCommitment(
  hash: ExtrinsicHash([14'u8, 87, 81, 192, 38, 229, 67, 178, 232, 171, 46, 176, 96, 153, 218, 161,
      209, 229, 223, 71, 119, 143, 119, 135, 250, 171, 69, 205, 241, 47, 227, 168]),
  length: ExtrinsicLength(0)) ## Independent Python hashlib literal for b''.

const AbcExtrinsic* = ExtrinsicCommitment(
  hash: ExtrinsicHash([189'u8, 221, 129, 60, 99, 66, 57, 114, 49, 113, 239, 63, 238, 152, 87, 155,
      148, 150, 78, 59, 177, 203, 62, 66, 114, 98, 200, 192, 104, 213, 35, 25]),
  length: ExtrinsicLength(3)) ## Independent Python hashlib literal for b'abc'.

const AbdExtrinsic* = ExtrinsicCommitment(
  hash: ExtrinsicHash([214'u8, 58, 147, 234, 155, 75, 217, 31, 224, 178, 14, 109, 135, 162, 96, 66,
      210, 254, 69, 238, 197, 228, 147, 78, 198, 145, 90, 27, 219, 12, 154, 250]),
  length: ExtrinsicLength(3)) ## Independent Python hashlib literal for b'abd'.
