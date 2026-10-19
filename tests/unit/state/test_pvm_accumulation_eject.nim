# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_eject_arc_release"}

## Authored eject programs verify exact eligibility, atomic account removal/credit and retained implication owners.

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite, state_layout, state_accounts, state_requests,
  state_service_values, state_privileges, state_outputs, state_trie, c2_records, header]
import ../../../src/state/[accumulation_dispatch, accumulation_effects, accumulation_context,
  accumulation_machine, accumulation_invocation, accumulation_outcome, store]
import ../../../src/pvm/[machine, program, step, gas, host_fetch]
import ../../../src/crypto/primitives
import ../../support/[pvm_accumulation_program, pvm_accumulation_context, arc_evidence]

# Inject maintained-primitive failures after genuine fixture preparation.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
# Count namespace and trie hashes to prove charge-before-work and atomic failure behavior.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
# Reject after a chosen number of successful primitive invocations.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

# Fixed E32 identity of the invoking service; the remaining 28 bytes stay zero.
proc identity(service = 42'u32): CodeHash =
  var bytes = default(array[32, byte])
  for i in 0..<4:
    bytes[i] = byte((service shr (8*i)) and 255) # Encode directly, without a hash or native-endian alias.
  CodeHash(bytes)

# Exact independent profile offsets select the standard 19,200-slot expunge period and fixed memo width.
proc parameters(anchor = 14400'u32): Parameters =
  var bytes = encodeParameters(pvmParameters())
  for i in 0..<24:
    bytes[i] = 0 # Zero deposit settings do not grant permission or affect reclamation.
  bytes[24] = 2
  bytes[25] = 0
  bytes[82] = 80
  bytes[83] = 0
  for i in 0..<4:
    bytes[74+i] = byte((anchor shr (8*i)) and 255) # maxLookupAnchorAge is the E4 field at 74.
    bytes[110+i] = 0 # Fixed transfer memo profile for interaction witnesses.
  bytes[110] = 128
  result = decodeParameters(bytes).value
  assert result.get(maxLookupAnchorAge) == uint64(anchor), "independent expunge parameter offset"

# Eligible footprint represents one retained preimage request and no arbitrary storage.
proc account(balance = 77'u64, octets = 84'u64, items = 2'u32, code = identity()): ServiceMetadata =
  ServiceMetadata(codeHash: code, balance: AccountBalance(balance),
      storageBytes: AccountStorageBytes(octets),
    storageItems: AccountStorageItems(items), minimumTransferGas: Gas(7))

let blob = @[5'u8, 7, 9]
let hash = ServicePreimageHash(array[32, byte](blake2b256(blob).value))
let requestConfig = RequestEntryConfig(keyBytes: ByteLimit(32),
  history: RequestHistoryConfig(items: ElementLimit(3), maxBytes: ByteLimit(13)))

# Build real current accounts and request/preimage entries; optional inconsistencies target explicit local refusal contracts.
proc source(destination = 99'u64, address = 196608'u64, credit = 100000'u64,
    target = 99'u32, targetAccount = account(), selfBalance = 100'u64, slot = 20000'u32,
    history = unavailableHistory(RequestSlot(4), RequestSlot(799)), requestLength = 3'u32,
    includeAccount = true, includeRequest = true, includePreimage = true,
    badHistory = false, historyWire: seq[byte] = @[], data: seq[byte] = @[], writes = 4'u64,
    suffix: seq[seq[byte]] = @[@[50'u8, 0]], extra: seq[StateEntry] = @[]): PreparedAccumulationMachine =
  var entries = extra
  if includeAccount:
    entries.add(serviceMetadataEntry(ServiceIndex(target), targetAccount, ByteLimit(
        89)).value) # Current metadata grants actual target membership.
  if includeRequest:
    var request = serviceRequestEntry(ServiceIndex(target), hash, RequestLength(requestLength),
        history, requestConfig).value
    if badHistory:
      request.value = historyWire # Explicit malformed bytes remain in the genuine complete-map owner.
    entries.add(request)
  if includePreimage:
    entries.add(servicePreimageEntry(ServiceIndex(target), hash, blob,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(
          3))).value) # Unavailable history still retains this old blob.
  var input = data
  if input.len == 0:
    input = newSeq[byte](32)
    let digest = array[32, byte](hash)
    for i in 0..<32:
      input[i] = digest[i] # Default exact fixed hash input is independent from the account code identity.
  var instructions = @[registerImmediate(7, destination), registerImmediate(8, address), @[10'u8, 22]]
  for instruction in suffix:
    instructions.add(instruction) # Later observers execute through the same production CPU stream.
  guestProgram(instructions, credit, account = ServiceMetadata(balance: AccountBalance(
      selfBalance)),
    writable = input, extra = entries, writes = writes, slot = HeaderSlot(slot), spareEntries = 4)

# Explicit independent copy, execution and outgoing policies keep protocol refusals separate from local ceilings.
proc run(prepared: PreparedAccumulationMachine, copy = 128'u64, params = parameters()): AccumulationDispatchResult =
  executeAccumulationMachine(prepared, params,
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1), operand: OperandLimits(
        maxBytes: ByteLimit(132))),
    MemoryByteLimit(copy), ExecutionStepLimit(100), HostCallLimit(10), GasCycleLimit(1000),
    pvmContextConfig(), transferLimit = ElementLimit(2))

# Independently read basic-block charging before the fixed eject fee.
proc price(prepared: PreparedAccumulationMachine): uint64 =
  uint64(blockGas(programOf(prepared.accumulationMachine.value).value, CodeAddress(5),
      GasCycleLimit(1000)).value)

# Retain only a completed execution's matching regular or exceptional implication context.
proc context(done: AccumulationDispatchResult, dimension = AccumulationDimension.Regular): AccumulationEffectContext =
  assert done.error == AccumulationDispatchError.None, "completed execution exposes effects"
  done.effects.effectContext(dimension).value

# Decode current canonical caller metadata to inspect the exact complete-width credited balance.
proc balance(owner: AccumulationEffectContext): uint64 =
  let found = owner.effectAccounts.value.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(42))).value
  uint64(decodeServiceMetadata(found.bytes, ByteLimit(89)).value.metadata.balance)

# Every component of the removed account disappears together, while unrelated accounts remain current.
proc removed(owner: AccumulationEffectContext, target = 99'u32, length = 3'u32) =
  let state = owner.effectAccounts.value
  for key in [chapterServiceKey(StateChapter(255), ServiceIndex(target)),
    serviceRequestKey(ServiceIndex(target), hash, RequestLength(length), ByteLimit(32)).value,
    servicePreimageKey(ServiceIndex(target), hash, ByteLimit(32)).value]:
    assert state.lookup(key).error == StateStoreError.MissingKey, "all removed account components absent"

let valid = source()
let done = run(valid)
assert done.value.exit == StepExit.Halt and uint64(machineInfo(done.value.machine).value.registers[
    7]) == 0, "eligible eject returns OK"
assert uint64(machineInfo(done.value.machine).value.gas) == 100000-price(valid)-458, "fixed eject cost"
removed(context(done))
assert balance(context(done)) == 177 and balance(context(done,
    AccumulationDimension.Exceptional)) == 100, "credit and checkpoint independence"
assert normalizeAccumulationOutcome(done).value.outcomeContext.value.effectAccounts.value.lookup(
  chapterServiceKey(StateChapter(255), ServiceIndex(99))).error == StateStoreError.MissingKey, "normalized regular owner retains removal"
for chapter in [2, 7, 12]:
  assert context(done).effectAccounts.value.lookup(chapterKey(StateChapter(chapter))).value.bytes ==
    context(done, AccumulationDimension.Exceptional).effectAccounts.value.lookup(chapterKey(
        StateChapter(chapter))).value.bytes, "unrelated state chapters preserved"
for target in [0'u32, high(uint32)]:
  let completed = run(source(destination = uint64(target), target = target))
  removed(context(completed), target = target) # Full valid account domain has no sentinel.
for destination in [42'u64, 123, 0x100000063'u64, high(uint64)]:
  let refused = run(source(destination = destination, targetAccount = account(items = 0)))
  assert uint64(machineInfo(refused.value.machine).value.registers[7]) == high(uint64)-3, "WHO precedes footprint and rejects self/full-width aliases"
  assert balance(context(refused)) == 100, "WHO never credits self"
var wrongIdentity = array[32, byte](identity())
wrongIdentity[31] = 1
for code in [identity(99), CodeHash(wrongIdentity), default(CodeHash)]:
  assert uint64(machineInfo(run(source(targetAccount = account(
      code = code))).value.machine).value.registers[7]) == high(uint64)-3, "WHO compares every E32 code identity byte"
assert uint64(machineInfo(run(source(includeAccount = false)).value.machine).value.registers[7]) ==
    high(uint64)-3, "orphan request/preimage do not grant membership"
for items in [0'u32, 1, 3, high(uint32)]:
  assert uint64(machineInfo(run(source(targetAccount = account(
      items = items))).value.machine).value.registers[7]) == high(uint64)-8, "HUH requires exact two-item footprint"
for history in [requestedHistory(), availableHistory(RequestSlot(1)),
  reavailableHistory(RequestSlot(1), RequestSlot(2), RequestSlot(3))]:
  assert uint64(machineInfo(run(source(history = history)).value.machine).value.registers[7]) ==
      high(uint64)-8, "only exact unavailable shape qualifies"
for removedAt in [799'u32, 800, 801, high(uint32)]:
  let completed = run(source(history = unavailableHistory(RequestSlot(4), RequestSlot(removedAt))))
  assert uint64(machineInfo(completed.value.machine).value.registers[7]) ==
    (if removedAt < 800: 0'u64 else: high(uint64)-8), "strict expiry edge"
for slot in [0'u32, 128, 19199, 19200]:
  let completed = run(source(slot = slot, history = unavailableHistory(RequestSlot(0), RequestSlot(0))))
  assert uint64(machineInfo(completed.value.machine).value.registers[7]) == high(uint64)-8, "mathematical nonpositive cutoff never wraps"
let earliest = run(source(slot = 19201, history = unavailableHistory(RequestSlot(0), RequestSlot(0))))
removed(context(earliest))
assert uint64(machineInfo(run(source(slot = high(uint32)), params = parameters(high(
    uint32))).value.machine).value.registers[7]) == high(uint64)-8, "widened expunge-period addition"
assert uint64(machineInfo(run(source(includeRequest = false)).value.machine).value.registers[7]) ==
    high(uint64)-8, "missing exact request"
assert uint64(machineInfo(run(source(requestLength = 4)).value.machine).value.registers[7]) == high(
    uint64)-8, "derived footprint length is exact"
for octets in [0'u64, 80, 81]:
  let completed = run(source(targetAccount = account(octets = octets), requestLength = 0))
  removed(context(completed), length = 0) # The pinned maximum clamps length to zero before subtracting 81.
for length in [uint32(high(uint32)-1), high(uint32)]:
  let completed = run(source(targetAccount = account(octets = uint64(length)+81),
      requestLength = length,
    includePreimage = false))
  removed(context(completed), length = length) # Preserve pinned overlapping request namespace bytes; shared deletion is idempotent.
for octets in [uint64(high(uint32))+82, high(uint64)]:
  assert uint64(machineInfo(run(source(targetAccount = account(
      octets = octets))).value.machine).value.registers[7]) == high(uint64)-8, "full-width footprint cannot narrow to a request length"
for wire in [newSeq[byte](0), @[4'u8], @[2'u8, 0], @[0'u8, 0], newSeq[byte](14)]:
  assert run(source(badHistory = true, historyWire = wire)).error ==
      AccumulationDispatchError.MalformedState, "malformed/trailing history is a local refusal"
let malformed = StateEntry(key: chapterServiceKey(StateChapter(255), ServiceIndex(99)), value: @[0'u8])
assert run(source(includeAccount = false, extra = @[malformed])).error ==
    AccumulationDispatchError.MalformedState, "malformed metadata is local"
for address in [0'u64, 65536'u64+4096-16, 196608'u64+8192-16, 0x100000000'u64, high(uint64)]:
  let failed = run(source(address = address, destination = high(uint64)))
  assert failed.value.exit == StepExit.Panic and uint64(machineInfo(
      failed.value.machine).value.registers[7]) == high(uint64), "memory precedes WHO with unchanged r7"
  assert uint64(machineInfo(failed.value.machine).value.gas) == 100000-price(valid)-458, "memory panic pays fixed fee"
assert run(valid, copy = 31).error == AccumulationDispatchError.LimitExceeded, "fixed hash capture policy"
let ro = run(source(address = 65536))
assert uint64(machineInfo(ro.value.machine).value.registers[7]) == high(uint64)-8, "readable RO hash gives missing-request HUH"
let crossing = run(source(address = 196608'u64+4096-16))
assert uint64(machineInfo(crossing.value.machine).value.registers[7]) == high(uint64)-8, "readable cross-page hash"
for available in [0'u64, 457, 458, 459]:
  let completed = run(source(credit = price(valid)+available))
  let cpu = machineInfo(completed.value.machine).value
  if available < 458:
    assert completed.value.exit == StepExit.OutOfGas and uint64(cpu.gasDeficit) == 458-available, "exact fixed fee deficit"
    assert uint64(cpu.registers[7]) == 99 and balance(context(completed)) == 100, "OOG preserves destination and accounts"
  else:
    assert completed.value.exit == StepExit.Halt and uint64(cpu.gas) == available-458, "funded fixed fee edge"
let hugeCredit = run(source(credit = high(uint64)))
assert uint64(machineInfo(hugeCredit.value.machine).value.gas) == high(uint64)-price(valid)-458, "full-width gas credit"
let unfundedCaller = run(source(selfBalance = 0, targetAccount = account(balance = high(uint64))))
assert balance(context(unfundedCaller)) == high(uint64), "reclamation requires no minimum balance or privilege role"
for reclaimed in [0'u64, high(uint64)-100]:
  let completed = run(source(targetAccount = account(balance = reclaimed)))
  assert balance(context(completed)) == 100+reclaimed, "exact full-width balance credit"
assert run(source(targetAccount = account(balance = high(uint64)))).error ==
    AccumulationDispatchError.InvalidContext, "overflow remains local rather than wrapping balance"
let repeated = run(source(suffix = @[registerImmediate(7, 99), @[10'u8, 22], @[50'u8, 0]]))
assert uint64(machineInfo(repeated.value.machine).value.registers[7]) == high(uint64)-3 and balance(
    context(repeated)) == 177, "second eject sees removed current account and cannot double-credit"
# The current transfer reader sees the deletion immediately and returns WHO without an outgoing append.
var transferInput = newSeq[byte](128)
for i, octet in array[32, byte](hash):
  transferInput[i] = octet # Eject consumes the original hash, while transfer later reads a complete independent memo.
let followed = run(source(suffix = @[registerImmediate(7, 99), registerImmediate(8, 1),
    registerImmediate(9, 7),
  registerImmediate(10, 196608), @[10'u8, 21], @[50'u8, 0]], data = transferInput))
assert uint64(machineInfo(followed.value.machine).value.registers[7]) == high(uint64)-3 and
  context(followed).effectInfo.value.transfers == 0 and balance(context(followed)) == 177, "later transfer sees deleted current account"
# Eject preserves pending transfers, provisions and yield, even when their target is reclaimed later.
let solicitation = serviceRequestEntry(ServiceIndex(42), hash, RequestLength(3), requestedHistory(),
    requestConfig).value
let withRequest = run(source(extra = @[solicitation]))
let owners = prepareAccumulationEffects(withRequest.effects.effectsSource.value).value
let provided = recordAccumulationProvision(owners, ServiceIndex(42), blob,
  AccumulationProvisionLimits(items: ElementLimit(1), perBlob: ByteLimit(3),
      totalBlobBytes: ByteLimit(3))).value
let yielded = recordAccumulationYield(provided, default(OutputCommitment)).value
let planned = prepareAccumulationTransfer(yielded, AccumulationTransferDestination(99),
    TransferBalance(5),
  Gas(7), default(TransferMemo), parameters()).value
let sent = commitAccumulationTransfer(planned, ElementLimit(1)).value
let checkpointed = checkpointAccumulationEffects(sent).value
let reclaimed = recordAccumulationEject(checkpointed, AccumulationEjectTarget(99), hash, parameters()).value
let retained = reclaimed.effectContext(AccumulationDimension.Regular).value
let frozen = reclaimed.effectContext(AccumulationDimension.Exceptional).value
removed(retained)
assert balance(retained) == 172 and balance(frozen) == 95, "deferred debit and exceptional checkpoint remain independent"
assert retained.effectInfo.value.transfers == 1 and retained.effectInfo.value.provisions == 1 and
  retained.effectInfo.value.hasYield, "all nonempty implication owners survive eject"
assert uint64(retained.effectTransferAt(AccumulationTransferIndex(0)).value.amount) == 5 and
  retained.effectProvisionAt(AccumulationProvisionIndex(0)).value.copyProvisionBytes.value == blob and
  array[32, byte](retained.effectYield.value) == default(array[32, byte]), "retained payloads remain exact"
assert frozen.effectAccounts.value.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
    99))).error == StateStoreError.None,
  "checkpoint keeps target membership before reclamation"
# Direct effects preserve every retained non-account owner and permit fresh fault injection after fixture preparation.
let prepared = prepareAccumulationEffects(done.effects.effectsSource.value).value
assert recordAccumulationEject(default(AccumulationEffects), AccumulationEjectTarget(99), hash,
    parameters()).error == AccumulationEffectError.Uninitialized, "default pair cannot reclaim"
assert recordAccumulationEject(prepared, AccumulationEjectTarget(99), hash, default(
    Parameters)).error == AccumulationEffectError.InvalidParameters, "default schedule cannot authorize age"
for successful in [0, 1, 2, 4]:
  failAfter(cint(successful))
  let failed = recordAccumulationEject(prepared, AccumulationEjectTarget(99), hash, parameters())
  assert failed.error == AccumulationEffectError.BackendFailure and hashCalls() == cint(
      successful+1), "atomic immediate/late hashing refusal"
  failHash(0)
  let prior = prepared.effectContext(AccumulationDimension.Regular).value
  assert balance(prior) == 100 and prior.effectAccounts.value.lookup(chapterServiceKey(StateChapter(
      255), ServiceIndex(99))).error == StateStoreError.None, "failed candidate retains target and self balance"
for writes in [0'u64, 1, 2, 3]:
  assert run(source(writes = writes)).error == AccumulationDispatchError.LimitExceeded, "inherited four-write policy"
let exhausted = source(credit = price(valid)+457, address = high(uint64), destination = high(
    uint64), writes = 0)
failHash(1)
assert run(exhausted, copy = 0).value.exit == StepExit.OutOfGas and hashCalls() == 0, "OOG precedes capture/eligibility/store work"
failHash(0)
for checkpoint in [false, true]:
  let failed = run(source(suffix = (if checkpoint: @[@[10'u8, 18], @[0'u8]] else: @[@[0'u8]])))
  let selected = normalizeAccumulationOutcome(failed).value.outcomeContext.value
  assert balance(selected) == (if checkpoint: 177'u64 else: 100'u64), "panic chooses matching credit/removal checkpoint"
  assert selected.effectAccounts.value.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      99))).error ==
    (if checkpoint: StateStoreError.MissingKey else: StateStoreError.None), "checkpoint account membership matches balance"
# Exhaustion after a successful eject chooses the same complete account/balance checkpoint as panic.
for checkpoint in [false, true]:
  let exhaustedAfter = run(source(credit = price(valid)+650, suffix = (if checkpoint:
    @[@[10'u8, 18], registerImmediate(7, 99), @[10'u8, 22], @[50'u8, 0]] else:
    @[registerImmediate(7, 99), @[10'u8, 22], @[50'u8, 0]])))
  assert exhaustedAfter.value.exit == StepExit.OutOfGas, "second fixed eject charge is unaffordable"
  let selected = normalizeAccumulationOutcome(exhaustedAfter).value.outcomeContext.value
  assert balance(selected) == (if checkpoint: 177'u64 else: 100'u64), "OOG chooses matching account/balance checkpoint"
let before = getOccupiedMem()
for iteration in 0..<1000:
  let completed = run(valid)
  removed(context(completed)) # Release each CPU and complete-map successor without retaining intermediate owners.
let after = getOccupiedMem()
assert before == after, "eject releases all ARC-owned snapshots"
recordArcRelease("pvm_accumulation_eject", 1000, before, after)
echo "PVM accumulation eject passed"
echo "ARC_RELEASE cycles=1000 unchanged"
