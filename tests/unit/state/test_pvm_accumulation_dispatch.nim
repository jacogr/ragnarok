# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored accumulation dispatch witnesses exercise identifier classification and real engine execution.
## Tests preserve local refusals, exact gas outcomes, preparation ownership and ARC release.

# @@Verification={"arc": "pvm_accumulation_dispatch_arc_release"}

import std/[assertions, syncio]
import ../../../src/state/[accumulation_machine, accumulation_dispatch, accumulation_context, accumulation_effects]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, c2_records, state_outputs, assurances, composite,
  state_authorization, state_safrole, state_privileges, state_layout, state_trie]
import ../../../src/pvm/[initialize, program, machine, host_fetch, step, gas]
import ../../support/[pvm_accumulation_context, pvm_accumulation_program, arc_evidence]

## Prepare an actual bound service with ecalli at PC 5 and a dynamic return at PC 7.
proc prepared(id: byte, credit = 10000'u64): PreparedAccumulationMachine =
  initializeAccumulationMachine(pvmBootstrap(pvmEnvelope(
    [0'u8, 0, 9, 0, 0, 0, 0, 0, 10, id, 50, 0, 191, 0]), credit, includeContexts = true),
    InitializationLimits(envelope: InitializationByteLimit(64), program: ProgramByteLimit(32),
      jumps: JumpCountLimit(0), pages: PageLimit(5))).value

## A present empty input list still needs its canonical one-byte count.
proc limits(): FetchAccumulationLimits =
  FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
    operand: OperandLimits(maxBytes: ByteLimit(132)))

## Use independently configurable engine budgets; zero copy policy permits zero-length fetch queries.
proc run(source: PreparedAccumulationMachine, steps = 2'u64, calls = 1'u64,
    cycles = 200'u64): AccumulationDispatchResult =
  executeAccumulationMachine(source, pvmParameters(), limits(), MemoryByteLimit(0),
    ExecutionStepLimit(steps), HostCallLimit(calls), GasCycleLimit(cycles), pvmContextConfig())

for id in [1'u8, 24, 25]:
  # Every known unavailable accumulation call refuses locally instead of charging WHAT.
  assert run(prepared(id)).error == AccumulationDispatchError.UnsupportedHostCall
for id in [7'u8, 8, 9, 10, 11, 12, 13, 14, 28, 127, 255]:
  # Refine-only identifiers and the sign-extended full-width identifier all use F's fallback.
  let done = run(prepared(id))
  assert done.error == AccumulationDispatchError.None
  assert done.value.exit == StepExit.Halt
  assert uint64(machineInfo(done.value.machine).value.registers[7]) == high(uint64)-1
for id in [0'u8, 2, 28, 255]:
  let cost = (if id == 0: 48'u64 elif id == 2: 390'u64 else: 1000'u64)
  let source = prepared(id)
  let initial = source.accumulationMachine.value
  let price = uint64(blockGas(programOf(initial).value, CodeAddress(5), GasCycleLimit(200)).value)
  for available in [0'u64, cost-1, cost, cost+1]:
    # The independent block cost establishes exact host credit, without bypassing initialization.
    let done = run(prepared(id, price+available))
    assert done.error == AccumulationDispatchError.None
    let cpu = machineInfo(done.value.machine).value
    if available < cost:
      # Terminal deficits retain causing PC and preserve r7 except for F's mandatory WHAT assignment.
      assert done.value.exit == StepExit.OutOfGas
      assert uint64(cpu.gas) == 0 and uint64(cpu.gasDeficit) == cost-available
      assert uint64(cpu.pc) == 5
      let expected = (if id == 28 or id == 255: high(uint64)-1 else: 0xfeff0000'u64)
      assert uint64(cpu.registers[7]) == expected
    else:
      # Funded calls execute the prepaid return; zero requested bytes still returns parameter length.
      assert done.value.exit == StepExit.Halt
      assert uint64(cpu.gas) == available-cost and uint64(cpu.gasDeficit) == 0
      let expected = (if id == 0: available-cost elif id == 2: 122'u64 else: high(uint64)-1)
      assert uint64(cpu.registers[7]) == expected
  assert uint64(machineInfo(initial).value.gas) == 10000 # All successors leave the input intact.
let source = prepared(2)
for policy in 0..<3:
  # The adapter retains the engine's exact refusal instead of publishing partial progress.
  let done = (if policy == 0: run(source, steps = 0)
    elif policy == 1: run(source, calls = 0) else: run(source, cycles = 0))
  let expected = (if policy == 0: StepError.StepLimitExceeded
    elif policy == 1: StepError.HostCallLimitExceeded else: StepError.GasCycleLimitExceeded)
  assert done.error == AccumulationDispatchError.ExecutionFailure
  assert done.executionError == expected
assert run(default(PreparedAccumulationMachine)).error == AccumulationDispatchError.InvalidMachine
assert executeAccumulationMachine(source, default(Parameters), limits(), MemoryByteLimit(0),
  ExecutionStepLimit(2), HostCallLimit(1), GasCycleLimit(200), pvmContextConfig()).error ==
  AccumulationDispatchError.InvalidParameters
assert executeAccumulationMachine(source, pvmParameters(), default(FetchAccumulationLimits),
  MemoryByteLimit(0), ExecutionStepLimit(2), HostCallLimit(1), GasCycleLimit(200), pvmContextConfig(
  )).error ==
  AccumulationDispatchError.LimitExceeded
# Request one parameter byte at the initialized read-only argument address.
let copying = initializeAccumulationMachine(pvmBootstrap(pvmEnvelope(
  [0'u8, 0, 12, 0, 0, 0, 0, 0, 51, 9, 1, 10, 2, 50, 0, 63, 5]), 10000, includeContexts = true),
  InitializationLimits(envelope: InitializationByteLimit(64), program: ProgramByteLimit(32),
    jumps: JumpCountLimit(0), pages: PageLimit(5))).value
assert run(copying, steps = 3).error == AccumulationDispatchError.LimitExceeded
let panicked = executeAccumulationMachine(copying, pvmParameters(), limits(), MemoryByteLimit(1),
  ExecutionStepLimit(3), HostCallLimit(1), GasCycleLimit(200), pvmContextConfig())
assert panicked.error == AccumulationDispatchError.None and panicked.value.exit == StepExit.Panic
# Sufficient block gas still leaves an unavailable known call as a local scope refusal.
let known = prepared(1)
let knownPrice = uint64(blockGas(programOf(known.accumulationMachine.value).value,
  CodeAddress(5), GasCycleLimit(200)).value)
assert run(prepared(1, knownPrice)).error == AccumulationDispatchError.UnsupportedHostCall
## Fund a bounded actual engine run; copy policy is independent of gas and memory accessibility.
proc runEffects(source: PreparedAccumulationMachine, copyLimit = 32'u64,
    steps = 100'u64, calls = 10'u64): AccumulationDispatchResult =
  executeAccumulationMachine(source, pvmParameters(), limits(), MemoryByteLimit(copyLimit),
    ExecutionStepLimit(steps), HostCallLimit(calls), GasCycleLimit(1000), pvmContextConfig())

## Assert exact optional commitment bytes in one dimension; absence is not a zero hash.
proc checkYield(done: AccumulationDispatchResult, dimension: AccumulationDimension,
    present: bool, first = 0'u8): void =
  assert done.error == AccumulationDispatchError.None
  let context = done.effects.effectContext(dimension).value
  assert context.effectInfo.value.hasYield == present
  if present:
    # Every byte is checked; the authored RO/RW pages contain one nonzero octet followed by zeros.
    let bytes = array[32, byte](context.effectYield.value)
    assert bytes[0] == first
    for i in 1..<32:
      assert bytes[i] == 0
  else:
    assert context.effectYield.error == AccumulationEffectError.YieldAbsent # No fabricated commitment.

let halt = @[50'u8, 0]
let yieldCall = @[10'u8, 26]
let checkpointCall = @[10'u8, 18]
let regular = AccumulationDimension.Regular
let exceptional = AccumulationDimension.Exceptional
for id in [18'u8, 26]:
  let cost = (if id == 18: 103'u64 else: 98'u64)
  let initial = prepared(id).accumulationMachine.value
  let price = uint64(blockGas(programOf(initial).value, CodeAddress(5), GasCycleLimit(200)).value)
  for available in [0'u64, cost-1, cost, cost+1]:
    # Exact affordability witnesses preserve both dimensions on debt; zero credit still permits a paid halt.
    let done = runEffects(prepared(id, price+available))
    let cpu = machineInfo(done.value.machine).value
    if available < cost:
      assert done.value.exit == StepExit.OutOfGas
      assert uint64(cpu.gasDeficit) == cost-available and uint64(cpu.gas) == 0
      assert uint64(cpu.pc) == 5 and uint64(cpu.registers[7]) == 0xfeff0000'u64
      checkYield(done, regular, false)
    else:
      assert done.value.exit == StepExit.Halt
      assert uint64(cpu.gas) == available-cost and uint64(cpu.gasDeficit) == 0
      assert uint64(cpu.registers[7]) == (if id == 18: available-cost else: 0'u64)
      # A funded yield captures initial invocation arguments; later explicit-pointer tests check all bytes.
      assert done.effects.effectContext(regular).value.effectInfo.value.hasYield == (id == 26)
    for i in 0..<13:
      if i != 7:
        assert uint64(cpu.registers[i]) == uint64(machineInfo(initial).value.registers[
            i]) # Unrelated registers persist.
    checkYield(done, exceptional, false)
# Yield then checkpoint then a different yield leaves independently retained X and Y values.
let history = guestProgram([registerImmediate(7, 65536), yieldCall, checkpointCall,
  registerImmediate(7, 196608), yieldCall, halt])
let completed = runEffects(history)
assert completed.value.exit == StepExit.Halt
checkYield(completed, regular, true, 81)
checkYield(completed, exceptional, true, 73)
let repeated = runEffects(history)
checkYield(repeated, regular, true, 81)
checkYield(repeated, exceptional, true, 73)
assert uint64(machineInfo(history.accumulationMachine.value).value.gas) == 10000
for finalId in [18'u8, 26]:
  # A final unaffordable call cannot replace an already divergent regular/exceptional pair.
  let cost = (if finalId == 18: 103'u64 else: 98'u64)
  let instructions = [registerImmediate(7, 65536), yieldCall, checkpointCall, registerImmediate(7, 196608),
    yieldCall, @[10'u8, finalId], halt]
  let prototype = guestProgram(instructions).accumulationMachine.value
  let price = uint64(blockGas(programOf(prototype).value, CodeAddress(5), GasCycleLimit(1000)).value)
  let done = runEffects(guestProgram(instructions, price+98+103+98+cost-1))
  assert done.value.exit == StepExit.OutOfGas
  assert uint64(machineInfo(done.value.machine).value.gasDeficit) == 1
  assert uint64(machineInfo(done.value.machine).value.registers[7]) == 0
  checkYield(done, regular, true, 81)
  checkYield(done, exceptional, true, 73)
# Writable zero-filled bytes remain a present all-zero commitment; no implicit checkpoint is taken.
let zeroYield = runEffects(guestProgram([registerImmediate(7, 196609), yieldCall, halt]))
checkYield(zeroYield, regular, true)
checkYield(zeroYield, exceptional, false)
# Adjacent readable RW pages permit a full cross-page read, preserving all zero bytes.
let crossing = runEffects(guestProgram([registerImmediate(7, 196608'u64+4096-16), yieldCall, halt]))
checkYield(crossing, regular, true)
for address in [0'u64, 65536'u64+4096-16, 196608'u64+8192-16, 0xffffffff'u64,
    0x100010000'u64, high(uint64)]:
  # Protected, sparse, boundary and high-bit intervals must not wrap or yield a readable prefix.
  let failed = runEffects(guestProgram([registerImmediate(7, 65536), yieldCall, checkpointCall,
    registerImmediate(7, address), yieldCall, halt]))
  assert failed.value.exit == StepExit.Panic
  assert uint64(machineInfo(failed.value.machine).value.registers[7]) == address
  assert uint64(machineInfo(failed.value.machine).value.gasDeficit) == 0
  let price = uint64(blockGas(programOf(failed.value.machine).value, CodeAddress(5),
    GasCycleLimit(1000)).value)
  assert uint64(machineInfo(failed.value.machine).value.gas) == 10000-price-98-103-98
  checkYield(failed, regular, true, 73)
  checkYield(failed, exceptional, true, 73)
# Guest trap after a new yield retains both dimensions for subsequent Psi_A outcome selection.
let trapped = runEffects(guestProgram([checkpointCall, registerImmediate(7, 65536), yieldCall, @[0'u8]]))
assert trapped.value.exit == StepExit.Panic
checkYield(trapped, regular, true, 73)
checkYield(trapped, exceptional, false)
# Copy policy refuses locally after affordability, while an underfunded call never attempts copying.
assert runEffects(prepared(26), copyLimit = 31).error == AccumulationDispatchError.LimitExceeded
let yieldPrice = uint64(blockGas(programOf(prepared(26).accumulationMachine.value).value,
  CodeAddress(5), GasCycleLimit(200)).value)
assert runEffects(prepared(26, yieldPrice), copyLimit = 0).value.exit == StepExit.OutOfGas
assert runEffects(history, calls = 2).executionError == StepError.HostCallLimitExceeded
assert runEffects(history, steps = 2).executionError == StepError.StepLimitExceeded
assert runEffects(guestProgram([halt], includeContexts = false)).error ==
  AccumulationDispatchError.InvalidContext
var insufficient = pvmContextConfig()
insufficient.totalBytes = ByteLimit(0)
assert executeAccumulationMachine(history, pvmParameters(), limits(), MemoryByteLimit(32),
  ExecutionStepLimit(100), HostCallLimit(10), GasCycleLimit(1000), insufficient).error ==
  AccumulationDispatchError.LimitExceeded
checkYield(completed, regular, true, 81) # Later refusals never mutate already published effects.
## Each descriptor optionally loads r7 before issuing its host call; checkpoints use the preceding registers.
type GuestCall = (byte, uint32)

## Assemble only literal load_imm/ecalli/return opcodes with independently marked instruction boundaries.
proc patternedPrepared(sequence: openArray[GuestCall],
    credit = 10000'u64): PreparedAccumulationMachine =
  var code = @[0'u8, 0, 0, 0, 0]
  var starts = @[0, 1, 2, 3, 4]
  # Every yield receives an explicit pointer, including signed/full-width and inaccessible cases.
  for call in sequence:
    if call[0] == 26:
      starts.add(code.len)
      code.add(51); code.add(7)
      for i in 0..<4: code.add(byte((call[1] shr (8*i)) and 255)) # Literal E4 signed immediate.
    starts.add(code.len)
    code.add(10); code.add(call[0])
  starts.add(code.len)
  code.add(50); code.add(0)
  assert code.len < 128 # This authored helper uses one-byte compact program lengths.
  var raw = @[0'u8, 0, byte(code.len)]
  for octet in code: raw.add(octet) # The raw instruction sequence is followed by its boundary bitmask.
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or byte(1 shl (start mod 8))
  for octet in mask: raw.add(octet)
  let config = pvmContextConfig()
  let entries = @[
    authorizationEntry(AuthorizationKind.Queues,
      @[newSeq[AuthorizerHash](80), newSeq[AuthorizerHash](80)], config.queues).value,
    validatorEntry(ValidatorChapter.Staging, newSeq[StateValidator](6), config.staging).value,
    privilegeStateEntry(PrivilegeState(assigners: @[ServiceIndex(0), ServiceIndex(0)]),
      config.privileges).value]
  var envelope = @[32'u8, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0]
  # Literal patterned RO data catches every missing/reordered hash byte; following padding is all zero.
  for i in 0..<32: envelope.add(byte(73+i))
  envelope.add(81)
  for i in 0..<4: envelope.add(byte((uint64(raw.len) shr (8*i)) and 255))
  for octet in raw: envelope.add(octet)
  initializeAccumulationMachine(pvmBootstrap(envelope, credit, extra = entries),
    InitializationLimits(envelope: InitializationByteLimit(128), program: ProgramByteLimit(100),
      jumps: JumpCountLimit(0), pages: PageLimit(5))).value

# A nonconstant 32-byte commitment detects truncation, byte swaps and incorrect zero padding.
let patterned = runEffects(patternedPrepared([(26'u8, 65536'u32), (18'u8, 0'u32),
  (26'u8, 65568'u32)]))
assert patterned.error == AccumulationDispatchError.None and patterned.value.exit == StepExit.Halt
for dimension in [AccumulationDimension.Regular, AccumulationDimension.Exceptional]:
  # The checkpoint retains every patterned byte while the later yield captures a present zero value.
  let child = patterned.effects.effectContext(dimension).value
  assert child.effectInfo.value.hasYield
  let bytes = array[32, byte](child.effectYield.value)
  for i in 0..<32:
    assert bytes[i] == (if dimension == AccumulationDimension.Regular: 0'u8 else: byte(73+i))

let before = getOccupiedMem()
for iteration in 0..<1000:
  # Repeated execution captures/releases its own environment and never advances the original CPU.
  let done = runEffects(history)
  assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt
  checkYield(done, regular, true, 81)
  checkYield(done, exceptional, true, 73)
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_accumulation_dispatch", 1000, before, after)
echo "PVM accumulation dispatch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
