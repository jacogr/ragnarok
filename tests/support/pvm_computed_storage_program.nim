# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored dual-entry storage guests and pre-execution gas rebinding for genuine computed-chain witnesses.

import std/assertions
import ../../src/state/[extrinsic_inputs, import_inputs, import_justification]
import ../../src/codec/[bounded, composite, work_package, work_digest]
import ./[pvm_refinement_outcome, pvm_input_refinement, pvm_extrinsic_inputs, pvm_import_inputs]

type ComputedStorageMode* {.pure.} = enum ## Test-only original guest selection; defaults preserve every earlier zero-output witness.
  Disabled, Commit, Panic, Underfunded, CheckpointCommit, CheckpointPanic

proc computedStorageInstructions*(mode: ComputedStorageMode): seq[seq[byte]] =
  ## Jump from refinement entry0 to its own empty output; real accumulation entry5 writes RO key11 and RW value21/22/23.
  assert mode != ComputedStorageMode.Disabled
  var body = @[refinementImmediate(7, 65536), refinementImmediate(8, 1),
    refinementImmediate(9, 196608), refinementImmediate(10, 3), @[10'u8, 5]]
  if mode in {ComputedStorageMode.CheckpointCommit, ComputedStorageMode.CheckpointPanic}:
    # Checkpoint changes r7, so independently reload every actual pointer/length before the later write.
    body.add(@[10'u8, 18])
    for instruction in [refinementImmediate(7, 65536), refinementImmediate(8, 1),
      refinementImmediate(9, 196609), refinementImmediate(10, 2), @[10'u8, 5]]:
      body.add(instruction) # Same raw key proves one provenance descriptor can retain multiple real mutations.
  body.add(refinementImmediate(8, 0))
  if mode in {ComputedStorageMode.Panic, ComputedStorageMode.CheckpointPanic}:
    body.add(@[0'u8]) # The real trap selects the prior exceptional implication after a completed write.
  else:
    body.add(@[50'u8, 0]) # Halt selects regular effects, including an admitted write or unchanged FULL state.
  var refineEntry = 5
  for instruction in body: refineEntry += instruction.len # Five explicit bytes reserve the fixed accumulation entry.
  assert refineEntry < 128
  result = @[@[40'u8, byte(refineEntry)], @[1'u8], @[1'u8], @[1'u8]]
  for instruction in body: result.add(instruction) # Every operand remains unmarked in the real program mask.
  result.add(refinementImmediate(8, 0))
  result.add(@[50'u8, 0])
proc computedStorageBudget*(fixture: InputFixture): InputFixture =
  ## Re-author the single empty-manifest original package with enough accumulation gas before its first refinement/report.
  result = fixture
  let info = fixture.package.workPackageInfo.value
  assert info.items == 1
  let selected = fixture.package.workItemAt(0).value
  let item = selected.workItemInfo.value
  assert item.imports == 0 and item.extrinsics == 0, "storage fixture requires original empty manifests"
  var payload = newSeq[byte](item.payloadBytes)
  assert selected.copyItemPayload(payload).error == PackageError.None
  var authorization = newSeq[byte](info.authorizationBytes)
  var configuration = newSeq[byte](info.configurationBytes)
  assert fixture.package.copyPackageBlob(PackageBlob.Authorization, authorization).error ==
      PackageError.None
  assert fixture.package.copyPackageBlob(PackageBlob.Configuration, configuration).error ==
      PackageError.None
  let authored = WorkPackage(host: info.host, codeHash: info.codeHash, context: info.context,
    authorization: authorization, configuration: configuration, items: @[WorkItem(
      service: item.service,
      codeHash: item.codeHash, refineGas: item.refineGas, accumulateGas: Gas(10000),
          exports: item.exports, payload: payload)])
  var wire = newSeq[byte](4096)
  let config = fullPackageConfig(ByteLimit(4096))
  let written = encodeWorkPackage(authored, config, wire).value
  result.package = decodeWorkPackage(wire.toOpenArray(0, written-1), config).value.owner
  let external = verifyExtrinsicInputs(result.package, @[newSeq[seq[byte]](0)], extrinsicLimits()).value
  result.inputs = bindImportInputs(external, @[newSeq[VerifiedImport](0)], [], inputLimits()).value
