# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_inner_lifecycle_arc_release"}

## Current compile/instantiate/expunge equations preserve independent immutable catalogue and instance owners.

import std/assertions
import std/syncio
import ../../../src/pvm/inner_machines as pvm_inner_machines
import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/program as pvm_program
import ../../../src/pvm/step as pvm_step
import ../../support/pvm_inner_lifecycle
import ../../support/testing_arc_evidence

# Stable borrowed fixture memory is captured once; returned responses retain its immutable owner.
let fixtureMemory = innerMemory()

proc compile(map: InnerMachines, size = 6'u64, credit = 10000'u64,
    pointer = 65536'u64, mode = 0'u64, memory = default(Memory)): InnerMachineResult[
        InnerMachineTransition] =
  ## Compile original bytes using current m,p,l arguments and independent gas.
  var regs = innerRegisters()
  regs[7] = RegisterValue(mode)
  regs[8] = RegisterValue(pointer)
  regs[9] = RegisterValue(size)
  let source = if memory.pageImage(PageIndex(0)).error ==
      MachineError.None: memory else: fixtureMemory
  compileInnerModule(map, MachineGas(credit), regs, source)
proc create(map: InnerMachines, handle = 0'u64, entry = 0'u64,
    credit = 10000'u64): InnerMachineResult[InnerMachineTransition] =
  ## Instance creation takes a catalogue handle and entry, never a memory pointer.
  var regs = innerRegisters()
  regs[7] = RegisterValue(handle)
  regs[8] = RegisterValue(entry)
  let memory = fixtureMemory
  createInnerMachine(map, MachineGas(credit), regs, memory)
proc remove(map: InnerMachines, id: uint64, mode = 0'u64,
    credit = 1000'u64): InnerMachineResult[InnerMachineTransition] =
  ## Mode zero removes instances; mode one removes only catalogue ownership.
  var regs = innerRegisters()
  regs[7] = RegisterValue(mode)
  regs[8] = RegisterValue(id)
  let memory = fixtureMemory
  expungeInnerMachine(map, MachineGas(credit), regs, memory)

let empty = captureInnerMachines(innerLimits())
let compiled = compile(empty).value
assert uint64(compiled.response.gas) == 8136 # 1862+ceil(264*6/1024)=1864.
assert uint64(compiled.response.registers[7]) == 0
assert empty.innerMachineCount.value == 0 and compiled.machines.innerMachineCount.value == 0
let created = create(compiled.machines).value
assert uint64(created.response.gas) == 8138 # Instantiation has the fixed 1862 price.
assert uint64(created.response.registers[7]) == 0 and created.machines.innerMachineCount.value == 1
var view = created.machines.innerMachine(InnerMachineId(0)).value
assert uint64(view.moduleHandle) == 0 and uint64(view.pc) == 0 and not view.blockCharged
assert view.memory.pageImage(PageIndex(16)).value.access == PageAccess.Inaccessible
view.pc = CodeAddress(99)
assert uint64(created.machines.innerMachine(InnerMachineId(0)).value.pc) == 0
for credit in [0'u64, 1863, 1864]:
  # Gas is charged before source access and no deficit representation is admitted.
  let done = compile(empty, credit = credit).value
  assert done.response.action == (if credit < 1864: HostAction.OutOfGas else: HostAction.Continue)
  assert uint64(done.response.gas) == 0 and uint64(done.response.gasDeficit) == 0
for credit in [0'u64, 1861, 1862]:
  # Exact instantiation affordability precedes handle lookup.
  let done = create(compiled.machines, credit = credit).value
  assert done.response.action == (if credit < 1862: HostAction.OutOfGas else: HostAction.Continue)
  assert uint64(done.response.gas) == 0 and uint64(done.response.gasDeficit) == 0
for pointer in [0'u64, 69631, 0x100000000'u64, high(uint64)]:
  # A fully charged inaccessible source panics without publishing a handle.
  assert compile(empty, pointer = pointer).value.response.action == HostAction.Panic
assert uint64(compile(empty, size = 0, pointer = high(uint64)).value.response.registers[7]) == high(uint64)-8
assert uint64(compile(empty, mode = 2).value.response.registers[7]) == high(uint64)-8
assert compile(empty, mode = 1).error == InnerMachineError.UnsupportedSource
assert uint64(create(empty).value.response.registers[7]) == high(uint64)-3
assert uint64(create(compiled.machines, entry = 1).value.response.registers[7]) == high(uint64)-8
let nonzeroCode = @[0'u8, 0, 3, 1, 50, 0, 3]
let nonzero = compile(empty, size = 7, memory = innerMemory(nonzeroCode)).value.machines
assert uint64(remove(create(nonzero, entry = 1).value.machines, 0).value.response.registers[7]) == 1

var full = compiled.machines
for id in 0..<63:
  # Multiple instances share one module without consuming duplicate program bytes.
  let appended = create(full).value
  assert uint64(appended.response.registers[7]) == uint64(id)
  full = appended.machines
assert uint64(create(full, handle = high(uint64)).value.response.registers[7]) == high(uint64)-4
assert create(full, credit = 1861).value.response.action == HostAction.OutOfGas
let deleted = remove(full, 12).value.machines
assert full.innerMachineCount.value == 63 and deleted.innerMachineCount.value == 62
assert uint64(create(deleted).value.response.registers[7]) == 12
for id in [63'u64, 0x100000000'u64, high(uint64)]:
  # Full-width unknown identifiers cannot alias a valid instance after narrowing.
  assert uint64(remove(full, id).value.response.registers[7]) == high(uint64)-3
assert uint64(remove(full, 0, mode = 2).value.response.registers[7]) == high(uint64)-8
assert remove(full, 0, credit = 334).value.response.action == HostAction.OutOfGas

var catalogue = empty
for handle in 0..<128:
  # Module capacity is independent of the smaller running-instance limit.
  let appended = compile(catalogue).value
  assert uint64(appended.response.registers[7]) == uint64(handle)
  catalogue = appended.machines
assert uint64(compile(catalogue, pointer = 0).value.response.registers[7]) == high(uint64)-4
# Trusted historical capture uses requested-length pricing, actual-byte budgets and the same handle limit.
var databaseArgs = innerRegisters()
databaseArgs[7] = RegisterValue(1)
databaseArgs[9] = RegisterValue(1000)
let databaseCode = @[0'u8, 0, 2, 50, 0, 1]
let databaseFull = compileHistoricalInnerModule(catalogue, MachineGas(10000), databaseArgs,
    fixtureMemory, false, []).value
assert uint64(databaseFull.response.registers[7]) == high(uint64)-4
var databaseLimits = innerLimits()
databaseLimits.program = ProgramByteLimit(6)
databaseLimits.total = InnerProgramLimit(6)
let historical = compileHistoricalInnerModule(captureInnerMachines(databaseLimits), MachineGas(
    10000), databaseArgs, fixtureMemory, true, databaseCode).value
assert uint64(historical.response.gas) == 7780
assert uint64(create(historical.machines).value.response.registers[7]) == 0
assert compileHistoricalInnerModule(empty, MachineGas(10000), innerRegisters(), fixtureMemory,
    true, databaseCode).error == InnerMachineError.InvalidContext
assert compileHistoricalInnerModule(empty, MachineGas(10000), databaseArgs, fixtureMemory,
    false, databaseCode).error == InnerMachineError.InvalidContext
assert compileHistoricalInnerModule(default(InnerMachines), MachineGas(10000), databaseArgs,
    fixtureMemory, true, databaseCode).error == InnerMachineError.InvalidContext
let hole = remove(catalogue, 12, mode = 1).value.machines
assert uint64(compile(hole).value.response.registers[7]) == 12

var cap = innerLimits()
cap.total = InnerProgramLimit(6)
let only = compile(captureInnerMachines(cap)).value.machines
let live = create(only).value.machines
let detached = remove(live, 0, mode = 1).value.machines
assert detached.innerMachineCount.value == 1
assert uint64(create(detached).value.response.registers[7]) == high(uint64)-3
assert compile(detached).error == InnerMachineError.LimitExceeded # Live instance retains bytes after catalogue removal.
let released = remove(detached, 0).value.machines
assert uint64(compile(released).value.response.registers[7]) ==
    0 # Final owner releases bytes and handle together.
assert compile(remove(live, 0).value.machines).error ==
    InnerMachineError.LimitExceeded # Catalogue still retains bytes.
for policy in 0..<3:
  # Independent local policies refuse without a partial module or instance successor.
  var limits = innerLimits()
  if policy == 0: limits.items = InnerMachineLimit(0) # Module preparation may still succeed.
  elif policy == 1: limits.program = ProgramByteLimit(5) # Per-module bound.
  else: limits.total = InnerProgramLimit(5) # Aggregate retained bytes.
  if policy == 0:
    assert create(compile(captureInnerMachines(limits)).value.machines).error ==
        InnerMachineError.LimitExceeded
  else:
    assert compile(captureInnerMachines(limits)).error == InnerMachineError.LimitExceeded
assert compile(default(InnerMachines)).error == InnerMachineError.InvalidContext
assert compileInnerModule(empty, MachineGas(10000), innerRegisters(), default(Memory)).error ==
    InnerMachineError.InvalidMemory
assert create(default(InnerMachines)).error == InnerMachineError.InvalidContext
assert remove(default(InnerMachines), 0).error == InnerMachineError.InvalidContext
assert default(InnerMachines).innerMachineCount.error == InnerMachineError.InvalidContext

proc cycle() =
  ## Release every shared module/instance generation after catalogue and final instance removal.
  let memory = innerMemory()
  var args = innerRegisters()
  args[7] = RegisterValue(0)
  args[8] = RegisterValue(65536)
  args[9] = RegisterValue(6)
  let compiled = compileInnerModule(captureInnerMachines(innerLimits()), MachineGas(10000), args, memory).value
  args[7] = compiled.response.registers[7]
  args[8] = RegisterValue(0)
  let live = createInnerMachine(compiled.machines, MachineGas(10000), args, memory).value
  args[7] = RegisterValue(1)
  args[8] = RegisterValue(0)
  let detached = expungeInnerMachine(live.machines, MachineGas(1000), args, memory).value
  assert detached.machines.innerMachineCount.value == 1 and
      compiled.machines.innerMachineCount.value == 0
  args[7] = RegisterValue(0)
  let released = expungeInnerMachine(detached.machines, MachineGas(1000), args, memory).value
  assert released.machines.innerMachineCount.value == 0

cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle() # Independent roots must not retain ARC cycles.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_inner_lifecycle", 1000, before, after)
echo "PVM inner lifecycle passed"
echo "ARC_RELEASE cycles=1000 unchanged"
