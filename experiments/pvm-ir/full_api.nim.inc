# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete prepared execution binds decoded code and a fixed pricing policy to an exact owner.
type
  PricingMode* {.pure.} = enum ## Lazy learns only reached successful prices; Complete prices every block before admission.
    Lazy, Complete
  PreparedCodeLimit* = distinct uint64 ## Maximum admitted code bytes; not interchangeable with record or payload counts.
  PreparedOperationLimit* = distinct uint64 ## Maximum retained decoded instructions.
  PreparedPayloadLimit* = distinct uint64 ## Combined logical code/price bytes, excluding allocation metadata and spare capacity.
  PreparedBlockLimit* = distinct uint64 ## Maximum statically enumerated blocks before any pricing allocation.
  PreparedLimits* = object ## Logical payload/work ceilings exclude allocator metadata/capacity and never denote guest gas.
    codeBytes*: PreparedCodeLimit
    instructions*: PreparedOperationLimit
    bytes*: PreparedPayloadLimit
    blocks*: PreparedBlockLimit
    cycles*: GasCycleLimit
    pricing*: PricingMode
  PreparedError* {.pure.} = enum ## Default and failed alternatives expose no runnable partial state.
    Uninitialized, None, InvalidProgram, CodeLimit, InstructionLimit, PriceLimit,
    PriceCycleLimit, InvalidInput, WrongOwner
  PreparedResult*[T] = object ## The success contract guards the private generic payload.
    case status: PreparedError
    of None: completed: T
    else: discard
  PreparedExecution* = object ## Immutable code and fixed policy; lazy handles share monotone facts and require exclusive synchronous use.
    operands: PreparedProgram
    complete: GasPlan
    lazy: GasMemo
    limits: PreparedLimits
    records, blocks, payload: uint64
  PreparedInvocation* = object ## Private immutable source binds one prepared owner to fresh CPU/memory values.
    code: PreparedExecution
    source: Machine
  PreparedInfo* = object ## Copied observations expose neither mutable table nor caller-changeable policy.
    codeBytes*, instructions*, blocks*, payloadBytes*, pricedBlocks*: uint64
    cycles*: GasCycleLimit
    pricing*: PricingMode

proc error*[T](r: PreparedResult[T]): PreparedError =
  ## Inspect only the reason; a refusal carries no completed value.
  r.status
proc value*[T](r: PreparedResult[T]): T {.requires: r.status == PreparedError.None.} =
  ## Retain a complete result only after selecting success.
  r.completed

proc defaultPreparedLimits*(pricing: PricingMode = PricingMode.Lazy): PreparedLimits =
  ## Fixed hard ceilings also apply when callers request larger limits.
  PreparedLimits(codeBytes: PreparedCodeLimit(1048576), instructions: PreparedOperationLimit(65535),
    bytes: PreparedPayloadLimit(16777216), blocks: PreparedBlockLimit(65535), cycles: GasCycleLimit(
        1000000), pricing: pricing)

proc prepareExecution*(owner: Program, limits: PreparedLimits): PreparedResult[PreparedExecution] =
  ## Count and prove the logical payload budget before allocating code or price storage.
  let extent = codeLength(owner)
  if extent.error != ProgramError.None or extent.value == 0:
    return PreparedResult[PreparedExecution](status: PreparedError.InvalidProgram)
  let length = extent.value
  if length > min(1048576'u64, uint64(limits.codeBytes)):
    return PreparedResult[PreparedExecution](status: PreparedError.CodeLimit)
  var pc = 0'u64
  var count = 0'u64
  var blocks = 0'u64
  var atStart = true
  while pc < length:
    # Admission counts all marked instructions, including unreachable code; no guest state exists yet.
    if count >= min(65535'u64, uint64(limits.instructions)):
      return PreparedResult[PreparedExecution](status: PreparedError.InstructionLimit)
    let item = instruction(owner, CodeAddress(pc))
    if item.error != ProgramError.None:
      return PreparedResult[PreparedExecution](status: PreparedError.InvalidProgram)
    if atStart:
      inc blocks
      if blocks > min(65535'u64, uint64(limits.blocks)):
        return PreparedResult[PreparedExecution](status: PreparedError.PriceLimit)
    let advance = 1'u64 + uint64(item.value.skip)
    if advance > length - pc:
      return PreparedResult[PreparedExecution](status: PreparedError.InvalidProgram)
    atStart = terminatesBlock(item.value.opcode)
    pc += advance
    inc count
  # Code <=1MiB and count<=65535 prove these native-size sums cannot wrap on supported hosts.
  let payload = length * 10 + count * uint64(sizeof(ProgramResult[Instruction]))
  if payload > min(16777216'u64, uint64(limits.bytes)):
    return PreparedResult[PreparedExecution](status: PreparedError.PriceLimit)
  let decoded = prepareProgram(owner, PreparationByteLimit(length), PreparationInstructionLimit(count))
  if decoded.error != PreparationError.None:
    return PreparedResult[PreparedExecution](status: PreparedError.InvalidProgram)
  var resultCode = PreparedExecution(operands: decoded.value, limits: limits,
    complete: default(GasPlan), lazy: default(GasMemo), records: count, blocks: blocks,
        payload: payload)
  if limits.pricing == PricingMode.Complete:
    # Eager policy refuses on any unpriceable block; failed preparation publishes neither prefix nor operands.
    let priced = newGasPlan(owner, GasPlanLimits(bytes: GasPlanByteLimit(length * 8),
      blocks: GasPlanBlockLimit(blocks), cycles: limits.cycles))
    if priced.error == GasPlanError.CycleLimitExceeded:
      return PreparedResult[PreparedExecution](status: PreparedError.PriceCycleLimit)
    if priced.error != GasPlanError.None:
      return PreparedResult[PreparedExecution](status: PreparedError.InvalidProgram)
    resultCode.complete = priced.value
  else:
    # Lazy admission does no simulation, preserving reachability-dependent runtime errors and refusals.
    let priced = newGasMemo(owner, GasMemoLimits(bytes: GasMemoByteLimit(length * 8),
        cycles: limits.cycles))
    if priced.error != GasMemoError.None:
      return PreparedResult[PreparedExecution](status: PreparedError.InvalidProgram)
    resultCode.lazy = priced.value
  PreparedResult[PreparedExecution](status: PreparedError.None, completed: resultCode)

proc preparedInfo*(code: PreparedExecution): PreparedResult[PreparedInfo] =
  ## Lazy occupancy is an observation, not mutable configuration; complete plans are immutable.
  let retained = code.operands.cache
  if retained == nil: return PreparedResult[PreparedInfo](status: PreparedError.InvalidInput)
  let table: CacheData = retained
  let size = codeLength(table.owner)
  if size.error != ProgramError.None:
    return PreparedResult[PreparedInfo](status: PreparedError.InvalidInput)
  var priced = code.blocks
  if code.limits.pricing == PricingMode.Lazy:
    let statistics = gasMemoInfo(code.lazy)
    if statistics.error != GasMemoError.None:
      return PreparedResult[PreparedInfo](status: PreparedError.InvalidInput)
    priced = statistics.value.pricedBlocks
  PreparedResult[PreparedInfo](status: PreparedError.None, completed: PreparedInfo(
    codeBytes: size.value, instructions: code.records, blocks: code.blocks,
    payloadBytes: code.payload,
    pricedBlocks: priced, cycles: code.limits.cycles, pricing: code.limits.pricing))

proc bindPrepared*(code: PreparedExecution, source: Machine): PreparedResult[PreparedInvocation] =
  ## Retain the exact source root only when its program is the prepared owner; caller state stays immutable.
  let retained = code.operands.cache
  if retained == nil: return PreparedResult[PreparedInvocation](status: PreparedError.InvalidInput)
  let table: CacheData = retained
  let owner = programOf(source)
  if owner.error != MachineError.None: return PreparedResult[PreparedInvocation](
      status: PreparedError.InvalidInput)
  if owner.value != table.owner: return PreparedResult[PreparedInvocation](
      status: PreparedError.WrongOwner)
  PreparedResult[PreparedInvocation](status: PreparedError.None,
    completed: PreparedInvocation(code: code, source: source))

proc bindPrepared*(code: PreparedExecution, memory: Memory, info: MachineInfo): PreparedResult[
    PreparedInvocation] =
  ## Build a fresh root from the privately retained program; invalid CPUs/memory remain typed refusals.
  let retained = code.operands.cache
  if retained == nil: return PreparedResult[PreparedInvocation](status: PreparedError.InvalidInput)
  let table: CacheData = retained
  let captured = captureTerminalMachine(table.owner, memory, info)
  if captured.error != MachineError.None:
    return PreparedResult[PreparedInvocation](status: PreparedError.InvalidInput)
  bindPrepared(code, captured.value)

proc executePrepared*(input: PreparedInvocation, stepLimit: ExecutionStepLimit): StepResult =
  ## Every call starts fresh attempt/memory state; only immutable code and successful pricing facts survive.
  if input.code.operands.cache == nil: return StepResult(status: StepError.InvalidMachine)
  var remaining = uint64(stepLimit)
  var prices = initBlockChargeCache()
  var cursor = default(ExecutionCursor)
  if input.code.limits.pricing == PricingMode.Complete:
    return executeBudget[true](input.source, remaining, input.code.limits.cycles,
      prices, input.code.operands.cache, cursor, false, input.code.complete)
  memoBudget(input.source, remaining, input.code.limits.cycles, prices,
    input.code.operands.cache, cursor, false, input.code.lazy)

proc preparedStep(input: PreparedInvocation, control, memoryAccess, hostCalls: bool): StepResult =
  ## Single-step capability, fault, charging and publication logic is the production body for either policy.
  let retained = input.code.operands.cache
  if retained == nil: return StepResult(status: StepError.InvalidMachine)
  let table: CacheData = retained
  let info = machineInfo(input.source)
  if info.error != MachineError.None: return StepResult(status: StepError.InvalidMachine)
  var prices = initBlockChargeCache()
  let decoded = cachedInstruction(table.owner, info.value.pc, retained)
  if input.code.limits.pricing == PricingMode.Complete:
    return stepDecoded[true](input.source, input.code.limits.cycles, control, memoryAccess,
      hostCalls, prices, decoded, input.code.complete)
  preparedMemoStep(input.source, input.code.limits.cycles, control, memoryAccess,
    hostCalls, prices, decoded, input.code.lazy)

proc stepRegisters*(input: PreparedInvocation): StepResult =
  ## Register-only capability retains production rejection precedence.
  preparedStep(input, false, false, false)
proc stepControl*(input: PreparedInvocation): StepResult =
  ## Control capability includes dynamic targets and guest termination.
  preparedStep(input, true, false, false)
proc stepMemory*(input: PreparedInvocation): StepResult =
  ## Memory capability preserves preflight atomicity and page-fault metadata.
  preparedStep(input, true, true, false)
proc stepOnce*(input: PreparedInvocation): StepResult =
  ## Full single-step execution may return Host without invoking a callback.
  preparedStep(input, true, true, true)

proc executeWithHost*[Context](input: PreparedInvocation, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit): StepResult =
  ## Context/callbacks are borrowed for this call; valid host continuations retain the prepared identity.
  if input.code.operands.cache == nil: return StepResult(status: StepError.InvalidMachine)
  if input.code.limits.pricing == PricingMode.Complete:
    return runSharedHostBody[Context, true, false](input.source, context, handler, stepLimit,
      hostLimit, input.code.limits.cycles, input.code.complete, default(GasMemo),
          input.code.operands.cache)
  runSharedHostBody[Context, false, true](input.source, context, handler, stepLimit,
    hostLimit, input.code.limits.cycles, default(GasPlan), input.code.lazy,
        input.code.operands.cache)

proc executeWithHost*[Context; Reason: enum](input: PreparedInvocation, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason] {.nimcall,
        raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit): HostExecutionResult[Reason] =
  ## Typed callback failures remain distinct from execution errors; performed context effects survive refusal.
  if input.code.operands.cache == nil:
    return executionResult[Reason](StepResult(status: StepError.InvalidMachine))
  if input.code.limits.pricing == PricingMode.Complete:
    return preparedFallibleBody[Context, Reason, true, false](input.source, context, handler,
      stepLimit, hostLimit, input.code.limits.cycles, input.code.complete, default(GasMemo),
          input.code.operands.cache)
  preparedFallibleBody[Context, Reason, false, true](input.source, context, handler,
    stepLimit, hostLimit, input.code.limits.cycles, default(GasPlan), input.code.lazy,
        input.code.operands.cache)
