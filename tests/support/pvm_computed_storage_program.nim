# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored dual-entry storage guests and pre-execution gas rebinding for genuine computed-chain witnesses.

import std/assertions
import ../../src/state/[extrinsic_inputs, import_inputs, import_justification]
import ../../src/codec/[bounded, composite, work_package, work_digest]
import ./[pvm_refinement_outcome, pvm_input_refinement, pvm_extrinsic_inputs, pvm_import_inputs]

type ComputedStorageMode* {.pure.} = enum ## Test-only original guest selection; defaults preserve every earlier zero-output witness.
  Disabled, Commit, Panic, Underfunded, CheckpointCommit, CheckpointPanic, OutOfGas,
    CheckpointOutOfGas,
  FetchFirst, FetchSecond, FetchMissing, FetchList

proc computedStorageInstructions*(mode: ComputedStorageMode): seq[seq[byte]] =
  ## Jump from refinement entry0 to empty output; entry5 writes RO key11 using literal or genuinely fetched RW bytes.
  assert mode != ComputedStorageMode.Disabled
  var body = @[refinementImmediate(7, 65536), refinementImmediate(8, 1),
    refinementImmediate(9, 196608), refinementImmediate(10, 3), @[10'u8, 5]]
  if mode in {ComputedStorageMode.FetchFirst, ComputedStorageMode.FetchSecond,
      ComputedStorageMode.FetchMissing, ComputedStorageMode.FetchList}:
    # Compact load_imm instructions keep the real dual-entry envelope below128 bytes; fetch skips the C.2 operand tag.
    body = @[@[51'u8, 7, 0, 0, 3], @[51'u8, 8, 1], @[51'u8, 9, 3], @[51'u8, 10, 15]]
    if mode == ComputedStorageMode.FetchList:
      body = @[@[51'u8, 7, 0, 0, 3], @[51'u8, 8, 0], @[51'u8, 9, 3], @[51'u8, 10, 14],
        refinementImmediate(11, high(uint64)), refinementImmediate(12, high(
            uint64))] # Complete-list fetch ignores both full-width item registers and starts at the count prefix.
    elif mode == ComputedStorageMode.FetchMissing:
      body.add(refinementImmediate(11, high(uint64))) # Preserve all64 index bits; an absent record must not wrap to the first.
    else:
      let index = if mode == ComputedStorageMode.FetchSecond: 1'u8 else: 0'u8
      body.add(@[51'u8, 11, index]) # Both genuine report positions are selected by the guest, not by fixture injection.
    body.add(@[10'u8, 2]) # Fetch actual invocation record bytes into RW196608 before the storage host reads them.
    for instruction in [@[51'u8, 7, 0, 0, 1], @[51'u8, 8, 1], @[51'u8, 9, 0, 0, 3],
        @[51'u8, 10, 3], @[10'u8, 5]]:
      body.add(instruction) # Fetch returns a length in r7, so reload every storage pointer and length independently.
  let checkpoint = mode in {ComputedStorageMode.CheckpointCommit,
      ComputedStorageMode.CheckpointPanic, ComputedStorageMode.CheckpointOutOfGas}
  if checkpoint:
    body.add(@[10'u8, 18]) # Retain the first write only after the real checkpoint precharge succeeds.
  if checkpoint or mode == ComputedStorageMode.OutOfGas:
    # Checkpoint changes r7, so independently reload every actual pointer/length before the later write.
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
proc computedStorageBudget*(fixture: InputFixture, mode: ComputedStorageMode): InputFixture =
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
  # Include prepaid instruction-block work (100 pipeline cycles per host) before the first write and checkpoint.
  let credit = if mode in {ComputedStorageMode.OutOfGas,
      ComputedStorageMode.CheckpointOutOfGas}: 3500'u64 else: 10000'u64
  let authored = WorkPackage(host: info.host, codeHash: info.codeHash, context: info.context,
    authorization: authorization, configuration: configuration, items: @[WorkItem(
      service: item.service,
      codeHash: item.codeHash, refineGas: item.refineGas, accumulateGas: Gas(credit),
          exports: item.exports, payload: payload)])
  var wire = newSeq[byte](4096)
  let config = fullPackageConfig(ByteLimit(4096))
  let written = encodeWorkPackage(authored, config, wire).value
  result.package = decodeWorkPackage(wire.toOpenArray(0, written-1), config).value.owner
  let external = verifyExtrinsicInputs(result.package, @[newSeq[seq[byte]](0)], extrinsicLimits()).value
  result.inputs = bindImportInputs(external, @[newSeq[VerifiedImport](0)], [], inputLimits()).value
