# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_inner_lifecycle_arc_release"}

## Literal protocol prices, lifecycle priority and immutable full-capacity forks verify Omega_M/Omega_X.

import std/[assertions, syncio]
import ../../../src/pvm/[inner_machines, machine, program, step]
import ../../support/[pvm_inner_lifecycle, arc_evidence]

proc create(map: InnerMachines, regs = innerRegisters(), credit = 10000'u64,
    memory = innerMemory()): InnerMachineResult[InnerMachineTransition] =
  ## Supply stable original memory and independent protocol gas to a real lifecycle transition.
  createInnerMachine(map, MachineGas(credit), regs, memory)
proc remove(map: InnerMachines, id: uint64, credit = 1000'u64): InnerMachineResult[
    InnerMachineTransition] =
  ## Only r7 supplies the full-width identifier; unrelated register sentinels remain present.
  expungeInnerMachine(map, MachineGas(credit), innerRegisters(pointer = id), innerMemory())
let empty = captureInnerMachines(innerLimits())
let created = create(empty).value
assert created.response.action == HostAction.Continue
assert uint64(created.response.gas) == 8137 # 1862+ceil(112*6/1024) = 1863.
assert uint64(created.response.registers[7]) == 0
assert created.response.memory.pageImage(PageIndex(16)).value.bytes[3] ==
    50 # Creation retains the caller memory beside copied code.
for index in 0..<13:
  if index != 7: assert uint64(created.response.registers[index]) == uint64(innerRegisters()[
      index]) # Only r7 changes.
assert uint64(created.response.registers[8]) == 6 and uint64(created.response.registers[9]) == 0
assert empty.innerMachineCount.value == 0 and created.machines.innerMachineCount.value == 1
var view = created.machines.innerMachine(InnerMachineId(0)).value
assert uint64(view.pc) == 0 and not view.blockCharged
assert view.memory.pageImage(PageIndex(16)).value.access == PageAccess.Inaccessible
assert view.memory.pageImage(PageIndex(16)).value.bytes == default(array[4096, byte])
view.pc = CodeAddress(99)
view.blockCharged = true
assert uint64(created.machines.innerMachine(InnerMachineId(0)).value.pc) == 0
assert not created.machines.innerMachine(InnerMachineId(0)).value.blockCharged
# Entry PC is retained exactly; empty RAM remains inaccessible even for a nonzero valid entry.
let secondCode = @[0'u8, 0, 3, 1, 50, 0, 3]
let nonzero = create(empty, innerRegisters(7, entry = 1), memory = innerMemory(secondCode)).value
assert uint64(remove(nonzero.machines, 0).value.response.registers[7]) == 1
# Exact gas and underfunding precede every table decision; debt is never silently clamped away.
for credit in [0'u64, 1862, 1863]:
  let done = create(empty, credit = credit).value
  assert done.response.memory.pageImage(PageIndex(16)).value.bytes[3] ==
      50 # Every charged creation response retains memory.
  assert done.response.action == (if credit < 1863: HostAction.OutOfGas else: HostAction.Continue)
  assert uint64(done.response.gas) == 0
  assert uint64(done.response.gasDeficit) == (if credit < 1863: 1863-credit else: 0'u64)
  assert done.machines.innerMachineCount.value == uint32(credit == 1863)
  if credit < 1863: assert uint64(done.response.registers[7]) == 65536 # No argument mutation on OOG.
# Independent literal fnmemgas witnesses include the largest guest length, without overflow.
for row in [(0'u64, 1862'u64), (1'u64, 1863'u64), (9'u64, 1863'u64),
    (10'u64, 1864'u64), (1024'u64, 1974'u64), (1025'u64, 1975'u64),
    (high(uint64), 2017612633061984070'u64)]:
  let done = create(empty, innerRegisters(row[0]), credit = 0).value
  assert uint64(done.response.gasDeficit) == row[1]
# Invalid natural ranges panic; empty ranges ignore their pointer then fail deblob with HUH.
for pointer in [0'u64, 69631, 0x100000000'u64, high(uint64)]:
  assert create(empty, innerRegisters(pointer = pointer)).value.response.action == HostAction.Panic
let zero = create(empty, innerRegisters(0, high(uint64))).value
assert zero.response.action == HostAction.Continue
assert uint64(zero.response.registers[7]) == high(uint64)-8
for blob in [@[0'u8], @[0'u8, 0, 2, 50, 0, 0], @[0'u8, 0, 1, 2, 1]]:
  let bad = create(empty, innerRegisters(uint64(blob.len)), memory = innerMemory(blob)).value
  assert uint64(bad.response.registers[7]) == high(uint64)-8
  assert bad.machines.innerMachineCount.value == 0
for entry in [1'u64, 2, high(uint64)]:
  assert uint64(create(empty, innerRegisters(entry = entry)).value.response.registers[7]) == high(uint64)-8
# Inner-machine creation selects the same JAM profile as outer guest initialization.
for blob in [@[0'u8, 0, 1, 1, 1], @[0'u8, 0, 3, 170, 0, 0, 1],
    @[0'u8, 5, 1, 0, 1]]:
  let refused = create(empty, innerRegisters(uint64(blob.len)), memory = innerMemory(blob)).value
  assert uint64(refused.response.registers[7]) == high(uint64)-8
  assert refused.machines.innerMachineCount.value == 0
# A nonempty zero-width table still creates an inner machine, with no usable dynamic entries.
let zeroWidth = @[1'u8, 0, 4, 10, 0, 50, 8, 5]
let zeroCreated = create(empty, innerRegisters(uint64(zeroWidth.len), entry = 2),
  memory = innerMemory(zeroWidth)).value
assert uint64(zeroCreated.response.registers[7]) == 0 and
    zeroCreated.machines.innerMachineCount.value == 1
let zeroProgram = zeroCreated.machines.innerMachine(InnerMachineId(0)).value.program
assert jumpTarget(zeroProgram, JumpIndex(0)).error == ProgramError.InvalidIndex

# GP-PVM-009 is retained through actual inner-machine capture, independently of raw paper owners.
let destinationBytes = @[0'u8, 0, 11, 51, 1, 7, 51, 2, 11, 190, 33, 16, 50, 0, 73, 2]
let destinationCreated = create(empty, innerRegisters(uint64(destinationBytes.len)),
  memory = innerMemory(destinationBytes)).value
let destinationOwner = destinationCreated.machines.innerMachine(InnerMachineId(0)).value.program
assert byte(instruction(destinationOwner, CodeAddress(6)).value.d) == 0
let destinationPaper = decodeProgram(destinationBytes, CodeAddress(0), ProgramByteLimit(100),
    JumpCountLimit(0)).value
assert byte(instruction(destinationPaper, CodeAddress(6)).value.d) == 12
assert empty.innerMachineCount.value == 0

# Populate every slot, delete a middle hole, reuse the minimum hole and retain earlier snapshots unchanged.
var full = empty
for id in 0..<63:
  let appended = create(full).value
  assert uint64(appended.response.registers[7]) == uint64(id)
  full = appended.machines
let denied = create(full, innerRegisters(high(uint64), high(uint64)), high(uint64)).value
assert denied.response.action == HostAction.Continue and uint64(denied.response.registers[7]) ==
    high(uint64)-4
assert denied.machines.innerMachineCount.value == 63 # FULL before unreadability or local size cap.
assert create(full, credit = 1862).value.response.action == HostAction.OutOfGas
let deleted = remove(full, 12).value
assert deleted.response.memory.pageImage(PageIndex(16)).value.bytes[0] ==
    0 # Host response retains the original program memory.
assert uint64(deleted.response.registers[7]) == 0 and deleted.machines.innerMachineCount.value == 62
assert full.innerMachine(InnerMachineId(12)).error == InnerMachineError.None
assert deleted.machines.innerMachine(InnerMachineId(12)).error == InnerMachineError.Missing
assert uint64(create(deleted.machines).value.response.registers[7]) == 12
for id in [63'u64, 0x100000000'u64, high(uint64)]:
  assert uint64(remove(full, id).value.response.registers[7]) == high(uint64)-3
  assert full.innerMachine(InnerMachineId(id)).error == InnerMachineError.Missing
for credit in [334'u64, 335]:
  let done = remove(created.machines, 0, credit).value
  assert done.response.action == (if credit < 335: HostAction.OutOfGas else: HostAction.Continue)
  assert done.response.memory.pageImage(PageIndex(16)).value.bytes[3] ==
      50 # Both deletion and OOG retain readable input memory.
  assert done.machines.innerMachineCount.value == uint32(credit < 335)
  assert uint64(done.response.gasDeficit) == (if credit < 335: 1'u64 else: 0'u64)
# Each independent local policy refuses without publishing response or a new map.
for policy in 0..<3:
  var cap = innerLimits()
  case policy
  of 0: cap.items = InnerMachineLimit(0) # Zero item policy is local, never protocol FULL.
  of 1: cap.program = ProgramByteLimit(5) # A valid six-byte blob exceeds this independent copy/parse cap.
  else: cap.total = InnerProgramLimit(5) # Aggregate storage is separate from the per-program cap.
  assert create(captureInnerMachines(cap)).error == InnerMachineError.LimitExceeded
var capped = innerLimits()
capped.total = InnerProgramLimit(6)
let first = create(captureInnerMachines(capped)).value.machines
assert create(first).error == InnerMachineError.LimitExceeded
assert create(remove(first, 0).value.machines).error == InnerMachineError.None # Deletion recovers byte capacity.
capped = innerLimits()
capped.jumps = JumpCountLimit(0)
let jumpBlob = @[1'u8, 1, 2, 2, 50, 0, 1]
assert create(captureInnerMachines(capped), innerRegisters(7), memory = innerMemory(
    jumpBlob)).error ==
  InnerMachineError.LimitExceeded
assert create(default(InnerMachines)).error == InnerMachineError.InvalidContext
assert create(empty, memory = default(Memory)).error == InnerMachineError.InvalidMemory
assert remove(default(InnerMachines), 0).error == InnerMachineError.InvalidContext
assert default(InnerMachines).innerMachineCount.error == InnerMachineError.InvalidContext
assert default(InnerMachines).innerMachine(InnerMachineId(0)).error ==
    InnerMachineError.InvalidContext
# Fresh maps, forks, failed appends and deletes must release all program/memory owners with ARC.
proc cycle() =
  ## Drop all local immutable generations on return; no mutable shared map can retain released programs.
  var cap = innerLimits()
  cap.total = InnerProgramLimit(6)
  let original = captureInnerMachines(cap)
  let memory = innerMemory()
  let created = createInnerMachine(original, MachineGas(10000), innerRegisters(), memory)
  let map = created.value.machines
  let refused = createInnerMachine(map, MachineGas(10000), innerRegisters(), memory)
  assert refused.error == InnerMachineError.LimitExceeded
  let removed = expungeInnerMachine(map, MachineGas(1000), innerRegisters(pointer = 0), memory)
  assert removed.value.machines.innerMachineCount.value == 0
  assert removed.value.response.memory.pageImage(PageIndex(16)).value.bytes[3] == 50
  let absent = expungeInnerMachine(original, MachineGas(1000), innerRegisters(pointer = 0), memory)
  assert uint64(absent.value.response.registers[7]) == high(uint64)-3
  assert absent.value.response.memory.pageImage(PageIndex(16)).value.bytes[3] == 50
  let starved = expungeInnerMachine(map, MachineGas(334), innerRegisters(pointer = 0), memory)
  assert starved.value.response.action == HostAction.OutOfGas
  assert starved.value.response.memory.pageImage(PageIndex(16)).value.bytes[3] == 50
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_inner_lifecycle", 1000, before, after)
echo "PVM inner lifecycle passed"
echo "ARC_RELEASE cycles=1000 unchanged"
