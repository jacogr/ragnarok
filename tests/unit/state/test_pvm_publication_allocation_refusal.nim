# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A refused sparse dirty-page sort cannot publish the immutable input as a successful result.

import std/[assertions, syncio]
import ../../../src/pvm/[machine, program, step]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/internal/handler_stream

const Address = MemoryAddress(65536)
# Store one byte at 65536, suspend, and then trap.
let wire = [0'u8, 0, 13, 30, 4, 0, 0, 1, 0, 42, 0, 0, 0, 10, 7, 0, 1, 20]
let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(128), JumpCountLimit(0))
assert decoded.error == ProgramError.None
let plan = newFlatPlan(decoded.value, GasCycleLimit(10000))
let regions = [InitializationRegion(first: PageIndex(16), past: PageIndex(48),
  access: PageAccess.ReadWrite, source: InitializationSource.First, offset: 0, length: 0)]
let input = captureInitializationMemory(regions, [], [], PageLimit(32))
assert input.error == MachineError.None
let cpu = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000))
var admitted = prepareFlatMemoryFrame(plan, input.value, cpu)
assert admitted.error == FlatError.None
var frame = handler_stream.takeValue(admitted)
runFlat(frame, 3)
assert frame.reason == StepError.None and frame.exit == StepExit.Host
let stopped = frame.info

# All execution allocations happened before pressure. The sparse publisher
# needs one four-byte dirty ordinal before it can expose the changed page.
let filler = alloc(1024*1024-getOccupiedMem())
assert filler != nil and getOccupiedMem()+4 > 1024*1024
var observation = default(Memory)
let refused = tryObserveFlatHostMemory(frame, observation)
dealloc(filler)
assert refused == StepError.ResidentAllocationRefused
assert memoryPageCount(observation).error == MachineError.InvalidOwner
assert frame.info == stopped
assert resumeFlatHostMemory(frame, input.value, stopped.gas, stopped.registers) ==
  StepError.InvalidHostSuspension

# The original stop and its guest store survive. No partial snapshot escaped.
assert tryObserveFlatHostMemory(frame, observation) == StepError.None
let written = load(observation, Address, AccessWidth(1))
assert written.error == MachineError.None and uint64(written.value) == 42
assert uint64(load(input.value, Address, AccessWidth(1)).value) == 0

proc checkStagingRefusal(source: Memory, dense: bool) =
  ## Make the dirty-index collection irrelevant and refuse the replacement payload directly.
  var batch = beginResidentReplacements(source)
  var bytes = default(array[4096, byte])
  bytes[0] = 42
  if dense:
    # Change every chunk to exercise the independent backing/tail path.
    for chunk in 1..<8: bytes[chunk*512] = 42
  let page = PageDescription(index: PageIndex(16), access: PageAccess.ReadWrite)
  let pressure = alloc(1024*1024-getOccupiedMem()-131072)
  assert pressure != nil
  var padding = default(array[1024, nil pointer])
  var used = 0
  while 1024*1024-getOccupiedMem() > 288:
    assert used < padding.len
    padding[used] = alloc(if 1024*1024-getOccupiedMem() > 768: 256 else: 16)
    assert padding[used] != nil
    inc used
  let occupied = getOccupiedMem()
  assert 1024*1024-occupied >= 128 and 1024*1024-occupied < 512
  let staged = stageResidentPage(batch, MemoryPageSlot(0), page, bytes)
  assert getOccupiedMem() == occupied
  for i in 0..<used: dealloc(padding[i])
  dealloc(pressure)
  assert staged == MachineError.LimitExceeded
  assert finishResidentReplacements(batch).error == MachineError.LimitExceeded

checkStagingRefusal(input.value, false)
checkStagingRefusal(input.value, true)
echo "PVM publication allocation refusal passed"
