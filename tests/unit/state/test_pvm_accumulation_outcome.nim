# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_outcome_arc_release"}

## Authored Psi_M/Psi_A terminal normalization witnesses use actual guest execution and retained effects.
## Exercises gas caps, checkpoint selection, bounded return overrides, provenance and ARC release.

import std/[assertions, syncio]
import ../../../src/state/[accumulation_machine, accumulation_dispatch, accumulation_outcome,
  accumulation_context, accumulation_effects, accumulation_invocation, accumulation_service]
import ../../../src/pvm/[machine, program, step, gas, host_fetch]
import ../../../src/codec/[bounded, c2_records, state_outputs]
import ../../support/[pvm_accumulation_context, pvm_accumulation_program, arc_evidence]

## Refuse backend hashing only after execution; collapsing immutable effects must perform no hashes.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

## Execute only authored initialized machines with independent host/copy/engine limits.
proc run(source: PreparedAccumulationMachine, steps = 100'u64,
    calls = 10'u64): AccumulationDispatchResult =
  executeAccumulationMachine(source, pvmParameters(),
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
      operand: OperandLimits(maxBytes: ByteLimit(132))), MemoryByteLimit(32),
    ExecutionStepLimit(steps), HostCallLimit(calls), GasCycleLimit(1000), pvmContextConfig())

## Check optional output bytes exactly, independently of the selected context's earlier version.
proc checkYield(outcome: AccumulationOutcome, present: bool, first = 0'u8) =
  let info = outcome.outcomeInfo.value
  let context = outcome.outcomeContext.value
  assert info.hasYield == present and context.effectInfo.value.hasYield == present
  assert info.transfers == 0 and info.provisions == 0
  if present:
    let bytes = array[32, byte](context.effectYield.value)
    assert bytes[0] == first
    for i in 1..<32:
      assert bytes[i] == 0 # All authored RO/RW return regions contain just one nonzero leading octet.
  else:
    assert context.effectYield.error == AccumulationEffectError.YieldAbsent # Absence is never a zero commitment.

let halt = @[50'u8, 0]
let yieldCall = @[10'u8, 26]
let checkpointCall = @[10'u8, 18]
let regular = AccumulationDimension.Regular
let exceptional = AccumulationDimension.Exceptional
let invalidExecution = default(AccumulationDispatchResult)
let refused = normalizeAccumulationOutcome(invalidExecution)
assert refused.error == AccumulationOutcomeError.InvalidExecution
assert default(AccumulationOutcome).outcomeInfo.error == AccumulationOutcomeError.Uninitialized
assert default(AccumulationOutcome).outcomeContext.error == AccumulationOutcomeError.Uninitialized
let defaultResult = default(AccumulationOutcomeResult[AccumulationOutcome])
assert defaultResult.error == AccumulationOutcomeError.Uninitialized
# Initial r8 is the non-32-byte argument length, so an unmodified halt has no commitment override.
let emptyExecution = run(guestProgram([halt]))
let empty = normalizeAccumulationOutcome(emptyExecution).value
checkYield(empty, false)
assert empty.outcomeInfo.value.dimension == regular
assert empty.outcomeInfo.value.termination == AccumulationTermination.Halt
assert uint32(empty.outcomeInfo.value.service) == 42
for length in [0'u64, 31, 32, 33, high(uint64)]:
  # Exactly 32 readable bytes override the prior yield; all other lengths need no output allocation.
  let executed = run(guestProgram([registerImmediate(7, 196608), yieldCall,
    registerImmediate(7, 65536), registerImmediate(8, length), halt]))
  let outcome = normalizeAccumulationOutcome(executed).value
  checkYield(outcome, true, (if length == 32: 73'u8 else: 81'u8))
  assert outcome.outcomeInfo.value.dimension == regular
  assert outcome.outcomeInfo.value.termination == AccumulationTermination.Halt
  let cpu = machineInfo(executed.value.machine).value
  assert uint64(outcome.outcomeInfo.value.gasUsed) == 10000-uint64(cpu.gas)
  # Normalization must not mutate the original execution's yield, including the override case.
  let original = array[32, byte](executed.effects.effectContext(regular).value.effectYield.value)
  assert original[0] == 81
for address in [0'u64, 65536'u64+4096-16, 0xffffffff'u64, 0x100010000'u64, high(uint64)]:
  # An unreadable exactly-32-byte return becomes empty output, retaining the regular yield without panic.
  let executed = run(guestProgram([registerImmediate(7, 65536), yieldCall,
    registerImmediate(7, address), registerImmediate(8, 32), halt]))
  let outcome = normalizeAccumulationOutcome(executed).value
  checkYield(outcome, true, 73)
  assert outcome.outcomeInfo.value.termination == AccumulationTermination.Halt
# A readable all-zero hash is a present override, even without an earlier yield.
let zero = normalizeAccumulationOutcome(run(guestProgram([registerImmediate(7, 196609),
  registerImmediate(8, 32), halt]))).value
checkYield(zero, true)
let crossPage = normalizeAccumulationOutcome(run(guestProgram([
  registerImmediate(7, 196608'u64+4096-16), registerImmediate(8, 32), halt]))).value
checkYield(crossPage, true)
# Checkpoint commits the first yield; later regular changes must be rolled back on trap or physical fault.
for ending in [@[0'u8], @[52'u8, 2, 0, 0, 4]]:
  let source = guestProgram([registerImmediate(7, 65536), yieldCall, checkpointCall,
    registerImmediate(7, 196608), yieldCall, ending, halt])
  let executed = run(source)
  assert executed.value.exit == (if ending[0] == 0: StepExit.Panic else: StepExit.Fault)
  let outcome = normalizeAccumulationOutcome(executed).value
  assert outcome.outcomeInfo.value.dimension == exceptional
  assert outcome.outcomeInfo.value.termination == AccumulationTermination.Panic
  checkYield(outcome, true, 73)
# Without a checkpoint, panic discards a regular yield instead of synthesizing a present zero hash.
let unchecked = normalizeAccumulationOutcome(run(guestProgram([
  registerImmediate(7, 65536), yieldCall, @[0'u8]]))).value
checkYield(unchecked, false)
# Return registers cannot override exceptional output, even when they point to a readable hash.
let exceptionalReturn = normalizeAccumulationOutcome(run(guestProgram([
  registerImmediate(7, 65536), yieldCall, checkpointCall, registerImmediate(7, 196608),
  registerImmediate(8, 32), @[0'u8]]))).value
checkYield(exceptionalReturn, true, 73)
# A host deficit is inspectable in raw execution but never inflates protocol gas usage above initial credit.
let debtInstructions = [registerImmediate(7, 65536), yieldCall, checkpointCall,
  registerImmediate(7, 196608), yieldCall, @[10'u8, 18], halt]
let prototype = guestProgram(debtInstructions).accumulationMachine.value
let price = uint64(blockGas(programOf(prototype).value, CodeAddress(5), GasCycleLimit(1000)).value)
let credit = price+98+103+98+102
let debtExecution = run(guestProgram(debtInstructions, credit))
assert debtExecution.value.exit == StepExit.OutOfGas
assert uint64(machineInfo(debtExecution.value.machine).value.gasDeficit) == 1
let debt = normalizeAccumulationOutcome(debtExecution).value
assert uint64(debt.outcomeInfo.value.gasUsed) == credit
assert debt.outcomeInfo.value.termination == AccumulationTermination.OutOfGas
checkYield(debt, true, 73)
# Whole-block affordability does not debit gas on refusal, so instruction OOG can consume zero gas.
let instructionOog = normalizeAccumulationOutcome(run(guestProgram([halt], 0))).value
assert instructionOog.outcomeInfo.value.termination == AccumulationTermination.OutOfGas
assert uint64(instructionOog.outcomeInfo.value.gasUsed) == 0
checkYield(instructionOog, false)
for executed in [run(guestProgram([halt]), steps = 0), run(guestProgram([yieldCall, halt]),
    calls = 0), run(guestProgram([@[10'u8, 1], halt]))]:
  # Engine budgets and unsupported host calls refuse locally; none may become a normalized guest failure.
  assert normalizeAccumulationOutcome(executed).error == AccumulationOutcomeError.InvalidExecution
# Capture/normalization only retains immutable owners and copied fields; no backend call is required.
failHash(1)
let retained = normalizeAccumulationOutcome(debtExecution).value
checkYield(retained, true, 73)
assert uint32(retained.outcomeContext.value.effectInitialContext.value.contextInfo.value.service) == 42
let provenance = retained.outcomeContext.value.effectInitialContext.value.contextInvocation.value
assert uint64(provenance.bootstrapService.value.serviceInfo.value.gas) == credit
failHash(0)
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Each complete run releases transient CPUs, both dimensions and normalized overlays without retaining history.
  let executed = run(guestProgram([registerImmediate(7, 196608), yieldCall,
    registerImmediate(7, 65536), registerImmediate(8, 32), halt]))
  let outcome = normalizeAccumulationOutcome(executed).value
  checkYield(outcome, true, 73)
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_accumulation_outcome", 1000, before, after)
echo "PVM accumulation outcome passed"
echo "ARC_RELEASE cycles=1000 unchanged"
