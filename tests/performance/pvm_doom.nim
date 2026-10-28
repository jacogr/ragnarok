# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute one bounded pinned DOOM call from shared complete input; validate memory, CPU and output events.
import std/[assertions, syncio, envvars, monotimes]
import ../../src/pvm/[program, machine, gas, gas_plan, step]

proc cpuNanoseconds(): int64 {.importc: "pvm_sieve_cpu_nanoseconds", header: "pvm_sieve_clock.h".}
  ## Reuse the checked OS process clock only for explicitly enabled CI timing runs.

type
  OutputEvent = object ## Captured payload ownership moves into one bounded host record without serialization.
    kind: byte
    payload: seq[byte]
  HostContext = object ## Host state owns immutable WAD/event bytes; no mutable guest storage escapes.
    rom: seq[byte]
    events: seq[OutputEvent]
    outputBytes: int
    hosts: array[5, uint64]

proc word(data: string, at, width: int): uint64 =
  ## Reject truncated independent fixture fields before decoding their little-endian bytes.
  assert width in 1..8 and at >= 0 and at <= data.len-width
  result = 0
  for i in 0..<width:
    # Independent framing does not call the production operand decoder.
    result = result or (uint64(byte(data[at+i])) shl (8*i))

proc respond(context: var HostContext, suspension: StepOutcome): HostResponse {.raises: [].} =
  ## Apply exactly the pinned example's imports, retaining checked public memory operations.
  let cpu = machineInfo(suspension.machine).value
  var registers = cpu.registers
  var memory = memoryOf(suspension.machine).value
  var kind = -1
  for i in 0..<5:
    # An immutable ID map binds the linked guest's actual import numbering to one host behavior.
    if context.hosts[i] == uint64(suspension.hostCall): kind = i
  assert kind >= 0
  let address = uint64(registers[7])
  let b = uint64(registers[8])
  let c = uint64(registers[9])
  assert address <= 0xffffffff'u64
  case kind
  of 2:
    # Validate the entire immutable ROM range before narrowing or creating an open-array view.
    assert b <= uint64(context.rom.len) and c <= uint64(context.rom.len)-b
    if c > 0:
      let written = writeBytes(memory, MemoryAddress(address),
        context.rom.toOpenArray(int(b), int(b+c)-1), MemoryByteLimit(8*1024*1024))
      assert written.error == MachineError.None
      memory = written.value
  of 3:
    # The WAD's fixed size is the only ROM-size return value.
    registers[7] = RegisterValue(uint64(context.rom.len))
  else:
    # Audio/video/stdout payloads have the same framing and extent checks in both embeddings.
    var length = b
    if kind == 0:
      assert b <= 262144
      length = b*4
    elif kind == 1:
      assert b == 640 and c == 400
      length = 640'u64*400*4
    else:
      assert kind == 4
    assert length <= 1048576
    let read = readBytes(memory, MemoryAddress(address), MemoryLength(length), MemoryByteLimit(1048576))
    assert read.error == MachineError.None
    assert context.outputBytes <= 4*1024*1024-5-int(length)
    context.events.add(OutputEvent(kind: byte(kind), payload: read.value))
    context.outputBytes += 5+int(length)
    if kind == 4:
      # The guest's console ABI returns the number of successfully consumed bytes.
      registers[7] = RegisterValue(length)
  HostResponse(action: HostAction.Continue, gas: cpu.gas, gasDeficit: GasDeficit(0),
    registers: registers, memory: memory)

proc runDoom(source: Machine, context: var HostContext, plan: GasPlan): StepResult {.noinline.} =
  ## Give calibrated collection one stable boundary around the real host loop and in-memory callbacks.
  executeWithHost(source, context, respond, ExecutionStepLimit(1000000000), HostCallLimit(4096), plan)

proc runPreparedDoom(source: Machine, context: var HostContext,
    prepared: PreparedProgram): StepResult {.noinline.} =
  ## Reuse only source facts and executable nodes; every public call still owns private invocation memory.
  executeWithHost(source, context, respond, ExecutionStepLimit(1000000000), HostCallLimit(4096), prepared)

if getEnv("RAGNAROK_PVM_DOOM_ASSERT") == "1":
  # Refusal controls prove assertions remain present in this optimized driver.
  assert false, "doom native assertion control"
let folder = getEnv("RAGNAROK_PVM_DOOM_INPUT")
let phase = getEnv("RAGNAROK_PVM_DOOM_PHASE")
assert phase in ["init", "tick"]
var data = ""
var expected = ""
var events = ""
var rom = ""
try:
  # File failures cannot produce a successful correctness/profile record.
  data = readFile(folder & "/" & phase & ".input")
  expected = readFile(folder & "/" & phase & ".expected")
  events = readFile(folder & "/" & phase & ".events")
  rom = readFile(getEnv("RAGNAROK_PVM_DOOM_ROM"))
except:
  quit 2
assert data.len >= 152 and data[0..7] == "PVMDOM01"
assert expected.len >= 120 and expected[0..7] == "PVMDOME1"
let wireSize = int(word(data, 8, 4))
let entry = word(data, 12, 4)
let pages = int(word(data, 16, 4))
assert wireSize > 0 and wireSize <= 4*1024*1024 and pages > 0 and pages <= 8192
assert data.len == 152+wireSize+pages*4101 and expected.len == 120+pages*4096
assert rom.len == 4196020 and events.len <= 4*1024*1024
var context = HostContext(rom: newSeq[byte](rom.len), events: @[], outputBytes: 0, hosts: default(
    array[5, uint64]))
for i in 0..<rom.len:
  # Copy host-owned immutable input once, outside every collected execution.
  context.rom[i] = byte(rom[i])
for i in 0..<5:
  # This blob has exactly five distinct import slots; malformed maps cannot select another host ABI.
  context.hosts[i] = word(data, 20+i*4, 4)
  assert context.hosts[i] < 5
  for j in 0..<i: assert context.hosts[i] != context.hosts[j]
var info = MachineInfo(pc: CodeAddress(entry), gas: MachineGas(word(data, 40, 8)),
  registers: default(RegisterFile), blockCharged: false)
assert uint64(info.gas) == 1000000000000'u64
for i in 0..<13: info.registers[i] = RegisterValue(word(data, 48+i*8, 8))
assert uint64(info.registers[0]) == 0xffff0000'u64
var wire = newSeq[byte](wireSize)
for i in 0..<wireSize: wire[i] = byte(data[152+i])
let decoded = decodeJamProgram(wire, CodeAddress(entry), ProgramByteLimit(4*1024*1024),
    JumpCountLimit(1048576))
assert decoded.error == ProgramError.None
let owner = decoded.value
var images: seq[PageImage] = @[]
for page in 0..<pages:
  # Every complete source page retains its canonical index and permissions.
  let cursor = 152+wireSize+page*4101
  let permission = byte(data[cursor+4])
  assert permission in [1'u8, 2'u8]
  var image = PageImage(index: PageIndex(uint32(word(data, cursor, 4))),
    access: (if permission == 1: PageAccess.ReadOnly else: PageAccess.ReadWrite),
    bytes: default(array[4096, byte]))
  for i in 0..<4096: image.bytes[i] = byte(data[cursor+5+i])
  images.add(image)
let captured = captureMemory(images, PageLimit(8192))
assert captured.error == MachineError.None
let source = captureMachine(owner, captured.value, info).value
let pricing = getEnv("RAGNAROK_PVM_DOOM_PRICING")
assert pricing in ["", "planned", "prepared"]
let preparedMode = pricing == "prepared"
let requestedPreparation = getEnv("RAGNAROK_PVM_DOOM_PREPARATION")
assert requestedPreparation in ["", "0", "1"]
let prepareStart = if requestedPreparation == "1": cpuNanoseconds() else: 0'i64
var plan = default(GasPlan)
var prepared = default(PreparedProgram)
if preparedMode:
  # The explicit reusable owner is admitted outside calls; sample zero retains its cold stream preparation.
  let created = newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(1000000)))
  assert created.error == PreparationError.None
  prepared = created.value
else:
  # Ordinary attribution and performance runs retain their existing complete-price policy.
  let created = newGasPlan(owner, GasPlanLimits(blocks: GasPlanBlockLimit(262144),
    bytes: GasPlanByteLimit(64*1024*1024), cycles: GasCycleLimit(1000000)))
  assert created.error == GasPlanError.None
  plan = created.value
if requestedPreparation == "1":
  # Only the explicit lifecycle comparison accepts this constructor record; ordinary reports stay unchanged.
  echo "API_PREPARE,", (if preparedMode: "prepared" else: "planned"), ",", cpuNanoseconds()-prepareStart
let requestedTiming = getEnv("RAGNAROK_PVM_DOOM_TIMING")
assert requestedTiming in ["", "0", "1"]
let timing = requestedTiming == "1"
let samples = if timing: 13 else: 1
for sample in 0..<samples:
  # Fresh host output and invocation-local execution state preserve equal sample starts.
  context.events = @[]
  context.outputBytes = 0
  let cpuStart = if timing: cpuNanoseconds() else: 0'i64
  let wallStart = if timing: getMonoTime().ticks else: 0'i64
  let done = if preparedMode: runPreparedDoom(source, context, prepared) else: runDoom(source,
      context, plan)
  let wallElapsed = if timing: getMonoTime().ticks-wallStart else: 0'i64
  let cpuElapsed = if timing: cpuNanoseconds()-cpuStart else: 0'i64
  assert done.error == StepError.None and done.value.exit == StepExit.Halt
  let cpu = machineInfo(done.value.machine).value
  assert uint64(cpu.pc) == 0 and cpu.blockCharged and uint64(cpu.gasDeficit) == 0
  assert uint64(cpu.gas) == word(expected, 8, 8), "doom terminal gas mismatch"
  for i in 0..<13: assert uint64(cpu.registers[i]) == word(expected, 16+i*8, 8)
  let finalMemory = memoryOf(done.value.machine).value
  for page in 0..<pages:
    # Complete final-state comparison and source immutability validation stay outside collection.
    let finalPage = pageImage(finalMemory, images[page].index).value
    let original = pageImage(captured.value, images[page].index).value
    assert finalPage.access == images[page].access
    for i in 0..<4096:
      assert finalPage.bytes[i] == byte(expected[120+page*4096+i])
      assert original.bytes[i] == images[page].bytes[i]
  assert context.outputBytes == events.len
  var cursor = 0
  for event in context.events:
    # Serialization comparison remains outside collection and both clocks; payload bytes were copied only once.
    assert cursor <= events.len-5
    assert event.kind == byte(events[cursor]), "doom event payload mismatch"
    assert uint64(event.payload.len) == word(events, cursor+1, 4), "doom event payload mismatch"
    cursor += 5
    assert event.payload.len <= events.len-cursor
    for i in 0..<event.payload.len:
      assert event.payload[i] == byte(events[cursor+i]), "doom event payload mismatch"
    cursor += event.payload.len
  assert cursor == events.len
  if timing:
    # A sample is emitted only after complete CPU/memory/output validation succeeds.
    assert cpuElapsed > 0 and wallElapsed > 0
    echo "DOOM_SAMPLE,native,", phase, ",", sample, ",", cpuElapsed, ",", wallElapsed
echo "DOOM_OK,native,", phase, ",", context.outputBytes

when defined(pvmArm64JitOwnerReceipt):
  # Genuine host callbacks and immutable publication finish before copied cache diagnostics are emitted.
  let native = preparedArmStatistics(prepared).value
  echo "ARM_OWNER,", phase, ",", native[0], ",", native[1], ",", native[2], ",",
    native[3], ",", native[4], ",", native[5], ",", native[6]
