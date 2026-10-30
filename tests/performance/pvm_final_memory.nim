# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private frozen CI characterization: fixed source attempts across mapped/dirty pages and exact immutable host checkpoints.
import std/[assertions, syncio, envvars]
import ../../src/pvm/[program, machine, step]
import ../../src/pvm/gas/gas
import ../../src/pvm/internal/handler_stream

proc cpuNs(): int64 {.importc: "pvm_sieve_cpu_nanoseconds", header: "pvm_sieve_clock.h".}

proc saveFile(path, data: string) =
  ## Artifact I/O is outside clocks; failure must terminate instead of sealing partial evidence.
  try:
    writeFile(path, data)
  except:
    echo "FINAL_IO_FAILURE,", path
    quit 2


type HostContext = object
  ## Every callback observation remains owned independently until invocation retirement.
  calls: int
  write: bool
  dirty: bool
  snapshots: seq[Memory]

proc changed(memory: Memory, write: bool, call: int): Memory =
  ## Host writes one checked byte; its immutable source is never mutated through an alias.
  if not write: return memory
  let written = writeBytes(memory, MemoryAddress(65537), [byte(9+call)], MemoryByteLimit(1))
  assert written.error == MachineError.None
  written.value

proc host(context: var HostContext, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## Literal ordered source PCs and host IDs discriminate skipped/reordered checkpoints.
  assert stopped.exit == StepExit.Host and uint64(stopped.hostCall) == 0
  let cpu = stopped.machine.machineInfo.value
  let expectedPc = if context.dirty: (if context.calls == 0: 5'u64 else: 12'u64)
      else: uint64(context.calls*2)
  assert uint64(cpu.pc) == expectedPc and cpu.blockCharged
  inc context.calls
  let memory = stopped.machine.memoryOf.value
  context.snapshots.add(memory)
  var registers = cpu.registers
  registers[8] = RegisterValue(uint64(registers[8])+1)
  HostResponse(action: HostAction.Continue, gas: cpu.gas, gasDeficit: GasDeficit(0),
      registers: registers, memory: changed(memory, context.write, context.calls))

proc expected(memory: Memory, count: int, dirty, write, readOnly: bool, stage: int) =
  ## Validate every mapped byte and permission against literal construction rules, independent of engine comparisons.
  let images = memoryImages(memory).value
  assert images.len == count
  for page in 0..<images.len:
    let image {.cursor.} = images[page]
    assert uint32(image.index) == uint32(16+page)
    assert image.access == (if readOnly: PageAccess.ReadOnly else: PageAccess.ReadWrite)
    for offset in 0..<4096:
      var value = if offset == 0: byte(page and 255) else: 0'u8
      if page == 0:
        if offset == 0 and dirty and stage > 0: value = byte(if stage == 1: 1 else: 2)
        if offset == 1 and write:
          if stage == 2: value = 10
          elif stage == 3: value = 11
      assert image.bytes[offset] == value

proc persist(memory: Memory, name: string) =
  ## Retain complete raw page identities, permissions and bytes for independently auditable first/last observations.
  let images = memoryImages(memory).value
  var data = newStringOfCap(images.len*4101)
  for page in 0..<images.len:
    let image {.cursor.} = images[page]
    let ordinal = uint32(image.index)
    for octet in 0..<4: data.add(char(byte((ordinal shr (octet*8)) and 255)))
    data.add(char(if image.access == PageAccess.ReadOnly: 1 else: 2))
    for octet in image.bytes: data.add(char(octet))
  saveFile(getEnv("PVM_FINAL_OUTPUT") & "/" & name & ".ram", data)

proc components(plan: FlatPlan, memory: Memory, cpu: MachineInfo, count: int,
    dirty, write, readOnly, noHost: bool): array[7, int64] =
  ## Separate entry, execution, guest publication, host work, resumption, final publication and live entry bytes.
  result = default(array[7, int64])
  let occupied = getOccupiedMem()
  let before = cpuNs()
  var created = prepareFlatMemoryFrame(plan, memory, cpu)
  assert created.error == FlatError.None
  var frame = takeValue(created)
  result[0] = cpuNs()-before
  result[6] = int64(getOccupiedMem()-occupied)
  for ordinal in 0..<(if noHost: 0 else: 2):
    # A true no-host halt separates entry/final publication from checkpoint work.
    let call = ordinal+1
    let runStart = cpuNs()
    runFlat(frame, 100)
    result[1] += cpuNs()-runStart
    assert frame.reason == StepError.None and frame.exit == StepExit.Host
    let publishStart = cpuNs()
    let observed = observeFlatHostMemory(frame)
    result[2] += cpuNs()-publishStart
    let hostStart = cpuNs()
    let posterior = changed(observed, write, call)
    var registers = frame.info.registers
    registers[8] = RegisterValue(uint64(registers[8])+1)
    result[3] += cpuNs()-hostStart
    let resumeStart = cpuNs()
    assert resumeFlatHostMemory(frame, posterior, frame.info.gas, registers) == StepError.None
    result[4] += cpuNs()-resumeStart
  let runStart = cpuNs()
  runFlat(frame, 100)
  result[1] += cpuNs()-runStart
  assert frame.reason == StepError.None and frame.exit == StepExit.Halt
  let finalStart = cpuNs()
  let finalMemory = flatMemorySnapshot(frame)
  result[5] = cpuNs()-finalStart
  assert uint64(frame.info.gas) == (if noHost: 9978'u64 elif dirty: 9897'u64 else: 9899'u64)
  expected(finalMemory, count, dirty, write, readOnly, 3)
  checkFlatSource(frame)

proc validateInvocation(completed: StepResult, context: HostContext, initial: Machine,
    count, scenario, sample, repetition: int, dirty, write, readOnly, noHost: bool): Memory =
  ## Complete CPU/RAM/ordered-host validation and raw observations are outside all production-call clocks.
  result = default(Memory)
  assert completed.error == StepError.None and completed.value.exit == StepExit.Halt
  assert completed.value.backend == PvmBackend.Interpreted
  assert context.calls == (if noHost: 0 else: 2)
  let actual = completed.value.machine.machineInfo.value
  assert uint64(actual.pc) == 0 and actual.blockCharged and uint64(actual.gasDeficit) == 0
  assert uint64(actual.gas) == (if noHost: 9978'u64 elif dirty: 9897'u64 else: 9899'u64)
  var registers = initial.machineInfo.value.registers
  registers[8] = RegisterValue(if noHost: 1 else: 3)
  assert actual.registers == registers
  let finalMemory = completed.value.machine.memoryOf.value
  expected(finalMemory, count, dirty, write, readOnly, 3)
  if not noHost:
    # Retained pre-response snapshots must still describe their own first/second checkpoint stages.
    assert context.snapshots.len == 2
    expected(context.snapshots[0], count, dirty, write, readOnly, 1)
    expected(context.snapshots[1], count, dirty, write, readOnly, 2)
  if sample == 0 and repetition == 0:
    result = if noHost: finalMemory else: context.snapshots[0]
  if sample in [0, 12] and repetition == 0:
    persist(finalMemory, "memory-" & $count & "-" & $scenario & "-" & $sample)

proc main() =
  ## Mapped-page order and case order reverse together; each row retains three warmups and ten samples.
  if getEnv("PVM_FINAL_ASSERT") == "1": assert false, "final lifecycle checks enabled"
  let reverse = getEnv("PVM_FINAL_ORDER") == "reverse"
  let counts = if reverse: [4096, 1024, 64, 1] else: [1, 64, 1024, 4096]
  for count in counts:
    for ordinal in 0..<6:
      let scenario = if reverse: 5-ordinal else: ordinal
      let noHost = scenario == 0
      let dirty = scenario in [2, 4]
      let write = scenario in [3, 4]
      let readOnly = scenario == 5
      let wire = if noHost: @[0'u8, 0, 2, 50, 0, 1]
          elif dirty: @[0'u8, 0, 16, 59, 8, 0, 0, 1, 10, 0, 59, 8, 0, 0, 1, 10, 0, 50, 0, 161, 80]
          else: @[0'u8, 0, 6, 10, 0, 10, 0, 50, 0, 21]
      let source = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0)).value
      var images = newSeq[PageImage](count)
      for page in 0..<count:
        images[page] = PageImage(index: PageIndex(uint32(16+page)),
            access: if readOnly: PageAccess.ReadOnly else: PageAccess.ReadWrite)
        images[page].bytes[0] = byte(page and 255)
      let memory = captureMemory(images, PageLimit(uint32(count))).value
      var cpu = MachineInfo(pc: CodeAddress(0), gas: MachineGas(10000), gasDeficit: GasDeficit(0),
          registers: default(RegisterFile), blockCharged: false)
      cpu.registers[0] = RegisterValue(0xffff0000'u64)
      cpu.registers[8] = RegisterValue(1)
      let initial = captureMachine(source, memory, cpu).value
      let prepared = newPreparedProgram(source, defaultPreparedLimits(GasCycleLimit(1000)),
          PvmBackend.Interpreted).value
      var admitted = prepareFlatPlan(source, GasCycleLimit(1000), defaultFlatLimits(),
          allowNative = false)
      assert admitted.error == FlatError.None
      let plan = takeValue(admitted)
      var retained = default(Memory)
      for sample in 0..<13:
        var callNs, retireNs = 0'i64
        for repetition in 0..<8:
          var context = HostContext(calls: 0, write: write, dirty: dirty, snapshots: @[])
          let before = cpuNs()
          var completed = executeWithHost(initial, context, host, ExecutionStepLimit(100),
              HostCallLimit(2), prepared)
          callNs += cpuNs()-before
          # All temporary views die inside validation before the retirement clock starts.
          block:
            let saved = validateInvocation(completed, context, initial, count, scenario, sample,
                repetition, dirty, write, readOnly, noHost)
            if sample == 0 and repetition == 0: retained = saved
          let retirement = cpuNs()
          completed = default(StepResult)
          context = default(HostContext)
          retireNs += cpuNs()-retirement
        expected(retained, count, dirty, write, readOnly, 1)
        expected(memory, count, false, false, readOnly, 0)
        let phase = components(plan, memory, cpu, count, dirty, write, readOnly, noHost)
        echo "MEMORY,", count, ",", scenario, ",", sample, ",", callNs, ",", retireNs, ",", phase[
            0], ",", phase[1], ",", phase[2], ",", phase[3], ",", phase[4], ",", phase[5], ",",
                phase[6]
      assert preparedInfo(prepared).value.nativeOperations == 0
      let other = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0)).value
      assert execute(captureMachine(other, memory, cpu).value, ExecutionStepLimit(100),
          prepared).error == StepError.InvalidPreparedProgram
      var context = HostContext(calls: 0, write: write, dirty: dirty, snapshots: @[])
      assert executeWithHost(initial, context, host, ExecutionStepLimit(if noHost: 0 else: 1),
          HostCallLimit(2), prepared).error == StepError.StepLimitExceeded
      assert context.calls == (if noHost or dirty: 0 else: 1)
      assert uint64(initial.machineInfo.value.gas) == 10000
      expected(memory, count, false, false, readOnly, 0)
  echo "MEMORY_COMPLETE"

main()
