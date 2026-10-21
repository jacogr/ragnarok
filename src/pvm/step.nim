# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 charged single steps and bounded execution; see spec/pvm-step.md.
## Exposes scoped stepRegisters/stepControl/stepMemory, complete stepOnce, bounded execute,
## applyHostResponse and executeWithHost for bounded trusted host transitions including terminal gas deficits.
## HostResult/HostExecutionResult preserve enum-valued callback refusals separately from engine errors.
## Guarded StepResult snapshots expose read-only exit and selected faultPage/hostCall metadata.
## Successful steps publish immutable snapshots; local failures publish no state or gas progress.

import ./[program, machine, registers, gas]

type
  BlockChargeCache = object ## Private constant-space memo bound to one execution's immutable program and cycle limit.
    valid: bool
    start: CodeAddress
    charge: BlockGas
  HostCallId* = distinct uint64 ## Host identifiers occupy a register-width domain distinct from gas, addresses and step budgets.
  ExecutionStepLimit* = distinct uint64 ## Local scheduling policy bounds attempted instructions; it is not guest gas or a guest exit.
  HostCallLimit* = distinct uint64 ## Local dispatch budget, independent of attempted guest instructions and guest gas.
  StepExit* {.pure.} = enum ## Guest outcomes shared by single-step and bounded recursive execution.
    Continued, OutOfGas, Panic, Halt, Fault, Host
  StepOutcome* = object ## Normal and terminal guest outcomes are completed evaluations with an inspectable snapshot.
    machine*: Machine
    case kind: StepExit
    of Fault:
      # Only a fault carries a physical aligned page address; no default page is fabricated.
      failedPage: PageAddress
    of Host:
      # The sign-extended instruction immediate retains its complete register-width bit pattern.
      callNumber: HostCallId
      # Bind the suspension to its causing PC, including adjacent identical host calls.
      callAddress: CodeAddress
    else:
      # Normal, terminal and gas outcomes have no fault metadata.
      discard
  HostAction* {.pure.} = enum ## Host continuations and terminal requests are separate from guest fault/host suspension reasons.
    Uninitialized, Continue, Halt, Panic, OutOfGas
  HostResponse* = object ## A trusted host supplies posterior gas/registers/memory; it cannot choose PC, code or charged flag.
 ## Memory remains an immutable retained owner, while registers are copied by value.
    action*: HostAction
    gas*: MachineGas
    # Reserved-zero compatibility field; all current host actions carry unsigned gas.
    gasDeficit*: GasDeficit
    registers*: RegisterFile
    memory*: Memory
  StepError* {.pure.} = enum ## Local scope/resource/specification failures are distinct from guest execution outcomes.
    Uninitialized, None, InvalidMachine, UnsupportedInstruction, GasCycleLimitExceeded,
    NegativeBranchTarget, AmbiguousAccessOrder, StepLimitExceeded, InvalidHostSuspension,
      InvalidHostResponse, HostCallLimitExceeded
  StepResult* = object ## Failed/default alternatives carry only their reason; no partial machine or charge escapes.
    case status: StepError
    of None:
      # Immutable child handles form an acyclic graph without a back-reference to this result.
      completed: StepOutcome
    else:
      # Callers cannot inspect a fabricated zero/default execution state on failure.
      discard

type
  HostResultKind* {.pure.} = enum ## Callback selection is independent of the caller's enum: no numeric reason implies success.
    Uninitialized, Response, Failure
  HostResult*[Reason: enum] = object ## A fallible callback returns either posterior state or its own typed local refusal, never both.
    case selection: HostResultKind
    of Response:
      # Only this alternative retains a memory owner through the host response.
      response: HostResponse
    of Failure:
      # Enum-only reasons cannot smuggle partial machine state or owned resources into a failure.
      reason: Reason
    else:
      # A default callback result is malformed, not an implicit continuation.
      discard
  HostExecutionError* {.pure.} = enum ## Guest completion, engine refusal and callback refusal have separate guarded alternatives.
    Uninitialized, None, ExecutionFailure, HostFailure
  HostExecutionResult*[Reason: enum] = object ## Fallible execution preserves the callback's enum while exposing no machine on either failure.
    case status: HostExecutionError
    of None:
      # Completed guest outcomes retain the same immutable snapshot as ordinary StepResult.
      completed: StepOutcome
    of ExecutionFailure:
      # Scheduling, malformed replies and machine errors retain their existing StepError reason.
      executionReason: StepError
    of HostFailure:
      # Callback reasons are copied verbatim; their ordinal values have no engine-level meaning.
      hostReason: Reason
    else:
      # Default results have no outcome or selected error detail.
      discard

func hostSuccess*[Reason: enum](response: HostResponse): HostResult[Reason] =
  ## Construct a selected response; applyHostResponse still validates its fields before publication.
  HostResult[Reason](selection: HostResultKind.Response, response: response)
func hostFailure*[Reason: enum](reason: Reason): HostResult[Reason] =
  ## Construct a local callback refusal, preserving even the zero ordinal of the supplied enum.
  HostResult[Reason](selection: HostResultKind.Failure, reason: reason)
func kind*[Reason: enum](r: HostResult[Reason]): HostResultKind =
  ## Read callback selection without allowing discriminator mutation.
  r.selection
func value*[Reason: enum](r: HostResult[Reason]): HostResponse
    {.requires: r.selection == HostResultKind.Response.} =
  ## Select a callback response only after checking its kind.
  r.response
func failure*[Reason: enum](r: HostResult[Reason]): Reason
    {.requires: r.selection == HostResultKind.Failure.} =
  ## Select the local reason only after choosing the callback failure branch.
  r.reason
func error*[Reason: enum](r: HostExecutionResult[Reason]): HostExecutionError =
  ## Inspect fallible execution status without permitting result forgery.
  r.status
func value*[Reason: enum](r: HostExecutionResult[Reason]): StepOutcome
    {.requires: r.status == HostExecutionError.None.} =
  ## Extract completed guest state only after successful execution.
  r.completed
func executionError*[Reason: enum](r: HostExecutionResult[Reason]): StepError
    {.requires: r.status == HostExecutionError.ExecutionFailure.} =
  ## Extract an engine reason only from the selected execution-failure alternative.
  r.executionReason
func hostError*[Reason: enum](r: HostExecutionResult[Reason]): Reason
    {.requires: r.status == HostExecutionError.HostFailure.} =
  ## Extract the original callback enum only from a selected host failure.
  r.hostReason

func error*(r: StepResult): StepError =
  ## Inspect status without permitting success forgery or retagging.
  r.status
func value*(r: StepResult): StepOutcome {.requires: r.status == StepError.None.} =
  ## Select successful evaluation before inspecting either guest outcome and its machine snapshot.
  r.completed

func exit*(outcome: StepOutcome): StepExit =
  ## Read the guest reason without permitting an outcome to be retagged into a fabricated fault.
  outcome.kind
func faultPage*(outcome: StepOutcome): PageAddress {.requires: outcome.kind == StepExit.Fault.} =
  ## A page address is available only after selecting the fault alternative.
  outcome.failedPage

func hostCall*(outcome: StepOutcome): HostCallId {.requires: outcome.kind == StepExit.Host.} =
  ## Host-call metadata is meaningful only after selecting the Host alternative.
  outcome.callNumber

proc applyHostResponse*(suspension: StepOutcome, response: HostResponse): StepResult =
  ## Apply Psi_H's posterior host state to a recursive execute suspension at its causing ecalli.
  ## The host has already selected its action and gas; this function invokes no host or guest work.
  # Only recursive Host suspensions are valid inputs, never fault repair or terminal normalization.
  if suspension.exit != StepExit.Host:
    return StepResult(status: StepError.InvalidHostSuspension)
  let original = machineInfo(suspension.machine)
  let program = programOf(suspension.machine)
  if original.error != MachineError.None or program.error != MachineError.None:
    # Public outcome handles may be replaced by callers; never dereference invalid machine roots.
    return StepResult(status: StepError.InvalidMachine)
  if uint64(original.value.pc) != uint64(suspension.callAddress):
    # Single-step Host carries the following PC, even when it names an identical ecalli.
    return StepResult(status: StepError.InvalidHostSuspension)
  if uint64(original.value.gasDeficit) != 0:
    # A replaced terminal snapshot cannot authorize another host response.
    return StepResult(status: StepError.InvalidMachine)
  if uint64(response.gasDeficit) != 0:
    # Host gas is unsigned for every action; reserved nonzero deficit values are invalid.
    return StepResult(status: StepError.InvalidHostResponse)
  let item = instruction(program.value, original.value.pc)
  if item.error != ProgramError.None:
    # A terminal/import PC outside executable code cannot authorize a host response.
    return StepResult(status: StepError.InvalidHostSuspension)
  if item.value.opcode != 10 or uint64(item.value.x) != uint64(suspension.hostCall):
    # Keep the causing instruction and its full-width host identifier consistent.
    return StepResult(status: StepError.InvalidHostSuspension)
  var info = original.value
  info.gas = response.gas
  info.gasDeficit = response.gasDeficit
  info.registers = response.registers
  var exit = StepExit.Continued
  case response.action
  of HostAction.Continue:
    # The validated instruction bounds PC and skip; retain the existing block's charged flag.
    info.pc = CodeAddress(uint64(info.pc) + 1 + uint64(item.value.skip))
  of HostAction.Halt:
    # PR533 removes host Halt from the mutator domain; retain the enum spelling only for source compatibility.
    return StepResult(status: StepError.InvalidHostResponse)
  of HostAction.Panic:
    # Host panic likewise retains all posterior state and the causing host-call PC.
    exit = StepExit.Panic
  of HostAction.OutOfGas:
    # Preserve the unsigned posterior balance supplied by the trusted host.
    exit = StepExit.OutOfGas
  of HostAction.Uninitialized:
    # A default response is not an implicit continuation with zeroed registers or gas.
    return StepResult(status: StepError.InvalidHostResponse)
  let captured = (if exit == StepExit.Continued:
    captureMachine(program.value, response.memory, info)
    else: captureTerminalMachine(program.value, response.memory, info))
  if captured.error != MachineError.None:
    # Invalid response memory publishes no partially applied host mutation.
    return StepResult(status: StepError.InvalidHostResponse)
  StepResult(status: StepError.None, completed: StepOutcome(kind: exit, machine: captured.value))

# Exact scalar load/store instruction set; host response application executes no instruction.
func memoryOpcode(opcode: byte): bool =
  opcode in {30'u8..33'u8, 52'u8..62'u8, 70'u8..73'u8, 120'u8..130'u8}

# Apply one memory instruction to tentative copied state only after gas affordability is established.
# Failed preflight leaves registers and memory untouched; faultPage is meaningful only on Fault.
proc memoryMutation(item: Instruction, info: var MachineInfo, memory: var Memory,
    failedPage: var PageAddress): MachineError =
  let op = item.opcode
  let loading = op in {52'u8..58'u8, 124'u8..130'u8}
  var width = 1
  var signedLoad = false
  var base = 0'u64
  let offset = uint64(item.x)
  var stored = uint64(info.registers[int(byte(item.a))])
  if loading:
    # Load pairs alternate unsigned/signed at 8/16/32 bits, followed by an unsigned 64-bit load.
    let index = (if op <= 58: int(op) - 52 else: int(op) - 124)
    width = 1 shl (index div 2)
    signedLoad = index in [1, 3, 5]
    if op >= 124:
      # Indirect loads read the original B even when it aliases destination A.
      base = uint64(info.registers[int(byte(item.b))])
  elif op <= 33:
    # Absolute immediate stores use X as the address and Y as the stored bit pattern.
    width = 1 shl (int(op) - 30)
    stored = uint64(item.y)
  elif op <= 62:
    # Absolute register stores write the low bytes of A at X.
    width = 1 shl (int(op) - 59)
  elif op <= 73:
    # Indirect immediate stores use original A plus X and store Y.
    width = 1 shl (int(op) - 70)
    base = uint64(info.registers[int(byte(item.a))])
    stored = uint64(item.y)
  else:
    # Indirect register stores use original B plus X and store original A.
    width = 1 shl (int(op) - 120)
    base = uint64(info.registers[int(byte(item.b))])
  # Mask operands before addition: the sum fits 33 bits and preserves every cyclic physical address.
  let address = MemoryAddress((base and 0xffffffff'u64) + (offset and 0xffffffff'u64))
  if loading:
    # Preflight includes all bytes before a value or destination-register mutation becomes visible.
    let read = load(memory, address, AccessWidth(byte(width)))
    if read.error == MachineError.Fault:
      # Propagate the physical page reason without selecting a failed value.
      failedPage = read.faultPage
    if read.error != MachineError.None: return read.error
    var value = uint64(read.value)
    if signedLoad:
      # Signed widths are at most four bytes, so both shifts are strictly below 64.
      let bits = width * 8
      if (value and (1'u64 shl (bits - 1))) != 0:
        # Fill the high bits explicitly instead of relying on checked narrowing casts.
        value = value or (high(uint64) shl bits)
    info.registers[int(byte(item.a))] = RegisterValue(value)
  else:
    # The scalar store preflights the entire access and publishes an independent immutable owner.
    let written = store(memory, address, AccessWidth(byte(width)), RegisterValue(stored))
    if written.error == MachineError.Fault:
      # A failed cross-page store carries only its first failing page; no prefix bytes escape.
      failedPage = written.faultPage
    if written.error != MachineError.None: return written.error
    memory = written.value
  # All memory instructions are nonterminating; validated blobs guarantee a following instruction.
  info.pc = CodeAddress(uint64(info.pc) + 1 + uint64(item.skip))
  MachineError.None

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
proc stepDecoded(source: Machine, limit: GasCycleLimit, control, memoryAccess,
    hostCalls: bool, cache: var BlockChargeCache, decoded: ProgramResult[Instruction]): StepResult =
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
  if uint64(info.gasDeficit) != 0:
    # Terminal host debt must never be reinterpreted as executable zero gas.
    return StepResult(status: StepError.InvalidMachine)
  # Both private callers derive this result from the current machine's own program and PC.
  # Entry capture validates PC; terminal snapshots may intentionally have a non-executable PC.
  if decoded.error != ProgramError.None: return StepResult(status: StepError.InvalidMachine)
  let item = decoded.value
  if not registerOnlyOpcode(item.opcode) and
      not (control and (terminatesBlock(item.opcode) or item.opcode == 2)) and
      not (memoryAccess and memoryOpcode(item.opcode)) and not (hostCalls and item.opcode == 10):
    # Capability rejection precedes evaluation and never fabricates a guest trap or gas debit.
    return StepResult(status: StepError.UnsupportedInstruction)
  if not info.blockCharged:
    # Interior entry still charges the entire containing block, including already-skipped instructions.
    let start = containingBlockStart(program, info.pc)
    if start.error != ProgramError.None: return StepResult(status: StepError.InvalidMachine)
    # The private caller keeps one program/limit for this cache's entire lifetime.
    # A cache hit reuses simulation work only; affordability and debit below still run on every visit.
    var chargeError = GasError.None
    var needed = 0'u64
    if cache.valid and uint64(cache.start) == uint64(start.value):
      # A successful prior simulation in this invocation has exactly the same immutable input.
      needed = uint64(cache.charge)
    else:
      # Failed or locally refused simulations never populate the cache.
      let charge = blockGas(program, start.value, limit)
      chargeError = charge.error
      if chargeError == GasError.None:
        needed = uint64(charge.value)
        cache = BlockChargeCache(valid: true, start: start.value, charge: charge.value)
    case chargeError
    of GasError.None:
      # Prove affordability before subtraction and before evaluating any register mutation.
      if uint64(info.gas) < needed:
        return StepResult(status: StepError.None,
          completed: StepOutcome(kind: StepExit.OutOfGas, machine: source))
      info.gas = MachineGas(uint64(info.gas) - needed)
      info.blockCharged = true
    of GasError.CycleLimitExceeded:
      # Local simulation exhaustion is not guest out-of-gas and carries no partial debit.
      return StepResult(status: StepError.GasCycleLimitExceeded)
    of GasError.NegativeBranchTarget:
      # Retain the historical error alternative; current PolkaVM-aligned pricing does not emit it.
      return StepResult(status: StepError.NegativeBranchTarget)
    else:
      # A captured valid PC must have a valid containing block.
      return StepResult(status: StepError.InvalidMachine)
  var outcome = StepExit.Continued
  var changedMemory = memory.value
  var failedPage = PageAddress(0)
  if registerOnlyOpcode(item.opcode):
    # Register-only execution retains its existing scope and copied-register semantics.
    let mutation = evaluateRegisters(decoded, info.registers)
    if mutation.error != RegisterError.None:
      # Defensive evaluator failure cannot publish the tentative copied gas state.
      return StepResult(status: StepError.UnsupportedInstruction)
    info.registers = mutation.value
    info.pc = CodeAddress(uint64(info.pc) + 1 + uint64(item.skip))
  elif memoryOpcode(item.opcode):
    # Memory exceptions retain the charged gas/flag but never publish partial CPU or memory writes.
    case memoryMutation(item, info, changedMemory, failedPage)
    of MachineError.None:
      # A complete load/store has already updated only its specified state fields.
      discard
    of MachineError.Panic:
      # Protected-memory panic retains this instruction PC, unlike the trap instruction's increment.
      outcome = StepExit.Panic
    of MachineError.Fault:
      # A resumable fault preserves the precise physical page and successfully charged snapshot.
      outcome = StepExit.Fault
    of MachineError.AmbiguousAccessOrder:
      # Retain the historical error alternative for compatibility; current PolkaVM-aligned scalar inspection never emits it.
      return StepResult(status: StepError.AmbiguousAccessOrder)
    else:
      # Decoded widths and captured owners make other scalar API failures unreachable.
      return StepResult(status: StepError.InvalidMachine)
  elif item.opcode == 10:
    # Psi_1 ecalli inherits the default PC increment and leaves the current block prepaid.
    outcome = StepExit.Host
    info.pc = CodeAddress(uint64(info.pc) + 1 + uint64(item.skip))
  else:
    # This path is reachable only for explicitly supported control/no-op instructions.
    outcome = controlMutation(program, item, info)
  let updated = (if outcome in {StepExit.Panic, StepExit.Halt}:
    captureTerminalMachine(program, changedMemory, info)
    else: captureMachine(program, changedMemory, info))
  if updated.error != MachineError.None:
    # Publish only a complete validated successor; the original snapshot remains untouched.
    return StepResult(status: StepError.InvalidMachine)
  if outcome == StepExit.Fault:
    # Construct the sole guest alternative with fault metadata only after the snapshot is complete.
    return StepResult(status: StepError.None,
      completed: StepOutcome(kind: StepExit.Fault, machine: updated.value, failedPage: failedPage))
  if outcome == StepExit.Host:
    # Keep the full decoded immediate, including negative compact encodings, in its nominal domain.
    return StepResult(status: StepError.None, completed: StepOutcome(kind: StepExit.Host,
      machine: updated.value, callNumber: HostCallId(uint64(item.x)), callAddress: item.address))
  StepResult(status: StepError.None,
    completed: StepOutcome(kind: outcome, machine: updated.value))

# Single-step calls never inherit cached work across owners, scopes or local simulation limits.
proc stepImpl(source: Machine, limit: GasCycleLimit, control, memoryAccess,
    hostCalls: bool): StepResult =
  var cache = BlockChargeCache(valid: false, start: CodeAddress(0), charge: BlockGas(0))
  let owner = programOf(source)
  let current = machineInfo(source)
  if owner.error != MachineError.None or current.error != MachineError.None:
    # Absent roots cannot provide either a program or an executable instruction.
    return StepResult(status: StepError.InvalidMachine)
  let decoded = instruction(owner.value, current.value.pc)
  stepDecoded(source, limit, control, memoryAccess, hostCalls, cache, decoded)

proc stepRegisters*(source: Machine, limit: GasCycleLimit): StepResult =
  ## Preserve the register-only capability boundary for existing callers; no control opcode is accepted.
  stepImpl(source, limit, false, false, false)

proc stepControl*(source: Machine, limit: GasCycleLimit): StepResult =
  ## Execute one register/control instruction under Psi_1, including trap, unlikely and dynamic halt.
  ## Memory/host instructions remain local UnsupportedInstruction failures with no state progress.
  stepImpl(source, limit, true, false, false)

proc stepMemory*(source: Machine, limit: GasCycleLimit): StepResult =
  ## Execute one register/control/load/store instruction; host calls remain outside this capability.
  ## Memory fault/panic retains charged gas and original PC/registers/memory; local gates have no snapshot.
  stepImpl(source, limit, true, true, false)

proc stepOnce*(source: Machine, limit: GasCycleLimit): StepResult =
  ## Evaluate Psi_1 for every valid opcode, including host suspension; no host function is invoked here.
  ## Existing specification gates remain local failures and expose no partially updated machine.
  stepImpl(source, limit, true, true, true)

# Evaluate recursive Psi iteratively over an already validated program and captured machine.
# The shared remaining budget counts attempted instructions, including the exiting instruction.
# Each gas simulation is independently bounded by gasLimit. Local failures expose no partial progress.
proc executeBudget(source: Machine, remaining: var uint64, gasLimit: GasCycleLimit,
    chargeCache: var BlockChargeCache): StepResult =
  let original = machineInfo(source)
  let owner = programOf(source)
  let originalMemory = memoryOf(source)
  if original.error != MachineError.None or owner.error != MachineError.None or
      originalMemory.error != MachineError.None:
    # Absent owners are local API misuse, not a guest program failing deblob.
    return StepResult(status: StepError.InvalidMachine)
  if uint64(original.value.gasDeficit) != 0:
    # Reject terminal debt before even a zero-budget or invalid-PC execution path.
    return StepResult(status: StepError.InvalidMachine)
  let program = owner.value
  var current = source
  # Retain only the current immutable root; no host recursion or growing state history is required.
  while remaining > 0:
    # Consume each attempted instruction once, even when a Host exit returns to the dispatcher.
    dec remaining
    let prior = machineInfo(current).value
    let priorMemory = memoryOf(current).value
    let decoded = instruction(program, prior.pc)
    if decoded.error != ProgramError.None:
      # A trusted terminal/import snapshot may have an invalid PC: Psi's deblob branch panics uncharged.
      var stopped = prior
      stopped.pc = CodeAddress(0)
      let captured = captureTerminalMachine(program, priorMemory, stopped)
      if captured.error != MachineError.None:
        # Never expose a fabricated normalized state if ownership validation fails.
        return StepResult(status: StepError.InvalidMachine)
      return StepResult(status: StepError.None,
        completed: StepOutcome(kind: StepExit.Panic, machine: captured.value))
    let evaluated = stepDecoded(current, gasLimit, true, true, true, chargeCache, decoded)
    if evaluated.error != StepError.None:
      # Tentative earlier steps are private snapshots; local gates/limits discard all accumulated progress.
      return evaluated
    var outcome = evaluated.value
    if outcome.exit == StepExit.Continued:
      # The next iteration observes precisely the completed instruction's immutable successor.
      current = outcome.machine
    else:
      # Psi distinguishes terminal normalization from resumable exits at the causing instruction.
      var stopped = machineInfo(outcome.machine).value
      var stoppedMemory = memoryOf(outcome.machine).value
      if outcome.exit in {StepExit.Panic, StepExit.Halt}:
        # Final panic/halt retains posterior registers and memory, including load-and-jump mutations.
        stopped.pc = CodeAddress(0)
      else:
        # Fault, out-of-gas and host retain prior PC/registers/memory but posterior gas and charged flag.
        stopped.pc = prior.pc
        stopped.registers = prior.registers
        stoppedMemory = priorMemory
      let captured = captureTerminalMachine(program, stoppedMemory, stopped)
      if captured.error != MachineError.None:
        # Only a complete normalized snapshot may accompany the copied exit metadata.
        return StepResult(status: StepError.InvalidMachine)
      outcome.machine = captured.value
      return StepResult(status: StepError.None, completed: outcome)
  # Exhaustion is a local policy refusal, never OutOfGas, a host call, or a resumable guest outcome.
  StepResult(status: StepError.StepLimitExceeded)

proc execute*(source: Machine, stepLimit: ExecutionStepLimit, gasLimit: GasCycleLimit): StepResult =
  ## Execute a guest-only segment with a fresh local instruction budget; Host is returned to the caller.
  var remaining = uint64(stepLimit)
  # A direct execution has its own memo, never inherited from another program or local policy.
  var chargeCache = BlockChargeCache(valid: false, start: CodeAddress(0), charge: BlockGas(0))
  executeBudget(source, remaining, gasLimit, chargeCache)

# Lift guest/engine results without confusing guest terminal exits with local host errors.
func executionResult[Reason: enum](evaluated: StepResult): HostExecutionResult[Reason] =
  if evaluated.error != StepError.None:
    # Preserve the original engine refusal, without accessing a failed StepResult payload.
    return HostExecutionResult[Reason](status: HostExecutionError.ExecutionFailure,
      executionReason: evaluated.error)
  HostExecutionResult[Reason](status: HostExecutionError.None, completed: evaluated.value)

# Advance a shared invocation budget to the next dispatch or terminal result.
# Dispatch credit is consumed before callbacks, identically for both public callback forms.
proc nextHost(current: Machine, remaining, calls: var uint64, gasLimit: GasCycleLimit,
    chargeCache: var BlockChargeCache): StepResult =
  let evaluated = executeBudget(current, remaining, gasLimit, chargeCache)
  if evaluated.error != StepError.None:
    # Engine refusals carry no partial machine state.
    return evaluated
  if evaluated.value.exit == StepExit.Host:
    # A host suspension can invoke external code only after reserving one dispatch allowance.
    if calls == 0:
      # Local dispatch limits do not consume guest gas or become guest OutOfGas exits.
      return StepResult(status: StepError.HostCallLimitExceeded)
    dec calls
  evaluated

proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason] {.nimcall,
        raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit,
        gasLimit: GasCycleLimit): HostExecutionResult[Reason] =
  ## Run Psi_H* with typed local callback refusals and one instruction budget across continuations.
  ## Context is exclusively borrowed for this synchronous call. Callback effects persist on local errors;
  ## callers requiring atomic external effects must stage their context. Neither callback nor context is retained.
  var remaining = uint64(stepLimit)
  var calls = uint64(hostLimit)
  var current = source
  # Host responses preserve this invocation's program and fixed simulation limit.
  # Scalar cached prices retain neither context nor callbacks and disappear on every return.
  var chargeCache = BlockChargeCache(valid: false, start: CodeAddress(0), charge: BlockGas(0))
  while true:
    # Iteration retains one current snapshot; the shared helper owns all guest/dispatch budget rules.
    let evaluated = nextHost(current, remaining, calls, gasLimit, chargeCache)
    if evaluated.error != StepError.None:
      # Local refusal exposes no machine progress; already-completed context mutations remain visible.
      return executionResult[Reason](evaluated)
    let stopped = evaluated.value
    if stopped.exit != StepExit.Host:
      # Guest terminal and fault exits pass through unchanged and never invoke the handler.
      return executionResult[Reason](evaluated)
    let reply = handler(context, stopped)
    case reply.kind
    of HostResultKind.Uninitialized:
      # A missing selection is malformed callback output, not a caller-chosen local refusal.
      return executionResult[Reason](StepResult(status: StepError.InvalidHostResponse))
    of HostResultKind.Failure:
      # Stop before applying a response or executing another instruction; return only the reason.
      return HostExecutionResult[Reason](status: HostExecutionError.HostFailure,
          hostReason: reply.failure)
    of HostResultKind.Response:
      # The existing application boundary validates all supplied posterior state.
      let applied = applyHostResponse(stopped, reply.value)
      if applied.error != StepError.None:
        # Malformed host replies are local failures, not fabricated guest panics or rollbacks.
        return executionResult[Reason](applied)
      if applied.value.exit != StepExit.Continued:
        # Host terminal replies retain posterior state at the causing PC, without another guest attempt.
        return executionResult[Reason](applied)
      current = applied.value.machine

proc executeWithHost*[Context](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, gasLimit: GasCycleLimit): StepResult =
  ## Preserve the response-only API with the same guest/dispatch scheduler and response application boundary.
  ## Context is borrowed synchronously; already-performed callback effects survive later local errors.
  var remaining = uint64(stepLimit)
  var calls = uint64(hostLimit)
  var current = source
  # Host responses preserve this invocation's program and fixed simulation limit.
  # Scalar cached prices retain neither context nor callbacks and disappear on every return.
  var chargeCache = BlockChargeCache(valid: false, start: CodeAddress(0), charge: BlockGas(0))
  while true:
    # All scheduling and charging happens in the same helper used by fallible callbacks.
    let evaluated = nextHost(current, remaining, calls, gasLimit, chargeCache)
    if evaluated.error != StepError.None:
      # Preserve the legacy local engine refusal without reading a failed payload.
      return evaluated
    let stopped = evaluated.value
    if stopped.exit != StepExit.Host:
      # Guest exits never invoke host callbacks.
      return evaluated
    let applied = applyHostResponse(stopped, handler(context, stopped))
    if applied.error != StepError.None:
      # Explicit posterior state must satisfy the existing host-response invariants.
      return applied
    if applied.value.exit != StepExit.Continued:
      # Terminal host replies finish immediately without another instruction attempt.
      return applied
    current = applied.value.machine
