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


hostTransitions()
echo "PVM bounded memory reuse passed"
echo "ARC_RELEASE cycles=1000 unchanged"
