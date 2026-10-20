# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_inner_transfer_arc_release"}

## Literal transfer bytes, host ordering, exact gas and immutable memory/map forks verify Omega_P/Omega_O.

import std/[assertions, syncio]
import ../../../src/pvm/[inner_machines, machine, program, step]
import ../../support/[pvm_inner_lifecycle, pvm_inner_pages, pvm_inner_transfer, arc_evidence]

proc transfer(peek: bool, map: InnerMachines, regs: RegisterFile, credit = 10000'u64,
    cap = 4'u64, memory = transferMemory()): InnerMachineResult[InnerMachineTransition] =
  ## Keep protocol gas and local copying policy separate for both public endpoint-specific APIs.
  if peek: innerPeekResponse(map, MachineGas(credit), regs, memory, MemoryByteLimit(cap))
  else: innerPokeResponse(map, MachineGas(credit), regs, memory, MemoryByteLimit(cap))
proc ram(map: InnerMachines, id = 0'u64): Memory =
  ## Retain only the selected immutable RAM child; copied metadata cannot update the map.
  map.innerMachine(InnerMachineId(id)).value.memory
let empty = transferMachines()
let caller = transferMemory()
let regs = transferRegisters()
let poked = transfer(false, empty, regs, memory = caller).value
assert uint64(poked.response.registers[7]) == 0 and uint64(poked.response.gas) == 9702
assert poked.response.memory.pageImage(PageIndex(16)).value.bytes[4094] == 61
assert ram(poked.machines).readBytes(MemoryAddress(69631), MemoryLength(4), MemoryByteLimit(
    4)).value == @[61'u8, 62, 71, 72]
assert ram(empty).pageImage(PageIndex(16)).value.bytes[4095] == 0
assert ram(poked.machines).pageImage(PageIndex(16)).value.bytes[4094] == 0
assert ram(poked.machines).pageImage(PageIndex(17)).value.bytes[3] == 0
let peeked = transfer(true, poked.machines, transferRegisters(caller = 200702),
    memory = caller).value
assert uint64(peeked.response.registers[7]) == 0 and uint64(peeked.response.gas) == 9621
assert peeked.response.memory.readBytes(MemoryAddress(200702), MemoryLength(4), MemoryByteLimit(
    4)).value == @[61'u8, 62, 71, 72]
assert peeked.response.memory.pageImage(PageIndex(48)).value.bytes[4093] == 165
assert peeked.response.memory.pageImage(PageIndex(49)).value.bytes[2] == 165
assert caller.pageImage(PageIndex(48)).value.bytes[4094] == 165
var copied = peeked.response.memory.pageImage(PageIndex(48)).value
copied.bytes[4094] = 255
assert peeked.response.memory.pageImage(PageIndex(48)).value.bytes[4094] == 61
for index in 0..<13:
  if index != 7:
    assert uint64(poked.response.registers[index]) == uint64(regs[index]) # Only r7 is a protocol result register.
assert uint64(poked.machines.innerMachine(InnerMachineId(0)).value.pc) == 0
assert not poked.machines.innerMachine(InnerMachineId(0)).value.blockCharged
assert poked.machines.innerMachine(InnerMachineId(0)).value.program.codeLength.value == 2
# Page permission-only changes preserve nonzero poke bytes; zeroed remapping clears them through the real host.
let readOnly = innerPagesResponse(poked.machines, MachineGas(10000), pageRegisters(3, count = 2),
    caller).value.machines
assert transfer(true, readOnly, transferRegisters(caller = 200702)).error == InnerMachineError.None
assert uint64(transfer(false, readOnly, regs).value.response.registers[7]) == high(uint64)-2
assert ram(readOnly).pageImage(PageIndex(16)).value.bytes[4095] == 61
let cleared = innerPagesResponse(readOnly, MachineGas(10000), pageRegisters(1, count = 2),
    caller).value.machines
assert ram(cleared).pageImage(PageIndex(16)).value.bytes[4095] == 0
assert ram(poked.machines).pageImage(PageIndex(16)).value.bytes[4095] == 61
# Full-domain prices are frozen independently; all debt arithmetic fits below 2^63 without multiplication overflow.
for row in [(0'u64, 377'u64, 297'u64), (1'u64, 378'u64, 298'u64),
    (3'u64, 378'u64, 298'u64), (4'u64, 379'u64, 298'u64),
    (1024'u64, 713'u64, 521'u64), (1025'u64, 714'u64, 522'u64),
    (high(uint64), 6052837899185947001'u64, 4035225266123964713'u64)]:
  for peek in [false, true]:
    let done = transfer(peek, empty, transferRegisters(size = row[0]), credit = 0, cap = 0).value
    assert done.response.action == HostAction.OutOfGas
    assert uint64(done.response.gasDeficit) == (if peek: row[1] else: row[2])
    assert uint64(done.response.registers[7]) == 0
    assert done.response.memory.pageImage(PageIndex(48)).value.bytes[0] == 165
for peek in [false, true]:
  let cost = if peek: 379'u64 else: 298'u64
  let args = transferRegisters(caller = if peek: 200702'u64 else: 69630'u64)
  for credit in [cost-1, cost]:
    let done = transfer(peek, empty, args, credit).value
    assert done.response.action == (if credit < cost: HostAction.OutOfGas else: HostAction.Continue)
    assert uint64(done.response.gas) == 0
    assert uint64(done.response.gasDeficit) == (if credit < cost: 1'u64 else: 0'u64)
  let bad = transferRegisters(caller = high(uint64), size = 1, id = high(uint64))
  assert transfer(peek, empty, bad, credit = 0, cap = 0).value.response.action ==
      HostAction.OutOfGas
# Caller panic precedes missing ID and local cap; WHO precedes inner OOB and copying policy.
for peek in [false, true]:
  let validCaller = if peek: 200702'u64 else: 69630'u64
  for address in [0'u64, 0x100000000'u64, high(uint64), (if peek: 204799'u64 else: 73727'u64)]:
    let bad = transfer(peek, empty, transferRegisters(caller = address, size = 2, id = high(
        uint64)), cap = 0).value
    assert bad.response.action == HostAction.Panic
    assert uint64(bad.response.registers[7]) == high(uint64)
  let who = transfer(peek, empty, transferRegisters(caller = validCaller, inner = high(uint64),
      id = high(uint64)), cap = 0).value
  assert who.response.action == HostAction.Continue and uint64(who.response.registers[7]) == high(uint64)-3
  for address in [0'u64, 0x100000000'u64, high(uint64), 73727'u64]:
    let oob = transfer(peek, empty, transferRegisters(caller = validCaller, inner = address,
        size = 2), cap = 0).value
    assert uint64(oob.response.registers[7]) == high(uint64)-2
    assert ram(oob.machines).pageImage(PageIndex(17)).value.bytes[4095] ==
        0 # No accessible prefix is copied before a bad suffix.
  assert transfer(peek, empty, transferRegisters(caller = validCaller), cap = 3).error ==
      InnerMachineError.LimitExceeded
  let zero = transfer(peek, empty, transferRegisters(high(uint64), high(uint64), 0), cap = 0).value
  assert uint64(zero.response.registers[7]) == 0 and zero.response.action == HostAction.Continue
  let missingZero = transfer(peek, empty, transferRegisters(high(uint64), high(uint64), 0, high(
      uint64)), cap = 0).value
  assert uint64(missingZero.response.registers[7]) == high(uint64)-3
  assert transfer(peek, default(InnerMachines), regs).error == InnerMachineError.InvalidContext
  assert transfer(peek, empty, regs, memory = default(Memory)).error ==
      InnerMachineError.InvalidMemory
assert transfer(true, empty, transferRegisters(caller = 65536)).value.response.action ==
    HostAction.Panic # Peek's outer destination must be writable.
# An unselected second machine and all source snapshots survive a poke unchanged.
let pair = createInnerMachine(empty, MachineGas(10000), innerRegisters(), innerMemory()).value.machines
let one = transfer(false, pair, regs).value.machines
assert ram(one, 1).pageImage(PageIndex(16)).value.access == PageAccess.Inaccessible
assert ram(pair).pageImage(PageIndex(16)).value.bytes[4095] == 0
# Allocation-free range inspection retains natural bounds, empty-owner rules and exact permission fault addresses.
assert caller.readableRange(MemoryAddress(69630), MemoryLength(4)).error == MachineError.None
assert caller.writableRange(MemoryAddress(69630), MemoryLength(4)).error == MachineError.Fault
assert uint32(caller.writableRange(MemoryAddress(69630), MemoryLength(4)).faultPage) == 65536
assert caller.writableRange(MemoryAddress(200702), MemoryLength(4)).error == MachineError.None
assert caller.readableRange(MemoryAddress(high(uint64)), MemoryLength(0)).error == MachineError.None
assert caller.writableRange(MemoryAddress(high(uint64)), MemoryLength(0)).error == MachineError.None
assert caller.readableRange(MemoryAddress(high(uint64)), MemoryLength(1)).error ==
    MachineError.InvalidRange
assert default(Memory).readableRange(MemoryAddress(0), MemoryLength(0)).error ==
    MachineError.InvalidOwner
# Fresh owners cover successful copies, immutable forks, local copy refusals and protocol OOB/panic/OOG release.
proc cycle() =
  ## Drop every response, copied byte buffer, page/map generation and input owner at the end of each iteration.
  let memory = transferMemory()
  let source = transferMachines()
  let poked = innerPokeResponse(source, MachineGas(10000), transferRegisters(), memory,
      MemoryByteLimit(4)).value
  let readOnly = innerPagesResponse(poked.machines, MachineGas(10000), pageRegisters(3, count = 2),
      memory).value.machines
  let copied = innerPeekResponse(readOnly, MachineGas(10000), transferRegisters(caller = 200702),
      memory, MemoryByteLimit(4)).value
  assert copied.response.memory.pageImage(PageIndex(48)).value.bytes[4094] == 61
  assert innerPeekResponse(readOnly, MachineGas(10000), transferRegisters(caller = 200702), memory,
      MemoryByteLimit(3)).error == InnerMachineError.LimitExceeded
  assert uint64(innerPokeResponse(readOnly, MachineGas(10000), transferRegisters(), memory,
      MemoryByteLimit(4)).value.response.registers[7]) == high(uint64)-2
  assert innerPeekResponse(readOnly, MachineGas(10000), transferRegisters(), memory,
      MemoryByteLimit(4)).value.response.action == HostAction.Panic
  assert innerPokeResponse(source, MachineGas(0), transferRegisters(), memory, MemoryByteLimit(
      4)).value.response.action == HostAction.OutOfGas
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_inner_transfer", 1000, before, after)
echo "PVM inner transfer passed"
echo "ARC_RELEASE cycles=1000 unchanged"
