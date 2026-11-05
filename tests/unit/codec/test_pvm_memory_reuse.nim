# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Checked memory leases preserve source changes, permissions, budgets, host exits and immutable predecessors.
# @@Verification={"arc": "pvm_memory_reuse_arc_release"}
import std/[assertions, syncio]
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/step
import ../../support/arc_evidence

proc code(parts: openArray[seq[byte]]): Program =
  ## Independent literal framing keeps instruction boundaries separate from production operand decoding.
  var bytes: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    starts.add(bytes.len)
    for octet in part: bytes.add(octet)
  assert bytes.len < 128
  var wire = @[0'u8, 0, byte(bytes.len)]
  for octet in bytes: wire.add(octet)
  var mask = newSeq[byte]((bytes.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for octet in mask: wire.add(octet)
  let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(1024), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  decoded.value

proc input(owner: Program, memory: Memory, marker: int): Machine =
  ## Untouched-register and gas sentinels expose stale execution state independently of byte restoration.
  var registers = default(RegisterFile)
  for index in 0..<13: registers[index] = RegisterValue(uint64(marker*19+index))
  captureMachine(owner, memory, MachineInfo(pc: CodeAddress(0), gas: MachineGas(uint64(
      1000+marker)),
    registers: registers, blockCharged: false)).value

proc same(left, right: Machine) =
  ## Compare full CPU, map/access and all bytes, including bytes the test guest never writes.
  let a = machineInfo(left).value
  let b = machineInfo(right).value
  assert a == b, "complete CPU differs"
  let al = memoryLayout(memoryOf(left).value).value
  let bl = memoryLayout(memoryOf(right).value).value
  assert al == bl, "layout differs"
  for page in al:
    assert pageImage(memoryOf(left).value, page.index).value == pageImage(memoryOf(right).value,
        page.index).value

proc addWord(bytes: var seq[byte], value: uint64) =
  ## Test-only literal operand encoding keeps the address and data independent of the decoder.
  for shift in 0..<4:
    bytes.add(byte((value shr (shift*8)) and 255))

proc crossingStore(address, value: uint64): seq[byte] =
  ## Opcode 33 stores eight bytes; the last byte of page 63 crosses into bitmap word 1.
  result = @[33'u8, 4]
  result.addWord(address)
  result.addWord(value)

proc literalCrossingMemory(memory: Memory, images: openArray[PageImage], stored: bool) =
  ## Literal source bytes and eight stored octets check publication without another execution oracle.
  const written = [0xef'u8, 0xcd, 0xab, 0x89, 0x67, 0x45, 0x23, 0x01]
  let layout = memoryLayout(memory).value
  assert layout.len == images.len, "literal crossing map count"
  for slot in 0..<images.len:
    # Compare the complete ordered map and permissions, including untouched read-only padding.
    let physical = uint32(images[slot].index)
    assert layout[slot].index == images[slot].index and layout[slot].access == images[slot].access
    let page = pageImage(memory, images[slot].index).value
    assert page.access == images[slot].access
    for offset in 0..<4096:
      # The oracle is the input pattern plus this literal store, never execute/stepOnce/fresh-owner output.
      let address = uint64(physical)*4096+uint64(offset)
      var expected = byte((offset*7+int(physical)) mod 251)
      if stored and address >= 262141 and address < 262149:
        expected = written[int(address-262141)]
      assert page.bytes[offset] == expected, "literal crossing page bytes"

let owner = code([@[52'u8, 0, 0, 0, 1, 0], @[52'u8, 1, 0, 32, 1, 0],
  @[52'u8, 2, 255, 17, 1, 0],
  @[30'u8, 4, 255, 17, 1, 0, 123, 0, 0, 0],
  @[30'u8, 4, 0, 18, 1, 0, 109, 0, 0, 0], @[0'u8]])
let prepared = newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(10000))).value
var images: seq[PageImage] = @[]
for physical in [16'u32, 17, 18, 31]:
  var image = PageImage(index: PageIndex(physical),
    access: (if physical == 16: PageAccess.ReadOnly else: PageAccess.ReadWrite))
  for offset in 0..<4096: image.bytes[offset] = byte(physical)
  images.add(image)
let original = captureMemory(images, PageLimit(8)).value
var changed = original
for physical in [16'u32, 17, 18]:
  # The new source changes RO and clean RW bytes, plus a page dirtied by the previous invocation.
  var image = pageImage(original, PageIndex(physical)).value
  for offset in 0..<4096: image.bytes[offset] = byte(physical+40)
  changed = withPage(changed, image).value
var saved: seq[Machine] = @[]
for iteration in 0..<32:
  let memory = if iteration mod 2 == 0: original else: changed
  let source = input(owner, memory, iteration)
  let fresh = newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(10000))).value
  let expected = execute(source, ExecutionStepLimit(100), fresh)
  let actual = execute(source, ExecutionStepLimit(100), prepared)
  assert expected.error == StepError.None and actual.error == StepError.None
  assert expected.value.exit == actual.value.exit
  same(actual.value.machine, expected.value.machine)
  let cpu = machineInfo(actual.value.machine).value
  assert uint64(cpu.registers[0]) == uint64(pageImage(memory, PageIndex(16)).value.bytes[0])
  assert uint64(cpu.registers[1]) == uint64(pageImage(memory, PageIndex(18)).value.bytes[0])
  assert uint64(cpu.registers[2]) == uint64(pageImage(memory, PageIndex(17)).value.bytes[511])
  saved.add(actual.value.machine)

for variant in 0..<4:
  # Permission and count changes must discard old capabilities before subsequent native/checked access.
  var memory = changed
  if variant == 0:
    var page = pageImage(changed, PageIndex(17)).value
    page.access = PageAccess.ReadOnly
    memory = withPage(changed, page).value
  elif variant == 1:
    memory = withPageRange(changed, PageIndex(18), PageIndex(19), PageAccess.Inaccessible,
      PageContent.Preserved).value
  elif variant == 2:
    memory = withPage(changed, PageImage(index: PageIndex(64), access: PageAccess.ReadWrite)).value
  let source = input(owner, memory, 40+variant)
  let fresh = newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(10000))).value
  let actual = execute(source, ExecutionStepLimit(100), prepared)
  let expected = execute(source, ExecutionStepLimit(100), fresh)
  assert actual.error == expected.error and actual.error == StepError.None
  assert actual.value.exit == expected.value.exit
  same(actual.value.machine, expected.value.machine)

let interrupted = execute(input(owner, original, 99), ExecutionStepLimit(5), prepared)
assert interrupted.error == StepError.StepLimitExceeded
let finalSource = input(owner, changed, 100)
let finalFresh = newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(10000))).value
let recovered = execute(finalSource, ExecutionStepLimit(100), prepared)
let expected = execute(finalSource, ExecutionStepLimit(100), finalFresh)
assert recovered.error == StepError.None and expected.error == StepError.None
same(recovered.value.machine, expected.value.machine)
for iteration in 0..<saved.len:
  # Later reuse and mapping/fault exits must not mutate any independently published predecessor.
  let memory = if iteration mod 2 == 0: original else: changed
  let fresh = newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(10000))).value
  let expected = execute(input(owner, memory, iteration), ExecutionStepLimit(100), fresh)
  same(saved[iteration], expected.value.machine)
for index in 0..<images.len:
  assert pageImage(original, images[index].index).value == images[index]

block crossing_unpublished_reuse:
  ## A refused call leaves two dirty physical pages across the 63/64 bitmap-word boundary.
  let crossingOwner = code([crossingStore(262143'u64, 0x89abcdef'u64),
    crossingStore(262143'u64, 0x76543210'u64), @[0'u8]])
  var crossingImages: seq[PageImage] = @[]
  for physical in [63'u32, 64'u32]:
    var image = PageImage(index: PageIndex(physical), access: PageAccess.ReadWrite)
    for offset in 0..<4096:
      image.bytes[offset] = byte((offset*7+int(physical)) mod 251)
    crossingImages.add(image)
  let crossingOriginal = captureMemory(crossingImages, PageLimit(2)).value
  let crossingPrepared = newPreparedProgram(crossingOwner,
    defaultPreparedLimits(GasCycleLimit(10000))).value
  let stopped = execute(input(crossingOwner, crossingOriginal, 11), ExecutionStepLimit(1),
    crossingPrepared)
  assert stopped.error == StepError.StepLimitExceeded

  # Reuse the unchanged source after an unpublished store, then compare every CPU and page byte.
  let firstSource = input(crossingOwner, crossingOriginal, 12)
  let firstFresh = newPreparedProgram(crossingOwner,
    defaultPreparedLimits(GasCycleLimit(10000))).value
  let firstExpected = execute(firstSource, ExecutionStepLimit(100), firstFresh)
  let firstActual = execute(firstSource, ExecutionStepLimit(100), crossingPrepared)
  assert firstExpected.error == StepError.None and firstActual.error == StepError.None
  assert firstActual.value.exit == firstExpected.value.exit
  same(firstActual.value.machine, firstExpected.value.machine)
  assert preparedInfo(crossingPrepared).value.memoryReuses == 1
  assert preparedInfo(crossingPrepared).value.retainedMemoryPayloadBytes == 16384

  # A new source owner in page 64 overlaps one previously dirty page; the old result stays immutable.
  var updated = pageImage(crossingOriginal, PageIndex(64)).value
  updated.bytes[10] = updated.bytes[10] xor 0xff
  let crossingChanged = withPage(crossingOriginal, updated).value
  let secondSource = input(crossingOwner, crossingChanged, 13)
  let secondFresh = newPreparedProgram(crossingOwner,
    defaultPreparedLimits(GasCycleLimit(10000))).value
  let secondExpected = execute(secondSource, ExecutionStepLimit(100), secondFresh)
  let secondActual = execute(secondSource, ExecutionStepLimit(100), crossingPrepared)
  assert secondExpected.error == StepError.None and secondActual.error == StepError.None
  assert secondActual.value.exit == secondExpected.value.exit
  same(secondActual.value.machine, secondExpected.value.machine)
  same(firstActual.value.machine, firstExpected.value.machine)
  assert preparedInfo(crossingPrepared).value.memoryReuses == 2
  for index in 0..<crossingImages.len:
    assert pageImage(crossingOriginal, crossingImages[index].index).value == crossingImages[index]

block literal_crossing_publication_and_reuse:
  ## Both publication paths must mark page 64 independently and restore it before a later read.
  # Absolute store/load operands encode address 262141; the last three bytes of page 63 cross into 64.
  let literalOwner = code([@[62'u8, 0, 0xfd, 0xff, 3, 0],
    @[58'u8, 1, 0xfd, 0xff, 3, 0], @[0'u8]])
  for padded in [false, true]:
    # Two dirty pages select dense publication in a two-page map, sparse publication in a 64-page map.
    var literalImages: seq[PageImage] = @[]
    let count = if padded: 64 else: 2
    for slot in 0..<count:
      let physical = uint32(if slot < 2: 63+slot else: 126+slot)
      let access = if slot >= 2 and slot mod 2 == 0: PageAccess.ReadOnly else: PageAccess.ReadWrite
      var image = PageImage(index: PageIndex(physical), access: access)
      for offset in 0..<4096: image.bytes[offset] = byte((offset*7+int(physical)) mod 251)
      literalImages.add(image)
    let literalOriginal = captureMemory(literalImages, PageLimit(64)).value
    let literalPrepared = newPreparedProgram(literalOwner,
      defaultPreparedLimits(GasCycleLimit(10000))).value
    var initial = MachineInfo(gas: MachineGas(7), blockCharged: true,
      registers: default(RegisterFile))
    for index in 0..<13: initial.registers[index] = RegisterValue(uint64(100+index))
    initial.registers[0] = RegisterValue(0x0123456789abcdef'u64)
    let literalSource = captureMachine(literalOwner, literalOriginal, initial).value
    let published = execute(literalSource, ExecutionStepLimit(3), literalPrepared)
    assert published.error == StepError.None and published.value.exit == StepExit.Panic
    var expectedCpu = initial
    expectedCpu.registers[1] = RegisterValue(0x0123456789abcdef'u64)
    assert machineInfo(published.value.machine).value == expectedCpu
    let held = memoryOf(published.value.machine).value
    literalCrossingMemory(held, literalImages, true)
    literalCrossingMemory(memoryOf(literalSource).value, literalImages, false)

    # A local attempt-limit return publishes no machine, but leaves both dirty physical pages in idle scratch.
    let unpublished = execute(literalSource, ExecutionStepLimit(1), literalPrepared)
    assert unpublished.error == StepError.StepLimitExceeded
    literalCrossingMemory(held, literalImages, true)
    literalCrossingMemory(literalOriginal, literalImages, false)

    # Enter at the load: no store can hide a missing restoration of either dirty-bitmap word.
    var reading = initial
    reading.pc = CodeAddress(6)
    let readSource = captureMachine(literalOwner, literalOriginal, reading).value
    let restored = execute(readSource, ExecutionStepLimit(2), literalPrepared)
    assert restored.error == StepError.None and restored.value.exit == StepExit.Panic
    expectedCpu.registers[1] = RegisterValue(0x5c554e4740726b64'u64)
    assert machineInfo(restored.value.machine).value == expectedCpu, "restore precedes read-only suffix"
    assert preparedInfo(literalPrepared).value.memoryReuses == 2
    literalCrossingMemory(memoryOf(restored.value.machine).value, literalImages, false)
    literalCrossingMemory(memoryOf(readSource).value, literalImages, false)
    literalCrossingMemory(memoryOf(literalSource).value, literalImages, false)
    literalCrossingMemory(held, literalImages, true)

block sparse_physical_overlap_readback:
  ## Physical bitmap words and positional directory slots deliberately name different pages.
  let sparseOwner = code([@[62'u8, 0, 0xfd, 0xff, 3, 0],
    @[58'u8, 1, 0xfd, 0xff, 3, 0], @[52'u8, 2, 7, 0xd0, 0x0b, 0],
    @[52'u8, 3, 11, 0xe0, 0x0b, 0], @[52'u8, 4, 5, 0, 8, 0],
    @[52'u8, 5, 6, 0x20, 8, 0], @[0'u8]])
  var sparseImages: seq[PageImage] = @[]
  var changedImages: seq[PageImage] = @[]
  for slot in 0..<65:
    # Dirty physical 63/64 occupy slots 0/1; changed slots 63/64 are physical 189/190.
    let physical = uint32(if slot < 2: 63+slot else: 126+slot)
    let access = if slot >= 2 and slot mod 2 == 0: PageAccess.ReadOnly else: PageAccess.ReadWrite
    var image = PageImage(index: PageIndex(physical), access: access)
    for offset in 0..<4096: image.bytes[offset] = byte((offset*7+int(physical)) mod 251)
    sparseImages.add(image)
    if physical == 64:
      # These five incoming bytes participate in the cross-page load after dirty restoration.
      for offset, value in [0xa1'u8, 0xb2, 0xc3, 0xd4, 0xe5]: image.bytes[offset] = value
    elif physical == 128: image.bytes[5] = 0xc8
    elif physical == 189: image.bytes[7] = 0xa6
    elif physical == 190: image.bytes[11] = 0xb7
    changedImages.add(image)
  let sparseOriginal = captureMemory(sparseImages, PageLimit(66)).value
  var sparseChanged = sparseOriginal
  for slot in [1, 2, 63, 64]:
    # Keep physical 63 dirty-only and physical 130 neither dirty nor changed by preserving their owners.
    sparseChanged = withPage(sparseChanged, changedImages[slot]).value
  let slots = changedMemoryPageSlots(sparseOriginal, sparseChanged).value
  assert slots.len == 4
  for index, slot in [1'u32, 2, 63, 64]: assert uint32(slots[index]) == slot
  let equalSource = withPage(sparseOriginal, sparseImages[1]).value
  let equalSlots = changedMemoryPageSlots(sparseOriginal, equalSource).value
  assert equalSlots.len == 1 and uint32(equalSlots[0]) == 1
  var initial = MachineInfo(gas: MachineGas(7), blockCharged: true,
    registers: default(RegisterFile))
  for index in 0..<13: initial.registers[index] = RegisterValue(uint64(100+index))
  initial.registers[0] = RegisterValue(0x0123456789abcdef'u64)
  let sparseSource = captureMachine(sparseOwner, sparseOriginal, initial).value
  var reading = initial
  reading.pc = CodeAddress(6)
  var snapshots: seq[Machine] = @[]
  var controls: seq[Machine] = @[]
  var readInputs: seq[Machine] = @[]
  block lease_lifetime:
    # Retained machines remain usable after the sole reusable prepared owner and its scratch retire.
    let sparsePrepared = newPreparedProgram(sparseOwner,
      defaultPreparedLimits(GasCycleLimit(10000))).value
    let firstFresh = newPreparedProgram(sparseOwner,
      defaultPreparedLimits(GasCycleLimit(10000))).value
    let published = execute(sparseSource, ExecutionStepLimit(100), sparsePrepared)
    let firstExpected = execute(sparseSource, ExecutionStepLimit(100), firstFresh)
    assert published.error == StepError.None and firstExpected.error == StepError.None
    assert published.value.exit == StepExit.Panic
    same(published.value.machine, firstExpected.value.machine)
    literalCrossingMemory(memoryOf(published.value.machine).value, sparseImages, true)
    snapshots.add(published.value.machine)
    controls.add(firstExpected.value.machine)
    for variant in 0..<3:
      # An unpublished real store primes both physical dirty words without changing the immutable input.
      assert execute(sparseSource, ExecutionStepLimit(1), sparsePrepared).error ==
        StepError.StepLimitExceeded
      let memory = if variant == 0: sparseChanged elif variant ==
          1: sparseOriginal else: equalSource
      let source = captureMachine(sparseOwner, memory, reading).value
      let fresh = newPreparedProgram(sparseOwner, defaultPreparedLimits(GasCycleLimit(10000))).value
      let actual = execute(source, ExecutionStepLimit(100), sparsePrepared)
      let expected = execute(source, ExecutionStepLimit(100), fresh)
      assert actual.error == StepError.None and expected.error == StepError.None
      assert actual.value.exit == StepExit.Panic and actual.value.exit == expected.value.exit
      same(actual.value.machine, expected.value.machine)
      var expectedCpu = reading
      expectedCpu.pc = CodeAddress(0)
      expectedCpu.registers[1] = RegisterValue(if variant == 0: 0xe5d4c3b2a1726b64'u64
        else: 0x5c554e4740726b64'u64)
      expectedCpu.registers[2] = RegisterValue(if variant == 0: 0xa6'u64 else: 0xee'u64)
      expectedCpu.registers[3] = RegisterValue(if variant == 0: 0xb7'u64 else: 0x10'u64)
      expectedCpu.registers[4] = RegisterValue(if variant == 0: 0xc8'u64 else: 0xa3'u64)
      expectedCpu.registers[5] = RegisterValue(0xac'u64)
      assert machineInfo(actual.value.machine).value == expectedCpu, "resident incoming bytes"
      assert preparedInfo(sparsePrepared).value.memoryReuses == uint64(2*(variant+1))
      assert preparedInfo(sparsePrepared).value.retainedMemoryPayloadBytes == 65'u64*8192
      snapshots.add(actual.value.machine)
      controls.add(expected.value.machine)
      readInputs.add(source)
    var readOnly = sparseImages[1]
    readOnly.access = PageAccess.ReadOnly
    var remapped: seq[PageImage] = @[]
    for slot in 0..<sparseImages.len:
      # Keep the count while moving physical 190; a read of its former address must fault as freshly mapped.
      var image = sparseImages[slot]
      if slot == 64: image.index = PageIndex(191)
      remapped.add(image)
    let accessChanged = withPage(sparseOriginal, readOnly).value
    let mapChanged = captureMemory(remapped, PageLimit(66)).value
    let countChanged = withPage(sparseOriginal,
      PageImage(index: PageIndex(191), access: PageAccess.ReadOnly)).value
    for variant, memory in [accessChanged, mapChanged, countChanged]:
      # All map/access mismatches discard old dirty capabilities and take fresh-frame preparation.
      assert execute(sparseSource, ExecutionStepLimit(1), sparsePrepared).error ==
        StepError.StepLimitExceeded
      let before = preparedInfo(sparsePrepared).value.memoryReuses
      let source = captureMachine(sparseOwner, memory, reading).value
      let fresh = newPreparedProgram(sparseOwner, defaultPreparedLimits(GasCycleLimit(10000))).value
      let actual = execute(source, ExecutionStepLimit(100), sparsePrepared)
      let expected = execute(source, ExecutionStepLimit(100), fresh)
      assert actual.error == StepError.None and expected.error == StepError.None
      assert actual.value.exit == expected.value.exit
      if actual.value.exit == StepExit.Fault:
        # Fault metadata remains selected only after the public tagged outcome permits extraction.
        assert actual.value.faultPage == expected.value.faultPage
      if variant == 1:
        # A genuine missing physical page faults at its original address after full map mismatch fallback.
        assert actual.value.exit == StepExit.Fault
        assert actual.value.faultPage == PageAddress(190'u64*4096)
      else:
        # Read-only access remains readable and an extra mapped row does not change these guest loads.
        assert actual.value.exit == StepExit.Panic
      same(actual.value.machine, expected.value.machine)
      assert preparedInfo(sparsePrepared).value.memoryReuses == before, "map/access fallback"
      snapshots.add(actual.value.machine)
      controls.add(expected.value.machine)
  for index in 0..<snapshots.len:
    # Later reuse, local exits, fresh fallback and prepared retirement preserve every published predecessor.
    same(snapshots[index], controls[index])
  literalCrossingMemory(memoryOf(sparseSource).value, sparseImages, false)
  literalCrossingMemory(memoryOf(snapshots[0]).value, sparseImages, true)
  for variant in 0..<readInputs.len:
    # Held read inputs retain every original or explicitly changed byte after scratch retirement.
    let memory = memoryOf(readInputs[variant]).value
    assert machineInfo(readInputs[variant]).value == reading
    for slot in 0..<sparseImages.len:
      let expected = if variant == 0: changedImages[slot] else: sparseImages[slot]
      assert pageImage(memory, expected.index).value == expected

proc releaseCycle(owner: Program, original, changed: Memory) =
  ## A dropped prepared identity must retire its idle byte lease and retained source baseline together.
  let local = newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(10000))).value
  for iteration in 0..<3:
    let source = input(owner, (if iteration mod 2 == 0: original else: changed), iteration)
    assert execute(source, ExecutionStepLimit(100), local).error == StepError.None
  assert preparedInfo(local).value.memoryReuses == 2

releaseCycle(owner, original, changed)
let before = getOccupiedMem()
for cycle in 0..<1000: releaseCycle(owner, original, changed)
let after = getOccupiedMem()
assert before == after, "idle lease ARC release"
recordArcRelease("pvm_memory_reuse", 1000, before, after)
let reused = preparedInfo(prepared).value
let stats = [reused.memoryReuses, reused.retainedMemoryPayloadBytes]
assert stats[0] >= 30 and stats[1] > 0, "actual reuse hit coverage"
var disabled = defaultPreparedLimits(GasCycleLimit(10000))
disabled.retainedMemoryBytes = RetainedMemoryByteLimit(0)
let coldOnly = newPreparedProgram(owner, disabled).value
for iteration in 0..<3:
  assert execute(input(owner, original, iteration), ExecutionStepLimit(100), coldOnly).error == StepError.None
assert preparedInfo(coldOnly).value.memoryReuses == 0
assert preparedInfo(coldOnly).value.retainedMemoryPayloadBytes == 0

var exact = defaultPreparedLimits(GasCycleLimit(10000))
exact.retainedMemoryBytes = RetainedMemoryByteLimit(32768)
let bounded = newPreparedProgram(owner, exact).value
for iteration in 0..<3:
  assert execute(input(owner, original, iteration), ExecutionStepLimit(100), bounded).error == StepError.None
assert preparedInfo(bounded).value.memoryReuses == 2
assert preparedInfo(bounded).value.retainedMemoryPayloadBytes == 32768

var tooSmall = exact
tooSmall.retainedMemoryBytes = RetainedMemoryByteLimit(32767)
let unretained = newPreparedProgram(owner, tooSmall).value
assert execute(input(owner, original, 0), ExecutionStepLimit(100), unretained).error == StepError.None
assert preparedInfo(unretained).value.retainedMemoryPayloadBytes == 0

let inaccessible = withPageRange(original, PageIndex(18), PageIndex(19), PageAccess.Inaccessible,
  PageContent.Preserved).value
var retainedSourceLimit = exact
retainedSourceLimit.retainedMemoryBytes = RetainedMemoryByteLimit(24576)
let invisiblePayload = newPreparedProgram(owner, retainedSourceLimit).value
assert execute(input(owner, inaccessible, 0), ExecutionStepLimit(100), invisiblePayload).error == StepError.None
assert preparedInfo(invisiblePayload).value.retainedMemoryPayloadBytes == 0

let worker = newPreparedProgramCache()
let a = cachedPreparedProgram(worker, owner, disabled, PvmBackend.Jit)
assert a.error == PreparationError.None
let b = cachedPreparedProgram(worker, owner, exact, PvmBackend.Jit)
assert b.error == PreparationError.None
assert uint64(preparedInfo(b.value).value.limits.retainedMemoryBytes) == 32768
assert preparedCacheInfo(worker).value.preparations == 2



type
  Refusal = enum
    Refused
  Context = object
    target: Memory
    calls: int
    fail: bool

proc terminal(context: var Context, suspension: StepOutcome): HostResponse {.raises: [].} =
  ## A terminal host can select different memory without installing it into the stopped resident frame.
  inc context.calls
  let cpu = machineInfo(suspension.machine).value
  HostResponse(action: HostAction.Panic, memory: context.target, gas: cpu.gas,
      registers: cpu.registers)

proc fallible(context: var Context, suspension: StepOutcome): HostResult[Refusal] {.raises: [].} =
  if context.fail:
    inc context.calls
    return hostFailure(Refusal.Refused)
  hostSuccess[Refusal](terminal(context, suspension))


proc hostTransitions() =
  let owner = code([@[52'u8, 0, 0, 0, 1, 0], @[52'u8, 1, 0, 32, 1, 0],
    @[52'u8, 2, 255, 17, 1, 0], @[30'u8, 4, 255, 17, 1, 0, 123, 0, 0, 0],
    @[30'u8, 4, 0, 18, 1, 0, 109, 0, 0, 0], @[10'u8, 1], @[0'u8]])
  var pages: seq[PageImage] = @[]
  for physical in [16'u32, 17, 18, 31]:
    var image = PageImage(index: PageIndex(physical), access:
      (if physical == 16: PageAccess.ReadOnly else: PageAccess.ReadWrite))
    for offset in 0..<4096: image.bytes[offset] = byte(physical)
    pages.add(image)
  let original = captureMemory(pages, PageLimit(8)).value
  var changed = original
  for physical in [16'u32, 17, 18]:
    var image = pageImage(original, PageIndex(physical)).value
    for offset in 0..<4096: image.bytes[offset] = byte(physical+40)
    changed = withPage(changed, image).value

  for shape in 0..<2:
    let target = if shape == 0: changed else: withPage(changed,
      PageImage(index: PageIndex(64), access: PageAccess.ReadWrite)).value
    let prepared = newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(10000))).value
    var context = Context(target: target, calls: 0, fail: false)
    let first = executeWithHost(input(owner, original, 1), context, terminal,
      ExecutionStepLimit(100), HostCallLimit(2), prepared)
    assert first.error == StepError.None and first.value.exit == StepExit.Panic, "first terminal result"
    assert preparedInfo(prepared).value.retainedMemoryPayloadBytes == 32768, "resident baseline payload"
    var source = input(owner, memoryOf(first.value.machine).value, 10)
    for iteration in 0..<2:
      let fresh = newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(10000))).value
      var oracle = Context(target: target, calls: 0, fail: false)
      let expected = executeWithHost(source, oracle, terminal, ExecutionStepLimit(100),
          HostCallLimit(2), fresh)
      let actual = executeWithHost(source, context, terminal, ExecutionStepLimit(100),
          HostCallLimit(2), prepared)
      assert actual.error == StepError.None and expected.error == StepError.None
      same(actual.value.machine, expected.value.machine)
      let cpu = machineInfo(actual.value.machine).value
      assert uint64(cpu.registers[0]) == 56 and uint64(cpu.registers[1]) == 58
      assert uint64(cpu.registers[2]) == 57
      source = input(owner, memoryOf(actual.value.machine).value, 11+iteration)
    assert preparedInfo(prepared).value.memoryReuses == uint64(if shape == 0: 2 else: 1), "terminal reuse count"

  let reused = newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(10000))).value
  var context = Context(target: changed, calls: 0, fail: false)
  let first = executeWithHost(input(owner, original, 0), context, fallible,
    ExecutionStepLimit(100), HostCallLimit(2), reused)
  assert first.error == HostExecutionError.None
  context.fail = true
  let refused = executeWithHost(input(owner, memoryOf(first.value.machine).value, 10), context,
      fallible,
    ExecutionStepLimit(100), HostCallLimit(2), reused)
  assert refused.error == HostExecutionError.HostFailure and refused.hostError == Refusal.Refused
  context.fail = false
  let source = input(owner, changed, 100)
  let actual = executeWithHost(source, context, fallible, ExecutionStepLimit(100), HostCallLimit(2), reused)
  let fresh = newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(10000))).value
  var oracle = Context(target: changed, calls: 0, fail: false)
  let expected = executeWithHost(source, oracle, fallible, ExecutionStepLimit(100), HostCallLimit(
      2), fresh)
  assert actual.error == HostExecutionError.None and expected.error == HostExecutionError.None
  same(actual.value.machine, expected.value.machine)
  assert uint64(machineInfo(actual.value.machine).value.registers[2]) == 57
  assert preparedInfo(reused).value.memoryReuses == 2


proc argumentSuccessor(base: Memory, value: byte): Memory =
  ## Fresh argument owners exercise the public append/replacement path without an initializer template.
  let mapped = withPageRange(base, PageIndex(256), PageIndex(257), PageAccess.ReadOnly,
    PageContent.Zeroed).value
  var argument = PageImage(index: PageIndex(256), access: PageAccess.ReadOnly,
    bytes: default(array[4096, byte]))
  argument.bytes[0] = value
  withReplacedPages(mapped, [argument]).value

proc literalArgumentMemory(memory: Memory, baseCount, argumentCount: int,
    argument: byte, written: bool) =
  ## Literal complete images expose stale dirty base bytes, argument bytes and padding independently of execute.
  let layout = memoryLayout(memory).value
  assert layout.len == baseCount+argumentCount
  for slot in 0..<layout.len:
    # The sorted map has a contiguous writable base and a separate fresh read-only argument region.
    let physical = uint32(if slot < baseCount: 16+slot else: 256+slot-baseCount)
    let access = if slot < baseCount: PageAccess.ReadWrite else: PageAccess.ReadOnly
    assert layout[slot].index == PageIndex(physical) and layout[slot].access == access
    let page = pageImage(memory, PageIndex(physical)).value
    for offset in 0..<4096:
      # Expected bytes come from input literals/patterns, never another execution or mapping operation.
      var expected = 0'u8
      if slot < baseCount:
        expected = byte((slot*11+offset*3+7) mod 251)
        if written and slot == 0 and offset == 0: expected = 123
      elif slot == baseCount and offset == 0:
        expected = argument
      assert page.bytes[offset] == expected

proc appendedArgumentReuse() =
  ## A real retained-frame consumer must restore a shared dirty prefix before reading each fresh invocation.
  let argumentOwner = code([@[52'u8, 0, 0, 0, 16, 0], @[52'u8, 1, 0, 0, 1, 0],
    @[30'u8, 4, 0, 0, 1, 0, 123, 0, 0, 0], @[0'u8]])
  for baseCount in [64, 65]:
    # Both a complete prefix block and a partial old tail receive independently owned arguments.
    var pages: seq[PageImage] = @[]
    for slot in 0..<baseCount:
      var page = PageImage(index: PageIndex(uint32(16+slot)), access: PageAccess.ReadWrite,
        bytes: default(array[4096, byte]))
      for offset in 0..<4096:
        page.bytes[offset] = byte((slot*11+offset*3+7) mod 251)
      pages.add(page)
    let base = captureMemory(pages, PageLimit(uint32(baseCount+2))).value
    let retained = newPreparedProgram(argumentOwner,
      defaultPreparedLimits(GasCycleLimit(10000))).value
    var previous = default(Memory)
    var sources: seq[Machine] = @[]
    var results: seq[Machine] = @[]
    var expectedCpus: seq[MachineInfo] = @[]
    var initialCpus: seq[MachineInfo] = @[]
    for iteration, value in [13'u8, 19, 23]:
      # Same-sized argument successors retain the base but require a real one-slot memory delta.
      let memory = argumentSuccessor(base, value)
      if iteration != 0:
        let delta = changedMemoryPageSlots(previous, memory).value
        assert delta.len == 1 and uint32(delta[0]) == uint32(baseCount)
      var initial = MachineInfo(gas: MachineGas(7), blockCharged: true,
        registers: default(RegisterFile))
      for register in 0..<13:
        initial.registers[register] = RegisterValue(uint64(100+iteration*19+register))
      let source = captureMachine(argumentOwner, memory, initial).value
      let actual = execute(source, ExecutionStepLimit(4), retained)
      assert actual.error == StepError.None and actual.value.exit == StepExit.Panic
      var expectedCpu = initial
      expectedCpu.registers[0] = RegisterValue(uint64(value))
      expectedCpu.registers[1] = RegisterValue(7)
      assert machineInfo(actual.value.machine).value == expectedCpu
      assert preparedInfo(retained).value.memoryReuses == uint64(iteration)
      literalArgumentMemory(memoryOf(source).value, baseCount, 1, value, false)
      literalArgumentMemory(memoryOf(actual.value.machine).value, baseCount, 1, value, true)
      sources.add(source)
      results.add(actual.value.machine)
      expectedCpus.add(expectedCpu)
      initialCpus.add(initial)
      previous = memory
    # A changed map must still discard scratch instead of treating shared prefix blocks as complete admission.
    let fresh = argumentSuccessor(base, 31)
    let expanded = withPage(fresh, PageImage(index: PageIndex(257), access: PageAccess.ReadOnly,
      bytes: default(array[4096, byte]))).value
    assert changedMemoryPageSlots(previous, expanded).error == MachineError.InvalidRange
    var initial = MachineInfo(gas: MachineGas(7), blockCharged: true,
      registers: default(RegisterFile))
    for register in 0..<13: initial.registers[register] = RegisterValue(uint64(300+register))
    let source = captureMachine(argumentOwner, expanded, initial).value
    let fallback = execute(source, ExecutionStepLimit(4), retained)
    assert fallback.error == StepError.None and fallback.value.exit == StepExit.Panic
    initial.registers[0] = RegisterValue(31)
    initial.registers[1] = RegisterValue(7)
    assert machineInfo(fallback.value.machine).value == initial
    assert preparedInfo(retained).value.memoryReuses == 2
    literalArgumentMemory(memoryOf(fallback.value.machine).value, baseCount, 2, 31, true)
    literalArgumentMemory(expanded, baseCount, 2, 31, false)
    for iteration, value in [13'u8, 19, 23]:
      # Later dirty restoration and a cold map fallback cannot alter earlier input or result snapshots.
      assert machineInfo(results[iteration]).value == expectedCpus[iteration]
      assert machineInfo(sources[iteration]).value == initialCpus[iteration]
      literalArgumentMemory(memoryOf(sources[iteration]).value, baseCount, 1, value, false)
      literalArgumentMemory(memoryOf(results[iteration]).value, baseCount, 1, value, true)
    for page in pages:
      assert pageImage(base, page.index).value == page

hostTransitions()
appendedArgumentReuse()
echo "PVM appended argument memory reuse passed"
echo "PVM bounded memory reuse passed"
echo "ARC_RELEASE cycles=1000 unchanged"
