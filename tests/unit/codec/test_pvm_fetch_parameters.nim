# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact GP parameter-layout witnesses and selector-0 configuration, gas and ownership tests.
## Exercises configured profiles, host dispatch, immutable attachment and native ARC release.

## Verification: {"arc": "pvm_fetch_parameters_arc_release"}

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[work_package, bounded]
import ../../../src/pvm/[program, machine, gas, step, host_fetch]
import ../../support/arc_evidence

# Literal GP 0.8.0 values and wire octets are independent of the production width table/encoder.
const Values = [10'u64, 1'u64, 100'u64, 341'u64, 19200'u64, 600'u64, 10000000'u64, 50000000'u64,
    5000000000'u64, 3500000000'u64, 8'u64, 16'u64, 8'u64, 16'u64, 14400'u64, 8'u64, 6'u64, 80'u64,
    10'u64, 128'u64, 5'u64, 64000'u64, 13791360'u64, 4000000'u64, 3072'u64, 49152'u64, 128'u64,
    3072'u64, 500'u64]
const Wire = [10'u8, 0'u8, 0'u8, 0'u8, 0'u8, 0'u8, 0'u8, 0'u8, 1'u8, 0'u8, 0'u8, 0'u8, 0'u8, 0'u8,
    0'u8, 0'u8, 100'u8, 0'u8, 0'u8, 0'u8, 0'u8, 0'u8, 0'u8, 0'u8, 85'u8, 1'u8, 0'u8, 75'u8, 0'u8,
    0'u8, 88'u8, 2'u8, 0'u8, 0'u8, 128'u8, 150'u8, 152'u8, 0'u8, 0'u8, 0'u8, 0'u8, 0'u8, 128'u8,
    240'u8, 250'u8, 2'u8, 0'u8, 0'u8, 0'u8, 0'u8, 0'u8, 242'u8, 5'u8, 42'u8, 1'u8, 0'u8, 0'u8, 0'u8,
    0'u8, 195'u8, 157'u8, 208'u8, 0'u8, 0'u8, 0'u8, 0'u8, 8'u8, 0'u8, 16'u8, 0'u8, 8'u8, 0'u8,
    16'u8, 0'u8, 64'u8, 56'u8, 0'u8, 0'u8, 8'u8, 0'u8, 6'u8, 0'u8, 80'u8, 0'u8, 10'u8, 0'u8, 128'u8,
    0'u8, 5'u8, 0'u8, 0'u8, 250'u8, 0'u8, 0'u8, 128'u8, 112'u8, 210'u8, 0'u8, 0'u8, 9'u8, 61'u8,
    0'u8, 0'u8, 12'u8, 0'u8, 0'u8, 0'u8, 192'u8, 0'u8, 0'u8, 128'u8, 0'u8, 0'u8, 0'u8, 0'u8, 12'u8,
    0'u8, 0'u8, 244'u8, 1'u8, 0'u8, 0'u8]

# Valid invocation base without configured chain parameters.
proc base(): FetchContext =
  captureFetchContext(FetchPresence.Absent, FetchEntropy(default(array[32, byte])),
    FetchPresence.Present, [37'u8], FetchTraceLimit(1)).value

# Deliberately huge unused item indices must not influence the protocol-parameter value.
proc arguments(offset, requested, pointer: uint64): RegisterFile =
  result = default(RegisterFile)
  for i in 0..<13:
    # Sentinels detect all unexpected register mutations.
    result[i] = RegisterValue(high(uint64))
  result[0] = RegisterValue(0xffff0000'u64)
  result[7] = RegisterValue(pointer)
  result[8] = RegisterValue(offset)
  result[9] = RegisterValue(requested)
  result[10] = RegisterValue(0)

let decoded = decodeParameters(Wire)
assert decoded.ok and decoded.value.valid
for field in low(Parameter)..high(Parameter):
  # Every field must decode at the independently specified offset and width.
  assert decoded.value.get(field) == Values[ord(field)]
assert encodeParameters(decoded.value) == Wire
assert not default(Parameters).valid
var maximal = default(array[122, byte])
for i in 0..<122:
  # All fixed-width maxima fit, including uint64 gas/deposit fields and equal epoch/tail bounds.
  maximal[i] = 255
let maxParameters = decodeParameters(maximal)
assert maxParameters.ok and encodeParameters(maxParameters.value) == maximal
for length in 0..<122:
  # Truncated records must never create a partial parameter snapshot.
  assert not decodeParameters(newSeq[byte](length)).ok
assert not decodeParameters(newSeq[byte](123)).ok
var small = default(array[122, byte])
small[24] = 2
small[30] = 10
small[80] = 1
small[84] = 1
small[118] = 9
let smallParameters = decodeParameters(small)
assert smallParameters.ok and encodeParameters(smallParameters.value) == small
for offset in [24, 30, 80, 84]:
  # Reused decoder validation must still reject unusable populations and clocks.
  var invalid = small
  invalid[offset] = 0
  assert not decodeParameters(invalid).ok
var invalidTail = small
invalidTail[118] = 11
assert not decodeParameters(invalidTail).ok

let captured = withFetchParameters(base(), decoded.value).value
let memory = captureMemory([PageImage(index: PageIndex(0), access: PageAccess.ReadWrite)],
    PageLimit(1)).value
assert withFetchParameters(default(FetchContext), decoded.value).error == FetchError.InvalidContext
assert withFetchParameters(base(), default(Parameters)).error == FetchError.InvalidContext
assert fetchContextResponse(base(), MachineGas(1000), arguments(0, 0, 0), memory,
  MemoryByteLimit(0)).error == FetchError.InvalidContext
for offset in [0'u64, 1'u64, 24'u64, 33'u64, 66'u64, 121'u64, 122'u64, high(uint64)]:
  for requested in [0'u64, 1'u64, 122'u64, 1025'u64, high(uint64)]:
    for credit in [0'u64, 389'u64, 390'u64, 391'u64]:
      # Cost is always 390, irrespective of requested length or clipping.
      let regs = arguments(offset, requested, 0)
      let reply = fetchContextResponse(captured, MachineGas(credit), regs, memory, MemoryByteLimit(122)).value
      let funded = credit >= 390
      let start = min(offset, 122'u64)
      let count = (if funded: min(requested, 122'u64 - start) else: 0'u64)
      assert reply.action == (if funded: HostAction.Continue else: HostAction.OutOfGas)
      assert uint64(reply.gas) == (if funded: credit - 390 else: 0'u64)
      assert uint64(reply.gasDeficit) == (if funded: 0'u64 else: 390 - credit)
      for i in 0..<13:
        # Only funded r7 changes and reports the complete tuple length.
        assert uint64(reply.registers[i]) == (if i == 7 and funded: 122'u64 else: uint64(regs[i]))
      let page = pageImage(reply.memory, PageIndex(0)).value
      for i in 0..122:
        # Includes the untouched suffix after the selected bytes.
        assert page.bytes[i] == (if uint64(i) < count: Wire[int(start) + i] else: 0'u8)
let empty = fetchContextResponse(captured, MachineGas(390), arguments(high(uint64), high(uint64),
  high(uint64)), memory, MemoryByteLimit(0)).value
assert empty.action == HostAction.Continue and uint64(empty.registers[7]) == 122
let panic = fetchContextResponse(captured, MachineGas(390), arguments(0, 2, 4095), memory,
  MemoryByteLimit(2)).value
assert panic.action == HostAction.Panic and uint64(panic.registers[7]) == 4095
assert uint64(panic.gas) == 0 and pageImage(panic.memory, PageIndex(0)).value.bytes[4095] == 0
assert fetchContextResponse(captured, MachineGas(390), arguments(0, 2, 0), memory,
  MemoryByteLimit(1)).error == FetchError.LimitExceeded
let oog = fetchContextResponse(captured, MachineGas(389), arguments(0, 2, 4095), memory,
  MemoryByteLimit(0)).value
assert oog.action == HostAction.OutOfGas

# Both attachment directions and clearing other selections preserve parameter identity.
block:
  var wire = default(array[265, byte])
  wire[207] = 1
  let owner = decodeWorkPackage(wire, fullPackageConfig(ByteLimit(265))).value.owner
  let package = withFetchPackage(captured, FetchPresence.Present, owner, FetchPackageLimit(0),
    FetchEncodingLimit(265)).value
  let inputs = withFetchInputs(package, FetchInputs(extrinsicsPresence: FetchPresence.Present,
    extrinsics: @[@[@[55'u8]]]), FetchInputLimit(1)).value
  let cleared = withFetchPackage(inputs, FetchPresence.Absent, default(OwnedWorkPackage),
    FetchPackageLimit(0), FetchEncodingLimit(0)).value
  for context in [captured, package, inputs, cleared]:
    # Canonical parameters survive package/input replacement and clearing.
    let reply = fetchContextResponse(context, MachineGas(390), arguments(0, 122, 0), memory,
      MemoryByteLimit(122)).value
    let page = pageImage(reply.memory, PageIndex(0)).value
    for i in 0..<122:
      # All original fields remain, not just the length or first byte.
      assert page.bytes[i] == Wire[i]
  let replaced = withFetchParameters(inputs, smallParameters.value).value
  let reply = fetchContextResponse(replaced, MachineGas(390), arguments(0, 122, 0), memory,
    MemoryByteLimit(122)).value
  let page = pageImage(reply.memory, PageIndex(0)).value
  for i in 0..<122:
    # A configured alternate profile is returned unchanged, without canonical-network substitution.
    assert page.bytes[i] == small[i]
  var regs = arguments(0, 0, 0)
  regs[10] = RegisterValue(7)
  assert uint64(fetchContextResponse(replaced, MachineGas(1000), regs, memory,
    MemoryByteLimit(0)).value.registers[7]) == 265
  regs[10] = RegisterValue(3)
  regs[11] = RegisterValue(0)
  regs[12] = RegisterValue(0)
  regs[9] = RegisterValue(1)
  assert pageImage(fetchContextResponse(replaced, MachineGas(1000), regs, memory,
    MemoryByteLimit(1)).value.memory, PageIndex(0)).value.bytes[0] == 55
  let prior = fetchContextResponse(captured, MachineGas(390), arguments(0, 1, 0), memory,
    MemoryByteLimit(1)).value
  assert pageImage(prior.memory, PageIndex(0)).value.bytes[0] == 10
  regs[10] = RegisterValue(2)
  regs[9] = RegisterValue(1)
  assert pageImage(fetchContextResponse(replaced, MachineGas(1000), regs, memory,
    MemoryByteLimit(1)).value.memory, PageIndex(0)).value.bytes[0] == 37

# Fallible host dispatch propagates missing configuration without manufacturing a guest outcome.
proc dispatch(context: var FetchContext, stopped: StepOutcome): HostResult[FetchError] {.raises: [].} =
  let cpu = machineInfo(stopped.machine).value
  let fetched = fetchContextResponse(context, cpu.gas, cpu.registers, memoryOf(
      stopped.machine).value,
    MemoryByteLimit(122))
  if fetched.error != FetchError.None:
    # Preserve local errors for the invocation caller.
    return hostFailure(fetched.error)
  hostSuccess[FetchError](fetched.value)

# Temporary source bytes, parameter owner and execution snapshots all have bounded acyclic lifetimes.
proc cycle() =
  var bytes = Wire
  var context = withFetchParameters(base(), decodeParameters(bytes).value).value
  bytes[0] = 255
  let code = decodeProgram([0'u8, 0, 4, 10, 2, 50, 0, 5], CodeAddress(0), ProgramByteLimit(8),
    JumpCountLimit(0)).value
  let memory = captureMemory([PageImage(index: PageIndex(0), access: PageAccess.ReadWrite)],
      PageLimit(1)).value
  let machine = captureMachine(code, memory, MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000),
    blockCharged: true, registers: arguments(0, 122, 0))).value
  let done = executeWithHost(machine, context, dispatch, ExecutionStepLimit(2), HostCallLimit(1),
      GasCycleLimit(0))
  assert done.error == HostExecutionError.None and done.value.exit == StepExit.Halt
  let page = pageImage(memoryOf(done.value.machine).value, PageIndex(0)).value
  for i in 0..<122:
    # Source mutation after capture cannot change guest-visible protocol parameters.
    assert page.bytes[i] == Wire[i]

cycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Repeated fixed captures and real host dispatch must release all owners.
  cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_fetch_parameters", 1000, before, after)
echo "PVM parameter fetch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
