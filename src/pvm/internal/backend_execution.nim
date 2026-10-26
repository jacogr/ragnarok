# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Included by step.nim so trusted publication and continuation validation stay private.
## Optional upstream execution keeps one resident instance across every synchronous host callback.

# This implementation fragment is included by step.nim; direct module audits have no private cursor.
when declared(ExecutionCursor):
  when defined(polkavmRuntime):
    type BackendCursor = object ## Stack-local exclusive foreign lifetime; never copied or published.
      handle: PolkaHandle
      cpu: ExecutionCursor
      resident: Memory
      primed: bool
      selected: PvmBackend
      dirty: seq[PageIndex]
      dirtyBits: seq[uint64]

    proc `=copy`(destination: var BackendCursor, source: BackendCursor) {.error.}
      ## Copying would duplicate the exclusive raw instance lifetime.
    proc `=dup`(source: BackendCursor): BackendCursor {.error.}
      ## Containers and implicit return duplication cannot share foreign execution state.
    proc `=destroy`(cursor: BackendCursor) =
      ## Normal paths close explicitly; exceptional unwinding still retires the opaque owner and Nim children.
      if cursor.handle != nil: discard polkaDestroy(cursor.handle)
      `=destroy`(cursor.cpu)
      `=destroy`(cursor.resident)
      `=destroy`(cursor.dirty)
      `=destroy`(cursor.dirtyBits)

    proc closeBackend(cursor: var BackendCursor): cint =
      ## Retire the sole foreign lifetime before destructor fallback, including failed creation paths.
      let handle = cursor.handle
      cursor.handle = nil
      polkaDestroy(handle)

    proc backendStatus(status: cint): StepError =
      ## Preserve local capability refusals separately from guest exits and host errors.
      case status
      of 0: StepError.None
      of 2: StepError.BackendUnavailable
      of 4: StepError.BackendReentryUnsupported
      else: StepError.BackendFailure # Invalid ABI inputs, upstream errors and caught unwinds expose no state.

    proc syncBackend(cursor: var BackendCursor): StepError =
      ## Copy only changed immutable host pages into a retained private instance; never recreate it on a callback.
      let before = pageIndices(cursor.resident)
      let after = pageIndices(cursor.cpu.memory)
      if after.error != MachineError.None: return StepError.InvalidMachine
      if before.error == MachineError.None:
        for index in before.value:
          if uint32(index) < 16: continue # Protected low-page bytes stay immutable in the Nim snapshot.
          if samePage(cursor.resident, cursor.cpu.memory, index): continue # Identity proves there is no removal.
          let prior = pageImage(cursor.resident, index).value
          let next = pageImage(cursor.cpu.memory, index).value
          if prior.access != PageAccess.Inaccessible and next.access == PageAccess.Inaccessible:
            let removed = polkaPage(cursor.handle, uint32(index)*4096, 0, nil, 0)
            if removed != 0: return backendStatus(
                removed) # Removal completes before a later host continuation runs.
      for index in after.value:
        if samePage(cursor.resident, cursor.cpu.memory,
            index): continue # Immutable identity proves unchanged bytes/permissions.
        var page = pageImage(cursor.cpu.memory, index).value
        if page.access == PageAccess.Inaccessible: continue # Retained inaccessible bytes stay solely in the Nim snapshot.
        if uint32(index) < 16: continue # Upstream and Nim always trap guest accesses here; preserve retained host bytes in Nim.
        let mapped = polkaPage(cursor.handle, uint32(index)*4096, uint32(ord(page.access)),
            addr page.bytes[0], 4096)
        if mapped != 0: return backendStatus(mapped)
      cursor.resident = cursor.cpu.memory
      StepError.None

    func compareBackendPage(left, right: PageIndex): int =
      ## Sort copied physical identities without moving any page payload or exposing mutable backing.
      if uint32(left) < uint32(right): -1
      elif uint32(left) > uint32(right): 1
      else: 0

    proc captureBackendMemory(cursor: var BackendCursor): StepError =
      ## Observe pages addressed by guest stores; changed pages become fresh immutable owned epochs.
      let memory = cursor.cpu.memory
      cursor.dirty.sort(compareBackendPage)
      var updates: seq[PageImage] = @[]
      for index in cursor.dirty:
        if uint32(index) < 16: continue # Protected-page traps cannot change bytes retained outside the foreign mapping.
        var page = pageImage(memory, index).value
        if page.access != PageAccess.ReadWrite: continue # Faulted attempts cannot have changed inaccessible/read-only bytes.
        let original = page.bytes
        let copied = polkaRead(cursor.handle, uint32(index)*4096, addr page.bytes[0], 4096)
        if copied != 0: return backendStatus(copied)
        if page.bytes != original:
          updates.add(page) # Copy only changed payloads; one final merge shares every untouched page.
      for index in cursor.dirty:
        let ordinal = uint32(index)
        cursor.dirtyBits[int(ordinal div 64)] = cursor.dirtyBits[int(ordinal div 64)] and not (
            1'u64 shl (ordinal mod 64))
      cursor.dirty.setLen(0) # Reuse bounded private tracking storage at the next publication epoch.
      let changed = withPages(memory, updates)
      if changed.error != MachineError.None: return StepError.BackendFailure
      cursor.cpu.memory = changed.value
      cursor.resident = changed.value
      StepError.None

    proc markBackendStore(cursor: var BackendCursor, decoded: ProgramResult[Instruction]) =
      ## Track at most two physical pages per scalar store before any aliased register changes.
      let operands = instructionMemoryOperands(decoded)
      if operands.width == 0 or operands.isLoad: return
      let indices = instructionRegisters(decoded)
      var base = 0'u64
      case operands.base
      of MemoryBase.A: base = uint64(cursor.cpu.info.registers[indices.aIndex])
      of MemoryBase.B: base = uint64(cursor.cpu.info.registers[indices.bIndex])
      of MemoryBase.None: discard # Absolute store addresses use only the decoded immediate.
      let address = (base and 0xffffffff'u64)+(uint64(decoded.value.x) and 0xffffffff'u64)
      let first = uint32((address and 0xffffffff'u64) div 4096)
      let last = uint32(((address+uint64(operands.width)-1) and 0xffffffff'u64) div 4096)
      if cursor.dirtyBits.len == 0: cursor.dirtyBits = newSeq[uint64](16384) # Fixed physical domain: 2^20 bits.
      for ordinal in [first, last]:
        let slot = int(ordinal div 64)
        let bit = 1'u64 shl (ordinal mod 64)
        if (cursor.dirtyBits[slot] and bit) == 0:
          cursor.dirtyBits[slot] = cursor.dirtyBits[slot] or bit
          cursor.dirty.add(PageIndex(ordinal)) # Deduplication bounds retained identities by the physical page domain.

    proc prepareBackend(cursor: var BackendCursor): StepError =
      ## Exact entry and complete registers are established before any guest instruction executes.
      var registers = default(array[13, uint64])
      for index in 0..<13: registers[index] = uint64(cursor.cpu.info.registers[index])
      let status = polkaPrepare(cursor.handle, uint32(uint64(cursor.cpu.info.pc)), addr registers[
          0], 13)
      cursor.primed = status == 0
      backendStatus(status)

    proc createBackend(source: Machine, selected: PvmBackend,
        cursor: var BackendCursor): StepError =
      ## Validate immutable source before transferring one opaque foreign lifetime into this invocation.
      if fromCString(polkaRevision()) != PolkaVmRevision: return StepError.BackendRevisionMismatch
      cursor.selected = selected
      let initialized = initializeCursor(source, cursor.cpu)
      if initialized != StepError.None: return initialized
      if not isJamProgram(cursor.cpu.program): return StepError.BackendProgramUnsupported
      let wire = programBytes(cursor.cpu.program)
      if wire.error != ProgramError.None or wire.value.len == 0: return StepError.InvalidMachine
      let status = polkaCreate(uint32(ord(selected)), unsafeAddr wire.value[0], csize_t(
          wire.value.len), cursor.handle)
      if status != 0: return backendStatus(status)
      syncBackend(cursor)

    proc publishBackend(cursor: var BackendCursor, effect: InstructionEffect): StepResult =
      ## Foreign memory is copied before private instance reuse; snapshots never borrow mutable Rust storage.
      let captured = captureBackendMemory(cursor)
      if captured != StepError.None: return StepResult(status: captured)
      let machine = captureTerminalMachine(cursor.cpu.program, cursor.cpu.memory, cursor.cpu.info)
      if machine.error != MachineError.None: return StepResult(status: StepError.InvalidMachine)
      case effect.kind
      of StepExit.Host:
        StepResult(status: StepError.None, completed: StepOutcome(machine: machine.value,
          engine: cursor.selected,
          kind: StepExit.Host, callNumber: effect.callNumber, callAddress: effect.callAddress))
      of StepExit.Fault:
        StepResult(status: StepError.None, completed: StepOutcome(machine: machine.value,
          engine: cursor.selected,
          kind: StepExit.Fault, failedPage: effect.failedPage))
      else:
        StepResult(status: StepError.None, completed: StepOutcome(machine: machine.value,
            engine: cursor.selected, kind: effect.kind))

    proc backendBudget(cursor: var BackendCursor, remaining: var uint64,
        cycles: GasCycleLimit, cache: var ExecutionCache): StepResult =
      ## Shared Nim gas rules surround real upstream instruction execution; local work never consumes protocol gas.
      while remaining > 0:
        dec remaining # Count every source attempt, including invalid PC, OOG, fault and host instructions.
        let decoded = instruction(cursor.cpu.program, cursor.cpu.info.pc)
        if decoded.error != ProgramError.None:
          cursor.cpu.info.pc = CodeAddress(0)
          return publishBackend(cursor, InstructionEffect(kind: StepExit.Panic))
        let item = decoded.value
        if not cursor.cpu.info.blockCharged:
          let start = containingBlockStart(cursor.cpu.program, cursor.cpu.info.pc)
          if start.error != ProgramError.None: return StepResult(status: StepError.InvalidMachine)
          var needed = 0'u64
          if not cachedCharge(cache, start.value, needed):
            let priced = blockGas(cursor.cpu.program, start.value, cycles)
            case priced.error
            of GasError.None:
              needed = uint64(priced.value)
              rememberCharge(cache, start.value, priced.value)
            of GasError.CycleLimitExceeded: return StepResult(
                status: StepError.GasCycleLimitExceeded)
            of GasError.NegativeBranchTarget: return StepResult(
                status: StepError.NegativeBranchTarget)
            else: return StepResult(status: StepError.InvalidMachine)
          if uint64(cursor.cpu.info.gas) < needed:
            return publishBackend(cursor, InstructionEffect(kind: StepExit.OutOfGas))
          cursor.cpu.info.gas = MachineGas(uint64(cursor.cpu.info.gas)-needed)
          cursor.cpu.info.blockCharged = true
        if not cursor.primed:
          let prepared = prepareBackend(cursor)
          if prepared != StepError.None: return StepResult(status: prepared)
        var event {.noinit.}: PolkaEvent
        event.kind = 0
        event.pc = 0
        event.detail = 0
        for index in 0..<13: event.registers[index] = 0 # Imported C arrays require element initialization in the pinned lowering.
        markBackendStore(cursor, decoded)
        let ran = polkaStep(cursor.handle, event)
        if ran != 0: return StepResult(status: backendStatus(ran))
        let causing = cursor.cpu.info.pc
        for index in 0..<13:
          cursor.cpu.info.registers[index] = RegisterValue(event.registers[index])
        case event.kind
        of 0:
          cursor.cpu.info.pc = CodeAddress(event.pc)
          if terminatesBlock(item.opcode): cursor.cpu.info.blockCharged = false
        of 1, 2:
          cursor.cpu.info.pc = CodeAddress(0) # Recursive final guest exits retain posterior register/memory state.
          return publishBackend(cursor, InstructionEffect(kind: (if event.kind ==
              1: StepExit.Panic else: StepExit.Halt)))
        of 3:
          if event.detail mod 4096 != 0: return StepResult(status: StepError.BackendFailure)
          return publishBackend(cursor, InstructionEffect(kind: StepExit.Fault,
              failedPage: PageAddress(event.detail)))
        of 4:
          if item.opcode != 10 or uint32(uint64(item.x) and 0xffffffff'u64) != event.detail:
            return StepResult(status: StepError.BackendFailure)
          cursor.primed = false
          return publishBackend(cursor, InstructionEffect(kind: StepExit.Host,
              callNumber: HostCallId(uint64(item.x)), callAddress: causing))
        else:
          return StepResult(status: StepError.BackendFailure) # An unknown ABI discriminator cannot fabricate a guest exit.
      StepResult(status: StepError.StepLimitExceeded)

    proc runBackendFallible[Context; Reason: enum](cursor: var BackendCursor, context: var Context,
        handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason] {.nimcall,
            raises: [].},
        stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit,
            gasLimit: GasCycleLimit): HostExecutionResult[Reason] =
      ## Borrow one exclusive resident owner while preserving callback refusals and checked continuation.
      var remaining = uint64(stepLimit)
      var calls = uint64(hostLimit)
      var cache = initExecutionCache()
      while true:
        let evaluated = backendBudget(cursor, remaining, gasLimit, cache)
        if evaluated.error != StepError.None or evaluated.value.exit != StepExit.Host:
          return executionResult[Reason](evaluated)
        if calls == 0: return executionResult[Reason](StepResult(
            status: StepError.HostCallLimitExceeded))
        dec calls # Host budget is spent before callback invocation, independently of gas and attempts.
        let reply = handler(context, evaluated.value)
        case reply.kind
        of HostResultKind.Uninitialized:
          return executionResult[Reason](StepResult(status: StepError.InvalidHostResponse))
        of HostResultKind.Failure:
          return HostExecutionResult[Reason](status: HostExecutionError.HostFailure,
              hostReason: reply.failure)
        of HostResultKind.Response:
          let applied = applyHostResponse(evaluated.value, reply.value)
          if applied.error != StepError.None or applied.value.exit != StepExit.Continued:
            return executionResult[Reason](applied)
          let resumed = initializeCursor(applied.value.machine, cursor.cpu)
          if resumed != StepError.None: return executionResult[Reason](StepResult(status: resumed))
          let synced = syncBackend(cursor)
          if synced != StepError.None: return executionResult[Reason](StepResult(status: synced))

    proc runBackendInfallible[Context](cursor: var BackendCursor, context: var Context,
        handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall,
            raises: [].},
        stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit,
            gasLimit: GasCycleLimit): StepResult =
      ## Borrow the same resident owner and check every ordinary posterior response before resumption.
      var remaining = uint64(stepLimit)
      var calls = uint64(hostLimit)
      var cache = initExecutionCache()
      while true:
        let evaluated = backendBudget(cursor, remaining, gasLimit, cache)
        if evaluated.error != StepError.None or evaluated.value.exit != StepExit.Host:
          return evaluated
        if calls == 0: return StepResult(status: StepError.HostCallLimitExceeded)
        dec calls # Callback credit remains independent of instruction attempts and protocol gas.
        let reply = handler(context, evaluated.value)
        let applied = applyHostResponse(evaluated.value, reply)
        if applied.error != StepError.None or applied.value.exit !=
            StepExit.Continued: return applied
        let resumed = initializeCursor(applied.value.machine, cursor.cpu)
        if resumed != StepError.None: return StepResult(status: resumed)
        let synced = syncBackend(cursor)
        if synced != StepError.None: return StepResult(status: synced)

  proc execute*(source: Machine, stepLimit: ExecutionStepLimit, gasLimit: GasCycleLimit,
      selected: PvmBackend): StepResult =
    ## Select one real engine explicitly; optional support never changes the independent default path.
    if selected == PvmBackend.Ragnarok: return execute(source, stepLimit, gasLimit)
    when defined(polkavmRuntime):
      var cursor = BackendCursor(handle: nil, cpu: default(ExecutionCursor), resident: default(
          Memory), primed: false)
      var evaluated = StepResult(status: createBackend(source, selected, cursor))
      if evaluated.status == StepError.None:
        var remaining = uint64(stepLimit)
        var cache = initExecutionCache()
        evaluated = backendBudget(cursor, remaining, gasLimit, cache)
      let closed = closeBackend(cursor) # Every success/refusal retires the sole stack-local owner.
      if closed != 0: return StepResult(status: StepError.BackendFailure)
      evaluated
    else:
      StepResult(status: StepError.BackendNotBuilt)

  proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
      handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason] {.nimcall,
          raises: [].},
      stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, gasLimit: GasCycleLimit,
      selected: PvmBackend): HostExecutionResult[Reason] =
    ## One selected resident guest engine calls ordinary Nim hosts with checked immutable observations.
    if selected == PvmBackend.Ragnarok:
      return executeWithHost(source, context, handler, stepLimit, hostLimit, gasLimit)
    when defined(polkavmRuntime):
      var cursor = BackendCursor(handle: nil, cpu: default(ExecutionCursor), resident: default(
          Memory), primed: false)
      let initialized = createBackend(source, selected, cursor)
      var evaluated = executionResult[Reason](StepResult(status: initialized))
      if initialized == StepError.None:
        evaluated = runBackendFallible(cursor, context, handler, stepLimit, hostLimit, gasLimit)
      let closed = closeBackend(cursor)
      if closed != 0: return executionResult[Reason](StepResult(status: StepError.BackendFailure))
      evaluated
    else:
      executionResult[Reason](StepResult(status: StepError.BackendNotBuilt))

  proc backendAvailability*(selected: PvmBackend): StepError =
    ## Check actual pinned engine/sandbox availability before application resources or guest effects open.
    if selected == PvmBackend.Ragnarok: return StepError.None
    when defined(polkavmRuntime):
      if fromCString(polkaRevision()) != PolkaVmRevision: return StepError.BackendRevisionMismatch
      var raw = [0'u8, 0, 1, 0, 1] # Valid one-instruction JAM trap module; this probe executes no guest.
      var handle: PolkaHandle = nil
      let created = polkaCreate(uint32(ord(selected)), addr raw[0], 5, handle)
      let closed = polkaDestroy(handle)
      if closed != 0: return StepError.BackendFailure
      backendStatus(created)
    else:
      StepError.BackendNotBuilt

  proc executeWithHost*[Context](source: Machine, context: var Context,
      handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall,
          raises: [].},
      stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, gasLimit: GasCycleLimit,
      selected: PvmBackend): StepResult =
    ## Infallible callbacks share resident budgeting and checked replies without a closure or retained context pointer.
    if selected == PvmBackend.Ragnarok:
      return executeWithHost(source, context, handler, stepLimit, hostLimit, gasLimit)
    when defined(polkavmRuntime):
      var cursor = BackendCursor(handle: nil, cpu: default(ExecutionCursor), resident: default(
          Memory), primed: false)
      let initialized = createBackend(source, selected, cursor)
      var evaluated = StepResult(status: initialized)
      if initialized == StepError.None:
        evaluated = runBackendInfallible(cursor, context, handler, stepLimit, hostLimit, gasLimit)
      let closed = closeBackend(cursor)
      if closed != 0: return StepResult(status: StepError.BackendFailure)
      evaluated
    else:
      StepResult(status: StepError.BackendNotBuilt)
