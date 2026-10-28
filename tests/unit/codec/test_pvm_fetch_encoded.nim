# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact canonical package fetch witnesses with independent wire bytes and bounded capture.
## Exercises selector 7 prices, clipping, immutable ownership, host dispatch and ARC release.

# @@Verification={"arc": "pvm_fetch_encoded_arc_release"}

import std/assertions
import std/syncio
import ../../../src/codec/work_package as codec_work_package
import ../../../src/codec/work_report as codec_work_report
import ../../../src/codec/work_digest as codec_work_digest
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/bounded as codec_bounded
import ../../../src/pvm/program as pvm_program
import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/gas as pvm_gas
import ../../../src/pvm/step as pvm_step
import ../../../src/pvm/host_fetch as pvm_host_fetch
import ../../support/testing_arc_evidence

# Independent C.2 layout: two items, compact two-byte blob lengths and nonempty manifests.
proc expected(): seq[byte] =
  result = newSeq[byte](653)
  result[0] = 7
  result[4] = 19
  result[36] = 23
  result[68] = 29
  result[205] = 128
  result[206] = 128
  for i in 0..<128:
    # Authorization bytes follow compact length 128, encoded as 80 80.
    result[207 + i] = byte(i)
  result[335] = 2
  result[336] = 41
  result[337] = 42
  result[338] = 2
  result[339] = 11
  result[343] = 31
  result[375] = 1
  result[379] = 1
  result[383] = 3
  result[391] = 2
  result[393] = 128
  result[394] = 129
  for i in 0..<129:
    # Payload length 129 uses 80 81; payload contents have their own recognizable range.
    result[395 + i] = byte(255 - i)
  result[524] = 1
  result[525] = 37
  result[557] = 5
  result[559] = 1
  result[560] = 43
  result[592] = 9
  result[596] = 13

# Source fields correspond to the literal layout above without using it to construct this object.
proc package(): OwnedWorkPackage =
  var code = default(array[32, byte])
  code[0] = 19
  var itemCode = default(array[32, byte])
  itemCode[0] = 31
  var root = SegmentRoot()
  root.bytes[0] = 37
  var hash = default(array[32, byte])
  hash[0] = 43
  var source = WorkPackage(host: AuthorizerHost(7), codeHash: CodeHash(code),
    authorization: newSeq[byte](128), configuration: @[41'u8, 42],
    items: @[WorkItem(service: ServiceIndex(11), codeHash: CodeHash(itemCode),
      refineGas: Gas(0x100000001'u64), accumulateGas: Gas(3), exports: ExportCount(2),
      payload: newSeq[byte](129), imports: @[rootImport(root, ImportIndex(5))],
      extrinsics: @[ExtrinsicCommitment(hash: ExtrinsicHash(hash), length: ExtrinsicLength(9))]),
      WorkItem(service: ServiceIndex(13))])
  source.context.anchor.bytes[0] = 23
  source.context.anchorSlot = AnchorSlot(29)
  for i in 0..<128:
    # Distinct token bytes exercise compact framing and later slicing.
    source.authorization[i] = byte(i)
  for i in 0..<129:
    # Distinct payload bytes distinguish full package encoding from raw blob concatenation.
    source.items[0].payload[i] = byte(255 - i)
  var wire = newSeq[byte](1024)
  let config = fullPackageConfig(ByteLimit(1024))
  let size = encodeWorkPackage(source, config, wire).value
  let wanted = expected()
  assert size == wanted.len
  for i in 0..<size:
    # The host's expected bytes do not depend on its production encoder.
    assert wire[i] == wanted[i]
  wire[size] = 199
  let decoded = decodeWorkPackage(wire.toOpenArray(0, size), config).value
  assert decoded.consumed == size
  result = decoded.owner
  source.authorization[0] = 255
  for i in 0..<wire.len:
    # Decoder trailing bytes and later caller mutations must never enter the fetched encoding.
    wire[i] = 0

# An explicitly absent base is valid, unlike a default handle.
proc base(): FetchContext =
  captureFetchContext(FetchPresence.Absent, FetchEntropy(default(array[32, byte])),
    FetchPresence.Absent, [], FetchTraceLimit(0)).value

# Maximal item registers prove selector 7 ignores indices; other registers carry sentinels.
proc arguments(offset, requested, pointer: uint64): RegisterFile =
  result = default(RegisterFile)
  for i in 0..<13:
    # Only fetch arguments and the return jump register are replaced.
    result[i] = RegisterValue(high(uint64))
  result[0] = RegisterValue(0xffff0000'u64)
  result[7] = RegisterValue(pointer)
  result[8] = RegisterValue(offset)
  result[9] = RegisterValue(requested)
  result[10] = RegisterValue(7)

let wanted = expected()
let captured = withFetchPackage(base(), FetchPresence.Present, package(), FetchPackageLimit(259),
  FetchEncodingLimit(653)).value
for limit in [0'u64, 652'u64]:
  # The complete canonical prefix must fit, even when raw blobs fit their separate budget.
  assert withFetchPackage(base(), FetchPresence.Present, package(), FetchPackageLimit(259),
    FetchEncodingLimit(limit)).error == FetchError.LimitExceeded
assert withFetchPackage(base(), FetchPresence.Present, package(), FetchPackageLimit(258),
  FetchEncodingLimit(high(uint64))).error == FetchError.LimitExceeded
let generous = withFetchPackage(base(), FetchPresence.Present, package(), FetchPackageLimit(259),
  FetchEncodingLimit(high(uint64))).value
let absent = withFetchPackage(captured, FetchPresence.Absent, default(OwnedWorkPackage),
  FetchPackageLimit(0), FetchEncodingLimit(0)).value
let memory = captureMemory([PageImage(index: PageIndex(0), access: PageAccess.ReadWrite)],
    PageLimit(1)).value
for requested in [0'u64, 1'u64, 653'u64, 1023'u64, 1024'u64, 1025'u64, high(uint64)]:
  # Independently derive ordinary prices, with a literal maximal price avoiding oracle overflow.
  let price = (if requested == high(uint64): 1729382256910270549'u64
    else: 85 + (96 * requested + 1023) div 1024)
  for credit in [price - 1, price, price + 1]:
    for offset in [0'u64, 205'u64, 206'u64, 393'u64, 652'u64, 653'u64, high(uint64)]:
      let regs = arguments(offset, requested, 0)
      let response = fetchContextResponse(captured, MachineGas(credit), regs, memory,
          MemoryByteLimit(653)).value
      let funded = credit >= price
      let start = min(offset, 653'u64)
      let count = (if funded: min(requested, 653'u64 - start) else: 0'u64)
      assert response.action == (if funded: HostAction.Continue else: HostAction.OutOfGas)
      assert uint64(response.gas) == (if funded: credit - price else: 0'u64)
      assert uint64(response.gasDeficit) == 0
      for i in 0..<13:
        # Funded r7 is the full encoded length, not the clipped copy length.
        assert uint64(response.registers[i]) == (if i == 7 and funded: 653'u64 else: uint64(regs[i]))
      let page = pageImage(response.memory, PageIndex(0)).value
      for i in 0..653:
        # Entire selected prefix and an untouched suffix witness atomic, correctly offset writes.
        assert page.bytes[i] == (if uint64(i) < count: wanted[int(start) + i] else: 0'u8)
    let none = fetchContextResponse(absent, MachineGas(credit), arguments(0, requested, high(
        uint64)),
      memory, MemoryByteLimit(0)).value
    assert none.action == (if credit >= price: HostAction.Continue else: HostAction.OutOfGas)
    assert uint64(none.registers[7]) == high(uint64)
    assert uint64(none.gas) == (if credit >= price: credit - price else: 0'u64)
let noCopy = fetchContextResponse(generous, MachineGas(high(uint64)), arguments(high(uint64),
  high(uint64), high(uint64)), memory, MemoryByteLimit(0)).value
assert noCopy.action == HostAction.Continue and uint64(noCopy.registers[7]) == 653
let crossing = arguments(0, 2, 4095)
let panic = fetchContextResponse(captured, MachineGas(86), crossing, memory, MemoryByteLimit(2)).value
assert panic.action == HostAction.Panic and uint64(panic.registers[7]) == 4095
assert uint64(panic.gas) == 0 and pageImage(panic.memory, PageIndex(0)).value.bytes[4095] == 0
assert fetchContextResponse(captured, MachineGas(86), arguments(0, 2, 0), memory,
  MemoryByteLimit(1)).error == FetchError.LimitExceeded
let oog = fetchContextResponse(captured, MachineGas(85), crossing, memory, MemoryByteLimit(0)).value
assert oog.action == HostAction.OutOfGas and uint64(oog.gasDeficit) == 0
assert pageImage(memory, PageIndex(0)).value.bytes[0] == 0

# Empty blobs still form a nonempty canonical package, and replacement preserves earlier handles.
block:
  var wire = default(array[265, byte])
  wire[207] = 1
  let owner = decodeWorkPackage(wire, fullPackageConfig(ByteLimit(265))).value.owner
  assert withFetchPackage(captured, FetchPresence.Present, owner, FetchPackageLimit(0),
    FetchEncodingLimit(264)).error == FetchError.LimitExceeded
  let replacement = withFetchPackage(captured, FetchPresence.Present, owner, FetchPackageLimit(0),
    FetchEncodingLimit(265)).value
  let fetched = fetchContextResponse(replacement, MachineGas(1000), arguments(0, 265, 0), memory,
    MemoryByteLimit(265)).value
  assert fetched.action == HostAction.Continue and uint64(fetched.registers[7]) == 265
  let page = pageImage(fetched.memory, PageIndex(0)).value
  for i in 0..<265:
    # The sole nonzero byte is the required item count; empty payloads do not imply absence.
    assert page.bytes[i] == wire[i]
  let prior = fetchContextResponse(captured, MachineGas(1000), arguments(0, 1, 0), memory,
    MemoryByteLimit(1)).value
  assert uint64(prior.registers[7]) == 653
  assert pageImage(prior.memory, PageIndex(0)).value.bytes[0] == 7

# Fallible dispatch preserves local errors separately from charged guest outcomes.
proc dispatch(context: var FetchContext, stopped: StepOutcome): HostResult[FetchError] {.raises: [].} =
  assert uint64(stopped.hostCall) == 2
  let cpu = machineInfo(stopped.machine).value
  let fetched = fetchContextResponse(context, cpu.gas, cpu.registers, memoryOf(
      stopped.machine).value,
    MemoryByteLimit(653))
  if fetched.error != FetchError.None:
    # No partial host response escapes a local refusal.
    return hostFailure(fetched.error)
  hostSuccess[FetchError](fetched.value)

# Temporary codec storage, encoding snapshot and final guest memory must all be released.
proc cycle() =
  var context = withFetchPackage(base(), FetchPresence.Present, package(), FetchPackageLimit(259),
    FetchEncodingLimit(653)).value
  let code = decodeProgram([0'u8, 0, 4, 10, 2, 50, 0, 5], CodeAddress(0), ProgramByteLimit(8),
    JumpCountLimit(0)).value
  let memory = captureMemory([PageImage(index: PageIndex(0), access: PageAccess.ReadWrite)],
      PageLimit(1)).value
  let machine = captureMachine(code, memory, MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000),
    blockCharged: true, registers: arguments(0, 653, 0))).value
  let done = executeWithHost(machine, context, dispatch, ExecutionStepLimit(2), HostCallLimit(1),
      GasCycleLimit(0))
  assert done.error == HostExecutionError.None and done.value.exit == StepExit.Halt
  assert uint64(machineInfo(done.value.machine).value.registers[7]) == 653
  let page = pageImage(memoryOf(done.value.machine).value, PageIndex(0)).value
  let bytes = expected()
  for i in 0..<bytes.len:
    # A complete guest host dispatch returns exactly the independently described wire encoding.
    assert page.bytes[i] == bytes[i]

cycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  # No capture or execution path retains the temporary package or response graph.
  cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_fetch_encoded", 1000, before, after)
echo "PVM encoded package fetch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
