# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 charged register and control-flow single steps; see spec/pvm-step.md.
## Exposes stepRegisters/stepControl and guarded StepResult snapshots with guest exit reasons.
## Successful steps publish immutable snapshots; local failures publish no state or gas progress.

import ./[program, machine, registers, gas]

type
  # Guest outcomes for this bounded subset of single-step execution.
  StepExit* {.pure.} = enum
    Continued, OutOfGas, Panic, Halt
  # Normal and terminal guest outcomes are completed evaluations with an inspectable snapshot.
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

# Test static destination membership without narrowing invalid or negative mathematical addresses.
proc blockTarget(program: Program, address: CodeAddress): bool =
  let checked = basicBlockStart(program, address)
  checked.error == ProgramError.None and checked.value

# Compare signed 64-bit bit patterns by flipping their sign bits, avoiding checked casts.
func signedLess(a, b: uint64): bool =
  (a xor 0x8000000000000000'u64) < (b xor 0x8000000000000000'u64)

# Evaluate the condition against the original register file; decoding already saturated register IDs.
func branchCondition(item: Instruction, registers: RegisterFile): bool =
  let a = uint64(registers[int(byte(item.a))])
  let b = (if item.opcode <= 90: uint64(item.x)
    else: uint64(registers[int(byte(item.b))]))
  case item.opcode
  of 81, 170:
    # Equality has identical signed and unsigned interpretations.
    a == b
  of 82, 171:
    # Inequality also compares raw register bit patterns.
    a != b
  of 83, 172:
    # Unsigned strict lower bound.
    a < b
  of 84:
    # Unsigned inclusive lower bound.
    a <= b
  of 85, 174:
    # Unsigned inclusive upper bound.
    a >= b
  of 86:
    # Unsigned strict upper bound.
    a > b
  of 87, 173:
    # Signed strict lower bound.
    signedLess(a, b)
  of 88:
    # Signed inclusive lower bound.
    not signedLess(b, a)
  of 89, 175:
    # Signed inclusive upper bound.
    not signedLess(a, b)
  else:
    # The only remaining conditional opcode is signed greater-than immediate (90).
    signedLess(b, a)

# Apply control mutations after gas charging; panic/halt still retain explicit load mutations.
# All operands are read before writes, including aliased load-and-dynamic-jump registers.
proc controlMutation(program: Program, item: Instruction,
    info: var MachineInfo): StepExit =
  let pc = uint64(info.pc)
  let next = CodeAddress(pc + 1 + uint64(item.skip))
  var target = next
  var valid = true
  var outcome = StepExit.Continued
  if item.opcode == 0:
    # Trap inherits the table's default PC increment even at the end of code in Psi_1.
    info.pc = next
    return StepExit.Panic
  elif item.opcode == 2:
    # Unlikely is a nonterminating no-op, preserving the prepaid block flag.
    info.pc = next
    return StepExit.Continued
  elif item.opcode in {50'u8, 180'u8}:
    # Dynamic addresses use original operands, wrapping to 32 bits after addition.
    let base = (if item.opcode == 50: item.a else: item.b)
    let offset = (if item.opcode == 50: item.x else: item.y)
    let address = (uint64(info.registers[int(byte(base))]) + uint64(offset)) and 0xffffffff'u64
    if address == 0xffff0000'u64:
      # The halt sentinel takes precedence over table bounds or table contents.
      outcome = StepExit.Halt
    elif address == 0 or (address and 1) != 0:
      # Zero and unaligned dynamic addresses cannot index the table.
      outcome = StepExit.Panic
    else:
      # Division avoids overflow in a table-length times alignment check.
      let found = jumpTarget(program, JumpIndex(address div 2 - 1))
      if found.error != ProgramError.None:
        # An out-of-table address is a guest panic, not a local failure.
        outcome = StepExit.Panic
      else:
        # Table entries themselves must name valid block starts.
        target = found.value
        valid = blockTarget(program, target)
  else:
    # Static offsets are mathematical integers; never wrap a negative destination into code.
    if item.opcode != 1:
      if item.displacement < 0 and uint64(-item.displacement) > pc:
        # A negative static target is outside the basic-block set.
        valid = false
      elif item.displacement < 0:
        # Subtract only after proving the magnitude fits the current PC.
        target = CodeAddress(pc - uint64(-item.displacement))
      else:
        # Validated PC is host-int bounded and the displacement is at most signed 32 bits.
        target = CodeAddress(pc + uint64(item.displacement))
    valid = valid and blockTarget(program, target)
    if item.opcode in {81'u8..90'u8, 170'u8..175'u8}:
      # Both successors must be valid, even when the condition would avoid the invalid one.
      valid = valid and blockTarget(program, next)
      if not branchCondition(item, info.registers):
        # Only the selected PC changes; validation above still considered the taken target.
        target = next
  if not valid:
    # Invalid static or table destinations retain the instruction's original PC.
    outcome = StepExit.Panic
  if item.opcode in {80'u8, 180'u8}:
    # The instruction table specifies this mutation even when the jump panics or halts.
    info.registers[int(byte(item.a))] = RegisterValue(uint64(item.x))
  if outcome == StepExit.Continued:
    # Every successful control transfer enters a block that must be charged next time.
    info.pc = target
    info.blockCharged = false
  outcome

# Evaluate exactly one supported instruction with GP whole-block gas precedence.
# limit bounds gas simulation only; finding the containing block is bounded by program byte size.
proc stepImpl(source: Machine, limit: GasCycleLimit, control: bool): StepResult =
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
  # Entry capture validates PC; terminal snapshots may intentionally have a non-executable PC.
  if decoded.error != ProgramError.None: return StepResult(status: StepError.InvalidMachine)
  let item = decoded.value
  if not registerOnlyOpcode(item.opcode) and
      not (control and (terminatesBlock(item.opcode) or item.opcode == 2)):
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
  var outcome = StepExit.Continued
  if registerOnlyOpcode(item.opcode):
    # Register-only execution retains its existing scope and copied-register semantics.
    let mutation = evaluateRegisters(program, info.pc, info.registers)
    if mutation.error != RegisterError.None:
      # Defensive evaluator failure cannot publish the tentative copied gas state.
      return StepResult(status: StepError.UnsupportedInstruction)
    info.registers = mutation.value
    info.pc = CodeAddress(uint64(info.pc) + 1 + uint64(item.skip))
  else:
    # This path is reachable only for explicitly supported control/no-op instructions.
    outcome = controlMutation(program, item, info)
  let updated = (if outcome in {StepExit.Panic, StepExit.Halt}:
    captureTerminalMachine(program, memory.value, info)
    else: captureMachine(program, memory.value, info))
  if updated.error != MachineError.None:
    # Publish only a complete validated successor; the original snapshot remains untouched.
    return StepResult(status: StepError.InvalidMachine)
  StepResult(status: StepError.None,
    completed: StepOutcome(exit: outcome, machine: updated.value))

# Preserve the register-only capability boundary for existing callers; no control opcode is accepted.
proc stepRegisters*(source: Machine, limit: GasCycleLimit): StepResult =
  stepImpl(source, limit, false)

# Execute one register/control instruction under Psi_1, including trap, unlikely and dynamic halt.
# Memory/host instructions remain local UnsupportedInstruction failures with no state progress.
proc stepControl*(source: Machine, limit: GasCycleLimit): StepResult =
  stepImpl(source, limit, true)
