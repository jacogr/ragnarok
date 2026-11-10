# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## ARM64 and x86-64 use their checked read emitters for the first eleven operations.
## Neither auxiliary lowering writes guest memory or owns the suffix or branch. The shared
## bridge stages the store operands and scalar suffix, then the frame validates and commits.
## Reads outside the clipped contiguous extents and first writes stay with checked workers.

import std/assertions
import ../[machine, program]
import ./[native_platform, native_read_body, native_ir, register_ops]

when defined(pvmAuxLoop) and NativeCheckedReadEnabled:
  const
    AuxVisitSpan* = 15'u64
    AuxMaxVisits* = 256 ## Release exclusive mapping access after a finite number of visits.
    AuxOps* = [152'u8, 210, 58, 139, 212, 58, 200, 124, 200, 124, 149, 120, 190, 100, 171]

  type
    AuxProof* = object
      ## Copied source authority. Only the frame can relate it to a live stream and price.
      read*: NativeReadBody
      price*: uint64
      exitHeader*: uint32
      store*: NativeOperation
      suffix*: array[2, NativeOperation]
      branch*: RegisterSlots
    AuxStage* = object
      ## One visit's proposed effects. A rejected extent leaves the frame untouched.
      registers*: RegisterFile
      address*, value*: uint64
      next*: uint32

  proc stageAuxVisit*(image: NativeImage, proof: AuxProof, incoming: RegisterFile,
      context: var NativeReadContext, stage: var AuxStage): bool =
    ## The read image sees only scratch registers and current read-only borrows. Derive the
    ## store from the pre-suffix state even when the scalar suffix overwrites either lane.
    stage.registers = incoming
    if not enterNativeReadBody(image, stage.registers, context): return false
    let slots = proof.store.slots
    stage.address = (uint64(stage.registers[slots.bIndex])+proof.store.immediate) and 0xffffffff'u64
    stage.value = uint64(stage.registers[slots.aIndex]) and 255'u64
    var destination: range[0..12] = 0
    var value = RegisterValue(0)
    let first = proof.suffix[0]
    let second = proof.suffix[1]
    assert first.opcode == 190 and second.opcode == 100
    if not computeRegisterOperands(first.slots, first.immediate, first.opcode,
        stage.registers, destination, value, 190): abortNativeReceipt()
    stage.registers[destination] = value
    if not computeRegisterOperands(second.slots, second.immediate, second.opcode,
        stage.registers, destination, value, 100): abortNativeReceipt()
    stage.registers[destination] = value
    stage.next = if stage.registers[proof.branch.aIndex] != stage.registers[proof.branch.bIndex]:
      proof.read.info.header else: proof.exitHeader
    true
