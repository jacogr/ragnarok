# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute genuine ordinary/mixed-shape input packages before assembling their auditable wire bytes.

import std/assertions
import ../../src/state/[input_refinement, import_inputs, import_justification, extrinsic_inputs]
import ../../src/codec/[bounded, work_package, work_report]
import ./[pvm_input_refinement, pvm_refinement_outcome, pvm_report_results, pvm_import_inputs,
  pvm_import_justification, pvm_import_vectors, pvm_extrinsic_inputs, pvm_bundle_vectors]

proc bundleExecution*(rich = false, exports = false): InputRefinement =
  ## Retire all mutable preparation fixtures before returning only genuine completed execution ownership.
  let halt = @[50'u8, 0]
  let authCode = @[refinementImmediate(7, 65536), refinementImmediate(8, 3), halt]
  if exports:
    # Exported bytes belong to a separate availability source; makebundle includes only this original package.
    let guest = reportGuest([refinementImmediate(7, 65536), refinementImmediate(8, 3), @[10'u8, 8],
      refinementImmediate(8, 0), halt], declared = 1)
    return executionRun(executionFixture(authCode, [guest], external = false)).value
  if not rich:
    return executionRun(executionFixture(authCode, [fetchedGuest(4), fetchedGuest(6)])).value
  let guest = reportGuest([refinementImmediate(8, 0), halt])
  var fixture = executionFixture(authCode, [guest, guest, guest], external = false)
  let original = fixture.package.workPackageInfo.value
  var source = WorkPackage(host: original.host, codeHash: original.codeHash,
    context: original.context,
    authorization: @[91'u8], configuration: @[81'u8, 82])
  var long128 = newSeq[byte](128)
  var long129 = newSeq[byte](129)
  for index in 0..<128: long128[index] = 7 # Independent frozen commitments, not production-hashed expectations.
  for index in 0..<129: long129[index] = 8
  let c128 = ExtrinsicCommitment(hash: ExtrinsicHash(Long128Hash), length: ExtrinsicLength(128))
  let c129 = ExtrinsicCommitment(hash: ExtrinsicHash(Long129Hash), length: ExtrinsicLength(129))
  let singleton = verifyImportSegment(SegmentRoot(bytes: SingletonRoot), ImportIndex(0),
      importSegment(), [], importLimits()).value
  let singleRef = rootImport(SegmentRoot(bytes: SingletonRoot), ImportIndex(0))
  let root = SegmentRoot(bytes: ThreeRoot)
  let references = @[@[singleRef, rootImport(root, ImportIndex(0))], newSeq[ImportReference](0),
    @[rootImport(root, ImportIndex(1)), singleRef]]
  let commitments = @[@[EmptyExtrinsic, c128], newSeq[ExtrinsicCommitment](0), @[c129,
      EmptyExtrinsic, c128]]
  let rows = @[@[newSeq[byte](0), long128], newSeq[seq[byte]](0), @[long129, newSeq[byte](0), long128]]
  let imports = @[@[singleton, inputProof(0)], newSeq[VerifiedImport](0), @[inputProof(1), singleton]]
  for index in 0..<3:
    let selected = fixture.package.workItemAt(index).value
    let info = selected.workItemInfo.value
    var payload = newSeq[byte](info.payloadBytes)
    assert selected.copyItemPayload(payload).error == PackageError.None, "original bundle fixture payload"
    source.items.add(WorkItem(service: info.service, codeHash: info.codeHash,
      refineGas: info.refineGas,
      accumulateGas: info.accumulateGas, exports: info.exports, payload: payload,
      imports: references[index], extrinsics: commitments[index]))
  var wire = newSeq[byte](4096)
  let config = fullPackageConfig(ByteLimit(4096))
  let encoded = encodeWorkPackage(source, config, wire).value
  fixture.package = decodeWorkPackage(wire.toOpenArray(0, encoded-1), config).value.owner
  let extrinsics = verifyExtrinsicInputs(fixture.package, rows, extrinsicLimits()).value
  fixture.inputs = bindImportInputs(extrinsics, imports, [], inputLimits()).value
  executionRun(fixture).value
