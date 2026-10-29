# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual common-source parent/junior guest fixtures for accpar conflict and account-source witnesses.
## Independent pure plans retain these real normalized outcomes; no test-authored decision replaces execution.
import std/assertions
import ../../src/state/accumulation/[annulment as accumulation_annulment,
    outcome as accumulation_outcome, dispatch as accumulation_dispatch]
import ../../src/state/store
import ../../src/pvm/machine
import ../../src/chain/parameters
import ../../src/codec/bounded
import ../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    trie as state_trie]
import ../../src/codec/header
import ../../src/codec/state/safrole as state_safrole
import ./[accumulation_batch_context, pvm_accumulation_program, pvm_accumulation_context]

proc annulmentPolicy*(): AccumulationAnnulmentLimits =
  ## Small independent ceilings bound both original modifications and the complete pair scan.
  AccumulationAnnulmentLimits(outcomes: ElementLimit(2), modified: ElementLimit(8),
      checks: ElementLimit(128))
proc parentCode(target = 99'u64, supervisor = 42'u64, selfWrite = false, eject = false,
    emit = false, yieldOutput = false): seq[byte] =
  ## No-op supervisor calls still mark the junior; an optional genuine self upgrade tests mutually conflicting originals.
  if eject:
    return guestEnvelope([registerImmediate(7, target), @[10'u8, 23], @[50'u8,
        0]]) # Actual selected removal supports M's absent-account branch.
  var code: seq[seq[byte]] = @[]
  if selfWrite:
    for instruction in @[registerImmediate(7, high(uint64)), registerImmediate(8, 65536),
        registerImmediate(9, 0), registerImmediate(10, 0), @[10'u8, 21]]:
      code.add(instruction) # Mark self before the foreign supervisor mutation.
  for instruction in @[registerImmediate(7, target), registerImmediate(8, supervisor), @[10'u8, 29]]:
    code.add(instruction) # Preserve the ordinary parent program when selfWrite is false.
  if emit:
    for instruction in @[registerImmediate(7, high(uint64)), registerImmediate(8, 99),
        registerImmediate(9, 0), registerImmediate(10, 0), registerImmediate(11, 5),
        registerImmediate(12, 196608), @[10'u8, 22]]:
      code.add(instruction) # Paid gas and memo bytes originate in a real second producer.
  if yieldOutput:
    code.add(registerImmediate(7, 65536))
    code.add(@[10'u8, 27]) # A second actual producer may yield the same commitment without deduplicating service identity.
  code.add(@[50'u8, 0])
  guestEnvelope(code)
proc juniorCode(write = true, panic = false, checkpointAfter = false, emit = true,
    reciprocal = false, zeroYield = false): seq[byte] =
  ## Real provision/checkpoint/upgrade/transfer/yield effects distinguish original and annulled observations.
  var code = @[registerImmediate(7, 42), registerImmediate(8, 65536), registerImmediate(9, 1),
    @[10'u8, 28], @[10'u8, 19]]
  if reciprocal:
    code.add(registerImmediate(7, 42))
    code.add(registerImmediate(8, 99))
    code.add(@[10'u8, 29]) # A matching reverse prior relationship permits modifying the original supervisor too.
  if write:
    code.add(registerImmediate(7, high(uint64)))
    code.add(registerImmediate(8, 65536))
    code.add(registerImmediate(9, 0))
    code.add(registerImmediate(10, 0))
    code.add(@[10'u8, 21]) # Self upgrades remain authorized even with a different effective supervisor.
  if emit:
    for instruction in @[registerImmediate(7, high(uint64)), registerImmediate(8, 42),
        registerImmediate(9, 0), registerImmediate(10, 0), registerImmediate(11, 10),
        registerImmediate(12, 196608), @[10'u8, 22]]:
      code.add(instruction) # Only actual outgoing transfer calls modify the payer.
  code.add(registerImmediate(7, if zeroYield: 65537'u64 else: 65536'u64))
  code.add(@[10'u8, 27]) # Yield and provisions alone do not mark the invoking account.
  if checkpointAfter: code.add(@[10'u8, 19]) # Exceptional selection may retain or discard the self mutation.
  if panic: code.add(@[0'u8]) # Genuine guest panic chooses the exceptional context.
  code.add(@[50'u8, 0])
  guestEnvelope(code)
proc annulmentFixture*(supervisor = 42'u32, incarnation = 0'u32, incoming = false,
    write = true, panic = false, checkpointAfter = false, emit = true,
        handoff = false, mutual = false, eject = false, parentTarget = 99'u64,
            parentEmit = false, parentYield = false, zeroYield = false): BatchFixture =
  ## Amend the authored complete prior before either real execution captures it.
  result = batchFixture(incoming = incoming, firstEnvelope = parentCode(target = parentTarget,
      supervisor = (if handoff: 99'u64 else: 42'u64), selfWrite = mutual, eject = eject,
          emit = parentEmit, yieldOutput = parentYield),
    secondEnvelope = juniorCode(write, panic, checkpointAfter, emit, reciprocal = mutual,
        zeroYield = zeroYield))
  let key = chapterServiceKey(StateChapter(255), ServiceIndex(99))
  var metadata = decodeServiceMetadata(result.state.snapshot.value.lookup(key).value.bytes,
    ByteLimit(ServiceMetadataBytes)).value.metadata
  metadata.supervisor = ServiceIndex(supervisor)
  metadata.supervisorCreated = AccountSlot(incarnation)
  let entry = serviceMetadataEntry(ServiceIndex(99), metadata, ByteLimit(
      ServiceMetadataBytes)).value
  assert result.state.apply([StateWrite(key: key, kind: StateWriteKind.Put,
      value: entry.value)]).error == StateStoreError.None, "annulment witness at source line 59"
  if mutual:
    let parentKey = chapterServiceKey(StateChapter(255), ServiceIndex(42))
    var parent = decodeServiceMetadata(result.state.snapshot.value.lookup(parentKey).value.bytes,
        ByteLimit(ServiceMetadataBytes)).value.metadata
    parent.supervisor = ServiceIndex(99)
    parent.supervisorCreated = AccountSlot(0)
    let entry = serviceMetadataEntry(ServiceIndex(42), parent, ByteLimit(
        ServiceMetadataBytes)).value
    assert result.state.apply([StateWrite(key: parentKey, kind: StateWriteKind.Put,
        value: entry.value)]).error == StateStoreError.None, "seed a real matching reverse supervisor before execution"
proc profile(): Parameters =
  ## Tiny fixture balances have zero deposits; genuine deferred transfers still require the exact 128-byte memo profile.
  var wire = encodeParameters(pvmParameters())
  for index in 0..<24: wire[index] = 0 # Clear all three complete deposit words.
  for index in 110..<114: wire[index] = 0 # Clear the complete E4 memo-width field.
  wire[110] = 128
  decodeParameters(wire).value
proc annulmentOriginal*(source: BatchFixture, index: uint64, enabled = true,
    slot = HeaderSlot(128), entropy = default(StateEntropyWord)): AccumulationOutcome =
  ## Normalize actual terminal selection; no caller-authored state, gas or modification flag exists.
  let execution = batchExecution(source, index, slot = slot, entropy = entropy,
      parameters = profile(), copyLimit = MemoryByteLimit(128), transferLimit = ElementLimit(1),
          deletedAccounts = ElementLimit(2),
    modifiedAccounts = ElementLimit(if enabled: 8'u64 else: 0'u64))
  assert execution.error == AccumulationDispatchError.None, "original dispatch service ordinal " &
      $index & ": " & $execution.error
  normalizeAccumulationOutcome(execution).value
proc annulmentPrepared*(source: BatchFixture, first,
    second: AccumulationOutcome): PreparedAccumulationAnnulment =
  ## Only genuine common-source outcomes and their exact original input/map owners construct decisions.
  prepareAccumulationAnnulment(source.inputs, source.state.snapshot.value, [first, second],
      annulmentPolicy()).value
