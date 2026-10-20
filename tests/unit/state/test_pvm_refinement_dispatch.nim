# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_refinement_dispatch_arc_release"}

## Original real guests verify bound refinement host inputs, transactional exports and shared heap behavior.

import std/[assertions, syncio]
import ../../../src/state/[refinement_dispatch, store]
import ../../../src/pvm/[machine, program, step, gas, host_fetch, refinement_exports]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite, state_accounts, state_trie, state_service_values,
  state_requests, work_package, work_digest, work_report]
import ../../support/arc_evidence

proc parameters(): Parameters =
  ## Literal fixed-field maxima form a valid configured snapshot without a mutable parameter back door.
  var wire = default(array[122, byte])
  for index in 0..<122: wire[index] = 255
  decodeParameters(wire).value
proc package(anchor = 20'u32): OwnedWorkPackage =
  ## Two distinguishable manifest rows select different services, payloads and external input lengths.
  let value = WorkPackage(context: RefinementContext(lookupSlot: LookupSlot(anchor)),
    configuration: @[61'u8], authorization: @[71'u8], items: @[
      WorkItem(service: ServiceIndex(42), payload: @[41'u8], imports: @[rootImport(default(
          SegmentRoot), ImportIndex(0))],
        extrinsics: @[ExtrinsicCommitment(length: ExtrinsicLength(2))]),
      WorkItem(service: ServiceIndex(99), payload: @[51'u8, 52], imports: @[rootImport(default(
          SegmentRoot), ImportIndex(0))],
        extrinsics: @[ExtrinsicCommitment(length: ExtrinsicLength(3))])])
  var wire = default(array[2048, byte])
  let config = fullPackageConfig(ByteLimit(2048))
  let size = encodeWorkPackage(value, config, wire).value
  decodeWorkPackage(wire.toOpenArray(0, size-1), config).value.owner
proc state(): StateStoreSnapshot =
  ## Retained complete maps supply independent histories and byte values for each package-selected self.
  var hash = default(array[32, byte])
  hash[0] = 73
  var entries: seq[StateEntry] = @[]
  for service in [42'u32, 99]:
    entries.add(serviceMetadataEntry(ServiceIndex(service), ServiceMetadata(), ByteLimit(89)).value)
    let bytes = if service == 42: @[21'u8, 22, 23] else: @[31'u8, 32, 33]
    entries.add(servicePreimageEntry(ServiceIndex(service), ServicePreimageHash(hash), bytes,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(3))).value)
    let key = serviceRequestKey(ServiceIndex(service), ServicePreimageHash(hash), RequestLength(3),
        ByteLimit(32)).value
    entries.add(StateEntry(key: key, value: @[1'u8, 10, 0, 0, 0])) # Available since literal timeslot ten.
  newStateStore(entries, StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(8),
      perValue: ByteLimit(100),
    totalValueBytes: ByteLimit(1000), nodes: TrieNodeLimit(200)), writes: ElementLimit(8),
    writeValueBytes: ByteLimit(1000))).value.snapshot.value
proc inputs(): RefinementInputs =
  ## Independent source octets need no production hash oracle to test owned selection and copy contracts.
  var first, second = default(array[4104, byte])
  first[0] = 11
  second[0] = 22
  RefinementInputs(extrinsics: @[@[@[81'u8, 82]], @[@[91'u8, 92, 93]]],
    imports: @[@[FetchSegment(first)], @[FetchSegment(second)]])
proc registers(): RegisterFile =
  ## A default real halt sentinel plus explicit lookup argument registers.
  result = default(RegisterFile)
  result[0] = RegisterValue(0xffff0000'u64)
  result[7] = RegisterValue(high(uint64))
  result[8] = RegisterValue(65536)
  result[9] = RegisterValue(196608)
  result[11] = RegisterValue(3)
proc immediate(index: byte, value: uint64): seq[byte] =
  ## Authored full-width load_imm_64 bytes freeze every register bit independently.
  result = @[20'u8, index]
  for shift in 0..<8: result.add(byte((value shr (shift*8)) and 255))
proc cpu(instructions: openArray[seq[byte]], regs: RegisterFile, credit = 100000'u64,
    pages = 4'u32): Machine =
  ## Frame short original instruction bytes and an exact opcode mask, with a prepaid first basic block.
  var code: seq[byte] = @[]
  var starts: seq[bool] = @[]
  for instruction in instructions:
    for index, octet in instruction:
      code.add(octet)
      starts.add(index == 0) # Operand bytes never become legal instruction boundaries.
  assert code.len > 0 and code.len < 128
  var blob = @[0'u8, 0, byte(code.len)]
  for octet in code: blob.add(octet)
  var mask = newSeq[byte]((code.len+7) div 8)
  for index, marked in starts:
    if marked: mask[index div 8] = mask[index div 8] or byte(1 shl (index mod 8))
  for octet in mask: blob.add(octet)
  let parsed = decodeProgram(blob, CodeAddress(0), ProgramByteLimit(256), JumpCountLimit(0))
  assert parsed.error == ProgramError.None, "authored guest must decode before execution"
  let program = parsed.value
  var hash = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly)
  hash.bytes[0] = 73
  let memory = captureMemory([hash, PageImage(index: PageIndex(48), access: PageAccess.ReadWrite)],
      PageLimit(pages)).value
  captureMachine(program, memory, MachineInfo(pc: CodeAddress(0), gas: MachineGas(credit),
    registers: regs, blockCharged: true)).value
proc caps(): RefinementCaptureLimits =
  ## Independent budgets are deliberately larger than these small authored captures.
  RefinementCaptureLimits(trace: FetchTraceLimit(3), package: FetchPackageLimit(64),
    encoding: FetchEncodingLimit(2048), inputs: FetchInputLimit(9000))
proc prepare(machine: Machine, item = 0'u64, anchor = 20'u32,
    source = inputs(), cap = caps()): RefinementDispatchResult[PreparedRefinementExecution] =
  ## Capture all rows but bind current fetch identity and historical self to the same selected package item.
  prepareRefinementExecution(machine, state(), package(anchor), FetchItemIndex(item), parameters(),
    [101'u8, 102, 103], source, RefinementHeapBounds(first: PageIndex(48), past: PageIndex(64)),
    ExportOffset(7), cap)
proc run(prepared: PreparedRefinementExecution, steps = 100'u64, calls = 10'u64,
    cycles = 1000'u64, copy = 5000'u64, exports = 2'u64): RefinementDispatchResult[
        RefinementOutcome] =
  ## Keep engine/copy/export policies independently selectable for transactional refusal witnesses.
  executeRefinement(prepared, MemoryByteLimit(copy), ExportLimits(items: ElementLimit(exports),
    bytes: ByteLimit(exports*4104)), ExecutionStepLimit(steps), HostCallLimit(calls), GasCycleLimit(cycles))

let lookup = cpu([@[10'u8, 7], @[50'u8, 0]], registers())
for item in [0'u64, 1]:
  let done = run(prepare(lookup, item).value).value
  assert done.outcome.exit == StepExit.Halt and uint64(done.exports.count) == 0
  assert uint64(done.outcome.machine.machineInfo.value.registers[7]) == 3
  let actual = readBytes(done.outcome.machine.memoryOf.value, MemoryAddress(196608), MemoryLength(
      3), MemoryByteLimit(3)).value
  assert actual == (if item == 0: @[21'u8, 22, 23] else: @[31'u8, 32,
      33]) # Package-selected self cannot alias another item.
let absent = run(prepare(lookup, anchor = 9).value).value
assert uint64(absent.outcome.machine.machineInfo.value.registers[7]) == high(uint64)
# One guest first looks up bytes, then exports those exact bytes; replay starts with the original CPU and empty exports.
let multi = cpu([@[10'u8, 7], immediate(7, 196608), immediate(8, 3), @[10'u8, 8], @[50'u8, 0]],
    registers())
let prepared = prepare(multi).value
for replay in 0..<2:
  let done = run(prepared).value
  assert done.outcome.exit == StepExit.Halt and uint64(done.exports.count) == 1
  assert uint64(done.outcome.machine.machineInfo.value.registers[7]) == 7
  let bytes = array[4104, byte](done.exports.segment(ExportCount(0)))
  assert bytes[0] == 21 and bytes[1] == 22 and bytes[2] == 23
  for index in 3..<4104: assert bytes[index] == 0 # Exact lookup bytes plus a fully zero-padded tail.
assert multi.memoryOf.value.pageImage(PageIndex(48)).value.bytes == default(array[4096, byte])
# Fetch binds current extrinsic/import to item one; payload uses the explicit guest item; zero entropy and trace are always present.
for selector in [1'u64, 2, 4, 6, 13]:
  var regs = registers()
  regs[7] = RegisterValue(196608)
  regs[8] = RegisterValue(0)
  regs[9] = RegisterValue(4)
  regs[10] = RegisterValue(selector)
  regs[11] = RegisterValue(if selector == 13: 1'u64 else: 0'u64)
  var borrowed = inputs()
  let captured = prepare(cpu([@[10'u8, 2], @[50'u8, 0]], regs), item = 1, source = borrowed).value
  borrowed.extrinsics[1][0][0] = 255 # Later caller mutation cannot alter the captured table.
  let done = run(captured).value
  let bytes = readBytes(done.outcome.machine.memoryOf.value, MemoryAddress(196608), MemoryLength(4),
      MemoryByteLimit(4)).value
  let expected = if selector == 1: @[0'u8, 0, 0, 0]
    elif selector == 2: @[101'u8, 102, 103, 0]
    elif selector == 4: @[91'u8, 92, 93, 0]
    elif selector == 6: @[22'u8, 0, 0, 0]
    else: @[51'u8, 52, 0, 0]
  assert bytes == expected, "captured fetch selection and immutable input bytes"
# Known unsupported hosts retain a typed gate, while all unrelated IDs use F's WHAT branch, even on OOG.
for id in 10'u8..13'u8:
  assert run(prepare(cpu([@[10'u8, id], @[50'u8, 0]], registers(), 0)).value).error ==
      RefinementDispatchError.UnsupportedHostCall
for id in [3'u8, 6, 15, 27, 28, 127, 255]:
  for credit in [999'u64, 1000]:
    let done = run(prepare(cpu([@[10'u8, id], @[50'u8, 0]], registers(), credit)).value).value
    assert uint64(done.outcome.machine.machineInfo.value.registers[7]) == high(uint64)-1
    assert done.outcome.exit == (if credit < 1000: StepExit.OutOfGas else: StepExit.Halt)
# Shared gas/heap primitives preserve adopted zero-deficit OOG, exact growth cost and local page capacity refusals.
var regs = registers()
let gasResult = run(prepare(cpu([@[10'u8, 0], @[50'u8, 0]], regs, 100)).value).value
assert uint64(gasResult.outcome.machine.machineInfo.value.registers[7]) == 52
regs[7] = RegisterValue(50)
let heap = run(prepare(cpu([@[10'u8, 1], @[50'u8, 0]], regs, 396)).value).value
assert uint64(heap.outcome.machine.machineInfo.value.registers[7]) == 50
assert heap.outcome.machine.memoryOf.value.pageImage(PageIndex(49)).value.access ==
    PageAccess.ReadWrite
let starved = run(prepare(cpu([@[10'u8, 1], @[50'u8, 0]], regs, 395)).value).value
assert starved.outcome.exit == StepExit.OutOfGas and uint64(
    starved.outcome.machine.machineInfo.value.gasDeficit) == 0
assert run(prepare(cpu([@[10'u8, 1], @[50'u8, 0]], regs, 396, pages = 2)).value).error ==
    RefinementDispatchError.LimitExceeded
# A successful export is discarded on later guest panic/OOG/fault, and never escapes a later local failure.
for kind, ending in [@[0'u8], @[10'u8, 8], @[52'u8, 0, 0, 0, 0, 1]]:
  let guest = cpu([immediate(7, 196608), immediate(8, 3), @[10'u8, 8], ending, @[50'u8, 0]],
      registers(), 3521)
  let done = run(prepare(guest).value).value
  assert done.outcome.exit == [StepExit.Panic, StepExit.OutOfGas, StepExit.Fault][kind]
  assert uint64(done.exports.count) == 0
let unsupported = cpu([immediate(7, 196608), immediate(8, 3), @[10'u8, 8], @[10'u8, 13], @[50'u8,
    0]], registers())
assert run(prepare(unsupported).value).error == RefinementDispatchError.UnsupportedHostCall
var uncharged = multi.machineInfo.value
uncharged.blockCharged = false
let cycleChecked = prepare(captureMachine(multi.programOf.value, multi.memoryOf.value,
    uncharged).value).value
for budget in 0..<3:
  let failed = if budget == 0: run(prepared, steps = 0)
    elif budget == 1: run(prepared, calls = 0) else: run(cycleChecked, cycles = 0)
  assert failed.error == RefinementDispatchError.ExecutionFailure
  assert failed.executionError == (if budget == 0: StepError.StepLimitExceeded
    elif budget == 1: StepError.HostCallLimitExceeded else: StepError.GasCycleLimitExceeded)
assert run(prepared, copy = 2).error == RefinementDispatchError.LimitExceeded
assert run(prepared, exports = 0).error == RefinementDispatchError.LimitExceeded
# Capture refuses invalid/default selection and independently exhausted policies before any guest instruction.
assert prepare(default(Machine)).error == RefinementDispatchError.InvalidMachine
assert prepare(lookup, item = high(uint64)).error == RefinementDispatchError.InvalidInputs
var missing = inputs()
missing.imports = @[]
assert prepare(lookup, source = missing).error == RefinementDispatchError.InvalidInputs
missing = inputs()
missing.extrinsics[1][0] = @[]
assert prepare(lookup, source = missing).error == RefinementDispatchError.InvalidInputs
for policy in 0..<4:
  var cap = caps()
  case policy
  of 0: cap.trace = FetchTraceLimit(2) # Trace is present and requires all three source bytes.
  of 1: cap.package = FetchPackageLimit(0)
  of 2: cap.encoding = FetchEncodingLimit(1)
  else: cap.inputs = FetchInputLimit(1)
  assert prepare(lookup, cap = cap).error == RefinementDispatchError.LimitExceeded
assert run(default(PreparedRefinementExecution)).error == RefinementDispatchError.InvalidContext
# Repeated fresh complete environments and host successors release independently, including failed scratch runs.
proc cycle() =
  ## No original mutable source or callback-local export accumulator survives a single iteration.
  let captured = prepare(multi).value
  assert uint64(run(captured).value.exports.count) == 1
  assert run(captured, exports = 0).error == RefinementDispatchError.LimitExceeded
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_refinement_dispatch", 1000, before, after)
echo "PVM refinement dispatch passed"
echo "ARC_RELEASE cycles=1000 unchanged"
