# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_inner_pages_arc_release"}

## Literal page prices, atomic memory transformations and immutable map successors verify Omega_Z.

import std/assertions
import std/syncio
import ../../../src/pvm/inner_machines as pvm_inner_machines
import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/program as pvm_program
import ../../../src/pvm/step as pvm_step
import ../../support/pvm_inner_lifecycle
import ../../support/pvm_inner_pages
import ../../support/testing_arc_evidence

proc pages(map: InnerMachines, regs = pageRegisters(), credit = 10000'u64):
    InnerMachineResult[InnerMachineTransition] =
  ## Use a stable caller memory distinct from every inner RAM owner.
  innerPagesResponse(map, MachineGas(credit), regs, innerMemory())
proc ram(map: InnerMachines, id = 0'u64): Memory =
  ## Extract the immutable child of the selected original map without public mutable slot access.
  map.innerMachine(InnerMachineId(id)).value.memory
let empty = pageMachines()
# All five modes have independently authored prices; invalid modes ignore even maximal count.
for row in [(0'u64, 448'u64), (1'u64, 517'u64), (2'u64, 517'u64),
    (3'u64, 188'u64), (4'u64, 188'u64), (5'u64, 80'u64), (high(uint64), 80'u64)]:
  for credit in [row[1]-1, row[1]]:
    let regs = pageRegisters(row[0], count = 2)
    let done = pages(empty, regs, credit).value
    assert done.response.action == (if credit < row[
        1]: HostAction.OutOfGas else: HostAction.Continue)
    assert uint64(done.response.gas) == 0
    assert uint64(done.response.gasDeficit) == 0
    assert done.response.memory.pageImage(PageIndex(16)).value.bytes[3] == 50
    for index in 0..<13:
      if credit < row[1] or index != 7:
        assert uint64(done.response.registers[index]) == uint64(regs[
            index]) # Only affordable table rows may change r7.
    assert ram(empty).pageImage(PageIndex(16)).value.access == PageAccess.Inaccessible
let allocated = pages(empty).value.machines
assert ram(allocated).pageImage(PageIndex(16)).value.access == PageAccess.ReadWrite
assert ram(allocated).pageImage(PageIndex(16)).value.bytes == default(array[4096, byte])
assert uint64(allocated.innerMachine(InnerMachineId(0)).value.pc) == 0
assert not allocated.innerMachine(InnerMachineId(0)).value.blockCharged
assert allocated.innerMachine(InnerMachineId(0)).value.program.codeLength.value == 2
# WHO precedes malformed geometry/mode; underfunding precedes WHO and HUH.
for id in [1'u64, 63, 0x100000000'u64, high(uint64)]:
  let done = pages(empty, pageRegisters(99, high(uint64), high(uint64), id), 80).value
  assert uint64(done.response.registers[7]) == high(uint64)-3
  assert pages(empty, pageRegisters(99, high(uint64), high(uint64), id),
      79).value.response.action == HostAction.OutOfGas
for regs in [pageRegisters(5), pageRegisters(first = 15), pageRegisters(first = 0x100000),
    pageRegisters(first = high(uint64)), pageRegisters(first = 0xfffff, count = 1),
    pageRegisters(first = 16, count = 0x100000'u64-16)]:
  assert uint64(pages(empty, regs, 1000000000).value.response.registers[7]) == high(uint64)-8
# The last physical page cannot be allocated by Omega_Z's strict exclusive endpoint; empty intervals can end there.
assert uint64(pages(empty, pageRegisters(first = 0xfffff, count = 0)).value.response.registers[7]) == 0
assert uint64(pages(empty, pageRegisters(first = 0xffffe)).value.response.registers[7]) == 0
for mode in 0'u64..4'u64:
  let done = pages(empty, pageRegisters(mode, count = 0)).value
  assert uint64(done.response.registers[7]) == 0 # Vacuous permission intervals include preserved mode on empty RAM.
# Preserve modes require every old page accessible; a missing suffix never produces a partially mapped prefix.
for mode in [3'u64, 4]:
  let rejected = pages(allocated, pageRegisters(mode, count = 2)).value
  assert uint64(rejected.response.registers[7]) == high(uint64)-8
  assert ram(rejected.machines).pageImage(PageIndex(16)).value.access == PageAccess.ReadWrite
  assert ram(rejected.machines).pageImage(PageIndex(17)).value.access == PageAccess.Inaccessible
  let remapped = pages(allocated, pageRegisters(mode)).value
  assert uint64(remapped.response.registers[7]) == 0
  assert ram(remapped.machines).pageImage(PageIndex(16)).value.access ==
    (if mode == 3: PageAccess.ReadOnly else: PageAccess.ReadWrite)
# Allocation/refree share a finite page budget; zeroed inaccessible pages relinquish sparse storage capacity.
let bounded = pageMachines(1)
let first = pages(bounded).value.machines
assert pages(first, pageRegisters(first = 17)).error == InnerMachineError.LimitExceeded
let freed = pages(first, pageRegisters(0)).value.machines
assert ram(freed).pageImage(PageIndex(16)).value.access == PageAccess.Inaccessible
assert ram(freed).pageImage(PageIndex(16)).value.bytes == default(array[4096, byte])
assert pages(freed, pageRegisters(first = 17)).error == InnerMachineError.None
assert pages(pageMachines(0)).error == InnerMachineError.LimitExceeded
# Successful updating of machine zero retains the second machine's original inaccessible memory and metadata.
let pair = preparedInnerMachine(empty, MachineGas(10000), innerRegisters(), innerMemory()).value.machines
let changed = pages(pair).value.machines
assert ram(changed, 1).pageImage(PageIndex(16)).value.access == PageAccess.Inaccessible
assert uint64(changed.innerMachine(InnerMachineId(1)).value.pc) == 0
assert ram(pair).pageImage(PageIndex(16)).value.access == PageAccess.Inaccessible
# Exact representable high costs retain OOG debt; larger natural costs/debts are explicit local implementation refusals.
let large = pages(empty, pageRegisters(count = 0x100000000'u64), 0).value
assert uint64(large.response.gasDeficit) == 0
assert pages(empty, pageRegisters(count = high(uint64)), 0).value.response.action ==
    HostAction.OutOfGas
assert pages(empty, pageRegisters(count = 100000000000000000'u64), 0).value.response.action ==
    HostAction.OutOfGas
let boundary = pages(empty, pageRegisters(count = 76226215180617980'u64), 47).value
assert uint64(boundary.response.gasDeficit) == 0
assert pages(empty, pageRegisters(count = 76226215180617980'u64), 46).value.response.action ==
    HostAction.OutOfGas
let invalid = pages(empty, pageRegisters(99, count = high(uint64)), 80).value
assert uint64(invalid.response.registers[7]) == high(
    uint64)-8 # Invalid mode costs only 80 and never multiplies count.
assert pages(default(InnerMachines)).error == InnerMachineError.InvalidContext
assert innerPagesResponse(empty, MachineGas(1000), pageRegisters(), default(Memory)).error ==
    InnerMachineError.InvalidMemory
# Trusted page-range updates preserve nonzero bytes on remap and zero every byte on allocation/free.
var a = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)
var b = PageImage(index: PageIndex(17), access: PageAccess.ReadOnly)
a.bytes[0] = 71
a.bytes[4095] = 72
b.bytes[0] = 81
let original = captureMemory([a, b], PageLimit(2)).value
let preserved = original.withPageRange(PageIndex(16), PageIndex(17), PageAccess.ReadOnly,
    PageContent.Preserved).value
assert preserved.pageImage(PageIndex(16)).value.bytes[0] == 71
assert preserved.pageImage(PageIndex(16)).value.bytes[4095] == 72
assert preserved.pageImage(PageIndex(17)).value.bytes[0] == 81
assert original.pageImage(PageIndex(16)).value.access == PageAccess.ReadWrite
let zeroed = preserved.withPageRange(PageIndex(16), PageIndex(17), PageAccess.ReadWrite,
    PageContent.Zeroed).value
assert zeroed.pageImage(PageIndex(16)).value.bytes == default(array[4096, byte])
assert original.withPageRange(PageIndex(16), PageIndex(19), PageAccess.ReadOnly,
    PageContent.Zeroed).error == MachineError.LimitExceeded
assert original.pageImage(PageIndex(16)).value.bytes[0] ==
    71 # Failed growth cannot zero any original prefix.
let removed = original.withPageRange(PageIndex(16), PageIndex(17), PageAccess.Inaccessible,
    PageContent.Zeroed).value
assert removed.pageImage(PageIndex(16)).value.bytes == default(array[4096, byte])
assert removed.pageImage(PageIndex(17)).value.bytes[0] == 81
assert removed.withPageRange(PageIndex(18), PageIndex(19), PageAccess.ReadWrite,
    PageContent.Zeroed).error == MachineError.None
assert original.withPageRange(PageIndex(17), PageIndex(16), PageAccess.ReadOnly,
    PageContent.Zeroed).error == MachineError.InvalidRange
assert original.withPageRange(PageIndex(0), PageIndex(0x100001), PageAccess.Inaccessible,
    PageContent.Zeroed).error == MachineError.InvalidRange
assert default(Memory).withPageRange(PageIndex(0), PageIndex(0), PageAccess.Inaccessible,
    PageContent.Zeroed).error == MachineError.InvalidOwner
# Fresh atomic memory/map successors, protocol refusals and local-capacity failures all release with ARC.
proc cycle() =
  ## Retain no source, map, response or child RAM between fresh independent lifetime iterations.
  let source = pageMachines(1)
  let memory = innerMemory()
  let writable = innerPagesResponse(source, MachineGas(10000), pageRegisters(),
      memory).value.machines
  let readOnly = innerPagesResponse(writable, MachineGas(10000), pageRegisters(3),
      memory).value.machines
  let preserved = innerPagesResponse(readOnly, MachineGas(10000), pageRegisters(4),
      memory).value.machines
  let zeroed = innerPagesResponse(preserved, MachineGas(10000), pageRegisters(1),
      memory).value.machines
  assert ram(zeroed).pageImage(PageIndex(16)).value.bytes == default(array[4096, byte])
  assert innerPagesResponse(zeroed, MachineGas(10000), pageRegisters(first = 17), memory).error ==
      InnerMachineError.LimitExceeded
  let freed = innerPagesResponse(zeroed, MachineGas(10000), pageRegisters(0), memory).value.machines
  assert ram(freed).pageImage(PageIndex(16)).value.access == PageAccess.Inaccessible
  let refused = innerPagesResponse(freed, MachineGas(10000), pageRegisters(3), memory).value
  assert uint64(refused.response.registers[7]) == high(uint64)-8
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_inner_pages", 1000, before, after)
echo "PVM inner pages passed"
echo "ARC_RELEASE cycles=1000 unchanged"
