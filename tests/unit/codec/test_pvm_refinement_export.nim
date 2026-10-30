# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_refinement_export_arc_release"}

## Literal export bytes, host ordering, immutable forks and generic host execution verify Omega_E.

import std/[assertions, syncio]
import ../../../src/pvm/refinement_exports
import ../../../src/pvm/host/fetch as host_fetch
import ../../../src/pvm/[machine, program, step]
import ../../../src/pvm/gas/gas
import ../../../src/codec/bounded
import ../../../src/codec/work/digest as work_digest
import ../../support/arc_evidence

proc source(): Memory =
  ## Distinct consecutive read-only pages expose clipping, cross-page reads and unreadable successors.
  var pages: seq[PageImage] = @[]
  for page in 16'u32..17'u32:
    var image = PageImage(index: PageIndex(page), access: PageAccess.ReadOnly,
      bytes: default(array[4096, byte]))
    for index in 0..<4096:
      image.bytes[index] = byte((uint64(page-16)*4096+uint64(index)) mod 251+1) # Independent source pattern.
    pages.add(image)
  captureMemory(pages, PageLimit(2)).value
proc registers(length = 12'u64, address = 65536'u64): RegisterFile =
  ## Every nonargument register carries a sentinel to catch accidental host mutations.
  result = default(RegisterFile)
  for index in 0..<13: result[index] = RegisterValue(uint64(index+100))
  result[7] = RegisterValue(address)
  result[8] = RegisterValue(length)
proc limits(items = 3072'u64, bytes = 12607488'u64): ExportLimits =
  ## Local policy is distinct from the package-wide protocol capacity.
  ExportLimits(items: ElementLimit(items), bytes: ByteLimit(bytes))
proc run(owner: RefinementExports, regs: RegisterFile, memory: Memory,
    credit = 10000'u64, cap = limits()): RefinementExportResult =
  ## Direct evaluation leaves host selection to the invocation dispatcher.
  exportResponse(owner, MachineGas(credit), regs, memory, cap)
proc checkUnchanged(response: HostResponse, before: RegisterFile, memory: Memory) =
  ## Export changes only r7 and gas; even the retained readable pages keep exact prior contents.
  for index in 0..<13:
    if index != 7: assert uint64(response.registers[index]) == uint64(before[index])
  for page in 16'u32..17'u32:
    assert response.memory.pageImage(PageIndex(page)).value.bytes == memory.pageImage(PageIndex(
        page)).value.bytes
proc respond(owner: var RefinementExports, stopped: StepOutcome): HostResult[
    RefinementExportError] {.raises: [].} =
  ## A genuine callback installs only a completed matching response/successor pair.
  assert stopped.exit == StepExit.Host and uint64(stopped.hostCall) == 8
  let cpu = stopped.machine.machineInfo.value
  let done = exportResponse(owner, cpu.gas, cpu.registers, stopped.machine.memoryOf.value, limits())
  if done.error != RefinementExportError.None: return hostFailure(done.error)
  let selected = done.value
  owner = selected.exports
  hostSuccess[RefinementExportError](selected.response)

let memory = source()
let empty = captureRefinementExports(ExportOffset(7))
assert uint64(empty.count) == 0
# Every length uses independent expected octets, including clipping of a full-width oversized request.
for length in [0'u64, 1, 4095, 4096, 4103, 4104, 4105, high(uint64)]:
  let regs = registers(length)
  let done = run(empty, regs, memory).value
  assert done.response.action == HostAction.Continue and uint64(done.response.gas) == 6479
  assert uint64(done.response.registers[7]) == 7 and uint64(done.exports.count) == 1
  let segment = array[4104, byte](done.exports.segment(ExportCount(0)))
  for index in 0..<4104:
    let expected = if uint64(index) < min(length, 4104'u64): byte(index mod 251+1) else: 0'u8
    assert segment[index] == expected # All bytes, including the complete zero tail, must match.
  checkUnchanged(done.response, regs, memory)
  assert uint64(empty.count) == 0 # Successful append cannot mutate an earlier owner.
# A read can span both pages; inaccessible later bytes panic without exposing a partially appended segment.
let cross = run(empty, registers(20, 69626), memory).value
let crossBytes = array[4104, byte](cross.exports.segment(ExportCount(0)))
for index in 0..<20: assert crossBytes[index] == byte((4090+index) mod 251+1)
for index in 20..<4104: assert crossBytes[index] == 0
for address in [0'u64, 73722, 0x100000000'u64, 0x100010000'u64, high(uint64)]:
  let regs = registers(12, address)
  let done = run(empty, regs, memory).value
  assert done.response.action == HostAction.Panic and uint64(done.response.gas) == 6479
  assert uint64(done.response.registers[7]) == address and uint64(done.exports.count) == 0
  checkUnchanged(done.response, regs, memory)
# An empty natural input interval permits every pointer, yet appends a complete zero-filled segment.
let zero = run(empty, registers(0, high(uint64)), memory).value
assert uint64(zero.response.registers[7]) == 7
for octet in array[4104, byte](zero.exports.segment(ExportCount(0))): assert octet == 0
# Exact gas succeeds; every underfunded call preserves all registers/exports before reading bad memory.
for credit in [0'u64, 1, 3520, 3521, 3522]:
  let regs = registers(12, if credit < 3521: high(uint64) else: 65536'u64)
  let done = run(empty, regs, memory, credit).value
  if credit < 3521:
    assert done.response.action == HostAction.OutOfGas
    assert uint64(done.response.gas) == 0 and uint64(done.response.gasDeficit) == 0
    assert uint64(done.exports.count) == 0
    for index in 0..<13: assert uint64(done.response.registers[index]) == uint64(regs[index])
  else:
    assert done.response.action == HostAction.Continue and uint64(done.response.gas) == credit-3521
    assert uint64(done.exports.count) == 1
# Protocol capacity is checked after input readability and before local policy, without offset overflow.
for offset in [3072'u64, 3073, high(uint64)]:
  let full = captureRefinementExports(ExportOffset(offset))
  let done = run(full, registers(), memory, cap = limits(0, 0)).value
  assert uint64(done.response.registers[7]) == high(uint64)-4
  assert done.response.action == HostAction.Continue and uint64(done.exports.count) == 0
  assert run(full, registers(1, high(uint64)), memory, cap = limits(0, 0)).value.response.action ==
      HostAction.Panic
  assert run(full, registers(1, high(uint64)), memory, 3520).value.response.action ==
      HostAction.OutOfGas
# The final two permissible package indices remain ordered, then FULL retains both old segments.
let near = captureRefinementExports(ExportOffset(3070))
let first = run(near, registers(1), memory).value
let second = run(first.exports, registers(2), memory).value
assert uint64(first.response.registers[7]) == 3070 and uint64(second.response.registers[7]) == 3071
let full = run(second.exports, registers(), memory, cap = limits(0, 0)).value
assert uint64(full.response.registers[7]) == high(uint64)-4 and uint64(full.exports.count) == 2
assert array[4104, byte](full.exports.segment(ExportCount(0)))[1] == 0
assert array[4104, byte](full.exports.segment(ExportCount(1)))[1] == 2
# Local limits cover the complete padded successor, even for zero guest bytes; exact caps succeed.
for cap in [limits(0, 4104), limits(1, 4103)]:
  assert run(empty, registers(0), memory, cap = cap).error == RefinementExportError.LimitExceeded
assert run(empty, registers(0), memory, cap = limits(1, 4104)).error == RefinementExportError.None
assert run(first.exports, registers(0), memory, cap = limits(1, 8208)).error ==
    RefinementExportError.LimitExceeded
assert run(first.exports, registers(0), memory, cap = limits(2, 8207)).error ==
    RefinementExportError.LimitExceeded
assert run(first.exports, registers(0), memory, cap = limits(2, 8208)).error ==
    RefinementExportError.None
assert run(empty, registers(12, high(uint64)), memory, cap = limits(0, 0)).value.response.action ==
    HostAction.Panic
assert run(default(RefinementExports), registers(), memory).error ==
    RefinementExportError.InvalidContext
assert run(empty, registers(), default(Memory)).error == RefinementExportError.InvalidMemory
# Mutating copies and forking an earlier successor cannot change any existing export sequence.
var copied = array[4104, byte](second.exports.segment(ExportCount(0)))
copied[0] = 255
let fork = run(first.exports, registers(3, 65537), memory).value
assert uint64(first.exports.count) == 1 and uint64(fork.exports.count) == 2
assert array[4104, byte](second.exports.segment(ExportCount(0)))[0] == 1
assert array[4104, byte](second.exports.segment(ExportCount(1)))[0] == 1
assert array[4104, byte](fork.exports.segment(ExportCount(1)))[0] == 2
# A genuine ecalli-8/halt retains the host output after the temporary callback context is gone.
proc hosted(): RefinementExports =
  ## Assemble a tiny guest without claiming a fully authenticated refinement invocation.
  let code = decodeProgram([0'u8, 0, 4, 10, 8, 50, 0, 5], CodeAddress(0), ProgramByteLimit(32),
      JumpCountLimit(0)).value
  var regs = registers()
  regs[0] = RegisterValue(0xffff0000'u64)
  let captured = captureMachine(code, memory, MachineInfo(pc: CodeAddress(0), gas: MachineGas(10000),
    blockCharged: true, registers: regs)).value
  var owner = captureRefinementExports(ExportOffset(29))
  let done = executeWithHost(captured, owner, respond, ExecutionStepLimit(2), HostCallLimit(1),
      GasCycleLimit(1000))
  assert done.error == HostExecutionError.None and done.value.exit == StepExit.Halt
  assert uint64(done.value.machine.machineInfo.value.registers[7]) == 29
  owner
let detached = hosted()
assert uint64(detached.count) == 1 and array[4104, byte](detached.segment(ExportCount(0)))[0] == 1
# Fresh roots, immutable forks and refused successor allocations retire on every ARC cycle.
proc cycle() =
  ## Each iteration owns distinct segment payloads and metadata, including a successful branch and local refusal.
  let root = captureRefinementExports(ExportOffset(0))
  let one = run(root, registers(), memory).value.exports
  let two = run(one, registers(4104), memory).value.exports
  assert uint64(two.count) == 2 and uint64(one.count) == 1
  assert run(two, registers(), memory, cap = limits(2)).error == RefinementExportError.LimitExceeded
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_refinement_export", 1000, before, after)
echo "PVM refinement export passed"
echo "ARC_RELEASE cycles=1000 unchanged"
