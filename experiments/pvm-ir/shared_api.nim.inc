# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Experiment entry points keep prepared code separate from per-invocation CPU and memory state.

type
  PreparationByteLimit* = distinct uint64 ## Caller ceiling, capped at 4096 code bytes in this probe.
  PreparationInstructionLimit* = distinct uint64 ## Caller ceiling, capped at 256 decoded operations.
  PreparationError* {.pure.} = enum ## Failed preparation exposes no partial executable table.
    Uninitialized, None, InvalidProgram, ByteLimitExceeded, InstructionLimitExceeded
  PreparedProgram* = object ## Opaque acyclic owner retains only immutable program/operand storage.
    cache: InstructionCache
  PreparationResult* = object ## A success guard is required to extract the prepared owner.
    case status: PreparationError
    of None:
      completed: PreparedProgram
    else:
      discard

proc error*(r: PreparationResult): PreparationError =
  ## Inspect preparation status without exposing the discriminator for mutation.
  r.status

proc value*(r: PreparationResult): PreparedProgram {.requires: r.status == PreparationError.None.} =
  ## Retain the immutable table only after preparation completed within both resource ceilings.
  r.completed

proc prepareProgram*(owner: Program, byteLimit: PreparationByteLimit,
    instructionLimit: PreparationInstructionLimit): PreparationResult =
  ## Bound all new table allocations independently of the already-owned validated program bytes.
  let size = codeLength(owner)
  if size.error != ProgramError.None:
    return PreparationResult(status: PreparationError.InvalidProgram)
  if size.value > min(4096'u64, uint64(byteLimit)):
    return PreparationResult(status: PreparationError.ByteLimitExceeded)
  let maximum = min(256'u64, uint64(instructionLimit))
  var entries: seq[ProgramResult[Instruction]] = @[]
  var pc = 0'u64
  while pc < size.value:
    # Refuse before appending an operation that would exceed the bounded record count.
    if uint64(entries.len) >= maximum:
      return PreparationResult(status: PreparationError.InstructionLimitExceeded)
    let decoded = instruction(owner, CodeAddress(pc))
    if decoded.error != ProgramError.None:
      return PreparationResult(status: PreparationError.InvalidProgram)
    entries.add(decoded)
    pc += 1 + uint64(decoded.value.skip)
  var lookup = newSeq[uint16](int(size.value))
  for i in 0..<lookup.len:
    # Explicit zero denotes every unmarked operand byte, independent of allocator initialization.
    lookup[i] = 0
  for i in 0..<entries.len:
    # At most 256 records make the one-based index safe to narrow to uint16.
    lookup[int(uint64(entries[i].value.address))] = uint16(i + 1)
  let table = CacheData(owner: owner, entries: entries, lookup: lookup)
  PreparationResult(status: PreparationError.None, completed: PreparedProgram(cache: table))

proc preparedBytes*(plan: PreparedProgram): int =
  ## Report table payload, excluding allocator/sequence metadata and the existing program owner.
  let retained = plan.cache
  if retained == nil: return 0
  let table: CacheData = retained
  table.lookup.len * sizeof(uint16) + table.entries.len * sizeof(ProgramResult[Instruction])

proc executeShared*(plan: PreparedProgram, memory: Memory, info: MachineInfo,
    stepLimit: ExecutionStepLimit, gasLimit: GasCycleLimit): StepResult =
  ## The plan supplies program identity; callers provide only invocation state and local limits.
  let retained = plan.cache
  if retained == nil: return StepResult(status: StepError.InvalidMachine)
  let table: CacheData = retained
  let captured = captureTerminalMachine(table.owner, memory, info)
  if captured.error != MachineError.None: return StepResult(status: StepError.InvalidMachine)
  var remaining = uint64(stepLimit)
  var prices = BlockChargeCache(valid: false, start: CodeAddress(0), charge: BlockGas(0))
  executeBudget(captured.value, remaining, gasLimit, prices, plan.cache)
