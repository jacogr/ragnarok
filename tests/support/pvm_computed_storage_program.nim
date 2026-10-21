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
  FetchFirst, FetchSecond, FetchMissing, FetchList, FetchWideOffset, FetchWideIndex, FetchTail,
    FetchDelete, FetchBranchPanic, FetchReadBack, FetchReadTail, ReadMissing, ReadCheckpointPanic,
      ReadCheckpointFault, ReadCheckpointProtection

proc computedStorageInstructions*(mode: ComputedStorageMode): seq[seq[byte]] =
  ## Jump from refinement entry0 to empty output; entry5 writes RO key11 using literal or genuinely fetched RW bytes.
  assert mode != ComputedStorageMode.Disabled
  var body = @[refinementImmediate(7, 65536), refinementImmediate(8, 1),
    refinementImmediate(9, 196608), refinementImmediate(10, 3), @[10'u8, 5]]
  if mode in {ComputedStorageMode.ReadMissing, ComputedStorageMode.ReadCheckpointPanic,
      ComputedStorageMode.ReadCheckpointFault, ComputedStorageMode.ReadCheckpointProtection}:
    let retainedDeletion = mode in {ComputedStorageMode.ReadCheckpointPanic,
      ComputedStorageMode.ReadCheckpointFault, ComputedStorageMode.ReadCheckpointProtection}
    body = @[]
    if retainedDeletion:
      body = @[@[51'u8, 7, 0, 0, 3], @[51'u8, 8, 0], @[51'u8, 9, 1],
        @[51'u8, 10, 14], @[10'u8, 2], @[52'u8, 6, 0, 0,
            3]] # Fetch the actual count and preserve it in r6 across all later hosts.
    for instruction in [@[51'u8, 7, 0, 0, 1], @[51'u8, 8, 1], @[51'u8, 9, 255],
        @[51'u8, 10, 0], @[10'u8, 5]]:
      body.add(instruction) # Real deletion ignores the invalid value pointer; the assured parent genuinely contains the key.
    if retainedDeletion:
      body.add(@[10'u8, 18]) # Checkpoint the absent key before any regular restoration; r6 remains the actual fetched count.
    let target = if retainedDeletion: 42'u8 else: 255'u8
    for instruction in [@[51'u8, 7, target], @[51'u8, 8, 0, 0, 1], @[51'u8, 9, 1],
        @[51'u8, 10, 255], @[51'u8, 11, 0], @[51'u8, 12, 3], @[10'u8, 4],
        @[62'u8, 7, 3, 0, 3], @[51'u8, 7, 0, 0, 1], @[51'u8, 8, 1],
        @[51'u8, 9, 0, 0, 3], @[51'u8, 10, 11], @[10'u8, 5]]:
      body.add(instruction) # Read current absence into an ignored MAX destination, then persist its full NONE word in regular state.
  if mode in {ComputedStorageMode.FetchFirst, ComputedStorageMode.FetchSecond,
      ComputedStorageMode.FetchMissing, ComputedStorageMode.FetchList,
      ComputedStorageMode.FetchWideOffset, ComputedStorageMode.FetchWideIndex,
      ComputedStorageMode.FetchTail, ComputedStorageMode.FetchDelete,
      ComputedStorageMode.FetchBranchPanic, ComputedStorageMode.FetchReadBack,
      ComputedStorageMode.FetchReadTail}:
    # Compact load_imm instructions keep the real dual-entry envelope below128 bytes; fetch skips the C.2 operand tag.
    body = @[@[51'u8, 7, 0, 0, 3], @[51'u8, 8, 1], @[51'u8, 9, 3], @[51'u8, 10, 15]]
    let wide = mode in {ComputedStorageMode.FetchWideOffset, ComputedStorageMode.FetchWideIndex}
    let returnedWord = wide or mode == ComputedStorageMode.FetchTail
    if mode in {ComputedStorageMode.FetchReadBack, ComputedStorageMode.FetchReadTail}:
      body = @[@[51'u8, 7, 0, 0, 3], @[51'u8, 8, 0], @[51'u8, 9, 1],
        @[51'u8, 10, 14]] # Selector14 ignores item registers; the count comes from the actual full list.
    elif mode in {ComputedStorageMode.FetchDelete, ComputedStorageMode.FetchBranchPanic}:
      body = @[@[51'u8, 7, 0, 0, 3], @[51'u8, 8, 0], @[51'u8, 9, 1], @[51'u8, 10, 14],
        refinementImmediate(11, high(uint64)), refinementImmediate(12, high(
            uint64))] # Fetch the actual compact input count; selector14 ignores both item registers.
    elif mode == ComputedStorageMode.FetchTail:
      body = @[refinementImmediate(7, high(uint64)), @[51'u8, 8, 0], @[51'u8, 9, 0],
        @[51'u8, 10, 15], @[51'u8, 11, 0]] # A zero-request query returns the actual record length without copying to the invalid destination.
    elif wide:
      # Values2^32 have zero low bits: narrowing would incorrectly select offset/index0 and copy into an invalid destination.
      let offset = if mode == ComputedStorageMode.FetchWideOffset: 4294967296'u64 else: 0'u64
      let index = if mode == ComputedStorageMode.FetchWideIndex: 4294967296'u64 else: 0'u64
      body = @[refinementImmediate(7, high(uint64)), refinementImmediate(8, offset),
        @[51'u8, 9, 3], @[51'u8, 10, 15], refinementImmediate(11, index)]
    elif mode == ComputedStorageMode.FetchList:
      body = @[@[51'u8, 7, 0, 0, 3], @[51'u8, 8, 0], @[51'u8, 9, 3], @[51'u8, 10, 14],
        refinementImmediate(11, high(uint64)), refinementImmediate(12, high(
            uint64))] # Complete-list fetch ignores both full-width item registers and starts at the count prefix.
    elif mode == ComputedStorageMode.FetchMissing:
      body.add(refinementImmediate(11, high(uint64))) # Preserve all64 index bits; an absent record must not wrap to the first.
    else:
      let index = if mode == ComputedStorageMode.FetchSecond: 1'u8 else: 0'u8
      body.add(@[51'u8, 11, index]) # Both genuine report positions are selected by the guest, not by fixture injection.
    body.add(@[10'u8, 2]) # Actual input capture returns a full length or NONE; wide zero intervals must tolerate the invalid destination.
    if mode == ComputedStorageMode.FetchTail:
      for instruction in [@[149'u8, 120, 255], @[51'u8, 7, 0, 0, 3], @[51'u8, 9, 3], @[10'u8, 2]]:
        body.add(instruction) # Real add_imm_64 derives r8=r7-1; request3 then copies only the final canonical record byte.
    if returnedWord:
      body.add(@[62'u8, 7, 3, 0, 3]) # Real store_u64 persists all eight r7 bytes atRW196611 while preserving initialRW21/22/23.
    if mode == ComputedStorageMode.FetchBranchPanic:
      body.add(@[52'u8, 11, 0, 0, 3]) # Preserve the actual count in r11 across the real storage write.
    let valueBytes = if returnedWord: 11'u8 else: 3'u8
    if mode == ComputedStorageMode.FetchDelete:
      for instruction in [@[52'u8, 10, 0, 0, 3], @[154'u8, 170, 2], @[150'u8, 170, 3],
          @[51'u8, 7, 0, 0, 1], @[51'u8, 8, 1], refinementImmediate(9, high(uint64)),
          @[148'u8, 169, 0, 0, 3], @[10'u8, 5]]:
        body.add(instruction) # Derive len=(2-count)*3; real cmov selects RW only for a nonempty value, leaving MAX ignored on deletion.
    else:
      for instruction in [@[51'u8, 7, 0, 0, 1], @[51'u8, 8, 1], @[51'u8, 9, 0, 0, 3],
          @[51'u8, 10, valueBytes], @[10'u8, 5]]:
        body.add(instruction) # Fetch returns a length in r7, so reload every storage pointer and length independently.
  if mode in {ComputedStorageMode.FetchReadBack, ComputedStorageMode.FetchReadTail}:
    let offset = if mode == ComputedStorageMode.FetchReadTail: 2'u8 else: 0'u8
    let length = if mode == ComputedStorageMode.FetchReadTail: 11'u8 else: 3'u8
    for instruction in [refinementImmediate(7, high(uint64)), @[51'u8, 8, 0, 0, 1],
        @[51'u8, 9, 1], @[51'u8, 10, 3, 0, 3], @[51'u8, 11, offset], @[51'u8, 12, 3],
        @[10'u8, 4]]:
      body.add(instruction) # Read current regular self storage into disjoint zeroed RW+3; clipping leaves the remaining bytes untouched.
    if mode == ComputedStorageMode.FetchReadTail:
      body.add(@[62'u8, 7, 6, 0, 3]) # Preserve all eight returned length bytes atRW+6 before reloading the final storage arguments.
    for instruction in [@[51'u8, 7, 0, 0, 1], @[51'u8, 8, 1], @[51'u8, 9, 3, 0, 3],
        @[51'u8, 10, length], @[10'u8, 5]]:
      body.add(instruction) # Persist only actual read bytes, including the full return word in the clipped-read mode.
  let checkpoint = mode in {ComputedStorageMode.CheckpointCommit,
      ComputedStorageMode.CheckpointPanic, ComputedStorageMode.CheckpointOutOfGas}
  if checkpoint:
    body.add(@[10'u8, 18]) # Retain the first write only after the real checkpoint precharge succeeds.
  if checkpoint or mode == ComputedStorageMode.OutOfGas:
    # Checkpoint changes r7, so independently reload every actual pointer/length before the later write.
    for instruction in [refinementImmediate(7, 65536), refinementImmediate(8, 1),
      refinementImmediate(9, 196609), refinementImmediate(10, 2), @[10'u8, 5]]:
      body.add(instruction) # Same raw key proves one provenance descriptor can retain multiple real mutations.
  if mode in {ComputedStorageMode.FetchReadBack, ComputedStorageMode.FetchReadTail,
      ComputedStorageMode.ReadMissing, ComputedStorageMode.ReadCheckpointPanic,
      ComputedStorageMode.ReadCheckpointFault, ComputedStorageMode.ReadCheckpointProtection}:
    body.add(@[51'u8, 8, 0]) # Only the read-back and missing-read guests use compact empty-yield setup to keep the authored code below128 bytes.
  else:
    body.add(refinementImmediate(8, 0)) # Preserve every predecessor guest byte and its instruction boundaries.
  if mode in {ComputedStorageMode.ReadCheckpointPanic, ComputedStorageMode.ReadCheckpointFault,
      ComputedStorageMode.ReadCheckpointProtection}:
    body.add(@[81'u8, 22, 2, 6]) # Compare preserved r6 with two and branch forward past the historical regular halt.
    body.add(@[50'u8, 0]) # One genuine input commits the actual regular restoration.
    if mode == ComputedStorageMode.ReadCheckpointProtection:
      body.add(@[52'u8, 7, 0]) # A real byte load from address0 must panic under unconditional low-memory protection.
    elif mode == ComputedStorageMode.ReadCheckpointFault:
      body.add(@[52'u8, 7, 0, 0, 2]) # Actual load_u8 from the unmapped guard at131072 faults after the regular restoration.
    else:
      body.add(@[0'u8]) # Two genuine inputs select the retained checkpoint deletion after that restoration.
  elif mode == ComputedStorageMode.FetchBranchPanic:
    body.add(@[81'u8, 27, 2, 6]) # Real equality branches forward by six bytes exactly when the count is two.
    body.add(@[50'u8, 0]) # Historical count one commits the write through the actual regular exit.
    body.add(@[0'u8]) # The assured count two selects initial exceptional state after attempting a different write.
  elif mode in {ComputedStorageMode.Panic, ComputedStorageMode.CheckpointPanic}:
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
