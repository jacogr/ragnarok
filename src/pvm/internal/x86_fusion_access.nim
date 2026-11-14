# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Included private x86 fusion operand policy. One allocation spans the entire linked graph:
## the six lanes with most static operand references occupy saved SysV GPRs, and the remaining used lanes occupy
## XMM0..XMM6. SSE2 is part of the x86-64 baseline; no CPU feature probe is required.
## Scalar and memory emitters keep their original scratch registers. R9/R11 retain gas/quota,
## XMM7 retains the visit count, and every checked exit publishes the written guest lanes.

when declared(X86Block):
  type X86FusionAccess* = object
    ## Zero SIMD bytes defer to the existing GPR/canonical policy; other bytes encode XMM index+1.
    bank: X86ResidentAccess
    simd: array[13, uint8]
    written: uint32

  func scoreX86FusionOperation(uses: var array[13, uint16], written: var uint32,
      op: NativeOperation) =
    ## Count the original operands, including memory bases and aliases, without executing guest work.
    let encoding = nativeReadEncodingOpcode(op.opcode)
    if nativeMixedLoopStoreWidth(op.opcode) != 0:
      # Stores consume their value and, for relative forms, their current address base.
      inc uses[op.slots.aIndex]
      if op.opcode >= 120: inc uses[op.slots.bIndex]
    else:
      let destination = if nativeReadOpcode(encoding): op.slots.aIndex
        else: op.slots.destinationIndex
      inc uses[destination]
      written = written or (1'u32 shl int(destination))
      if nativeReadOpcode(encoding):
        # Absolute reads have no guest address operand.
        if encoding == op.opcode: inc uses[op.slots.bIndex]
      elif op.opcode in [20'u8, 51]:
        discard # Literal assignments have no guest input.
      elif op.opcode in {100'u8..110}:
        inc uses[op.slots.aIndex]
      elif op.opcode < 190:
        inc uses[op.slots.bIndex]
      else:
        inc uses[op.slots.aIndex]
        inc uses[op.slots.bIndex]

  func x86FusionAccess*(blocks: openArray[NativeFusionBlock]): X86FusionAccess =
    ## Share one bounded allocation across every external entry and internal edge.
    ## Empty or oversized inputs produce the empty policy. Invalid blocks do not influence
    ## allocation and are independently rejected by the encoder.
    result = default(X86FusionAccess)
    if blocks.len == 0 or blocks.len > NativeFusionBlockLimit: return
    var uses = default(array[13, uint16])
    for item in blocks:
      if not item.complete: continue
      for index in 0..<int(item.terminal-item.header)-1:
        scoreX86FusionOperation(uses, result.written, item.operations[index])
      if item.targets[0] == NativeEntryFailure: continue
      let branch = item.branch
      if branch.opcode == 80:
        # The linked load-and-jump writes its lane before entering its successor.
        inc uses[branch.slots.aIndex]
        result.written = result.written or (1'u32 shl int(branch.slots.aIndex))
      elif item.targets[1] != NativeEntryFailure:
        inc uses[branch.slots.aIndex]
        if branch.opcode > 90: inc uses[branch.slots.bIndex]
    var mask = 0'u32
    for position in 0..<X86ResidentHardware.len:
      # At most 255 blocks of 32 operations, each with three references, fit a uint16 score.
      var best = -1
      var score = 0'u16
      for slot in 0..12:
        if uses[slot] > score and (mask and (1'u32 shl slot)) == 0:
          best = slot
          score = uses[slot]
      if best < 0: break
      mask = mask or (1'u32 shl best)
    result.bank = x86ResidentAccess(mask)
    var next = 1'u8
    for slot in 0..12:
      # Only lanes that appear in a supported source block pay entry/exit work.
      if uses[slot] != 0 and result.bank.registers[slot] == 0:
        result.simd[slot] = next
        inc next

  proc readAccess(code: var X86Block, access: X86FusionAccess,
      slot: range[0..12], right: bool) =
    ## Consume old lane values into RAX/RCX before an aliased destination changes.
    let encoded = access.simd[slot]
    if encoded == 0:
      readAccess(code, access.bank, slot, right)
    else:
      put(code, [0x66'u8, 0x48, 0x0f, 0x7e,
        byte(0xc0 or ((int(encoded)-1) shl 3) or (if right: 1 else: 0))]) # MOVQ RAX/RCX,XMMn.

  proc writeAccess(code: var X86Block, access: X86FusionAccess, slot: range[0..12]) =
    ## Update only the original destination; other resident lanes and budgets stay live.
    let encoded = access.simd[slot]
    if encoded == 0:
      writeAccess(code, access.bank, slot)
    else:
      put(code, [0x66'u8, 0x48, 0x0f, 0x6e,
        byte(0xc0 or ((int(encoded)-1) shl 3))]) # MOVQ XMMn,RAX.

  proc readBodyBase(code: var X86Block, access: X86FusionAccess, slot: range[0..12]) =
    ## Address formation consumes the current low word and keeps the original modulo-2^32 addition.
    let encoded = access.simd[slot]
    if encoded == 0:
      readBodyBase(code, access.bank, slot)
    else:
      put(code, [0x66'u8, 0x0f, 0x7e,
        byte(0xc2 or ((int(encoded)-1) shl 3))]) # MOVD EDX,XMMn.

  proc beginX86Fusion(code: var X86Block, access: X86FusionAccess) =
    ## Save each selected SysV register once and initialize all used lanes, including write-only
    ## lanes whose original value must survive an unpaid or earlier paid exit.
    for slot in 0..12:
      let encoded = access.bank.registers[slot]
      if encoded != 0:
        saveX86ResidentRegister(code, encoded-1)
        loadX86ResidentRegister(code, access.bank, slot)
      elif access.simd[slot] != 0:
        put(code, [0xf3'u8, 0x0f, 0x7e,
          byte(0x47 or ((int(access.simd[slot])-1) shl 3)), byte(slot*8)]) # MOVQ XMMn,[RDI+slot*8].

  proc endX86Fusion(code: var X86Block, access: X86FusionAccess) =
    ## Publish every potentially written lane and restore host GPRs without disturbing EAX's
    ## checked continuation. SSE registers are caller-saved in the supported SysV ABI.
    commitX86ResidentRegisters(code, access.bank, access.written)
    for slot in 0..12:
      if access.simd[slot] != 0 and (access.written and (1'u32 shl slot)) != 0:
        put(code, [0x66'u8, 0x0f, 0xd6,
          byte(0x47 or ((int(access.simd[slot])-1) shl 3)), byte(slot*8)]) # MOVQ [RDI+slot*8],XMMn.
    restoreX86ResidentRegisters(code, access.bank)
