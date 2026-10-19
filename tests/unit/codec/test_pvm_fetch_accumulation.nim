# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent C.2 transfer/operand fetch bytes, bounded capture and requested-length price tests.
## Exercises list framing, empty/absent values, immutable attachment, host dispatch and ARC release.

## Verification: {"arc": "pvm_fetch_accumulation_arc_release"}

import std/[assertions, syncio]
import ../../../src/codec/[c2_records, bounded, composite, work_digest, work_package]
import ../../../src/chain/parameters
import ../../../src/pvm/[program, machine, gas, step, host_fetch]
import ../../support/arc_evidence

# Generous per-record bounds are independent of the aggregate capture budget.
proc limits(count, bytes: uint64): FetchAccumulationLimits =
  FetchAccumulationLimits(items: ElementLimit(count), bytes: ByteLimit(bytes),
    operand: OperandLimits(outputBytes: ByteLimit(1024), authBytes: ByteLimit(1024),
      totalBlobBytes: ByteLimit(2048), maxBytes: ByteLimit(4096)))

# Ordered mixed variants distinguish fixed transfer gas from compact operand gas.
proc sources(): seq[AccumulationSource] =
  var memo = default(array[128, byte])
  memo[0] = 31
  memo[127] = 32
  var operand = AccumulationOperand(gas: Gas(128), output: successfulOperandOutput(@[1'u8, 2, 3]),
    authTrace: @[4'u8, 5])
  operand.packageHash.bytes[0] = 11
  operand.segmentRoot.bytes[0] = 12
  operand.authorizer.bytes[0] = 13
  var payloadHash = default(array[32, byte])
  payloadHash[0] = 14
  operand.payloadHash = PayloadHash(payloadHash)
  @[transferSource(DeferredTransfer(source: ServiceIndex(7), destination: ServiceIndex(9),
    amount: TransferBalance(0x10000000003'u64), memo: TransferMemo(memo), gas: Gas(128))),
    operandSource(operand), operandSource(AccumulationOperand(output: failedOperandOutput(
        WorkKind.Panic)))]

# Original literal records include their C.2 variant tags but no extra per-member framing.
proc record(index: int): seq[byte] =
  if index == 0:
    # Transfer: tag, E4 source/destination, E8 balance, fixed memo, E8 gas.
    result = newSeq[byte](153)
    result[0] = 1
    result[1] = 7
    result[5] = 9
    result[9] = 3
    result[14] = 1
    result[17] = 31
    result[144] = 32
    result[145] = 128
  elif index == 1:
    # Operand: tag, four hashes, compact 128 gas, success blob, compact trace blob.
    result = newSeq[byte](139)
    result[1] = 11
    result[33] = 12
    result[65] = 13
    result[97] = 14
    result[129] = 128
    result[130] = 128
    result[132] = 3
    result[133] = 1
    result[134] = 2
    result[135] = 3
    result[136] = 2
    result[137] = 4
    result[138] = 5
  else:
    # Panic outcome has no blob length or payload, only its result tag.
    result = newSeq[byte](132)
    result[130] = 2

# A single compact input-count prefix precedes the ordered record encodings.
proc listBytes(): seq[byte] =
  result = @[3'u8]
  for i in 0..<3:
    for octet in record(i):
      # Preserve input order instead of sorting records or repeating length prefixes.
      result.add(octet)

# Base trace witnesses preservation of unrelated invocation data.
proc base(): FetchContext =
  captureFetchContext(FetchPresence.Absent, FetchEntropy(default(array[32, byte])),
    FetchPresence.Present, [73'u8], FetchTraceLimit(1)).value

# Caller source mutation and destruction must not affect the stored canonical record bytes.
proc capture(): FetchContext =
  var values = sources()
  result = withFetchAccumulation(base(), FetchPresence.Present, values, limits(3, 425)).value
  values[1] = operandSource(AccumulationOperand(output: failedOperandOutput(WorkKind.Bad)))

# r12 is deliberately huge; list selection also ignores the item index in r11.
proc arguments(selector, index, offset, requested, pointer: uint64): RegisterFile =
  result = default(RegisterFile)
  for i in 0..<13:
    # All nonargument registers carry sentinels to detect accidental mutation.
    result[i] = RegisterValue(high(uint64))
  result[0] = RegisterValue(0xffff0000'u64)
  result[7] = RegisterValue(pointer)
  result[8] = RegisterValue(offset)
  result[9] = RegisterValue(requested)
  result[10] = RegisterValue(selector)
  result[11] = RegisterValue(index)

let captured = capture()
let memory = captureMemory([PageImage(index: PageIndex(0), access: PageAccess.ReadWrite)],
    PageLimit(1)).value
for selector in [14'u64, 15'u64]:
  for index in [0'u64, 1'u64, 2'u64, 3'u64, high(uint64)]:
    let present = selector == 14 or index < 3
    let expected = (if selector == 14: listBytes() elif present: record(int(index)) else: newSeq[
        byte](0))
    for requested in [0'u64, 1'u64, 425'u64, 1023'u64, 1024'u64, 1025'u64, high(uint64)]:
      # Literal maximal prices avoid duplicating production's overflow-safe arithmetic decomposition.
      let price = (if requested == high(uint64):
        (if selector == 14: 7205759403792793887'u64 else: 6196953087261802851'u64)
        elif selector == 14: 287 + (400 * requested + 1023) div 1024
        else: 355 + (344 * requested + 1023) div 1024)
      for credit in [0'u64, price - 1, price, price + 1]:
        for offset in [0'u64, 1'u64, 129'u64, 153'u64, 424'u64, high(uint64)]:
          let regs = arguments(selector, index, offset, requested, 0)
          let reply = fetchContextResponse(captured, MachineGas(credit), regs, memory,
              MemoryByteLimit(425)).value
          let funded = credit >= price
          let start = min(offset, uint64(expected.len))
          let count = (if funded: min(requested, uint64(expected.len) - start) else: 0'u64)
          assert reply.action == (if funded: HostAction.Continue else: HostAction.OutOfGas)
          assert uint64(reply.gas) == (if funded: credit - price else: 0'u64)
          assert uint64(reply.gasDeficit) == (if funded: 0'u64 else: price - credit)
          for i in 0..<13:
            # Funded r7 reports complete selected length or NONE, not copy length.
            let wanted = (if i != 7 or not funded: uint64(regs[i])
              elif present: uint64(expected.len) else: high(uint64))
            assert uint64(reply.registers[i]) == wanted
          let page = pageImage(reply.memory, PageIndex(0)).value
          for i in 0..expected.len:
            # Verify the complete selected prefix and untouched suffix byte.
            assert page.bytes[i] == (if uint64(i) < count: expected[int(start) + i] else: 0'u8)
      let absent = fetchContextResponse(base(), MachineGas(price), arguments(selector, index, 0,
        requested, high(uint64)), memory, MemoryByteLimit(0)).value
      assert absent.action == HostAction.Continue and uint64(absent.gas) == 0
      assert uint64(absent.registers[7]) == high(uint64)
  let price = (if selector == 14: 288'u64 else: 356'u64)
  let regs = arguments(selector, 0, 0, 2, 4095)
  let panic = fetchContextResponse(captured, MachineGas(price), regs, memory, MemoryByteLimit(2)).value
  assert panic.action == HostAction.Panic and uint64(panic.registers[7]) == 4095
  assert pageImage(panic.memory, PageIndex(0)).value.bytes[4095] == 0
  assert fetchContextResponse(captured, MachineGas(price), arguments(selector, 0, 0, 2, 0),
    memory, MemoryByteLimit(1)).error == FetchError.LimitExceeded
  let oog = fetchContextResponse(captured, MachineGas(price - 1), regs, memory, MemoryByteLimit(0)).value
  assert oog.action == HostAction.OutOfGas

assert withFetchAccumulation(default(FetchContext), FetchPresence.Absent, [], limits(0, 0)).error ==
    FetchError.InvalidContext
assert withFetchAccumulation(base(), FetchPresence.Present, sources(), limits(2, 425)).error ==
    FetchError.LimitExceeded
assert withFetchAccumulation(base(), FetchPresence.Present, sources(), limits(3, 424)).error ==
    FetchError.LimitExceeded
var strict = limits(3, 425)
strict.operand.authBytes = ByteLimit(1)
assert withFetchAccumulation(base(), FetchPresence.Present, sources(), strict).error ==
    FetchError.LimitExceeded
let cleared = withFetchAccumulation(captured, FetchPresence.Absent, sources(), limits(0, 0)).value
let empty = withFetchAccumulation(captured, FetchPresence.Present, [], limits(0, 1)).value
assert withFetchAccumulation(base(), FetchPresence.Present, [], limits(0, 0)).error ==
    FetchError.LimitExceeded
for selector in [14'u64, 15'u64]:
  # Present empty list is one compact zero byte, while indexing it is absence.
  let reply = fetchContextResponse(empty, MachineGas(1000), arguments(selector, 0, 0, 1, 0), memory,
    MemoryByteLimit(1)).value
  assert uint64(reply.registers[7]) == (if selector == 14: 1'u64 else: high(uint64))
  assert pageImage(reply.memory, PageIndex(0)).value.bytes[0] == 0
  assert uint64(fetchContextResponse(cleared, MachineGas(1000), arguments(selector, 0, 0, 0, 0),
    memory, MemoryByteLimit(0)).value.registers[7]) == high(uint64)
let prior = fetchContextResponse(captured, MachineGas(1000), arguments(14, 0, high(uint64), 1,
  high(uint64)), memory, MemoryByteLimit(0)).value
assert prior.action == HostAction.Continue and uint64(prior.registers[7]) == 425

for count in [127, 128, 129]:
  # Crossing the compact-count boundary changes list framing, not individual record framing.
  var values = newSeq[AccumulationSource](count)
  for i in 0..<count:
    # Equal fixed records make metadata bounds independent of variable blob budgets.
    values[i] = transferSource(DeferredTransfer())
  let length = uint64(count * 153 + (if count < 128: 1 else: 2))
  let context = withFetchAccumulation(base(), FetchPresence.Present, values, limits(uint64(count), length)).value
  assert withFetchAccumulation(base(), FetchPresence.Present, values, limits(uint64(count), length -
      1)).error == FetchError.LimitExceeded
  let reply = fetchContextResponse(context, MachineGas(1000), arguments(14, high(uint64), 0, 2, 0),
    memory, MemoryByteLimit(2)).value
  let page = pageImage(reply.memory, PageIndex(0)).value
  assert uint64(reply.registers[7]) == length
  assert page.bytes[0] == (if count == 127: 127'u8 else: 128'u8)
  assert page.bytes[1] == (if count == 127: 1'u8 else: byte(count))

# New captures of unrelated families must preserve the encoded accumulation owner.
let retained = withFetchInputs(captured, FetchInputs(), FetchInputLimit(0)).value
let reply = fetchContextResponse(retained, MachineGas(1000), arguments(15, 1, 0, 1, 0), memory,
  MemoryByteLimit(1)).value
assert uint64(reply.registers[7]) == 139
var traceArgs = arguments(2, 0, 0, 1, 0)
assert pageImage(fetchContextResponse(retained, MachineGas(1000), traceArgs, memory,
  MemoryByteLimit(1)).value.memory, PageIndex(0)).value.bytes[0] == 73

# Parameter and package attachments must preserve accumulation; accumulation replacement preserves them.
block:
  var parameters = default(array[122, byte])
  parameters[24] = 2
  parameters[30] = 1
  parameters[80] = 1
  parameters[84] = 1
  let configured = withFetchParameters(captured, decodeParameters(parameters).value).value
  var wire = default(array[265, byte])
  wire[207] = 1
  let package = decodeWorkPackage(wire, fullPackageConfig(ByteLimit(265))).value.owner
  let attached = withFetchPackage(configured, FetchPresence.Present, package, FetchPackageLimit(0),
    FetchEncodingLimit(265)).value
  let clearedPackage = withFetchPackage(attached, FetchPresence.Absent, default(OwnedWorkPackage),
    FetchPackageLimit(0), FetchEncodingLimit(0)).value
  for context in [configured, attached, clearedPackage]:
    # Every new owner keeps the prior canonical input sequence intact.
    assert uint64(fetchContextResponse(context, MachineGas(1000), arguments(14, 0, 0, 0, 0),
      memory, MemoryByteLimit(0)).value.registers[7]) == 425
  let replaced = withFetchAccumulation(attached, FetchPresence.Present, [], limits(0, 1)).value
  for selector in [0'u64, 7'u64]:
    # Replacing accumulation inputs must not clear configured parameters or package bytes.
    assert uint64(fetchContextResponse(replaced, MachineGas(1000), arguments(selector, 0, 0, 0, 0),
      memory, MemoryByteLimit(0)).value.registers[7]) == (if selector == 0: 122'u64 else: 265'u64)
assert withFetchAccumulation(base(), FetchPresence.Present, sources(),
  limits(high(uint64), high(uint64))).error == FetchError.None

# Propagate local errors through actual fallible host dispatch.
proc dispatch(context: var FetchContext, stopped: StepOutcome): HostResult[FetchError] {.raises: [].} =
  let cpu = machineInfo(stopped.machine).value
  let fetched = fetchContextResponse(context, cpu.gas, cpu.registers, memoryOf(
      stopped.machine).value,
    MemoryByteLimit(425))
  if fetched.error != FetchError.None:
    # Local capture/copy failures never become fabricated guest exits.
    return hostFailure(fetched.error)
  hostSuccess[FetchError](fetched.value)

# Capture and execution graphs must release all canonical bytes and slice descriptors.
proc cycle() =
  var context = capture()
  let code = decodeProgram([0'u8, 0, 4, 10, 2, 50, 0, 5], CodeAddress(0), ProgramByteLimit(8),
    JumpCountLimit(0)).value
  let memory = captureMemory([PageImage(index: PageIndex(0), access: PageAccess.ReadWrite)],
      PageLimit(1)).value
  for selector in [14'u64, 15'u64]:
    # Both selectors execute through ecalli and then return through the guest halt address.
    let machine = captureMachine(code, memory, MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000),
      blockCharged: true, registers: arguments(selector, 0, 0, 425, 0))).value
    let done = executeWithHost(machine, context, dispatch, ExecutionStepLimit(2), HostCallLimit(1),
        GasCycleLimit(0))
    assert done.error == HostExecutionError.None and done.value.exit == StepExit.Halt
    assert uint64(machineInfo(done.value.machine).value.registers[7]) == (if selector ==
        14: 425'u64 else: 153'u64)

cycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Owners retain no caller storage or references back to themselves.
  cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_fetch_accumulation", 1000, before, after)
echo "PVM accumulation fetch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
