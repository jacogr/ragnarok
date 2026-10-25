# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute frozen checked upstream guests supplied to PolkaVM; compare complete reference outputs.
import std/[assertions, syncio, monotimes, envvars]
import ../../src/pvm/[program, machine, gas, gas_plan, gas_memo]
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

proc cpuNanoseconds(): int64 {.importc: "pvm_sieve_cpu_nanoseconds", header: "pvm_sieve_clock.h".}
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

proc checkMemory(memory: Memory, indices: seq[PageIndex], access: seq[PageAccess], expected: string,
    offset: int): void =
  ## Compare every initialized/mapped byte; a matching prime count alone is insufficient.
  assert expected.len == offset + indices.len * 4096
  for page in 0..<indices.len:
    let image = pageImage(memory, indices[page]).value
    assert image.access == access[page]
    for i in 0..<4096: assert image.bytes[i] == byte(expected[offset + page * 4096 + i])

proc check(machine: Machine, indices: seq[PageIndex], access: seq[PageAccess], expected: string,
    limit: uint64, guest: GuestKind) =
  ## Validate terminal CPU state, exact gas, all registers and all mapped memory outside timing.
  let cpu = machineInfo(machine).value
  assert uint64(cpu.pc) == 0 and cpu.blockCharged and uint64(cpu.gasDeficit) == 0
  assert uint64(cpu.gas) == word(expected, 8, 8)
  for i in 0..<13: assert uint64(cpu.registers[i]) == word(expected, 16 + i * 8, 8)
  assert uint64(cpu.registers[7]) == count(guest, limit)
  checkMemory(memoryOf(machine).value, indices, access, expected, 120)

let guest = selectedGuest(getEnv("RAGNAROK_PVM_GUEST"))
if getEnv("RAGNAROK_PVM_SIEVE_ASSERT_PROBE") == "1":
  assert false, "pvm sieve native assertion control"
var data = ""
var expected = ""
try:
  data = readFile(getEnv("RAGNAROK_PVM_SIEVE_INPUT"))
  expected = readFile(getEnv("RAGNAROK_PVM_SIEVE_EXPECTED"))
except:
  quit 2
assert data.len >= 136 and data[0..7] == "PVMSIV01"
assert expected.len >= 120 and expected[0..7] == "PVMSIE01"
let wireSize = int(word(data, 8, 4))
let entry = word(data, 12, 4)
let limit = word(data, 16, 4)
discard count(guest, limit) # Reject a foreign family/size before an expensive execution or policy allocation.
let pageCount = int(word(data, 20, 4))
assert wireSize > 0 and wireSize <= 4 * 1024 * 1024 and pageCount > 0 and pageCount <= 4096
assert data.len == 136 + wireSize + pageCount * 4101
var info = MachineInfo(pc: CodeAddress(entry), gas: MachineGas(word(data, 24, 8)),
  registers: default(RegisterFile), blockCharged: false)
for i in 0..<13: info.registers[i] = RegisterValue(word(data, 32 + i * 8, 8))
var wire = newSeq[byte](wireSize)
for i in 0..<wireSize: wire[i] = byte(data[136 + i])
let decoded = decodeJamProgram(wire, CodeAddress(entry), ProgramByteLimit(4 * 1024 * 1024),
  JumpCountLimit(1024 * 1024))
assert decoded.error == ProgramError.None, "sieve program decoding"
let owner = decoded.value
var images: seq[PageImage] = @[]
var indices: seq[PageIndex] = @[]
var access: seq[PageAccess] = @[]
var cursor = 136 + wireSize
var originalBytes = ""
for page in 0..<pageCount:
  let index = PageIndex(uint32(word(data, cursor, 4)))
  let permission = byte(data[cursor + 4])
  assert permission in [1'u8, 2'u8]
  var image = PageImage(index: index,
    access: (if permission == 1: PageAccess.ReadOnly else: PageAccess.ReadWrite),
    bytes: default(array[4096, byte]))
  for i in 0..<4096:
    image.bytes[i] = byte(data[cursor + 5 + i])
    originalBytes.add(data[cursor + 5 + i])
  images.add(image)
  indices.add(index)
  access.add(image.access)
  cursor += 4101
let captured = captureMemory(images, PageLimit(uint32(pageCount)))
assert captured.error == MachineError.None
let memory = captured.value
let source = captureMachine(owner, memory, info).value
let pricing = getEnv("RAGNAROK_PVM_PRICING")
assert pricing in ["", "dynamic", "planned", "memo", "prepared"]
let preparedMode = pricing == "prepared"
let clocked = getEnv("RAGNAROK_PVM_SIEVE_CLOCK") != "0"
let plannedMode = pricing == "planned"
let memoMode = pricing == "memo"
if guest != GuestKind.Sieve:
  # Additional families require a protocol witness before policy metadata or samples.
  echo "GUEST,", getEnv("RAGNAROK_PVM_GUEST")
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
  let created = newGasMemo(owner, GasMemoLimits(bytes: GasMemoByteLimit(8*1024*1024),
      cycles: GasCycleLimit(1000000)))
  let prepareCpuNs = if clocked: cpuNanoseconds()-prepareCpu else: 0'i64
  let prepareWallNs = if clocked: getMonoTime().ticks-prepareWall else: 0'i64
  assert created.error == GasMemoError.None
  memo = created.value
  let info = gasMemoInfo(memo).value
  assert info.pricedBlocks == 0
  echo "GAS_MEMO,", prepareCpuNs, ",", prepareWallNs, ",", info.codeBytes, ",", info.payloadBytes,
      ",", uint64(info.cycleLimit)
var prepared = default(reference.PreparedProgram)
if preparedMode:
  # Construction reserves only a bounded empty index; sample zero includes actual lazy operation/price preparation.
  let prepareWall = if clocked: getMonoTime().ticks else: 0'i64
  let prepareCpu = if clocked: cpuNanoseconds() else: 0'i64
  let created = reference.newPreparedProgram(owner, reference.PreparedLimits(
      bytes: reference.PreparedByteLimit(64*1024*1024), blocks: reference.PreparedBlockLimit(16384),
      cycles: GasCycleLimit(1000000)))
  let prepareCpuNs = if clocked: cpuNanoseconds()-prepareCpu else: 0'i64
  let prepareWallNs = if clocked: getMonoTime().ticks-prepareWall else: 0'i64
  assert created.error == reference.PreparationError.None
  prepared = created.value
  let observed = reference.preparedInfo(prepared).value
  assert observed.preparedOperations == 0
  echo "PREPARED_PROGRAM,", prepareCpuNs, ",", prepareWallNs, ",", observed.codeBytes, ",",
      observed.residentBytes
let engine = if preparedMode: "ragnarok_prepared" elif memoMode: "ragnarok_memo" elif plannedMode: "ragnarok_planned" else: "ragnarok"
let requestedSamples = getEnv("RAGNAROK_PVM_SIEVE_SAMPLES")
assert requestedSamples in ["1", "4", "13"]
# Four calls support an isolated post-three-warmup counter dump; ordinary timings retain thirteen.
let samples = if requestedSamples == "1": 1 elif requestedSamples == "4": 4 else: 13
for sample in 0..<samples:
  # Program/memory/ABI setup is outside execution timing in both interpreters.
  let wallStart = if clocked: getMonoTime().ticks else: 0'i64
  let cpuStart = if clocked: cpuNanoseconds() else: 0'i64
  let done = if preparedMode: reference.execute(source, reference.ExecutionStepLimit(1000000000), prepared)
    elif memoMode: reference.execute(source, reference.ExecutionStepLimit(1000000000), memo)
    elif plannedMode: reference.execute(source, reference.ExecutionStepLimit(1000000000), plan)
    else: reference.execute(source, reference.ExecutionStepLimit(1000000000), GasCycleLimit(1000000))
  let cpuElapsed = if clocked: cpuNanoseconds() - cpuStart else: 0'i64
  let elapsed = if clocked: getMonoTime().ticks - wallStart else: 0'i64
  assert done.error == reference.StepError.None, "current sieve execution"
  assert done.value.exit == reference.StepExit.Halt
  check(done.value.machine, indices, access, expected, limit, guest)
  echo "SIEVE,", engine, ",", limit, ",", sample, ",", elapsed, ",", cpuElapsed
  if preparedMode:
    # Cache occupancy and preparation progress remain explicit for cold and reused executions.
    let observed = reference.preparedInfo(prepared).value
    assert observed.residentBytes <= uint64(observed.byteLimit) and observed.preparedOperations > 0
    echo "PREPARED_CACHE,", sample, ",", observed.residentBytes, ",", observed.residentBlocks, ",",
        observed.residentOperations, ",", observed.preparedBlocks, ",", observed.preparedOperations,
        ",", observed.hits, ",", observed.evictions, ",", observed.peakBytes
  checkMemory(memory, indices, access, originalBytes, 0)
  let original = machineInfo(source).value
  assert uint64(original.pc) == entry and uint64(original.gas) == uint64(info.gas)
  assert not original.blockCharged
  for i in 0..<13: assert uint64(original.registers[i]) == uint64(info.registers[i])

if memoMode:
  # Final bounded occupancy is observed outside execution timing and must accompany every complete memo pass.
  echo "GAS_MEMO_END,", gasMemoInfo(memo).value.pricedBlocks
