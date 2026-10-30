# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Private whole-image controls for native control flow, checked memory refusal and executable ownership.
import std/[assertions, syncio]
import ../../src/codec/natural
import ../../src/pvm/[program, machine]
import ./pvm_whole_image

proc source(code: seq[byte], starts: seq[int]): Program =
  ## Build canonical owner-bound small programs; arbitrary operand bytes never become native entry points.
  var wire: seq[byte] = @[0'u8, 0]
  let size = encode(JamNatural(uint64(code.len)))
  for i in 0..<size.len: wire.add(size.bytes[i])
  for value in code: wire.add(value)
  var mask = newSeq[byte]((code.len+7) div 8)
  for pc in starts:
    assert pc >= 0 and pc < code.len
    mask[pc div 8] = mask[pc div 8] or (1'u8 shl (pc mod 8))
  for value in mask: wire.add(value)
  let made = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(4096), JumpCountLimit(32))
  assert made.error == ProgramError.None
  made.value

proc execute(source: Program, memory: Memory, registers: RegisterFile): (Invocation, Memory) =
  ## Exactly one synchronous native entry owns no guest memory after the typed writer snapshot is published.
  var image = default(WholeImage)
  var diagnostic = ""
  assert compileWhole(source, CodeAddress(0), image, diagnostic), diagnostic
  let made = newScalarMemoryWriter(memory)
  assert made.error == MachineError.None
  let writer = made.value
  let done = invoke(image, writer, registers)
  let snapshot = snapshotMemory(writer)
  assert snapshot.error == MachineError.None and done.exits == 1
  release(image)
  (done, snapshot.value)

proc unchanged(left, right: Memory) =
  ## Every permission and byte is compared, including failure paths and immutable source backing.
  let before = memoryImages(left)
  let after = memoryImages(right)
  assert before.error == MachineError.None and after.error == MachineError.None
  assert before.value.len == after.value.len
  for i in 0..<before.value.len:
    assert uint32(before.value[i].index) == uint32(after.value[i].index)
    assert before.value[i].access == after.value[i].access
    assert before.value[i].bytes == after.value[i].bytes

var registers = default(RegisterFile)
registers[0] = RegisterValue(0xffff0000'u64)
for i in 1..<13: registers[i] = RegisterValue(0x1122334455667700'u64+uint64(i))
let empty = captureMemory(@[], PageLimit(4))
assert empty.error == MachineError.None
block:
  # Twenty source blocks traverse native branches without memory helpers or an interpreter return.
  let loop = source(@[149'u8, 0x77, 1, 172, 0x87, 3, 149, 0x77, 1, 172, 0x87, 0xf7, 50, 0, 0],
      @[0, 3, 6, 9, 12])
  var cpu = registers
  cpu[7] = RegisterValue(0)
  cpu[8] = RegisterValue(20)
  let (done, memory) = execute(loop, empty.value, cpu)
  echo "CONTROL_LOOP,", done.status, ",", done.pc, ",", done.registers[7], ",", done.exits
  assert done.status == 1 and done.pc == 0 and done.registers[7] == 20
  assert done.loads == 0 and done.stores == 0
  unchanged(empty.value, memory)
block:
  # A valid source opcode outside the explicit compiler subset rejects before any executable allocation.
  let unsupported = source(@[101'u8, 0, 50, 0, 0], @[0, 2])
  let before = allocationCounts()
  var image = default(WholeImage)
  var diagnostic = ""
  assert not compileWhole(unsupported, CodeAddress(0), image, diagnostic)
  assert diagnostic == "unsupported opcode 101 at 0"
  echo "CONTROL_UNSUPPORTED,", diagnostic, ",", allocationCounts()[0], ",", allocationCounts()[1]
  assert allocationCounts() == before
let storeProgram = source(@[123'u8, 0x17, 0, 50, 0, 0], @[0, 3])
let loadProgram = source(@[130'u8, 0x17, 0, 50, 0, 0], @[0, 3])
for scenario in 0..<4:
  # Protected-prefix, readonly, and second-page failure must match the real immutable scalar API exactly.
  var first = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte]))
  var second = PageImage(index: PageIndex(17), access: PageAccess.ReadOnly,
      bytes: default(array[4096, byte]))
  first.bytes[4095] = 0x12
  second.bytes[0] = 0x34
  if scenario == 1: first.access = PageAccess.ReadOnly
  let captured = captureMemory(@[first, second], PageLimit(4))
  assert captured.error == MachineError.None
  let address = if scenario == 0: 0xffff'u64 elif scenario == 2: 0x10fff'u64 else: 0x10000'u64
  var cpu = registers
  cpu[1] = RegisterValue(address)
  cpu[7] = RegisterValue(0x8877665544332211'u64)
  let oracle = store(captured.value, MemoryAddress(address), AccessWidth(8), cpu[7])
  let (done, actual) = execute(storeProgram, captured.value, cpu)
  echo "CONTROL_MEMORY,", scenario, ",", oracle.error, ",", done.status, ",", done.pc, ",",
      done.fault_page, ",", done.loads, ",", done.stores
  if oracle.error == MachineError.None:
    assert scenario == 3 and done.status == 1 and done.stores == 1
    unchanged(oracle.value, actual)
    var loadCpu = cpu
    loadCpu[7] = RegisterValue(0)
    let loaded = execute(loadProgram, actual, loadCpu)
    assert loaded[0].status == 1 and loaded[0].registers[7] == uint64(cpu[7])
    assert loaded[0].loads == 1 and loaded[0].stores == 0
    unchanged(actual, loaded[1])
  else:
    assert done.status == (if oracle.error == MachineError.Fault: 3'u64 else: 2'u64)
    assert done.pc == 0 and done.stores == 1 and done.loads == 0
    for i in 0..<13: assert done.registers[i] == uint64(cpu[i])
    if oracle.error == MachineError.Fault: assert done.fault_page == uint64(oracle.faultPage)
    unchanged(captured.value, actual)
  assert pageImage(captured.value, PageIndex(16)).value.bytes == first.bytes
block:
  # A signed byte load consumes the original address before overwriting that same guest register.
  var page = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly,
      bytes: default(array[4096, byte]))
  page.bytes[0] = 0x80
  let captured = captureMemory(@[page], PageLimit(4))
  assert captured.error == MachineError.None
  var cpu = registers
  cpu[1] = RegisterValue(0x10000)
  let signed = source(@[125'u8, 0x11, 0, 50, 0, 0], @[0, 3])
  let (done, actual) = execute(signed, captured.value, cpu)
  assert done.status == 1 and done.loads == 1 and done.registers[1] == 0xffffffffffffff80'u64
  unchanged(captured.value, actual)
block:
  # Nonzero-PC explicit and invalid-control panics publish the checked terminal PC zero, preserving earlier writes.
  let cases = @[
    source(@[51'u8, 7, 42, 0], @[0, 3]),
    source(@[51'u8, 7, 42, 40, 0x7f], @[0, 3]),
    source(@[51'u8, 7, 42, 50, 1, 0], @[0, 3]),
    source(@[2'u8, 80, 0x17, 42, 0x7f], @[0, 1])]
  for program in cases:
    var cpu = registers
    cpu[1] = RegisterValue(1)
    let (done, actual) = execute(program, empty.value, cpu)
    assert done.status == 2 and done.pc == 0 and done.registers[7] == 42
    unchanged(empty.value, actual)
block:
  # Memory panic normalization and nonzero fault PC retention share the actual checked-memory callback route.
  let program = source(@[51'u8, 7, 42, 123, 0x17, 0, 50, 0, 0], @[0, 3, 6])
  let readonly = PageImage(index: PageIndex(17), access: PageAccess.ReadOnly,
      bytes: default(array[4096, byte]))
  let captured = captureMemory(@[readonly], PageLimit(4))
  assert captured.error == MachineError.None
  for scenario in 0..<2:
    var cpu = registers
    cpu[1] = RegisterValue(if scenario == 0: 0xffff'u64 else: 0x11000'u64)
    let (done, actual) = execute(program, captured.value, cpu)
    assert done.status == (if scenario == 0: 2'u64 else: 3'u64)
    assert done.pc == (if scenario == 0: 0'u64 else: 3'u64)
    assert done.registers[7] == 42 and done.stores == 1
    unchanged(captured.value, actual)
block:
  # Immediate/register conditions validate both successors before either outcome; earlier writes survive panic.
  let badTargetRegister = source(@[51'u8, 9, 42, 172, 0x87, 0x7f, 50, 0, 0], @[0, 3, 6])
  let badTargetImmediate = source(@[51'u8, 9, 42, 83, 0x17, 1, 0x7f, 50, 0, 0], @[0, 3, 7])
  let missingRegister = source(@[51'u8, 9, 42, 40, 5, 50, 0, 0, 172, 0x87, 0xfd], @[0, 3, 5, 8])
  let missingImmediate = source(@[51'u8, 9, 42, 40, 5, 50, 0, 0, 83, 0x17, 1, 0xfd], @[0, 3, 5, 8])
  for program in @[badTargetRegister, badTargetImmediate, missingRegister, missingImmediate]:
    for taken in 0..<2:
      var cpu = registers
      cpu[7] = RegisterValue(if taken == 0: 2'u64 else: 0'u64)
      cpu[8] = RegisterValue(1)
      let (done, actual) = execute(program, empty.value, cpu)
      assert done.status == 2 and done.pc == 0
      for register in 0..<13:
        assert done.registers[register] == (if register == 9: 42'u64 else: uint64(cpu[register]))
      unchanged(empty.value, actual)
block:
  # A final nonterminator refuses compilation without allocating code or mutating any caller CPU/memory.
  let before = allocationCounts()
  for program in @[source(@[51'u8, 7, 42], @[0]), source(@[123'u8, 0x17, 0], @[0]),
      source(@[130'u8, 0x17, 0], @[0])]:
    var image = default(WholeImage)
    var diagnostic = ""
    assert not compileWhole(program, CodeAddress(0), image, diagnostic)
    assert diagnostic == "missing successor at 0"
    assert allocationCounts() == before
block:
  # Fallthrough is a true control opcode: a missing target is guest Panic, not local-invalid compilation refusal.
  let endProgram = source(@[1'u8], @[0])
  let (done, actual) = execute(endProgram, empty.value, registers)
  assert done.status == 2 and done.pc == 0
  for i in 0..<13: assert done.registers[i] == uint64(registers[i])
  unchanged(empty.value, actual)
block:
  # Automatic scope destruction and explicit release both retire one raw image exactly once.
  let before = allocationCounts()
  block:
    var image = default(WholeImage)
    var diagnostic = ""
    let halt = source(@[50'u8, 0, 0], @[0])
    assert compileWhole(halt, CodeAddress(0), image, diagnostic)
    assert allocationCounts()[0] == before[0]+1
  echo "CONTROL_LIFETIME,", before[0], ",", before[1], ",", allocationCounts()[0], ",",
      allocationCounts()[1]
  assert allocationCounts()[1] == before[1]+1
let counts = allocationCounts()
assert counts[0] > 0 and counts[0] == counts[1]
echo "WHOLE_CONTROLS_PASS,", counts[0], ",", counts[1]
