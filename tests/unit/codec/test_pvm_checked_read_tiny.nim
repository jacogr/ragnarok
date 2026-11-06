# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Run one genuine read candidate with a large quota and tiny actual work.
import std/[assertions, syncio]
import ../../../src/pvm/[machine, program, step]
import ../../../src/pvm/gas/gas

proc unexpectedHost(called: var bool, suspension: StepOutcome): HostResponse {.raises: [].} =
  ## This guest uses no host import, so any suspension invalidates the witness.
  called = true
  default(HostResponse)

let wire = [0'u8, 0, 30,
  2, 124, 0x11, 2, 0, 1, 149, 0x11, 0, 0, 1, 129, 0x12, 0xff, 130, 0x54, 1,
  51, 6, 1, 0, 1, 149, 0x66, 0xff, 82, 0x06, 0xfd, 50, 0,
  0x43, 0x48, 0x63, 0x12]
# The qualified synthetic read shape is unchanged. Only the later loop count is now one.
let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
assert decoded.error == ProgramError.None
let code = decoded.value
var input = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000000),
  gasDeficit: GasDeficit(0), blockCharged: false)
for i in 0..<input.registers.len:
  # Preserve the staged-read witness's original register and alias conditions.
  input.registers[i] = RegisterValue(0x1234567800000000'u64+uint64(i))
input.registers[0] = RegisterValue(0xffff0000)
input.registers[1] = RegisterValue(0x00000001fffffffe'u64)
input.registers[5] = RegisterValue(0x20000)
var pages = default(array[2, PageImage])
pages[0].index = PageIndex(16)
pages[0].access = PageAccess.ReadOnly
pages[0].bytes[0] = 0x80
pages[0].bytes[0x7f] = 1
pages[0].bytes[0x82] = 0x80
pages[1].index = PageIndex(32)
pages[1].access = PageAccess.ReadWrite
for i, value in [0x10'u8, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe]:
  # The final staged read must preserve its actual aliased source bytes.
  pages[1].bytes[i] = value
let captured = captureMemory(pages, PageLimit(2))
assert captured.error == MachineError.None
let source = captureMachine(code, captured.value, input).value
let limits = defaultPreparedLimits(GasCycleLimit(1000))
const quota = ExecutionStepLimit(1000000000)
let checked = newPreparedProgram(code, limits, PvmBackend.Interpreted, default(NativeRuntime))
assert checked.error == PreparationError.None
var called = false
let expected = executeWithHost(source, called, unexpectedHost, quota, HostCallLimit(0),
    checked.value)
assert expected.error == StepError.None and expected.value.exit == StepExit.Halt
let runtime = newNativeRuntime()
try:
  assert start(runtime)
except:
  assert false, "tiny read probe worker failed to start"
var owner = default(PreparedProgram)
block:
  let created = newPreparedProgram(code, limits, PvmBackend.Jit, runtime)
  assert created.error == PreparationError.None
  owner = created.value
let done = executeWithHost(source, called, unexpectedHost, quota, HostCallLimit(0), owner)
assert not called and done.error == StepError.None and done.value.exit == StepExit.Halt
assert done.value.backend == PvmBackend.Interpreted
let a = machineInfo(expected.value.machine).value
let b = machineInfo(done.value.machine).value
assert uint64(a.pc) == uint64(b.pc) and uint64(a.gas) == uint64(b.gas)
assert uint64(a.gasDeficit) == uint64(b.gasDeficit) and a.blockCharged == b.blockCharged
for i in 0..<a.registers.len:
  # Register values retain their independent nominal domain.
  assert uint64(a.registers[i]) == uint64(b.registers[i])
assert uint64(b.registers[1]) == 0x10080 and uint64(b.registers[2]) == 0xffffffff80000001'u64
assert uint64(b.registers[4]) == 0xfedcba9876543210'u64 and uint64(b.registers[6]) == 0
let finalMemory = memoryOf(done.value.machine).value
let finalPages = pageIndices(finalMemory)
assert finalPages.error == MachineError.None and finalPages.value.len == pages.len
for i, original in pages:
  # Require every retained byte and permission to match both the immutable input and checked result.
  assert uint32(finalPages.value[i]) == uint32(original.index)
  let checkedPage = pageImage(memoryOf(expected.value.machine).value, original.index).value
  let actual = pageImage(finalMemory, original.index).value
  let originalPage = pageImage(captured.value, original.index).value
  assert actual.access == original.access and actual.bytes == original.bytes
  assert checkedPage.access == actual.access and checkedPage.bytes == actual.bytes
  assert originalPage.access == actual.access and originalPage.bytes == actual.bytes
let state = preparedInfo(owner).value
let worker = runtimeInfo(runtime)
assert state.nativeFragments == 0 and state.nativeCalls == 0 and state.nativeOperations == 0
assert worker.submitted == 0 and worker.completed == 0
owner = default(PreparedProgram)
assert close(runtime)
echo "PVM tiny read admission passed"
