# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_transfer_arc_release"}

## Authored transfer programs verify conditional fees, deferred balances and immutable outgoing/checkpoint owners.

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite, state_layout, state_accounts, state_requests,
  state_service_values, state_privileges, state_authorization, state_safrole, state_outputs,
  state_trie, c2_records]
import ../../../src/state/[accumulation_dispatch, accumulation_effects, accumulation_context,
  accumulation_machine, accumulation_invocation, accumulation_outcome, store]
import ../../../src/pvm/[machine, program, step, gas, host_fetch]
import ../../../src/crypto/primitives
import ../../support/[pvm_accumulation_program, pvm_accumulation_context, arc_evidence]

# Fail only after real fixture construction, retaining the maintained primitive implementation.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
# Detect writes/hashing during pure fee evaluation or unaffordable successful rows.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
# Exercise cleanup after successful candidate-tree child hashes.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

# Fixed-width parameter construction gives independent deposit and memo/profile witnesses.
proc parameters(base = 10'u64, item = 0'u64, octet = 0'u64): Parameters =
  var bytes = encodeParameters(pvmParameters())
  for field, value in [item, octet, base]:
    for i in 0..<8:
      bytes[field*8+i] = byte((value shr (8*i)) and 255) # Exact E8 tuple order is item/byte/account.
  bytes[24] = 2
  bytes[25] = 0
  bytes[82] = 80
  bytes[83] = 0
  for i in 110..<114:
    bytes[i] = 0 # transferMemoSize is the E4 field before maxExports/epochTailStart.
  bytes[110] = 128
  result = decodeParameters(bytes).value
  assert result.get(transferMemoSize) == 128, "independent memo parameter offset"

# Memo octets are fixed opaque values, neither a string nor a length-prefixed payload.
proc payload(): seq[byte] =
  result = newSeq[byte](128)
  for i in 0..<128:
    result[i] = byte((i*7+3) mod 256) # Bounded pattern spans every memo octet.

proc immediate(index: byte, value: uint64): seq[byte] =
  ## Fixed-width authored operands preserve identical instruction pricing across full-width edge values.
  registerImmediate(index, value)

proc transferCall(destination = 99'u64, amount = 5'u64, gas = 9'u64, address = 196608'u64,
    suffix: seq[seq[byte]] = @[], mode = 0'u64, funder = high(uint64)): seq[seq[byte]] =
  ## Current liquid self-funded deferred transfer: source/destination/mode/amount/gas/memo in r7-r12.
  result = @[immediate(7, funder), immediate(8, destination), (if mode == 0: @[51'u8, 9,
      0] else: immediate(9, mode)),
    immediate(10, amount), immediate(11, gas), immediate(12, address), @[10'u8, 22]]
  for instruction in suffix:
    result.add(instruction) # Explicit appending retains each current call's complete argument setup.

# Build genuine host calls over current self/target accounts and independently bounded storage.
proc source(destination = 99'u64, amount = 5'u64, gas = 9'u64, address = 196608'u64,
    credit = 100000'u64, account = ServiceMetadata(balance: AccountBalance(100),
        minimumTransferGas: Gas(6)),
    target = 99'u32, targetGas = 7'u64, includeTarget = true, role = 42'u32,
    data: seq[byte] = payload(), extra: seq[StateEntry] = @[], writes = 3'u64,
    suffix: seq[seq[byte]] = @[@[50'u8, 0]], mode = 0'u64, funder = high(uint64),
    targetAccount = ServiceMetadata(balance: AccountBalance(77))): PreparedAccumulationMachine =
  var entries = extra
  if includeTarget:
    var recipient = targetAccount
    recipient.minimumTransferGas = Gas(targetGas)
    entries.add(serviceMetadataEntry(ServiceIndex(target), recipient,
        ByteLimit(ServiceMetadataBytes)).value) # Optional metadata permits explicit destination-supervision witnesses.
  var instructions = transferCall(destination, amount, gas, address, mode = mode, funder = funder)
  for instruction in suffix:
    instructions.add(instruction) # Later calls execute through the same decoded production stream.
  guestProgram(instructions, credit, account = account, writable = data, extra = entries,
    manager = role, delegator = role, assigner = role, writes = writes, spareEntries = 4)

# Capacity is charged only after protocol validation and complete conditional affordability.
proc run(prepared: PreparedAccumulationMachine, limit = 128'u64, capacity = 4'u64,
    params: Parameters = parameters()): AccumulationDispatchResult =
  executeAccumulationMachine(prepared, params,
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
      operand: OperandLimits(maxBytes: ByteLimit(132))), MemoryByteLimit(limit),
    ExecutionStepLimit(100), HostCallLimit(10), GasCycleLimit(1000), pvmContextConfig(),
    serviceProbes = ServiceProbeLimit(1), transferLimit = ElementLimit(capacity))

# Basic-block instruction prices are independent from the conditional host fee.
proc price(prepared: PreparedAccumulationMachine): uint64 =
  uint64(blockGas(programOf(prepared.accumulationMachine.value).value, CodeAddress(5),
      GasCycleLimit(1000)).value)

# Retain only a completed guest execution's own exact implication version.
proc context(done: AccumulationDispatchResult, dimension = AccumulationDimension.Regular): AccumulationEffectContext =
  assert done.error == AccumulationDispatchError.None, "completed execution grants outgoing effects"
  done.effects.effectContext(dimension).value

# Current canonical metadata provides independent debit/non-credit checks.
proc metadata(owner: AccumulationEffectContext, service = 42'u32): ServiceMetadata =
  let found = owner.effectAccounts.value.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      service))).value
  decodeServiceMetadata(found.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata

# Extraction copies every fixed transfer field, preserving append order and opaque memo identity.
proc checkTransfer(owner: AccumulationEffectContext, index = 0'u64, destination = 99'u32,
    amount = 5'u64, gas = 9'u64, memo: seq[byte] = payload()) =
  let selected = owner.effectTransferAt(AccumulationTransferIndex(index))
  assert selected.error == AccumulationEffectError.None, "selected outgoing ordinal exists"
  let value = selected.value
  assert uint32(value.source) == 42 and uint32(value.destination) == destination, "source/target identity"
  assert uint64(value.amount) == amount and uint64(value.gas) == gas, "complete amount and deferred gas"
  let bytes = array[128, byte](value.memo)
  for i in 0..<128:
    assert bytes[i] == memo[i], "ordered raw memo copied exactly"

let valid = source()
let done = run(valid)
assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt, "funded transfer completes"
assert uint64(machineInfo(done.value.machine).value.registers[7]) == 0, "transfer returns OK"
assert uint64(machineInfo(done.value.machine).value.gas) == 100000-price(valid)-584, "successful fee includes deferred gas"
checkTransfer(context(done))
assert context(done).effectInfo.value.transfers == 1 and uint64(metadata(context(done)).balance) ==
    95, "debit and append publish together"
assert uint64(metadata(context(done), 99).balance) == 77, "destination is not credited during this invocation"
let initial = context(done, AccumulationDimension.Exceptional)
assert initial.effectInfo.value.transfers == 0 and uint64(metadata(initial).balance) == 100, "checkpoint retains original debit/list"
assert normalizeAccumulationOutcome(done).value.outcomeInfo.value.transfers == 1, "normalization reports retained outgoing count"
for chapter in [2, 7, 12]:
  assert context(done).effectAccounts.value.lookup(chapterKey(StateChapter(chapter))).value.bytes ==
    initial.effectAccounts.value.lookup(chapterKey(StateChapter(chapter))).value.bytes, "unrelated component unchanged"
assert readBytes(memoryOf(valid.accumulationMachine.value).value, MemoryAddress(196608),
    MemoryLength(128), MemoryByteLimit(128)).value ==
  readBytes(memoryOf(done.value.machine).value, MemoryAddress(196608), MemoryLength(128),
      MemoryByteLimit(128)).value, "transfer never writes memo memory"
for amount in [0'u64, 90, 91, 100, 101, high(uint64)]:
  let completed = run(source(amount = amount))
  if amount <= 90:
    checkTransfer(context(completed), amount = amount)
    assert uint64(metadata(context(completed)).balance) == 100-amount, "exact sender funding boundary"
  else:
    assert uint64(machineInfo(completed.value.machine).value.registers[7]) == high(uint64)-6, "CASH protects sender threshold and subtraction"
    assert context(completed).effectInfo.value.transfers == 0 and uint64(metadata(context(
        completed)).balance) == 100, "CASH never debits or appends"
    assert uint64(machineInfo(completed.value.machine).value.gas) == 100000-price(valid)-575, "CASH pays no deferred gas"
# A full-width amount can succeed without narrowing, with exact subtraction to zero under a zero deposit schedule.
let entireBalance = run(source(amount = high(uint64),
  account = ServiceMetadata(balance: AccountBalance(high(uint64)))), params = parameters(0))
checkTransfer(context(entireBalance), amount = high(uint64))
assert uint64(metadata(context(entireBalance)).balance) == 0 and
  uint64(metadata(context(entireBalance), 99).balance) == 77, "full-width balance debit remains deferred"
let selfTransfer = run(source(destination = 42, gas = 6))
checkTransfer(context(selfTransfer), destination = 42, gas = 6)
checkTransfer(context(run(source(destination = high(uint64), gas = 6))), destination = 42, gas = 6)
assert uint64(metadata(context(selfTransfer)).balance) == 95, "self-transfer is deferred, with no immediate credit"
checkTransfer(context(run(source(role = 0)))) # No privileged role is required.
for destination in [0'u64, uint64(high(uint32))]:
  checkTransfer(context(run(source(destination = destination, target = uint32(destination)))),
      destination = uint32(destination)) # Complete service domain, without sentinels.
for destination in [123'u64, 0x100000063'u64, high(uint64)-1]:
  let refused = run(source(destination = destination, amount = high(uint64), gas = high(uint64)), capacity = 0)
  assert uint64(machineInfo(refused.value.machine).value.registers[7]) == high(uint64)-3, "WHO precedes LOW/CASH and append capacity"
  assert uint64(machineInfo(refused.value.machine).value.gas) == 100000-price(valid)-575, "WHO pays only base, even for huge offered gas"
# A present malformed current target is a local state refusal, never a fabricated WHO or LOW response.
let malformed = StateEntry(key: chapterServiceKey(StateChapter(255), ServiceIndex(99)), value: @[0'u8])
assert run(source(includeTarget = false, extra = @[malformed])).error ==
  AccumulationDispatchError.MalformedState, "canonical target metadata required"
let low = run(source(gas = 6, amount = high(uint64)), capacity = 0)
assert uint64(machineInfo(low.value.machine).value.registers[7]) == high(uint64)-7, "LOW precedes CASH and capacity"
assert uint64(machineInfo(low.value.machine).value.gas) == 100000-price(valid)-575, "LOW pays only base"
let unsupervisedDirect = run(source(address = 0), limit = 0, capacity = 0)
assert uint64(machineInfo(unsupervisedDirect.value.machine).value.registers[7]) == high(uint64)-8,
    "direct credit requires destination authority even when deferred credit is permitted"
for address in [65536'u64+4096-64, 196608'u64+8192-64, 0x100000000'u64, high(uint64)]:
  let failed = run(source(address = address, destination = high(uint64), gas = high(uint64),
      amount = high(uint64)))
  assert failed.value.exit == StepExit.Panic and uint64(machineInfo(
      failed.value.machine).value.registers[7]) == high(uint64), "memo failure precedes WHO/LOW/CASH and preserves r7"
  assert uint64(machineInfo(failed.value.machine).value.gas) == 100000-price(valid)-575, "panic charges base only"
# Undefined modes preserve gas, memo and service-existence precedence without producing outgoing work.
for mode in [4'u64, high(uint64)]:
  let prepared = source(mode = mode, gas = high(uint64))
  let refused = run(prepared, capacity = 0)
  assert refused.error == AccumulationDispatchError.None and refused.value.exit == StepExit.Halt, "undefined transfer mode completes with a refusal"
  assert uint64(machineInfo(refused.value.machine).value.registers[7]) == high(uint64)-8, "existing accounts precede undefined-mode HUH"
  assert uint64(machineInfo(refused.value.machine).value.gas) == 100000-price(prepared)-575, "undefined mode never charges deferred gas"
  assert context(refused).effectInfo.value.transfers == 0 and uint64(metadata(context(
      refused)).balance) == 100, "undefined mode never debits or appends"
  assert run(source(mode = mode, address = high(uint64), includeTarget = false)).value.exit ==
      StepExit.Panic, "unreadable memo precedes missing-service WHO"
  let absent = run(source(mode = mode, includeTarget = false))
  assert uint64(machineInfo(absent.value.machine).value.registers[7]) == high(uint64)-3, "missing destination precedes undefined-mode HUH"
  let wide = run(source(mode = mode, destination = 0x100000063'u64))
  assert uint64(machineInfo(wide.value.machine).value.registers[7]) == high(uint64)-3, "full-width destination never aliases the existing low E4 account"
  let direct = run(source(mode = mode, address = 0), limit = 0)
  assert uint64(machineInfo(direct.value.machine).value.registers[7]) == high(uint64)-8, "undefined direct mode skips memo capture and returns HUH"
  assert run(source(mode = mode, address = high(uint64), credit = price(prepared)+574),
      limit = 0).value.exit == StepExit.OutOfGas, "base-fee underfunding precedes invalid-mode memory checks"
# Valid protected source modes refuse CASH when that selected source pool is empty.
for mode in [1'u64, 3]:
  let emptyProtected = run(source(mode = mode))
  assert uint64(machineInfo(emptyProtected.value.machine).value.registers[7]) == high(uint64)-6,
      "valid protected funding cannot borrow from liquid balance"
let protectedDestination = run(source(mode = 2))
assert context(protectedDestination).effectTransferAt(AccumulationTransferIndex(
    0)).value.destinationSupervisor,
    "liquid funding can select a deferred protected destination"
var ro = newSeq[byte](128)
ro[0] = 73
checkTransfer(context(run(source(address = 65536))), memo = ro) # Read-only memo input is valid.
checkTransfer(context(run(source(address = 196608'u64+4096-64))), memo = newSeq[byte](
    128)) # Complete crossing read spans adjacent RW pages.
assert run(valid, limit = 127).error == AccumulationDispatchError.LimitExceeded, "memo capture budget exact edge"
assert run(valid, capacity = 0).error == AccumulationDispatchError.LimitExceeded, "outgoing capacity is explicit"
var wrong = encodeParameters(parameters())
wrong[110] = 127
assert run(valid, params = decodeParameters(wrong).value).error ==
    AccumulationDispatchError.InvalidContext, "fixed memo/profile mismatch refuses locally"
for available in [0'u64, 574, 575, 583, 584, 585]:
  let completed = run(source(credit = price(valid)+available), capacity = (if available <
      584: 0'u64 else: 1'u64))
  assert completed.error == AccumulationDispatchError.None, "conditional successful-row gas edge"
  let cpu = machineInfo(completed.value.machine).value
  if available < 584:
    assert completed.value.exit == StepExit.OutOfGas and uint64(cpu.gasDeficit) == 0, "exact full fee deficit even below base credit"
    assert uint64(cpu.registers[7]) == high(uint64) and context(
        completed).effectInfo.value.transfers == 0, "OOG wins before append capacity and publishes no transfer"
  else:
    assert completed.value.exit == StepExit.Halt and uint64(cpu.gas) == available-584, "full funded fee"
for available in [0'u64, 574, 575, 576]:
  for mode in 0..<4:
    let completed = run(source(destination = (if mode == 0: high(uint64)-1 else: 99'u64),
      gas = (if mode == 1: 6'u64 else: high(uint64)), amount = (if mode == 2: high(
          uint64) else: 5'u64),
      address = (if mode == 3: high(uint64) else: 196608'u64), credit = price(valid)+available), capacity = 0)
    let cpu = machineInfo(completed.value.machine).value
    if available < 575:
      assert completed.value.exit == StepExit.OutOfGas and uint64(cpu.gasDeficit) == 0, "refusal quotes exact base-only deficit"
    else:
      assert uint64(cpu.gas) == available-575, "funded refusal pays base-only cost"
      if mode == 3:
        assert completed.value.exit == StepExit.Panic, "funded unreadable memo panics"
      else:
        assert uint64(cpu.registers[7]) == (if mode == 0: high(uint64)-3 elif mode == 1: high(
            uint64)-7 else: high(uint64)-6), "funded protocol refusal priority"
let huge = run(source(gas = high(uint64), credit = high(uint64)))
assert huge.error == AccumulationDispatchError.None and huge.value.exit == StepExit.OutOfGas, "full fee retains the 65th bit"
assert uint64(machineInfo(huge.value.machine).value.gasDeficit) == 0, "exact high-limb borrowing"
assert run(source(gas = high(uint64), credit = price(valid))).value.exit == StepExit.OutOfGas, "valid huge fee cannot degrade to base-only OOG"
let boundary = run(source(gas = 0x8000000000000000'u64, credit = price(valid)+575))
assert boundary.value.exit == StepExit.OutOfGas and uint64(machineInfo(
    boundary.value.machine).value.gasDeficit) == 0, "exact signed-negative boundary"
assert run(source(gas = 0x8000000000000000'u64, credit = price(valid)+574)).value.exit ==
    StepExit.OutOfGas, "unrepresentable signed debt remains explicit"
let fullCredit = run(source(credit = high(uint64)))
assert uint64(machineInfo(fullCredit.value.machine).value.gas) == high(uint64)-price(valid)-584, "full-width funded credit"
let duplicates = run(source(suffix = @[immediate(7, high(uint64)), @[10'u8, 22],
  immediate(7, high(uint64)), @[10'u8, 22], @[50'u8, 0]]))
assert context(duplicates).effectInfo.value.transfers == 3 and uint64(metadata(context(
    duplicates)).balance) == 85, "ordered duplicates are independent deferred debits"
for i in 0..<3:
  checkTransfer(context(duplicates), index = uint64(
      i)) # Repeated identical records are never deduplicated.
let ordered = run(source(suffix = transferCall(destination = 42, amount = 0, gas = 6,
    address = 65536, suffix = @[@[50'u8, 0]])))
checkTransfer(context(ordered))
checkTransfer(context(ordered), index = 1, destination = 42, amount = 0, gas = 6, memo = ro)
for checkpoint in [false, true]:
  let failed = run(source(suffix = (if checkpoint: @[@[10'u8, 19], @[0'u8]] else: @[@[0'u8]])))
  let selected = normalizeAccumulationOutcome(failed).value.outcomeContext.value
  assert selected.effectInfo.value.transfers == (if checkpoint: 1 else: 0) and uint64(metadata(
      selected).balance) == (if checkpoint: 95'u64 else: 100'u64), "panic selects matching debit/list checkpoint"
  var ending: seq[seq[byte]] = @[]
  if checkpoint:
    ending.add(@[10'u8, 19]) # Checkpoint the first debit before the complete second transfer call.
  for instruction in transferCall(suffix = @[@[50'u8, 0]]):
    ending.add(instruction) # Preserve complete current arguments without relying on sequence insertion.
  let exhausted = run(source(credit = price(valid)+750, suffix = ending))
  assert exhausted.value.exit == StepExit.OutOfGas, "second transfer unaffordable"
  let retained = normalizeAccumulationOutcome(exhausted).value.outcomeContext.value
  assert retained.effectInfo.value.transfers == (if checkpoint: 1 else: 0) and uint64(metadata(
      retained).balance) == (if checkpoint: 95'u64 else: 100'u64), "OOG selects matching debit/list checkpoint"
# Upgrade changes the current self target's transfer minimum without changing the active program.
var upgradeInstructions = @[immediate(7, high(uint64)), immediate(8, 65536), immediate(9, 0),
  immediate(10, 100), @[10'u8, 21]]
for instruction in transferCall(destination = 42, gas = 99, suffix = @[@[50'u8, 0]]):
  upgradeInstructions.add(instruction) # The transfer observes the upgraded self account immediately.
let upgraded = guestProgram(upgradeInstructions, credit = 100000,
  account = ServiceMetadata(balance: AccountBalance(100)), writable = payload())
assert uint64(machineInfo(run(upgraded).value.machine).value.registers[7]) == high(uint64)-7, "LOW reads current upgraded destination minimum"
# Newly created targets are visible immediately, but receive no immediate credit from transfer.
var childRequest = payload()
childRequest.setLen(188)
childRequest[128] = 73 # Opaque code hash matches the existing read-only fixture prefix.
childRequest[160] = 5 # E4 code length.
childRequest[172] = 7 # E8 minimum transfer gas; all other configuration bytes remain zero.
let creating = guestProgram([immediate(7, high(uint64)), immediate(8, high(uint64)),
  immediate(9, 0), immediate(10, 196736), @[10'u8, 20], @[100'u8, 0x78],
  immediate(7, high(uint64)), immediate(9, 0), immediate(10, 5), immediate(11, 9),
  immediate(12, 196608), @[10'u8, 22], @[50'u8, 0]],
  credit = 100000, account = ServiceMetadata(balance: AccountBalance(100)), writable = childRequest,
  writes = 3, spareEntries = 2)
let created = run(creating)
assert context(created).effectInfo.value.transfers == 1 and uint64(metadata(context(
    created)).balance) == 85, "transfer sees new current account and preserves new debit"
let newTarget = context(created).effectTransferAt(AccumulationTransferIndex(0)).value.destination
assert uint64(metadata(context(created), uint32(newTarget)).balance) == 10, "new target credit remains deferred"
# Prepared plans retain source provenance and fixed memo copies; no hash or debit occurs before commit.
let prepared = prepareAccumulationEffects(done.effects.effectsSource.value).value
var memo = default(array[128, byte])
let raw = payload()
for i in 0..<128:
  memo[i] = raw[i] # Stable fixed proposal data is independent of guest memory.
failHash(1)
let plan = prepareAccumulationTransfer(prepared, AccumulationTransferDestination(99),
    TransferBalance(5), Gas(9), TransferMemo(memo), parameters())
assert plan.error == AccumulationEffectError.None and hashCalls() == 0, "pure preparation does no hashing"
failHash(0)
memo[0] = 255
let committed = commitAccumulationTransfer(plan.value, ElementLimit(1))
assert committed.error == AccumulationEffectError.None, "bound plan commits"
checkTransfer(committed.value.effectContext(AccumulationDimension.Regular).value)
assert prepared.effectContext(AccumulationDimension.Regular).value.effectInfo.value.transfers == 0, "source pair remains independent"
let reused = commitAccumulationTransfer(plan.value, ElementLimit(1)).value
assert reused.effectContext(AccumulationDimension.Regular).value.effectInfo.value.transfers == 1, "plan reuse starts from its bound source, not an ambient successor"
var copied = committed.value.effectContext(AccumulationDimension.Regular).value.effectTransferAt(
    AccumulationTransferIndex(0)).value
copied.memo = TransferMemo(default(array[128, byte]))
checkTransfer(committed.value.effectContext(AccumulationDimension.Regular).value) # Extracted fixed values cannot mutate private outgoing storage.
assert commitAccumulationTransfer(plan.value, ElementLimit(0)).error ==
    AccumulationEffectError.LimitExceeded, "direct append policy"
assert commitAccumulationTransfer(default(PreparedAccumulationTransfer), ElementLimit(1)).error ==
    AccumulationEffectError.Uninitialized, "default plan cannot publish"
assert default(AccumulationEffectContext).effectTransferAt(AccumulationTransferIndex(0)).error ==
    AccumulationEffectError.Uninitialized, "default context has no transfers"
assert context(done).effectTransferAt(AccumulationTransferIndex(high(uint64))).error ==
    AccumulationEffectError.InvalidIndex, "full-width outgoing ordinal cannot narrow"
# Every older mutation must preserve a nonempty outgoing owner through the private successor helper.
let effects = done.effects
let yielded = recordAccumulationYield(effects, OutputCommitment(default(array[32, byte]))).value
let blessed = recordAccumulationBless(effects, PrivilegeState(manager: ServiceIndex(42),
    delegator: ServiceIndex(42),
  assigners: @[ServiceIndex(42), ServiceIndex(42)]), pvmContextConfig().privileges).value
let assigned = recordAccumulationAssign(effects, AuthorizationCoreIndex(0), newSeq[AuthorizerHash](
    80), ServiceIndex(42), pvmContextConfig().queues, pvmContextConfig().privileges).value
let designated = recordAccumulationDesignate(effects, newSeq[StateValidator](6), pvmContextConfig().staging).value
let changedCode = recordAccumulationUpgrade(effects, default(CodeHash), Gas(0), Gas(0)).value
let stored = recordAccumulationStorage(effects, [73'u8], [1'u8], parameters(), ByteLimit(
    1)).value.effects
let born = recordAccumulationNew(effects, AccumulationNewService(length: RequestLength(5)),
    parameters(), ServiceProbeLimit(1)).value.effects
for successor in [yielded, blessed, assigned, designated, changedCode, stored, born]:
  assert successor.effectContext(AccumulationDimension.Regular).value.effectInfo.value.transfers ==
      1, "existing mutation retains outgoing owner"
  checkTransfer(successor.effectContext(AccumulationDimension.Regular).value) # All retained fields and ordered memos remain exact.
# Provision append also shares the frozen outgoing sequence and preserves the existing account debit.
let blob = @[4'u8, 5, 6]
let request = serviceRequestEntry(ServiceIndex(42), ServicePreimageHash(array[32, byte](blake2b256(
    blob).value)), RequestLength(3), requestedHistory(),
  RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(items: ElementLimit(0),
      maxBytes: ByteLimit(1)))).value
let provisionSource = run(source(extra = @[request]))
let provisioned = recordAccumulationProvision(provisionSource.effects, ServiceIndex(42), blob,
    AccumulationProvisionLimits(items: ElementLimit(1), perBlob: ByteLimit(3),
    totalBlobBytes: ByteLimit(3))).value
checkTransfer(provisioned.effectContext(AccumulationDimension.Regular).value)
assert provisioned.effectContext(AccumulationDimension.Regular).value.effectInfo.value.provisions ==
    1, "provision and outgoing owners coexist"
assert run(source(writes = 0)).error == AccumulationDispatchError.LimitExceeded, "inherited store capacity refuses atomically"
for successful in [0, 2]:
  failAfter(cint(successful))
  let failed = commitAccumulationTransfer(plan.value, ElementLimit(1))
  assert failed.error == AccumulationEffectError.BackendFailure and hashCalls() == cint(
      successful+1), "atomic immediate/delayed debit Merklization failure"
  failHash(0)
  assert uint64(metadata(prepared.effectContext(AccumulationDimension.Regular).value).balance) ==
      100 and prepared.effectContext(
      AccumulationDimension.Regular).value.effectInfo.value.transfers == 0, "failed commit retains source balance/list"
let unaffordable = source(credit = price(valid)+575)
failHash(1)
assert run(unaffordable, capacity = 0).value.exit == StepExit.OutOfGas and hashCalls() == 0, "unaffordable valid transfer performs no hash or append"
failHash(0)
# All four modes preserve actual payer identity and select independent source/destination pools.
proc fundedActor(supervisor = 42'u32, incarnation = 43'u32): ServiceMetadata =
  ServiceMetadata(balance: AccountBalance(100), supervisorBalance: AccountBalance(100),
      created: AccountSlot(43), supervisor: ServiceIndex(supervisor),
          supervisorCreated: AccountSlot(incarnation))
proc payer(balance = 100'u64, protected = 100'u64, supervisor = 42'u32): StateEntry =
  serviceMetadataEntry(ServiceIndex(77), ServiceMetadata(balance: AccountBalance(balance),
      supervisorBalance: AccountBalance(protected), created: AccountSlot(7),
          supervisor: ServiceIndex(supervisor),
      supervisorCreated: AccountSlot(43)), ByteLimit(ServiceMetadataBytes)).value
for foreign in [false, true]:
  for mode in 0'u64..3:
    let guest = source(mode = mode, funder = (if foreign: 77'u64 else: high(uint64)),
        account = fundedActor(), extra = (if foreign: @[payer()] else: @[]))
    let completed = run(guest)
    assert completed.error == AccumulationDispatchError.None and completed.value.exit ==
        StepExit.Halt,
        "authorized deferred funding modes complete"
    let owner = context(completed)
    let transfer = owner.effectTransferAt(AccumulationTransferIndex(0)).value
    let funder = if foreign: 77'u32 else: 42'u32
    assert uint32(transfer.source) == funder and uint32(transfer.destination) == 99,
        "deferred source is the actual payer, not the supervising invoker"
    assert transfer.destinationSupervisor == (mode >= 2), "mode selects the exact future destination pool"
    let paid = metadata(owner, funder)
    assert uint64(paid.balance) == (if mode in [0'u64, 2]: 95'u64 else: 100'u64) and
        uint64(paid.supervisorBalance) == (if mode in [1'u64, 3]: 95'u64 else: 100'u64),
        "only the selected payer pool is debited"
    let destination = metadata(owner, 99)
    assert uint64(destination.balance) == 77 and uint64(destination.supervisorBalance) == 0,
        "deferred funding never credits either destination pool during this invocation"
    assert uint64(machineInfo(completed.value.machine).value.gas) == 100000-price(guest)-584,
        "every successful mode pays the same base plus deferred fee"
    assert (owner.effectAccountScope.value == AccumulationAccountScope.Unsupported) == foreign,
        "self metadata proofs cannot certify a foreign payer"
    if foreign:
      assert uint64(metadata(owner).balance) == 100 and uint64(metadata(owner).supervisorBalance) ==
          100,
          "foreign funding preserves both invoker balances"
# Protected source authority is incarnation-bound even for self.
let delegate = serviceMetadataEntry(ServiceIndex(98), ServiceMetadata(created: AccountSlot(7)),
    ByteLimit(ServiceMetadataBytes)).value
for stale in [false, true]:
  for mode in 0'u64..3:
    let completed = run(source(mode = mode, account = fundedActor(supervisor = 98,
        incarnation = (if stale: 6'u32 else: 7'u32)), extra = @[delegate]))
    let huh = not stale and mode in [1'u64, 3]
    assert (uint64(machineInfo(completed.value.machine).value.registers[7]) == high(uint64)-8) ==
        huh,
        "matching effective supervision controls protected self funds"
for mode in 0'u64..3:
  let denied = source(mode = mode, funder = 77, gas = 0, amount = high(uint64),
      account = fundedActor(), extra = @[payer(supervisor = 77)])
  failHash(1)
  let refused = run(denied, capacity = 0)
  assert uint64(machineInfo(refused.value.machine).value.registers[7]) == high(uint64)-8 and
      hashCalls() == 0,
      "authority HUH precedes LOW and CASH without hashing or append capacity"
  failHash(0)
  assert uint64(machineInfo(refused.value.machine).value.gas) == 100000-price(denied)-575,
      "unauthorized funding charges no deferred gas"
  let short = if mode in [0'u64, 2]: payer(balance = 4) else: payer(protected = 4)
  let cash = run(source(mode = mode, funder = 77, account = fundedActor(), extra = @[short]))
  assert uint64(machineInfo(cash.value.machine).value.registers[7]) == high(uint64)-6,
      "another pool cannot conceal selected source underflow"
for funder in [100'u64, 0x10000002a'u64]:
  let absent = run(source(funder = funder, gas = 0, amount = high(uint64)))
  assert uint64(machineInfo(absent.value.machine).value.registers[7]) == high(uint64)-3,
      "source WHO precedes LOW and CASH without low-bit aliases"
  let unreadable = run(source(funder = funder, address = high(uint64)))
  assert unreadable.value.exit == StepExit.Panic, "memo panic precedes missing source WHO"
for balance in [14'u64, 15]:
  let completed = run(source(funder = 77, account = fundedActor(), extra = @[payer(
      balance = balance, protected = 0)]))
  assert (uint64(machineInfo(completed.value.machine).value.registers[7]) == high(uint64)-6) == (
      balance == 14),
      "deferred funding retains the payer's own exact aggregate threshold"
let foreignSource = source(mode = 3, funder = 77, account = fundedActor(), extra = @[payer()])
for checkpoint in [false, true]:
  let suffix = if checkpoint: @[@[10'u8, 19], @[0'u8]] else: @[@[0'u8]]
  let failed = run(source(mode = 3, funder = 77, account = fundedActor(), extra = @[payer()],
      suffix = suffix))
  let selected = normalizeAccumulationOutcome(failed).value.outcomeContext.value
  assert (uint64(metadata(selected, 77).supervisorBalance) == 95) == checkpoint and
      (selected.effectInfo.value.transfers == 1) == checkpoint,
      "foreign payer and outgoing flag remain paired across checkpoint selection"
let foreignPair = prepareAccumulationEffects(prepareAccumulationContexts(
    foreignSource.machineBootstrap.value, pvmContextConfig()).value).value
let foreignPlan = prepareAccumulationTransfer(foreignPair, AccumulationTransferDestination(99),
    TransferBalance(5), Gas(9), TransferMemo(memo), parameters(), ServiceIndex(77),
        AccumulationFundingMode(3))
assert foreignPlan.error == AccumulationEffectError.None, "pure foreign validation yields a bound plan"
for successful in [0, 2]:
  failAfter(cint(successful))
  let refused = commitAccumulationTransfer(foreignPlan.value, ElementLimit(1))
  assert refused.error == AccumulationEffectError.BackendFailure, "foreign debit and append refuse atomically on backend failure"
  failHash(0)
  let prior = foreignPair.effectContext(AccumulationDimension.Regular).value
  assert uint64(metadata(prior, 77).supervisorBalance) == 100 and
      prior.effectInfo.value.transfers == 0,
      "failed foreign commit retains its source map and outgoing owner"
let poorGas = source(mode = 3, funder = 77, account = fundedActor(), extra = @[payer()],
    credit = price(foreignSource)+583)
failHash(1)
let poor = run(poorGas, capacity = 0)
assert poor.value.exit == StepExit.OutOfGas and hashCalls() == 0,
    "unaffordable protected foreign transfer neither hashes nor appends"
failHash(0)
# Zero memo selects immediate credit with base-only gas and no outgoing capacity or copying.
proc supervisedTarget(supervisor = 42'u32, incarnation = 43'u32,
    liquid = 77'u64, protected = 55'u64): ServiceMetadata =
  ServiceMetadata(balance: AccountBalance(liquid), supervisorBalance: AccountBalance(protected),
      supervisor: ServiceIndex(supervisor), supervisorCreated: AccountSlot(incarnation),
          created: AccountSlot(7))
for foreignSource in [false, true]:
  for foreignTarget in [false, true]:
    for mode in 0'u64..3:
      let guest = source(address = 0, mode = mode, gas = high(uint64), targetGas = high(uint64),
          funder = (if foreignSource: 77'u64 else: high(uint64)),
          destination = (if foreignTarget: 99'u64 else: high(uint64)),
          account = fundedActor(), targetAccount = supervisedTarget(),
          extra = (if foreignSource: @[payer()] else: @[]))
      let completed = run(guest, limit = 0, capacity = 0)
      assert completed.error == AccumulationDispatchError.None and completed.value.exit ==
          StepExit.Halt,
          "direct forms complete without memo/deferred gas or append capacity"
      let same = not foreignSource and not foreignTarget
      let forbidden = same and mode in [0'u64, 3]
      let cpu = machineInfo(completed.value.machine).value
      assert uint64(cpu.registers[7]) == (if forbidden: high(uint64)-8 else: 0'u64),
          "same-account direct transfer permits exactly cross-pool modes"
      assert uint64(cpu.gas) == 100000-price(guest)-575, "direct calls charge only base despite full-width deferred gas"
      let owner = context(completed)
      assert owner.effectInfo.value.transfers == 0, "direct success never appends a deferred record"
      if not forbidden:
        let sourceId = if foreignSource: 77'u32 else: 42'u32
        let targetId = if foreignTarget: 99'u32 else: 42'u32
        let paid = metadata(owner, sourceId)
        let credited = metadata(owner, targetId)
        let sourceLiquid = 100'u64 - (if mode in [0'u64, 2]: 5'u64 else: 0'u64) +
            (if same and mode < 2: 5'u64 else: 0'u64)
        let sourceProtected = 100'u64 - (if mode in [1'u64, 3]: 5'u64 else: 0'u64) +
            (if same and mode >= 2: 5'u64 else: 0'u64)
        assert uint64(paid.balance) == sourceLiquid and uint64(paid.supervisorBalance) ==
            sourceProtected,
            "direct selected debit and same-account credit combine into one source record"
        if not same:
          let targetLiquid = (if foreignTarget: 77'u64 else: 100'u64) + (if mode <
              2: 5'u64 else: 0'u64)
          let targetProtected = (if foreignTarget: 55'u64 else: 100'u64) + (if mode >=
              2: 5'u64 else: 0'u64)
          assert uint64(credited.balance) == targetLiquid and uint64(credited.supervisorBalance) ==
              targetProtected,
              "a distinct immediate destination receives exactly its selected pool credit"
        assert (owner.effectAccountScope.value == AccumulationAccountScope.Unsupported) == (
            foreignSource or foreignTarget),
            "only genuine self metadata changes retain the bounded publication proof"
# Cross-pool self moves check aggregate funding after the credit, not after a temporary debit.
for mode in [1'u64, 2]:
  let exact = ServiceMetadata(balance: AccountBalance(6), supervisorBalance: AccountBalance(4))
  let completed = run(source(address = 0, destination = high(uint64), mode = mode,
      account = exact, amount = (if mode == 1: 4'u64 else: 6'u64), gas = high(uint64)), limit = 0, capacity = 0)
  assert uint64(machineInfo(completed.value.machine).value.registers[7]) == 0,
      "an exact-minimum self account can move its complete selected pool"
for mode in 0'u64..3:
  let denied = source(address = 0, mode = mode, gas = 0, amount = high(uint64),
      account = fundedActor(), targetAccount = supervisedTarget(incarnation = 42))
  failHash(1)
  let refused = run(denied, limit = 0, capacity = 0)
  assert uint64(machineInfo(refused.value.machine).value.registers[7]) == high(uint64)-8 and
      hashCalls() == 0,
      "stale destination authority HUH precedes CASH and performs no hashing"
  failHash(0)
  let missing = run(source(address = 0, mode = mode, includeTarget = false, account = fundedActor(
    )), limit = 0, capacity = 0)
  assert uint64(machineInfo(missing.value.machine).value.registers[7]) == high(uint64)-3,
      "missing destination WHO precedes valid-mode authority"
# Distinct destination credit cannot restore source funding or hide selected-pool underflow.
for mode in 0'u64..3:
  let short = ServiceMetadata(balance: AccountBalance(if mode in [0'u64, 2]: 4'u64 else: 100'u64),
      supervisorBalance: AccountBalance(if mode in [1'u64, 3]: 4'u64 else: 100'u64),
          created: AccountSlot(43))
  let refused = run(source(address = 0, mode = mode, account = short,
      targetAccount = supervisedTarget()), limit = 0, capacity = 0)
  assert uint64(machineInfo(refused.value.machine).value.registers[7]) == high(uint64)-6,
      "direct selected-pool underflow remains CASH with a rich other pool"
for balance in [14'u64, 15]:
  let actor = ServiceMetadata(balance: AccountBalance(balance), created: AccountSlot(43))
  let completed = run(source(address = 0, account = actor, targetAccount = supervisedTarget()),
      limit = 0, capacity = 0)
  assert (uint64(machineInfo(completed.value.machine).value.registers[7]) == high(uint64)-6) == (
      balance == 14),
      "distinct direct debit retains the source's exact minimum balance"
# Destination overflow is a local invariant refusal and cannot wrap either pool.
for mode in 0'u64..3:
  let full = supervisedTarget(liquid = (if mode < 2: high(uint64) else: 77'u64),
      protected = (if mode >= 2: high(uint64) else: 55'u64))
  let refused = run(source(address = 0, mode = mode, account = fundedActor(), targetAccount = full),
      limit = 0, capacity = 0)
  assert refused.error == AccumulationDispatchError.InvalidContext, "unrepresentable direct credit publishes no guest verdict or partial debit"
let directSource = source(address = 0, mode = 3, funder = 77, account = fundedActor(),
    targetAccount = supervisedTarget(), extra = @[payer()])
for checkpoint in [false, true]:
  let suffix = if checkpoint: @[@[10'u8, 19], @[0'u8]] else: @[@[0'u8]]
  let failed = run(source(address = 0, mode = 3, funder = 77, account = fundedActor(),
      targetAccount = supervisedTarget(), extra = @[payer()], suffix = suffix), limit = 0, capacity = 0)
  let selected = normalizeAccumulationOutcome(failed).value.outcomeContext.value
  assert (uint64(metadata(selected, 77).supervisorBalance) == 95) == checkpoint and
      (uint64(metadata(selected, 99).supervisorBalance) == 60) == checkpoint,
      "panic selects both direct endpoints from the same retained checkpoint"
let directPair = prepareAccumulationEffects(prepareAccumulationContexts(
    directSource.machineBootstrap.value, pvmContextConfig()).value).value
for successful in [0, 2]:
  failAfter(cint(successful))
  let refused = recordAccumulationDirectTransfer(directPair, ServiceIndex(77),
      AccumulationTransferDestination(99), TransferBalance(5), AccumulationFundingMode(3),
          parameters())
  assert refused.error == AccumulationEffectError.BackendFailure, "early and late direct hash failures publish neither endpoint"
  failHash(0)
  let prior = directPair.effectContext(AccumulationDimension.Regular).value
  assert uint64(metadata(prior, 77).supervisorBalance) == 100 and uint64(metadata(prior,
      99).supervisorBalance) == 55,
      "prior endpoint owners survive atomic direct backend refusal"
let narrowDirect = run(source(address = 0, mode = 3, funder = 77, account = fundedActor(),
    targetAccount = supervisedTarget(), extra = @[payer()], writes = 1), limit = 0, capacity = 0)
assert narrowDirect.error == AccumulationDispatchError.LimitExceeded, "distinct direct endpoints need one atomic two-write budget"
let oneWriteDirect = run(source(address = 0, mode = 2, destination = high(uint64),
    account = fundedActor(), writes = 1), limit = 0, capacity = 0)
assert oneWriteDirect.error == AccumulationDispatchError.None,
    "same-account debit and credit need exactly one atomic metadata write"
for credit in [574'u64, 575]:
  let guest = source(address = 0, mode = 2, destination = high(uint64), account = fundedActor(),
      credit = price(source(address = 0, mode = 2, destination = high(uint64),
          account = fundedActor()))+credit)
  failHash(1)
  let completed = run(guest, limit = 0, capacity = 0)
  if credit == 574:
    assert completed.value.exit == StepExit.OutOfGas and hashCalls() == 0, "direct base OOG precedes any atomic write"
  else:
    assert completed.error == AccumulationDispatchError.BackendFailure, "exact direct base affordability reaches the actual hash operation"
  failHash(0)
let before = getOccupiedMem()
for iteration in 0..<1000:
  let completed = run(valid)
  checkTransfer(context(completed)) # Release each plan, outgoing sequence, map and CPU successor.
  let funded = run(foreignSource)
  assert context(funded).effectTransferAt(AccumulationTransferIndex(0)).value.destinationSupervisor,
      "release protected foreign plans and their fixed outgoing values"
  let immediate = run(directSource, limit = 0, capacity = 0)
  assert uint64(metadata(context(immediate), 99).supervisorBalance) == 60,
      "release direct source and destination snapshots without outgoing ownership"
let after = getOccupiedMem()
assert before == after, "transfer releases all ARC-owned versions"
recordArcRelease("pvm_accumulation_transfer", 1000, before, after)
echo "PVM accumulation transfer passed"
echo "ARC_RELEASE cycles=1000 unchanged"
