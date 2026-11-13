# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise real recoverable allocator refusals during frame construction and the first guest store.

import std/[assertions, syncio]
import ../../../src/pvm/[machine, program, step]
import ../../../src/pvm/gas/gas

const
  FirstPage = 32'u32
  PastPage = 292'u32
  Address = MemoryAddress(uint64(FirstPage+1)*4096-3)
  Cycles = GasCycleLimit(10000)

func writable(first, past: uint32): InitializationRegion =
  ## A zero-filled mapping uses shared immutable baseline chunks.
  InitializationRegion(first: PageIndex(first), past: PageIndex(past),
    access: PageAccess.ReadWrite, source: InitializationSource.First, offset: 0, length: 0)

proc memory(regions: openArray[InitializationRegion]): Memory =
  ## Keep setup small relative to the private 260-page payload the frame will request.
  let captured = captureInitializationMemory(regions, [], [], PageLimit(264))
  assert captured.error == MachineError.None
  captured.value

proc guest(): Program =
  ## Store the literal eight-byte value across a page boundary, then call host 7 and trap.
  let address = uint64(Address)
  let wire = [0'u8, 0, 13, 33, 4, byte(address and 255), byte((address shr 8) and 255),
    byte((address shr 16) and 255), 0, 0x78, 0x56, 0x34, 0x12, 10, 7, 0, 1, 20]
  let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(128), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  decoded.value

proc unexpectedHost(calls: var int, suspension: StepOutcome): HostResponse =
  ## Allocation refusal precedes the host instruction.
  inc calls
  default(HostResponse)

proc checkRefusal(owner: Program, prepared: PreparedProgram, input: Memory, info: MachineInfo) =
  ## Every public adapter returns only the local reason and leaves its input intact.
  let source = captureMachine(owner, input, info).value
  assert execute(source, ExecutionStepLimit(3), prepared).error ==
      StepError.ResidentAllocationRefused
  assert stepOnce(source, Cycles).error == StepError.ResidentAllocationRefused
  var calls = 0
  assert executeWithHost(source, calls, unexpectedHost, ExecutionStepLimit(3), HostCallLimit(1),
    prepared).error == StepError.ResidentAllocationRefused
  assert calls == 0 and machineInfo(source).value == info
  let baseline = load(memoryOf(source).value, Address, AccessWidth(8))
  assert baseline.error == MachineError.None and uint64(baseline.value) == 0

let owner = guest()
let info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(10000))
let prepared = newPreparedProgram(owner, defaultPreparedLimits(Cycles)).value
let wide = writable(FirstPage, PastPage)
let first = writable(16, 17)
let last = writable(512, 513)
 # A sole RW run is prepared eagerly. Between two other RW runs, it stays
 # baseline-backed until the first checked store tries to materialize it.
checkRefusal(owner, prepared, memory([wide]), info)
let lazy = memory([first, wide, last])
let poor = captureMachine(owner, lazy, MachineInfo(pc: CodeAddress(0), gas: MachineGas(0))).value
let exhausted = execute(poor, ExecutionStepLimit(3), prepared)
assert exhausted.error == StepError.None and exhausted.value.exit == StepExit.OutOfGas
assert machineInfo(exhausted.value.machine).value == machineInfo(poor).value
checkRefusal(owner, prepared, lazy, info)

# The same owner can retry on a smaller run, including the same crossing store.
let small = memory([first, writable(FirstPage, FirstPage+2), last])
let source = captureMachine(owner, small, info).value
let retried = execute(source, ExecutionStepLimit(3), prepared)
assert retried.error == StepError.None and retried.value.exit == StepExit.Host
assert retried.value.hostCall == HostCallId(7)
let stored = load(memoryOf(retried.value.machine).value, Address, AccessWidth(8))
assert stored.error == MachineError.None and uint64(stored.value) == 0x12345678
assert uint64(load(small, Address, AccessWidth(8)).value) == 0
echo "PVM frame allocation refusal passed"
