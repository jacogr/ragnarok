# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External-input fetch witnesses for presence, two-level indexing, prices and capture bounds.
## Exercises independent byte expectations, immutable handles, host dispatch and ARC release.

# @@Verification={"arc": "pvm_fetch_inputs_arc_release"}

import std/assertions
import std/syncio
import ../../../src/codec/work_package as codec_work_package
import ../../../src/codec/bounded as codec_bounded
import ../../../src/pvm/program as pvm_program
import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/gas as pvm_gas
import ../../../src/pvm/step as pvm_step
import ../../../src/pvm/host_fetch as pvm_host_fetch
import ../../support/testing_arc_evidence

# Fixed-size test segments distinguish each row and entry, including the last octet.
proc segment(marker: byte): FetchSegment =
  var bytes = default(array[4104, byte])
  bytes[0] = marker
  bytes[4103] = marker + 1
  FetchSegment(bytes)

# Ragged rows include both a present empty extrinsic and a row with no values.
proc inputs(): FetchInputs =
  FetchInputs(extrinsicsPresence: FetchPresence.Present, importsPresence: FetchPresence.Present,
    currentPresence: FetchPresence.Present, current: FetchItemIndex(2),
    extrinsics: @[@[@[11'u8, 12, 13], newSeq[byte](0)], newSeq[seq[byte]](0), @[@[21'u8, 22]]],
    imports: @[@[segment(31)], newSeq[FetchSegment](0), @[segment(41), segment(51)]])

# A trace sentinel detects whether attachment loses unrelated captured data.
proc base(): FetchContext =
  captureFetchContext(FetchPresence.Absent, FetchEntropy(default(array[32, byte])),
    FetchPresence.Present, [73'u8], FetchTraceLimit(1)).value

# Capture destroys all mutable input storage before any guest reads it.
proc capture(): FetchContext =
  var source = inputs()
  result = withFetchInputs(base(), source, FetchInputLimit(12317)).value
  source.extrinsics[0][0][0] = 255
  source.imports[2][1] = segment(99)
  source.current = FetchItemIndex(0)

# Independent expected selection preserves absence separately from a zero-length blob.
type Wanted = object
  present: bool
  bytes: seq[byte]

# The oracle maps literal fixture locations and does not use captured metadata or production lookup.
proc wanted(selector, first, second: uint64): Wanted =
  let row = (if selector == 4 or selector == 6: 2'u64 else: first)
  let entry = (if selector == 4 or selector == 6: first else: second)
  if selector == 3 or selector == 4:
    # Only these three explicit extrinsic locations are present.
    if row == 0 and entry == 0: return Wanted(present: true, bytes: @[11'u8, 12, 13])
    if row == 0 and entry == 1: return Wanted(present: true, bytes: @[])
    if row == 2 and entry == 0: return Wanted(present: true, bytes: @[21'u8, 22])
    return Wanted(present: false, bytes: @[])
  var marker = 0'u8
  if row == 0 and entry == 0:
    # Row zero has a single import.
    marker = 31
  elif row == 2 and entry == 0:
    # The first import of the current item is distinct from the first package import.
    marker = 41
  elif row == 2 and entry == 1:
    # The last import tests the upper valid entry index.
    marker = 51
  else:
    # Huge and ragged-row indices must not alias a valid value.
    return Wanted(present: false, bytes: @[])
  result = Wanted(present: true, bytes: newSeq[byte](4104))
  result.bytes[0] = marker
  result.bytes[4103] = marker + 1

# Sentinels expose unexpected register changes; current selectors must ignore r12.
proc arguments(selector, first, second, offset, requested, pointer: uint64): RegisterFile =
  result = default(RegisterFile)
  for i in 0..<13:
    # Replace only arguments and the halt-return register below.
    result[i] = RegisterValue(100 + uint64(i))
  result[0] = RegisterValue(0xffff0000'u64)
  result[7] = RegisterValue(pointer)
  result[8] = RegisterValue(offset)
  result[9] = RegisterValue(requested)
  result[10] = RegisterValue(selector)
  result[11] = RegisterValue(first)
  result[12] = RegisterValue(second)

let captured = capture()
let memory = captureMemory([PageImage(index: PageIndex(0), access: PageAccess.ReadWrite),
  PageImage(index: PageIndex(1), access: PageAccess.ReadWrite)], PageLimit(2)).value
for selector in [3'u64, 4'u64, 5'u64, 6'u64]:
  for first in [0'u64, 1'u64, 2'u64, 3'u64, high(uint64)]:
    for second in [0'u64, 1'u64, 2'u64, high(uint64)]:
      let expected = wanted(selector, first, second)
      for offset in [0'u64, 1'u64, 4103'u64, 4104'u64, high(uint64)]:
        for requested in [0'u64, 1'u64, 1025'u64, high(uint64)]:
          # Imports cost 171 independent of length; extrinsics use requested-length charging.
          let price = (if selector >= 5: 171'u64
            elif requested == high(uint64): 1729382256910270549'u64
            else: 85 + (96 * requested + 1023) div 1024)
          for credit in [price - 1, price, price + 1]:
            let regs = arguments(selector, first, second, offset, requested, 0)
            let response = fetchContextResponse(captured, MachineGas(credit), regs, memory,
              MemoryByteLimit(4104)).value
            let funded = credit >= price
            let start = min(offset, uint64(expected.bytes.len))
            let count = (if funded: min(requested, uint64(expected.bytes.len) - start) else: 0'u64)
            assert response.action == (if funded: HostAction.Continue else: HostAction.OutOfGas)
            assert uint64(response.gas) == (if funded: credit - price else: 0'u64)
            assert uint64(response.gasDeficit) == 0
            for i in 0..<13:
              # Funded r7 returns full length or NONE, never the copied suffix length.
              let value = (if i != 7 or not funded: uint64(regs[i])
                elif expected.present: uint64(expected.bytes.len) else: high(uint64))
              assert uint64(response.registers[i]) == value
            let bytes = readBytes(response.memory, MemoryAddress(0), MemoryLength(4105),
              MemoryByteLimit(4105)).value
            for i in 0..<bytes.len:
              # Covers the entire segment, its page crossing and an untouched trailing byte.
              assert bytes[i] == (if uint64(i) < count: expected.bytes[int(start) + i] else: 0'u8)

for ep in [FetchPresence.Absent, FetchPresence.Present]:
  for ip in [FetchPresence.Absent, FetchPresence.Present]:
    for cp in [FetchPresence.Absent, FetchPresence.Present]:
      var source = inputs()
      source.extrinsicsPresence = ep
      source.importsPresence = ip
      source.currentPresence = cp
      let context = withFetchInputs(captured, source, FetchInputLimit(12317)).value
      for selector in [3'u64, 4'u64, 5'u64, 6'u64]:
        # The two families and current-item identity have independent presence.
        let present = (if selector <= 4: ep else: ip) == FetchPresence.Present and
          (selector == 3 or selector == 5 or cp == FetchPresence.Present)
        let price = (if selector <= 4: 85'u64 else: 171'u64)
        let reply = fetchContextResponse(context, MachineGas(price), arguments(selector, 0, 0,
          0, 0, high(uint64)), memory, MemoryByteLimit(0)).value
        assert reply.action == HostAction.Continue
        let length = (if selector >= 5: 4104'u64 elif selector == 3: 3'u64 else: 2'u64)
        assert uint64(reply.registers[7]) == (if present: length else: high(uint64))

for selector in [3'u64, 4'u64, 5'u64, 6'u64]:
  let price = (if selector <= 4: 86'u64 else: 171'u64)
  let regs = arguments(selector, 0, 0, 0, 2, 8191)
  let panic = fetchContextResponse(captured, MachineGas(price), regs, memory, MemoryByteLimit(2)).value
  assert panic.action == HostAction.Panic and uint64(panic.registers[7]) == 8191
  assert pageImage(panic.memory, PageIndex(1)).value.bytes[4095] == 0
  assert fetchContextResponse(captured, MachineGas(price), arguments(selector, 0, 0, 0, 2, 0),
    memory, MemoryByteLimit(1)).error == FetchError.LimitExceeded
  let oog = fetchContextResponse(captured, MachineGas(price - 1), regs, memory, MemoryByteLimit(0)).value
  assert oog.action == HostAction.OutOfGas
let empty = fetchContextResponse(captured, MachineGas(86), arguments(3, 0, 1, 0, 2, high(uint64)),
  memory, MemoryByteLimit(0)).value
assert empty.action == HostAction.Continue and uint64(empty.registers[7]) == 0
assert withFetchInputs(default(FetchContext), inputs(), FetchInputLimit(12317)).error ==
    FetchError.InvalidContext
assert withFetchInputs(base(), inputs(), FetchInputLimit(12316)).error == FetchError.LimitExceeded
for index in [3'u64, high(uint64)]:
  # Caller-supplied current indices are rejected before narrowing, unlike guest lookup misses.
  var source = inputs()
  source.current = FetchItemIndex(index)
  assert withFetchInputs(base(), source, FetchInputLimit(12317)).error == FetchError.InvalidContext

# Empty rows and zero-byte preimages cannot bypass fixed metadata count bounds.
block:
  var source = FetchInputs(extrinsicsPresence: FetchPresence.Present,
    importsPresence: FetchPresence.Present, extrinsics: newSeq[seq[seq[byte]]](16),
    imports: newSeq[seq[FetchSegment]](16))
  source.extrinsics[15] = newSeq[seq[byte]](128)
  assert withFetchInputs(base(), source, FetchInputLimit(0)).error == FetchError.None
  source.extrinsics[0] = newSeq[seq[byte]](1)
  assert withFetchInputs(base(), source, FetchInputLimit(0)).error == FetchError.LimitExceeded
  source.extrinsics = newSeq[seq[seq[byte]]](17)
  assert withFetchInputs(base(), source, FetchInputLimit(0)).error == FetchError.LimitExceeded
  source.extrinsicsPresence = FetchPresence.Absent
  source.imports = newSeq[seq[FetchSegment]](17)
  assert withFetchInputs(base(), source, FetchInputLimit(0)).error == FetchError.LimitExceeded
  source.importsPresence = FetchPresence.Absent
  assert withFetchInputs(base(), source, FetchInputLimit(0)).error == FetchError.None

# The import count bound is aggregate across rows, independently of the byte budget.
block:
  var source = FetchInputs(importsPresence: FetchPresence.Present,
    imports: @[newSeq[FetchSegment](3072), newSeq[FetchSegment](0)])
  assert withFetchInputs(base(), source, FetchInputLimit(12607487)).error ==
      FetchError.LimitExceeded
  let maximum = withFetchInputs(base(), source, FetchInputLimit(12607488)).value
  let last = fetchContextResponse(maximum, MachineGas(171), arguments(5, 0, 3071, 0, 0, high(uint64)),
    memory, MemoryByteLimit(0)).value
  assert uint64(last.registers[7]) == 4104
  source.imports[1] = newSeq[FetchSegment](1)
  assert withFetchInputs(base(), source, FetchInputLimit(high(uint64))).error ==
      FetchError.LimitExceeded
  source.imports = newSeq[seq[FetchSegment]](0)
  source.currentPresence = FetchPresence.Present
  source.current = FetchItemIndex(0)
  assert withFetchInputs(base(), source, FetchInputLimit(0)).error == FetchError.InvalidContext
  source.current = FetchItemIndex(high(uint64))
  assert withFetchInputs(base(), source, FetchInputLimit(0)).error == FetchError.InvalidContext
  source.currentPresence = FetchPresence.Absent
  assert withFetchInputs(base(), source, FetchInputLimit(0)).error == FetchError.None

for selector in [3'u64, 4'u64, 5'u64, 6'u64]:
  # A base context with no input owner has the same charged absence as explicitly cleared inputs.
  let reply = fetchContextResponse(base(), MachineGas(1000), arguments(selector, high(uint64),
    high(uint64), 0, 1, high(uint64)), memory, MemoryByteLimit(0)).value
  assert reply.action == HostAction.Continue and uint64(reply.registers[7]) == high(uint64)

# Package attachment and clearing preserve external inputs; input replacement preserves old handles.
block:
  var wire = default(array[265, byte])
  wire[207] = 1
  let owner = decodeWorkPackage(wire, fullPackageConfig(ByteLimit(265))).value.owner
  let package = withFetchPackage(captured, FetchPresence.Present, owner, FetchPackageLimit(0),
    FetchEncodingLimit(265)).value
  let clearedPackage = withFetchPackage(package, FetchPresence.Absent, default(OwnedWorkPackage),
    FetchPackageLimit(0), FetchEncodingLimit(0)).value
  let clearedInputs = withFetchInputs(package, FetchInputs(), FetchInputLimit(0)).value
  for context in [captured, package, clearedPackage]:
    # Both attachment directions retain their unrelated immutable owners.
    let reply = fetchContextResponse(context, MachineGas(1000), arguments(6, 1, high(uint64), 0, 1, 0),
      memory, MemoryByteLimit(1)).value
    assert pageImage(reply.memory, PageIndex(0)).value.bytes[0] == 51
  let packageReply = fetchContextResponse(clearedInputs, MachineGas(1000), arguments(7, 0, 0, 0, 0, 0),
    memory, MemoryByteLimit(0)).value
  assert uint64(packageReply.registers[7]) == 265
  let trace = fetchContextResponse(clearedInputs, MachineGas(1000), arguments(2, 0, 0, 0, 1, 0),
    memory, MemoryByteLimit(1)).value
  assert pageImage(trace.memory, PageIndex(0)).value.bytes[0] == 73

# Dispatch fetch through the fallible host boundary, preserving local refusal semantics.
proc dispatch(context: var FetchContext, stopped: StepOutcome): HostResult[FetchError] {.raises: [].} =
  let cpu = machineInfo(stopped.machine).value
  let fetched = fetchContextResponse(context, cpu.gas, cpu.registers, memoryOf(
      stopped.machine).value,
    MemoryByteLimit(1))
  if fetched.error != FetchError.None:
    # Local policy failure must never become a guest panic.
    return hostFailure(fetched.error)
  hostSuccess[FetchError](fetched.value)

# Repeated capture and guest execution must release all nested arrays and memory snapshots.
proc cycle() =
  var context = capture()
  let code = decodeProgram([0'u8, 0, 4, 10, 2, 50, 0, 5], CodeAddress(0), ProgramByteLimit(8),
    JumpCountLimit(0)).value
  let memory = captureMemory([PageImage(index: PageIndex(0), access: PageAccess.ReadWrite)],
      PageLimit(1)).value
  for selector in [3'u64, 4'u64, 5'u64, 6'u64]:
    # Each selector runs through a real ecalli followed by the guest halt return.
    let machine = captureMachine(code, memory, MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000),
      blockCharged: true, registers: arguments(selector, 0, 0, 0, 1, 0))).value
    let done = executeWithHost(machine, context, dispatch, ExecutionStepLimit(2), HostCallLimit(1),
        GasCycleLimit(0))
    assert done.error == HostExecutionError.None and done.value.exit == StepExit.Halt
    assert uint64(machineInfo(done.value.machine).value.registers[7]) == uint64(wanted(selector, 0, 0).bytes.len)

cycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Nested descriptor ownership is acyclic and contains no callback history.
  cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_fetch_inputs", 1000, before, after)
echo "PVM external input fetch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
