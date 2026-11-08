# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute frozen checked upstream guests supplied to PolkaVM; compare complete reference outputs.

import std/[assertions, syncio, monotimes, envvars]
import ./pvm_invocation_scope
import ../../src/pvm/[artifact, program, machine]
import ../../src/pvm/gas/[gas, plan as gas_plan, memo as gas_memo]
import ../../src/pvm/step as reference

type GuestKind {.pure.} = enum ## One immutable process selection binds the frozen guest to an independent expected result.
  Sieve, Minimal, Memset, Pinky

proc selectedGuest(value: string): GuestKind =
  ## Keep the original default and reject unknown family labels before any timing.
  case value
  of "", "sieve": GuestKind.Sieve # Existing sieve callers retain their original protocol.
  of "minimal": GuestKind.Minimal # Indirect calls retain a deterministic counter result.
  of "memset": GuestKind.Memset # Memory fill retains byte zero and checks the remaining extent.
  of "pinky": GuestKind.Pinky # One rendered frame from the shared initialized NES snapshot.
  else:
    assert false, "unknown checked guest family"
    GuestKind.Sieve

when defined(pvmProfileRequests):
  proc profileBegin() {.cdecl, importc: "pvm_profile_begin",
      header: "pvm_profile_scope.h".}
    ## Begin explicit diagnostic collection without borrowing guest state.
  proc profileEnd() {.cdecl, importc: "pvm_profile_end",
      header: "pvm_profile_scope.h".}
    ## Stop and dump one complete invocation before independent caller validation.

proc runPreparedKernel(source: Machine, prepared: reference.PreparedProgram): reference.StepResult {.noinline.} =
  ## One public call is a stable external profiler scope; setup and complete-state validation stay outside it.
  when defined(pvmProfileRequests):
    profileBegin()
    result = reference.execute(source, reference.ExecutionStepLimit(1000000000), prepared)
    profileEnd()
  else:
    # Ordinary timing images preserve the existing wrapper without any collection markers.
    reference.execute(source, reference.ExecutionStepLimit(1000000000), prepared)

proc cpuNanoseconds(): int64 {.importc: "pvm_sieve_cpu_nanoseconds",
    header: "pvm_sieve_clock.h".}
  ## Record CPU time alongside the elapsed metric also emitted by the reference harness.

proc word(data: string, at, width: int): uint64 =
  ## Decode fixed-width fields only within the independently framed fixture's extent.
  assert at >= 0 and width >= 1 and width <= 8 and at <= data.len - width
  result = 0
  for i in 0..<width: result = result or (uint64(byte(data[at + i])) shl (8 * i))

proc count(guest: GuestKind, limit: uint64): uint64 =
  ## Select independent expectations without reading mutable process configuration during execution.
  if guest == GuestKind.Pinky:
    assert limit == 1
    return 1 # The checked guest returns only after initialization and framebuffer conversion complete.
  if guest != GuestKind.Sieve:
    assert limit in [1000'u64, 100000'u64]
    if guest == GuestKind.Minimal: return 2*limit + limit mod 2
    else: return limit-1

  ## Known prime counts are independent of the two timed interpreters.
  case limit
  of 100: 25'u64
  of 1000: 168'u64
  of 10000: 1229'u64
  of 100000: 9592'u64
  of 1000000: 78498'u64
  of 10000000: 664579'u64
  else:
    assert false
    0'u64

proc checkMemory(memory: Memory, indices: seq[PageIndex], access: seq[
    PageAccess], expected: string, offset: int,
    diagnostic: string = "pvm sieve terminal memory mismatch"): void =
  ## Compare every initialized/mapped byte; a matching prime count alone is insufficient.
  assert expected.len == offset + indices.len * 4096
  for page in 0..<indices.len:
    let image = pageImage(memory, indices[page]).value
    assert image.access == access[page]
    for i in 0..<4096: assert image.bytes[i] == byte(expected[offset + page *
        4096 + i]), diagnostic

proc check(machine: Machine, cpu: MachineInfo, indices: seq[PageIndex], access: seq[PageAccess],
    expected: string, limit: uint64, guest: GuestKind) =
  ## Validate terminal CPU state, exact gas, all registers and all mapped memory outside timing.
  assert uint64(cpu.pc) == 0 and cpu.blockCharged and uint64(cpu.gasDeficit) == 0
  assert uint64(cpu.gas) == word(expected, 8, 8), "pvm sieve native terminal gas mismatch"
  for i in 0..<13: assert uint64(cpu.registers[i]) == word(expected, 16 + i * 8, 8)
  assert uint64(cpu.registers[7]) == count(guest, limit)
  checkMemory(memoryOf(machine).value, indices, access, expected, 120)

let guest = selectedGuest(getEnv("RAGNAROK_PVM_GUEST"))
let fullInvocation = getEnv("RAGNAROK_PVM_PERFORMANCE") == "1"
if fullInvocation: fullInvocationHeader()

if getEnv("RAGNAROK_PVM_SIEVE_ASSERT_PROBE") == "1":
  assert false, "pvm sieve native assertion control"
var data = ""
var expected = ""
var artifactData = ""
let artifactPath = getEnv("RAGNAROK_PVM_SIEVE_ARTIFACT")
let artifactAdmission = artifactPath.len > 0
if artifactAdmission:
  # Canonical ordinary guests admit their compact container; initialized Pinky retains its snapshot.
  assert fullInvocation and guest != GuestKind.Pinky
try:
  data = readFile(getEnv("RAGNAROK_PVM_SIEVE_INPUT"))
  expected = readFile(getEnv("RAGNAROK_PVM_SIEVE_EXPECTED"))
  if artifactAdmission:
    artifactData = readFile(artifactPath) # Read caller bytes before timing, as in the Rust driver.
except:
  quit 2
assert data.len >= 136 and data[0..7] == "PVMSIV01"
assert expected.len >= 120 and expected[0..7] == "PVMSIE01"
let wireSize = int(word(data, 8, 4))
let entry = word(data, 12, 4)
let limit = word(data, 16, 4)
discard count(guest, limit) # Reject a foreign family/size before an expensive execution or policy allocation.
let pageCount = int(word(data, 20, 4))
assert wireSize > 0 and wireSize <= 4 * 1024 * 1024 and pageCount > 0 and
    pageCount <= 4096
assert data.len == 136 + wireSize + pageCount * 4101
var info = MachineInfo(pc: CodeAddress(entry), gas: MachineGas(word(data, 24, 8)),
  registers: default(RegisterFile), blockCharged: false)
for i in 0..<13: info.registers[i] = RegisterValue(word(data, 32 + i * 8, 8))
let pricing = getEnv("RAGNAROK_PVM_PRICING")
assert pricing in ["", "dynamic", "planned", "memo", "prepared"]
let preparedMode = pricing == "prepared"
# Resolve the optional comparison policy before any constructor or execution clock.
let requestedBackend = getEnv("RAGNAROK_PVM_BACKEND")
assert requestedBackend in ["", "jit", "interpreted"]
if fullInvocation: assert requestedBackend in ["jit", "interpreted"]
when declared(reference.DefaultPvmBackend):
  var selectedBackend = reference.DefaultPvmBackend
  if requestedBackend.len > 0:
    assert reference.parsePvmBackend(requestedBackend, selectedBackend)
else:
  # Archived runtimes retain their original constructor and cannot honor current policy overrides.
  assert requestedBackend.len == 0
let clocked = getEnv("RAGNAROK_PVM_SIEVE_CLOCK") != "0"
let plannedMode = pricing == "planned"
let memoMode = pricing == "memo"
if guest != GuestKind.Sieve:
  # Additional families require a protocol witness before policy metadata or samples.
  echo "GUEST,", getEnv("RAGNAROK_PVM_GUEST")
let requestedSamples = getEnv("RAGNAROK_PVM_SIEVE_SAMPLES")
assert requestedSamples in ["1", "4", "13"]
# Four calls support an isolated post-three-warmup counter dump; ordinary timings retain thirteen.
let samples = if requestedSamples == "1": 1 elif requestedSamples ==
    "4": 4 else: 13
# Independent source oracles use frozen input bytes, without constructing any code or memory owner.
var indices: seq[PageIndex] = @[]
var access: seq[PageAccess] = @[]
var originalBytes = ""
for page in 0..<pageCount:
  let at = 136 + wireSize + page*4101
  let permission = byte(data[at + 4])
  assert permission in [1'u8, 2'u8]
  indices.add(PageIndex(uint32(word(data, at, 4))))
  access.add(if permission == 1: PageAccess.ReadOnly else: PageAccess.ReadWrite)
  originalBytes.add(data[at+5..<at+4101])
let coldCall = if fullInvocation: beginInvocation() else: default(
    InvocationClock)
var invocationRuntime = if fullInvocation and requestedBackend == "jit": startInvocationRuntime(
    ) else: default(InvocationRuntime)
var owner = default(Program)
var memory = default(Memory)
if artifactAdmission:
  # Owned byte admission, program validation and initial memory capture remain inside the cold clock.
  var limits = defaultArtifactLimits()
  limits.pages = uint32(pageCount)
  assert uint64(artifactData.len) <= limits.bytes, "sieve artifact byte limit"
  var raw = newSeq[byte](artifactData.len)
  if raw.len > 0:
    copyInvocationInput(raw, artifactData, 0) # An empty container reaches the production format refusal.
  let decoded = decodeArtifact(raw, limits)
  assert decoded.error == ArtifactError.None, "sieve artifact decoding"
  let admitted = decoded.value
  let selected = artifact.entry(admitted, "run_checked")
  assert selected.error == ArtifactError.None, "sieve artifact export"
  assert uint64(selected.value) == entry, "sieve artifact entry mismatch"
  owner = programOf(admitted)
  memory = memoryOf(admitted)
else:
  # Initialized snapshots and historical execution-only callers retain their complete byte input.
  var wire = newSeq[byte](wireSize)
  copyInvocationInput(wire, data, 136)
  let decoded = decodeJamProgram(wire, CodeAddress(entry), ProgramByteLimit(4 *
      1024 * 1024), JumpCountLimit(1024 * 1024))
  assert decoded.error == ProgramError.None, "sieve program decoding"
  owner = decoded.value
  var images = newSeq[PageImage](pageCount)
  var cursor = 136 + wireSize
  for page in 0..<pageCount:
    # Pinky's writable state includes its initializer's heap, framebuffer and stack residues.
    let index = PageIndex(uint32(word(data, cursor, 4)))
    let permission = byte(data[cursor + 4])
    assert permission in [1'u8, 2'u8]
    images[page].index = index
    images[page].access = if permission == 1: PageAccess.ReadOnly else: PageAccess.ReadWrite
    copyInvocationInput(images[page].bytes, data, cursor + 5)
    cursor += 4101
  let captured = captureMemory(images, PageLimit(uint32(pageCount)))
  assert captured.error == MachineError.None
  memory = captured.value
# All thirteen caller registers, finite gas and uncharged entry come from the frozen invocation ABI.
let source = captureMachine(owner, memory, info).value
var plan = default(GasPlan)
var memo = default(GasMemo)
if plannedMode:
  # Only additional immutable-price preparation is bracketed here; common program/memory capture stays outside execution.
  let prepareWall = if clocked: getMonoTime().ticks else: 0'i64
  let prepareCpu = if clocked: cpuNanoseconds() else: 0'i64
  let created = newGasPlan(owner, GasPlanLimits(blocks: GasPlanBlockLimit(100000),
    bytes: GasPlanByteLimit(8*1024*1024), cycles: GasCycleLimit(1000000)))
  let prepareCpuNs = if clocked: cpuNanoseconds()-prepareCpu else: 0'i64
  let prepareWallNs = if clocked: getMonoTime().ticks-prepareWall else: 0'i64
  assert created.error == GasPlanError.None
  plan = created.value
  let info = gasPlanInfo(plan).value
  echo "GAS_PLAN,", prepareCpuNs, ",", prepareWallNs, ",", info.codeBytes, ",",
    info.blockCount, ",", info.payloadBytes, ",", uint64(info.cycleLimit)
if memoMode:
  # Initialization allocates only bounded empty facts; sample zero retains the actual first-cold pricing work.
  let prepareWall = if clocked: getMonoTime().ticks else: 0'i64
  let prepareCpu = if clocked: cpuNanoseconds() else: 0'i64
  let created = newGasMemo(owner, GasMemoLimits(bytes: GasMemoByteLimit(
      8*1024*1024), cycles: GasCycleLimit(1000000)))
  let prepareCpuNs = if clocked: cpuNanoseconds()-prepareCpu else: 0'i64
  let prepareWallNs = if clocked: getMonoTime().ticks-prepareWall else: 0'i64
  assert created.error == GasMemoError.None
  memo = created.value
  let info = gasMemoInfo(memo).value
  assert info.pricedBlocks == 0
  echo "GAS_MEMO,", prepareCpuNs, ",", prepareWallNs, ",", info.codeBytes, ",",
      info.payloadBytes, ",", uint64(info.cycleLimit)
var preparationCpuNs = 0'i64
var preparationWallNs = 0'i64
var preparationCodeBytes = 0'u64
var preparationInstructions = 0'u64
var prepared = default(reference.PreparedProgram)
if preparedMode:
  # Construction admits decoded facts; sample zero includes lazy executable-node and price preparation.
  let prepareWall = if clocked: getMonoTime().ticks else: 0'i64
  let prepareCpu = if clocked: cpuNanoseconds() else: 0'i64
  let created = when declared(reference.DefaultPvmBackend):
    # The owner captures selection and prepares capabilities inside the existing constructor clock.
    reference.newPreparedProgram(owner, reference.defaultPreparedLimits(
        GasCycleLimit(1000000)), selectedBackend, invocationRuntime)
  else:
    # Historical source snapshots preserve their original public API and engine policy.
    reference.newPreparedProgram(owner, reference.defaultPreparedLimits(
        GasCycleLimit(1000000)))
  let prepareCpuNs = if clocked: cpuNanoseconds()-prepareCpu else: 0'i64
  let prepareWallNs = if clocked: getMonoTime().ticks-prepareWall else: 0'i64
  assert created.error == reference.PreparationError.None
  prepared = created.value
  let observed = reference.preparedInfo(prepared).value
  assert observed.streamNodes == 0
  # Retain raw scalar observations only; full-mode report formatting occurs after sample0 stops.
  preparationCpuNs = prepareCpuNs
  preparationWallNs = prepareWallNs
  preparationCodeBytes = observed.codeBytes
  preparationInstructions = observed.decodedInstructions
  if not fullInvocation:
    echo "PREPARED_PROGRAM,", prepareCpuNs, ",", prepareWallNs, ",", observed.codeBytes,
      ",", observed.decodedInstructions
let engine = if preparedMode: "ragnarok_prepared" elif memoMode: "ragnarok_memo" elif plannedMode: "ragnarok_planned" else: "ragnarok"
for sample in 0..<samples:
  # Program/memory/ABI setup is outside execution timing in both interpreters.
  let residentCall = if fullInvocation and sample != 0: beginInvocation() else: default(InvocationClock)
  let cpuStart = if fullInvocation: (if sample ==
      0: coldCall.cpu else: residentCall.cpu)
    elif clocked: cpuNanoseconds() else: 0'i64
  let wallStart = if fullInvocation: (if sample ==
      0: coldCall.wall else: residentCall.wall)
    elif clocked: getMonoTime().ticks else: 0'i64
  let done = if preparedMode: runPreparedKernel(source, prepared)
    elif memoMode: reference.execute(source, reference.ExecutionStepLimit(
        1000000000), memo)
    elif plannedMode: reference.execute(source, reference.ExecutionStepLimit(
        1000000000), plan)
    else: reference.execute(source, reference.ExecutionStepLimit(1000000000),
        GasCycleLimit(1000000))
  assert done.error == reference.StepError.None, "current sieve execution"
  let finalCpu = machineInfo(done.value.machine).value
  let elapsed = if clocked: getMonoTime().ticks - wallStart else: 0'i64
  let cpuElapsed = if clocked: cpuNanoseconds() - cpuStart else: 0'i64
  if sample == 0:
    if artifactAdmission:
      # The expanded fixture remains an independent oracle, checked after the complete cold call.
      var originalWire = newSeq[byte](wireSize)
      copyInvocationInput(originalWire, data, 136)
      assert matchesProgramEncoding(owner, originalWire), "sieve artifact program mismatch"
      let mapped = pageIndices(memory).value
      assert mapped.len == indices.len, "sieve artifact map mismatch"
      for page in 0..<mapped.len:
        assert uint32(mapped[page]) == uint32(indices[page]), "sieve artifact map mismatch"
      # Page zero is an unmapped ABI guard; inserting it must still hit the exact caller page ceiling.
      assert withPage(memory, PageImage(index: PageIndex(0), access:
        PageAccess.ReadWrite)).error == MachineError.LimitExceeded, "sieve artifact page limit mismatch"
    if fullInvocation:
      echo "PREPARED_PROGRAM,", preparationCpuNs, ",", preparationWallNs, ",",
        preparationCodeBytes, ",", preparationInstructions
  assert done.value.exit == reference.StepExit.Halt
  check(done.value.machine, finalCpu, indices, access, expected, limit, guest)
  echo "SIEVE,", engine, ",", limit, ",", sample, ",", elapsed, ",", cpuElapsed
  if preparedMode:
    # Cache occupancy and preparation progress remain explicit for cold and reused executions.
    let observed = reference.preparedInfo(prepared).value
    assert observed.streamNodes > 0
    assert observed.streamNodes <= uint64(observed.limits.resources.nodes)
    echo "PREPARED_CACHE,", sample, ",", observed.streamNodes, ",",
        observed.preparationUnits, ",", uint64(observed.limits.resources.nodes),
            ",", uint64(observed.limits.resources.preparation)
  checkMemory(memory, indices, access, originalBytes, 0, "pvm sieve initial memory mismatch")
  let original = machineInfo(source).value
  assert uint64(original.pc) == entry and uint64(original.gas) == uint64(info.gas)
  assert not original.blockCharged
  for i in 0..<13: assert uint64(original.registers[i]) == uint64(
      info.registers[i])

if memoMode:
  # Final bounded occupancy is observed outside execution timing and must accompany every complete memo pass.
  echo "GAS_MEMO_END,", gasMemoInfo(memo).value.pricedBlocks

when declared(reference.DefaultPvmBackend):
  if requestedBackend.len > 0:
    # Copied cumulative diagnostics certify policy after all full-state checks, outside all clocks.
    assert preparedMode
    let policy = reference.preparedInfo(prepared).value
    assert policy.backend == selectedBackend
    if fullInvocation: reportNativeCompilation("guest-process",
        policy.nativeCompilationMeasured, policy.nativeCompilationNs)
    let actual = if policy.nativeOperations > 0: "jit" else: "interpreted"
    echo "PVM_POLICY,1,", requestedBackend, ",", int(policy.jitBuilt), ",",
      int(policy.jitPlatformSupported), ",", int(policy.checkedFallbackEnabled),
          ",", actual, ",",
      policy.nativeFragments, ",", policy.nativeCalls, ",",
          policy.nativeOperations

when defined(pvmArmMacroReceipt):
  # Application qualification observes actual resident publication and completed macro calls.
  let macroStats = reference.preparedArmMacroStatistics(prepared).value
  let resident = reference.preparedArmMacroResidentActive(prepared).value
  echo "ARM_MACRO_APPLICATION,", getEnv("RAGNAROK_PVM_GUEST"), ",", int(
      resident),
    ",", macroStats[0], ",", macroStats[1], ",", macroStats[5], ",", macroStats[6]

when defined(pvmArm64JitOwnerReceipt):
  # Counter publication stays outside all call clocks and proves native work survives genuine prepared-owner reuse.
  assert preparedMode
  if fullInvocation:
    reportInvocationOwner(prepared, getEnv("RAGNAROK_PVM_GUEST"))
  else:
    let native = reference.preparedArmStatistics(prepared).value
    echo "ARM_OWNER,", getEnv("RAGNAROK_PVM_GUEST"), ",", native[0], ",", native[
        1], ",",
      native[2], ",", native[3], ",", native[4], ",", native[5], ",", native[6]

if fullInvocation:
  prepared = default(reference.PreparedProgram)
  if requestedBackend == "jit":
    closeInvocationRuntime(invocationRuntime, "guest-process", coldCall)
  else:
    finishInterpretedOwner("guest-process", coldCall)
