# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Real generated guards must reject stale leases after alias COW, both kinds of seals, overlap and saturation.
proc probed(owner: Program, memory: Memory, cpu: RegisterFile, mode: LeaseProbe,
    replacement: uint64): (Invocation, Memory, Memory, bool) =
  ## Save immutable epochs and publish only after the synchronous invocation cleared all borrowed pointers.
  var image = default(WholeImage)
  var diagnostic = ""
  assert compileWhole(owner, CodeAddress(0), image, diagnostic), diagnostic
  let made = newScalarMemoryWriter(memory)
  assert made.error == MachineError.None
  let writer = made.value
  let (done, saved, fired) = invokeLeaseProbe(image, writer, cpu, mode, replacement)
  let snapshot = snapshotMemory(writer)
  assert snapshot.error == MachineError.None and done.exits == 1
  release(image)
  (done, snapshot.value, saved, fired)

for logWidth in 0..<4:
  # Every scalar width has actual native hits and generation-forced helper misses with identical byte semantics.
  let width = 1 shl logWidth
  let loadOpcode = byte(124+2*logWidth)
  let storeOpcode = byte(120+logWidth)
  var page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte]))
  for i in 0..<4096: page.bytes[i] = byte(i and 255)
  let captured = captureMemory(@[page], PageLimit(2))
  assert captured.error == MachineError.None
  let memory = captured.value
  let address = 0x10018'u64
  let loadThree = source(@[loadOpcode, 0x17, 0, loadOpcode, 0x18, 0, loadOpcode, 0x19, 0, 50, 0, 0],
      @[0, 3, 6, 9])
  let storeThree = source(@[storeOpcode, 0x17, 0, 149, 0x77, 1, storeOpcode, 0x17, 0,
      storeOpcode, 0x17, 0, 50, 0, 0], @[0, 3, 6, 9, 12])
  var cpu = registers
  cpu[1] = RegisterValue(address)
  cpu[7] = RegisterValue(0x7f)
  let original = load(memory, MemoryAddress(address), AccessWidth(byte(width)))
  assert original.error == MachineError.None
  let changed = store(memory, MemoryAddress(address), AccessWidth(byte(width)), RegisterValue(0x21))
  assert changed.error == MachineError.None
  block:
    # The first read leases an immutable source chunk; alias COW must make the next generated read miss.
    let (done, actual, saved, fired) = probed(loadThree, memory, cpu, LeaseProbe.ReadThenCow, 0x21)
    assert fired and done.status == 1 and done.pc == 0
    assert done.registers[7] == uint64(original.value)
    assert done.registers[8] == 0x21 and done.registers[9] == 0x21
    assert memoryPaths(done) == [1'u64, 0, 2, 0]
    unchanged(changed.value, actual)
    unchanged(captured.value, memory)
    echo "LEASE_READ_COW,", width, ",1,2"
  block:
    # An unchanged snapshot through a copied alias must revoke a readable lease even without pointer replacement.
    let (done, actual, saved, fired) = probed(loadThree, memory, cpu,
        LeaseProbe.ReadThenUnchangedSeal, 0)
    assert fired and done.status == 1 and done.pc == 0
    for i in 7..9: assert done.registers[i] == uint64(original.value)
    assert memoryPaths(done) == [1'u64, 0, 2, 0]
    unchanged(memory, actual)
    unchanged(memory, saved)
    echo "LEASE_UNCHANGED_SEAL,", width, ",1,2"
  block:
    # A writable lease must not mutate the immutable epoch just sealed by another writer alias.
    let first = store(memory, MemoryAddress(address), AccessWidth(byte(width)), RegisterValue(0x7f))
    let second = store(first.value, MemoryAddress(address), AccessWidth(byte(width)), RegisterValue(0x80))
    assert first.error == MachineError.None and second.error == MachineError.None
    let (done, actual, saved, fired) = probed(storeThree, memory, cpu, LeaseProbe.StoreThenSeal, 0)
    assert fired and done.status == 1 and done.pc == 0 and done.registers[7] == 0x80
    assert memoryPaths(done) == [0'u64, 1, 0, 2]
    unchanged(first.value, saved)
    unchanged(second.value, actual)
    unchanged(memory, captured.value)
    echo "LEASE_WRITABLE_SEAL,", width, ",1,2"
  block:
    # Overlapping writes through a copied alias invalidate descriptors even when the already-private pointer survives.
    let mixed = source(@[storeOpcode, 0x17, 0, loadOpcode, 0x18, 0, loadOpcode, 0x19, 0, 50, 0, 0],
        @[0, 3, 6, 9])
    let (done, actual, saved, fired) = probed(mixed, memory, cpu, LeaseProbe.StoreThenOverlap, 0x21)
    assert fired and done.status == 1 and done.pc == 0
    assert done.registers[8] == 0x21 and done.registers[9] == 0x21
    assert memoryPaths(done) == [1'u64, 0, 1, 1]
    unchanged(changed.value, actual)
    unchanged(memory, captured.value)
    echo "LEASE_OVERLAP,", width, ",1,1,1"
  block:
    # Generation saturation never wraps to revive old authority: all future accesses use the original checked path.
    let second = store(memory, MemoryAddress(address), AccessWidth(byte(width)), RegisterValue(0x80))
    assert second.error == MachineError.None
    let (done, actual, saved, fired) = probed(storeThree, memory, cpu, LeaseProbe.Saturated, 0)
    assert fired and done.status == 1 and done.pc == 0
    assert memoryPaths(done) == [0'u64, 0, 0, 3]
    unchanged(second.value, actual)
    unchanged(memory, captured.value)
    echo "LEASE_SATURATED,", width, ",0,3"
  block:
    # Read-only chunks can be leased for native reads but can never acquire writable authority.
    page.access = PageAccess.ReadOnly
    let readonly = captureMemory(@[page], PageLimit(2))
    assert readonly.error == MachineError.None
    let (done, actual) = execute(loadThree, readonly.value, cpu)
    assert done.status == 1 and memoryPaths(done) == [2'u64, 0, 1, 0]
    unchanged(readonly.value, actual)
    let refused = source(@[loadOpcode, 0x18, 0, storeOpcode, 0x17, 0, 50, 0, 0], @[0, 3, 6])
    let failure = execute(refused, readonly.value, cpu)
    assert failure[0].status == 3 and failure[0].pc == 3 and failure[0].fault_page == 65536
    assert memoryPaths(failure[0]) == [0'u64, 0, 1, 1]
    unchanged(readonly.value, failure[1])
    echo "LEASE_READONLY,", width, ",2,1,Fault"
block:
  # A warm writable chunk does not authorize a cross-page store into a read-only second page or a protected prefix.
  for scenario in 0..<3:
    var page = PageImage(index: PageIndex(if scenario == 2: 1048575'u32 else: 16'u32),
        access: PageAccess.ReadWrite, bytes: default(array[4096, byte]))
    let second = PageImage(index: PageIndex(17), access: PageAccess.ReadOnly,
        bytes: default(array[4096, byte]))
    let made = if scenario == 2: captureMemory(@[page], PageLimit(2))
      else: captureMemory(@[page, second], PageLimit(2))
    assert made.error == MachineError.None
    let start = if scenario == 0: 0x10ff0'u64 elif scenario == 1: 0x10000'u64 else: 0xfffffff0'u64
    let delta = if scenario == 1: 0xff'u8 else: 12'u8
    var cpu = registers
    cpu[1] = RegisterValue(start)
    cpu[7] = RegisterValue(0x8877665544332211'u64)
    let warm = store(made.value, MemoryAddress(start), AccessWidth(8), cpu[7])
    assert warm.error == MachineError.None
    let failedAddress = if scenario == 1: start-1 else: start+12
    let oracle = store(warm.value, MemoryAddress(failedAddress), AccessWidth(8), cpu[7])
    assert oracle.error in [MachineError.Panic, MachineError.Fault]
    let code = source(@[123'u8, 0x17, 0, 149, 0x11, delta, 123, 0x17, 0, 50, 0, 0], @[0, 3, 6, 9])
    let (done, actual) = execute(code, made.value, cpu)
    assert done.status == (if oracle.error == MachineError.Panic: 2'u64 else: 3'u64)
    assert done.pc == (if oracle.error == MachineError.Panic: 0'u64 else: 6'u64)
    if oracle.error == MachineError.Fault: assert done.fault_page == uint64(oracle.faultPage)
    assert memoryPaths(done) == [0'u64, 0, 0, 2]
    unchanged(warm.value, actual)
    unchanged(made.value, captureMemory(if scenario == 2: @[page] else: @[page, second], PageLimit(2)).value)
    echo "LEASE_ATOMIC_REFUSAL,", scenario, ",", oracle.error, ",", done.pc
block:
  # Cross-chunk writes retain the original complete span/COW path, then an ordinary same-chunk hit can resume.
  let page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite, bytes: default(array[
      4096, byte]))
  let memory = captureMemory(@[page], PageLimit(2)).value
  var cpu = registers
  cpu[1] = RegisterValue(0x101f8'u64)
  cpu[7] = RegisterValue(0x8877665544332211'u64)
  let owner = source(@[123'u8, 0x17, 0, 149, 0x11, 4, 123, 0x17, 0,
      123, 0x17, 0, 149, 0x11, 0xfc, 123, 0x17, 0, 123, 0x17, 0, 50, 0, 0], @[0, 3, 6, 9, 12, 15,
          18, 21])
  var expected = store(memory, MemoryAddress(0x101f8), AccessWidth(8), cpu[7]).value
  expected = store(expected, MemoryAddress(0x101fc), AccessWidth(8), cpu[7]).value
  expected = store(expected, MemoryAddress(0x101f8), AccessWidth(8), cpu[7]).value
  let (done, actual) = execute(owner, memory, cpu)
  assert done.status == 1 and done.pc == 0 and memoryPaths(done) == [0'u64, 1, 0, 4]
  unchanged(expected, actual)
  unchanged(memory, captureMemory(@[page], PageLimit(2)).value)
  echo "LEASE_CROSS_CHUNK,1,4"
