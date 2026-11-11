# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute one bounded pinned DOOM call from shared complete input; validate memory, CPU and output events.

import std/[assertions, syncio, envvars, monotimes]
import ../../tests/performance/pvm_invocation_scope
import ./receipt
import ../../src/pvm/[program, machine]
import ../../src/pvm/gas/[gas, plan as gas_plan]
import ../../src/pvm/step

proc cpuNanoseconds(): int64 {.importc: "pvm_sieve_cpu_nanoseconds",
    header: "pvm_sieve_clock.h".}
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
    let read = readBytes(memory, MemoryAddress(address), MemoryLength(length),
        MemoryByteLimit(1048576))
    assert read.error == MachineError.None
    assert context.outputBytes <= 4*1024*1024-5-int(length)
    context.events.add(OutputEvent(kind: byte(kind), payload: read.value))
    context.outputBytes += 5+int(length)
    if kind == 4:
      # The guest's console ABI returns the number of successfully consumed bytes.
      registers[7] = RegisterValue(length)
  HostResponse(action: HostAction.Continue, gas: cpu.gas,
      gasDeficit: GasDeficit(0),
    registers: registers, memory: memory)

proc runDoom(source: Machine, context: var HostContext,
    plan: GasPlan): StepResult {.noinline.} =
  ## Give calibrated collection one stable boundary around the real host loop and in-memory callbacks.
  executeWithHost(source, context, respond, ExecutionStepLimit(1000000000),
      HostCallLimit(4096), plan)

when defined(pvmProfileRequests):
  proc profileBegin() {.cdecl, importc: "pvm_profile_begin",
      header: "pvm_profile_scope.h".}
    ## Begin explicit diagnostic collection without borrowing guest state.
  proc profileEnd() {.cdecl, importc: "pvm_profile_end",
      header: "pvm_profile_scope.h".}
    ## Stop and dump one complete invocation before independent caller validation.

proc runPreparedDoom(source: Machine, context: var HostContext,
    prepared: PreparedProgram): StepResult {.noinline.} =
  ## Reuse only source facts and executable nodes; every public call still owns private invocation memory.
  when defined(pvmProfileRequests):
    profileBegin()
    result = executeWithHost(source, context, respond, ExecutionStepLimit(
        1000000000), HostCallLimit(4096), prepared)
    profileEnd()
  else:
    # Ordinary timing images preserve the existing wrapper without any collection markers.
    executeWithHost(source, context, respond, ExecutionStepLimit(1000000000),
        HostCallLimit(4096), prepared)

let fullInvocation = false
if fullInvocation: fullInvocationHeader()

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
let pricing = getEnv("RAGNAROK_PVM_DOOM_PRICING")
assert pricing in ["", "planned", "prepared"]
let preparedMode = pricing == "prepared"
# Resolve the optional comparison policy before any constructor or execution clock.
let requestedBackend = getEnv("RAGNAROK_PVM_BACKEND")
assert requestedBackend in ["", "jit", "interpreted"]
if fullInvocation: assert requestedBackend in ["jit", "interpreted"]
when declared(step.DefaultPvmBackend):
  var selectedBackend = DefaultPvmBackend
  if requestedBackend.len > 0:
    assert parsePvmBackend(requestedBackend, selectedBackend)
else:
  # Archived runtimes retain their original constructor and cannot honor current policy overrides.
  assert requestedBackend.len == 0
let requestedPreparation = getEnv("RAGNAROK_PVM_DOOM_PREPARATION")
assert requestedPreparation in ["", "0", "1"]
let performance = getEnv("RAGNAROK_PVM_PERFORMANCE") == "1"

let ownerStart = if fullInvocation: default(InvocationClock) else: default(InvocationClock)
var invocationRuntime = if requestedBackend == "jit":
    startInvocationRuntime() else: default(InvocationRuntime)
let coldCall = if fullInvocation: default(InvocationClock) else: default(InvocationClock)
var context = HostContext(rom: newSeq[byte](rom.len), events: @[],
    outputBytes: 0, hosts: default(array[5, uint64]))
# Deliver the checked, nonempty WAD to the host owner within the enclosing cold call.
copyInvocationInput(context.rom, rom, 0)
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
copyInvocationInput(wire, data, 152)
let decoded = decodeJamProgram(wire, CodeAddress(entry), ProgramByteLimit(
    4*1024*1024), JumpCountLimit(1048576))
assert decoded.error == ProgramError.None
let owner = decoded.value
var images = newSeq[PageImage](pages)
for page in 0..<pages:
  # Every complete source page retains its canonical index and permissions.
  let cursor = 152+wireSize+page*4101
  let permission = byte(data[cursor+4])
  assert permission in [1'u8, 2'u8]
  images[page].index = PageIndex(uint32(word(data, cursor, 4)))
  images[page].access = if permission == 1: PageAccess.ReadOnly else: PageAccess.ReadWrite
  copyInvocationInput(images[page].bytes, data, cursor+5)
let captured = captureMemory(images, PageLimit(8192))
assert captured.error == MachineError.None
let source = captureMachine(owner, captured.value, info).value
let prepareWallStart = if requestedPreparation == "1": 0'i64 else: 0'i64
let prepareStart = if requestedPreparation == "1": 0'i64 else: 0'i64
var plan = default(GasPlan)
var prepared = default(PreparedProgram)
if preparedMode:
  # Canonical owner admission is nested inside the enclosing cold call; stream work stays lazy.
  let created = when declared(step.DefaultPvmBackend):
    # The owner captures selection and prepares capabilities inside the existing constructor clock.
    newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(1000000)),
        selectedBackend, invocationRuntime)
  else:
    # Historical source snapshots preserve their original public API and engine policy.
    newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(1000000)))
  assert created.error == PreparationError.None
  prepared = created.value
  let pairMode = case getEnv("RAGNAROK_PVM_MIXED_PAIR")
    of "checked": FlatMixedPairMode.Checked
    of "byte": FlatMixedPairMode.ByteOnly
    of "paid": FlatMixedPairMode.PaidOnly
    of "both": FlatMixedPairMode.Both
    else: FlatMixedPairMode.Disabled
  assert pairMode != FlatMixedPairMode.Disabled and requestedBackend == "jit" and phase == "tick"
  setPreparedMixedPairMode(prepared, pairMode)
  echo "MIXED_PAIR_MODE,", ord(pairMode)
else:
  # Ordinary attribution and performance runs retain their existing complete-price policy.
  let created = newGasPlan(owner, GasPlanLimits(blocks: GasPlanBlockLimit(262144),
    bytes: GasPlanByteLimit(64*1024*1024), cycles: GasCycleLimit(1000000)))
  assert created.error == GasPlanError.None
  plan = created.value
var preparationCpuElapsed = 0'i64
var preparationWallElapsed = 0'i64
if requestedPreparation == "1":
  preparationCpuElapsed = 0'i64-prepareStart
  preparationWallElapsed = 0'i64-prepareWallStart
let requestedTiming = getEnv("RAGNAROK_PVM_DOOM_TIMING")
assert requestedTiming in ["", "0", "1"]
let timing = requestedTiming == "1"
let samples = 4
for sample in 0..<samples:
  # Fresh host output and invocation-local execution state preserve equal sample starts.
  let residentCall = if fullInvocation and sample != 0: default(InvocationClock) else: default(InvocationClock)
  let cpuStart = if fullInvocation: (if sample ==
      0: coldCall.cpu else: residentCall.cpu)
    elif timing: 0'i64 else: 0'i64
  let wallStart = if fullInvocation: (if sample ==
      0: coldCall.wall else: residentCall.wall)
    elif timing: 0'i64 else: 0'i64
  context.events = @[]
  context.outputBytes = 0
  let done = if preparedMode: runPreparedDoom(source, context,
      prepared) else: runDoom(source, context, plan)
  assert done.error == StepError.None and done.value.exit == StepExit.Halt
  let cpu = machineInfo(done.value.machine).value
  let wallElapsed = if timing: 0'i64-wallStart else: 0'i64
  let cpuElapsed = if timing: 0'i64-cpuStart else: 0'i64
  if sample == 0 and requestedPreparation == "1":
    echo "API_PREPARE,", (if preparedMode: "prepared" else: "planned"), ",", preparationCpuElapsed
    if performance: echo "API_PREPARE_WALL,prepared,", preparationWallElapsed
  assert uint64(cpu.pc) == 0 and cpu.blockCharged and uint64(cpu.gasDeficit) == 0
  assert uint64(cpu.gas) == word(expected, 8, 8), "doom terminal gas mismatch"
  for i in 0..<13: assert uint64(cpu.registers[i]) == word(expected, 16+i*8, 8)
  let finalMemory = memoryOf(done.value.machine).value
  let finalIndices = pageIndices(finalMemory)
  let sourceIndices = pageIndices(captured.value)
  assert finalIndices.error == MachineError.None and sourceIndices.error ==
      MachineError.None
  assert finalIndices.value.len == pages and sourceIndices.value.len == pages
  for page in 0..<pages:
    # Complete final-state comparison and source immutability validation stay outside collection.
    assert uint32(finalIndices.value[page]) == uint32(images[page].index)
    assert uint32(sourceIndices.value[page]) == uint32(images[page].index)
    let finalPage = pageImage(finalMemory, images[page].index).value
    let original = pageImage(captured.value, images[page].index).value
    assert finalPage.access == images[page].access
    assert original.access == images[page].access
    for i in 0..<4096:
      assert finalPage.bytes[i] == byte(expected[120+page*4096+i])
      assert original.bytes[i] == images[page].bytes[i]
  let originalCpu = machineInfo(source).value
  assert uint64(originalCpu.pc) == uint64(info.pc) and
      not originalCpu.blockCharged
  assert uint64(originalCpu.gas) == uint64(info.gas) and uint64(
      originalCpu.gasDeficit) == 0
  for i in 0..<13:
    # Reused calls cannot inherit a preceding invocation's registers through the immutable source.
    assert uint64(originalCpu.registers[i]) == uint64(info.registers[i])
  assert context.rom.len == rom.len
  for i in 0..<rom.len:
    # Host callbacks read the canonical WAD; no invocation may alter this retained source.
    assert context.rom[i] == byte(rom[i])
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
  receipt(prepared, invocationRuntime, "doom-" & phase, sample)
  if timing:
    # A sample is emitted only after complete CPU/memory/output validation succeeds.
    if fullInvocation and (cpuElapsed <= 0 or wallElapsed <= 0):
      # Do not discard the actual primary deltas when the unchanged clock assertion fails.
      echo "PVM_TIMING_FAILURE,1,full-invocation-v1,native,doom-", phase, ",", sample,
        ",", cpuElapsed, ",", wallElapsed
    echo "DOOM_SAMPLE,native,", phase, ",", sample, ",", cpuElapsed, ",", wallElapsed
echo "DOOM_OK,native,", phase, ",", context.outputBytes

when declared(step.DefaultPvmBackend):
  if requestedBackend.len > 0:
    # Copied cumulative diagnostics certify policy after all full-state checks, outside all clocks.
    assert preparedMode
    let policy = preparedInfo(prepared).value
    assert policy.backend == selectedBackend
    if fullInvocation: reportNativeCompilation("doom-process",
        policy.nativeCompilationMeasured, policy.nativeCompilationNs)
    let actual = if policy.nativeOperations > 0: "jit" else: "interpreted"
    echo "PVM_POLICY,1,", requestedBackend, ",", int(policy.jitBuilt), ",",
      int(policy.jitPlatformSupported), ",", int(policy.checkedFallbackEnabled),
          ",", actual, ",",
      policy.nativeFragments, ",", policy.nativeCalls, ",",
          policy.nativeOperations

when defined(pvmArmMacroReceipt):
  # Application qualification observes actual resident publication and completed macro calls.
  let macroStats = preparedArmMacroStatistics(prepared).value
  let resident = preparedArmMacroResidentActive(prepared).value
  echo "ARM_MACRO_APPLICATION,", phase, ",", int(resident), ",", macroStats[0], ",",
    macroStats[1], ",", macroStats[5], ",", macroStats[6]

when defined(pvmArm64JitOwnerReceipt):
  # Genuine host callbacks and immutable publication finish before copied cache diagnostics are emitted.
  if fullInvocation:
    reportInvocationOwner(prepared, phase)
  else:
    let native = preparedArmStatistics(prepared).value
    echo "ARM_OWNER,", phase, ",", native[0], ",", native[1], ",", native[2], ",",
      native[3], ",", native[4], ",", native[5], ",", native[6]

if fullInvocation:
  prepared = default(PreparedProgram)
  if requestedBackend == "jit":
    closeInvocationRuntime(invocationRuntime, "doom-process", ownerStart)
  else:
    finishInterpretedOwner("doom-process", ownerStart)

when defined(pvmMixedLoopWitness) and declared(preparedPrimaryNativeStatistics):
  if requestedBackend == "jit" and phase == "tick":
    # Keep the existing prepared owner and enter the original mixed block directly.
    const address = 65536'u64
    const absolute = 17470376'u64
    var readPage = PageImage(index: PageIndex(absolute div 4096), access: PageAccess.ReadOnly)
    readPage.bytes[int(absolute mod 4096)+2] = 1
    readPage.bytes[int((absolute+8) mod 4096)+2] = 1
    let writePage = PageImage(index: PageIndex(address div 4096), access: PageAccess.ReadWrite)
    let memory = captureMemory([writePage, readPage], PageLimit(2))
    assert memory.error == MachineError.None
    let price = blockGas(owner, CodeAddress(469077), GasCycleLimit(1000000))
    assert price.error == GasError.None
    echo "MIXED_PUBLIC_BEGIN"
    for funded in 2'u64..3'u64:
      var isolated = MachineInfo(pc: CodeAddress(469077), gas: MachineGas(funded*uint64(price.value)))
      isolated.registers[3] = RegisterValue(address+funded+1)
      isolated.registers[11] = RegisterValue(address)
      let input = captureMachine(owner, memory.value, isolated)
      assert input.error == MachineError.None
      let before = preparedInfo(prepared).value
      let primary = preparedPrimaryNativeStatistics(prepared)
      let outcome = execute(input.value, ExecutionStepLimit(8192), prepared)
      assert outcome.error == StepError.None and outcome.value.exit == StepExit.OutOfGas
      assert outcome.value.backend == PvmBackend.Jit
      let after = preparedInfo(prepared).value
      let attempts = 15*(funded-1)
      let backedges = funded-2
      assert preparedPrimaryNativeStatistics(prepared) == primary
      assert after.nativeCalls == before.nativeCalls+1 and after.nativeOperations ==
          before.nativeOperations+attempts
      assert after.nativeBranchCalls == before.nativeBranchCalls+1
      assert after.nativeHeaderCalls == before.nativeHeaderCalls+backedges
      assert after.nativeFragments == before.nativeFragments and after.nativeCodeBytes ==
          before.nativeCodeBytes
      let final = machineInfo(outcome.value.machine).value
      assert final.registers[11] == RegisterValue(address+funded) and uint64(final.gas) == 0
      echo "MIXED_PUBLIC_AUX_ONLY,1,", attempts, ",0,1,", backedges

if requestedBackend == "jit": assert invocationRuntime.close()
