# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## A successful earlier helper cannot supply the PC or clobber CPU state for a later failed memory instruction.
for logWidth in 0..<4:
  # All widths must publish the second helper's nonzero fault PC, while panics still normalize to zero.
  let width = 1 shl logWidth
  let loadOpcode = byte(124+2*logWidth)
  let storeOpcode = byte(120+logWidth)
  for scenario in 0..<2:
    var page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
        bytes: default(array[4096, byte]))
    for i in 0..<4096: page.bytes[i] = byte(i and 255)
    let memory = captureMemory(@[page], PageLimit(2)).value
    let warm = if scenario == 0: 0x10ff8'u64 else: 0x10000'u64
    let delta = if scenario == 0: 8'u8 else: 0xff'u8
    let failedAddress = if scenario == 0: warm+8 else: warm-1
    var cpu = registers
    cpu[1] = RegisterValue(warm)
    let original = load(memory, MemoryAddress(warm), AccessWidth(byte(width))).value
    let failure = load(memory, MemoryAddress(failedAddress), AccessWidth(byte(width)))
    assert failure.error == (if scenario == 0: MachineError.Fault else: MachineError.Panic)
    let reads = source(@[loadOpcode, 0x17, 0, 149, 0x11, delta,
        loadOpcode, 0x1a, 0, 50, 0, 0], @[0, 3, 6, 9])
    let (loaded, actualRead) = execute(reads, memory, cpu)
    assert loaded.status == (if scenario == 0: 3'u64 else: 2'u64)
    assert loaded.pc == (if scenario == 0: 6'u64 else: 0'u64)
    assert loaded.loads == 2 and loaded.stores == 0
    assert loaded.registers[1] == failedAddress and loaded.registers[7] == uint64(original)
    for i in 0..<13:
      if i notin [1, 7]: assert loaded.registers[i] == uint64(cpu[i])
    if scenario == 0: assert loaded.fault_page == uint64(failure.faultPage)
    unchanged(memory, actualRead)
    let writes = source(@[storeOpcode, 0x1a, 0, 149, 0x11, delta,
        storeOpcode, 0x1a, 0, 50, 0, 0], @[0, 3, 6, 9])
    let expected = store(memory, MemoryAddress(warm), AccessWidth(byte(width)), cpu[10]).value
    let failedWrite = store(expected, MemoryAddress(failedAddress), AccessWidth(byte(width)), cpu[10])
    assert failedWrite.error == failure.error
    let (stored, actualWrite) = execute(writes, memory, cpu)
    assert stored.status == loaded.status and stored.pc == loaded.pc
    assert stored.loads == 0 and stored.stores == 2
    for i in 0..<13:
      assert stored.registers[i] == (if i == 1: failedAddress else: uint64(cpu[i]))
    if scenario == 0: assert stored.fault_page == uint64(failedWrite.faultPage)
    unchanged(expected, actualWrite)
    unchanged(memory, captureMemory(@[page], PageLimit(2)).value)
    echo "FAULT_PC_AFTER_SUCCESS,", width, ",", scenario, ",", stored.pc
