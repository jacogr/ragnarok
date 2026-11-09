# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Public saturated Read admission, replay and dirty publication over a compact seven-role program.

import std/[assertions, syncio]
import ../../src/pvm/[machine, program, step]
import ../../src/pvm/gas/gas
import ../../src/pvm/internal/native_pipeline

when not (NativeReadCycleEnabled and defined(pvmSharedAsyncWitness)):
  {.error: "connected handoff requires the native async witness profile".}

const
  PreludeBlockBytes = 12'u64
  PreludeBytes = 4 * PreludeBlockBytes
  ReadPc = PreludeBytes + 19
  SignedReadPc = PreludeBytes + 31
  StorePage = PageIndex(32)
  StoreOffset = 16
  StoreAddress = 0x20010'u64
  FaultAddress = 0x22000'u64
  TrainingAttempts = ExecutionStepLimit(2000000)
  TestAttempts = ExecutionStepLimit(4096)
  # No jump table, 176 code bytes and a 22-byte instruction-start bitmap.
  # Four noop / absolute byte load / absolute signed byte load / fallthrough blocks fill
  # ordinary observation before Read. Both loads read the zero byte at 0x10000 into r12.
  # The original 128-byte route starts at 48. Its original offsets below are relative to 48.
  # 0 marks the Store page and jumps to Read. Outer 4 -> Outside 126 or Gate 16.
  # Read 19 -> Setup 89 -> Store 98 -> Tail 112 -> Jump 124 -> Outer 4.
  # Tail can also jump to Setup, Store can loop, and Gate returns to Outer or Read.
  Wire = [0'u8, 0, 0x80, 0xb0,
    2, 52, 12, 0, 0, 1, 53, 12, 0, 0, 1, 1,
    2, 52, 12, 0, 0, 1, 53, 12, 0, 0, 1, 1,
    2, 52, 12, 0, 0, 1, 53, 12, 0, 0, 1, 1,
    2, 52, 12, 0, 0, 1, 53, 12, 0, 0, 1, 1,
    0x78, 0x47, 0x28, 0x11, 0x83, 0x88, 0x01, 0x95, 0x00, 0x01,
    0x51, 0x28, 0x40, 0x01, 0x74, 0x00, 0x58, 0x02, 0xf4,
    0x02, 0x7c, 0x0a, 0x97, 0xaa, 0x02, 0x82, 0x19, 0x60, 0xc8, 0x9a, 0x0a, 0x81, 0xaa,
    0x33, 0x04, 0x10, 0x00, 0x02, 0x97, 0xab, 0x28, 0x98, 0xbb, 0x38, 0x82, 0x19, 0x70,
    0xc6, 0x9b, 0x0b, 0x84, 0xa6, 0xff, 0x00, 0xc6, 0xc6, 0x06, 0x82, 0x19, 0x80, 0x00,
    0xc5, 0x9b, 0x0b, 0xd4, 0x6b, 0x0b, 0x97, 0xaa, 0x30, 0x98, 0xaa, 0x38, 0x82, 0x19, 0x68,
    0xc6, 0x9a, 0x0a, 0x82, 0x19, 0x78, 0xc5, 0x9a, 0x06, 0xd4, 0xb6, 0x06, 0x01,
    0x33, 0x0b, 0xc8, 0x54, 0x0a, 0x95, 0xaa, 0x01, 0x01, 0xc6, 0xb6, 0x09, 0x78, 0x49,
    0x95, 0x44, 0x01, 0x95, 0xbb, 0x08, 0xab, 0xa4, 0xf5, 0x02, 0x39, 0x02, 0xfc, 0x8f, 0x01,
    0x83, 0x33, 0x01, 0xad, 0x23, 0xe0, 0x28, 0x88, 0x32, 0x07,
    0x43, 0x38, 0x84, 0x43, 0x38, 0x84,
    0x95, 0x04, 0x59, 0x92, 0x42, 0x92, 0x44, 0x22, 0x49, 0x92, 0x24, 0x4b, 0xa6, 0x24, 0x43, 0x52]

type HandoffCase {.pure.} = enum
  ## Training resolves the same program used by the three focused invocation variants.
  Training, FaultReplay, SlowReplay, CleanStore

proc handoffProgram(): Program =
  ## Verify key instruction labels through the original decoder before public preparation.
  let decoded = decodeProgram(Wire, CodeAddress(0), ProgramByteLimit(uint64(Wire.len)),
      JumpCountLimit(0))
  assert decoded.error == ProgramError.None, "compact handoff wire must decode"
  let owner = decoded.value
  for start in [0'u64, PreludeBlockBytes, 2 * PreludeBlockBytes, 3 * PreludeBlockBytes]:
    # The four earlier candidates are distinct complete blocks with two absolute loads each.
    let boundary = basicBlockStart(owner, CodeAddress(start))
    assert boundary.error == ProgramError.None and boundary.value
    assert instruction(owner, CodeAddress(start + 1)).value.opcode == 52
    assert instruction(owner, CodeAddress(start + 6)).value.opcode == 53
  for label in [0'u64, 4, 16, 19, 89, 98, 112, 124, 126]:
    # The relocated route retains all original complete block boundaries.
    let boundary = basicBlockStart(owner, CodeAddress(PreludeBytes + label))
    assert boundary.error == ProgramError.None and boundary.value, "compact handoff source label"
  assert instruction(owner, CodeAddress(SignedReadPc)).value.opcode == 129
  owner

proc handoffInput(owner: Program, mode: HandoffCase): Machine =
  ## Construct the same small permission layout with one changed byte or secondary page per replay.
  let count = if mode == HandoffCase.SlowReplay: 12 else: 11
  var pages = newSeq[PageImage](count)
  for index in 0..<9:
    # One primary RO run contains the byte table, qword constants and signed Tail input.
    pages[index].index = PageIndex(uint32(index + 16))
    pages[index].access = PageAccess.ReadOnly
  if mode in {HandoffCase.FaultReplay, HandoffCase.SlowReplay}:
    # The second Read's scaled index will step across the primary writable run's end.
    pages[0].bytes[1] = 1
  pages[8].bytes[0xe60] = 0xfc
  pages[8].bytes[0xe61] = 0x1f
  pages[8].bytes[0xe62] = 0x02
  pages[8].bytes[0xe78] = 16
  pages[8].bytes[0xe80] = 8
  pages[8].bytes[0xffc] = 1
  for index in 9..10:
    # A single writable run owns both the Store destination and the signed32 source's last four bytes.
    pages[index].index = PageIndex(uint32(index + 23))
    pages[index].access = PageAccess.ReadWrite
    for offset in 0..<4096:
      pages[index].bytes[offset] = byte((index * 19 + offset * 13) and 255)
  pages[10].bytes[4092] = 0x44
  pages[10].bytes[4093] = 0x33
  pages[10].bytes[4094] = 0x22
  pages[10].bytes[4095] = 0x11
  if mode == HandoffCase.SlowReplay:
    # A secondary RO run is readable through checked memory and absent from the clipped native descriptors.
    pages[11].index = PageIndex(34)
    pages[11].access = PageAccess.ReadOnly
    pages[11].bytes[0] = 0x99
    pages[11].bytes[1] = 0x88
    pages[11].bytes[2] = 0x77
  let memory = captureMemory(pages, PageLimit(12))
  assert memory.error == MachineError.None
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(0x10000)
  registers[1] = RegisterValue(0x18e00)
  registers[4] = RegisterValue(StoreAddress)
  registers[5] = RegisterValue(3)
  registers[7] = RegisterValue(0xffff0000)
  registers[8] = RegisterValue(case mode
    of HandoffCase.Training: 0xffffffffffff8000'u64
    of HandoffCase.FaultReplay, HandoffCase.SlowReplay: 318'u64
    of HandoffCase.CleanStore: 319'u64)
  let entry = if mode == HandoffCase.CleanStore: ReadPc else: 0'u64
  let captured = captureMachine(owner, memory.value, MachineInfo(pc: CodeAddress(entry),
    gas: MachineGas(20000000), registers: registers))
  assert captured.error == MachineError.None
  captured.value

proc noHandoffHost(called: var bool, suspension: StepOutcome): HostResponse {.raises: [].} =
  ## This fixture ends at checked halt or fault. A host callback would invalidate the receipt.
  called = true
  default(HostResponse)

proc runHandoff(source: Machine, prepared: PreparedProgram,
    attempts: ExecutionStepLimit): StepOutcome =
  ## Use the ordinary public prepared host entry, including the checked/native frame bridge.
  var called = false
  let done = executeWithHost(source, called, noHandoffHost, attempts, HostCallLimit(0), prepared)
  assert not called and done.error == StepError.None, "compact handoff public execution"
  done.value

proc sameMachine(actual, expected: Machine) =
  ## Check complete public CPU, program, permissions and page bytes without relying on dirty metadata.
  let left = machineInfo(actual).value
  let right = machineInfo(expected).value
  assert uint64(left.pc) == uint64(right.pc) and uint64(left.gas) == uint64(right.gas)
  assert uint64(left.gasDeficit) == uint64(right.gasDeficit) and left.blockCharged ==
      right.blockCharged
  assert left.registers == right.registers
  assert programBytes(programOf(actual).value).value == programBytes(programOf(
      expected).value).value
  let leftMemory = memoryOf(actual).value
  let rightMemory = memoryOf(expected).value
  let leftIndices = pageIndices(leftMemory).value
  let rightIndices = pageIndices(rightMemory).value
  assert leftIndices.len == rightIndices.len
  for index in 0..<leftIndices.len:
    # Page order and every byte must agree, including untouched canaries and any secondary RO region.
    let page = leftIndices[index]
    assert uint32(page) == uint32(rightIndices[index])
    let leftPage = pageImage(leftMemory, page).value
    let rightPage = pageImage(rightMemory, page).value
    assert leftPage.access == rightPage.access and leftPage.bytes == rightPage.bytes

proc handoffOwner(owner: Program, backend: PvmBackend, runtime: NativeRuntime): PreparedProgram =
  ## Both policies share the identical immutable Program and default gas policy.
  let prepared = newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(1000)), backend, runtime)
  assert prepared.error == PreparationError.None
  prepared.value

proc verifyStore(before, after: Machine, mode: HandoffCase) =
  ## A literal word result and untouched neighboring bytes independently prove dirty publication.
  let original = pageImage(memoryOf(before).value, StorePage).value
  let changed = pageImage(memoryOf(after).value, StorePage).value
  let word = if mode == HandoffCase.SlowReplay: [0x99'u8, 0x77, 0x88, 0]
    else: [0x44'u8, 0x22, 0x33, 0]
  assert changed.access == PageAccess.ReadWrite and original.access == PageAccess.ReadWrite
  for index in 0..<4096:
    # The checked prelude touches only the first byte of the same final Store word.
    if index >= StoreOffset and index < StoreOffset + 4:
      assert changed.bytes[index] == word[index - StoreOffset], "published Store byte"
    else:
      assert changed.bytes[index] == original.bytes[index], "neighboring Store bytes"

proc runConnectedReadHandoff*(report: bool = true) =
  ## Publish one connected image after ordinary admission fills, then compare three checked exits.
  let owner = handoffProgram()
  let runtime = newNativeRuntime()
  try:
    assert start(runtime)
  except:
    assert false, "compact handoff runtime start failed"
  var jit = handoffOwner(owner, PvmBackend.Jit, runtime)
  let checked = handoffOwner(owner, PvmBackend.Interpreted, default(NativeRuntime))
  let training = handoffInput(owner, HandoffCase.Training)
  armNativeCompilerGate(runtime, NativeCompilerPoint.BeforePublish)
  let cold = runHandoff(training, jit, TrainingAttempts)
  assert cold.exit == StepExit.Halt and cold.backend == PvmBackend.Interpreted
  assert preparedNativeState(jit).value == NativeState.Pending, "compact handoff nomination must queue"
  let expectedTraining = runHandoff(training, checked, TrainingAttempts)
  assert expectedTraining.exit == StepExit.Halt
  sameMachine(cold.machine, expectedTraining.machine)
  let image = waitNativeCompilerGate(runtime)
  assert image.kind == NativeKind.ConnectedReadCycle,
    "saturated Read admission must queue ConnectedReadCycle"
  assert image.hasImage, "saturated Read admission must publish a real image"
  assert image.slot == 0 and image.ticket == 1 and image.epoch == 1 and image.generation == 1
  releaseNativeCompilerGate(runtime)
  waitNativeCompiler(runtime)
  let ready = runHandoff(training, jit, TrainingAttempts)
  assert ready.exit == StepExit.Halt and ready.backend == PvmBackend.Jit
  sameMachine(ready.machine, expectedTraining.machine)
  assert preparedNativeState(jit).value == NativeState.Ready
  let trained = preparedInfo(jit).value
  assert trained.nativeFragments == 1 and trained.nativeCodeBytes > 0 and
    trained.nativeCodeBytes <= uint64(NativeImageByteLimit)
  assert trained.nativeCalls > 0 and trained.nativeBranchCalls > 0 and trained.nativeHeaderCalls > 0
  if report:
    echo "CONNECTED_HANDOFF_READY,ConnectedReadCycle,", trained.nativeCodeBytes

  var saved: seq[StepOutcome] = @[]
  var expected: seq[StepOutcome] = @[]
  for mode in [HandoffCase.FaultReplay, HandoffCase.SlowReplay, HandoffCase.CleanStore]:
    # Each short guest case still receives the minimum public horizon needed to admit the installed image.
    let source = handoffInput(owner, mode)
    let reference = runHandoff(source, checked, TestAttempts)
    let before = preparedInfo(jit).value
    let actual = runHandoff(source, jit, TestAttempts)
    let after = preparedInfo(jit).value
    assert actual.backend == PvmBackend.Jit and reference.backend == PvmBackend.Interpreted
    assert actual.exit == reference.exit
    if mode == HandoffCase.FaultReplay:
      # The first native group remains visible even though the second Read faults before its StoreSetup.
      assert actual.exit == StepExit.Fault and uint64(actual.faultPage) == FaultAddress
      assert uint64(reference.faultPage) == FaultAddress
      let cpu = machineInfo(actual.machine).value
      assert uint64(cpu.pc) == SignedReadPc and cpu.blockCharged
      assert uint64(cpu.registers[10]) == FaultAddress
    else:
      assert actual.exit == StepExit.Halt
    sameMachine(actual.machine, reference.machine)
    verifyStore(source, actual.machine, mode)
    sameMachine(source, handoffInput(owner, mode))
    assert after.nativeFragments == 1 and after.nativeCodeBytes == trained.nativeCodeBytes
    assert after.nativeCalls - before.nativeCalls == 1
    let committed = if mode == HandoffCase.CleanStore: 28'u64 else: 57'u64
    let branches = if mode == HandoffCase.CleanStore: 0'u64 else: 1'u64
    assert after.nativeOperations - before.nativeOperations == committed, "exact native prefix before handoff"
    assert after.nativeBranchCalls - before.nativeBranchCalls == branches
    assert after.nativeHeaderCalls == before.nativeHeaderCalls
    if report:
      echo "CONNECTED_HANDOFF_CASE,", ord(mode), ",", ord(actual.exit), ",", committed, ",", branches
    saved.add(actual)
    expected.add(reference)
  jit = default(PreparedProgram)
  assert runtimeInfo(runtime).registered == 0 and close(runtime)
  for index in 0..<saved.len:
    # Retained immutable results survive subsequent calls, prepared-owner drop and compiler close.
    sameMachine(saved[index].machine, expected[index].machine)
  if report:
    echo "PASS public connected read handoff"
