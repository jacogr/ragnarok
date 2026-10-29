# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Run a bounded continuing DOOM sequence through the real CLI-selected prepared backend and host API.
import std/[assertions, syncio, envvars, cmdline]
import ../../src/app/options
import ../../src/pvm/[program, machine, gas, gas_plan, step, artifact]


type
  OutputEvent = object ## Captured payload ownership moves into one bounded host record without serialization.
    kind: byte
    payload: seq[byte]
  HostContext = object ## Host state owns immutable WAD/event bytes; no mutable guest storage escapes.
    rom: seq[byte]
    events: seq[OutputEvent]
    outputBytes: int
    hosts: array[5, uint64]
    hostTrace: string

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
  context.hostTrace.add($kind & "," & $uint64(registers[7]) & "," &
    $uint64(registers[8]) & "," & $uint64(registers[9]) & "\n")
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

# The production CLI parser owns artifact selection and backend spelling/defaults; hosts remain test-owned.
var arguments: seq[string] = @[]
for index in 1..paramCount(): arguments.add(paramStr(index))
var selected = default(Options)
var diagnostic = ""
assert parseOptions(arguments, selected, diagnostic), diagnostic
let requestedCohort = getEnv("PVM_DOOM_BACKENDS")
assert requestedCohort in ["", "polkavm-interpreted,interpreted",
    "polkavm-interpreted,jit,compiled"],
    "unsupported DOOM comparison cohort"
let interpretedCohort = requestedCohort == "polkavm-interpreted,interpreted"
let eagerCohort = requestedCohort == "polkavm-interpreted,jit,compiled"
assert selected.pvmBackend in [PvmBackend.Jit, PvmBackend.PolkaInterpreted] or
    (interpretedCohort and selected.pvmBackend == PvmBackend.Interpreted) or
        (eagerCohort and selected.pvmBackend == PvmBackend.Compiled),
        "unsupported DOOM comparison backend"
let requestedCalls = getEnv("RAGNAROK_DOOM_BACKEND_CALLS")
assert requestedCalls in ["1", "2"]
let callCount = if requestedCalls == "1": 1 else: 2
let output = getEnv("RAGNAROK_DOOM_BACKEND_OUTPUT")
assert output.len > 0
if getEnv("RAGNAROK_DOOM_BACKEND_ASSERT") == "1":
  # CI must demonstrate that native assertions survive the checked release profile.
  assert false, "DOOM backend assertion control"
let folder = getEnv("RAGNAROK_PVM_DOOM_INPUT")
let phase = "tick"
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
let entryPc = word(data, 12, 4)
let pages = int(word(data, 16, 4))
assert wireSize > 0 and wireSize <= 4*1024*1024 and pages > 0 and pages <= 8192
assert data.len == 152+wireSize+pages*4101 and expected.len == 120+pages*4096
assert rom.len == 4196020 and events.len <= 4*1024*1024
var context = HostContext(rom: newSeq[byte](rom.len), events: @[], outputBytes: 0, hostTrace: "",
    hosts: default(array[5, uint64]))
for i in 0..<rom.len:
  # Copy host-owned immutable input once, outside every collected execution.
  context.rom[i] = byte(rom[i])
for i in 0..<5:
  # This blob has exactly five distinct import slots; malformed maps cannot select another host ABI.
  context.hosts[i] = word(data, 20+i*4, 4)
  assert context.hosts[i] < 5
  for j in 0..<i: assert context.hosts[i] != context.hosts[j]
var info = MachineInfo(pc: CodeAddress(entryPc), gas: MachineGas(word(data, 40, 8)),
  registers: default(RegisterFile), blockCharged: false)
assert uint64(info.gas) == 1000000000000'u64
for i in 0..<13: info.registers[i] = RegisterValue(word(data, 48+i*8, 8))
assert uint64(info.registers[0]) == 0xffff0000'u64
var wire = newSeq[byte](wireSize)
for i in 0..<wireSize: wire[i] = byte(data[152+i])
let decoded = decodeJamProgram(wire, CodeAddress(entryPc), ProgramByteLimit(4*1024*1024),
    JumpCountLimit(1048576))
assert decoded.error == ProgramError.None
let loaded = loadArtifact(selected.pvmCodePath)
assert loaded.error == ArtifactError.None, "DOOM artifact loading " & $loaded.error
let guestArtifact = loaded.value
let owner = programOf(guestArtifact)
assert programBytes(owner).value == wire, "DOOM artifact code differs from warmed snapshot"
let exported = guestArtifact.entry(selected.pvmEntry)
assert exported.error == ArtifactError.None and uint64(exported.value) == entryPc,
    "DOOM artifact export differs from warmed snapshot"
let imports = importSymbols(guestArtifact)
assert imports.len == 5
let hostNames = ["ext_output_audio", "ext_output_video", "ext_rom_read", "ext_rom_size", "ext_stdout"]
for kind in 0..<5:
  assert imports[int(context.hosts[kind])] == hostNames[kind], "DOOM artifact import mapping differs"
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

proc appendWord(data: var string, value: uint64, width: int) =
  ## Serialized observation words are bounded and canonical; comparison hashes the actual emitted bytes.
  assert width in 1..8
  for octet in 0..<width: data.add(char((value shr (8*octet)) and 255))

proc eagerSnapshot(policy: PreparedInfo): string =
  ## Copied construction excludes live calls/operations and includes CI-only attempted compiler admission.
  let compilation = policy.compilation
  var passes = 0'u64
  when defined(pvmSourceSealingReceipt): passes = compilation.compilationPasses
  $int(compilation.sealed) & "," & $policy.streamNodes & "," & $policy.preparationUnits & "," &
    $policy.nativeFragments & "," & $policy.nativeCodeBytes & "," & $policy.nativeCompilationNs & "," &
    $compilation.sourceEntries & "," & $compilation.nativeEntries & "," &
    $compilation.checkedEntries & "," & $compilation.capacityDeferred & "," & $passes

let made = newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(1000000)),
    selected.pvmBackend)
if made.error != PreparationError.None:
  # Missing bridge/platform capability is an explicit failed process, never an omitted backend pass.
  echo "DOOM_BACKEND_UNAVAILABLE,", selected.pvmBackend, ",", made.error
  quit 2
let prepared = made.value
var construction = ""
var compilation = default(PreparedCompilationInfo)
if selected.pvmBackend == PvmBackend.Compiled:
  # A nominal unavailable/all-fallback constructor cannot substitute for actual eager-native qualification.
  let before = preparedInfo(prepared).value
  assert eagerCohort and before.backend == PvmBackend.Compiled and before.compilation.sealed
  assert before.compilation.nativeEntries > 0 and before.nativeFragments > 0 and
      before.nativeCodeBytes > 0
  assert before.nativeCalls == 0 and before.nativeOperations == 0
  when defined(pvmSourceSealingReceipt):
    assert before.compilation.compilationPasses > 0, "DOOM eager compiler-attempt witness active"
  construction = eagerSnapshot(before)
  compilation = before.compilation
  echo "DOOM_EAGER_PREPARED,", construction
var current = source
for call in 0..<callCount:
  # Restore the initial snapshot once; every later call starts with the previous guest memory, not a fixture reset.
  context.events = @[]
  context.outputBytes = 0
  context.hostTrace = ""
  let done = executeWithHost(current, context, respond, ExecutionStepLimit(1000000000),
      HostCallLimit(4096), prepared)
  assert done.error == StepError.None, "DOOM backend execution " & $done.error
  assert done.value.exit == StepExit.Halt
  let cpu = machineInfo(done.value.machine).value
  let finalMemory = memoryOf(done.value.machine).value
  assert uint64(cpu.pc) == 0 and cpu.blockCharged and uint64(cpu.gasDeficit) == 0
  assert uint32(memoryPageCount(finalMemory).value) == uint32(pages)
  var snapshot = ""
  appendWord(snapshot, uint64(cpu.pc), 8)
  appendWord(snapshot, uint64(cpu.gas), 8)
  appendWord(snapshot, uint64(cpu.gasDeficit), 8)
  appendWord(snapshot, uint64(int(cpu.blockCharged)), 1)
  for index in 0..<13: appendWord(snapshot, uint64(cpu.registers[index]), 8)
  if call == 0:
    # The first shared-adapter call also agrees with the independently prepared complete upstream oracle.
    assert uint64(cpu.gas) == word(expected, 8, 8), "DOOM upstream gas mismatch"
    for index in 0..<13: assert uint64(cpu.registers[index]) == word(expected, 16+index*8, 8)
  for page in 0..<pages:
    # Hash input includes every page, its canonical address and permissions; no framebuffer-only result can pass.
    let actual = pageImage(finalMemory, images[page].index).value
    let unchanged = pageImage(captured.value, images[page].index).value
    assert actual.access == images[page].access
    appendWord(snapshot, uint64(uint32(actual.index)), 4)
    appendWord(snapshot, uint64(ord(actual.access)), 1)
    for at in 0..<4096:
      snapshot.add(char(actual.bytes[at]))
      assert unchanged.bytes[at] == images[page].bytes[at], "DOOM source snapshot mutated"
      if call == 0: assert actual.bytes[at] == byte(expected[120+page*4096+at]), "DOOM upstream state mismatch"
  var eventBytes = ""
  for event in context.events:
    # Exact host event framing is retained transiently; orchestration publishes only bounded hashes and diagnostics.
    eventBytes.add(char(event.kind))
    appendWord(eventBytes, uint64(event.payload.len), 4)
    for octet in event.payload: eventBytes.add(char(octet))
  if call == 0: assert eventBytes == events, "DOOM upstream ordered events mismatch"
  let policy = preparedInfo(prepared).value
  assert policy.backend == selected.pvmBackend
  if selected.pvmBackend == PvmBackend.Interpreted:
    # The same native-enabled image must honor the explicit opt-out on every continuing call.
    assert interpretedCohort and done.value.backend == PvmBackend.Interpreted
    assert policy.jitBuilt and policy.jitPlatformSupported
    assert policy.nativeFragments == 0 and policy.nativeCalls == 0 and policy.nativeOperations == 0
  echo "DOOM_CALL,", call, ",", selected.pvmBackend, ",", done.value.backend, ",", uint64(cpu.gas),
    ",", policy.nativeFragments, ",", policy.nativeCalls, ",", policy.nativeOperations,
    ",", int(policy.jitBuilt), ",", int(policy.jitPlatformSupported)
  if selected.pvmBackend == PvmBackend.Compiled:
    # Every suspension/repair returns the same sealed owner; only genuine live native execution may advance.
    let reused = eagerSnapshot(policy)
    assert reused == construction and policy.compilation == compilation,
        "DOOM eager construction/publication changed after execution"
    echo "DOOM_EAGER_REUSED,", call, ",", reused
  try:
    # Any incomplete write fails the process; raw state/pixels are not uploaded as CI artifacts.
    writeFile(output & "/call-" & $call & ".state", snapshot)
    writeFile(output & "/call-" & $call & ".events", eventBytes)
    writeFile(output & "/call-" & $call & ".hosts", context.hostTrace)
  except:
    quit 2
  current = captureMachine(owner, finalMemory, info).value
stdout.writeLine("DOOM_SEQUENCE_OK," & $selected.pvmBackend & "," & $callCount)
