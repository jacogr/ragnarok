# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prepare genuine combined code/state and verify final manifests before the production execution path runs.

import std/assertions
import ../../src/state/input_refinement
import "../../src/state/import/inputs" as import_inputs
import "../../src/state/import/justification" as import_justification
import ../../src/state/[extrinsic_inputs, store]
import ../../src/codec/[bounded, composite]
import ../../src/codec/work/[package as work_package, report as work_report]
import ../../src/pvm/host/fetch as host_fetch
import ../../src/chain/parameters
import ./[pvm_authorized_refinement, pvm_authorization_invoke, pvm_report_results,
  pvm_import_inputs, pvm_import_vectors, pvm_extrinsic_inputs, pvm_refinement_outcome]

type
  InputFixture* = object ## Mutable test handles can be replaced without changing production owners' retained provenance.
    state*: StateStoreSnapshot
    parameters*: Parameters
    package*: OwnedWorkPackage
    inputs*: VerifiedImportInputs
proc executionLimits*(): InputRefinementLimits =
  ## Independent materialization/child/identity policies admit small fully owned witnesses.
  result = InputRefinementLimits(inputBytes: ByteLimit(65536), authorization: authorizationLimits(),
    refinement: authorizedLimits())
  result.refinement.refinement.invocation.capture.inputs = FetchInputLimit(65536)
  result.identity.packageBytes = ByteLimit(4096)
  result.identity.authorizerBytes = ByteLimit(4096)
proc executionFixture*(authCode: openArray[seq[byte]], guests: openArray[ReportGuest],
    external = true, authCodeSize = 0, missingAuth = false): InputFixture =
  ## Commit the final package before verifying extrinsics and binding independent import proof owners.
  let base = authorizedFixture(authCode, guests, authCodeSize, missingAuth)
  result = InputFixture(state: base.state, parameters: base.parameters)
  let described = base.package.workPackageInfo.value
  var source = WorkPackage(host: described.host, codeHash: described.codeHash,
    context: described.context, authorization: @[91'u8], configuration: @[81'u8, 82])
  var rows: seq[seq[seq[byte]]] = @[]
  var imports: seq[seq[VerifiedImport]] = @[]
  var lookup: seq[SegmentLookup] = @[]
  for index in 0..<guests.len:
    let selected = base.package.workItemAt(index).value
    let info = selected.workItemInfo.value
    var payload = newSeq[byte](info.payloadBytes)
    assert selected.copyItemPayload(payload).error == PackageError.None
    var item = WorkItem(service: info.service, codeHash: info.codeHash, refineGas: info.refineGas,
      accumulateGas: info.accumulateGas, exports: info.exports, payload: payload)
    if external:
      # Distinct per-item bytes and ordinal proofs catch accidental current-item selection or input substitution.
      let odd = index mod 2 == 1
      item.extrinsics = @[if odd: AbdExtrinsic else: AbcExtrinsic]
      rows.add(@[if odd: @[97'u8, 98, 100] else: @[97'u8, 98, 99]])
      let ordinal = ImportIndex(uint16(index mod 3))
      item.imports = @[if odd: packageImport(inputKey(1), ordinal)
        else: rootImport(SegmentRoot(bytes: ThreeRoot), ordinal)]
      imports.add(@[inputProof(index mod 3)])
      if index == 1: lookup.add(inputPair(1)) # Only tagged package references contribute to the exact lookup dictionary.
    else:
      rows.add(newSeq[seq[byte]](0)) # Empty tables still require explicit package-bound verification.
      imports.add(newSeq[VerifiedImport](0))
    source.items.add(item)
  var wire = newSeq[byte](4096)
  let config = fullPackageConfig(ByteLimit(4096))
  let size = encodeWorkPackage(source, config, wire).value
  result.package = decodeWorkPackage(wire.toOpenArray(0, size-1), config).value.owner
  let extrinsics = verifyExtrinsicInputs(result.package, rows, extrinsicLimits()).value
  result.inputs = bindImportInputs(extrinsics, imports, lookup, inputLimits()).value
proc executionRun*(fixture: InputFixture, cap = executionLimits(),
    core = 0x1234'u64): InputRefinementResult[InputRefinement] =
  ## Accept no detached authorization/report/trace or replaceable package argument.
  runInputRefinement(fixture.state, fixture.inputs, CoreIndex(core), fixture.parameters, cap)
proc fetchedGuest*(selector: uint64, otherItem = 0'u64): ReportGuest =
  ## Authored host-2 instructions fetch three bytes into writable stack memory and return that exact interval.
  reportGuest([refinementImmediate(7, 196608), refinementImmediate(8, 0),
    refinementImmediate(9, 3), refinementImmediate(10, selector),
    refinementImmediate(11, otherItem), refinementImmediate(12, 0), @[10'u8, 2],
    refinementImmediate(7, 196608), refinementImmediate(8, 3), @[50'u8, 0]])
