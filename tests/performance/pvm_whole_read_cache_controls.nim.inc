# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Actual backup hits retain current typed page owners across COW, alias seals, collisions and failures.
proc cachedExecute(owner: Program, memory: Memory, cpu: RegisterFile): (Invocation, Memory,
    array[3, uint64]) =
  ## Copy counters before publication; no mutable owner or pointer leaves the synchronous invocation.
  var image = default(WholeImage)
  var diagnostic = ""
  assert compileWhole(owner, CodeAddress(0), image, diagnostic), diagnostic
  let writer = newScalarMemoryWriter(memory).value
  let done = invoke(image, writer, cpu)
  let stats = readCacheCounters(writer)
  let saved = snapshotMemory(writer).value
  release(image)
  assert done.exits == 1
  (done, saved, stats)

for logWidth in 0..<4:
  # The same two-page alternation exercises one real backup hit at every admitted scalar width.
  let width = 1 shl logWidth
  let loadOpcode = byte(124+2*logWidth)
  let storeOpcode = byte(120+logWidth)
  var first = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte]))
  var second = PageImage(index: PageIndex(17), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte]))
  let third = PageImage(index: PageIndex(18), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte]))
  for i in 0..<4096:
    first.bytes[i] = 0x21
    second.bytes[i] = 0x43
  let memory = captureMemory(@[first, second, third], PageLimit(4)).value
  var cpu = registers
  cpu[1] = RegisterValue(0x10018)
  cpu[2] = RegisterValue(0x11018)
  let reads = source(@[loadOpcode, 0x17, 0, loadOpcode, 0x28, 0,
      loadOpcode, 0x19, 0, 50, 0, 0], @[0, 3, 6, 9])
  let originalA = uint64(load(memory, MemoryAddress(0x10018), AccessWidth(byte(width))).value)
  let originalB = uint64(load(memory, MemoryAddress(0x11018), AccessWidth(byte(width))).value)
  block:
    # A and B displace the single read window; A's second read must use the new typed backup entry.
    let (done, actual, stats) = cachedExecute(reads, memory, cpu)
    assert done.status == 1 and done.registers[7] == originalA
    assert done.registers[8] == originalB and done.registers[9] == originalA
    assert stats == [1'u64, 2, 0]
    unchanged(memory, actual)
  block:
    # Public alias stores clone A, B and C, evicting both original writable windows before reading A again.
    var image = default(WholeImage)
    var diagnostic = ""
    assert compileWhole(reads, CodeAddress(0), image, diagnostic), diagnostic
    let writer = newScalarMemoryWriter(memory).value
    let alias = writer
    let warm = invoke(image, writer, cpu)
    assert warm.status == 1 and readCacheCounters(writer) == [1'u64, 2, 0]
    var expected = memory
    for address in [0x10018'u64, 0x11018, 0x12018]:
      assert store(alias, MemoryAddress(address), AccessWidth(byte(width)), RegisterValue(
          0x65)).error == MachineError.None
      expected = store(expected, MemoryAddress(address), AccessWidth(byte(width)), RegisterValue(0x65)).value
    let done = invoke(image, writer, cpu)
    assert done.status == 1 and done.registers[7] == 0x65 and done.registers[9] == 0x65
    assert readCacheCounters(writer)[2] == 2
    unchanged(expected, snapshotMemory(alias).value)
    unchanged(memory, captureMemory(@[first, second, third], PageLimit(4)).value)
    release(image)
  block:
    # An unchanged seal through an alias still retires all64 entries before reusing the same writer.
    var image = default(WholeImage)
    var diagnostic = ""
    assert compileWhole(reads, CodeAddress(0), image, diagnostic), diagnostic
    let writer = newScalarMemoryWriter(memory).value
    let alias = writer
    assert invoke(image, writer, cpu).status == 1
    let saved = snapshotMemory(alias).value
    assert invoke(image, alias, cpu).status == 1
    assert readCacheCounters(writer) == [2'u64, 4, 0]
    unchanged(memory, saved)
    unchanged(memory, snapshotMemory(writer).value)
    release(image)
  block:
    # A cached private header is sealed immutably; later alias writes cannot change its observed bytes.
    var image = default(WholeImage)
    var diagnostic = ""
    assert compileWhole(reads, CodeAddress(0), image, diagnostic), diagnostic
    let writer = newScalarMemoryWriter(memory).value
    let alias = writer
    var expected = memory
    for address in [0x10018'u64, 0x11018, 0x12018]:
      assert store(writer, MemoryAddress(address), AccessWidth(byte(width)), RegisterValue(
          0x65)).error == MachineError.None
      expected = store(expected, MemoryAddress(address), AccessWidth(byte(width)), RegisterValue(0x65)).value
    let warm = invoke(image, writer, cpu)
    assert warm.status == 1 and warm.registers[7] == 0x65 and readCacheCounters(writer)[1] == 1
    let saved = snapshotMemory(alias).value
    let expectedSaved = expected
    for address in [0x10018'u64, 0x11018, 0x12018]:
      assert store(alias, MemoryAddress(address), AccessWidth(byte(width)), RegisterValue(
          0x76)).error == MachineError.None
      expected = store(expected, MemoryAddress(address), AccessWidth(byte(width)), RegisterValue(0x76)).value
    let done = invoke(image, writer, cpu)
    assert done.status == 1 and done.registers[7] == 0x76 and done.registers[9] == 0x76
    unchanged(saved, expectedSaved)
    unchanged(expected, snapshotMemory(writer).value)
    unchanged(saved, expectedSaved)
    release(image)
  block:
    # Page80 collides with16 under the fixed hash; exact page identity must make every alternating lookup miss.
    second.index = PageIndex(80)
    let colliding = captureMemory(@[first, second], PageLimit(2)).value
    var alternate = cpu
    alternate[2] = RegisterValue(0x50018)
    let (done, actual, stats) = cachedExecute(reads, colliding, alternate)
    assert done.status == 1 and done.registers[7] == originalA and done.registers[8] == originalB
    assert done.registers[9] == originalA and stats == [0'u64, 3, 0]
    unchanged(colliding, actual)
  block:
    # A warmed readable backup owner never grants writable access to its read-only page.
    first.access = PageAccess.ReadOnly
    second.index = PageIndex(17)
    let readonly = captureMemory(@[first, second], PageLimit(2)).value
    let refuses = source(@[loadOpcode, 0x17, 0, loadOpcode, 0x28, 0,
        loadOpcode, 0x19, 0, storeOpcode, 0x1a, 0, 50, 0, 0], @[0, 3, 6, 9, 12])
    let (done, actual, stats) = cachedExecute(refuses, readonly, cpu)
    assert done.status == 3 and done.pc == 9 and done.fault_page == 65536
    assert done.registers[10] == uint64(cpu[10]) and stats[0] == 1
    unchanged(readonly, actual)
  block:
    # A valid backup entry at A cannot bypass complete cross-page store preflight at its final byte.
    first.access = PageAccess.ReadWrite
    second.index = PageIndex(18)
    let crossing = captureMemory(@[first, second], PageLimit(2)).value
    var edge = cpu
    edge[1] = RegisterValue(0x10ff8)
    edge[2] = RegisterValue(0x12018)
    let owner = source(@[loadOpcode, 0x17, 0, loadOpcode, 0x28, 0, loadOpcode, 0x19, 0,
        149, 0x11, 7, storeOpcode, 0x1a, 0, 50, 0, 0], @[0, 3, 6, 9, 12, 15])
    let oracle = store(crossing, MemoryAddress(0x10fff), AccessWidth(byte(width)), edge[10])
    let (done, actual, stats) = cachedExecute(owner, crossing, edge)
    assert stats[0] == 1 and done.loads == 3 and done.stores == 1
    if width == 1:
      assert oracle.error == MachineError.None and done.status == 1
      unchanged(oracle.value, actual)
    else:
      assert oracle.error == MachineError.Fault and done.status == 3
      assert done.pc == 12 and done.fault_page == uint64(oracle.faultPage)
      unchanged(crossing, actual)
  echo "READ_CACHE_OWNER_CONTROLS,", width
