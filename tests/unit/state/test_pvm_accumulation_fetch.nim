# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Machine-derived accumulation fetch witnesses cover configuration, entropy, inputs and absent families.
## Exercises real host dispatch, resource refusals, immutable lifetime and ARC release.

# @@Verification={"arc": "pvm_accumulation_fetch_arc_release"}

import std/assertions
import std/syncio
import ../../../src/state/accumulation_machine as state_accumulation_machine
import ../../../src/state/accumulation_fetch as state_accumulation_fetch
import ../../../src/chain/parameters as chain_parameters
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/c2_records as codec_c2_records
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/pvm/initialize as pvm_initialize
import ../../../src/pvm/program as pvm_program
import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/host_fetch as pvm_host_fetch
import ../../../src/pvm/step as pvm_step
import ../../../src/pvm/gas as pvm_gas
import ../../support/pvm_accumulation_context
import ../../support/testing_arc_evidence

## Test-only provider refusal verifies setup never rehashes or reauthenticates prepared state.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

## Local code and page policy covers the authored halt and fetch/return programs.
proc initialization(): InitializationLimits =
  InitializationLimits(envelope: InitializationByteLimit(64), program: ProgramByteLimit(32),
    jumps: JumpCountLimit(0), pages: PageLimit(5))

## Exact count and canonical wire budget, including one compact list-count byte.
proc limits(count: uint64): FetchAccumulationLimits =
  FetchAccumulationLimits(items: ElementLimit(count), bytes: ByteLimit(1+132*count),
    operand: OperandLimits(maxBytes: ByteLimit(132)))

## Build distinct real prepared machines, retaining the chosen service, input count and entropy together.
proc prepared(count: int, entropy: byte, service = 42'u32): PreparedAccumulationMachine =
  var word = default(array[32, byte])
  word[0] = entropy
  word[31] = entropy
  initializeAccumulationMachine(pvmBootstrap(pvmEnvelope(), 10000, count, service,
    StateEntropyWord(word), true), initialization()).value

## Capture survives destruction of the complete code/state/argument/input preparation graph.
proc capture(count: int, entropy: byte, service = 42'u32): FetchContext =
  machineFetchContext(prepared(count, entropy, service), pvmParameters(), limits(uint64(count))).value

## Literal tagged failed-work operands have zero fixed hashes except the per-digest payload marker.
proc record(index: int): seq[byte] =
  result = newSeq[byte](132)
  result[97] = byte(index+1)
  result[130] = 2 # C.2 panic tag follows zero compact gas; final zero is the empty trace count.

## Use the actual fetch response on a bounded writable memory snapshot.
proc response(context: FetchContext, selector, index: uint64, requested = 512'u64): HostResponse =
  let memory = captureMemory([PageImage(index: PageIndex(0), access: PageAccess.ReadWrite)],
    PageLimit(1)).value
  var registers = default(RegisterFile)
  registers[9] = RegisterValue(requested)
  registers[10] = RegisterValue(selector)
  registers[11] = RegisterValue(index)
  registers[12] = RegisterValue(high(uint64))
  fetchContextResponse(context, MachineGas(10000), registers, memory, MemoryByteLimit(512)).value

## Compare the complete value and returned untruncated length against independent expected bytes.
proc check(context: FetchContext, selector, index: uint64, bytes: seq[byte]) =
  let fetched = response(context, selector, index)
  assert fetched.action == HostAction.Continue and uint64(fetched.registers[7]) == uint64(
      bytes.len), "fetch length selector " & $selector
  assert readBytes(fetched.memory, MemoryAddress(0), MemoryLength(bytes.len), MemoryByteLimit(
      512)).value == bytes, "fetch bytes selector " & $selector

let context = capture(3, 17, 7)
var expectedEntropy = newSeq[byte](32)
expectedEntropy[0] = 17
expectedEntropy[31] = 17
check(context, 1, high(uint64), expectedEntropy)
var parameterBytes = newSeq[byte](122)
for i in 0..<parameterBytes.len:
  parameterBytes[i] = 255 # Exact independent configured-parameter representation.
check(context, 0, high(uint64), parameterBytes)
var whole = @[3'u8]
for i in 0..<3:
  # Retain the selected service's report/digest order, without a second selector at assembly time.
  let bytes = record(i)
  check(context, 15, uint64(i), bytes)
  for octet in bytes:
    whole.add(octet) # Exactly one count prefix wraps the complete record sequence.
check(context, 14, high(uint64), whole)
for selector in 2'u64..13'u64:
  # Accumulation has no authorizer trace, work package, current item, extrinsics or imported segments.
  let absent = response(context, selector, 0)
  assert absent.action == HostAction.Continue and uint64(absent.registers[7]) == high(uint64)
for index in [3'u64, high(uint64)]:
  assert uint64(response(context, 15, index).registers[7]) == high(
      uint64) # No wrapped guest input ordinal.
let empty = capture(0, 0, 99)
check(empty, 1, 0, newSeq[byte](32)) # Present zero entropy is not NONE.
check(empty, 14, 0, @[0'u8])
assert uint64(response(empty, 15, 0).registers[7]) == high(uint64)
check(context, 14, 0, whole) # A different service's empty context cannot modify the original list.
check(context, 1, 0, expectedEntropy)
let selectedMachine = prepared(3, 17)
failHash(1)
assert machineFetchContext(selectedMachine, pvmParameters(), limits(3)).error ==
    InvocationFetchError.None
failHash(0)
assert machineFetchContext(default(PreparedAccumulationMachine), pvmParameters(), limits(
    0)).error ==
  InvocationFetchError.InvalidMachine
assert machineFetchContext(selectedMachine, default(Parameters), limits(3)).error ==
    InvocationFetchError.InvalidParameters
for field in 0..<3:
  # New local limits must still apply after successful service and CPU preparation.
  var tight = limits(3)
  case field
  of 0: tight.items = ElementLimit(2) # Count before traversal/allocation.
  of 1: tight.bytes = ByteLimit(396) # The list count is part of the aggregate byte policy.
  else: tight.operand.maxBytes = ByteLimit(131) # Fresh per-record policy also applies.
  assert machineFetchContext(selectedMachine, pvmParameters(), tight).error ==
      InvocationFetchError.LimitExceeded
var noBytes = limits(0)
noBytes.bytes = ByteLimit(0)
assert machineFetchContext(prepared(0, 0), pvmParameters(), noBytes).error ==
    InvocationFetchError.LimitExceeded

## Propagate local fetch errors explicitly through the real host execution loop.
proc dispatch(context: var FetchContext, stopped: StepOutcome): HostResult[FetchError] {.raises: [].} =
  let cpu = machineInfo(stopped.machine).value
  let fetched = fetchContextResponse(context, cpu.gas, cpu.registers, memoryOf(
      stopped.machine).value,
    MemoryByteLimit(512))
  if fetched.error != FetchError.None:
    return hostFailure(fetched.error) # Local errors cannot become a fabricated guest result.
  hostSuccess[FetchError](fetched.value)

## A PC-5 fetch(0) followed by jump_ind r0 uses zero requested bytes and returns the full parameter size.
proc cycle() =
  let envelope = pvmEnvelope([0'u8, 0, 9, 0, 0, 0, 0, 0, 10, 2, 50, 0, 191, 0])
  let initialized = initializeAccumulationMachine(pvmBootstrap(envelope, 10000, 2), initialization()).value
  var context = machineFetchContext(initialized, pvmParameters(), limits(2)).value
  let done = executeWithHost(initialized.accumulationMachine.value, context, dispatch,
    ExecutionStepLimit(2), HostCallLimit(1), GasCycleLimit(200))
  assert done.error == HostExecutionError.None, "fetch dispatch error " & $done.error
  assert done.value.exit == StepExit.Halt, "fetch dispatch exit"
  assert uint64(machineInfo(done.value.machine).value.registers[7]) == 122, "fetch dispatch length"
  check(context, 15, 1, record(1))
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  cycle() # Captured buffers have no references back to the machine or preparation graph.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_accumulation_fetch", 1000, before, after)
echo "PVM accumulation fetch context passed"
echo "ARC_RELEASE cycles=1000 unchanged"
