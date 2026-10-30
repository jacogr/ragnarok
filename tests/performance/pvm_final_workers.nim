# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private frozen CI comparison of real initialized refinement/accumulation invocations; fixture manufacture is outside clocks.
import std/[assertions, syncio, envvars]
import ../../src/pvm/[program, machine, step, initialize]
import ../../src/pvm/gas/gas
import ../../src/pvm/host/fetch as host_fetch
import ../../src/pvm/refinement_exports
import ../../src/state/refinement/[bootstrap as refinement_bootstrap, outcome as refinement_outcome]
import ../../src/state/accumulation/[machine as accumulation_machine,
    dispatch as accumulation_dispatch, invocation as accumulation_invocation,
    service as accumulation_service]
import ../../src/codec/[bounded, composite, c2_records]
import ../../src/codec/work/report as work_report
import ../support/[pvm_refinement_outcome, pvm_accumulation_context, pvm_accumulation_program]
import ../../src/pvm/worker

proc cpuNs(): int64 {.importc: "pvm_sieve_cpu_nanoseconds", header: "pvm_sieve_clock.h".}

proc persistMachine(machine: Machine, name: string) =
  ## Full canonical CPU words and all mapped identities/permissions/bytes remain independently auditable.
  let cpu = machine.machineInfo.value
  var words = $uint64(cpu.pc) & "," & $uint64(cpu.gas) & "," & $uint64(cpu.gasDeficit) & "," &
      $cpu.blockCharged
  for value in cpu.registers: words.add("," & $uint64(value))
  writeFile(getEnv("PVM_FINAL_OUTPUT") & "/" & name & ".cpu", words & "\n")
  let images = memoryImages(machine.memoryOf.value).value
  var bytes = newStringOfCap(images.len*4101)
  for page in 0..<images.len:
    let image {.cursor.} = images[page]
    for octet in 0..<4: bytes.add(char(byte((uint32(image.index) shr (octet*8)) and 255)))
    bytes.add(char(if image.access == PageAccess.ReadOnly: 1 else: 2))
    for value in image.bytes: bytes.add(char(value))
  writeFile(getEnv("PVM_FINAL_OUTPUT") & "/" & name & ".ram", bytes)

proc preparationMetrics(source: Program): array[4, int64] =
  ## Keep all temporary prepared handles inside one lifetime before checking ARC retirement from its caller.
  let occupied = getOccupiedMem()
  let before = cpuNs()
  let prepared = newPreparedProgram(source, defaultPreparedLimits(GasCycleLimit(1000)),
      PvmBackend.Interpreted)
  let elapsed = cpuNs()-before
  let live = int64(getOccupiedMem())-int64(occupied)
  assert prepared.error == PreparationError.None
  let info = preparedInfo(prepared.value).value
  [elapsed, live, int64(info.codeBytes), int64(info.decodedInstructions)]

proc preparationProbe(source: Program, name: string) =
  ## Constructor live managed allocation is distinct from total allocation volume/RSS; return retires every temporary.
  var rows = ""
  for sample in 0..<13:
    # Three warmups and ten measured constructors include a separately bounded complete lifetime.
    let occupied = getOccupiedMem()
    let start = cpuNs()
    let observed = preparationMetrics(source)
    let lifetime = cpuNs()-start
    assert getOccupiedMem() == occupied
    rows.add($sample & "," & $observed[0] & "," & $lifetime & "," & $observed[1] & "," &
        $observed[2] & "," & $observed[3] & "\n")
  writeFile(getEnv("PVM_FINAL_OUTPUT") & "/" & name & ".preparation", rows)


type CallMetrics = object
  ## CPU phases are diagnostics; the caller also clocks this entire procedure through final ARC cleanup.
  prepare, invoke, retire: int64
  checksum: uint64

proc measuredRefinement(selected: RefinementFixtureSource, worker: ExecutionWorker,
    second: bool): CallMetrics =
  ## Actual public bootstrap/invocation, normalized output consumption and complete call-local retirement.
  result = default(CallMetrics)
  let before = cpuNs()
  var initialized = prepareRefinementBootstrap(selected.state, selected.package,
      FetchItemIndex(0), CoreIndex(5), selected.parameters, selected.limits, worker)
  result.prepare = cpuNs()-before
  assert initialized.error == RefinementBootstrapError.None
  var policy = refinementLimits()
  policy.steps = ExecutionStepLimit(128)
  policy.backend = PvmBackend.Interpreted
  let invoke = cpuNs()
  var completed = runRefinementInvocation(initialized.value, [], refinementInputs(),
      ExportOffset(0), policy, worker)
  result.invoke = cpuNs()-invoke
  assert completed.error == RefinementInvocationError.None
  block:
    # All observer aliases end before the explicit production-owner retirement timer.
    let bytes = completed.value.refinementOutput.value
    let info = completed.value.refinementInfo.value
    assert bytes == (if second: @[31'u8, 32, 33] else: @[21'u8, 22, 23])
    assert info.kind == WorkKind.Success and uint64(info.gasUsed) == 158
    result.checksum = uint64(info.gasUsed)+uint64(bytes[0])
  let retirement = cpuNs()
  completed = default(RefinementInvocationResult[RefinementInvocation])
  initialized = default(RefinementBootstrapResult[PreparedRefinementBootstrap])
  result.retire = cpuNs()-retirement

proc admitAccumulation(selected: AccumulationFixtureSource): PreparedAccumulationInvocation =
  ## Resolve the actual service/code against its original state, then admit the collision-checked invocation.
  let service = prepareAccumulationService(selected.inputs, selected.index, selected.state,
      selected.slot, selected.config)
  assert service.error == AccumulationServiceError.None
  let invocation = prepareAccumulationInvocation(service.value, selected.entropy, selected.limit)
  assert invocation.error == AccumulationInvocationError.None
  invocation.value

proc measuredAccumulation(selected: AccumulationFixtureSource, worker: ExecutionWorker,
    alternate: bool): CallMetrics =
  ## Actual public initialization/dispatch and full terminal CPU consumption, with no escaping RAM/context owner.
  result = default(CallMetrics)
  let limits = InitializationLimits(envelope: InitializationByteLimit(4096),
      program: ProgramByteLimit(256), jumps: JumpCountLimit(0), pages: PageLimit(5))
  let before = cpuNs()
  var admitted = admitAccumulation(selected)
  var initialized = initializeAccumulationMachine(admitted, limits, worker)
  result.prepare = cpuNs()-before
  assert initialized.error == AccumulationMachineError.None
  let fetch = FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
      operand: OperandLimits(maxBytes: ByteLimit(132)))
  let invoke = cpuNs()
  var completed = executeAccumulationMachine(initialized.value, pvmParameters(), fetch,
      MemoryByteLimit(0), ExecutionStepLimit(128), HostCallLimit(4), GasCycleLimit(1000),
      pvmContextConfig(), backend = PvmBackend.Interpreted, worker = worker)
  result.invoke = cpuNs()-invoke
  assert completed.error == AccumulationDispatchError.None and completed.value.exit == StepExit.Halt
  assert completed.value.backend == PvmBackend.Interpreted
  block:
    # The independent literal terminal state is checked without retaining a handle across cleanup.
    let source = initialized.value.accumulationMachine.value
    let cpu = completed.value.machine.machineInfo.value
    var expectedRegisters = source.machineInfo.value.registers
    expectedRegisters[3] = RegisterValue(if alternate: 40 else: 39)
    expectedRegisters[7] = RegisterValue(9842)
    assert uint64(cpu.pc) == 0 and cpu.blockCharged and uint64(cpu.gasDeficit) == 0
    assert uint64(cpu.gas) == 9842 and cpu.registers == expectedRegisters
    result.checksum = uint64(cpu.gas)+uint64(cpu.registers[3])
  let retirement = cpuNs()
  completed = default(AccumulationDispatchResult)
  initialized = default(AccumulationMachineResult[PreparedAccumulationMachine])
  admitted = default(PreparedAccumulationInvocation)
  result.retire = cpuNs()-retirement

proc main() =
  ## Fixture manufacture and complete retained-state qualification precede every measured series.
  var body: seq[seq[byte]] = @[]
  for index in 0..<40: body.add(@[51'u8, 3, byte(index)])
  body.add(@[10'u8, 0])
  var refinementCode = body
  refinementCode.add(refinementImmediate(7, 196608))
  refinementCode.add(refinementImmediate(8, 3))
  refinementCode.add(@[50'u8, 0])
  var accumulationCode = body
  accumulationCode.add(@[50'u8, 0])
  var alternateRefinement: seq[seq[byte]] = @[]
  var alternateAccumulation: seq[seq[byte]] = @[]
  for index in 0..<40:
    let value = byte(if index == 39: 40 else: index)
    alternateRefinement.add(@[51'u8, 3, value])
    alternateAccumulation.add(@[51'u8, 3, value])
  alternateRefinement.add(@[10'u8, 0])
  alternateRefinement.add(refinementImmediate(7, 196608))
  alternateRefinement.add(refinementImmediate(8, 3))
  alternateRefinement.add(@[50'u8, 0])
  alternateAccumulation.add(@[10'u8, 0])
  alternateAccumulation.add(@[50'u8, 0])
  # Synthetic complete sources are created once before the actual production bootstrap/initialization clocks.
  let firstRefinement = refinementFixtureSource(refinementCode)
  let otherRefinement = refinementFixtureSource(refinementCode, writable = @[31'u8, 32, 33])
  let firstAccumulation = pvmBootstrapSource(guestEnvelope(accumulationCode), 10000,
      includeContexts = true)
  let otherAccumulation = pvmBootstrapSource(guestEnvelope(accumulationCode, @[91'u8]), 10000,
      includeContexts = true)
  let missedRefinement = refinementFixtureSource(alternateRefinement, writable = @[31'u8, 32, 33])
  let missedAccumulation = pvmBootstrapSource(guestEnvelope(alternateAccumulation, @[91'u8]), 10000,
      includeContexts = true)
  let retained = getEnv("PVM_FINAL_ROLE") == "retained"
  when not defined(pvmWorkerCandidate): assert not retained
  if getEnv("PVM_FINAL_ASSERT") == "1": assert false, "final worker checks enabled"

  for sample in 0..<1:
    for family in 0..<4:
      var prepareNs, invokeNs, retirementNs, ownerNs = 0'i64
      let occupiedBefore = getOccupiedMem()
      let startOwner = cpuNs()
      when defined(pvmWorkerCandidate):
        var worker = if retained: newExecutionWorker() else: default(ExecutionWorker)
      ownerNs += cpuNs()-startOwner
      var earlier = default(RefinementInvocation)
      var firstRam = default(Memory)
      var firstProgram = default(Program)
      var priorProgram = default(Program)
      for call in 0..<64:
        if family mod 2 == 0:
          let selected = if call mod 2 == 0: firstRefinement elif family <
              2: otherRefinement else: missedRefinement
          let prepareStart = cpuNs()
          when defined(pvmWorkerCandidate):
            var initialized = prepareRefinementBootstrap(selected.state, selected.package,
                FetchItemIndex(0), CoreIndex(5), selected.parameters, selected.limits, worker)
          else:
            var initialized = prepareRefinementBootstrap(selected.state, selected.package,
                FetchItemIndex(0), CoreIndex(5), selected.parameters, selected.limits)
          prepareNs += cpuNs()-prepareStart
          assert initialized.error == RefinementBootstrapError.None
          let actualProgram = programOf(initialized.value.bootstrapMachine.value).value
          if call == 0:
            firstProgram = actualProgram
            if sample == 0: preparationProbe(actualProgram, "family-" & $family)
          when defined(pvmWorkerCandidate):
            if retained:
              if family < 2: assert actualProgram == firstProgram
              elif call > 0: assert actualProgram != priorProgram
          priorProgram = actualProgram
          var policy = refinementLimits()
          policy.steps = ExecutionStepLimit(128)
          policy.backend = PvmBackend.Interpreted
          let invokeStart = cpuNs()
          when defined(pvmWorkerCandidate):
            var completed = runRefinementInvocation(initialized.value, [], refinementInputs(),
                ExportOffset(0), policy, worker)
          else:
            var completed = runRefinementInvocation(initialized.value, [], refinementInputs(),
                ExportOffset(0), policy)
          invokeNs += cpuNs()-invokeStart
          assert completed.error == RefinementInvocationError.None
          let bytes = completed.value.refinementOutput.value
          assert bytes == (if call mod 2 == 0: @[21'u8, 22, 23] else: @[31'u8, 32, 33])
          assert completed.value.refinementInfo.value.kind == WorkKind.Success
          assert uint64(completed.value.refinementInfo.value.gasUsed) == 158 # Independent GP110 plus host48.
          if sample in [0, 12] and call in [0, 63]:
            let name = "refinement-" & $family & "-" & $sample & "-" & $call
            persistMachine(initialized.value.bootstrapMachine.value, name & "-initial")
            var output = $uint64(completed.value.refinementInfo.value.gasUsed) & "\n"
            for value in bytes: output.add(char(value))
            writeFile(getEnv("PVM_FINAL_OUTPUT") & "/" & name & ".normalized", output)
          if call == 0: earlier = completed.value
          assert earlier.refinementOutput.value == @[21'u8, 22, 23]
          let retirement = cpuNs()
          completed = default(RefinementInvocationResult[RefinementInvocation])
          initialized = default(RefinementBootstrapResult[PreparedRefinementBootstrap])
          retirementNs += cpuNs()-retirement
        else:
          let selected = if call mod 2 == 0: firstAccumulation elif family <
              2: otherAccumulation else: missedAccumulation
          let limits = InitializationLimits(envelope: InitializationByteLimit(4096),
              program: ProgramByteLimit(256), jumps: JumpCountLimit(0), pages: PageLimit(5))
          let prepareStart = cpuNs()
          when defined(pvmWorkerCandidate):
            var initialized = initializeAccumulationMachine(admitAccumulation(selected), limits, worker)
          else:
            var initialized = initializeAccumulationMachine(admitAccumulation(selected), limits)
          prepareNs += cpuNs()-prepareStart
          assert initialized.error == AccumulationMachineError.None
          let source = initialized.value.accumulationMachine.value
          let actualProgram = programOf(source).value
          if call == 0:
            firstProgram = actualProgram
            if sample == 0: preparationProbe(actualProgram, "family-" & $family)
          when defined(pvmWorkerCandidate):
            if retained:
              if family < 2: assert actualProgram == firstProgram
              elif call > 0: assert actualProgram != priorProgram
          priorProgram = actualProgram
          let fetch = FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
              operand: OperandLimits(maxBytes: ByteLimit(132)))
          let invokeStart = cpuNs()
          when defined(pvmWorkerCandidate):
            var completed = executeAccumulationMachine(initialized.value, pvmParameters(), fetch,
                MemoryByteLimit(0), ExecutionStepLimit(128), HostCallLimit(4), GasCycleLimit(1000),
                pvmContextConfig(), backend = PvmBackend.Interpreted, worker = worker)
          else:
            var completed = executeAccumulationMachine(initialized.value, pvmParameters(), fetch,
                MemoryByteLimit(0), ExecutionStepLimit(128), HostCallLimit(4), GasCycleLimit(1000),
                pvmContextConfig(), backend = PvmBackend.Interpreted)
          invokeNs += cpuNs()-invokeStart
          assert completed.error == AccumulationDispatchError.None and completed.value.exit == StepExit.Halt
          assert completed.value.backend == PvmBackend.Interpreted
          let cpu = completed.value.machine.machineInfo.value
          var expectedRegisters = source.machineInfo.value.registers
          expectedRegisters[3] = RegisterValue(if family >= 2 and call mod 2 != 0: 40 else: 39)
          expectedRegisters[7] = RegisterValue(9842)
          assert uint64(cpu.pc) == 0 and cpu.blockCharged and uint64(cpu.gasDeficit) == 0
          assert uint64(cpu.gas) == 9842 and cpu.registers == expectedRegisters # Independent GP110 plus host48.
          if sample in [0, 12] and call in [0, 63]:
            persistMachine(completed.value.machine, "accumulation-" & $family & "-" & $sample &
                "-" & $call)
          let memory = completed.value.machine.memoryOf.value
          let expected = source.memoryOf.value
          let actualPages = memoryImages(memory).value
          let originalPages = memoryImages(expected).value
          assert actualPages == originalPages # All initialized bytes and permissions remain literal no-store inputs.
          if call == 0: firstRam = memory
          assert firstRam.pageImage(PageIndex(48)).value.bytes[0] == 81
          assert memory.pageImage(PageIndex(48)).value.bytes[0] == (if call mod 2 == 0: 81 else: 91)
          let retirement = cpuNs()
          completed = default(AccumulationDispatchResult)
          initialized = default(AccumulationMachineResult[PreparedAccumulationMachine])
          retirementNs += cpuNs()-retirement
      let liveBytes = int64(getOccupiedMem())-int64(occupiedBefore)
      var preparations, hits = -1'i64
      when defined(pvmWorkerCandidate):
        if retained:
          let observed = workerInfo(worker)
          assert observed.error == PreparationError.None
          assert observed.value.preparations == (if family < 2: 1'u64 else: 64'u64)
          assert observed.value.hits == (if family < 2: 63'u64 else: 0'u64)
          assert observed.value.prepared.nativeOperations == 0
          preparations = int64(observed.value.preparations)
          hits = int64(observed.value.hits)
      let retireOwner = cpuNs()
      earlier = default(RefinementInvocation)
      firstRam = default(Memory)
      firstProgram = default(Program)
      priorProgram = default(Program)
      when defined(pvmWorkerCandidate): worker = default(ExecutionWorker)
      ownerNs += cpuNs()-retireOwner
      echo "WORKER_CONTROL,", family, ",", preparations, ",", hits


  let reversed = getEnv("PVM_FINAL_ORDER") == "reverse"
  for sample in 0..<13:
    for ordinal in 0..<4:
      # Counterbalanced case order complements the externally balanced same-image mode order.
      let family = if reversed: 3-ordinal else: ordinal
      var prepareNs, invokeNs, retireNs, ownerNs, lifecycleNs = 0'i64
      var checksum = 0'u64
      let occupied = getOccupiedMem()
      let create = cpuNs()
      var worker = if retained: newExecutionWorker() else: default(ExecutionWorker)
      ownerNs += cpuNs()-create
      for call in 0..<64:
        let second = call mod 2 != 0
        if family mod 2 == 0:
          # Real source authentication/decoding happens inside the timed public pipeline, not this selection.
          let selected = if not second: firstRefinement elif family <
              2: otherRefinement else: missedRefinement
          let before = cpuNs()
          let observed = measuredRefinement(selected, worker, second)
          lifecycleNs += cpuNs()-before
          prepareNs += observed.prepare
          invokeNs += observed.invoke
          retireNs += observed.retire
          checksum += observed.checksum
        else:
          # Alternating code is a deliberate single-slot miss case; changing RAM alone remains a hit.
          let selected = if not second: firstAccumulation elif family <
              2: otherAccumulation else: missedAccumulation
          let before = cpuNs()
          let observed = measuredAccumulation(selected, worker, family >= 2 and second)
          lifecycleNs += cpuNs()-before
          prepareNs += observed.prepare
          invokeNs += observed.invoke
          retireNs += observed.retire
          checksum += observed.checksum
      let liveBytes = int64(getOccupiedMem())-int64(occupied)
      var preparations, hits = -1'i64
      if retained:
        # Diagnostics are observed outside clocks and bind measured calls to actual admissions/hits.
        let info = workerInfo(worker)
        assert info.error == PreparationError.None
        assert info.value.preparations == (if family < 2: 1'u64 else: 64'u64)
        assert info.value.hits == (if family < 2: 63'u64 else: 0'u64)
        assert info.value.prepared.nativeOperations == 0
        preparations = int64(info.value.preparations)
        hits = int64(info.value.hits)
      let retire = cpuNs()
      worker = default(ExecutionWorker)
      ownerNs += cpuNs()-retire
      lifecycleNs += ownerNs
      assert getOccupiedMem() == occupied
      assert checksum == (if family mod 2 == 0: 11776'u64 elif family <
          2: 632384'u64 else: 632416'u64)
      echo "WORKER,", family, ",", sample, ",", prepareNs, ",", invokeNs, ",", retireNs, ",",
          ownerNs, ",", lifecycleNs, ",", liveBytes, ",", preparations, ",", hits, ",", checksum
  echo "WORKER_COMPLETE"

main()
