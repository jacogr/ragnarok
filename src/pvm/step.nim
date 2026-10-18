# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 charged register-only single steps; see spec/pvm-step.md.
## Exposes stepRegisters, guarded StepResult and StepOutcome carrying Continued/OutOfGas snapshots.
## Successful steps publish immutable snapshots; local failures publish no state or gas progress.

import ./[program, machine, registers, gas]

type
  # These are the only guest outcomes possible for implemented register-only mutations.
  StepExit* {.pure.} = enum
    Continued, OutOfGas
  # Both a normal step and guest out-of-gas are completed evaluations with an inspectable snapshot.
  StepOutcome* = object
    exit*: StepExit
    machine*: Machine
  # Local scope/resource/specification failures are distinct from guest execution outcomes.
  StepError* {.pure.} = enum
    Uninitialized, None, InvalidMachine, UnsupportedInstruction, GasCycleLimitExceeded,
    NegativeBranchTarget
  # Failed/default alternatives carry only their reason; no partial machine or charge escapes.
  StepResult* = object
    case status: StepError
    of None:
      # Immutable child handles form an acyclic graph without a back-reference to this result.
      completed: StepOutcome
    else:
      # Callers cannot inspect a fabricated zero/default execution state on failure.
      discard

# Inspect status without permitting success forgery or retagging.
func error*(r: StepResult): StepError = r.status
# Select successful evaluation before inspecting either guest outcome and its machine snapshot.
func value*(r: StepResult): StepOutcome {.requires: r.status == StepError.None.} = r.completed

# Evaluate exactly one supported instruction with GP whole-block gas precedence.
# limit bounds gas simulation only; finding the containing block is bounded by program byte size.
proc stepRegisters*(source: Machine, limit: GasCycleLimit): StepResult =
  let captured = machineInfo(source)
  # A default machine must not become an all-zero executable state.
  if captured.error != MachineError.None: return StepResult(status: StepError.InvalidMachine)
  let owner = programOf(source)
  let memory = memoryOf(source)
  # Child handles come from the same immutable snapshot, never caller-selected replacements.
  if owner.error != MachineError.None or memory.error != MachineError.None:
    return StepResult(status: StepError.InvalidMachine)
  let program = owner.value
  var info = captured.value
  let decoded = instruction(program, info.pc)
  # Snapshot construction validates PC; keep an explicit defensive failure for an invalid owner.
  if decoded.error != ProgramError.None: return StepResult(status: StepError.InvalidMachine)
  let item = decoded.value
  if not registerOnlyOpcode(item.opcode):
    # Capability rejection precedes evaluation and never fabricates a guest trap or gas debit.
    return StepResult(status: StepError.UnsupportedInstruction)
  if not info.blockCharged:
    # Interior entry still charges the entire containing block, including already-skipped instructions.
    let start = containingBlockStart(program, info.pc)
    if start.error != ProgramError.None: return StepResult(status: StepError.InvalidMachine)
    let charge = blockGas(program, start.value, limit)
    case charge.error
    of GasError.None:
      # Prove affordability before subtraction and before evaluating any register mutation.
      let needed = uint64(charge.value)
      if uint64(info.gas) < needed:
        return StepResult(status: StepError.None,
          completed: StepOutcome(exit: StepExit.OutOfGas, machine: source))
      info.gas = MachineGas(uint64(info.gas) - needed)
      info.blockCharged = true
    of GasError.CycleLimitExceeded:
      # Local simulation exhaustion is not guest out-of-gas and carries no partial debit.
      return StepResult(status: StepError.GasCycleLimitExceeded)
    of GasError.NegativeBranchTarget:
      # Preserve the pinned gas model's explicit negative-target specification gate.
      return StepResult(status: StepError.NegativeBranchTarget)
    else:
      # A captured valid PC must have a valid containing block.
      return StepResult(status: StepError.InvalidMachine)
  let mutation = evaluateRegisters(program, info.pc, info.registers)
  if mutation.error != RegisterError.None:
    # Defensive evaluator failure cannot publish the tentative copied gas state.
    return StepResult(status: StepError.UnsupportedInstruction)
  info.registers = mutation.value
  # A supported opcode is never a terminator; the validated blob guarantees a following instruction.
  # PC fits host int, so adding the bounded skip cannot overflow the uint64 address domain.
  info.pc = CodeAddress(uint64(info.pc) + 1 + uint64(item.skip))
  let updated = captureMachine(program, memory.value, info)
  if updated.error != MachineError.None:
    # Publish only a complete validated successor; the original snapshot remains untouched.
    return StepResult(status: StepError.InvalidMachine)
  StepResult(status: StepError.None,
    completed: StepOutcome(exit: StepExit.Continued, machine: updated.value))
