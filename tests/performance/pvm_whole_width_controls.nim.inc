# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Each specialized callback must preserve original public scalar bytes, faults and immutable owners.
for logWidth in 0..<4:
  # Exercise every callback width across ordinary, crossing, protected, missing and final-page spans.
  let width = 1 shl logWidth
  let loadOpcode = byte(124+2*logWidth)
  let storeOpcode = byte(120+logWidth)
  let readCode = source(@[loadOpcode, 0x17, 0, 50, 0, 0], @[0, 3])
  let writeCode = source(@[storeOpcode, 0x17, 0, 50, 0, 0], @[0, 3])
  for scenario in 0..<11:
    var first = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
        bytes: default(array[4096, byte]))
    var second = PageImage(index: PageIndex(17), access: PageAccess.ReadWrite,
        bytes: default(array[4096, byte]))
    var finalPage = PageImage(index: PageIndex(1048575), access: PageAccess.ReadWrite,
        bytes: default(array[4096, byte]))
    for i in 0..<4096:
      first.bytes[i] = byte(i and 255)
      second.bytes[i] = byte((i+19) and 255)
      finalPage.bytes[i] = byte((i+31) and 255)
    if scenario == 3: first.access = PageAccess.ReadOnly
    if scenario == 4: second.access = PageAccess.ReadOnly
    let made = captureMemory(if scenario == 5: @[first, finalPage]
        else: @[first, second, finalPage], PageLimit(4))
    assert made.error == MachineError.None
    let address = case scenario
      of 1: 0x101ff'u64
      of 2, 4, 5: 0x10fff'u64
      of 6: 0xffff'u64
      of 7: 0xffffffff'u64
      of 8: 0x100010018'u64
      of 9: 0xffffffff'u64-uint64(width)
      of 10: 0x12000'u64
      else: 0x10018'u64
    var cpu = registers
    cpu[1] = RegisterValue(address)
    cpu[7] = RegisterValue(0x8877665544332211'u64)
    let read = load(made.value, MemoryAddress(address), AccessWidth(byte(width)))
    let (loaded, unchangedMemory) = execute(readCode, made.value, cpu)
    assert loaded.loads == 1 and loaded.stores == 0
    if read.error == MachineError.None:
      assert loaded.status == 1 and loaded.pc == 0 and loaded.registers[7] == uint64(read.value)
    else:
      assert loaded.status == (if read.error == MachineError.Panic: 2'u64 else: 3'u64)
      assert loaded.pc == 0
      if read.error == MachineError.Fault: assert loaded.fault_page == uint64(read.faultPage)
      assert loaded.registers[7] == uint64(cpu[7])
    unchanged(made.value, unchangedMemory)
    let written = store(made.value, MemoryAddress(address), AccessWidth(byte(width)), cpu[7])
    let (stored, actual) = execute(writeCode, made.value, cpu)
    assert stored.stores == 1 and stored.loads == 0
    if written.error == MachineError.None:
      assert stored.status == 1 and stored.pc == 0
      unchanged(written.value, actual)
    else:
      assert stored.status == (if written.error == MachineError.Panic: 2'u64 else: 3'u64)
      assert stored.pc == 0
      if written.error == MachineError.Fault: assert stored.fault_page == uint64(written.faultPage)
      unchanged(made.value, actual)
    for i in 0..<13:
      # Address and untouched registers retain their original values, including the three caller-saved slots.
      if i != 7: assert loaded.registers[i] == uint64(cpu[i])
      assert stored.registers[i] == uint64(cpu[i])
    unchanged(made.value, captureMemory(if scenario == 5: @[first, finalPage]
        else: @[first, second, finalPage], PageLimit(4)).value)
    echo "WIDTH_CALLBACK_CONTROL,", width, ",", scenario, ",", read.error, ",", written.error
for logWidth in 0..<4:
  # Original address/data aliases must be read before a load destination overwrites them.
  let width = 1 shl logWidth
  let loadOpcode = byte(124+2*logWidth)
  let storeOpcode = byte(120+logWidth)
  var page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte]))
  for i in 0..<4096: page.bytes[i] = 0x80
  let memory = captureMemory(@[page], PageLimit(2)).value
  let address = 0x10018'u64
  let original = load(memory, MemoryAddress(address), AccessWidth(byte(width))).value
  var cpu = registers
  cpu[1] = RegisterValue(address)
  block:
    # Unsigned address/destination overlap retains low-width results and every other CPU register.
    let owner = source(@[loadOpcode, 0x11, 0, 50, 0, 0], @[0, 3])
    let (done, actual) = execute(owner, memory, cpu)
    assert done.status == 1 and done.registers[1] == uint64(original)
    for i in 0..<13:
      if i != 1: assert done.registers[i] == uint64(cpu[i])
    unchanged(memory, actual)
  if width < 8:
    # Signed loads share the same unsigned checked helper but must retain the original native sign extension.
    let owner = source(@[byte(loadOpcode+1), 0x11, 0, 50, 0, 0], @[0, 3])
    let (done, actual) = execute(owner, memory, cpu)
    let bits = width*8
    let expected = uint64(original) or (high(uint64) shl bits)
    assert done.status == 1 and done.registers[1] == expected
    unchanged(memory, actual)
  block:
    # Store data and address can be the same original register, including narrow truncated writes.
    let owner = source(@[storeOpcode, 0x11, 0, 50, 0, 0], @[0, 3])
    let oracle = store(memory, MemoryAddress(address), AccessWidth(byte(width)), cpu[1]).value
    let (done, actual) = execute(owner, memory, cpu)
    assert done.status == 1
    for i in 0..<13: assert done.registers[i] == uint64(cpu[i])
    unchanged(oracle, actual)
  block:
    # One image reuses copied writer handles across sealed epochs; published snapshots remain immutable.
    let owner = source(@[storeOpcode, 0x17, 0, 50, 0, 0], @[0, 3])
    var image = default(WholeImage)
    var diagnostic = ""
    assert compileWhole(owner, CodeAddress(0), image, diagnostic), diagnostic
    let writer = newScalarMemoryWriter(memory).value
    let alias = writer
    cpu[7] = RegisterValue(0x21)
    let first = invoke(image, writer, cpu)
    assert first.status == 1 and first.stores == 1
    let saved = snapshotMemory(alias).value
    let expectedSaved = store(memory, MemoryAddress(address), AccessWidth(byte(width)), cpu[7]).value
    unchanged(saved, expectedSaved)
    cpu[7] = RegisterValue(0x43)
    let second = invoke(image, alias, cpu)
    assert second.status == 1 and second.stores == 1
    let finalMemory = snapshotMemory(writer).value
    let expectedFinal = store(expectedSaved, MemoryAddress(address), AccessWidth(byte(width)), cpu[7]).value
    unchanged(finalMemory, expectedFinal)
    unchanged(saved, expectedSaved)
    unchanged(memory, captureMemory(@[page], PageLimit(2)).value)
    release(image)
  echo "WIDTH_ALIAS_EPOCH_CONTROL,", width
