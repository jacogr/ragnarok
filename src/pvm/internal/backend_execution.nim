# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Included by step.nim so trusted publication and continuation validation stay private.
## Optional upstream execution keeps one resident instance across every synchronous host callback.

# This implementation fragment is included by step.nim; direct module audits have no private cursor.
when declared(ExecutionCursor):
  when defined(polkavmRuntime):
    type BackendEffect = object ## Copied private event metadata never owns a guest buffer.
      kind: StepExit
      callNumber: HostCallId
      callAddress: CodeAddress
      failedPage: PageAddress
    type BackendCursor = object ## Invocation-local borrowed cursor; the prepared owner retains the exclusive foreign lifetime.
      handle: PolkaHandle # Borrowed only while the prepared identity is leased.
      cpu: ExecutionCursor
      resident: Memory
      primed: bool
      selected: PvmBackend
      dirty: seq[PageIndex]
      dirtyBits: seq[uint64]
      pageLimit: PageLimit

    proc `=copy`(destination: var BackendCursor, source: BackendCursor) {.error.}
      ## Copying would alias one active foreign borrow and its invocation-local mutation state.
    proc `=dup`(source: BackendCursor): BackendCursor {.error.}
      ## Containers and implicit return duplication cannot share foreign execution state.
    proc backendStatus(status: cint): StepError =
      ## Preserve local capability refusals separately from guest exits and host errors.
      case status
      of 0: StepError.None
      of 2: StepError.BackendUnavailable
      of 4: StepError.BackendReentryUnsupported
      of 6: StepError.BackendCapabilityUnsupported
      else: StepError.BackendFailure # Invalid ABI inputs, upstream errors and caught unwinds expose no state.

    proc syncBackend(cursor: var BackendCursor): StepError =
      ## Copy only changed immutable host pages into a retained private instance; never recreate it on a callback.
      let before = pageIndices(cursor.resident)
      let after = pageIndices(cursor.cpu.memory)
      if after.error != MachineError.None: return StepError.InvalidMachine
      if uint64(after.value.len) > uint64(cursor.pageLimit): return StepError.InvalidMachine
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
      let changed = withReplacedPages(memory, updates)
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

    proc publishBackend(cursor: var BackendCursor, effect: BackendEffect): StepResult =
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
        prices: GasMemo): StepResult =
      ## Shared Nim gas rules surround real upstream instruction execution; local work never consumes protocol gas.
      while remaining > 0:
        dec remaining # Count every source attempt, including invalid PC, OOG, fault and host instructions.
        let decoded = instruction(cursor.cpu.program, cursor.cpu.info.pc)
        if decoded.error != ProgramError.None:
          cursor.cpu.info.pc = CodeAddress(0)
          return publishBackend(cursor, BackendEffect(kind: StepExit.Panic))
        let item = decoded.value
        if not cursor.cpu.info.blockCharged:
          let start = containingBlockStart(cursor.cpu.program, cursor.cpu.info.pc)
          if start.error != ProgramError.None: return StepResult(status: StepError.InvalidMachine)
          let priced = blockGas(prices, start.value)
          case priced.error
          of GasMemoError.None: discard # The exclusive source-bound memo retains only successful price facts.
          of GasMemoError.CycleLimitExceeded: return StepResult(
              status: StepError.GasCycleLimitExceeded)
          of GasMemoError.NegativeBranchTarget: return StepResult(
              status: StepError.NegativeBranchTarget)
          else: return StepResult(status: StepError.InvalidMachine)
          let needed = uint64(priced.value)
          if uint64(cursor.cpu.info.gas) < needed:
            return publishBackend(cursor, BackendEffect(kind: StepExit.OutOfGas))
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
          return publishBackend(cursor, BackendEffect(kind: (if event.kind ==
              1: StepExit.Panic else: StepExit.Halt)))
        of 3:
          if event.detail mod 4096 != 0: return StepResult(status: StepError.BackendFailure)
          return publishBackend(cursor, BackendEffect(kind: StepExit.Fault,
              failedPage: PageAddress(event.detail)))
        of 4:
          if item.opcode != 10 or uint32(uint64(item.x) and 0xffffffff'u64) != event.detail:
            return StepResult(status: StepError.BackendFailure)
          cursor.primed = false
          return publishBackend(cursor, BackendEffect(kind: StepExit.Host,
              callNumber: HostCallId(uint64(item.x)), callAddress: causing))
        else:
          return StepResult(status: StepError.BackendFailure) # An unknown ABI discriminator cannot fabricate a guest exit.
      StepResult(status: StepError.StepLimitExceeded)

    proc runBackendFallible[Context; Reason: enum](cursor: var BackendCursor, context: var Context,
        handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason] {.nimcall,
            raises: [].},
        stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit,
            prices: GasMemo): HostExecutionResult[Reason] =
      ## Borrow one exclusive resident owner while preserving callback refusals and checked continuation.
      var remaining = uint64(stepLimit)
      var calls = uint64(hostLimit)
      while true:
        let evaluated = backendBudget(cursor, remaining, prices)
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
          if not validPreparedHostResponse(reply.value, cursor.pageLimit):
            # Fallible response payloads share the same pre-publication admission as ordinary callbacks.
            return executionResult[Reason](StepResult(status: StepError.InvalidHostResponse))
          let applied = applyHostResponse(evaluated.value, reply.value)
          if applied.error != StepError.None or applied.value.exit != StepExit.Continued:
            return executionResult[Reason](applied)
          let resumed = sourceInfo(applied.value.machine, cursor.cpu.info, cursor.cpu.program,
              cursor.cpu.memory)
          if resumed != StepError.None: return executionResult[Reason](StepResult(status: resumed))
          let synced = syncBackend(cursor)
          if synced != StepError.None: return executionResult[Reason](StepResult(status: synced))

    proc runBackendInfallible[Context](cursor: var BackendCursor, context: var Context,
        handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall,
            raises: [].},
        stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit,
            prices: GasMemo): StepResult =
      ## Borrow the same resident owner and check every ordinary posterior response before resumption.
      var remaining = uint64(stepLimit)
      var calls = uint64(hostLimit)
      while true:
        let evaluated = backendBudget(cursor, remaining, prices)
        if evaluated.error != StepError.None or evaluated.value.exit != StepExit.Host:
          return evaluated
        if calls == 0: return StepResult(status: StepError.HostCallLimitExceeded)
        dec calls # Callback credit remains independent of instruction attempts and protocol gas.
        let reply = handler(context, evaluated.value)
        if not validPreparedHostResponse(reply, cursor.pageLimit):
          # Terminal replies obey the same owner ceiling before any posterior snapshot is published.
          return StepResult(status: StepError.InvalidHostResponse)
        let applied = applyHostResponse(evaluated.value, reply)
        if applied.error != StepError.None or applied.value.exit !=
            StepExit.Continued: return applied
        let resumed = sourceInfo(applied.value.machine, cursor.cpu.info, cursor.cpu.program,
            cursor.cpu.memory)
        if resumed != StepError.None: return StepResult(status: resumed)
        let synced = syncBackend(cursor)
        if synced != StepError.None: return StepResult(status: synced)


  func preparationFailure(reason: PreparationError): StepError =
    ## Preserve optional capability refusals through ordinary execution convenience overloads.
    case reason
    of PreparationError.BackendNotBuilt: StepError.BackendNotBuilt
    of PreparationError.BackendUnavailable: StepError.BackendUnavailable
    of PreparationError.BackendProgramUnsupported: StepError.BackendProgramUnsupported
    of PreparationError.BackendRevisionMismatch: StepError.BackendRevisionMismatch
    of PreparationError.BackendCapabilityUnsupported: StepError.BackendCapabilityUnsupported
    of PreparationError.BackendFailure: StepError.BackendFailure
    else: StepError.InvalidPreparedProgram

  proc newPreparedProgram*(source: Program, limits: PreparedLimits,
      selected: PvmBackend): PreparationResult[PreparedProgram] =
    ## Engine choice is immutable and bound to this source/cache identity before any invocation.
    if selected in [PvmBackend.Interpreted, PvmBackend.Jit]: return prepareIndependent(source,
        limits, selected)
    when defined(polkavmRuntime):
      if not isJamProgram(source): return PreparationResult[PreparedProgram](
          status: PreparationError.BackendProgramUnsupported)
      if fromCString(polkaRevision()) != PolkaVmRevision:
        return PreparationResult[PreparedProgram](status: PreparationError.BackendRevisionMismatch)
      let prepared = prepareIndependent(source, limits, PvmBackend.Interpreted)
      if prepared.error != PreparationError.None: return prepared
      let length = codeLength(source).value
      if length > high(uint64) div 8: return PreparationResult[PreparedProgram](
          status: PreparationError.LimitExceeded)
      let prices = newGasMemo(source, GasMemoLimits(bytes: GasMemoByteLimit(length*8),
          cycles: limits.cycles))
      if prices.error != GasMemoError.None:
        return PreparationResult[PreparedProgram](status: PreparationError.LimitExceeded)
      let wire = programBytes(source)
      if wire.error != ProgramError.None or wire.value.len == 0:
        return PreparationResult[PreparedProgram](status: PreparationError.InvalidProgram)
      let data = prepared.value.data
      assert data != nil
      let created = polkaCreate((if selected == PvmBackend.PolkaInterpreted: 1'u32 else: 2'u32),
          unsafeAddr wire.value[0], csize_t(wire.value.len), data.foreign.handle)
      if created != 0:
        return PreparationResult[PreparedProgram](status: (if created == 2:
          PreparationError.BackendUnavailable elif created ==
              6: PreparationError.BackendCapabilityUnsupported else: PreparationError.BackendFailure))
      data.selected = selected
      data.prices = prices.value
      prepared
    else:
      PreparationResult[PreparedProgram](status: PreparationError.BackendNotBuilt)

  when defined(polkavmRuntime):
    proc borrowForeign(source: Machine, prepared: PreparedProgram,
        cursor: var BackendCursor): StepError =
      ## Borrow only under the caller's busy lease; reset excludes RAM/registers/continuations from prior calls.
      let data = prepared.data
      if data == nil or data.foreign.handle == nil: return StepError.InvalidPreparedProgram
      let valid = sourceInfo(source, cursor.cpu.info, cursor.cpu.program, cursor.cpu.memory)
      if valid != StepError.None: return valid
      if cursor.cpu.program != data.source: return StepError.InvalidPreparedProgram
      let count = memoryPageCount(cursor.cpu.memory)
      if count.error != MachineError.None or uint64(uint32(count.value)) > uint64(
          data.limits.resources.pages):
        return StepError.InvalidMachine
      let cleared = polkaReset(data.foreign.handle)
      if cleared != 0: return backendStatus(cleared)
      cursor.handle = data.foreign.handle
      cursor.selected = data.selected
      cursor.pageLimit = data.limits.resources.pages
      syncBackend(cursor)

  when defined(polkavmRuntime):
    proc retireForeignInvocation(prepared: PreparedProgram): StepError =
      ## Drop all guest state on success and refusal; a failed reset permanently retires the opaque owner.
      let data = prepared.data
      if data == nil or data.foreign.handle == nil: return StepError.InvalidPreparedProgram
      let cleared = polkaReset(data.foreign.handle)
      if cleared != 0:
        let handle = data.foreign.handle
        data.foreign.handle = nil
        discard polkaDestroy(handle)
        return StepError.BackendFailure
      StepError.None

  proc runForeignFrame(source: Machine, prepared: PreparedProgram,
      limit: ExecutionStepLimit): StepResult =
    ## Private foreign execution implements the same checked recursive result boundary.
    when defined(polkavmRuntime):
      var cursor = BackendCursor(handle: nil, cpu: default(ExecutionCursor), resident: default(
          Memory), primed: false)
      let data = prepared.data
      if data == nil: return StepResult(status: StepError.InvalidPreparedProgram)
      let valid = borrowForeign(source, prepared, cursor)
      if valid != StepError.None:
        discard retireForeignInvocation(prepared)
        return StepResult(status: valid)
      var remaining = uint64(limit)
      let answer = backendBudget(cursor, remaining, data.prices)
      let cleared = retireForeignInvocation(prepared)
      if cleared != StepError.None: return StepResult(status: StepError.BackendFailure)
      answer
    else:
      StepResult(status: StepError.BackendNotBuilt)

  proc runForeignHost[Context; Reason: enum](source: Machine, prepared: PreparedProgram,
      context: var Context, handler: proc(context: var Context,
          suspension: StepOutcome): HostResult[Reason] {.nimcall, raises: [].},
      steps: ExecutionStepLimit, calls: HostCallLimit): HostExecutionResult[Reason] =
    ## The shared prepared lease remains held across every fallible synchronous callback.
    when defined(polkavmRuntime):
      var cursor = BackendCursor(handle: nil, cpu: default(ExecutionCursor), resident: default(
          Memory), primed: false)
      let data = prepared.data
      if data == nil: return executionResult[Reason](StepResult(
          status: StepError.InvalidPreparedProgram))
      let valid = borrowForeign(source, prepared, cursor)
      if valid != StepError.None:
        discard retireForeignInvocation(prepared)
        return executionResult[Reason](StepResult(status: valid))
      let answer = runBackendFallible(cursor, context, handler, steps, calls, data.prices)
      let cleared = retireForeignInvocation(prepared)
      if cleared != StepError.None: return executionResult[Reason](StepResult(
          status: StepError.BackendFailure))
      answer
    else:
      executionResult[Reason](StepResult(status: StepError.BackendNotBuilt))

  proc runForeignHost[Context](source: Machine, prepared: PreparedProgram,
      context: var Context, handler: proc(context: var Context,
          suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
      steps: ExecutionStepLimit, calls: HostCallLimit): StepResult =
    ## Ordinary hosts use the same resident foreign instance and immutable callback observations.
    when defined(polkavmRuntime):
      var cursor = BackendCursor(handle: nil, cpu: default(ExecutionCursor), resident: default(
          Memory), primed: false)
      let data = prepared.data
      if data == nil: return StepResult(status: StepError.InvalidPreparedProgram)
      let valid = borrowForeign(source, prepared, cursor)
      if valid != StepError.None:
        discard retireForeignInvocation(prepared)
        return StepResult(status: valid)
      let answer = runBackendInfallible(cursor, context, handler, steps, calls, data.prices)
      let cleared = retireForeignInvocation(prepared)
      if cleared != StepError.None: return StepResult(status: StepError.BackendFailure)
      answer
    else:
      StepResult(status: StepError.BackendNotBuilt)
