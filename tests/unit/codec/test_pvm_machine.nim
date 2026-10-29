# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Memory permissions, cyclic addressing, snapshot isolation and copied CPU state.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

# @@Verification={"arc": "pvm_machine_arc_release"}

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine]
import ../../support/arc_evidence

# Test fixtures own deterministic bytes; the implementation never supplies expected values.
proc page(index: uint32, access: PageAccess): PageImage =
  result = PageImage(index: PageIndex(index), access: access, bytes: default(array[4096, byte]))
  # Different offsets produce different low bytes, exposing endian and cross-page mistakes.
  for i in 0..<4096: result.bytes[i] = byte((i + int(index)) mod 256)

# Select success before extracting a complete result, including generic owner payloads.
proc checked[T](r: MachineResult[T]): T =
  assert r.error == MachineError.None
  r.value

# A literal single-trap program provides an independent validated entry for state capture.
proc programOwner(): Program =
  let decoded = decodeProgram([0'u8, 0, 1, 0, 1], CodeAddress(0),
    ProgramByteLimit(5), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  decoded.value

# CPU values include unsigned extremes and a true charged flag; memory operations must retain all of them.
proc cpu(): MachineInfo =
  result = MachineInfo(pc: CodeAddress(0), gas: MachineGas(high(uint64)),
    blockCharged: true, registers: default(RegisterFile))
  # Populate every register so partial/default copies cannot satisfy equality checks.
  for i in 0..<13: result.registers[i] = RegisterValue(high(uint64) - uint64(i))

# Compare copied fields explicitly because nominal values intentionally do not expose implicit equality.
proc sameCpu(a, b: MachineInfo) =
  assert uint64(a.pc) == uint64(b.pc) and uint64(a.gas) == uint64(b.gas)
  assert a.blockCharged == b.blockCharged
  # Every register must survive successful stores and failed operations unchanged.
  for i in 0..<13: assert uint64(a.registers[i]) == uint64(b.registers[i])

let defaultResult = default(MachineResult[Memory])
assert defaultResult.error == MachineError.Uninitialized
let empty = checked(captureMemory([], PageLimit(0)))
assert load(default(Memory), MemoryAddress(0x10000), AccessWidth(1)).error ==
    MachineError.InvalidOwner
assert store(default(Memory), MemoryAddress(0x10000), AccessWidth(1), RegisterValue(0)).error ==
    MachineError.InvalidOwner
# Read-only preflight preserves invalid-owner priority even when the width is also invalid.
assert writableScalar(default(Memory), MemoryAddress(0x10000), AccessWidth(0)).error ==
    MachineError.InvalidOwner
assert pageImage(default(Memory), PageIndex(0)).error == MachineError.InvalidOwner
assert withPage(default(Memory), page(16, PageAccess.ReadWrite)).error == MachineError.InvalidOwner
assert machineInfo(default(Machine)).error == MachineError.InvalidOwner
assert memoryOf(default(Machine)).error == MachineError.InvalidOwner
assert withMemory(default(Machine), empty).error == MachineError.InvalidOwner
assert withRegister(default(Machine), RegisterIndex(0), RegisterValue(0)).error ==
    MachineError.InvalidOwner
assert store(default(Machine), MemoryAddress(0), AccessWidth(1), RegisterValue(0)).error ==
    MachineError.InvalidOwner
assert captureMachine(programOwner(), default(Memory), cpu()).error == MachineError.InvalidOwner
assert captureMachine(default(Program), empty, cpu()).error == MachineError.InvalidProgram
var badPc = cpu()
badPc.pc = CodeAddress(high(uint64))
assert captureMachine(programOwner(), empty, badPc).error == MachineError.InvalidProgram

# Shapes, ordering, count limits and ordinal boundaries fail before publishing any owner.
assert captureMemory([page(0x100000, PageAccess.ReadWrite)], PageLimit(1)).error ==
    MachineError.InvalidPage
assert captureMemory([page(16, PageAccess.ReadWrite)], PageLimit(0)).error ==
    MachineError.LimitExceeded
assert captureMemory([page(16, PageAccess.ReadWrite), page(16, PageAccess.ReadOnly)], PageLimit(
    2)).error == MachineError.UnsortedPages
assert captureMemory([page(17, PageAccess.ReadWrite), page(16, PageAccess.ReadOnly)], PageLimit(
    2)).error == MachineError.UnsortedPages
assert pageImage(empty, PageIndex(high(uint32))).error == MachineError.InvalidPage
assert withPage(empty, page(16, PageAccess.ReadWrite)).error == MachineError.LimitExceeded
assert withPage(empty, page(high(uint32), PageAccess.ReadWrite)).error == MachineError.InvalidPage
let absent = checked(pageImage(empty, PageIndex(16)))
assert absent.access == PageAccess.Inaccessible
# All absent bytes are zero in the sparse representation, not uninitialized host memory.
for b in absent.bytes: assert b == 0

# Every non-scalar width is a typed local error; it never silently truncates or becomes a large scan.
for width in 0..255:
  let r = load(empty, MemoryAddress(0x10000), AccessWidth(byte(width)))
  let w = store(empty, MemoryAddress(0x10000), AccessWidth(byte(width)), RegisterValue(0))
  let preflight = writableScalar(empty, MemoryAddress(0x10000), AccessWidth(byte(width)))
  # Legal widths reach permission validation and report the same aligned missing page.
  if width in [1, 2, 4, 8]:
    assert r.error == MachineError.Fault and uint32(r.faultPage) == 0x10000
    assert w.error == MachineError.Fault and uint32(w.faultPage) == 0x10000
    assert preflight.error == MachineError.Fault and uint32(preflight.faultPage) == 0x10000
  else:
    # Invalid widths are rejected even though the addressed memory would also fault.
    assert r.error == MachineError.InvalidWidth and w.error == MachineError.InvalidWidth
    assert preflight.error == MachineError.InvalidWidth

# Reference permission matrix uses two dense literal page inputs, independent from sparse lookup.
for leftAccess in [PageAccess.Inaccessible, PageAccess.ReadOnly, PageAccess.ReadWrite]:
  for rightAccess in [PageAccess.Inaccessible, PageAccess.ReadOnly, PageAccess.ReadWrite]:
    let inputs = [page(16, leftAccess), page(17, rightAccess)]
    let memory = checked(captureMemory(inputs, PageLimit(2)))
    # Probe both sides of protection, page and mapped/unmapped boundaries.
    for boundary in [65536, 69632, 73728]:
      for delta in -8..8:
        for width in [1, 2, 4, 8]:
          let start = boundary + delta
          var readError = MachineError.None
          var writeError = MachineError.None
          var readFault = 0'u32
          var writeFault = 0'u32
          var missingFault = 0'u32
          var expected = 0'u64
          # The dense reference evaluates bytes in ascending order without production helper calls.
          for offset in 0..<width:
            let address = start + offset
            let ordinal = address div 4096
            var access = PageAccess.Inaccessible
            # Only the two fixture pages are present; all others are independently inaccessible.
            if ordinal == 16 or ordinal == 17: access = inputs[ordinal - 16].access
            # Presence priority is independent of writability: retain the first absent page separately.
            if address >= 65536 and access == PageAccess.Inaccessible and missingFault == 0:
              missingFault = uint32(ordinal * 4096)
            # Protected accesses dominate at these non-wrapping boundaries.
            if address < 65536:
              readError = MachineError.Panic
              writeError = MachineError.Panic
            else:
              # Record only the first fault so cross-page cases cannot overwrite its address.
              if readError == MachineError.None and access == PageAccess.Inaccessible:
                readError = MachineError.Fault
                readFault = uint32(ordinal * 4096)
              if writeError == MachineError.None and access != PageAccess.ReadWrite:
                writeError = MachineError.Fault
                writeFault = uint32(ordinal * 4096)
              if ordinal == 16 or ordinal == 17:
                # Expected bytes come directly from the input fixture, not a production load.
                expected = expected or (uint64(inputs[ordinal - 16].bytes[address mod 4096]) shl (
                    8 * offset))
          # GP-PVM-008 gives missing pages priority over an earlier read-only page for scalar writes.
          if start >= 65536 and missingFault != 0:
            writeFault = missingFault
          let read = load(memory, MemoryAddress(uint64(start)), AccessWidth(byte(width)))
          let written = store(memory, MemoryAddress(uint64(start)), AccessWidth(byte(width)),
              RegisterValue(0x8877665544332211'u64))
          let preflight = writableScalar(memory, MemoryAddress(uint64(start)), AccessWidth(byte(width)))
          assert read.error == readError and written.error == writeError
          assert preflight.error == writeError
          if writeError == MachineError.None:
            # The query reports eligibility only and never publishes replacement storage.
            assert preflight.value
          elif writeError == MachineError.Fault:
            # The dense reference fixes missing-before-read-only ordering independently of store.
            assert uint32(preflight.faultPage) == writeFault
          # Success must reproduce every input byte in little-endian order.
          if readError == MachineError.None: assert uint64(read.value) == expected
          if readError == MachineError.Fault:
            # Fault metadata is part of the reason, selected only after establishing Fault.
            assert uint32(read.faultPage) == readFault
          if writeError == MachineError.Fault:
            # Failed cross-page stores expose no new snapshot and retain the selected fault.
            assert uint32(written.faultPage) == writeFault
          # Both old pages remain byte-for-byte unchanged after success or failure.
          for i in 0..1:
            let old = checked(pageImage(memory, PageIndex(uint32(16 + i))))
            assert old.bytes == inputs[i].bytes and old.access == inputs[i].access
            if writeError == MachineError.None:
              # Verify every byte, including untouched neighbors and both ends of a cross-page store.
              let updated = checked(pageImage(written.value, PageIndex(uint32(16 + i))))
              for j in 0..<4096:
                let absolute = (16 + i) * 4096 + j
                let offset = absolute - start
                if offset >= 0 and offset < width:
                  assert updated.bytes[j] == byte((0x8877665544332211'u64 shr (8 * offset)) and 255)
                else:
                  assert updated.bytes[j] == inputs[i].bytes[j]

# PolkaVM cross-page regression witnesses; source pin and adaptation are recorded in spec/pvm-machine.md.
# A failing store must not partially publish the first half before the missing page is supplied.
let zeroPage = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
  bytes: default(array[4096, byte]))
let firstOnly = checked(captureMemory([zeroPage], PageLimit(2)))
let partialStore = store(firstOnly, MemoryAddress(0x10ffe), AccessWidth(4),
    RegisterValue(0x12345678))
assert partialStore.error == MachineError.Fault and uint32(
    partialStore.faultPage) == 0x11000
assert uint64(checked(load(firstOnly, MemoryAddress(0x10ffe), AccessWidth(2)))) == 0
let bothPages = checked(withPage(firstOnly, PageImage(index: PageIndex(17),
  access: PageAccess.ReadWrite, bytes: default(array[4096, byte]))))
let retried = checked(store(bothPages, MemoryAddress(0x10ffe), AccessWidth(4),
  RegisterValue(0x12345678)))
assert uint64(checked(load(retried, MemoryAddress(0x10ffe), AccessWidth(2)))) == 0x5678
assert uint64(checked(load(retried, MemoryAddress(0x11000), AccessWidth(2)))) == 0x1234
assert uint64(checked(load(bothPages, MemoryAddress(0x10ffe), AccessWidth(4)))) == 0

# The upstream load witness reads aa/bb across the page edge, including after write protection.
let missingRead = load(empty, MemoryAddress(0x10ffe), AccessWidth(4))
assert missingRead.error == MachineError.Fault and uint32(
    missingRead.faultPage) == 0x10000
var readLeft = zeroPage
var readRight = PageImage(index: PageIndex(17), access: PageAccess.ReadWrite,
  bytes: default(array[4096, byte]))
readLeft.bytes[4095] = 0xaa
readRight.bytes[0] = 0xbb
# Both permission modes must produce the same byte order and value.
for access in [PageAccess.ReadWrite, PageAccess.ReadOnly]:
  readLeft.access = access
  readRight.access = access
  let readable = checked(captureMemory([readLeft, readRight], PageLimit(2)))
  assert uint64(checked(load(readable, MemoryAddress(0x10ffe), AccessWidth(
      4)))) == 0x00bbaa00

# Low memory remains protected even when explicitly mapped readable/writable by the environment.
let lowMapped = checked(captureMemory([page(0, PageAccess.ReadWrite), page(15,
    PageAccess.ReadWrite)], PageLimit(2)))
assert load(lowMapped, MemoryAddress(0), AccessWidth(1)).error == MachineError.Panic
assert store(lowMapped, MemoryAddress(65535), AccessWidth(2), RegisterValue(0)).error ==
    MachineError.Panic
let highMapped = checked(captureMemory([page(0xfffff, PageAccess.ReadWrite)], PageLimit(1)))
assert uint64(checked(load(highMapped, MemoryAddress(0xfffffffe'u64), AccessWidth(1)))) == 253
assert load(highMapped, MemoryAddress(0xffffffff'u64), AccessWidth(1)).error == MachineError.Panic
assert load(highMapped, MemoryAddress(0xffffffff'u64), AccessWidth(2)).error == MachineError.Panic
assert store(highMapped, MemoryAddress(high(uint64)), AccessWidth(8), RegisterValue(0)).error ==
    MachineError.Panic
assert load(empty, MemoryAddress(0x100000000'u64), AccessWidth(1)).error == MachineError.Panic
let normal = checked(captureMemory([page(16, PageAccess.ReadWrite)], PageLimit(1)))
assert checked(writableScalar(normal, MemoryAddress(0x100010000'u64), AccessWidth(8)))
assert writableScalar(lowMapped, MemoryAddress(65535), AccessWidth(2)).error == MachineError.Panic
assert uint64(checked(load(normal, MemoryAddress(0x100010000'u64), AccessWidth(8)))) == 0x1716151413121110'u64
# PolkaVM checks exclusive-end overflow before ordinary permissions: absent final page faults, present final page traps.
# Probe the exact fitting/overflowing boundary at every scalar width and both 32/64-bit address extremes.
for width in [1, 2, 4, 8]:
  for access in [PageAccess.Inaccessible, PageAccess.ReadOnly, PageAccess.ReadWrite]:
    let originalPage = page(0xfffff, access)
    let memory = checked(captureMemory([page(0, PageAccess.ReadWrite), originalPage], PageLimit(2)))
    for start in [0xffffffff'u64 - uint64(width), 0x100000000'u64 - uint64(width),
        0xffffffff'u64, high(uint64)]:
      let overflow = (start and 0xffffffff'u64) + uint64(width) > 0xffffffff'u64
      let expectedRead = if overflow and access != PageAccess.Inaccessible: MachineError.Panic
        elif access == PageAccess.Inaccessible: MachineError.Fault else: MachineError.None
      let expectedWrite = if overflow and access != PageAccess.Inaccessible: MachineError.Panic
        elif access != PageAccess.ReadWrite: MachineError.Fault else: MachineError.None
      let loaded = load(memory, MemoryAddress(start), AccessWidth(byte(width)))
      let written = store(memory, MemoryAddress(start), AccessWidth(byte(width)), RegisterValue(0))
      let preflight = writableScalar(memory, MemoryAddress(start), AccessWidth(byte(width)))
      assert loaded.error == expectedRead and written.error == expectedWrite
      assert preflight.error == expectedWrite
      if expectedWrite == MachineError.None:
        # Exact-fitting scalar extents succeed without copying or changing the retained page.
        assert preflight.value
      elif expectedWrite == MachineError.Fault:
        # Final-page absence remains distinguishable from present-page overflow panic.
        assert uint32(preflight.faultPage) == 0xfffff000'u32
      if loaded.error == MachineError.Fault:
        assert uint32(loaded.faultPage) == 0xfffff000'u32 # Fault metadata retains the final physical page.
      if written.error == MachineError.Fault:
        assert uint32(written.faultPage) == 0xfffff000'u32 # Read-only nonoverflow writes fault; overflowing present-page writes trap.
      assert checked(pageImage(memory, PageIndex(0xfffff))).bytes == originalPage.bytes
      assert checked(pageImage(memory, PageIndex(0xfffff))).access == access

# Environment updates preserve hidden bytes, insert in order and enforce limits only for new pages.
var local = page(17, PageAccess.Inaccessible)
let original = checked(captureMemory([local], PageLimit(3)))
local.bytes[0] = 77
assert checked(pageImage(original, PageIndex(17))).bytes[0] == 17
var unlocked = checked(pageImage(original, PageIndex(17)))
unlocked.access = PageAccess.ReadWrite
let repaired = checked(withPage(original, unlocked))
assert uint64(checked(load(repaired, MemoryAddress(69632), AccessWidth(1)))) == 17
assert load(original, MemoryAddress(69632), AccessWidth(1)).error == MachineError.Fault
let inserted = checked(withPage(checked(withPage(repaired, page(18, PageAccess.ReadOnly))), page(16,
    PageAccess.ReadWrite)))
assert checked(pageImage(inserted, PageIndex(16))).bytes[0] == 16
assert checked(pageImage(inserted, PageIndex(18))).bytes[0] == 18
assert withPage(inserted, page(19, PageAccess.ReadWrite)).error == MachineError.LimitExceeded
assert withPage(inserted, page(18, PageAccess.Inaccessible)).error == MachineError.None

# CPU snapshots are fully copied and memory replacement leaves PC, gas, charged flag and registers alone.
let initialCpu = cpu()
let initial = checked(captureMachine(programOwner(), inserted, initialCpu))
var copiedCpu = checked(machineInfo(initial))
copiedCpu.registers[0] = RegisterValue(0)
sameCpu(checked(machineInfo(initial)), initialCpu)
let stored = checked(store(initial, MemoryAddress(69631), AccessWidth(2), RegisterValue(0xbeef)))
sameCpu(checked(machineInfo(stored)), initialCpu)
assert uint64(checked(load(checked(memoryOf(stored)), MemoryAddress(69631), AccessWidth(2)))) == 0xbeef
assert store(initial, MemoryAddress(73728), AccessWidth(1), RegisterValue(0)).error ==
    MachineError.Fault
sameCpu(checked(machineInfo(initial)), initialCpu)
let machineFault = store(initial, MemoryAddress(73728), AccessWidth(1), RegisterValue(0))
assert machineFault.error == MachineError.Fault and uint32(machineFault.faultPage) == 73728
assert store(initial, MemoryAddress(69632), AccessWidth(3), RegisterValue(0)).error ==
    MachineError.InvalidWidth
let zeroCpu = MachineInfo(pc: CodeAddress(0), gas: MachineGas(0),
  blockCharged: false, registers: default(RegisterFile))
let zeroMachine = checked(captureMachine(programOwner(), empty, zeroCpu))
sameCpu(checked(machineInfo(zeroMachine)), zeroCpu)
assert store(zeroMachine, MemoryAddress(0xffffffff'u64), AccessWidth(2), RegisterValue(0)).error ==
    MachineError.Fault
assert uint32(store(zeroMachine, MemoryAddress(0xffffffff'u64), AccessWidth(2), RegisterValue(
    0)).faultPage) == 0xfffff000'u32
let replaced = checked(withMemory(initial, empty))
sameCpu(checked(machineInfo(replaced)), initialCpu)
assert withMemory(initial, default(Memory)).error == MachineError.InvalidOwner
# Direct API indices are validated, while valid indices update exactly one of thirteen values.
for index in 0..255:
  let updated = withRegister(initial, RegisterIndex(byte(index)), RegisterValue(123))
  if index < 13:
    # Compare all thirteen registers so neighboring fields cannot be accidentally overwritten.
    let info = checked(machineInfo(checked(updated)))
    for other in 0..<13:
      assert uint64(info.registers[other]) == (if other == index: 123'u64 else: uint64(
          initialCpu.registers[other]))
    assert uint64(info.gas) == high(uint64) and info.blockCharged
  else:
    # Invalid nominal values are local errors, never bounds-check crashes.
    assert updated.error == MachineError.InvalidRegister

# Dense neighboring pairs separated by sparse holes expose incorrect reuse of insertion slots as page identities.
block sparseScalarSpans:
  var images: seq[PageImage] = @[]
  for pair in 0..<64:
    images.add(page(uint32(16+3*pair), PageAccess.ReadWrite))
    images.add(page(uint32(17+3*pair), PageAccess.ReadWrite))
  let memory = checked(captureMemory(images, PageLimit(128)))
  let retained = memory
  for pair in 0..<64:
    let first = uint32(16+3*pair)
    let address = MemoryAddress(uint64(first)*4096+4093)
    var expected = 0'u64
    for i in 0..<8:
      # Independent literal byte selection spans three bytes in the first page and five in the second.
      let offset = 4093+i
      let ordinal = first+uint32(offset div 4096)
      expected = expected or (uint64(byte((offset mod 4096+int(ordinal)) mod 256)) shl (8*i))
    assert uint64(checked(load(memory, address, AccessWidth(8)))) == expected
    let written = checked(store(memory, address, AccessWidth(8), RegisterValue(
        0x9876543210abcdef'u64)))
    assert uint64(checked(load(written, address, AccessWidth(8)))) == 0x9876543210abcdef'u64
    assert uint64(checked(load(retained, address, AccessWidth(8)))) == expected
    for side in 0..<2:
      let actual = checked(pageImage(written, PageIndex(first+uint32(side))))
      for i in 0..<4096:
        # Full-page comparisons reject neighboring-byte writes and preserve original page ownership.
        let relative = side*4096+i-4093
        let wanted = if relative >= 0 and relative < 8:
            byte((0x9876543210abcdef'u64 shr (8*relative)) and 255)
          else: images[2*pair+side].bytes[i]
        assert actual.bytes[i] == wanted
    let gap = MemoryAddress((uint64(first)+1)*4096+4095)
    let refused = store(memory, gap, AccessWidth(8), RegisterValue(0))
    assert refused.error == MachineError.Fault
    assert uint32(refused.faultPage) == (first+2)*4096
    assert checked(pageImage(retained, PageIndex(first+1))).bytes == images[2*pair+1].bytes

# Each call releases a machine, shared aliases, copied page and two generations of changed memory.
proc releaseCycle() =
  let memory = checked(captureMemory([page(16, PageAccess.ReadWrite), page(17,
      PageAccess.ReadWrite)], PageLimit(2)))
  let machine = checked(captureMachine(programOwner(), memory, cpu()))
  let alias = machine
  let written = checked(store(machine, MemoryAddress(69631), AccessWidth(8), RegisterValue(42)))
  let changed = checked(withRegister(written, RegisterIndex(12), RegisterValue(99)))
  assert uint64(checked(load(checked(memoryOf(changed)), MemoryAddress(69631), AccessWidth(8)))) == 42
  assert uint64(checked(machineInfo(alias)).registers[12]) == high(uint64) - 12

releaseCycle()
let before = getOccupiedMem()
# A thousand complete owner lifetimes expose retained cycles or accidental shared mutation.
for iteration in 0..<1000: releaseCycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_machine", 1000, before, after)
echo "PVM machine and memory passed"
echo "ARC_RELEASE cycles=1000 unchanged"
