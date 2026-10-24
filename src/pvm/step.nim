# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 charged single steps and bounded execution; see spec/pvm-step.md.
## Exposes scoped stepRegisters/stepControl/stepMemory, complete stepOnce, bounded execute,
## applyHostResponse and executeWithHost for bounded trusted host transitions including terminal gas deficits.
## HostResult/HostExecutionResult preserve enum-valued callback refusals separately from engine errors.
## Guarded StepResult snapshots expose read-only exit and selected faultPage/hostCall metadata.
## Successful steps publish immutable snapshots; local failures publish no state or gas progress.

import ./[program, machine, registers, gas, gas_plan, gas_memo]

type
  BlockChargeEntry = object ## One complete successful pipeline price belongs to this invocation's immutable program and cycle limit.
    valid: bool
    start: CodeAddress
    charge: BlockGas
  DynamicTargetEntry = object ## A validated dynamic ordinal/target fact belongs only to this invocation's immutable program.
    valid: bool
    index: JumpIndex
    target: CodeAddress
  SecondaryPrices = ref object ## A bounded private spill owner allocates only after four successful distinct dynamic prices.
    entries: array[128, BlockChargeEntry]
    replaceUpper: array[64, bool]
  ExecutionCache = object ## Invocation-local prices retain their policy; four exact-tagged dynamic targets never certify paid gas.
    valid: bool
    start: CodeAddress
    charge: BlockGas
    recent: array[3, BlockChargeEntry]
    next: range[0..2]
    secondary: nil SecondaryPrices
    targets: array[4, DynamicTargetEntry]
  DecodedSpill = ref object ## One bounded invocation-local spill retains copied scalar results, never a program or mutable machine.
    entries: array[4096, ProgramResult[Instruction]]
    replaceUpper: array[2048, bool]
  InstructionCache = object ## Thirty-two genuine scalar results retain their natural first slot; paired alternatives and bounded replacement belong only to this invocation.
    entries: array[32, ProgramResult[Instruction]]
    replaceUpper: array[16, bool]
    spill: nil DecodedSpill
    misses: range[0..32768]
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
      InvalidHostResponse, HostCallLimitExceeded, InvalidGasPlan, InvalidGasMemo
  StepResult* = object ## Failed/default alternatives carry only their reason; no partial machine or charge escapes.
    case status: StepError
    of None:
      # Immutable child handles form an acyclic graph without a back-reference to this result.
      completed: StepOutcome
    else:
      # Callers cannot inspect a fabricated zero/default execution state on failure.
      discard


  InstructionEffect = object ## Private scalar exit metadata contains no immutable machine root or mutable graph alias.
    case kind: StepExit
    of Fault:
      failedPage: PageAddress
    of Host:
      callNumber: HostCallId
      callAddress: CodeAddress
    else:
      discard # Ordinary exits carry no unrelated fault/host metadata.
  InstructionEvaluation = object ## Local failures expose no intermediate CPU/memory prefix, even inside the evaluator.
    case status: StepError
    of None:
      effect: InstructionEffect
    else:
      discard # The invocation discards its private cursor on local refusal.

  ExecutionCursor = object ## One invocation owns mutable CPU values and immutable program/memory children across host resumptions.
    program: Program
    memory: Memory
    info: MachineInfo

  WorkingMemory = object ## Short segments use immutable stores; longer private runs stage scalar writes until the next observation.
    current: Memory
    writer: nil ScalarMemoryWriter
    stores: byte
    buffered: bool

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

proc initializeCursor(source: Machine, cursor: var ExecutionCursor): StepError =
  ## Validate once before any guest/host work, then copy CPU values and retain immutable child owners.
  let original = machineInfo(source)
  let program = programOf(source)
  let memory = memoryOf(source)
  if original.error != MachineError.None or program.error != MachineError.None or memory.error !=
      MachineError.None:
    return StepError.InvalidMachine
  if uint64(original.value.gasDeficit) != 0:
    return StepError.InvalidMachine # Terminal debt is invalid even with an empty local instruction budget.
  cursor = ExecutionCursor(program: program.value, memory: memory.value, info: original.value)
  StepError.None

proc applyResponseCursor(cursor: var ExecutionCursor, item: Instruction,
    response: HostResponse, exit: var StepExit): StepError =
  ## A genuine causing host instruction is supplied privately; validate all posterior fields before changing the cursor.
  if uint64(response.gasDeficit) != 0: return StepError.InvalidHostResponse
  var next = cursor.info.pc
  var selected = StepExit.Continued
  case response.action
  of HostAction.Continue:
    next = CodeAddress(uint64(next)+1+uint64(item.skip)) # Owned instruction bounds prove the successor addition.
    if instructionOpcode(cursor.program, next).error != ProgramError.None:
      return StepError.InvalidHostResponse # Preserve public captureMachine's executable-successor requirement.
  of HostAction.Panic:
    selected = StepExit.Panic # Host terminal replies retain the causing PC and posterior state.
  of HostAction.OutOfGas:
    selected = StepExit.OutOfGas
  of HostAction.Halt, HostAction.Uninitialized:
    return StepError.InvalidHostResponse # GP PR533 excludes Halt; an unselected response never implies continuation.
  if readableRange(response.memory, MemoryAddress(0), MemoryLength(0)).error != MachineError.None:
    return StepError.InvalidHostResponse # Empty range validation checks genuine memory ownership without payload allocation.
  cursor.info = MachineInfo(pc: next, gas: response.gas, gasDeficit: response.gasDeficit,
    blockCharged: cursor.info.blockCharged, registers: response.registers)
  cursor.memory = response.memory
  exit = selected
  StepError.None

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
  let memory = memoryOf(suspension.machine)
  if memory.error != MachineError.None: return StepResult(status: StepError.InvalidMachine)
  var cursor = ExecutionCursor(program: program.value, memory: memory.value, info: original.value)
  var exit = StepExit.Continued
  let applied = applyResponseCursor(cursor, item.value, response, exit)
  if applied != StepError.None: return StepResult(status: applied)
  let captured = (if exit == StepExit.Continued:
    captureMachine(cursor.program, cursor.memory, cursor.info)
    else: captureTerminalMachine(cursor.program, cursor.memory, cursor.info))
  if captured.error != MachineError.None:
    return StepResult(status: StepError.InvalidHostResponse) # Failed capture never exposes a partially applied response.
  StepResult(status: StepError.None, completed: StepOutcome(kind: exit, machine: captured.value))

const executionClasses = # Immutable byte metadata: r registers, m memory, h host, c control, - unsupported.
  "ccc-------h-----" & # Opcodes0..15.
  "----r---------mm" & # Opcodes16..31.
  "mm------c-------" & # Opcodes32..47.
  "--crmmmmmmmmmmm-" & # Opcodes48..63.
  "------mmmm------" & # Opcodes64..79.
  "ccccccccccc-----" & # Opcodes80..95.
  "----rrrrrrrrrrr-" & # Opcodes96..111.
  "--------mmmmmmmm" & # Opcodes112..127.
  "mmmrrrrrrrrrrrrr" & # Opcodes128..143.
  "rrrrrrrrrrrrrrrr" & # Opcodes144..159.
  "rr--------cccccc" & # Opcodes160..175.
  "----c---------rr" & # Opcodes176..191.
  "rrrrrrrrrrrrrrrr" & # Opcodes192..207.
  "rrrrrrrrrrrrrrrr" & # Opcodes208..223.
  "rrrrrrr---------" & # Opcodes224..239.
  "----------------"   # Opcodes240..255.

func initExecutionCache(): ExecutionCache =
  ## New invocation/limit pairs explicitly start with no valid hot/secondary entries or inherited replacement progress.
  ExecutionCache(valid: false, start: CodeAddress(0), charge: BlockGas(0),
    recent: default(array[3, BlockChargeEntry]), next: 0,
    secondary: nil,
    targets: default(array[4, DynamicTargetEntry]))

proc cachedSecondaryCharge(cache: ExecutionCache, start: CodeAddress,
    needed: var uint64): bool {.noinline.} =
  ## Four-hot-price invocations allocate nothing; an exact-tagged two-way spill retains only successful owned prices.
  let table = cache.secondary
  if table == nil: return false
  let slot = int((uint64(start)*11400714819323198485'u64) shr 58)
  if table.entries[slot].valid and uint64(table.entries[slot].start) == uint64(start):
    needed = uint64(table.entries[slot].charge)
    return true
  elif table.entries[slot+64].valid and uint64(table.entries[slot+64].start) ==
      uint64(start):
    needed = uint64(table.entries[slot+64].charge)
    return true
  false # Full address tags prevent a collision from authorizing the wrong price.

proc insertSecondary(table: SecondaryPrices, start: CodeAddress, charge: BlockGas) =
  ## The exclusive invocation owner mutates at most one fixed set; no guest balances or failed simulations enter this table.
  let slot = int((uint64(start)*11400714819323198485'u64) shr 58)
  let destination = if table.replaceUpper[slot]: slot+64 else: slot
  table.entries[destination] = BlockChargeEntry(valid: true, start: start, charge: charge)
  table.replaceUpper[slot] = not table.replaceUpper[slot]

proc cachedCharge(cache: ExecutionCache, start: CodeAddress,
    needed: var uint64): bool {.inline.} =
  ## Only exact starts from successful owned simulations grant a price; at most three secondary scalar entries are inspected.
  if cache.valid and uint64(cache.start) == uint64(start):
    needed = uint64(cache.charge)
    return true
  for entry in cache.recent:
    if entry.valid and uint64(entry.start) == uint64(start):
      needed = uint64(entry.charge)
      return true
  cachedSecondaryCharge(cache, start, needed) # Cold misses alone consult the larger bounded table.

proc rememberCharge(cache: var ExecutionCache, start: CodeAddress, charge: BlockGas) =
  ## Preserve the first successful block; later successful misses fill the hot ring and one tagged secondary way.
  if not cache.valid:
    cache.valid = true
    cache.start = start
    cache.charge = charge
  else:
    if cache.secondary == nil and cache.recent[cache.next].valid:
      # The fifth distinct successful miss justifies one bounded allocation. Seed only the three genuine preceding hot facts.
      let table = SecondaryPrices(entries: default(array[128, BlockChargeEntry]),
        replaceUpper: default(array[64, bool]))
      for entry in cache.recent: insertSecondary(table, entry.start, entry.charge)
      cache.secondary = table
    let table = cache.secondary
    if table != nil: insertSecondary(table, start, charge)
    cache.recent[cache.next] = BlockChargeEntry(valid: true, start: start, charge: charge)
    if cache.next == 2: cache.next = 0
    else: inc cache.next # The 0..2 domain and branch prove the next index; no guest-length counter can wrap.


func initWorkingMemory(memory: Memory, buffered: bool): WorkingMemory =
  ## No mutable builder or vector allocates before enough successful stores justify a private epoch.
  WorkingMemory(current: memory, writer: nil, stores: 0, buffered: buffered)

proc loadWorking(memory: WorkingMemory, address: MemoryAddress, width: AccessWidth): MachineResult[
    RegisterValue] {.inline.} =
  ## Loads observe the latest staged bytes when active, otherwise the current immutable snapshot.
  if memory.writer != nil: load(memory.writer, address, width)
  else: load(memory.current, address, width)

proc storeWorking(memory: var WorkingMemory, address: MemoryAddress, width: AccessWidth,
    value: RegisterValue, failedPage: var PageAddress): MachineError =
  ## Retain the direct path for the first three stores; staging begins on the fourth successful write in this segment.
  if memory.writer != nil:
    let written = store(memory.writer, address, width, value)
    if written.error == MachineError.Fault: failedPage = written.faultPage
    return written.error
  if memory.buffered and memory.stores == 3:
    let created = newScalarMemoryWriter(memory.current)
    if created.error != MachineError.None: return created.error
    let written = store(created.value, address, width, value)
    if written.error == MachineError.Fault: failedPage = written.faultPage
    if written.error == MachineError.None:
      memory.writer = created.value # A refused activation keeps the last immutable successful prefix untouched.
    return written.error
  let written = store(memory.current, address, width, value)
  if written.error == MachineError.Fault: failedPage = written.faultPage
  if written.error == MachineError.None:
    memory.current = written.value
    if memory.stores < 3: inc memory.stores # Saturation is bounded; no guest-length counter can wrap.
  written.error

proc finishWorking(memory: var WorkingMemory): MachineError =
  ## Observable exits seal the active epoch once; local refusals discard it without publishing private progress.
  if memory.writer != nil:
    let frozen = snapshotMemory(memory.writer)
    if frozen.error != MachineError.None: return frozen.error
    memory.current = frozen.value
  MachineError.None

# Apply one memory instruction to tentative copied state only after gas affordability is established.
# Failed preflight leaves registers and memory untouched; faultPage is meaningful only on Fault.
proc memoryMutation(decoded: ProgramResult[Instruction], info: var MachineInfo,
    memory: var WorkingMemory, failedPage: var PageAddress): MachineError =
  let item = decoded.value
  let indices = instructionRegisters(decoded)
  let op = item.opcode
  let loading = op in {52'u8..58'u8, 124'u8..130'u8}
  var width = 1
  var signedLoad = false
  var base = 0'u64
  let offset = uint64(item.x)
  var stored = uint64(info.registers[indices.aIndex])
  if loading:
    # Load pairs alternate unsigned/signed at 8/16/32 bits, followed by an unsigned 64-bit load.
    let index = (if op <= 58: int(op) - 52 else: int(op) - 124)
    width = 1 shl (index div 2)
    signedLoad = index in [1, 3, 5]
    if op >= 124:
      # Indirect loads read the original B even when it aliases destination A.
      base = uint64(info.registers[indices.bIndex])
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
    base = uint64(info.registers[indices.aIndex])
    stored = uint64(item.y)
  else:
    # Indirect register stores use original B plus X and store original A.
    width = 1 shl (int(op) - 120)
    base = uint64(info.registers[indices.bIndex])
  # Mask operands before addition: the sum fits 33 bits and preserves every cyclic physical address.
  let address = MemoryAddress((base and 0xffffffff'u64) + (offset and 0xffffffff'u64))
  if loading:
    # Preflight includes all bytes before a value or destination-register mutation becomes visible.
    let read = loadWorking(memory, address, AccessWidth(byte(width)))
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
    info.registers[indices.aIndex] = RegisterValue(value)
  else:
    # Scalar stores preflight the complete access before changing direct snapshots or private staged bytes.
    let written = storeWorking(memory, address, AccessWidth(byte(width)), RegisterValue(stored), failedPage)
    if written != MachineError.None: return written # Complete scalar preflight preserves prior staged writes on every refusal.
  # All memory instructions are nonterminating; validated blobs guarantee a following instruction.
  info.pc = CodeAddress(uint64(info.pc) + 1 + uint64(item.skip))
  MachineError.None

# Test static destination membership without narrowing invalid or negative mathematical addresses.
proc blockTarget(program: Program, address: CodeAddress): bool =
  let checked = basicBlockStart(program, address)
  checked.error == ProgramError.None and checked.value

proc cachedDynamicTarget(cache: var ExecutionCache, program: Program, index: JumpIndex,
    target: var CodeAddress): bool =
  ## Only a complete table lookup and block-membership check supplies a positive exact-ordinal fact.
  let slot = int(uint64(index) mod uint64(cache.targets.len))
  if cache.targets[slot].valid and uint64(cache.targets[slot].index) == uint64(index):
    target = cache.targets[slot].target # Full ordinal tags reject colliding entries without truncation.
    return true
  let found = jumpTarget(program, index)
  if found.error != ProgramError.None: return false # Failed lookups never replace a resident or grant a target.
  let resolved = found.value
  if not blockTarget(program, resolved): return false # Nonblock and out-of-code table contents remain guest panics.
  cache.targets[slot] = DynamicTargetEntry(valid: true, index: index, target: resolved)
  target = resolved
  true

# Compare signed 64-bit bit patterns by flipping their sign bits, avoiding checked casts.
func signedLess(a, b: uint64): bool =
  (a xor 0x8000000000000000'u64) < (b xor 0x8000000000000000'u64)

# Evaluate the condition against the original register file; decoding already saturated register IDs.
func branchCondition(decoded: ProgramResult[Instruction], registers: RegisterFile): bool =
  let item = decoded.value
  let indices = instructionRegisters(decoded)
  let a = uint64(registers[indices.aIndex])
  let b = (if item.opcode <= 90: uint64(item.x)
    else: uint64(registers[indices.bIndex]))
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
proc controlMutation(program: Program, decoded: ProgramResult[Instruction],
    info: var MachineInfo, cache: var ExecutionCache): StepExit =
  let item = decoded.value # The private caller supplies this machine's genuine result; payload and validation facts cannot separate.
  let indices = instructionRegisters(decoded)
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
    let base = (if item.opcode == 50: indices.aIndex else: indices.bIndex)
    let offset = (if item.opcode == 50: item.x else: item.y)
    let address = (uint64(info.registers[base]) + uint64(offset)) and 0xffffffff'u64
    if address == 0xffff0000'u64:
      # The halt sentinel takes precedence over table bounds or table contents.
      outcome = StepExit.Halt
    elif address == 0 or (address and 1) != 0:
      # Zero and unaligned dynamic addresses cannot index the table.
      outcome = StepExit.Panic
    else:
      # Division avoids overflow in a table-length times alignment check.
      valid = cachedDynamicTarget(cache, program, JumpIndex(address div 2 - 1), target)
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
    valid = valid and instructionTargetStartsBlock(
        decoded) # This result binds the target fact to the exact decoded operands.
    if item.opcode in {81'u8..90'u8, 170'u8..175'u8}:
      # Both successors must be valid, even when the condition would avoid the invalid one.
      valid = valid and instructionHasFallthrough(
          decoded) # A present successor after this terminating conditional is a validated block start.
      if not branchCondition(decoded, info.registers):
        # Only the selected PC changes; validation above still considered the taken target.
        target = next
  if not valid:
    # Invalid static or table destinations retain the instruction's original PC.
    outcome = StepExit.Panic
  if item.opcode in {80'u8, 180'u8}:
    # The instruction table specifies this mutation even when the jump panics or halts.
    info.registers[indices.aIndex] = RegisterValue(uint64(item.x))
  if outcome == StepExit.Continued:
    # Every successful control transfer enters a block that must be charged next time.
    info.pc = target
    info.blockCharged = false
  outcome

# Mutate only invocation-owned CPU values and a checked private memory workspace; observable exits publish immutable roots.
template instructionBody[UsePlan, UseMemo: static[bool]](program: Program, info: var MachineInfo,
    memory: var WorkingMemory, limit: GasCycleLimit, control, memoryAccess, hostCalls: bool,
    cache: var ExecutionCache, decoded: ProgramResult[Instruction], plan: GasPlan,
    memo: GasMemo): InstructionEvaluation =
  ## Share checked transitions while erasing unused pricing ownership at compile time.
  if uint64(info.gasDeficit) != 0:
    # Terminal host debt must never be reinterpreted as executable zero gas.
    return InstructionEvaluation(status: StepError.InvalidMachine)
  # Both private callers derive this result from the current machine's own program and PC.
  # Entry capture validates PC; terminal snapshots may intentionally have a non-executable PC.
  if decoded.error != ProgramError.None: return InstructionEvaluation(
      status: StepError.InvalidMachine)
  let item = decoded.value
  let category = executionClasses[int(item.opcode)]
  if category == '-' or
      (category == 'c' and not control) or
      (category == 'm' and not memoryAccess) or
      (category == 'h' and not hostCalls):
    # Capability rejection precedes evaluation and never fabricates a guest trap or gas debit.
    return InstructionEvaluation(status: StepError.UnsupportedInstruction)
  if not info.blockCharged:
    # Exact cached starts already certify block membership; arbitrary interior entry retains the complete containing-block lookup.
    var chargeError = GasError.None
    var needed = 0'u64
    when UsePlan:
      let direct = blockGas(plan, info.pc)
      if direct.error == GasPlanError.None:
        needed = uint64(direct.value)
      elif direct.error == GasPlanError.InvalidStart:
        let start = containingBlockStart(program, info.pc)
        if start.error != ProgramError.None:
          return InstructionEvaluation(status: StepError.InvalidMachine)
        let priced = blockGas(plan, start.value)
        if priced.error != GasPlanError.None:
          return InstructionEvaluation(status: StepError.InvalidGasPlan)
        needed = uint64(priced.value)
      else:
        return InstructionEvaluation(status: StepError.InvalidGasPlan)
    else:
      if not cachedCharge(cache, info.pc, needed):
        let start = containingBlockStart(program, info.pc)
        if start.error != ProgramError.None: return InstructionEvaluation(
            status: StepError.InvalidMachine)
        if not cachedCharge(cache, start.value, needed):
          # Only successful prices under this invocation's immutable program/limit enter the memo; failures publish no prefix.
          when UseMemo:
            let charge = blockGas(memo, start.value)
            case charge.error
            of GasMemoError.None:
              # Facts certify a price only; affordability and the paid-block flag still belong to this invocation.
              needed = uint64(charge.value)
              rememberCharge(cache, start.value, charge.value)
            of GasMemoError.CycleLimitExceeded:
              chargeError = GasError.CycleLimitExceeded
            of GasMemoError.NegativeBranchTarget:
              chargeError = GasError.NegativeBranchTarget
            else:
              return InstructionEvaluation(status: StepError.InvalidGasMemo)
          else:
            let charge = blockGas(program, start.value, limit)
            chargeError = charge.error
            if chargeError == GasError.None:
              needed = uint64(charge.value)
              rememberCharge(cache, start.value, charge.value)
    case chargeError
    of GasError.None:
      # Prove affordability before subtraction and before evaluating any register mutation.
      if uint64(info.gas) < needed:
        return InstructionEvaluation(status: StepError.None,
          effect: InstructionEffect(kind: StepExit.OutOfGas))
      info.gas = MachineGas(uint64(info.gas) - needed)
      info.blockCharged = true
    of GasError.CycleLimitExceeded:
      # Local simulation exhaustion is not guest out-of-gas and carries no partial debit.
      return InstructionEvaluation(status: StepError.GasCycleLimitExceeded)
    of GasError.NegativeBranchTarget:
      # Retain the historical error alternative; current PolkaVM-aligned pricing does not emit it.
      return InstructionEvaluation(status: StepError.NegativeBranchTarget)
    else:
      # A captured valid PC must have a valid containing block.
      return InstructionEvaluation(status: StepError.InvalidMachine)
  var outcome = StepExit.Continued
  var failedPage = PageAddress(0)
  if category == 'r':
    # Register-only execution retains its existing scope and copied-register semantics.
    let mutation = evaluateRegisterWrite(decoded, info.registers)
    if mutation.error != RegisterError.None:
      # Defensive evaluator failure cannot publish the tentative copied gas state.
      return InstructionEvaluation(status: StepError.UnsupportedInstruction)
    applyRegisterWrite(info.registers, mutation)
    info.pc = CodeAddress(uint64(info.pc) + 1 + uint64(item.skip))
  elif category == 'm':
    # Memory exceptions retain the charged gas/flag but never publish partial CPU or memory writes.
    case memoryMutation(decoded, info, memory, failedPage)
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
      return InstructionEvaluation(status: StepError.AmbiguousAccessOrder)
    else:
      # Decoded widths and captured owners make other scalar API failures unreachable.
      return InstructionEvaluation(status: StepError.InvalidMachine)
  elif category == 'h':
    # Psi_1 ecalli inherits the default PC increment and leaves the current block prepaid.
    outcome = StepExit.Host
    info.pc = CodeAddress(uint64(info.pc) + 1 + uint64(item.skip))
  else:
    # This path is reachable only for explicitly supported control/no-op instructions.
    outcome = controlMutation(program, decoded, info, cache)
  if outcome notin {StepExit.Panic, StepExit.Halt}:
    if not terminatesBlock(item.opcode):
      # Every admitted nonterminator advances by the decoded skip, except a failed scalar access retaining its genuine causing PC.
      if outcome != StepExit.Fault and not instructionHasFallthrough(decoded):
        return InstructionEvaluation(status: StepError.InvalidMachine)
    # Continued controls already selected a complete executable block: sealed static/fallthrough facts or a checked dynamic target.
    # No program mutation or callback occurs before this point, so another opcode lookup would only repeat that validation.
  # The workspace owns staged writes; published source/exit snapshots never expose its mutable storage.
  if outcome == StepExit.Fault:
    return InstructionEvaluation(status: StepError.None,
        effect: InstructionEffect(kind: StepExit.Fault, failedPage: failedPage))
  if outcome == StepExit.Host:
    return InstructionEvaluation(status: StepError.None,
        effect: InstructionEffect(kind: StepExit.Host, callNumber: HostCallId(uint64(item.x)),
        callAddress: item.address))
  InstructionEvaluation(status: StepError.None, effect: InstructionEffect(kind: outcome))
proc evaluateInstruction[UsePlan: static[bool]](program: Program, info: var MachineInfo,
    memory: var WorkingMemory, limit: GasCycleLimit, control, memoryAccess, hostCalls: bool,
        cache: var ExecutionCache,
    decoded: ProgramResult[Instruction], plan: GasPlan = default(GasPlan)): InstructionEvaluation =
  ## Expand the shared checked transition with the original legacy helper interface.
  instructionBody[UsePlan, false](program, info, memory, limit, control, memoryAccess, hostCalls,
      cache, decoded, plan, default(GasMemo))

proc memoEvaluateInstruction(program: Program, info: var MachineInfo,
    memory: var WorkingMemory, limit: GasCycleLimit, control, memoryAccess, hostCalls: bool,
        cache: var ExecutionCache,
    decoded: ProgramResult[Instruction], memo: GasMemo): InstructionEvaluation =
  ## Use the same checked transition with an exclusively borrowed lazy pricing handle.
  instructionBody[false, true](program, info, memory, limit, control, memoryAccess, hostCalls,
      cache, decoded, default(GasPlan), memo)

proc publishInstruction(program: Program, memory: Memory, info: MachineInfo,
    effect: InstructionEffect, terminal: bool): StepResult =
  ## Materialize an immutable observable snapshot only after evaluation/normalization succeeds; local capture refusals expose no prefix.
  let updated = (if terminal or effect.kind in {StepExit.Panic, StepExit.Halt}:
    captureTerminalMachine(program, memory, info)
    else: captureMachine(program, memory, info))
  if updated.error != MachineError.None: return StepResult(status: StepError.InvalidMachine)
  case effect.kind
  of StepExit.Fault:
    return StepResult(status: StepError.None,
        completed: StepOutcome(kind: StepExit.Fault, machine: updated.value,
            failedPage: effect.failedPage))
  of StepExit.Host:
    return StepResult(status: StepError.None,
        completed: StepOutcome(kind: StepExit.Host, machine: updated.value,
        callNumber: effect.callNumber, callAddress: effect.callAddress))
  else:
    return StepResult(status: StepError.None,
        completed: StepOutcome(kind: effect.kind, machine: updated.value)) # Ordinary outcomes never inherit metadata from a prior instruction.

proc publishInstruction(program: Program, memory: var WorkingMemory, info: MachineInfo,
    effect: InstructionEffect, terminal: bool): StepResult =
  ## Freeze only actual observations; the immutable publisher still validates program/memory/CPU construction.
  if finishWorking(memory) != MachineError.None: return StepResult(status: StepError.InvalidMachine)
  publishInstruction(program, memory.current, info, effect, terminal)

proc stepDecoded[UsePlan: static[bool]](source: Machine, limit: GasCycleLimit, control,
    memoryAccess, hostCalls: bool, cache: var ExecutionCache, decoded: ProgramResult[Instruction],
        plan: GasPlan = default(GasPlan)): StepResult =
  ## Single-step APIs retain their exact immutable-snapshot boundary and capability/refusal semantics.
  let captured = machineInfo(source)
  let owner = programOf(source)
  let originalMemory = memoryOf(source)
  if captured.error != MachineError.None or owner.error != MachineError.None or
      originalMemory.error != MachineError.None: return StepResult(status: StepError.InvalidMachine)
  var info = captured.value
  var memory = initWorkingMemory(originalMemory.value, false)
  let evaluated = evaluateInstruction[UsePlan](owner.value, info, memory, limit, control,
      memoryAccess, hostCalls, cache, decoded, plan)
  if evaluated.status != StepError.None: return StepResult(status: evaluated.status)
  if evaluated.effect.kind == StepExit.OutOfGas:
    return StepResult(status: StepError.None, completed: StepOutcome(kind: StepExit.OutOfGas,
        machine: source)) # An unaffordable single step preserves the exact original root.
  publishInstruction(owner.value, memory, info, evaluated.effect, false)

# Single-step calls never inherit cached work across owners, scopes or local simulation limits.
proc stepImpl[UsePlan: static[bool]](source: Machine, limit: GasCycleLimit, control, memoryAccess,
    hostCalls: bool, plan: GasPlan = default(GasPlan)): StepResult =
  var cache = initExecutionCache()
  let owner = programOf(source)
  let current = machineInfo(source)
  if owner.error != MachineError.None or current.error != MachineError.None:
    # Absent roots cannot provide either a program or an executable instruction.
    return StepResult(status: StepError.InvalidMachine)
  when UsePlan:
    if not matchesProgram(plan, owner.value): return StepResult(status: StepError.InvalidGasPlan)
  let decoded = instruction(owner.value, current.value.pc)
  stepDecoded[UsePlan](source, limit, control, memoryAccess, hostCalls, cache, decoded, plan)

proc stepRegisters*(source: Machine, limit: GasCycleLimit): StepResult =
  ## Preserve the register-only capability boundary for existing callers; no control opcode is accepted.
  stepImpl[false](source, limit, false, false, false)

proc stepControl*(source: Machine, limit: GasCycleLimit): StepResult =
  ## Execute one register/control instruction under Psi_1, including trap, unlikely and dynamic halt.
  ## Memory/host instructions remain local UnsupportedInstruction failures with no state progress.
  stepImpl[false](source, limit, true, false, false)

proc stepMemory*(source: Machine, limit: GasCycleLimit): StepResult =
  ## Execute one register/control/load/store instruction; host calls remain outside this capability.
  ## Memory fault/panic retains charged gas and original PC/registers/memory; local gates have no snapshot.
  stepImpl[false](source, limit, true, true, false)

proc stepOnce*(source: Machine, limit: GasCycleLimit): StepResult =
  ## Evaluate Psi_1 for every valid opcode, including host suspension; no host function is invoked here.
  ## Existing specification gates remain local failures and expose no partially updated machine.
  stepImpl[false](source, limit, true, true, true)

proc stepWithPlan(source: Machine, plan: GasPlan, control, memoryAccess,
    hostCalls: bool): StepResult =
  ## Validate the immutable policy once before entering the same scoped single-step evaluator.
  let configured = gasPlanInfo(plan)
  if configured.error != GasPlanError.None: return StepResult(status: StepError.InvalidGasPlan)
  stepImpl[true](source, configured.value.cycleLimit, control, memoryAccess, hostCalls, plan)

proc stepRegisters*(source: Machine, plan: GasPlan): StepResult =
  ## Retain the register-only capability/refusal boundary under a matching complete gas plan.
  stepWithPlan(source, plan, false, false, false)
proc stepControl*(source: Machine, plan: GasPlan): StepResult =
  ## Apply the existing register/control step semantics with immutable precomputed block prices.
  stepWithPlan(source, plan, true, false, false)
proc stepMemory*(source: Machine, plan: GasPlan): StepResult =
  ## Preserve paid faults, permission ordering and atomic memory snapshots with the fixed plan policy.
  stepWithPlan(source, plan, true, true, false)
proc stepOnce*(source: Machine, plan: GasPlan): StepResult =
  ## Evaluate any admitted opcode, including a genuine host suspension, under matching immutable prices.
  stepWithPlan(source, plan, true, true, true)

proc rememberSpill(table: DecodedSpill, address: CodeAddress, decoded: ProgramResult[Instruction]) =
  ## Only the private successful-decode path calls this insertion; replacement is bounded and never retains source ownership.
  let bucket = int((uint64(address)*11400714819323198485'u64) shr 53)
  let destination = if table.replaceUpper[bucket]: bucket+2048 else: bucket
  table.entries[destination] = decoded
  table.replaceUpper[bucket] = not table.replaceUpper[bucket]

proc decodeInstructionMiss(program: Program, address: CodeAddress,
    cache: var InstructionCache, slot, alternative: int): ProgramResult[Instruction] {.noinline.} =
  ## Keep decoding, bounded allocation and replacement off the original two-comparison hit path.
  result = instruction(program, address)
  if result.error == ProgramError.None:
    if cache.spill == nil:
      if cache.misses < 32768:
        inc cache.misses # Saturating successful-miss progress never wraps with guest work.
      else:
        # Only sustained pressure pays one fixed allocation; the existing small-program path remains allocation-free.
        let table = DecodedSpill(entries: default(array[4096, ProgramResult[Instruction]]),
          replaceUpper: default(array[2048, bool]))
        for entry in cache.entries:
          if entry.error == ProgramError.None: rememberSpill(table, entry.value.address, entry)
        cache.spill = table
    let table = cache.spill
    if table != nil: rememberSpill(table, address, result)

    var destination = slot
    if cache.entries[slot].error == ProgramError.None:
      if cache.entries[alternative].error != ProgramError.None:
        destination = alternative # Fill a free paired way without disturbing the natural resident.
      else:
        # A third successful colliding decode alternates the two residents; failures never replace or advance this bit.
        let bucket = slot mod cache.replaceUpper.len
        destination = if cache.replaceUpper[bucket]: bucket+16 else: bucket
        cache.replaceUpper[bucket] = not cache.replaceUpper[bucket]
    cache.entries[destination] = result

proc cachedInstruction(program: Program, address: CodeAddress,
    cache: var InstructionCache): ProgramResult[Instruction] {.inline.} =
  ## Preserve the original thirty-two-result fast path; larger working sets enter a separately bounded cold helper.
  let slot = int(uint64(address) mod uint64(cache.entries.len)) # Fixed positive capacity proves the native index.
  if cache.entries[slot].error == ProgramError.None and uint64(cache.entries[slot].value.address) ==
      uint64(address):
    return cache.entries[slot] # Most existing working sets keep their original single-comparison hit path.
  let alternative = slot xor 16 # Toggling one of five bounded index bits stays within 0..31.
  if cache.entries[alternative].error == ProgramError.None and uint64(cache.entries[
      alternative].value.address) == uint64(address):
    return cache.entries[alternative]
  let table {.cursor.} = cache.spill # The invocation owns this immutable-program fact table through the callback-free lookup.
  if table != nil:
    # Exact PC tags permit copied scalar results only; misses alone enter the allocating cold path.
    let bucket = int((uint64(address)*11400714819323198485'u64) shr 53)
    if table.entries[bucket].error == ProgramError.None and uint64(table.entries[
        bucket].value.address) == uint64(address):
      return table.entries[bucket]
    if table.entries[bucket+2048].error == ProgramError.None and uint64(table.entries[
        bucket+2048].value.address) == uint64(address):
      return table.entries[bucket+2048]
  decodeInstructionMiss(program, address, cache, slot, alternative)

# Evaluate recursive Psi iteratively over an already validated program and captured machine.
# The shared remaining budget counts attempted instructions, including the exiting instruction.
# Each gas simulation is independently bounded by gasLimit. Local failures expose no partial progress.
template evaluateSelected[UsePlan, UseMemo: static[bool]](program: Program, info: var MachineInfo,
    memory: var WorkingMemory, gasLimit: GasCycleLimit, chargeCache: var ExecutionCache,
    decoded: ProgramResult[Instruction], plan: GasPlan, memo: GasMemo): InstructionEvaluation =
  ## Select the priced evaluator without changing ordinary call frames.
  when UseMemo:
    memoEvaluateInstruction(program, info, memory, gasLimit, true, true, true, chargeCache, decoded, memo)
  else:
    evaluateInstruction[UsePlan](program, info, memory, gasLimit, true, true, true, chargeCache,
        decoded, plan)

template budgetBody[UsePlan, UseMemo: static[bool]](source: Machine, remaining: var uint64,
    gasLimit: GasCycleLimit, chargeCache: var ExecutionCache, instructions: var InstructionCache,
    cursor: var ExecutionCursor, resumed: bool, plan: GasPlan, memo: GasMemo): StepResult =
  ## Share checked transitions while erasing unused pricing ownership at compile time.
  var program = default(Program)
  var info = default(MachineInfo)
  var memory = initWorkingMemory(default(Memory), true)
  if resumed:
    # Only this invocation's validated host cursor can seed a continuation; no public mode exposes mutable state.
    program = cursor.program
    info = cursor.info
    memory.current = cursor.memory
  else:
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
    program = owner.value
    info = original.value
    memory.current = originalMemory.value
  when UsePlan:
    if not matchesProgram(plan, program):
      return StepResult(status: StepError.InvalidGasPlan)
  when UseMemo:
    if not matchesProgram(memo, program): return StepResult(status: StepError.InvalidGasMemo)
  # CPU values are local to this invocation; immutable memory updates cannot mutate retained source snapshots.
  while remaining > 0:
    dec remaining # Each attempted instruction consumes exactly one local step, including invalid entry and every exit.
    let causingPc = info.pc # Nonfinal instruction exits preserve registers/memory; only the causing PC needs restoration.
    let decoded = cachedInstruction(program, causingPc, instructions)
    if decoded.error != ProgramError.None:
      info.pc = CodeAddress(0) # Trusted terminal/import snapshots retain the existing uncharged deblob panic rule.
      return publishInstruction(program, memory, info, InstructionEffect(kind: StepExit.Panic), true)
    let evaluated = evaluateSelected[UsePlan, UseMemo](program, info, memory, gasLimit, chargeCache,
        decoded, plan, memo)
    if evaluated.status != StepError.None:
      return StepResult(status: evaluated.status) # The whole private cursor retires; local failures never publish earlier progress.
    let effect = evaluated.effect
    if effect.kind != StepExit.Continued:
      if effect.kind in {StepExit.Panic, StepExit.Halt}:
        info.pc = CodeAddress(0) # Final exits preserve posterior registers/memory, including load-and-jump mutations.
      else:
        # OutOfGas exits before mutation, failed memory preflight writes nothing, and Host changes only PC.
        # Preserve posterior gas/charged state without copying or rolling back the complete register file.
        info.pc = causingPc
      let published = publishInstruction(program, memory, info, effect, true)
      if resumed and effect.kind == StepExit.Host and published.error == StepError.None:
        cursor.info = info
        cursor.memory = memory.current # The checked response resumes from the actual frozen callback memory.
      return published
  StepResult(status: StepError.StepLimitExceeded) # Bounded exhaustion grants no machine or resumable prefix.
proc executeBudget[UsePlan: static[bool]](source: Machine, remaining: var uint64,
    gasLimit: GasCycleLimit, chargeCache: var ExecutionCache, instructions: var InstructionCache,
        cursor: var ExecutionCursor, resumed: bool, plan: GasPlan = default(GasPlan)): StepResult =
  ## Keep ordinary CPU and memory frames while expanding the common budget loop.
  budgetBody[UsePlan, false](source, remaining, gasLimit, chargeCache, instructions, cursor,
      resumed, plan, default(GasMemo))

proc memoBudget(source: Machine, remaining: var uint64,
    gasLimit: GasCycleLimit, chargeCache: var ExecutionCache, instructions: var InstructionCache,
        cursor: var ExecutionCursor, resumed: bool, memo: GasMemo): StepResult =
  ## Use the common budget loop with source-bound lazy facts and no new legacy frame fields.
  budgetBody[false, true](source, remaining, gasLimit, chargeCache, instructions, cursor, resumed,
      default(GasPlan), memo)

proc execute*(source: Machine, stepLimit: ExecutionStepLimit, gasLimit: GasCycleLimit): StepResult =
  ## Execute a guest-only segment with a fresh local instruction budget; Host is returned to the caller.
  var remaining = uint64(stepLimit)
  # A direct execution has its own memo, never inherited from another program or local policy.
  var chargeCache = initExecutionCache()
  var instructions = default(InstructionCache) # Fresh explicit empty memo prevents cross-program or cross-invocation operand reuse.
  var unusedCursor = default(ExecutionCursor) # Ordinary execution uses source validation and its original loop-local CPU storage.
  executeBudget[false](source, remaining, gasLimit, chargeCache, instructions, unusedCursor, false)

proc execute*(source: Machine, stepLimit: ExecutionStepLimit, plan: GasPlan): StepResult =
  ## Reuse immutable complete prices while all CPU, attempt budgets and memory staging stay invocation-local.
  var remaining = uint64(stepLimit)
  var chargeCache = initExecutionCache()
  var instructions = default(InstructionCache)
  var unusedCursor = default(ExecutionCursor)
  let settings = gasPlanInfo(plan)
  if settings.error != GasPlanError.None: return StepResult(status: StepError.InvalidGasPlan)
  executeBudget[true](source, remaining, settings.value.cycleLimit, chargeCache, instructions,
      unusedCursor, false, plan)

# Lift guest/engine results without confusing guest terminal exits with local host errors.
func executionResult[Reason: enum](evaluated: StepResult): HostExecutionResult[Reason] =
  if evaluated.error != StepError.None:
    # Preserve the original engine refusal, without accessing a failed StepResult payload.
    return HostExecutionResult[Reason](status: HostExecutionError.ExecutionFailure,
      executionReason: evaluated.error)
  HostExecutionResult[Reason](status: HostExecutionError.None, completed: evaluated.value)

# Advance a shared invocation budget to the next dispatch or terminal result.
# Dispatch credit is consumed before callbacks, identically for both public callback forms.
template budgetSelected[UsePlan, UseMemo: static[bool]](remaining: var uint64,
    gasLimit: GasCycleLimit, chargeCache: var ExecutionCache, instructions: var InstructionCache,
    cursor: var ExecutionCursor, plan: GasPlan, memo: GasMemo): StepResult =
  ## Resume through the selected pricing implementation with the same attempt budget.
  when UseMemo:
    memoBudget(default(Machine), remaining, gasLimit, chargeCache, instructions, cursor, true, memo)
  else:
    executeBudget[UsePlan](default(Machine), remaining, gasLimit, chargeCache, instructions, cursor,
        true, plan)

template hostAdvanceBody[UsePlan, UseMemo: static[bool]](cursor: var ExecutionCursor,
    remaining, calls: var uint64, gasLimit: GasCycleLimit, chargeCache: var ExecutionCache,
    instructions: var InstructionCache, plan: GasPlan, memo: GasMemo): StepResult =
  ## Share checked transitions while erasing unused pricing ownership at compile time.
  ## Both callback forms share the ordinary transition loop and reserve dispatch credit before external code.
  let evaluated = budgetSelected[UsePlan, UseMemo](remaining, gasLimit, chargeCache, instructions,
      cursor, plan, memo)
  if evaluated.error != StepError.None: return evaluated
  if evaluated.value.exit == StepExit.Host:
    if calls == 0: return StepResult(status: StepError.HostCallLimitExceeded)
    dec calls
  evaluated
proc nextHost[UsePlan: static[bool]](cursor: var ExecutionCursor, remaining, calls: var uint64,
    gasLimit: GasCycleLimit, chargeCache: var ExecutionCache, instructions: var InstructionCache,
        plan: GasPlan = default(GasPlan)): StepResult =
  ## Reserve callback credit through the common scheduler and original pricing interface.
  hostAdvanceBody[UsePlan, false](cursor, remaining, calls, gasLimit, chargeCache, instructions,
      plan, default(GasMemo))

proc memoNextHost(cursor: var ExecutionCursor, remaining, calls: var uint64,
    gasLimit: GasCycleLimit, chargeCache: var ExecutionCache, instructions: var InstructionCache,
        memo: GasMemo): StepResult =
  ## Reserve callback credit through the same scheduler with the retained memo policy.
  hostAdvanceBody[false, true](cursor, remaining, calls, gasLimit, chargeCache, instructions,
      default(GasPlan), memo)

proc applyCursorResponse(cursor: var ExecutionCursor, response: HostResponse,
    instructions: var InstructionCache): InstructionEvaluation =
  ## Only a genuine cursor-produced Host reaches this private continuation; reuse its invocation-bound decode.
  let item = cachedInstruction(cursor.program, cursor.info.pc, instructions)
  if item.error != ProgramError.None: return InstructionEvaluation(
      status: StepError.InvalidHostSuspension)
  if item.value.opcode != 10: return InstructionEvaluation(status: StepError.InvalidHostSuspension)
  var exit = StepExit.Continued
  let applied = applyResponseCursor(cursor, item.value, response, exit)
  if applied != StepError.None: return InstructionEvaluation(status: applied)
  InstructionEvaluation(status: StepError.None, effect: InstructionEffect(kind: exit))

template hostSelected[UsePlan, UseMemo: static[bool]](cursor: var ExecutionCursor,
    remaining, calls: var uint64, gasLimit: GasCycleLimit, chargeCache: var ExecutionCache,
    instructions: var InstructionCache, plan: GasPlan, memo: GasMemo): StepResult =
  ## Share callback scheduling without retaining a memo in legacy host execution.
  when UseMemo:
    memoNextHost(cursor, remaining, calls, gasLimit, chargeCache, instructions, memo)
  else:
    nextHost[UsePlan](cursor, remaining, calls, gasLimit, chargeCache, instructions, plan)

template runFallibleHostBody[Context; Reason: enum; UsePlan, UseMemo: static[bool]](source: Machine,
    context: var Context, handler: proc(context: var Context, suspension: StepOutcome): HostResult[
        Reason] {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, gasLimit: GasCycleLimit,
    plan: GasPlan, memo: GasMemo): HostExecutionResult[Reason] =
  ## Share checked transitions while erasing unused pricing ownership at compile time.
  ## Run Psi_H* with typed local callback refusals and one instruction budget across continuations.
  ## Context is exclusively borrowed for this synchronous call. Callback effects persist on local errors;
  ## callers requiring atomic external effects must stage their context. Neither callback nor context is retained.
  let retainedPlan = plan # Keep an immutable policy value across mutable callback scheduling.
  let retainedMemo = memo # The default legacy argument is a compile-time empty handle.
  var remaining = uint64(stepLimit)
  var calls = uint64(hostLimit)
  var cursor = default(ExecutionCursor)
  let initialized = initializeCursor(source, cursor)
  if initialized != StepError.None: return executionResult[Reason](StepResult(status: initialized))
  when UseMemo:
    if not matchesProgram(retainedMemo, cursor.program): return executionResult[Reason](StepResult(
        status: StepError.InvalidGasMemo))
  # Host responses preserve this invocation's program and fixed simulation limit.
  # Scalar cached prices retain neither context nor callbacks and disappear on every return.
  var chargeCache = initExecutionCache()
  var instructions = default(InstructionCache) # Host replies preserve the program, so scalar decoder hits remain valid until this invocation returns.
  while true:
    # Publish the next actual callback observation from this invocation's validated continuation.
    let evaluated = hostSelected[UsePlan, UseMemo](cursor, remaining, calls, gasLimit, chargeCache,
        instructions, retainedPlan, retainedMemo)
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
      let applied = applyCursorResponse(cursor, reply.value, instructions)
      if applied.status != StepError.None:
        return executionResult[Reason](StepResult(
            status: applied.status)) # Callback state is validated before private resumption.
      if applied.effect.kind != StepExit.Continued:
        return executionResult[Reason](publishInstruction(cursor.program, cursor.memory,
          cursor.info, applied.effect, true)) # Terminal replies preserve the host's posterior state and causing PC.
  executionResult[Reason](StepResult(status: StepError.InvalidMachine)) # Defensive unreachable tail satisfies the template expression contract.

proc runFallibleHost[Context; Reason: enum; UsePlan: static[bool]](source: Machine,
    context: var Context, handler: proc(context: var Context, suspension: StepOutcome): HostResult[
        Reason] {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit,
        gasLimit: GasCycleLimit, plan: GasPlan = default(GasPlan)): HostExecutionResult[Reason] =
  ## Expand shared fallible scheduling without adding memo ownership to the legacy interface.
  runFallibleHostBody[Context, Reason, UsePlan, false](source, context, handler, stepLimit,
      hostLimit, gasLimit, plan, default(GasMemo))

proc memoRunFallibleHost[Context; Reason: enum](source: Machine,
    context: var Context, handler: proc(context: var Context, suspension: StepOutcome): HostResult[
        Reason] {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit,
        gasLimit: GasCycleLimit, memo: GasMemo): HostExecutionResult[Reason] =
  ## Retain lazy policy facts across synchronous fallible callbacks using shared transitions.
  runFallibleHostBody[Context, Reason, false, true](source, context, handler, stepLimit, hostLimit,
      gasLimit, default(GasPlan), memo)

template runHostBody[Context; UsePlan, UseMemo: static[bool]](source: Machine,
    context: var Context, handler: proc(context: var Context,
        suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, gasLimit: GasCycleLimit,
    plan: GasPlan, memo: GasMemo): StepResult =
  ## Share checked transitions while erasing unused pricing ownership at compile time.
  ## Preserve the response-only API with the same guest/dispatch scheduler and response application boundary.
  ## Context is borrowed synchronously; already-performed callback effects survive later local errors.
  let retainedPlan = plan # Retain the selected policy value independently of callback context updates.
  let retainedMemo = memo # The default legacy argument is a compile-time empty handle.
  var remaining = uint64(stepLimit)
  var calls = uint64(hostLimit)
  var cursor = default(ExecutionCursor)
  let initialized = initializeCursor(source, cursor)
  if initialized != StepError.None: return StepResult(status: initialized)
  when UseMemo:
    if not matchesProgram(retainedMemo, cursor.program): return StepResult(
        status: StepError.InvalidGasMemo)
  # Host responses preserve this invocation's program and fixed simulation limit.
  # Scalar cached prices retain neither context nor callbacks and disappear on every return.
  var chargeCache = initExecutionCache()
  var instructions = default(InstructionCache) # Host replies preserve the program, so scalar decoder hits remain valid until this invocation returns.
  while true:
    # All scheduling and charging happens in the same helper used by fallible callbacks.
    let evaluated = hostSelected[UsePlan, UseMemo](cursor, remaining, calls, gasLimit, chargeCache,
        instructions, retainedPlan, retainedMemo)
    if evaluated.error != StepError.None:
      # Preserve the legacy local engine refusal without reading a failed payload.
      return evaluated
    let stopped = evaluated.value
    if stopped.exit != StepExit.Host:
      # Guest exits never invoke host callbacks.
      return evaluated
    let applied = applyCursorResponse(cursor, handler(context, stopped), instructions)
    if applied.status != StepError.None: return StepResult(status: applied.status)
    if applied.effect.kind != StepExit.Continued:
      return publishInstruction(cursor.program, cursor.memory, cursor.info, applied.effect, true)
    # A valid Continue updates the private cursor without allocating an unobserved resumed machine root.
  StepResult(status: StepError.InvalidMachine) # Defensive unreachable tail satisfies the template expression contract.

proc runHost[Context; UsePlan: static[bool]](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, gasLimit: GasCycleLimit,
        plan: GasPlan = default(GasPlan)): StepResult =
  ## Expand shared response-only scheduling with the legacy pricing interface.
  runHostBody[Context, UsePlan, false](source, context, handler, stepLimit, hostLimit, gasLimit,
      plan, default(GasMemo))

proc memoRunHost[Context](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, gasLimit: GasCycleLimit,
        memo: GasMemo): StepResult =
  ## Retain lazy policy facts across synchronous response-only callbacks.
  runHostBody[Context, false, true](source, context, handler, stepLimit, hostLimit, gasLimit,
      default(GasPlan), memo)

proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason] {.nimcall,
        raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit,
        gasLimit: GasCycleLimit): HostExecutionResult[Reason] =
  ## Preserve fallible callback semantics and per-block cycle ceilings through the shared scheduler.
  runFallibleHost[Context, Reason, false](source, context, handler, stepLimit, hostLimit, gasLimit)

proc executeWithHost*[Context](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, gasLimit: GasCycleLimit): StepResult =
  ## Preserve response-only callbacks with the existing dynamic price policy and shared invocation budgets.
  runHost[Context, false](source, context, handler, stepLimit, hostLimit, gasLimit)

proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason] {.nimcall,
        raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, plan: GasPlan): HostExecutionResult[Reason] =
  ## Retain matching immutable prices across synchronous fallible callbacks; no callback or context is retained afterward.
  let configured = gasPlanInfo(plan)
  if configured.error != GasPlanError.None:
    return executionResult[Reason](StepResult(status: StepError.InvalidGasPlan))
  runFallibleHost[Context, Reason, true](source, context, handler, stepLimit, hostLimit,
      configured.value.cycleLimit, plan)

proc executeWithHost*[Context](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, plan: GasPlan): StepResult =
  ## Reuse complete prices with ordinary callback reply validation and exact shared step/dispatch budgets.
  let configured = gasPlanInfo(plan)
  if configured.error != GasPlanError.None: return StepResult(status: StepError.InvalidGasPlan)
  runHost[Context, true](source, context, handler, stepLimit, hostLimit,
      configured.value.cycleLimit, plan)

proc execute*(source: Machine, stepLimit: ExecutionStepLimit, memo: GasMemo): StepResult =
  ## Reuse successful bounded prices lazily while CPU, memory staging and attempt budgets remain invocation-local.
  let settings = gasMemoInfo(memo)
  if settings.error != GasMemoError.None: return StepResult(status: StepError.InvalidGasMemo)
  var remaining = uint64(stepLimit)
  var prices = initExecutionCache()
  var instructions = default(InstructionCache)
  var cursor = default(ExecutionCursor)
  memoBudget(source, remaining, settings.value.cycleLimit, prices, instructions,
    cursor, false, memo)

proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason] {.nimcall,
        raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, memo: GasMemo): HostExecutionResult[Reason] =
  ## Retain one fixed source/policy across fallible callbacks; already-learned facts may survive local refusals without machine progress.
  let settings = gasMemoInfo(memo)
  if settings.error != GasMemoError.None:
    return executionResult[Reason](StepResult(status: StepError.InvalidGasMemo))
  memoRunFallibleHost[Context, Reason](source, context, handler, stepLimit, hostLimit,
    settings.value.cycleLimit, memo)

proc executeWithHost*[Context](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, memo: GasMemo): StepResult =
  ## Response-only callers keep the ordinary scheduler, dispatch limits and source-bound lazy pricing identity.
  let settings = gasMemoInfo(memo)
  if settings.error != GasMemoError.None: return StepResult(status: StepError.InvalidGasMemo)
  memoRunHost[Context](source, context, handler, stepLimit, hostLimit,
    settings.value.cycleLimit, memo)
