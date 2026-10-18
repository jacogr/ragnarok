# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent exact-byte witnesses for fetch context and work-item summaries.
## Covers fixed bounds, clipping, charges, atomic copies, retained ownership and ARC release.

import std/[assertions, syncio]
import ../../../src/codec/[work_package, work_report, work_digest, composite, bounded]
import ../../../src/pvm/[program, machine, gas, step, host_fetch]
import ../../support/arc_evidence

# Distinct field bytes make field order, scalar width and hash order observable.
proc source(count, prerequisites: int): WorkPackage =
  result = WorkPackage(items: newSeq[WorkItem](count))
  result.context.prerequisiteCount = prerequisites
  result.context.anchorSlot = AnchorSlot(0x04030201)
  result.context.lookupSlot = LookupSlot(0x08070605)
  for i in 0..<32:
    # Every context hash has a different marker and varies within the field.
    result.context.anchor.bytes[i] = byte(i)
    result.context.stateRoot.bytes[i] = byte(i + 32)
    result.context.accumulationRoot.bytes[i] = byte(i + 64)
    result.context.lookupAnchor.bytes[i] = byte(i + 96)
    result.context.lookupStateRoot.bytes[i] = byte(i + 128)
  for i in 0..<prerequisites:
    # Strictly ordered distinct prerequisites satisfy the canonical codec contract.
    result.context.prerequisites[i].bytes[0] = byte(i + 1)
  var hash = default(array[32, byte])
  for i in 0..<32:
    # Summary code hashes must not reverse or use a package-level hash instead.
    hash[i] = byte(255 - i)
  result.items[0] = WorkItem(service: ServiceIndex(0x04030201), codeHash: CodeHash(hash),
    refineGas: Gas(0x100000001'u64), accumulateGas: Gas(0x010203), exports: ExportCount(258),
    payload: newSeq[byte](259), imports: newSeq[ImportReference](257),
    extrinsics: newSeq[ExtrinsicCommitment](2))
  for i in 0..<257:
    # A multi-byte count distinguishes E2 from a compact count and from the import byte size.
    result.items[0].imports[i] = rootImport(SegmentRoot(), ImportIndex(i))
  for i in 1..<count:
    # Ordered summaries retain the position of even otherwise empty work items.
    result.items[i].service = ServiceIndex(i)

# Capture from temporary codec/source storage, then destroy or mutate every caller-owned input.
proc capture(count, prerequisites: int): FetchContext =
  var value = source(count, prerequisites)
  var wire = newSeq[byte](32768)
  let config = fullPackageConfig(ByteLimit(32768))
  let size = encodeWorkPackage(value, config, wire).value
  let package = decodeWorkPackage(wire.toOpenArray(0, size - 1), config).value.owner
  let base = captureFetchContext(FetchPresence.Absent, FetchEntropy(default(array[32, byte])),
    FetchPresence.Absent, [], FetchTraceLimit(0)).value
  result = withFetchPackage(base, FetchPresence.Present, package, FetchPackageLimit(259)).value
  value.items[0].service = ServiceIndex(0)
  for i in 0..<wire.len:
    # Captured metadata cannot depend on the encoder output's lifetime or subsequent mutation.
    wire[i] = 0

# Literal byte layout is independent of all production serializers.
proc summary(index: int): seq[byte] =
  result = newSeq[byte](62)
  if index != 0:
    # Later items contain only their one-byte service index in a four-byte field.
    result[0] = byte(index)
    return
  for i in 0..<4:
    # Service 0x04030201 is little-endian E4.
    result[i] = byte(i + 1)
  for i in 0..<32:
    # Code hash follows the service without a prefix.
    result[4 + i] = byte(255 - i)
  result[36] = 1
  result[40] = 1
  result[44] = 3
  result[45] = 2
  result[46] = 1
  result[52] = 2
  result[53] = 1
  result[54] = 1
  result[55] = 1
  result[56] = 2
  result[58] = 3
  result[59] = 1

# Independently assemble context bytes, including the compact prerequisite count.
proc contextBytes(prerequisites: int): seq[byte] =
  result = newSeq[byte](169 + prerequisites * 32)
  for field in 0..<5:
    let start = [0, 36, 68, 100, 136][field]
    for i in 0..<32:
      # Five marker ranges identify the five different hash domains.
      result[start + i] = byte(field * 32 + i)
  for i in 0..<4:
    # Slots occupy E4 between hashes, without affecting hash order.
    result[32 + i] = byte(i + 1)
    result[132 + i] = byte(i + 5)
  result[168] = byte(prerequisites)
  for i in 0..<prerequisites:
    # Each prerequisite is a full 32-byte hash, without individual framing.
    result[169 + 32 * i] = byte(i + 1)

# The expected list has one item-count prefix, followed by exact fixed-size records.
proc expected(selector: uint64, index, count, prerequisites: int): seq[byte] =
  if selector == 10:
    # Context encoding ignores both item registers.
    return contextBytes(prerequisites)
  if selector == 12:
    # A single summary omits the list prefix.
    return summary(index)
  result = @[byte(count)]
  for i in 0..<count:
    # Preserve package item order instead of sorting by metadata.
    for octet in summary(i):
      # Append the literal record bytes without calling a production codec.
      result.add(octet)

# All nonargument registers carry sentinels and r12 is deliberately out of range.
proc arguments(selector, index, offset, requested, pointer: uint64): RegisterFile =
  result = default(RegisterFile)
  for i in 0..<13:
    # Detect unexpected register changes in every funded/underfunded response.
    result[i] = RegisterValue(high(uint64) - uint64(i))
  result[7] = RegisterValue(pointer)
  result[8] = RegisterValue(offset)
  result[9] = RegisterValue(requested)
  result[10] = RegisterValue(selector)
  result[11] = RegisterValue(index)

let memory = captureMemory([PageImage(index: PageIndex(0), access: PageAccess.ReadWrite)],
  PageLimit(1)).value
for count in [1, 16]:
  for prerequisites in [0, 8]:
    let captured = capture(count, prerequisites)
    for selector in [10'u64, 11'u64, 12'u64]:
      let price = (if selector == 10: 111'u64 elif selector == 11: 317'u64 else: 250'u64)
      for index in [0'u64, uint64(count - 1), uint64(count), high(uint64)]:
        let present = selector != 12 or index < uint64(count)
        let wanted = expected(selector, (if present and selector == 12: int(index) else: 0),
          count, prerequisites)
        for offset in [0'u64, 1'u64, 61'u64, 62'u64, uint64(wanted.len), high(uint64)]:
          for requested in [0'u64, 1'u64, 63'u64, high(uint64)]:
            for credit in [price - 1, price, price + 1]:
              # Maximal requests still have fixed prices; clipping selects only available bytes.
              let regs = arguments(selector, index, offset, requested, 0)
              let response = fetchContextResponse(captured, MachineGas(credit), regs, memory,
                MemoryByteLimit(993)).value
              let funded = credit >= price
              let start = min(offset, uint64(wanted.len))
              let copied = (if funded and present: min(requested, uint64(wanted.len) -
                  start) else: 0'u64)
              assert response.action == (if funded: HostAction.Continue else: HostAction.OutOfGas)
              assert uint64(response.gas) == (if funded: credit - price else: 0'u64)
              assert uint64(response.gasDeficit) == (if funded: 0'u64 else: 1'u64)
              for i in 0..<13:
                # Only funded r7 changes, and always reports full length or NONE.
                let value = (if i != 7 or not funded: uint64(regs[i])
                  elif present: uint64(wanted.len) else: high(uint64))
                assert uint64(response.registers[i]) == value
              let page = pageImage(response.memory, PageIndex(0)).value
              for i in 0..wanted.len:
                # Check all selected bytes and an untouched trailing sentinel.
                assert page.bytes[i] == (if uint64(i) < copied: wanted[int(start) + i] else: 0'u8)
      let absent = withFetchPackage(captured, FetchPresence.Absent, default(OwnedWorkPackage),
        FetchPackageLimit(0)).value
      let none = fetchContextResponse(absent, MachineGas(price), arguments(selector, high(uint64),
        0, high(uint64), high(uint64)), memory, MemoryByteLimit(0)).value
      assert none.action == HostAction.Continue and uint64(none.registers[7]) == high(uint64)
      assert uint64(none.gas) == 0
      let empty = fetchContextResponse(captured, MachineGas(price), arguments(selector, 0,
        high(uint64), high(uint64), high(uint64)), memory, MemoryByteLimit(0)).value
      assert empty.action == HostAction.Continue
      assert uint64(empty.registers[7]) == uint64(expected(selector, 0, count, prerequisites).len)
      let crossing = arguments(selector, 0, 0, 2, 4095)
      let panic = fetchContextResponse(captured, MachineGas(price), crossing, memory,
          MemoryByteLimit(2)).value
      assert panic.action == HostAction.Panic and uint64(panic.registers[7]) == 4095
      assert uint64(panic.gas) == 0 and pageImage(panic.memory, PageIndex(0)).value.bytes[4095] == 0
      assert fetchContextResponse(captured, MachineGas(price), arguments(selector, 0, 0, 2, 0),
        memory, MemoryByteLimit(1)).error == FetchError.LimitExceeded
      let oog = fetchContextResponse(captured, MachineGas(price - 1), crossing, memory,
          MemoryByteLimit(0)).value
      assert oog.action == HostAction.OutOfGas
assert pageImage(memory, PageIndex(0)).value.bytes[0] == 0

# The real host loop propagates local refusal without manufacturing a guest panic.
proc dispatch(context: var FetchContext, stopped: StepOutcome): HostResult[FetchError] {.raises: [].} =
  assert uint64(stopped.hostCall) == 2
  let cpu = machineInfo(stopped.machine).value
  let fetched = fetchContextResponse(context, cpu.gas, cpu.registers,
    memoryOf(stopped.machine).value, MemoryByteLimit(993))
  if fetched.error != FetchError.None:
    # Preserve the exact local error for the invocation caller.
    return hostFailure(fetched.error)
  hostSuccess[FetchError](fetched.value)

# Maximum fixed metadata storage and response memory must be released on every cycle.
proc cycle() =
  var captured = capture(16, 8)
  let code = decodeProgram([0'u8, 0, 4, 10, 2, 50, 0, 5], CodeAddress(0), ProgramByteLimit(8),
    JumpCountLimit(0)).value
  let memory = captureMemory([PageImage(index: PageIndex(0), access: PageAccess.ReadWrite)],
      PageLimit(1)).value
  for selector in [10'u64, 11'u64, 12'u64]:
    # Repeated calls borrow the stored encoding without retaining their memory in the context.
    let response = fetchContextResponse(captured, MachineGas(1000), arguments(selector, 15, 0,
      high(uint64), 0), memory, MemoryByteLimit(993)).value
    assert response.action == HostAction.Continue
    assert uint64(response.registers[7]) == uint64(expected(selector, 15, 16, 8).len)
    var registers = arguments(selector, 15, 0, high(uint64), 0)
    registers[0] = RegisterValue(0xffff0000'u64)
    let machine = captureMachine(code, memory, MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000),
      blockCharged: true, registers: registers)).value
    let done = executeWithHost(machine, captured, dispatch, ExecutionStepLimit(2), HostCallLimit(1),
      GasCycleLimit(0))
    assert done.error == HostExecutionError.None and done.value.exit == StepExit.Halt
    assert uint64(machineInfo(done.value.machine).value.registers[7]) == uint64(expected(selector,
        15, 16, 8).len)

cycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Captured package metadata remains acyclic and shares no lifetime with temporary codec owners.
  cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_fetch_summaries", 1000, before, after)
echo "PVM summary fetch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
