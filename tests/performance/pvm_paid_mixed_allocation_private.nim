# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Recoverable allocation refusal and retry for the production paid mixed-loop lowerers.

import std/[assertions, syncio]
import ../../src/pvm/program
import ../../src/pvm/internal/[native_ir, native_mixed_loop, native_platform]

proc operation(opcode, lanes: byte, operand: uint32 = 0): NativeOperation =
  ## Bind register roles through the real decoder before constructing copied test IR.
  let wire = [0'u8, 0, 7, opcode, lanes, byte(operand and 255), byte((operand shr 8) and 255),
    byte((operand shr 16) and 255), byte(operand shr 24), 0, 0x41]
  let owner = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
  assert owner.error == ProgramError.None
  let decoded = instruction(owner.value, CodeAddress(0))
  assert decoded.error == ProgramError.None
  NativeOperation(opcode: opcode, slots: instructionRegisters(decoded),
    immediate: uint64(decoded.value.x))

proc paidProof(): NativeMixedLoop =
  ## Decode the register roles in a valid paid loop with two differently sized relative stores.
  result = NativeMixedLoop(header: 100, first: 100, terminal: 105, exitHeader: 106,
    price: 10, epoch: 1, span: 5, count: 5)
  let operations = [operation(124, 0x61), operation(121, 0x50), operation(130, 0x62),
    operation(123, 0x52, 16), operation(171, 0xc5)]
  for index, item in operations: result.operations[index] = item
  result.paidGuards = nativeMixedLoopPaidGuards(result)
  assert result.paidGuards == 15 and result.complete

var allocationRefusals {.threadvar.}: int

proc observeAllocationRefusal(size: int) =
  ## Use the allocator's own callback so a prior refusal cannot qualify a later case.
  if size > 0: inc allocationRefusals

block paid_lowering_allocation_refusal:
  # The widened mixed body must refuse under the real recoverable allocator cap.
  # Keep admission outside the capped operation, then retry with the same proof.
  let proof = paidProof()
  setOomHandler(observeAllocationRefusal)
  const heapLimit = 1024*1024 # The qualification runs with nimMaxHeap=1.
  for headroom in [768, 1600]:
    # Page rounding of a large allocation can consume the whole cap. Leave
    # slack first, then approach the requested headroom using small allocations.
    let filler = alloc(heapLimit-getOccupiedMem()-131072)
    assert filler != nil, "initial heap pressure"
    var padding = default(array[1024, nil pointer])
    var used = 0
    while heapLimit-getOccupiedMem() > headroom:
      assert used < padding.len, "bounded heap pressure"
      let remaining = heapLimit-getOccupiedMem()-headroom
      padding[used] = alloc(if remaining > 512: 256 else: 16)
      assert padding[used] != nil, "padding allocation"
      inc used
    let occupied = getOccupiedMem()
    assert heapLimit-occupied >= headroom-64 and heapLimit-occupied <= headroom
    allocationRefusals = 0
    var refused = false
    var image = lowerNativeMixedLoop(proof, refused)
    assert getOccupiedMem() == occupied, "partial staging leaked"
    for index in 0..<used: dealloc(padding[index])
    dealloc(filler)
    assert allocationRefusals > 0, "actual allocator refusal"
    assert refused and not image.ready and image.codeBytes == 0, "incomplete image published"
    assert nativeMixedLoopEntries(image) == 0
  allocationRefusals = 0
  var refused = false
  var image = lowerNativeMixedLoop(proof, refused)
  assert allocationRefusals == 0
  assert image.ready and not refused and nativeMixedLoopEntries(image) == 1
  echo "MIXED_PAID_ALLOCATION_REFUSAL_OK"
