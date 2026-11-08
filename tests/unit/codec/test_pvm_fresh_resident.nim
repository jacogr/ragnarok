# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## First-RW capture preserves literal bytes, dirty restore, transactional host refusal and exclusive release.

# @@Verification={"arc": "pvm_fresh_resident_arc_release"}
import std/[assertions, syncio]
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/step
import ../../../src/pvm/internal/[handler_stream, resident_bytes]
import ../../support/arc_evidence

const
  FirstPage = 32'u32
  PastPage = 292'u32
  LogicalBytes = uint64(PastPage-FirstPage)*4096
  RetainedBytes = LogicalBytes*2
  DirtyAddress = uint64(33*4096+4093)

proc addWord(bytes: var seq[byte], value: uint64) =
  ## Encode a literal four-byte immediate independently of production instruction decoding.
  for shift in 0..<4: bytes.add(byte((value shr (shift*8)) and 255))

proc guest(): Program =
  ## Read before writing, suspend, read after repair and trap; the literal memory oracle has eight known octets.
  var read = @[52'u8, 7]
  read.addWord(DirtyAddress)
  var write = @[33'u8, 4]
  write.addWord(DirtyAddress)
  write.addWord(0x12345678)
  var after = @[52'u8, 8]
  after.addWord(DirtyAddress)
  let parts = [read, write, @[10'u8, 1], after, @[0'u8]]
  var bytes: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    # The short literal program needs one-byte natural counts and no jump table.
    starts.add(bytes.len)
    for value in part: bytes.add(value)
  assert bytes.len < 128
  var wire = @[0'u8, 0, byte(bytes.len)]
  for value in bytes: wire.add(value)
  var mask = newSeq[byte]((bytes.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for value in mask: wire.add(value)
  decodeProgram(wire, CodeAddress(0), ProgramByteLimit(128), JumpCountLimit(0)).value

proc initialMemory(): Memory =
  ## The initialized first byte is unknown; 259 whole absent-prefix pages have genuine zero provenance.
  let regions = [InitializationRegion(first: PageIndex(FirstPage), past: PageIndex(PastPage),
    access: PageAccess.ReadWrite, source: InitializationSource.First, offset: 0, length: 1)]
  captureInitializationMemory(regions, [0x5a'u8], [], PageLimit(264)).value

proc freshFrame(plan: FlatPlan, memory: Memory, info: MachineInfo): FlatFrame =
  ## Consume only an admitted complete frame, preserving the typed constructor boundary.
  var created = prepareFlatMemoryFrame(plan, memory, info)
  assert created.error == FlatError.None
  handler_stream.takeValue(created)

proc literalBytes(stored: bool): string =
  ## The oracle is one initialized byte plus the literal guest store, never another execution's memory.
  result = newString(int(LogicalBytes))
  result[0] = char(0x5a)
  if stored:
    # The eight-byte positive immediate crosses two pages; its high four octets are zero.
    const octets = [0x78'u8, 0x56, 0x34, 0x12, 0, 0, 0, 0]
    for index in 0..<octets.len:
      result[int(DirtyAddress-uint64(FirstPage)*4096)+index] = char(octets[index])

proc checkStorage(frame: FlatFrame) =
  ## Full logical bytes remain visible even when the managed alternative is empty.
  let shape = residentFrameRWInfo(frame)
  assert shape[0] == LogicalBytes and shape[1] == LogicalBytes
  when FreshRWProfileEnabled:
    assert shape[2] >= LogicalBytes
  else:
    assert shape[2] == 0

proc lifecycle(plan: FlatPlan, memory: Memory, info: MachineInfo) =
  ## Actual Frame/result/heap-scratch moves release exactly once after restoring guest-dirty source bytes.
  var frame = freshFrame(plan, memory, info)
  checkStorage(frame)
  runFlat(frame, 3)
  assert frame.reason == StepError.None and frame.exit == StepExit.Host
  assert uint64(frame.info.registers[7]) == 0
  var scratch = takeFlatMemoryScratch(frame, RetainedBytes)
  assert scratch != nil and flatMemoryScratchPayload(scratch) == RetainedBytes
  assert residentFrameRWInfo(frame) == [0'u64, 0, 0]
  var reused = false
  var created = prepareReusedFlatMemoryFrame(plan, memory, info, scratch, reused)
  assert created.error == FlatError.None and reused and scratch == nil
  var restored = handler_stream.takeValue(created)
  checkStorage(restored)
  runFlat(restored, 1)
  assert uint64(restored.info.registers[7]) == 0 # Read actual restored resident bytes before any new store.

proc completeRestores(plan: FlatPlan, memory: Memory, info: MachineInfo) =
  ## Fresh mixed-prefix capture, complete reset and dense changed-source reuse all preserve every byte.
  var frame = freshFrame(plan, memory, info)
  checkFlatReference(frame, literalBytes(false), 0)
  runFlat(frame, 3)
  checkFlatReference(frame, literalBytes(true), 0)
  resetFlatFrame(frame, info)
  checkFlatReference(frame, literalBytes(false), 0)
  var declined = takeFlatMemoryScratch(frame, RetainedBytes-1)
  assert declined == nil and residentFrameRWInfo(frame)[0] == LogicalBytes
  var scratch = takeFlatMemoryScratch(frame, RetainedBytes)
  assert scratch != nil
  var pages = newSeq[PageImage](int(PastPage-FirstPage))
  var expected = newString(int(LogicalBytes))
  for slot in 0..<pages.len:
    # Arbitrary caller pages remain unknown even if a value happens to be zero.
    pages[slot] = PageImage(index: PageIndex(FirstPage+uint32(slot)), access: PageAccess.ReadWrite)
    for offset in 0..<4096:
      let value = byte((slot*11+offset*7) mod 251)
      pages[slot].bytes[offset] = value
      expected[slot*4096+offset] = char(value)
  let dense = captureMemory(pages, PageLimit(264)).value
  var reused = false
  var created = prepareReusedFlatMemoryFrame(plan, dense, info, scratch, reused)
  assert created.error == FlatError.None and reused
  var restored = handler_stream.takeValue(created)
  checkFlatReference(restored, expected, 0)
  let before = residentWitnessSnapshot()
  var managed = freshFrame(plan, dense, info)
  checkFlatReference(managed, expected, 0)
  assert residentFrameRWInfo(managed)[2] == 0 # No useful provenance means ordinary managed fallback.
  assert residentWitnessSnapshot().acquisitions == before.acquisitions

proc reuseRefusal(plan: FlatPlan, memory: Memory, info: MachineInfo) =
  ## A mismatched idle map is discarded as before; fresh refusal must propagate without a leaked old lease.
  when FreshRWProfileEnabled:
    var frame = freshFrame(plan, memory, info)
    var scratch = takeFlatMemoryScratch(frame, RetainedBytes)
    assert scratch != nil
    let expanded = withPageRange(memory, PageIndex(PastPage), PageIndex(PastPage+1),
      PageAccess.ReadWrite, PageContent.Zeroed).value
    let before = residentWitnessSnapshot()
    refuseNextResidentAllocation()
    var reused = true
    var created = prepareReusedFlatMemoryFrame(plan, expanded, info, scratch, reused)
    assert created.error == FlatError.ResidentAllocationRefused and not reused and scratch == nil
    let after = residentWitnessSnapshot()
    assert after.acquisitions == before.acquisitions and after.releases == before.releases+1
    assert after.logicalBytes+LogicalBytes == before.logicalBytes
    assert after.mappedBytes < before.mappedBytes

proc unexpectedHost(calls: var int, suspension: StepOutcome): HostResponse =
  ## Fresh construction refusal must return before invoking this callback at all.
  inc calls
  default(HostResponse)

proc refusalRollback(plan: FlatPlan, owner: Program, memory: Memory, info: MachineInfo) =
  ## Selected allocation failures preserve stopped bytes, CPU, descriptors and the existing owner's charges.
  when FreshRWProfileEnabled:
    var frame = freshFrame(plan, memory, info)
    runFlat(frame, 3)
    let stopped = observeFlatHostMemory(frame)
    let posterior = withPageRange(stopped, PageIndex(PastPage), PageIndex(PastPage+1),
      PageAccess.ReadWrite, PageContent.Zeroed).value
    let beforeCpu = frame.info
    let beforeStats = flatHostStats(frame)
    let before = residentWitnessSnapshot()
    refuseNextResidentAllocation()
    assert resumeFlatHostMemory(frame, posterior, beforeCpu.gas, beforeCpu.registers) ==
        StepError.ResidentAllocationRefused
    let refused = residentWitnessSnapshot()
    assert refused.refusals == before.refusals+1 and refused.acquisitions == before.acquisitions
    assert refused.logicalBytes == before.logicalBytes and refused.mappedBytes == before.mappedBytes
    assert frame.info == beforeCpu and frame.exit == StepExit.Host and frame.reason == StepError.None
    assert flatHostStats(frame) == beforeStats
    checkFlatReference(frame, literalBytes(true), 0)
    # Repair the response explicitly without invoking any host callback again; old resident bytes stay readable.
    assert resumeFlatHostMemory(frame, stopped, beforeCpu.gas, beforeCpu.registers) == StepError.None
    runFlat(frame, 2)
    assert uint64(frame.info.registers[8]) == 0x78 and frame.exit == StepExit.Panic
    let source = captureMachine(owner, memory, info).value
    let prepared = newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(10000))).value
    refuseNextResidentAllocation()
    assert execute(source, ExecutionStepLimit(3), prepared).error ==
        StepError.ResidentAllocationRefused
    refuseNextResidentAllocation()
    assert stepOnce(source, GasCycleLimit(10000)).error == StepError.ResidentAllocationRefused
    refuseNextResidentAllocation()
    var calls = 0
    let hosted = executeWithHost(source, calls, unexpectedHost, ExecutionStepLimit(10),
      HostCallLimit(1), prepared)
    assert hosted.error == StepError.ResidentAllocationRefused and calls == 0

let owner = guest()
let memory = initialMemory()
let info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(10000), registers: default(RegisterFile))
var admitted = prepareFlatPlan(owner, GasCycleLimit(10000), defaultFlatLimits(), false)
assert admitted.error == FlatError.None
let plan = handler_stream.takeValue(admitted)
completeRestores(plan, memory, info)
refusalRollback(plan, owner, memory, info)
reuseRefusal(plan, memory, info)
lifecycle(plan, memory, info)
let countersBefore = residentWitnessSnapshot()
let occupiedBefore = getOccupiedMem()
for cycle in 0..<1000: lifecycle(plan, memory, info)
let occupiedAfter = getOccupiedMem()
let countersAfter = residentWitnessSnapshot()
assert occupiedBefore == occupiedAfter
assert countersAfter.logicalBytes == countersBefore.logicalBytes
assert countersAfter.mappedBytes == countersBefore.mappedBytes
when FreshRWProfileEnabled:
  assert countersAfter.acquisitions-countersBefore.acquisitions == 1000
  assert countersAfter.releases-countersBefore.releases == 1000
else:
  assert countersAfter.acquisitions == countersBefore.acquisitions
recordArcRelease("pvm_fresh_resident", 1000, occupiedBefore, occupiedAfter)
echo "ARC_RELEASE cycles=1000 unchanged"
echo "PVM fresh resident memory passed"
