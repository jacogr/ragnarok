# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native fixed-entry accumulation initialization through actual service and bootstrap preparation.
## Verifies exact CPU/memory binding, resource and code failures, retained children and ARC release.

# @@Verification={"arc": "pvm_accumulation_machine_arc_release"}

import std/[assertions, syncio]
import ../../../src/state/[accumulation_machine, accumulation_invocation, accumulation_service]
import ../../../src/pvm/[initialize, program, machine, step, gas]
import ../../support/[pvm_accumulation_context, arc_evidence]

## Test-only provider refusal proves initialization uses the existing immutable bootstrap without rehashing.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

## Exact envelope/program extents and five materialized pages for the authored fixture.
proc policy(): InitializationLimits =
  InitializationLimits(envelope: InitializationByteLimit(28), program: ProgramByteLimit(11),
    jumps: JumpCountLimit(0), pages: PageLimit(5))

## Retain a machine after every preparation owner leaves scope; caller code/argument mutation is isolated.
proc captured(): Machine =
  var code = pvmEnvelope()
  let bootstrap = pvmBootstrap(code)
  code[0] = 255 # Source mutation must not alter the owned account code.
  var arguments = bootstrap.bootstrapArguments.value
  arguments[0] = 0 # Extracted argument arrays are independent of the bootstrap.
  let prepared = initializeAccumulationMachine(bootstrap, policy()).value
  assert prepared.machineBootstrap.value.bootstrapArguments.value == @[128'u8, 128, 42, 0]
  result = prepared.accumulationMachine.value

## Assert every register and the preserved declared gas before any guest instruction executes.
proc checkCpu(cpu: Machine, gas: uint64) =
  let info = machineInfo(cpu).value
  assert uint64(info.pc) == 5 and uint64(info.gas) == gas and not info.blockCharged
  for i in 0..<13:
    # Only r0, r1, r7 and r8 are initialized by the standard argument wrapper.
    let expected = (if i == 0: 0xffff0000'u64 elif i == 1: 0xfefe0000'u64
      elif i == 7: 0xfeff0000'u64 elif i == 8: 4'u64 else: 0'u64)
    assert uint64(info.registers[i]) == expected

# A real report-derived nonempty service must pass its actual count through the compact argument tuple.
let populated = initializeAccumulationMachine(pvmBootstrap(pvmEnvelope(), 100, 3), policy()).value
assert readBytes(memoryOf(populated.accumulationMachine.value).value, MemoryAddress(0xfeff0000'u32),
  MemoryLength(4), MemoryByteLimit(4)).value == @[128'u8, 128, 42, 3]

let source = pvmBootstrap(pvmEnvelope())
let initialized = initializeAccumulationMachine(source, policy())
assert initialized.error == AccumulationMachineError.None
let prepared = initialized.value
let cpu = captured()
checkCpu(cpu, 100)
let memory = memoryOf(cpu).value
assert readBytes(memory, MemoryAddress(0xfeff0000'u32), MemoryLength(4),
  MemoryByteLimit(4)).value == @[128'u8, 128, 42, 0]
assert readBytes(memory, MemoryAddress(65536), MemoryLength(1), MemoryByteLimit(1)).value == @[73'u8]
assert readBytes(memory, MemoryAddress(196608), MemoryLength(1), MemoryByteLimit(1)).value == @[81'u8]
for page in [16'u32, 0xfeff0'u32]:
  assert pageImage(memory, PageIndex(page)).value.access == PageAccess.ReadOnly # RO payload and arguments.
for page in [48'u32, 49'u32, 0xfefdf'u32]:
  assert pageImage(memory, PageIndex(page)).value.access == PageAccess.ReadWrite # Data, heap and stack.
assert pageImage(memory, PageIndex(17)).value.access == PageAccess.Inaccessible
let changed = writeBytes(memory, MemoryAddress(196608), [99'u8], MemoryByteLimit(1)).value
assert readBytes(changed, MemoryAddress(196608), MemoryLength(1), MemoryByteLimit(1)).value == @[99'u8]
assert readBytes(memory, MemoryAddress(196608), MemoryLength(1), MemoryByteLimit(1)).value == @[81'u8]
let retained = prepared.machineBootstrap.value
assert retained.bootstrapArguments.value == @[128'u8, 128, 42, 0]
assert retained.bootstrapService.value.serviceCode.value == pvmEnvelope()
assert uint32(retained.bootstrapInfo.value.service) == 42
assert execute(cpu, ExecutionStepLimit(1), GasCycleLimit(100)).value.exit == StepExit.Halt
checkCpu(cpu, 100) # Executing a retained child cannot mutate the stored initial CPU.

for credit in [0'u64, 1'u64, uint64(high(int64)), high(uint64)]:
  # Preserve the complete declared unsigned gas domain; high values are inspected, not claimed as gate closure.
  let selected = initializeAccumulationMachine(pvmBootstrap(pvmEnvelope(), credit), policy()).value
  checkCpu(selected.accumulationMachine.value, credit)
  if credit == 0:
    assert execute(selected.accumulationMachine.value, ExecutionStepLimit(1),
      GasCycleLimit(100)).value.exit == StepExit.OutOfGas # Zero funding is not a preparation failure.
  elif credit == 1:
    assert execute(selected.accumulationMachine.value, ExecutionStepLimit(1),
      GasCycleLimit(100)).value.exit == StepExit.OutOfGas # Indirect jump pipeline cost exceeds one gas.
  else:
    discard # Full-width gas preservation alone does not resolve invocation gas-domain parity.

assert initializeAccumulationMachine(default(PreparedAccumulationInvocation), policy()).error ==
  AccumulationMachineError.InvalidInvocation
assert default(PreparedAccumulationMachine).accumulationMachine.error ==
    AccumulationMachineError.Uninitialized
assert default(PreparedAccumulationMachine).machineBootstrap.error ==
    AccumulationMachineError.Uninitialized
for field in 0..<3:
  # Every independent allocation/decoding ceiling refuses one below its exact fixture requirement.
  var tight = policy()
  case field
  of 0: tight.envelope = InitializationByteLimit(27) # Before copying the complete service code.
  of 1: tight.program = ProgramByteLimit(10) # Embedded program has independent policy.
  else: tight.pages = PageLimit(4) # Include RO, RW, extra heap, stack and argument pages.
  assert initializeAccumulationMachine(source, tight).error ==
      AccumulationMachineError.LimitExceeded
assert initializeAccumulationMachine(pvmBootstrap([]), policy()).error ==
    AccumulationMachineError.InvalidEnvelope
var trailing = pvmEnvelope()
trailing.add(0)
var wide = policy()
wide.envelope = InitializationByteLimit(1000)
assert initializeAccumulationMachine(pvmBootstrap(trailing), wide).error ==
    AccumulationMachineError.InvalidEnvelope
for raw in [@[0'u8, 0, 1, 0, 1], @[255'u8], newSeq[byte](0), @[0'u8, 0, 7, 0, 0, 0, 0, 50, 0, 0, 31]]:
  # Valid entry-zero code is insufficient: accumulation's required PC 5 must also exist and be valid.
  assert initializeAccumulationMachine(pvmBootstrap(pvmEnvelope(raw)), wide).error ==
    AccumulationMachineError.InvalidProgram
# The mandatory accumulation entry5 exists; only the final missing successor causes rejection.
var validationPolicy = wide
validationPolicy.program = ProgramByteLimit(64)
for program in [@[0'u8, 0, 9, 0, 0, 0, 0, 0, 51, 7, 7, 1, 63, 1],
    @[0'u8, 0, 11, 0, 0, 0, 0, 0, 51, 7, 7, 170, 0, 253, 63, 1]]:
  let bootstrap = pvmBootstrap(pvmEnvelope(program))
  let code = bootstrap.bootstrapService.value.serviceCode.value
  assert initializeAccumulationMachine(bootstrap, validationPolicy).error ==
      AccumulationMachineError.InvalidProgram
  assert bootstrap.bootstrapService.value.serviceCode.value == code
# A trailing trap restores preparation at the same accumulation entry; raw execution still panics normally.
let successor = pvmEnvelope([0'u8, 0, 10, 0, 0, 0, 0, 0, 51, 7, 7, 1, 0, 63, 3])
let successorCpu = initializeAccumulationMachine(pvmBootstrap(successor),
    validationPolicy).value.accumulationMachine.value
assert execute(successorCpu, ExecutionStepLimit(3), GasCycleLimit(100)).value.exit == StepExit.Panic
assert uint64(machineInfo(successorCpu).value.registers[7]) == 0xfeff0000'u64

# Entry5 loads the dynamic address2; width0 has no usable entry and must panic within two steps.
for width in [0'u8, 5]:
  var tableProgram = @[1'u8, width, 10]
  for index in 0..<int(width): tableProgram.add(0)
  for octet in [0'u8, 0, 0, 0, 0, 51, 8, 2, 50, 8, 63, 1]: tableProgram.add(octet)
  let bootstrap = pvmBootstrap(pvmEnvelope(tableProgram))
  var tableLimits = validationPolicy
  tableLimits.jumps = JumpCountLimit(1)
  let checked = initializeAccumulationMachine(bootstrap, tableLimits)
  if width == 0:
    assert checked.error == AccumulationMachineError.None
    let execution = execute(checked.value.accumulationMachine.value, ExecutionStepLimit(2),
        GasCycleLimit(100))
    assert execution.error == StepError.None and execution.value.exit == StepExit.Panic
    assert uint64(machineInfo(execution.value.machine).value.registers[8]) == 2
  else:
    assert checked.error == AccumulationMachineError.InvalidProgram

let panic = pvmEnvelope([0'u8, 0, 6, 0, 0, 0, 0, 0, 0, 63])
let trapping = initializeAccumulationMachine(pvmBootstrap(panic),
    wide).value.accumulationMachine.value
assert execute(trapping, ExecutionStepLimit(1), GasCycleLimit(100)).value.exit == StepExit.Panic
failHash(1)
assert initializeAccumulationMachine(source, policy()).error == AccumulationMachineError.None
failHash(0)

## Repeated success/refusal releases wrapper, copied code, program and mapped-memory owners.
proc cycle() =
  let bootstrap = pvmBootstrap(pvmEnvelope())
  let prepared = initializeAccumulationMachine(bootstrap, policy()).value
  checkCpu(prepared.accumulationMachine.value, 100)
  var tight = policy()
  tight.pages = PageLimit(4)
  assert initializeAccumulationMachine(bootstrap, tight).error ==
      AccumulationMachineError.LimitExceeded
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  cycle() # No child points back to its wrapper or retains caller-owned arrays.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_accumulation_machine", 1000, before, after)
echo "PVM accumulation machine passed"
echo "ARC_RELEASE cycles=1000 unchanged"
