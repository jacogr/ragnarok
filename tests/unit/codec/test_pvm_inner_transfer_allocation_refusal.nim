# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Check direct transfers, Fetch and Invoke under a recoverable heap cap.

import std/[assertions, syncio]
import ../../../src/pvm/[inner_machines, machine, step]
import ../../../src/pvm/host/fetch
import ../../support/[pvm_inner_invoke, pvm_inner_transfer]

const HeapCap = 1024*1024
let caller = transferMemory()
var machines = transferMachines()
var createArgs = default(RegisterFile)
for id in 1..<63:
  # A full table makes successor publication need more storage than the four-byte RAM update.
  let created = createInnerMachine(machines, MachineGas(10000), createArgs, caller)
  assert created.error == InnerMachineError.None and uint64(created.value.response.registers[7]) ==
      uint64(id)
  machines = created.value.machines
let initial = innerMachine(machines, InnerMachineId(0)).value.memory
let empty = transferRegisters(caller = high(uint64), inner = high(uint64), size = 0)
let poke = transferRegisters()
let peek = transferRegisters(caller = 200702)

block staging:
  # Empty Poke must still return its charged reply when no allocation can succeed.
  let filler = alloc(HeapCap-getOccupiedMem())
  assert filler != nil and getOccupiedMem() >= HeapCap
  let unchanged = innerPokeResponse(machines, MachineGas(10000), empty, caller, MemoryByteLimit(0))
  let failedPeek = innerPeekResponse(machines, MachineGas(10000), peek, caller, MemoryByteLimit(4))
  let failedPoke = innerPokeResponse(machines, MachineGas(10000), poke, caller, MemoryByteLimit(4))
  dealloc(filler)
  assert unchanged.error == InnerMachineError.None and unchanged.value.response.action ==
      HostAction.Continue
  assert uint64(unchanged.value.response.registers[7]) == 0 and uint64(
      unchanged.value.response.gas) == 9703
  assert innerMachineCount(unchanged.value.machines).value == 63
  assert failedPeek.error == InnerMachineError.LimitExceeded and failedPoke.error ==
      InnerMachineError.LimitExceeded

proc stagingResult(source, destination: Memory): MachineError =
  ## Release the staged successor before the real Poke runs at the same heap headroom.
  copyMemoryBytes(source, MemoryAddress(69630), destination, MemoryAddress(69631),
    MemoryLength(4), MemoryByteLimit(4)).error

block publication:
  # Use small allocations after the coarse filler to avoid page-sized jumps in headroom.
  # Find a point where the RAM staging still succeeds and the larger map refuses.
  let pressure = alloc(HeapCap-getOccupiedMem()-131072)
  assert pressure != nil
  var padding = default(array[1024, nil pointer])
  var used = 0
  var reachedMap = false
  while not reachedMap:
    let occupied = getOccupiedMem()
    let staging = stagingResult(caller, initial)
    assert getOccupiedMem() == occupied
    if staging != MachineError.None:
      # Once staging itself fails, lowering the headroom cannot reach the map.
      break
    block transfer:
      let result = innerPokeResponse(machines, MachineGas(10000), poke, caller, MemoryByteLimit(4))
      assert result.error in {InnerMachineError.None, InnerMachineError.LimitExceeded}
      reachedMap = result.error == InnerMachineError.LimitExceeded
    assert getOccupiedMem() == occupied
    if not reachedMap:
      assert used < padding.len
      padding[used] = alloc(if HeapCap-occupied > 8192: 4096 else: 16)
      assert padding[used] != nil
      inc used
  for index in 0..<used: dealloc(padding[index])
  dealloc(pressure)
  assert reachedMap

# A retry applies all bytes once. Both original owners remain unchanged.
let retried = innerPokeResponse(machines, MachineGas(10000), poke, caller, MemoryByteLimit(4))
assert retried.error == InnerMachineError.None and uint64(retried.value.response.registers[7]) == 0
let updated = innerMachine(retried.value.machines, InnerMachineId(0)).value.memory
assert uint64(load(updated, MemoryAddress(69631), AccessWidth(1)).value) == 61
assert uint64(load(initial, MemoryAddress(69631), AccessWidth(1)).value) == 0
assert uint64(load(caller, MemoryAddress(69630), AccessWidth(1)).value) == 61

block hostWrites:
  # A crossing Invoke frame stages two pages. Warm the child engine before applying pressure.
  const InvokeAddress = 200650'u64
  let child = invokeMachines()
  let frame = invokeMemory(address = InvokeAddress)
  let invokeRegisters = invokeArgs(address = InvokeAddress)
  assert innerInvokeResponse(child, MachineGas(10000), invokeRegisters, frame).error ==
      InnerMachineError.None
  var fetchRegisters = default(RegisterFile)
  fetchRegisters[7] = RegisterValue(196608)
  fetchRegisters[9] = RegisterValue(4)
  fetchRegisters[10] = RegisterValue(1)
  let entropy = default(FetchEntropy)
  assert fetchEntropyResponse(MachineGas(103), fetchRegisters, caller, entropy,
      MemoryByteLimit(4)).error == FetchError.None

  let pressure = alloc(HeapCap-getOccupiedMem()-131072)
  assert pressure != nil
  var padding = default(array[1024, nil pointer])
  var used = 0
  var invokeOutputRefused = false
  var invokeEngineRefused = false
  while HeapCap-getOccupiedMem() > 256:
    let occupied = getOccupiedMem()
    let fetched = fetchEntropyResponse(MachineGas(103), fetchRegisters, caller, entropy,
      MemoryByteLimit(4))
    assert fetched.error in {FetchError.None, FetchError.LimitExceeded}
    if HeapCap-occupied <= 512: assert fetched.error == FetchError.LimitExceeded
    if not invokeEngineRefused:
      let invoked = innerInvokeResponse(child, MachineGas(10000), invokeRegisters, frame)
      case invoked.error
      of InnerMachineError.None: discard
      of InnerMachineError.LimitExceeded: invokeOutputRefused = true
      of InnerMachineError.ExecutionFailure:
        # Stop invoking once pressure reaches the child engine, before the frame read can refuse.
        assert invoked.executionError == StepError.ResidentAllocationRefused
        invokeEngineRefused = true
      else: assert false
    assert used < padding.len
    padding[used] = alloc(if HeapCap-occupied > 8192: 4096 else: 16)
    assert padding[used] != nil
    inc used
  for index in 0..<used: dealloc(padding[index])
  dealloc(pressure)
  assert invokeOutputRefused and invokeEngineRefused
  assert not innerMachine(child, InnerMachineId(0)).value.executed
  assert uint64(load(frame, MemoryAddress(InvokeAddress), AccessWidth(8)).value) == 100
  assert uint64(load(caller, MemoryAddress(196608), AccessWidth(1)).value) == 165
  assert innerInvokeResponse(child, MachineGas(10000), invokeRegisters, frame).error ==
      InnerMachineError.None
  assert fetchEntropyResponse(MachineGas(103), fetchRegisters, caller, entropy,
      MemoryByteLimit(4)).error == FetchError.None

echo "PVM inner transfer allocation refusal passed"
