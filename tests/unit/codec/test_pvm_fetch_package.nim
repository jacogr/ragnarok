# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Original raw-package fetch witnesses for blob selection, prices, ownership and bounded capture.
## Exercises validated codec owners and fallible execution with fresh ARC evidence.

# @@Verification={"arc": "pvm_fetch_package_arc_release"}

import std/[assertions, syncio]
import ../../../src/codec/[work_package, bounded, work_digest]
import ../../../src/pvm/[program, machine, gas, step, host_fetch]
import ../../support/arc_evidence

# Three distinct payloads include an empty middle item, separate from token and configuration.
proc package(): OwnedWorkPackage =
  var value = WorkPackage(configuration: @[41'u8, 42], authorization: @[51'u8, 52, 53],
    items: @[WorkItem(payload: @[61'u8, 62, 63, 64]), WorkItem(payload: @[]), WorkItem(payload: @[71'u8])])
  var wire = default(array[2048, byte])
  let config = fullPackageConfig(ByteLimit(2048))
  let size = encodeWorkPackage(value, config, wire).value
  let parsed = decodeWorkPackage(wire.toOpenArray(0, size - 1), config).value.owner
  value.items[0].payload[0] = 255
  for i in 0..<wire.len:
    # Mutating both encoder sources and raw input cannot alter the codec's retained snapshot.
    wire[i] = 0
  parsed

# The base carries nonempty entropy and trace so attachment/clearing must preserve unrelated selectors.
proc base(): FetchContext =
  var entropy = default(array[32, byte])
  entropy[0] = 37
  captureFetchContext(FetchPresence.Present, FetchEntropy(entropy), FetchPresence.Present,
    [17'u8], FetchTraceLimit(1)).value

# One writable page makes crossing its final byte an atomic permission failure.
proc memory(): Memory =
  captureMemory([PageImage(index: PageIndex(0), access: PageAccess.ReadWrite)], PageLimit(1)).value

# Distinct sentinels make all unrelated register mutations visible, including ignored r12.
proc arguments(selector, item, offset, requested, pointer: uint64): RegisterFile =
  result = default(RegisterFile)
  for i in 0..<13:
    # Only the host argument registers are replaced below.
    result[i] = RegisterValue(uint64(i + 100))
  result[0] = RegisterValue(0xffff0000'u64)
  result[7] = RegisterValue(pointer)
  result[8] = RegisterValue(offset)
  result[9] = RegisterValue(requested)
  result[10] = RegisterValue(selector)
  result[11] = RegisterValue(item)

# Independent expected raw fields contain no C.2 framing or lengths.
proc expected(selector, item: uint64): seq[byte] =
  if selector == 8:
    # Configuration is independent of the item index.
    return @[41'u8, 42]
  if selector == 9:
    # Token must not be confused with authorizer configuration.
    return @[51'u8, 52, 53]
  if item == 0:
    # First item's bytes differ from every package header field.
    return @[61'u8, 62, 63, 64]
  if item == 2:
    # The last item tests the inclusive upper valid index.
    return @[71'u8]
  @[]

let original = base()
let sourceMemory = memory()
for limit in 0'u64..<10:
  # The aggregate cap counts both package fields and every payload, including the late last item.
  assert withFetchPackage(original, FetchPresence.Present, package(), FetchPackageLimit(
      limit), FetchEncodingLimit(32768)).error == FetchError.LimitExceeded
let captured = withFetchPackage(original, FetchPresence.Present, package(), FetchPackageLimit(10),
    FetchEncodingLimit(32768)).value
let cleared = withFetchPackage(captured, FetchPresence.Absent, default(OwnedWorkPackage),
    FetchPackageLimit(0), FetchEncodingLimit(32768)).value
assert withFetchPackage(original, FetchPresence.Present, default(OwnedWorkPackage),
    FetchPackageLimit(10), FetchEncodingLimit(32768)).error == FetchError.InvalidContext
assert withFetchPackage(default(FetchContext), FetchPresence.Absent, package(), FetchPackageLimit(
    10), FetchEncodingLimit(32768)).error == FetchError.InvalidContext
for context in [original, captured, cleared]:
  for selector in [1'u64, 2'u64]:
    # Sharing or clearing package state cannot replace the base entropy/trace snapshot.
    let reply = fetchContextResponse(context, MachineGas(1000), arguments(selector, 0, 0, 1, 0),
        sourceMemory, MemoryByteLimit(1)).value
    assert pageImage(reply.memory, PageIndex(0)).value.bytes[0] == (if selector ==
        1: 37'u8 else: 17'u8)

for selector in [8'u64, 9'u64, 13'u64]:
  for item in [0'u64, 1'u64, 2'u64, 3'u64, high(uint64)]:
    for requested in [0'u64, 1'u64, 3'u64, 1023'u64, 1024'u64, 1025'u64, high(uint64)]:
      # Safe small multiplication and a separately derived maximal constant are the price oracle.
      let cost = (if selector == 8: 84'u64 elif selector == 9: 88'u64
        elif requested == high(uint64): 1729382256910270559'u64
        else: 95 + (96 * requested + 1023) div 1024)
      for credit in [cost - 1, cost, cost + 1]:
        for offset in [0'u64, 1'u64, high(uint64)]:
          # The byte oracle clips independently and keeps absent distinct from present empty payload.
          let regs = arguments(selector, item, offset, requested, 0)
          let reply = fetchContextResponse(captured, MachineGas(credit), regs, sourceMemory,
              MemoryByteLimit(4)).value
          let bytes = expected(selector, item)
          let present = selector != 13 or item < 3
          let start = min(offset, uint64(bytes.len))
          let count = min(requested, uint64(bytes.len) - start)
          if credit < cost:
            # Underflow must precede return assignment and all memory writes.
            assert reply.action == HostAction.OutOfGas and uint64(reply.gasDeficit) == 1
            assert uint64(reply.gas) == 0
          else:
            # Full selected length is returned even when only a suffix or no bytes were requested.
            assert reply.action == HostAction.Continue and uint64(reply.gas) == credit - cost
            assert uint64(reply.gasDeficit) == 0
          for i in 0..<13:
            # All registers except funded r7 remain unchanged.
            let wanted = (if i != 7 or credit < cost: uint64(regs[i])
              elif present: uint64(bytes.len) else: high(uint64))
            assert uint64(reply.registers[i]) == wanted
          let page = pageImage(reply.memory, PageIndex(0)).value
          for i in 0..<5:
            # Includes the untouched suffix and every byte of the longest field.
            assert page.bytes[i] == (if credit >= cost and uint64(i) < count:
              bytes[int(start) + i] else: 0'u8)
      for context in [original, cleared]:
        # Absent package never dereferences the item index or destination, but keeps selector pricing.
        let reply = fetchContextResponse(context, MachineGas(cost), arguments(selector, item, 0,
          requested, high(uint64)), sourceMemory, MemoryByteLimit(0)).value
        assert reply.action == HostAction.Continue and uint64(reply.gas) == 0
        assert uint64(reply.registers[7]) == high(uint64)

for selector in [8'u64, 9'u64, 13'u64]:
  let reply = fetchContextResponse(captured, MachineGas(1000), arguments(selector, 0, 0, 2, 4095),
    sourceMemory, MemoryByteLimit(2)).value
  # A valid first byte followed by an absent page must not commit a partial prefix.
  assert reply.action == HostAction.Panic and uint64(reply.registers[7]) == 4095
  assert pageImage(reply.memory, PageIndex(0)).value.bytes[4095] == 0
  assert fetchContextResponse(captured, MachineGas(1000), arguments(selector, 0, 0, 2, 0),
    sourceMemory, MemoryByteLimit(1)).error == FetchError.LimitExceeded
let empty = fetchContextResponse(captured, MachineGas(96), arguments(13, 1, 0, 1, high(uint64)),
  sourceMemory, MemoryByteLimit(0)).value
assert empty.action == HostAction.Continue and uint64(empty.registers[7]) == 0
assert pageImage(sourceMemory, PageIndex(0)).value.bytes[0] == 0

# Fixed sixteen-item codec limit is also the capture table's last valid entry.
block:
  var value = WorkPackage(items: newSeq[WorkItem](16))
  value.items[15].payload = @[99'u8]
  var wire = default(array[2048, byte])
  let config = fullPackageConfig(ByteLimit(2048))
  let size = encodeWorkPackage(value, config, wire).value
  let sixteen = withFetchPackage(captured, FetchPresence.Present,
    decodeWorkPackage(wire.toOpenArray(0, size - 1), config).value.owner, FetchPackageLimit(1),
        FetchEncodingLimit(32768)).value
  let reply = fetchContextResponse(sixteen, MachineGas(96), arguments(13, 15, 0, 1, 0),
    sourceMemory, MemoryByteLimit(1)).value
  assert pageImage(reply.memory, PageIndex(0)).value.bytes[0] == 99
  for selector in [8'u64, 9'u64]:
    # Present empty package fields return zero even with an invalid pointer and zero copy capacity.
    let field = fetchContextResponse(sixteen, MachineGas(1000), arguments(selector, high(uint64),
      0, high(uint64), high(uint64)), sourceMemory, MemoryByteLimit(0)).value
    assert field.action == HostAction.Continue and uint64(field.registers[7]) == 0
  let prior = fetchContextResponse(captured, MachineGas(96), arguments(13, 2, 0, 1, 0),
    sourceMemory, MemoryByteLimit(1)).value
  assert pageImage(prior.memory, PageIndex(0)).value.bytes[0] == 71


# Dispatch only fetch and propagate local context/copy refusals without translating them into guest exits.
proc dispatch(context: var FetchContext, stopped: StepOutcome): HostResult[FetchError] {.raises: [].} =
  assert uint64(stopped.hostCall) == 2
  let cpu = machineInfo(stopped.machine).value
  let fetched = fetchContextResponse(context, cpu.gas, cpu.registers, memoryOf(
      stopped.machine).value, MemoryByteLimit(4))
  if fetched.error != FetchError.None:
    # The host loop preserves the exact typed refusal and exposes no partial machine.
    return hostFailure(fetched.error)
  hostSuccess[FetchError](fetched.value)

# Owner destruction and guest execution release both copied payload storage and transient memory pages.
proc cycle() =
  var context = withFetchPackage(base(), FetchPresence.Present, package(), FetchPackageLimit(10),
      FetchEncodingLimit(32768)).value
  let code = decodeProgram([0'u8, 0, 4, 10, 2, 50, 0, 5], CodeAddress(0), ProgramByteLimit(8),
      JumpCountLimit(0)).value
  for selector in [8'u64, 9'u64, 13'u64]:
    # Repeated calls reuse the captured blobs without recapturing the package or mutating the context.
    let source = captureMachine(code, memory(), MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000),
      blockCharged: true, registers: arguments(selector, 0, 0, 4, 0))).value
    let done = executeWithHost(source, context, dispatch, ExecutionStepLimit(2), HostCallLimit(1),
        GasCycleLimit(0))
    assert done.error == HostExecutionError.None and done.value.exit == StepExit.Halt
    assert uint64(machineInfo(done.value.machine).value.registers[7]) == uint64(expected(selector, 0).len)

cycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Private owners retain no parent pointer or callback history and are acyclic under ARC.
  cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_fetch_package", 1000, before, after)
echo "PVM package fetch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
