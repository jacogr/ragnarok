# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_inner_invoke_arc_release"}

## Original raw guests verify all invoke exits, exact reservation/refund and immutable resumable machine state.

import std/[assertions, syncio]
import ../../../src/pvm/[inner_machines, machine, program, step, gas]
import ../../support/[pvm_inner_lifecycle, pvm_inner_pages, pvm_inner_invoke, arc_evidence]

proc run(map: InnerMachines, memory = invokeMemory(), args = invokeArgs(), credit = 10000'u64):
    InnerMachineResult[InnerMachineTransition] =
  ## Invoke only the supplied immutable map and frame, with independent outer gas for accounting witnesses.
  innerInvokeResponse(map, MachineGas(credit), args, memory)
proc price(map: InnerMachines): uint64 =
  ## Block pricing is independently verified by its own suite; host fee/refund/frame expectations remain literal.
  uint64(blockGas(map.innerMachine(InnerMachineId(0)).value.program, CodeAddress(0), GasCycleLimit(1000)).value)
let source = invokeMachines()
let memory = invokeMemory()
let halted = run(source, memory).value
assert halted.response.action == HostAction.Continue and uint64(halted.response.registers[7]) == 0
assert uint64(halted.response.registers[8]) == 196608
assert uint64(halted.response.gas) == 10000'u64-968-price(source)
let frame = invokeFrame(halted.response.memory)
assert frame[0] == 100-price(source)
for index in 0..<13: assert frame[index+1] == uint64(invokeRegisters()[
    index]) # All high-word patterns survive the real guest.
assert invokeFrame(memory)[0] == 100
assert uint64(halted.machines.innerMachine(InnerMachineId(0)).value.pc) == 0
for index in 0..<13:
  if index notin [7, 8]: assert uint64(halted.response.registers[index]) == uint64(invokeArgs()[index])
# Guest panic is an inner result, not outer panic; entry block OOG refunds its preserved positive credit.
let trapBlob = invokeBlob([@[0'u8]])
let trap = invokeMachines(trapBlob)
let panicked = run(trap, invokeMemory(trapBlob)).value
assert uint64(panicked.response.registers[7]) == 1 and panicked.response.action ==
    HostAction.Continue
assert uint64(panicked.machines.innerMachine(InnerMachineId(0)).value.pc) == 0
# Real inner invocation observes a semantically empty width-zero table, preserving the completed load.
let zeroTableBlob = @[1'u8, 0, 5, 51, 8, 2, 50, 8, 9]
let zeroTableMap = invokeMachines(zeroTableBlob)
let zeroTableMemory = invokeMemory(zeroTableBlob)
let zeroTableRun = run(zeroTableMap, zeroTableMemory).value
assert zeroTableRun.response.action == HostAction.Continue
assert uint64(zeroTableRun.response.registers[7]) == 1
assert invokeFrame(zeroTableRun.response.memory)[9] == 2
assert invokeFrame(zeroTableRun.response.memory)[0] == 100-price(zeroTableMap)
assert uint64(zeroTableRun.response.gas) == 10000'u64-968-price(zeroTableMap)
assert invokeFrame(zeroTableMemory)[9] == uint64(invokeRegisters()[8])
assert uint64(zeroTableMap.innerMachine(InnerMachineId(0)).value.pc) == 0
assert not zeroTableMap.innerMachine(InnerMachineId(0)).value.blockCharged

let underfunded = run(source, invokeMemory(fuel = price(source)-1)).value
assert uint64(underfunded.response.registers[7]) == 4
assert uint64(underfunded.response.gas) == 9032 # No inner block charge on OOG, so all reserved fuel is refunded.
assert invokeFrame(underfunded.response.memory)[0] == price(source)-1
assert not underfunded.machines.innerMachine(InnerMachineId(0)).value.blockCharged
# A larger original block proves positive, unused fuel survives OOG and is refunded rather than drained.
var costlyInstructions: seq[seq[byte]] = @[]
for register in 1'u8..12'u8: costlyInstructions.add(@[51'u8, register, 0])
costlyInstructions.add(@[50'u8, 0])
let costlyBlob = invokeBlob(costlyInstructions)
let costly = invokeMachines(costlyBlob)
assert price(costly) > 1
let preservedFuel = price(costly)-1
let unpaid = run(costly, invokeMemory(costlyBlob, fuel = preservedFuel)).value
assert uint64(unpaid.response.registers[7]) == 4 and uint64(unpaid.response.gas) == 9032
assert invokeFrame(unpaid.response.memory)[0] == preservedFuel
# A host request is returned without dispatch, advances past ecalli, and resumes the already-paid block.
let hostBlob = invokeBlob([@[10'u8, 13], @[50'u8, 0]])
let hostSource = invokeMachines(hostBlob)
let hosted = run(hostSource, invokeMemory(hostBlob)).value
assert uint64(hosted.response.registers[7]) == 3 and uint64(hosted.response.registers[8]) == 13
let suspended = hosted.machines.innerMachine(InnerMachineId(0)).value
assert uint64(suspended.pc) == 2 and suspended.blockCharged
assert uint64(hostSource.innerMachine(InnerMachineId(0)).value.pc) == 0
let resumed = run(hosted.machines, hosted.response.memory).value
assert uint64(resumed.response.registers[7]) == 0
assert uint64(resumed.response.gas) == 9032 # Resume retains the charged flag; the block is not priced twice.
assert invokeFrame(resumed.response.memory)[0] == invokeFrame(hosted.response.memory)[0]
# Fault recovery preserves registers/PC/paid gas; the caller repairs RAM using the real pages host before retry.
let loadBlob = invokeBlob([@[52'u8, 7, 0, 0, 1], @[50'u8, 0]])
let loadSource = invokeMachines(loadBlob)
let faulted = run(loadSource, invokeMemory(loadBlob)).value
assert uint64(faulted.response.registers[7]) == 2 and uint64(faulted.response.registers[8]) == 65536
let faultCpu = faulted.machines.innerMachine(InnerMachineId(0)).value
assert uint64(faultCpu.pc) == 0 and faultCpu.blockCharged
assert invokeFrame(faulted.response.memory)[8] == uint64(invokeRegisters()[
    7]) # Fault does not publish the failed load destination.
let repaired = innerPagesResponse(faulted.machines, MachineGas(10000), pageRegisters(),
    faulted.response.memory).value.machines
let retried = run(repaired, faulted.response.memory).value
assert uint64(retried.response.registers[7]) == 0 and uint64(retried.response.gas) == 9032
assert invokeFrame(retried.response.memory)[8] == 0
assert invokeFrame(retried.response.memory)[0] == invokeFrame(faulted.response.memory)[0]
# Completed writes remain attached to the executed RAM owner, without mutating the source or another slot.
let storeBlob = invokeBlob([@[59'u8, 7, 0, 0, 1], @[50'u8, 0]])
let storeSource = invokeMachines(storeBlob)
let mapped = innerPagesResponse(storeSource, MachineGas(10000), pageRegisters(), invokeMemory(
    storeBlob)).value.machines
let pair = createInnerMachine(mapped, MachineGas(10000), innerRegisters(), invokeMemory()).value.machines
let stored = run(pair, invokeMemory(storeBlob)).value
assert stored.machines.innerMachine(InnerMachineId(0)).value.memory.pageImage(PageIndex(
    16)).value.bytes[0] == 7
assert pair.innerMachine(InnerMachineId(0)).value.memory.pageImage(PageIndex(16)).value.bytes[0] == 0
assert stored.machines.innerMachine(InnerMachineId(1)).value.memory.pageImage(PageIndex(
    16)).value.access == PageAccess.Inaccessible
# Frame writes are complete across page boundaries and preserve all outside sentinels/source snapshots.
let crossMemory = invokeMemory(address = 200650)
let cross = run(source, crossMemory, invokeArgs(address = 200650)).value
assert invokeFrame(cross.response.memory, 200650)[0] == 100-price(source)
assert cross.response.memory.pageImage(PageIndex(48)).value.bytes[4041] == 173
assert cross.response.memory.pageImage(PageIndex(49)).value.bytes[58] == 173
assert invokeFrame(crossMemory, 200650)[0] == 100
# Full reservation precedes WHO and exact OOG; no missing-machine refund or partial frame/map is invented.
let missing = run(source, memory, invokeArgs(id = high(uint64)), 1068).value
assert uint64(missing.response.registers[7]) == high(uint64)-3 and uint64(missing.response.gas) == 0
assert invokeFrame(missing.response.memory)[0] == 100
let oog = run(source, memory, invokeArgs(id = high(uint64)), 1067).value
assert oog.response.action == HostAction.OutOfGas and uint64(oog.response.gasDeficit) == 1
assert uint64(oog.response.registers[7]) == high(uint64) and invokeFrame(oog.response.memory)[0] == 100
# Read-only/inaccessible/overflowing/partly writable frames request zero gas and panic only after affordability.
for address in [65536'u64, 0, 204799, 0x100000000'u64, high(uint64)]:
  let bad = run(source, memory, invokeArgs(id = high(uint64), address = address), 968).value
  assert bad.response.action == HostAction.Panic and uint64(bad.response.gas) == 0
  let short = run(source, memory, invokeArgs(address = address), 967).value
  assert short.response.action == HostAction.OutOfGas and uint64(short.response.gasDeficit) == 1
# Unsigned high fuel survives E8 decode; checked reservation/debt never overflows when 968+fuel exceeds uint64.
let huge = invokeMemory(fuel = high(uint64))
assert run(source, huge, credit = 0).error == InnerMachineError.LimitExceeded
let one = run(source, huge, credit = high(uint64)).value
assert one.response.action == HostAction.OutOfGas and uint64(one.response.gasDeficit) == 968
let highFuel = run(source, invokeMemory(fuel = 0x8000000000000000'u64), credit = high(uint64)).value
assert uint64(highFuel.response.gas) == high(uint64)-968-price(source)
assert invokeFrame(highFuel.response.memory)[0] == 0x8000000000000000'u64-price(source)
let boundary = run(source, invokeMemory(fuel = 0x8000000000000000'u64-968), credit = 0).value
assert uint64(boundary.response.gasDeficit) == 0x8000000000000000'u64
# Independent per-segment instruction/gas-analysis limits retain exact typed local reasons, without frame/map successors.
for limit in 0..<2:
  var cap = innerLimits()
  if limit == 0: cap.steps = ExecutionStepLimit(0)
  else: cap.cycles = GasCycleLimit(0)
  let refused = run(invokeMachines(cap = cap))
  assert refused.error == InnerMachineError.ExecutionFailure
  assert refused.executionError == (if limit == 0: StepError.StepLimitExceeded else: StepError.GasCycleLimitExceeded)
assert run(default(InnerMachines)).error == InnerMachineError.InvalidContext
assert run(source, default(Memory)).error == InnerMachineError.InvalidMemory
# Fresh success, resumable host/fault owners and local engine refusals release all frame, code and RAM generations with ARC.
proc cycle() =
  ## No original input or completed/failed segment owner survives one independent lifetime iteration.
  let host = invokeMachines(hostBlob)
  let memory = invokeMemory(hostBlob)
  let stopped = innerInvokeResponse(host, MachineGas(10000), invokeArgs(), memory).value
  let done = innerInvokeResponse(stopped.machines, MachineGas(10000), invokeArgs(),
      stopped.response.memory).value
  assert uint64(done.response.registers[7]) == 0
  var cap = innerLimits()
  cap.steps = ExecutionStepLimit(0)
  let refused = innerInvokeResponse(invokeMachines(cap = cap), MachineGas(10000), invokeArgs(),
      invokeMemory())
  assert refused.executionError == StepError.StepLimitExceeded
  let faultSource = invokeMachines(loadBlob)
  let faultMemory = invokeMemory(loadBlob)
  let fault = innerInvokeResponse(faultSource, MachineGas(10000), invokeArgs(), faultMemory).value
  let repaired = innerPagesResponse(fault.machines, MachineGas(10000), pageRegisters(),
      fault.response.memory).value.machines
  let retry = innerInvokeResponse(repaired, MachineGas(10000), invokeArgs(),
      fault.response.memory).value
  assert uint64(retry.response.registers[7]) == 0
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_inner_invoke", 1000, before, after)
echo "PVM inner invoke passed"
echo "ARC_RELEASE cycles=1000 unchanged"
