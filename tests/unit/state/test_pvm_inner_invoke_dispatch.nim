# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_inner_invoke_dispatch_arc_release"}

## Genuine refinement bootstraps compose creation/invoke/frame return and preserve exact nested engine refusal reasons.

import std/[assertions, syncio]
import ../../../src/state/[refinement_bootstrap, refinement_dispatch, refinement_outcome]
import ../../../src/pvm/[inner_machines, machine, program, step, gas, refinement_exports]
import ../../../src/codec/[composite, work_digest]
import ../../support/[pvm_refinement_outcome, pvm_inner_lifecycle, pvm_inner_invoke, arc_evidence]

proc limits(): RefinementInvocationLimits =
  ## Inner segment work is independently finite; the outer instruction/call policies remain unchanged.
  result = refinementLimits()
  result.inner = innerLimits()
proc code(): seq[byte] =
  ## Authored inner load_imm r7=42 followed by jump_ind r0 proves executed register mutation in the returned frame.
  invokeBlob([@[51'u8, 7, 42], @[50'u8, 0]])
proc fixture(blob = code(), fuel = 100'u64, frameOutput = true,
    twice = false): PreparedRefinementBootstrap =
  ## A distinct embedded program and frame travel through genuine standard initialization and source capture.
  var writable = newSeq[byte](176)
  for index, octet in blob: writable[index] = octet
  let regs = invokeRegisters()
  for word in 0..<14:
    let value = if word == 0: fuel else: uint64(regs[word-1])
    for octet in 0..<8: writable[64+word*8+octet] = byte((value shr (octet*8)) and 255)
  var instructions = refinementInnerCreate(length = uint64(blob.len), suffix = @[
      refinementImmediate(8, 196672), @[10'u8, 14]])
  if twice:
    instructions.add(refinementImmediate(7, 0))
    instructions.add(refinementImmediate(8, 196672))
    instructions.add(@[10'u8, 14]) # A returned HOST does not recursively dispatch; the outer guest explicitly resumes.
  if frameOutput:
    instructions.add(refinementImmediate(7, 196672))
    instructions.add(refinementImmediate(8, 112)) # Return the updated frame at its exact caller address.
  instructions.add(@[50'u8, 0])
  refinementFixture(instructions, writable = writable)
proc run(source: PreparedRefinementBootstrap, cap = limits()): RefinementInvocationResult[
    RefinementInvocation] =
  ## Only the original bootstrap owner authorizes complete execution and normalized output.
  runRefinementInvocation(source, [], refinementInputs(), ExportOffset(7), cap)
proc raw(source: PreparedRefinementBootstrap, cap = limits()): RefinementDispatchResult[
    RefinementOutcome] =
  ## Inspect host return codes using that same bootstrap's own captured immutable execution environment.
  let captured = source.bootstrapHosts([], refinementInputs(), ExportOffset(7), cap.capture).value
  executeRefinement(captured, cap.copy, cap.exports, cap.steps, cap.calls, cap.cycles, cap.inner)
let source = fixture()
let innerProgram = decodeProgram(code(), CodeAddress(0), ProgramByteLimit(100), JumpCountLimit(0)).value
let innerCost = uint64(blockGas(innerProgram, CodeAddress(0), GasCycleLimit(1000)).value)
for replay in 0..<2:
  let done = run(source).value
  let bytes = done.refinementOutput.value
  assert bytes.len == 112 and bytes[64] == 42 # Frame word eight is inner r7, independent of outer result registers.
  assert bytes[0] == byte(100-innerCost)
  assert done.refinementInfo.value.kind == WorkKind.Success
  assert uint64(done.refinementInfo.value.gasUsed) == refinementPrice(source)+1862+(1862+(
      264*uint64(code().len)+1023) div 1024)+968+innerCost
  assert source.bootstrapMachine.value.memoryOf.value.pageImage(PageIndex(48)).value.bytes[128] ==
      7 # Original frame r7 low byte is unchanged.
# Inner panic/fault/host/OOG are protocol return codes and leave the outer guest able to continue.
for row, blob in [invokeBlob([@[0'u8]]), invokeBlob([@[52'u8, 7, 0, 0, 1], @[50'u8, 0]]),
    invokeBlob([@[10'u8, 14], @[50'u8, 0]])]:
  let guest = fixture(blob, frameOutput = false)
  let done = raw(guest).value
  assert uint64(done.outcome.machine.machineInfo.value.registers[7]) == uint64(row+1)
  assert run(guest).value.refinementInfo.value.kind == WorkKind.Success
let oog = fixture(fuel = 0, frameOutput = false)
assert uint64(raw(oog).value.outcome.machine.machineInfo.value.registers[7]) == 4
assert run(oog).value.refinementInfo.value.kind == WorkKind.Success
let resumed = fixture(invokeBlob([@[10'u8, 14], @[50'u8, 0]]), twice = true)
assert run(resumed).value.refinementOutput.value.len ==
    112 # Explicit outer resume preserves paid inner block state.
# Nested local policies retain exact StepError and never masquerade as an inner OOG result or host refusal.
for policy in 0..<2:
  var cap = limits()
  if policy == 0: cap.inner.steps = ExecutionStepLimit(0)
  else: cap.inner.cycles = GasCycleLimit(0)
  let refused = run(source, cap)
  assert refused.error == RefinementInvocationError.ExecutionFailure
  assert refused.executionError == (if policy == 0: StepError.StepLimitExceeded else: StepError.GasCycleLimitExceeded)
var noCopy = limits()
noCopy.copy = MemoryByteLimit(0)
assert run(source, noCopy).error == RefinementInvocationError.None # Invoke has a fixed 112-byte protocol frame, not a variable transfer payload.
# Fresh captured sources, inner CPU/RAM/frame owners, normalized output and failed scratch runs release together.
proc cycle() =
  ## No genuine bootstrap, frame or inner segment generation is retained between isolated lifetime iterations.
  let fresh = fixture()
  assert run(fresh).value.refinementOutput.value[64] == 42
  var cap = limits()
  cap.inner.steps = ExecutionStepLimit(0)
  assert run(fresh, cap).executionError == StepError.StepLimitExceeded
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_inner_invoke_dispatch", 1000, before, after)
echo "PVM inner invoke dispatch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
