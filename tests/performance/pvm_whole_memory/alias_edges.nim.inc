# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Native hits preserve register/address aliasing, signed extension, low32 narrowing and the exclusive final byte.
for logWidth in 0..<4:
  let width = 1 shl logWidth
  let loadOpcode = byte(124+2*logWidth)
  let signedOpcode = if logWidth < 3: loadOpcode+1 else: loadOpcode
  let storeOpcode = byte(120+logWidth)
  var page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte]))
  for i in 0..<4096: page.bytes[i] = 0x80
  let memory = captureMemory(@[page], PageLimit(2)).value
  var cpu = registers
  cpu[1] = RegisterValue(0x10018)
  block:
    # The second signed native load consumes the original address before replacing that very guest register.
    let owner = source(@[signedOpcode, 0x18, 0, signedOpcode, 0x11, 0, 50, 0, 0], @[0, 3, 6])
    let raw = uint64(load(memory, MemoryAddress(0x10018), AccessWidth(byte(width))).value)
    let expected = if logWidth < 3: raw or (high(uint64) shl (width*8)) else: raw
    let (done, actual) = execute(owner, memory, cpu)
    assert done.status == 1 and done.registers[8] == expected and done.registers[1] == expected
    assert memoryPaths(done) == [1'u64, 0, 1, 0]
    unchanged(memory, actual)
    echo "LEASE_SIGNED_ADDRESS_ALIAS,", width, ",1,1"
  block:
    # Store data and address can name the same guest slot; native argument setup must preserve both.
    let owner = source(@[storeOpcode, 0x11, 0, storeOpcode, 0x11, 0, 50, 0, 0], @[0, 3, 6])
    let expected = store(memory, MemoryAddress(0x10018), AccessWidth(byte(width)), cpu[1]).value
    let (done, actual) = execute(owner, memory, cpu)
    assert done.status == 1 and done.registers[1] == uint64(cpu[1])
    assert memoryPaths(done) == [0'u64, 1, 0, 1]
    unchanged(expected, actual)
    unchanged(memory, captureMemory(@[page], PageLimit(2)).value)
    echo "LEASE_STORE_ADDRESS_ALIAS,", width, ",1,1"
  block:
    # High register bits never alter the physical 32-bit memory tag, for the initial helper or subsequent native hit.
    cpu[1] = RegisterValue(0x100010018'u64)
    let owner = source(@[loadOpcode, 0x18, 0, loadOpcode, 0x19, 0, 50, 0, 0], @[0, 3, 6])
    let expected = uint64(load(memory, MemoryAddress(uint64(cpu[1])), AccessWidth(byte(width))).value)
    let (done, actual) = execute(owner, memory, cpu)
    assert done.status == 1 and done.registers[8] == expected and done.registers[9] == expected
    assert done.registers[1] == uint64(cpu[1]) and memoryPaths(done) == [1'u64, 0, 1, 0]
    unchanged(memory, actual)
    echo "LEASE_LOW32_WRAP,", width, ",1,1"
  block:
    # A warm final physical chunk does not authorize the existing exclusive-end byte, even when within-chunk passes.
    let finalPage = PageImage(index: PageIndex(1048575), access: PageAccess.ReadWrite,
        bytes: default(array[4096, byte]))
    let finalMemory = captureMemory(@[finalPage], PageLimit(1)).value
    cpu[1] = RegisterValue(0xffffffe0'u64)
    cpu[7] = RegisterValue(0x8877665544332211'u64)
    let delta = byte(32-width)
    let warm = store(finalMemory, MemoryAddress(0xffffffe0'u64), AccessWidth(byte(width)), cpu[7]).value
    let oracle = store(warm, MemoryAddress(0x100000000'u64-uint64(width)), AccessWidth(byte(width)),
        cpu[7])
    assert oracle.error == MachineError.Panic
    let owner = source(@[storeOpcode, 0x17, 0, 149, 0x11, delta, storeOpcode, 0x17, 0, 50, 0, 0], @[
        0, 3, 6, 9])
    let (done, actual) = execute(owner, finalMemory, cpu)
    assert done.status == 2 and done.pc == 0 and memoryPaths(done) == [0'u64, 0, 0, 2]
    unchanged(warm, actual)
    unchanged(finalMemory, captureMemory(@[finalPage], PageLimit(1)).value)
    echo "LEASE_EXCLUSIVE_END,", width, ",Panic,0"
block:
  # A warm writable chunk cannot turn an absent physical page into a native access.
  let page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte]))
  let memory = captureMemory(@[page], PageLimit(1)).value
  var cpu = registers
  cpu[1] = RegisterValue(0x10ff0)
  cpu[7] = RegisterValue(0x8877665544332211'u64)
  let warm = store(memory, MemoryAddress(0x10ff0), AccessWidth(8), cpu[7]).value
  let owner = source(@[123'u8, 0x17, 0, 149, 0x11, 32, 123, 0x17, 0, 50, 0, 0], @[0, 3, 6, 9])
  let (done, actual) = execute(owner, memory, cpu)
  assert done.status == 3 and done.pc == 6 and done.fault_page == 69632
  assert memoryPaths(done) == [0'u64, 0, 0, 2]
  unchanged(warm, actual)
  unchanged(memory, captureMemory(@[page], PageLimit(1)).value)
  echo "LEASE_MISSING_PAGE,Fault,6,69632"

for logWidth in 0..<4:
  # A still-armed descriptor must be revoked by static stores, failed stores, and the last generation increment.
  let width = 1 shl logWidth
  let opcode = byte(124+2*logWidth)
  let page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte]))
  let memory = captureMemory(@[page], PageLimit(1)).value
  var cpu = registers
  cpu[1] = RegisterValue(0x10018)
  let owner = source(@[opcode, 0x17, 0, opcode, 0x18, 0, opcode, 0x19, 0, 50, 0, 0], @[0, 3, 6, 9])
  for mode in [LeaseProbe.ReadThenStaticCow, LeaseProbe.ReadThenFailedStore,
      LeaseProbe.ReadThenSaturatingCow]:
    let (done, actual, saved, fired) = probed(owner, memory, cpu, mode, 0x21)
    assert fired and done.status == 1 and done.pc == 0 and done.registers[7] == 0
    if mode == LeaseProbe.ReadThenFailedStore:
      assert done.registers[8] == 0 and done.registers[9] == 0
      unchanged(memory, actual)
    else:
      assert done.registers[8] == 0x21 and done.registers[9] == 0x21
      unchanged(store(memory, MemoryAddress(0x10018), AccessWidth(byte(width)), RegisterValue(
          0x21)).value, actual)
    if mode == LeaseProbe.ReadThenSaturatingCow:
      assert memoryPaths(done) == [0'u64, 0, 3, 0]
    else:
      assert memoryPaths(done) == [1'u64, 0, 2, 0]
    unchanged(memory, captureMemory(@[page], PageLimit(1)).value)
    echo "LEASE_ADDITIONAL_REVOCATION,", width, ",", mode, ",", memoryPaths(done)[0], ",",
        memoryPaths(done)[2]
