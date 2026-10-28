# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent present-value fetch witnesses for prices, clipping, atomicity and owned responses.
## Applies responses to a real host suspension and records fresh native ARC evidence.

# @@Verification={"arc": "pvm_fetch_arc_release"}

import std/assertions
import std/syncio
import ../../../src/pvm/program as pvm_program
import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/gas as pvm_gas
import ../../../src/pvm/step as pvm_step
import ../../../src/pvm/host_fetch as pvm_host_fetch
import ../../support/testing_arc_evidence

# Two writable pages straddle the test destination; a readonly page follows them.
proc memory(): Memory =
  captureMemory([
    PageImage(index: PageIndex(0), access: PageAccess.ReadWrite),
    PageImage(index: PageIndex(1), access: PageAccess.ReadWrite),
    PageImage(index: PageIndex(2), access: PageAccess.ReadOnly),
    PageImage(index: PageIndex(1048575), access: PageAccess.ReadWrite)], PageLimit(4)).value

# Preserve distinguishable sentinels around the four fetch argument registers.
proc arguments(selector, address, offset, length: uint64): RegisterFile =
  result = default(RegisterFile)
  for i in 0..<13:
    # Unrelated registers must survive all completed protocol outcomes unchanged.
    result[i] = RegisterValue(uint64(i + 100))
  result[7] = RegisterValue(address)
  result[8] = RegisterValue(offset)
  result[9] = RegisterValue(length)
  result[10] = RegisterValue(selector)

# Check all registers, allowing precisely the specified successful length return.
proc registersEqual(response: HostResponse, original: RegisterFile, returned: uint64) =
  for i in 0..<13:
    # Panic and underflow callers pass the original r7; successful callers pass the full length.
    assert uint64(response.registers[i]) == (if i == 7: returned else: uint64(original[i]))

let original = memory()
var trace = newSeq[byte](40)
for i in 0..<trace.len:
  # Nonzero byte pattern makes unintended zero-fill and offset mistakes visible.
  trace[i] = byte(i + 1)

for requested in 0'u64..2050:
  # Small-domain multiplication is safe here and independent of the production quotient split.
  let price = 80 + (96 * requested + 1023) div 1024
  let regs = arguments(2, 4090, 3, requested)
  for credit in [price - 1, price, price + 1]:
    # Exhaust rounding transitions and both sides of each exact gas boundary.
    let response = fetchTraceResponse(MachineGas(credit), regs, original, trace,
      MemoryByteLimit(40)).value
    if credit < price:
      # An underfunded call does not copy even the writable prefix.
      assert response.action == HostAction.OutOfGas
      assert uint64(response.gas) == 0 and uint64(response.gasDeficit) == 0
      registersEqual(response, regs, 4090)
      assert pageImage(response.memory, PageIndex(0)).value.bytes[4090] == 0
    else:
      # Clipping affects the copy only, not charging or the full-length return.
      assert response.action == HostAction.Continue
      assert uint64(response.gas) == credit - price and uint64(response.gasDeficit) == 0
      registersEqual(response, regs, 40)
      let bytes = readBytes(response.memory, MemoryAddress(4089), MemoryLength(39),
        MemoryByteLimit(39)).value
      assert bytes[0] == 0 and bytes[38] == 0
      for i in 0..<37:
        # Verify bytes on both sides of the page boundary and the untouched suffix.
        assert bytes[i + 1] == (if uint64(i) < requested: byte(i + 4) else: 0'u8)
assert pageImage(original, PageIndex(0)).value.bytes[4090] == 0

# Maximal request price is independently evaluated as ceil(3*(2^64-1)/32)+80.
let maximumPrice = 1729382256910270544'u64
for offset in [0'u64, 40'u64, high(uint64)]:
  let regs = arguments(2, 0, offset, high(uint64))
  let response = fetchTraceResponse(MachineGas(maximumPrice), regs, original, trace,
    MemoryByteLimit(40)).value
  assert response.action == HostAction.Continue and uint64(response.gas) == 0
  registersEqual(response, regs, 40)
  let debt = fetchTraceResponse(MachineGas(0), regs, original, trace, MemoryByteLimit(0)).value
  assert debt.action == HostAction.OutOfGas and uint64(debt.gasDeficit) == 0

for pointer in [8192'u64, 12288'u64, 0x100000000'u64, high(uint64)]:
  let regs = arguments(2, pointer, 0, 1)
  let response = fetchTraceResponse(MachineGas(81), regs, original, trace,
    MemoryByteLimit(40)).value
  assert response.action == HostAction.Panic and uint64(response.gas) == 0
  registersEqual(response, regs, pointer)
  for offset in [40'u64, high(uint64)]:
    # Offset clipping makes the same invalid pointers valid empty intervals.
    let empty = fetchTraceResponse(MachineGas(81), arguments(2, pointer, offset, 1), original,
      trace, MemoryByteLimit(0)).value
    assert empty.action == HostAction.Continue and uint64(empty.registers[7]) == 40
  let empty = fetchTraceResponse(MachineGas(80), arguments(2, pointer, 0, 0), original,
    trace, MemoryByteLimit(0)).value
  assert empty.action == HostAction.Continue

for pointer in [8191'u64, 0xffffffff'u64]:
  let regs = arguments(2, pointer, 0, 2)
  let response = fetchTraceResponse(MachineGas(81), regs, original, trace,
    MemoryByteLimit(40)).value
  # A writable prefix followed by readonly or out-of-domain memory never commits a partial copy.
  assert response.action == HostAction.Panic
  registersEqual(response, regs, pointer)
  assert readBytes(response.memory, MemoryAddress(pointer), MemoryLength(1),
    MemoryByteLimit(1)).value[0] == 0
let top = fetchTraceResponse(MachineGas(81), arguments(2, 0xffffffff'u64, 0, 1), original,
  trace, MemoryByteLimit(1)).value
assert top.action == HostAction.Continue
assert pageImage(top.memory, PageIndex(1048575)).value.bytes[4095] == 1

# A present empty trace returns zero, including when the request is large and the pointer invalid.
let emptyTrace = fetchTraceResponse(MachineGas(maximumPrice),
  arguments(2, high(uint64), 0, high(uint64)), original, [], MemoryByteLimit(0)).value
assert emptyTrace.action == HostAction.Continue and uint64(emptyTrace.registers[7]) == 0

var entropy = default(array[32, byte])
entropy[31] = 71
for requested in [0'u64, 1'u64, high(uint64)]:
  let regs = arguments(1, 4095, 31, requested)
  let response = fetchEntropyResponse(MachineGas(103), regs, original, FetchEntropy(entropy),
    MemoryByteLimit(1)).value
  assert response.action == HostAction.Continue and uint64(response.gas) == 0
  registersEqual(response, regs, 32)
  assert pageImage(response.memory, PageIndex(0)).value.bytes[4095] ==
    (if requested == 0: 0'u8 else: 71'u8)
  let debt = fetchEntropyResponse(MachineGas(102), regs, original, FetchEntropy(entropy),
    MemoryByteLimit(0)).value
  assert debt.action == HostAction.OutOfGas and uint64(debt.gasDeficit) == 0
  registersEqual(debt, regs, 4095)

let emptyResult = default(FetchResult)
assert emptyResult.error == FetchError.Uninitialized
assert fetchTraceResponse(MachineGas(100), arguments(1, 0, 0, 1), original, trace,
  MemoryByteLimit(40)).error == FetchError.UnsupportedSelector
assert fetchEntropyResponse(MachineGas(100), arguments(2, 0, 0, 1), original, FetchEntropy(entropy),
  MemoryByteLimit(40)).error == FetchError.UnsupportedSelector
assert fetchTraceResponse(MachineGas(0), arguments(2, 0, 0, 0), default(Memory), trace,
  MemoryByteLimit(0)).error == FetchError.InvalidMemory
assert fetchTraceResponse(MachineGas(100), arguments(2, 0, 0, 40), original, trace,
  MemoryByteLimit(39)).error == FetchError.LimitExceeded
# A local policy refusal precedes page access but is never mislabeled as guest panic.
assert fetchTraceResponse(MachineGas(100), arguments(2, 8192, 0, 40), original, trace,
  MemoryByteLimit(39)).error == FetchError.LimitExceeded

let owned = fetchTraceResponse(MachineGas(100), arguments(2, 0, 0, 40), original, trace,
  MemoryByteLimit(40)).value
trace[0] = 255
assert pageImage(owned.memory, PageIndex(0)).value.bytes[0] == 1
assert pageImage(original, PageIndex(0)).value.bytes[0] == 0

# Apply each protocol exit to an authentic ecalli suspension without a lossy callback adapter.
proc cycle() =
  let code = decodeProgram([0'u8, 0, 4, 10, 2, 50, 0, 5], CodeAddress(0),
    ProgramByteLimit(8), JumpCountLimit(0)).value
  for pointer in [0'u64, 8192'u64]:
    # Both writable and readonly destinations exercise complete-response ownership.
    for credit in [0'u64, 81'u64]:
      var regs = arguments(2, pointer, 0, 1)
      regs[0] = RegisterValue(0xffff0000'u64)
      let source = captureMachine(code, memory(), MachineInfo(pc: CodeAddress(0),
        gas: MachineGas(credit), blockCharged: true, registers: regs)).value
      let stopped = execute(source, ExecutionStepLimit(1), GasCycleLimit(0)).value
      let reply = fetchTraceResponse(MachineGas(credit), regs, memoryOf(source).value,
        [7'u8], MemoryByteLimit(1)).value
      let applied = applyHostResponse(stopped, reply).value
      if credit == 0:
        # Underflow keeps the causing PC and the full terminal deficit.
        assert applied.exit == StepExit.OutOfGas
        assert uint64(machineInfo(applied.machine).value.gasDeficit) == 0
      elif pointer == 8192:
        # The host's permission panic terminates at the causing ecalli.
        assert applied.exit == StepExit.Panic
      else:
        # A continued fetch resumes the prepaid suffix and halts normally.
        assert applied.exit == StepExit.Continued
        assert execute(applied.machine, ExecutionStepLimit(1), GasCycleLimit(0)).value.exit == StepExit.Halt

cycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  # No response retains a callback or borrowed trace; all acyclic roots release on return.
  cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_fetch", 1000, before, after)
echo "PVM fetch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
